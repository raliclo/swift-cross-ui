import Foundation

public struct DatePickerComponents: OptionSet, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public init() {
        self.rawValue = 0
    }

    // These magic numbers are the same as SwiftUI. It's actually a bitfield:
    //
    //                        smhdMy--
    //                   date 00011100
    //          hourAndMinute 01100000
    //    hourMinuteAndSecond 11100000
    //
    // Like SwiftUI, not all combinations are valid (SwiftUI fatalErrors if you try to get creative
    // with your choice of flags), and hourMinuteAndSecond intentionally includes hourAndMinute.

    public static let date = DatePickerComponents(rawValue: 0x1C)
    public static let hourAndMinute = DatePickerComponents(rawValue: 0x60)

    @available(iOS, unavailable)
    @available(visionOS, unavailable)
    @available(macCatalyst, unavailable)
    public static let hourMinuteAndSecond = DatePickerComponents(rawValue: 0xE0)
}

// `DatePickerStyle` used to be an enum here. It is now a protocol in
// Views/Styles/DatePickerStyle/, and the enum it used to be lives on as
// `BackendDatePickerStyle` in Backend/ -- the vocabulary a backend implements,
// as distinct from the API an application writes against.
// `DatePickerStyle` 過去是此處的一個 enum。它現已成為 Views/Styles/DatePickerStyle/ 中的
// protocol，而它原本那個 enum 則以 `BackendDatePickerStyle` 之名存續於 Backend/ 之中——那是
// backend 所實作的詞彙，與應用程式所面對的 API 有別。

@available(tvOS, unavailable)
public struct DatePicker<Label: View> {
    private var label: Label
    private var selection: Binding<Date>
    private var range: ClosedRange<Date>
    private var components: DatePickerComponents

    // No stored `style`. There was one, defaulted to `.automatic`, and nothing
    // ever read it -- `body` did not pass it on and no initialiser set it. The
    // style has always come from the environment, which is what
    // `datePickerStyle(_:)` writes to.
    // 此處不保存 `style`。原本有一個、預設為 `.automatic`，但從來沒有任何地方讀取它——`body`
    // 不會把它傳下去，也沒有任何 initialiser 設定它。樣式一向來自 environment，而那正是
    // `datePickerStyle(_:)` 所寫入的位置。
    @Environment(\.self) private var environment

    /// Displays a date input.
    /// - Parameters:
    ///   - selection: The currently-selected date.
    ///   - range: The range of dates to display. The backend takes this as a hint but it is not
    ///     necessarily enforced. As such this parameter should be treated as an aid to validation
    ///     rather than a replacement for it.
    ///   - displayedComponents: Which parts of the date/time to display in the input.
    ///   - label: The view to be shown next to the date input.
    public nonisolated init(
        selection: Binding<Date>,
        in range: ClosedRange<Date> = Date.distantPast...Date.distantFuture,
        displayedComponents: DatePickerComponents = [.hourAndMinute, .date],
        @ViewBuilder label: () -> Label
    ) {
        self.label = label()
        self.selection = selection
        self.range = range
        self.components = displayedComponents
    }

    /// Displays a date input.
    /// - Parameters:
    ///   - label: The text to be shown next to the date input.
    ///   - selection: The currently-selected date.
    ///   - range: The range of dates to display. The backend takes this as a hint but it is not
    ///     necessarily enforced. As such this parameter should be treated as an aid to validation
    ///     rather than a replacement for it.
    ///   - displayedComponents: Which parts of the date/time to display in the input.
    public nonisolated init(
        _ label: String,
        selection: Binding<Date>,
        in range: ClosedRange<Date> = Date.distantPast...Date.distantFuture,
        displayedComponents: DatePickerComponents = [.hourAndMinute, .date]
    ) where Label == Text {
        self.label = Text(label)
        self.selection = selection
        self.range = range
        self.components = displayedComponents
    }

    public typealias Components = DatePickerComponents
}

@available(tvOS, unavailable)
extension DatePicker: View {
    public var body: some View {
        HStack {
            label

            // Routed through the style, exactly as `Picker` routes through
            // `PickerStyle`. `AnyView` because the style is existential and its
            // `Body` is not known here.
            // 交由 style 繪製，與 `Picker` 交由 `PickerStyle` 的方式完全相同。使用 `AnyView`，
            // 因為此處的 style 是 existential，其 `Body` 型別在這裡無從得知。
            AnyView(
                environment.datePickerStyle.makeView(
                    selection: selection,
                    range: range,
                    components: components,
                    environment: environment
                )
            )
        }
    }
}

/// The backend's own date input, as reached by the four built-in styles.
///
/// Public for the same reason ``_BuiltinPickerImplementation`` is: it is the
/// return type of a public extension method on ``DatePickerStyle``. The
/// underscore says the same thing that one's does -- an application should not
/// name this type.
///
/// 之所以公開，理由與 ``_BuiltinPickerImplementation`` 相同：它是 ``DatePickerStyle`` 上某個公開
/// extension 方法的回傳型別。底線所表達的與那一個相同——應用程式不應直接指名此型別。
@available(tvOS, unavailable)
public struct _BuiltinDatePickerImplementation: ElementaryView {
    private var style: BackendDatePickerStyle
    @Binding private var selection: Date
    private var range: ClosedRange<Date>
    private var components: DatePickerComponents

    init(
        style: BackendDatePickerStyle,
        selection: Binding<Date>,
        range: ClosedRange<Date>,
        components: DatePickerComponents
    ) {
        self.style = style
        self._selection = selection
        self.range = range
        self.components = components
    }

    public let body = EmptyView()

    @CastBackend<BackendFeatures.DatePickers>(returnsWidget: true)
    func asWidget<Backend: BaseAppBackend>(backend: Backend) -> Backend.Widget {
        backend.createDatePicker()
    }

    @CastBackend<BackendFeatures.DatePickers>
    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        backend.updateDatePicker(
            widget,
            environment: environment,
            date: selection,
            range: range,
            components: components,
            onChange: { selection = $0 }
        )

        // I reject your proposedSize and substitute my own
        let naturalSize = backend.naturalSize(of: widget)
        return ViewLayoutResult.leafView(size: ViewSize(naturalSize))
    }

    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        backend.setSize(of: widget, to: layout.size.vector)
    }
}
