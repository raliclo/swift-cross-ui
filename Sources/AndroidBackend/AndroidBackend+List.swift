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
