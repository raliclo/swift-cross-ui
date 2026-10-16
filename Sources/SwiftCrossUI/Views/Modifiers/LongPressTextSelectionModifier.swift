extension View {
    /// Long-press drag selection in every `TextField` and `TextEditor` inside
    /// this view: a long press puts the caret under the finger as the anchor,
    /// dragging without lifting extends the selection to the character under
    /// the pointer, nothing scrolls meanwhile, and lifting keeps the selection.
    ///
    /// **Not SwiftUI API -- SwiftUI has no equivalent**, so the name says what
    /// it does, in the shape of SwiftUI's `textSelection(_:)`. Off unless
    /// asked for: it replaces each platform's own long press in a field
    /// (iOS's loupe, Android's word selection and its Paste menu, WinUI's touch
    /// flyout), and an app should choose to trade those away, as the app this
    /// came from did. Set on a container, it reaches every field below, the
    /// way that app made it page-wide. A long press outside a field is not
    /// touched. `SecureField` is never affected.
    ///
    /// 這個 view 裡每個 `TextField` 與 `TextEditor` 的長按拖曳選取：長按把插入點放在手指底下作為錨點，
    /// 不放開地拖曳會把選取延伸到指標底下的字元，期間不捲動，放開後保留選取。**不是 SwiftUI API——SwiftUI
    /// 沒有對應物**,所以名稱直接說出它做什麼，形狀仿 SwiftUI 的 `textSelection(_:)`。預設關閉：它取代各平台
    /// 在欄位裡原有的長按(iOS 的放大鏡、Android 的選字與「貼上」選單、WinUI 的觸控 flyout),要不要拿那些
    /// 去換，應由 app 選擇——就像這個功能的來源 app 那樣。設在容器上就涵蓋底下所有欄位，如同該 app 讓它對
    /// 整頁生效。欄位以外的長按不受影響。`SecureField` 永遠不受影響。
    public func longPressTextSelection(_ isEnabled: Bool = true) -> some View {
        EnvironmentModifier(
            self,
            modification: { environment in
                environment.with(\.isLongPressTextSelectionEnabled, isEnabled)
            }
        )
    }
}

extension EnvironmentValues {
    /// Whether text fields and editors select by long press and drag. Set by
    /// ``View/longPressTextSelection(_:)``.
    /// 文字欄位與編輯器是否以長按加拖曳選取。由 ``View/longPressTextSelection(_:)`` 設定。
    @Entry public var isLongPressTextSelectionEnabled: Bool = false
}

/// Opens a backend's ``BackendFeatures/LongPressTextSelection`` for TextField
/// and TextEditor. / 為 TextField 與 TextEditor 開啟 backend 的 ``BackendFeatures/LongPressTextSelection``。
@MainActor
enum LongPressTextSelectionSupport {
    /// Which view the widget belongs to, for the diagnostics.
    /// widget 屬於哪個 view,供診斷使用。
    enum Kind: String {
        case textField
        case textEditor
    }

    static func update<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        kind: Kind,
        backend: Backend,
        environment: EnvironmentValues
    ) {
        let enabled = environment.isLongPressTextSelectionEnabled && environment.isEnabled
        guard let capable = backend as? any BackendFeatures.LongPressTextSelection else {
            if enabled {
                logger.warnOnce(
                    "\(type(of: backend)) has no long-press text selection; longPressTextSelection() leaves its fields as they are"
                )
            }
            return
        }
        func open<B: BackendFeatures.LongPressTextSelection>(_ backend: B) {
            var handler: (@MainActor (TextDragSelection, TextDragSelectionPhase) -> Void)? = nil
            if enabled {
                handler = { selection, phase in
                    LongPressTextSelectionDiagnostics.record(kind: kind, selection, phase)
                }
            }
            backend.setLongPressTextSelection(
                ofTextInput: widget as! B.Widget,
                enabled: enabled,
                onChange: handler
            )
        }
        open(capable)
    }
}

/// Every long-press drag selection the backends reported, for test apps that
/// check the toolkit's selection after a scripted press. Not SwiftUI API.
/// 各 backend 回報過的每一次長按拖曳選取，供在腳本化按壓之後檢查 toolkit 選取的測試 app 使用。不是 SwiftUI API。
@_spi(Backends)
@MainActor
public enum LongPressTextSelectionDiagnostics {
    public struct Entry: Sendable, CustomStringConvertible {
        /// `"textField"` or `"textEditor"`.
        public var kind: String
        public var selection: TextDragSelection
        public var phase: TextDragSelectionPhase

        public var description: String {
            "\(kind) \(phase.rawValue) \(selection)"
        }
    }

    public private(set) static var entries: [Entry] = []

    /// Called after each entry is recorded. / 每記錄一筆之後呼叫。
    public static var onRecord: (@MainActor (Entry) -> Void)?

    static func record(kind: LongPressTextSelectionSupport.Kind, _ selection: TextDragSelection, _ phase: TextDragSelectionPhase) {
        let entry = Entry(kind: kind.rawValue, selection: selection, phase: phase)
        entries.append(entry)
        if entries.count > 512 { entries.removeFirst(entries.count - 512) }
        onRecord?(entry)
    }

    public static func reset() {
        entries.removeAll()
    }
}
