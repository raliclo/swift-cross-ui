/// The description of a single column in a ``LazyVGrid``.
///
/// A value type only -- it renders nothing itself and needs nothing from any
/// backend. ``LazyVGrid`` turns each item into a ``View/frame(width:height:alignment:)``
/// or ``View/frame(minWidth:idealWidth:maxWidth:minHeight:idealHeight:maxHeight:alignment:)``
/// around the cells of that column.
///
/// The spelling matches SwiftUI's, down to the default arguments, so that
/// `GridItem(.adaptive(minimum: 80))` and
/// `Array(repeating: GridItem(.flexible()), count: 3)` compile unchanged. Two
/// deliberate substitutions, both to match what this project already uses
/// elsewhere: sizes are `Double` rather than `CGFloat` (there is no CoreGraphics
/// on four of the five backends), and `spacing` is `Int?` rather than `CGFloat?`
/// because ``VStack`` and ``HStack`` take `Int?`.
///
/// **``Size/adaptive(minimum:maximum:)`` does not adapt.** In SwiftUI it changes
/// the *number* of columns to fit the available width, which means deciding the
/// column count during layout, from a width this type never sees. Here it is
/// accepted, and treated as ``Size/flexible(minimum:maximum:)`` -- one column,
/// sized between the same two bounds. So a grid built from one adaptive item has
/// exactly one column rather than as many as fit. That is stated because the two
/// look identical in source and differ entirely on screen, and because silently
/// accepting the case would be the worse of the two options: refusing to compile
/// `adaptive` would reject correct SwiftUI for a difference in one axis.
///
/// ``LazyVGrid`` 中單一欄的描述。
///
/// 純粹是個值型別——它自身不繪製任何東西，也不需要任何 backend 支援。``LazyVGrid`` 會把每個 item
/// 轉換成套在該欄各儲存格外的
/// ``View/frame(width:height:alignment:)`` 或
/// ``View/frame(minWidth:idealWidth:maxWidth:minHeight:idealHeight:maxHeight:alignment:)``。
///
/// 其拼寫與 SwiftUI 一致，連預設引數都相同，因此 `GridItem(.adaptive(minimum: 80))` 與
/// `Array(repeating: GridItem(.flexible()), count: 3)` 都可以原封不動地編譯。有兩項刻意的替換，
/// 皆為配合本專案他處既有的用法：尺寸使用 `Double` 而非 `CGFloat`（五個 backend 中有四個沒有
/// CoreGraphics），而 `spacing` 使用 `Int?` 而非 `CGFloat?`，因為 ``VStack`` 與 ``HStack`` 接受的
/// 就是 `Int?`。
///
/// **``Size/adaptive(minimum:maximum:)`` 並不會自適應。** 在 SwiftUI 中，它會改變**欄的數量**以填滿
/// 可用寬度，也就是必須在版面計算期間、依據一個本型別永遠看不到的寬度來決定欄數。此處它會被接受，
/// 並比照 ``Size/flexible(minimum:maximum:)`` 處理——單一欄，尺寸落在同樣的兩個界限之間。因此由一個
/// adaptive item 建構出的網格恰好只有一欄，而不是「能塞下幾欄就幾欄」。之所以載明這點，是因為兩者
/// 在原始碼中看起來完全相同、在畫面上卻截然不同；也因為在兩個選項之中，靜默接受此 case 才是較好的
/// 那一個：拒絕編譯 `adaptive` 等於為了單一軸向上的差異而否決正確的 SwiftUI 程式碼。
public struct GridItem: Sendable {
    /// How wide the column is.
    /// 該欄有多寬。
    public enum Size: Sendable {
        /// Exactly this wide, regardless of the content or the space available.
        /// 就是這麼寬，與內容及可用空間皆無關。
        case fixed(Double)

        /// Between `minimum` and `maximum` wide, sharing the space with the
        /// other flexible columns.
        /// 寬度介於 `minimum` 與 `maximum` 之間，並與其他 flexible 欄分享空間。
        case flexible(minimum: Double = 10, maximum: Double = .infinity)

        /// In SwiftUI, as many columns of at least `minimum` as fit. Here, one
        /// column behaving as ``flexible(minimum:maximum:)`` -- see the note on
        /// ``GridItem`` itself.
        /// 在 SwiftUI 中是「能塞下幾個至少 `minimum` 寬的欄就有幾欄」。此處則是一欄，行為等同
        /// ``flexible(minimum:maximum:)``——見 ``GridItem`` 本身的說明。
        case adaptive(minimum: Double, maximum: Double = .infinity)
    }

    /// The column's width behaviour.
    /// 該欄的寬度行為。
    public var size: Size

    /// The spacing to the NEXT column. `nil` takes the grid's own spacing.
    ///
    /// "To the next column" rather than "around this column" is SwiftUI's
    /// meaning, and it is worth naming: the last item's spacing is therefore
    /// unused rather than adding a trailing gap.
    ///
    /// 與**下一欄**之間的間距。`nil` 表示採用網格自身的間距。
    ///
    /// SwiftUI 的語意是「與下一欄之間」而非「本欄兩側」，這點值得指明：因此最後一個 item 的 spacing
    /// 不會被使用，而不是在尾端多加一段空隙。
    public var spacing: Int?

    /// How a cell sits inside this column's width. `nil` centres it.
    /// 儲存格如何置於該欄寬度之中。`nil` 表示置中。
    public var alignment: Alignment?

    /// Creates a column description.
    ///
    /// - Parameters:
    ///   - size: The column's width behaviour.
    ///   - spacing: The spacing to the next column.
    ///   - alignment: How a cell sits inside this column's width.
    public init(
        _ size: Size = .flexible(),
        spacing: Int? = nil,
        alignment: Alignment? = nil
    ) {
        self.size = size
        self.spacing = spacing
        self.alignment = alignment
    }
}

extension GridItem {
    /// Wraps a cell in the frame this column asks for.
    ///
    /// Returns ``AnyView`` because the two `frame` overloads produce different
    /// types and a column may be described by either. The cells are already
    /// erased by ``gridCells(of:)`` at this point, so this adds no erasure that
    /// was not there anyway.
    ///
    /// 把儲存格包進本欄所要求的 frame 之中。
    ///
    /// 回傳 ``AnyView``，因為那兩個 `frame` 多載產生的型別不同，而一欄可能由其中任一者描述。此時
    /// 儲存格早已被 ``gridCells(of:)`` 抹除型別，因此這裡並未增加任何原本就不存在的抹除。
    @MainActor
    func sizing(_ cell: AnyView) -> AnyView {
        switch size {
            case .fixed(let width):
                AnyView(cell.frame(width: width, alignment: alignment ?? .center))
            case .flexible(let minimum, let maximum),
                .adaptive(let minimum, let maximum):
                AnyView(
                    cell.frame(
                        minWidth: minimum,
                        maxWidth: maximum,
                        alignment: alignment ?? .center
                    )
                )
        }
    }
}
