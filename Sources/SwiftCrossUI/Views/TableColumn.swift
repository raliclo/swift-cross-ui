/// A labelled column with a view for each row in a table.
public struct TableColumn<RowValue, Content: View> {
    /// The label displayed at the top of the column (also known as the column title).
    public var label: String
    /// The content displayed for this column of each row of the table.
    public var content: (RowValue) -> Content
    /// A fixed width in points, or nil to share the table's width evenly with
    /// the other unsized columns.
    ///
    /// **nil is an even share, not "no opinion".** A nil column shares what the
    /// sized columns leave behind; with every column nil that is the flat
    /// `proposedWidth / columnCount`.
    ///
    /// 固定寬度(單位為 point);nil 表示與其他未指定寬度的欄平均分配表格寬度。
    ///
    /// **nil 是平分,不是「沒有意見」。** nil 的欄位平分的是那些已指定寬度的欄所剩下的部分;若所有欄都是 nil,
    /// 就與單純的 `proposedWidth / columnCount` 相同。
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
