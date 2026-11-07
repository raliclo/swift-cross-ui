@_spi(Backends) import SwiftCrossUI
import AndroidKit
import SwiftJava

extension AndroidKit.ListView {
    @JavaMethod
    public func setSelector(_ sel: AndroidKit.Drawable?)
}

@JavaClass(
    "dev.swiftcrossui.androidbackend.lists.CustomListAdapter",
    extends: AndroidKit.BaseAdapter.self
)
class CustomListAdapter: AndroidKit.BaseAdapter {
    @JavaMethod
    @_nonoverride convenience init(
        environment: JNIEnvironment? = nil
    )

    @JavaMethod
    func setViews(_ newViews: [AndroidKit.View?], _ newHeights: [Int32])

    @JavaMethod
    func setEnabled(_ isEnabled: Bool)

    @JavaMethod
    func setLazy(_ rows: SwiftObject?, _ count: Int32, _ estimatedHeight: Int32)

    @JavaMethod
    func getLazyRows() -> SwiftObject?

    @JavaMethod
    func getRowRecycler() -> SwiftRowRecycler?

    @JavaMethod
    func setRowRecycler(_ recycler: SwiftRowRecycler?)
}

/// The Swift side of `CustomListAdapter`'s two native methods: one list's row
/// provider and the heights its rows came back with.
///
/// **Held by the adapter, boxed in a `SwiftObject`, not in a table keyed by an
/// id.** A JNI native method has no captured state, but these two are instance
/// methods, so each reads the source back from the adapter that is asking. The
/// source then lives exactly as long as its adapter, and a list that updates
/// replaces the provider in the box it already has. A table keyed by
/// `ObjectIdentifier` of the adapter's Swift wrapper did neither: the wrapper
/// is made per call, so every update added an entry that was never removed, and
/// the identity of a freed wrapper could be reused by another list's adapter.
///
/// `CustomListAdapter` 那兩個 native method 的 Swift 側：一份清單的列 provider,以及它的各列回報的高度。
///
/// **由 adapter 持有、裝在一個 `SwiftObject` 裡，而不是放在以 id 為鍵的表中。** JNI native method 沒有被捕捉的
/// 狀態，但這兩個是實例方法，所以各自從發問的那個 adapter 讀回來源。來源的壽命因此恰好等於它的 adapter,而一份更新中的
/// 清單是替換它已有的那個箱子裡的 provider。以 adapter 的 Swift 包裝物件之 `ObjectIdentifier` 為鍵的表兩者都做不到：
/// 包裝物件每次呼叫都新建，所以每次更新都多出一筆永不移除的紀錄，而被釋放之包裝物件的身分可能被另一份清單的 adapter 重複使用。
final class LazyListRowSource {
    typealias Provider = (Int) -> (widget: AndroidKit.View, height: Int)?

    var provider: Provider
    private var heights: [Int: Int] = [:]

    init(provider: @escaping Provider) {
        self.provider = provider
    }

    func view(row: Int32) -> AndroidKit.View? {
        guard let built = provider(Int(row)) else { return nil }
        heights[Int(row)] = built.height
        return built.widget
    }

    func knownHeight(row: Int32) -> Int32 {
        Int32(clamping: heights[Int(row)] ?? 0)
    }
}

extension CustomListAdapter {
    var lazyRowSource: LazyListRowSource? {
        getLazyRows()?.value() as? LazyListRowSource
    }
}

@JavaImplementation("dev.swiftcrossui.androidbackend.lists.CustomListAdapter")
extension CustomListAdapter {
    @JavaMethod
    func swiftViewForRow(_ position: Int32) -> AndroidKit.View? {
        lazyRowSource?.view(row: position)
    }

    @JavaMethod
    func swiftKnownHeightForRow(_ position: Int32) -> Int32 {
        lazyRowSource?.knownHeight(row: position) ?? 0
    }
}

@JavaClass(
    "dev.swiftcrossui.androidbackend.lists.ListItemSelectedListener",
    implements: AndroidKit.AdapterView.OnItemSelectedListener.self
)
class ListItemSelectedListener: JavaObject {
    @JavaMethod
    @_nonoverride convenience init(environment: JNIEnvironment? = nil)

    @JavaMethod
    func getSelectedPosition() -> Int32

    @JavaMethod
    func setAction(_ action: SwiftAction?)
}

// swiftlint:disable force_try

// implements BackendFeatures.SelectableListViews
extension AndroidBackend {
    /// Whether each list was last drawn as a sidebar. 每個清單上次是否畫成側邊欄。
    @MainActor static let listSidebarStates = LastSet<String>()

    public func createSelectableListView() -> Widget {
        let absListViewClass = try! JavaClass<AndroidKit.AbsListView>()

        let listView = AndroidKit.ListView(
            Self.activity,
            environment: Self.env
        )

        listView.setChoiceMode(absListViewClass.CHOICE_MODE_SINGLE)

        listView
            .setAdapter(CustomListAdapter(environment: Self.env).as(AndroidKit.ListAdapter.self))

        // One object, registered twice. Which of the two callbacks fires
        // depends on how the row was reached, and on a phone it is always the
        // click one -- see ListItemSelectedListener.
        // 同一個物件，註冊兩次。兩個 callback 中哪一個會被觸發，取決於該列是以何種方式被抵達的，
        // 而在手機上永遠是 click 那一個——見 ListItemSelectedListener。
        let listener = ListItemSelectedListener(environment: Self.env)
        listView
            .setOnItemSelectedListener(
                listener.as(AndroidKit.AdapterView.OnItemSelectedListener.self)
            )
        listView
            .setOnItemClickListener(
                listener.as(AndroidKit.AdapterView.OnItemClickListener.self)
            )

        // Color was derived experimentally on an Android 16 emulator to match
        // the default pressed color.
        listView.setSelector(AndroidKit.ColorDrawable(0x32a1a1a1))

        return listView
    }

    public func updateSelectableListView(
        _ selectableListView: Widget,
        environment: EnvironmentValues
    ) {
        selectableListView.as(AndroidKit.AdapterView.self)!
            .getAdapter()!
            .as(CustomListAdapter.self)!
            .setEnabled(environment.isEnabled)

        // `.sidebar` as a Material navigation drawer (`setListSidebar`). Only on
        // change: the call builds drawables and resolves theme attributes.
        // `.sidebar` 畫成 Material 的 navigation drawer(`setListSidebar`)。只在改變時呼叫：它會建立 drawable
        // 並解析主題屬性。
        let isSidebar = environment.backendListStyle == .sidebar
        // The scheme too: the sidebar panel is drawn in iOS's grouped background
        // for the window's scheme, not the system's. 深淺色也算在內：側邊欄面板以視窗的配色
        // (而非系統的)畫成 iOS 的 grouped 背景。
        let isDark = environment.colorScheme == .dark
        let sidebarState = "\(isSidebar)/\(isDark)"
        // Also on the first update (no state yet), so a default list gets its
        // background too. 第一次更新(尚無狀態)時也套用，讓預設清單也拿到背景。
        if Self.listSidebarStates.value(for: selectableListView) != sidebarState {
            helpers.setListSidebar(selectableListView.as(AndroidKit.ListView.self), isSidebar, isDark)
            Self.listSidebarStates.set(sidebarState, for: selectableListView)
        }
    }

    public func baseItemPadding(ofSelectableListView listView: Widget) -> EdgeInsets {
        let density = AndroidBackend.density { listView.getResources().getDisplayMetrics().density }

        let dividerHeightPx = listView.as(AndroidKit.ListView.self)!.getDividerHeight()

        // Not truncated to an Int: a divider of 3px at density 2.75 is
        // 1.09 dp, and `Int(...)` would report 1, losing 8% of the divider
        // on every row. `EdgeInsets` is `Double`, so the fraction survives
        // to the single rounding at the backend hand-off.
        // 不截斷成 Int:密度 2.75 之下,3px 的分隔線是 1.09 dp,而 `Int(...)`
        // 會回報 1,於是**每一列**都少掉這條分隔線的 8%。`EdgeInsets` 是 `Double`,
        // 因此那個分數會一路存活到「交給 backend 時的那唯一一次取整」。
        return EdgeInsets(bottom: Double(Float(dividerHeightPx) / density))
    }

    public func minimumRowSize(ofSelectableListView listView: Widget) -> SIMD2<Int> {
        .zero
    }

    public func setItems(
        ofSelectableListView listView: Widget,
        to items: [Widget],
        withRowHeights rowHeights: [Int]
    ) {
        let density = AndroidBackend.density { listView.getResources().getDisplayMetrics().density }

        listView.as(AndroidKit.AdapterView.self)!
            .getAdapter()!
            .as(CustomListAdapter.self)!
            .setViews(items.map(Optional.some(_:)), rowHeights.map {
                Self.layoutLength($0, density: density)
            })
    }

    public func setSelectionHandler(
        forSelectableListView listView: Widget,
        to action: @escaping (_ selectedIndex: Int) -> Void
    ) {
        let listener = listView.as(AndroidKit.ListView.self)!
            .getOnItemSelectedListener()!
            .as(ListItemSelectedListener.self)!

        listener.setAction(
            SwiftAction(environment: Self.env) {
                action(Int(listener.getSelectedPosition()))
            }
        )
    }

    public func setSelectedItem(
        ofSelectableListView listView: Widget,
        toItemAt index: Int?
    ) {
        // `setItemChecked`, not `setSelection`. The list is in
        // `CHOICE_MODE_SINGLE`, and in touch mode "selection" does not exist --
        // `setSelection` is accepted and draws nothing. Checking is the state a
        // touchscreen list actually carries.
        // 使用 `setItemChecked`，而非 `setSelection`。此清單處於 `CHOICE_MODE_SINGLE`，而在 touch
        // mode 下「selection」並不存在——`setSelection` 會被接受，但不會畫出任何東西。checked 才是
        // 觸控清單真正持有的狀態。
        let listView = listView.as(AndroidKit.ListView.self)!
        if let index {
            listView.setItemChecked(Int32(index), true)
        } else {
            listView.clearChoices()
        }
    }
}
// swiftlint:enable force_try
