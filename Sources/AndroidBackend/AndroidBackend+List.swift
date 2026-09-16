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
    func setLazy(_ id: Int32, _ count: Int32, _ estimatedHeight: Int32)
}

/// The Swift side of `CustomListAdapter`'s two native methods.
///
/// **A side table keyed by an id, because a JNI native method has no captured
/// state.** `swiftViewForRow` arrives with its arguments and nothing else --
/// there is no `self` carrying a closure -- so the adapter is given a number
/// when its rows go lazy and hands that number back with every question.
/// `MainRunLoopTickler` uses the same `external fun` contract with no id,
/// because there is only ever one of it.
///
/// `CustomListAdapter` 那兩個 native method 的 Swift 側。
///
/// **以 id 為鍵的旁表，因為一個 JNI native method 沒有被捕捉的狀態。** `swiftViewForRow` 只帶著它的
/// 引數抵達，沒有別的——沒有任何 `self` 攜帶著一個 closure——因此當某個 adapter 的列轉為延遲建立時，
/// 它會拿到一個號碼，並在每次提問時把那個號碼帶回來。`MainRunLoopTickler` 用的是同一套 `external fun`
/// 契約而沒有 id，因為它從頭到尾只會有一個。
enum LazyListProviders {
    typealias Provider = (Int) -> (widget: AndroidKit.View, height: Int)?

    nonisolated(unsafe) private static var providers: [Int32: Provider] = [:]
    nonisolated(unsafe) private static var heights: [Int32: [Int: Int]] = [:]
    nonisolated(unsafe) private static var nextID: Int32 = 0

    static func register(_ provider: @escaping Provider, reusing id: Int32?) -> Int32 {
        let id = id ?? { nextID += 1; return nextID }()
        providers[id] = provider
        heights[id] = heights[id] ?? [:]
        return id
    }

    static func view(id: Int32, row: Int32) -> AndroidKit.View? {
        guard let provider = providers[id], let built = provider(Int(row)) else { return nil }
        heights[id, default: [:]][Int(row)] = built.height
        return built.widget
    }

    static func knownHeight(id: Int32, row: Int32) -> Int32 {
        Int32(heights[id]?[Int(row)] ?? 0)
    }
}

@JavaImplementation("dev.swiftcrossui.androidbackend.lists.CustomListAdapter")
extension CustomListAdapter {
    @JavaMethod
    func swiftViewForRow(_ id: Int32, _ position: Int32) -> AndroidKit.View? {
        LazyListProviders.view(id: id, row: position)
    }

    @JavaMethod
    func swiftKnownHeightForRow(_ id: Int32, _ position: Int32) -> Int32 {
        LazyListProviders.knownHeight(id: id, row: position)
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
    }

    public func baseItemPadding(ofSelectableListView listView: Widget) -> EdgeInsets {
        let density = listView.getResources().getDisplayMetrics().density

        let dividerHeightPx = listView.as(AndroidKit.ListView.self)!.getDividerHeight()

        // No longer truncated to an Int: a divider of 3px at density 2.75 is
        // 1.09 dp, and the old `Int(...)` reported 1, losing 8% of the divider
        // on every row. `EdgeInsets` is `Double` now, so the fraction survives
        // to the single rounding at the backend hand-off.
        // 不再截斷成 Int:密度 2.75 之下,3px 的分隔線是 1.09 dp,而舊的 `Int(...)`
        // 會回報 1,於是**每一列**都少掉這條分隔線的 8%。`EdgeInsets` 現在是 `Double`,
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
        let density = listView.getResources().getDisplayMetrics().density

        listView.as(AndroidKit.AdapterView.self)!
            .getAdapter()!
            .as(CustomListAdapter.self)!
            .setViews(items.map(Optional.some(_:)), rowHeights.map {
                Int32(Float($0) * density)
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
