/// A labelled column with a view for each row in a table.
public struct TableColumn<RowValue, Content: View> {
    /// The label displayed at the top of the column (also known as the column title).
    public var label: String
    /// The content displayed for this column of each row of the table.
    public var content: (RowValue) -> Content
    /// A fixed width in points, or nil to share the table's width evenly with
    /// the other unsized columns.
    ///
    /// **nil is not "no opinion", it is the CURRENT behaviour made explicit.**
    /// Before this existed, ``Table/computeLayout`` gave every column
    /// `proposedWidth / columnCount` -- a flat average with no way to say
    /// otherwise, so a column of dates and a column of one-word names got the
    /// same space. A nil column still gets an even share; the difference is
    /// that it now shares what the sized columns left behind.
    ///
    /// 固定寬度(單位為 point);nil 表示與其他未指定寬度的欄平均分配表格寬度。
    ///
    /// **nil 不是「沒有意見」,而是把既有行為明說出來。** 在此之前,``Table/computeLayout`` 給每一欄
    /// 的都是 `proposedWidth / columnCount` ——一個沒有辦法改變的平均值,因此一欄日期與一欄單字姓名
    /// 得到相同的空間。nil 的欄位現在仍然平分,差別在於**它平分的是那些已指定寬度的欄所剩下的部分**。
    public var width: Double?
}

extension TableColumn {
    /// Sets this column's width.
    ///
    /// A method rather than an initialiser parameter because that is SwiftUI's
    /// shape -- `TableColumn("Name", value: \.name).width(120)` -- and because
    /// it keeps the two existing initialisers unchanged.
    ///
    /// 設定此欄的寬度。
    ///
    /// 採用方法而非建構式參數,因為那是 SwiftUI 的形狀
    /// (`TableColumn("Name", value: \.name).width(120)`),也因為這讓既有的兩個建構式維持不變。
    public func width(_ width: Double?) -> Self {
        var column = self
        column.width = width
        return column
    }
}

extension TableColumn {
    /// Creates a column.
    ///
    /// - Parameters:
    ///   - label: The label displayed at the top of the column (also known as
    ///     the column title).
    ///   - content: The content displayed for this column of each row of the
    ///     table.
    public init(_ label: String, @ViewBuilder content: @escaping (RowValue) -> Content) {
        self.label = label
        self.content = content
    }
}

extension TableColumn where Content == Text {
    /// Creates a column with that displays a string property and has a text
    /// label.
    ///
    /// - Parameters:
    ///   - label: The label displayed at the top of the column (also known as
    ///     the column title).
    ///   - keyPath: A key path to the string value to display.
    public init(_ label: String, value keyPath: KeyPath<RowValue, String>) {
        self.label = label
        self.content = { row in
            Text(row[keyPath: keyPath])
        }
    }
}
