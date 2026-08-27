/// A view the displays text.
///
/// ``Text`` truncates its content to fit within its proposed size. To wrap
/// without truncation, put the ``Text`` (or its enclosing view hierarchy) into
/// an ideal height context such as a ``ScrollView``. Alternatively, use
/// ``View/fixedSize(horizontal:vertical:)`` with `horizontal` set to false and
/// `vertical` set to true, but be aware that this may lead to unintuitive
/// minimum sizing behaviour when used within a window. Often when developers
/// use ``View/fixedSize()`` on text, what they really need is a ``ScrollView``.
///
/// To avoid wrapping and truncation entirely, use ``View/fixedSize()``.
///
/// ## Technical notes
///
/// The reason that ``Text`` truncates its content to fit its proposed size is
/// that SwiftCrossUI's layout system behaves rather unintuitively with views
/// that trade off width for height. The layout system used to support this
/// behaviour well, but when overhauling the layout system with performance in
/// mind, we discovered that it's not possible to handle minimum view sizing in
/// the intuitive way that we were, without a large performance cost or layout
/// system complexity cost.
///
/// With the current system, windows determine the minimum size of their content
/// by proposing a size of 0x0. A text view that doesn't truncate its content
/// would take on a width of 0 and then lay out each character on a new line (as
/// that's what most UI frameworks do when text is given a small width). This
/// leads to the window thinking that its minimum height is
/// `characterCount * lineHeight`, even though when given a width larger than
/// zero, the text view would be shorter than this 'minimum height'. The
/// underlying cause is the assumption that 'minimum size' is a sensible notion
/// for every view. A text view without truncation doesn't have a
/// 'minimum size'; are we minimizing width? height? width + height? area?
///
/// SwiftCrossUI's old layout system separated the concept of minimum size into
/// 'minimum width for current height', and 'minimum height for current width'.
/// This led to much more intuitive window sizing behaviour. If you had
/// non-truncating text inside a window, and resized the width of the window
/// such that the height of the text became taller than the window, then the
/// window would become taller, and if you resized the height of the window then
/// you'd reach the window's minimum height before the text could overflow the
/// window horizontally. Unfortunately this required a lot of book-keeping, and
/// was deemed to be unfeasible to do without significantly hurting performance
/// due to all the layout assumptions that we'd have to drop from our stack
/// layout algorithm.
///
/// The new layout system behaviour is in line with SwiftUI's layout behaviour.
public struct Text: Sendable {
    /// The string to be shown in the text view.
    var string: String

    /// Creates a new text view that displays a string.
    ///
    /// - Parameter string: The string to display.
    public init(_ string: String) {
        self.string = string
    }
}

extension Text: View {
    public var _asMenuItems: [MenuItem] {
        [.text(self)]
    }
}

extension Text: ElementaryView {
    public func asWidget<Backend: BaseAppBackend>(
        backend: Backend
    ) -> Backend.Widget {
        return backend.createTextView()
    }

    public func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        // TODO: Avoid this. Move it to commit once we figure out a solution for Gtk.
        // Even in dry runs we must update the underlying text view widget
        // because GtkBackend currently relies on querying the widget for text
        // properties and such (via Pango).
        backend.updateTextView(widget, content: string, environment: environment)

        // UI frameworks often handle the zero proposal specially. We want to
        // have standard text sizing behaviour so it's better for us to never
        // propose zero in either dimension and then fix up the resulting size
        // to match our expectations.
        //
        // Our desired behaviour is for a zero width proposal to result in at least
        // one line's worth of height (for a non-empty string). Furthermore, if
        // proposed more than one line's worth of height, then a zero width
        // proposal should result in height equivalent to however many lines are
        // required to put each character of the text on a new line (excluding
        // whitespace).
        //
        // A zero height proposal should result in the text using at least one
        // line of height (if non-empty).
        var size = backend.size(
            of: string,
            whenDisplayedIn: widget,
            proposedWidth: proposedSize.width.flatMap {
                // For text, an infinite proposal is the same as an unspecified
                // proposal, and this works nicer with most backends than converting
                // .infinity to a large integer (which is the alternative).
                $0 == .infinity ? nil : $0
            }.map(LayoutSystem.roundSize).map { max(1, $0) },
            proposedHeight: proposedSize.height.flatMap {
                $0 == .infinity ? nil : $0
            }.map(LayoutSystem.roundSize).map { max(1, $0) },
            environment: environment
        )

        // If the proposed width was 0 and the resuling width was 1, then set the
        // resulting width to 0. See above for more detail.
        if proposedSize.width == 0 && size.x == 1 {
            size.x = 0
        }

        // The line limit, applied here rather than in each backend.
        //
        // It was in all four: AppKit, UIKit and WinUI each had these same three
        // lines, and GtkBackend had a different implementation that was wrong.
        // It built a synthetic "a\na" string and measured it through a spare
        // label that was created and never added to a window -- and GTK resolves
        // style only for a widget with a root, which this backend had already
        // measured twice for other reasons. So the cap came out at GTK's default
        // font size whatever font was asked for.
        //
        // Measured 2026-08-27 with P22's two-font check: `.lineLimit(2)` on the
        // same paragraph reported 300x35 at 13pt and 300x35 at 30pt. Two lines of
        // 30pt text is not the height of two lines of 13pt text.
        //
        // The cap needs no widget and no measurement -- it is the line height
        // times the limit -- so a backend that reaches for a widget to compute it
        // has already gone wrong. Doing it once here is what stops a fifth
        // backend inventing a fifth version.
        //
        // 行數限制在此處套用，而非於每個 backend 各自處理。
        //
        // 先前四個 backend 都有：AppKit、UIKit 與 WinUI 各自有著相同的三行程式碼，而 GtkBackend
        // 的實作不同、且是錯的。它組出一個 "a\na" 的合成字串，並透過一個「建立後從未加入任何視窗」
        // 的備用 label 來量測——而 GTK 只會為具有 root 的 widget 解析樣式，這一點該 backend 早已
        // 因其他理由量測過兩次。於是無論被要求何種字型，該上限都以 GTK 的預設字級算出。
        //
        // 2026-08-27 以 P22 的雙字級檢查實測：同一段文字加上 `.lineLimit(2)`，13pt 回報 300x35、
        // 30pt 同樣回報 300x35。兩行 30pt 的文字不會等於兩行 13pt 文字的高度。
        //
        // 此上限不需要 widget、也不需要量測——它就是「行高 × 行數」——因此若某個 backend 為了計算
        // 它而去取用 widget，那時就已經走錯了。在此處做一次，正是為了阻止第五個 backend 發明第五
        // 種版本。
        if let lineLimitSettings = environment.lineLimitSettings {
            let limitedHeight =
                Double(max(lineLimitSettings.limit, 1)) * environment.resolvedFont.lineHeight
            if Double(size.y) > limitedHeight || lineLimitSettings.reservesSpace {
                size.y = LayoutSystem.roundSize(limitedHeight)
            }
        }

        return ViewLayoutResult.leafView(size: ViewSize(size))
    }

    public func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        backend.setSize(of: widget, to: layout.size.vector)
    }
}
