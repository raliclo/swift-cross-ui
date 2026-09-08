import Foundation

/// A progress indicator; either a bar or a spinner.
public struct ProgressView<Label: View>: View {
    /// The label for this progress view.
    private var label: Label
    /// The current progress, if this is a progress bar.
    private var progress: Double?
    private var kind: Kind
    private var isSpinnerResizable: Bool = false

    typealias Kind = _ProgressIndicatorKind

    public var body: some View {
        if label as? EmptyView == nil {
            progressIndicator
            label
        } else {
            progressIndicator
        }
    }

    /// The style decides, and the initialiser only supplies the default.
    ///
    /// `kind` used to decide alone, which made `ProgressView(value:)` a bar and
    /// `ProgressView(_:)` a spinner with no way to say otherwise -- SwiftUI
    /// spells that override `.progressViewStyle(.circular)`. The initialiser's
    /// choice survives as ``ProgressViewStyle/automatic``'s rule, so nothing
    /// that did not set a style changes behaviour.
    ///
    /// 由樣式決定，而建構式只提供預設值。
    ///
    /// 過去是由 `kind` 獨自決定的，那使得 `ProgressView(value:)` 必為長條、`ProgressView(_:)` 必為
    /// 轉圈，且無從表達其他意圖——而 SwiftUI 表達該覆寫的寫法是 `.progressViewStyle(.circular)`。
    /// 建構式原本的選擇以 ``ProgressViewStyle/automatic`` 的規則存續下來，因此任何未設定樣式的程式碼
    /// 行為都不會改變。
    private var progressIndicator: some View {
        StyledProgressIndicator(
            progress: progress,
            fallbackKind: kind,
            isSpinnerResizable: isSpinnerResizable
        )
    }

    /// Creates an indeterminate progress view (a spinner).
    ///
    /// - Parameter label: The label for this progress view.
    public init(_ label: Label) {
        self.label = label
        self.kind = .spinner
    }

    /// Creates a progress bar.
    ///
    /// - Parameters:
    ///   - label: The label for this progress view.
    ///   - progress: The current progress.
    public init(_ label: Label, _ progress: Progress) {
        self.label = label
        self.kind = .bar

        if !progress.isIndeterminate {
            self.progress = progress.fractionCompleted
        }
    }

    /// Creates a progress bar.
    ///
    /// - Parameters:
    ///   - label: The label for this progress view.
    ///   - value: The current progress. If `nil`, an indeterminate progress bar
    ///     will be shown.
    public init<Value: BinaryFloatingPoint>(_ label: Label, value: Value?) {
        self.label = label
        self.kind = .bar
        self.progress = value.map { Double($0) }
    }

    /// Makes the `ProgressView` resize to fit the available space.
    ///
    /// This only affects spinners.
    public func resizable(_ isResizable: Bool = true) -> Self {
        var progressView = self
        progressView.isSpinnerResizable = isResizable
        return progressView
    }
}

extension ProgressView where Label == EmptyView {
    /// Creates an indeterminate progress view (a spinner).
    public init() {
        self.label = EmptyView()
        self.kind = .spinner
    }

    /// Creates a progress bar.
    ///
    /// - Parameters:
    ///   - progress: The current progress.
    public init(_ progress: Progress) {
        self.label = EmptyView()
        self.kind = .bar

        if !progress.isIndeterminate {
            self.progress = progress.fractionCompleted
        }
    }

    /// Creates a progress bar.
    ///
    /// - Parameters:
    ///   - value: The current progress. If `nil`, an indeterminate progress bar
    ///     will be shown.
    public init<Value: BinaryFloatingPoint>(value: Value?) {
        self.label = EmptyView()
        self.kind = .bar
        self.progress = value.map { Double($0) }
    }
}

extension ProgressView where Label == Text {
    /// Creates an indeterminate progress view (a spinner).
    ///
    /// - Parameter label: The label for this progress view.
    public init(_ label: String) {
        self.label = Text(label)
        self.kind = .spinner
    }

    /// Creates a progress bar.
    ///
    /// - Parameters:
    ///   - label: The label for this progress view.
    ///   - progress: The current progress.
    public init(_ label: String, _ progress: Progress) {
        self.label = Text(label)
        self.kind = .bar

        if !progress.isIndeterminate {
            self.progress = progress.fractionCompleted
        }
    }

    /// Creates a progress bar.
    ///
    /// - Parameters:
    ///   - label: The label for this progress view.
    ///   - value: The current progress. If `nil`, an indeterminate progress bar
    ///     will be shown.
    public init<Value: BinaryFloatingPoint>(_ label: String, value: Value?) {
        self.label = Text(label)
        self.kind = .bar
        self.progress = value.map { Double($0) }
    }
}

struct ProgressSpinnerView: ElementaryView {
    let isResizable: Bool

    init(isResizable: Bool = false) {
        self.isResizable = isResizable
    }

    func asWidget<Backend: BaseAppBackend>(backend: Backend) -> Backend.Widget {
        backend.createProgressSpinner()
    }

    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        let naturalSize = backend.naturalSize(of: widget)

        guard isResizable else {
            return ViewLayoutResult.leafView(size: ViewSize(naturalSize))
        }

        let dimension: Double

        if let proposedWidth = proposedSize.width, let proposedHeight = proposedSize.height {
            dimension = min(proposedWidth, proposedHeight)
        } else if let proposedWidth = proposedSize.width {
            dimension = proposedWidth
        } else if let proposedHeight = proposedSize.height {
            dimension = proposedHeight
        } else {
            dimension = Double(min(naturalSize.x, naturalSize.y))
        }

        return ViewLayoutResult.leafView(
            size: ViewSize(dimension, dimension)
        )
    }

    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        // Doesn't change the rendered size of ProgressSpinner
        // on UIKitBackend, but still sets container size to
        // (width: n, height: n) n = min(proposedSize.x, proposedSize.y)
        backend.setSize(ofProgressSpinner: widget, to: layout.size.vector)
    }
}

struct ProgressBarView: ElementaryView {
    /// The ideal width of a ProgressBarView.
    static let idealWidth: Double = 100

    var value: Double?

    init(value: Double?) {
        self.value = value
    }

    func asWidget<Backend: BaseAppBackend>(backend: Backend) -> Backend.Widget {
        backend.createProgressBar()
    }

    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        let height = backend.naturalSize(of: widget).y
        let size = ViewSize(
            proposedSize.width ?? Self.idealWidth,
            Double(height)
        )

        return ViewLayoutResult.leafView(size: size)
    }

    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        backend.updateProgressBar(widget, progressFraction: value, environment: environment)
        backend.setSize(of: widget, to: layout.size.vector)
    }
}

/// Resolves the style against the environment, one level below ``ProgressView``.
///
/// A separate view because the style lives in the environment and
/// ``ProgressView``'s `body` has no `@Environment` of its own to read it from
/// -- reading it here keeps `ProgressView` a plain composition.
///
/// 在 ``ProgressView`` 下一層解析樣式。
///
/// 之所以獨立為一個 view，是因為樣式住在 environment 中，而 ``ProgressView`` 的 `body` 自身沒有
/// `@Environment` 可以讀取它——在此處讀取，可讓 `ProgressView` 維持為單純的組合。
struct StyledProgressIndicator: View {
    var progress: Double?
    var fallbackKind: _ProgressIndicatorKind
    var isSpinnerResizable: Bool

    @Environment(\.self) var environment

    var body: some View {
        // `isSpinnerResizable` is honoured only on the path the initialiser
        // chose, because it is a property of `ProgressView(_:)`'s spinner and a
        // style that asks for a spinner is asking for the control, not for that
        // view's sizing behaviour.
        // `isSpinnerResizable` 僅在「建構式所選的那條路徑」上被遵守，因為它是
        // `ProgressView(_:)` 那個轉圈的性質;而一個要求轉圈的樣式，要的是那個控制項本身，
        // 不是該 view 的尺寸行為。
        AnyView(
            environment.progressViewStyle.makeView(
                progress: progress,
                environment: environment
                    .with(\.progressViewDefaultKind, fallbackKind)
                    .with(\.progressSpinnerIsResizable, isSpinnerResizable)
            )
        )
    }
}
