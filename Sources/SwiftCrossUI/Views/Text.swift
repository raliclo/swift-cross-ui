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
    public private(set) var string: String

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

    /// Lays the text out, shrinking it towards ``View/minimumScaleFactor(_:)`` when it
    /// does not fit: taller than the proposed height or the ``View/lineLimit(_:reservesSpace:)``
    /// lines, or wider than the proposed width. The largest scale that fits is found by
    /// bisection, measuring through the backend, and the text is then laid out (and its
    /// widget updated) at that scale, so every backend shrinks it the same way. A zero
    /// width is a probe for the minimum size and is never shrunk for.
    ///
    /// 排版文字；放不下時(比提議的高度或 ``View/lineLimit(_:reservesSpace:)`` 的行數高，或比提議的寬度寬)
    /// 朝 ``View/minimumScaleFactor(_:)`` 縮小。以二分法透過 backend 量測找出放得下的最大倍率，再以該倍率排版
    /// (並更新其 widget),因此每個 backend 縮小的方式都相同。寬度為零是在探測最小尺寸，不會因此縮小。
    public func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        let factor = min(max(environment.minimumScaleFactor, 0.01), 1)
        let width = proposedSize.width.flatMap { $0 == .infinity ? nil : $0 }
        guard factor < 1, width != 0, Self.heightLimit(proposedSize, environment) != nil || width != nil
        else {
            return layoutText(widget, proposedSize: proposedSize, environment: environment, backend: backend)
        }
        let proposedWidth = width.map(LayoutSystem.roundSize).map { max(1, $0) }
        func scaled(_ scale: Double) -> EnvironmentValues {
            environment.with(\.textScale, environment.textScale * scale)
        }
        func fits(_ scale: Double) -> Bool {
            let scaledEnvironment = scaled(scale)
            // Measured without the line limit: a backend that applies it reports the
            // limited height, which always fits. / 量測時不套用行數限制：會套用它的 backend 回報的是
            // 限制後的高度，永遠放得下。
            let measuring = scaledEnvironment.with(\.lineLimitSettings, nil)
            let text = measuring.applyingTextTransforms(to: string)
            backend.updateTextView(widget, content: text, environment: measuring)
            let size = backend.size(
                of: text,
                whenDisplayedIn: widget,
                proposedWidth: proposedWidth,
                proposedHeight: nil,
                environment: measuring
            )
            if let proposedWidth, size.x > proposedWidth {
                return false
            }
            if let limit = Self.heightLimit(proposedSize, scaledEnvironment), Double(size.y) > limit + 0.5 {
                return false
            }
            return true
        }
        var chosen = 1.0
        if !fits(1) {
            chosen = factor
            if fits(factor) {
                var fitting = factor
                var tooBig = 1.0
                for _ in 0..<7 {
                    let middle = (fitting + tooBig) / 2
                    if fits(middle) {
                        fitting = middle
                    } else {
                        tooBig = middle
                    }
                }
                chosen = fitting
            }
        }
        return layoutText(widget, proposedSize: proposedSize, environment: scaled(chosen), backend: backend)
    }

    /// The height the text must fit in: the proposed height and the line limit, the
    /// smaller of the two, or `nil` when neither bounds it.
    /// 文字必須放得下的高度：提議的高度與行數限制兩者中較小的那個；都沒有限制時為 `nil`。
    @MainActor
    private static func heightLimit(_ proposedSize: ProposedViewSize, _ environment: EnvironmentValues) -> Double? {
        var limit: Double? = nil
        if let height = proposedSize.height, height != .infinity {
            limit = height
        }
        if let lineLimit = environment.lineLimitSettings {
            let lines = Double(max(lineLimit.limit, 1)) * environment.resolvedFont.lineHeight
            limit = min(limit ?? lines, lines)
        }
        return limit
    }

    @MainActor private func layoutText<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        let transformedString = environment.applyingTextTransforms(to: string)

        // TODO: Avoid this. Move it to commit once we figure out a solution for Gtk.
        // Even in dry runs we must update the underlying text view widget
        // because GtkBackend currently relies on querying the widget for text
        // properties and such (via Pango).
        backend
            .updateTextView(widget, content: transformedString, environment: environment)

        // UI frameworks often handle the zero proposal specially. We want to
        // have standard text sizing behaviour so it's better for us to never
        // propose zero in either dimension and then fix up the resulting size
        // to match our expectations.
        //
        // A zero width proposal results in one line's worth of height for a
        // non-empty string, clipped to zero width -- what AppKit's NSTextField
        // measures (width 0 or 1 gives one 16 pt line). Chosen over a
        // one-character-per-line column because UIKitBackend drew that column,
        // clipped to nothing, as about 300 pt of empty space above P9's buttons.
        //
        // 零寬度的提議，對非空字串得到一行的高度、裁切成零寬——那是 AppKit 的 NSTextField 量出的結果
        // (寬 0 或 1 得到一行 16 pt)。選它而不是「一個字元一行」的直欄，是因為 UIKitBackend 畫出的
        // 那種直欄被裁到看不見，在 P9 的按鈕上方留下約 300 pt 的空白。
        //
        // A zero height proposal should result in the text using at least one
        // line of height (if non-empty).
        var size = backend.size(
            of: transformedString,
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

        // One line of this font, measured from one visible character; nil for
        // a string with none.
        // 此字型的一行，以一個可見字元量測；字串中沒有可見字元時為 nil。
        func oneLineHeight() -> Int? {
            guard let first = transformedString.first(where: { !$0.isWhitespace }) else {
                return nil
            }
            return backend.size(
                of: String(first),
                whenDisplayedIn: widget,
                proposedWidth: nil,
                proposedHeight: nil,
                environment: environment
            ).y
        }

        // The zero width proposal: one line at zero width. See above.
        // 零寬度的提議：一行，寬度為零。見上方。
        if proposedSize.width == 0 {
            if let line = oneLineHeight() {
                size = SIMD2(0, line)
            } else if size.x == 1 {
                size.x = 0
            }
        } else if let proposedHeight = proposedSize.height, proposedHeight != .infinity,
            size.y >= max(1, LayoutSystem.roundSize(proposedHeight)),
            let line = oneLineHeight(), line > 0
        {
            // A height the backend's answer filled is a clamped one, and it is
            // whole lines: at least one, as the comment above asks, and no part
            // of a line, as SwiftUI shows only the lines that fit.
            //
            // At least one: AppKit's NSTextField sizes its cell to the bounds it
            // is given, so a zero height proposal (sent as 1) came back 1 pt tall
            // and P10's captions above its fixed-size buttons were never drawn,
            // the buttons rising into their place. No partial line: a table cell
            // proposed one row's height came back that height, and AppKit drew a
            // wrapped cell's second line half cut off below the first, where
            // GtkBackend ends the first line with an ellipsis (P23, 2026-10-16).
            // A frame of whole lines lets NSTextField's truncatesLastVisibleLine
            // do the same.
            //
            // 被 backend 的答案填滿的高度就是被壓住的高度，而它必須是整行：至少一行(如上方註解所要求),
            // 而且不留半行(SwiftUI 只顯示放得下的行)。
            //
            // 至少一行:AppKit 的 NSTextField 會把 cell 定為所給的框，因此零高度的提議(以 1 送出)回來時
            // 只有 1 pt 高,P10 固定尺寸按鈕上方的說明文字從未畫出，按鈕往上移進它的位置。不留半行：被提議
            // 一列高度的表格儲存格回來時就是那個高度,AppKit 把換行儲存格的第二行畫在第一行下方、被切掉一半，
            // 而 GtkBackend 是以刪節號結束第一行(P23,2026-10-16)。整行的框讓 NSTextField 的
            // truncatesLastVisibleLine 也能這樣做。
            size.y = max(line, size.y / line * line)
        }

        // The line limit, applied here rather than in each backend.
        //
        // The cap needs no widget and no measurement -- it is the line height
        // times the limit -- so a backend that reaches for a widget to compute it
        // has already gone wrong. Measuring through a spare label that is never
        // added to a window gives GTK's default font size whatever font was asked
        // for, because GTK resolves style only for a widget with a root: with
        // P22's two-font check, `.lineLimit(2)` on the same paragraph reported
        // 300x35 at 13pt and 300x35 at 30pt. Doing it once here keeps every
        // backend on the same arithmetic.
        //
        // 行數限制在此處套用，而非於每個 backend 各自處理。
        //
        // 此上限不需要 widget、也不需要量測——它就是「行高 × 行數」——因此若某個 backend 為了計算
        // 它而去取用 widget，那時就已經走錯了。透過一個「從未加入任何視窗」的備用 label 來量測，
        // 無論被要求何種字型，都會得到 GTK 的預設字級，因為 GTK 只會為具有 root 的 widget 解析樣式：
        // 以 P22 的雙字級檢查，同一段文字加上 `.lineLimit(2)`，13pt 回報 300x35、30pt 同樣回報 300x35。
        // 在此處做一次，讓每個 backend 都用同一套算法。
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
