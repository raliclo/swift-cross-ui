import Gtk
@_spi(Backends) import SwiftCrossUI

extension GtkBackend: BackendFeatures.LazyListRowLifetimes {
    public func setLazyRowReleaseHandler(
        ofSelectableListView listView: Widget,
        to handler: @escaping (Int) -> Void
    ) {
        lazyList(of: listView).onRowReleased = handler
    }

    public func setLazyRows(
        ofSelectableListView listView: Widget,
        count: Int,
        estimatedRowHeight: Int,
        provider: @escaping (Int) -> (widget: Widget, height: Int)?
    ) {
        let list = lazyList(of: listView)
        list.rowProvider = { index in
            guard let row = provider(index) else { return nil }
            let request = row.widget.getSizeRequest()
            row.widget.setSizeRequest(width: request.width, height: row.height)
            return row.widget
        }
        list.setRowCount(count)
        list.refreshBoundRows()
    }
}
