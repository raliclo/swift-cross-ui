@_spi(Backends) import SwiftCrossUI
import UIKit

extension UIKitBackend {
    public func createSelectableListView() -> Widget {
        let listView = UICustomTableView()
        listView.delegate = listView.customDelegate
        listView.dataSource = listView.customDelegate

        listView.customDelegate.allowSelections = true
        listView.backgroundColor = .clear

        return WrapperWidget(child: listView)
    }

    public func updateSelectableListView(
        _ selectableListView: Widget,
        environment: EnvironmentValues
    ) {
        let listView = (selectableListView as! WrapperWidget<UICustomTableView>).child
        listView.customDelegate.allowSelections = environment.isEnabled
    }

    public func baseItemPadding(
        ofSelectableListView listView: Widget
    ) -> SwiftCrossUI.EdgeInsets {
        // TODO: Figure out if there's a way to compute this more directly. At
        //   the moment these are just figures from empirical observations.
        SwiftCrossUI.EdgeInsets(top: 0, bottom: 0, leading: 0, trailing: 0)
    }

    public func minimumRowSize(ofSelectableListView listView: Widget) -> SIMD2<Int> {
        .zero
    }

    public func setItems(
        ofSelectableListView listView: Widget,
        to items: [Widget],
        withRowHeights rowHeights: [Int]
    ) {
        let listView = (listView as! WrapperWidget<UICustomTableView>).child
        listView.customDelegate.rowCount = items.count
        listView.customDelegate.widgets = items
        listView.customDelegate.rowHeights = rowHeights
        listView.reloadData()
    }

    public func setSelectionHandler(
        forSelectableListView listView: Widget,
        to action: @escaping (_ selectedIndex: Int) -> Void
    ) {
        let listView = (listView as! WrapperWidget<UICustomTableView>).child
        listView.customDelegate.selectionHandler = action
    }

    public func setSelectedItem(ofSelectableListView listView: Widget, toItemAt index: Int?) {
        let listView = (listView as! WrapperWidget<UICustomTableView>).child
        if let index {
            listView.selectRow(
                at: IndexPath(indexes: [0, index]),
                animated: false,
                scrollPosition: .none
            )
        } else {
            listView.selectRow(at: nil, animated: false, scrollPosition: .none)
        }
    }
}

class UICustomTableViewDelegate: NSObject, UITableViewDelegate, UITableViewDataSource {
    var widgets: [UIKitBackend.Widget] = []
    var rowHeights: [Int] = []

    /// Set instead of `widgets` when the framework hands rows over one at a
    /// time. See ``SwiftCrossUI/BackendFeatures/LazyListRows``.
    /// 當框架改為一次交出一列時，設定的是這個而不是 `widgets`。
    var lazyProvider: ((Int) -> (widget: UIKitBackend.Widget, height: Int)?)?
    var estimatedRowHeight = 0
    var knownRowHeights: [Int: Int] = [:]
    var rowCount = 0
    var allowSelections = false
    var selectionHandler: ((Int) -> Void)?

    // MARK: UITableViewDataSource

    func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
        return rowCount
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt path: IndexPath
    ) -> UITableViewCell {
        let cell = UITableViewCell()
        if let lazyProvider {
            guard let built = lazyProvider(path.row) else { return cell }
            if knownRowHeights[path.row] != built.height {
                knownRowHeights[path.row] = built.height
                // UIKit has no `noteHeightOfRows`; the height is re-read on the
                // next layout pass, and the row is already being laid out now.
                // Recording it is enough, and asking for a reload from inside
                // `cellForRowAt` is how a table ends up in an infinite layout.
                // UIKit 沒有 `noteHeightOfRows`;高度會在下一次版面計算時重新讀取，而這一列此刻本來就
                // 正在被排版。記下來就夠了——而在 `cellForRowAt` 之內要求 reload，正是一個表格陷入
                // 無窮版面計算的方式。
            }
            cell.contentView.addSubview(built.widget.view)
            return cell
        }
        cell.contentView.addSubview(widgets[path.row].view)
        return cell
    }

    func numberOfSections(in table: UITableView) -> Int {
        return 1
    }

    // MARK: UITableViewDelegate

    func tableView(_ tableView: UITableView, heightForRowAt path: IndexPath) -> CGFloat {
        // The provider is not called here. See the AppKit half: answering a
        // height question by building the row builds the whole list at the first
        // layout, which is the thing being avoided.
        // 此處不呼叫 provider。見 AppKit 那一半:靠建立該列來回答高度問題，會在第一次版面計算時就把
        // 整份清單建出來——正是本項所要避免的事。
        if lazyProvider != nil {
            return CGFloat(knownRowHeights[path.row] ?? estimatedRowHeight)
        }
        return CGFloat(rowHeights[path.row])
    }

    func tableView(
        _ tableView: UITableView,
        willSelectRowAt path: IndexPath
    ) -> IndexPath? {
        if allowSelections {
            selectionHandler?(path.row)
            return path
        } else {
            return nil
        }
    }
}

class UICustomTableView: UITableView {
    var customDelegate = UICustomTableViewDelegate()
}
