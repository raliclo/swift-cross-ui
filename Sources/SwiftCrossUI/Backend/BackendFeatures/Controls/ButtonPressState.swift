extension BackendFeatures {
    /// Backend methods for reporting whether a button is currently held down.
    ///
    /// This exists for one caller: ``ButtonStyleConfiguration/isPressed``. A
    /// SwiftUI ``ButtonStyle`` is handed `isPressed` and is expected to draw
    /// differently while the button is down, so without a live signal from the
    /// platform the whole protocol is decoration -- a custom style would compile,
    /// render, and never change.
    ///
    /// **Why a separate protocol rather than a parameter on `updateButton`.**
    /// `BackendFeatures/ViewLabelButtons` is upstream's, and widening one of its
    /// requirements would conflict on every merge. This is additive, and it is
    /// shaped after ``BackendFeatures/HoverGestures``, which answers the same
    /// question -- "tell me when a boolean about this widget changes" -- for
    /// hover.
    ///
    /// **Unlike `HoverGestures` there is no `create` half.** Hover has to wrap a
    /// view that knows nothing about pointers; a button already exists, already
    /// tracks whether it is held down in order to draw its own highlight, and on
    /// three of the five backends that state was already there and merely
    /// private. Measured 2026-09-08: `isPressed`/`isHighlighted` exist in
    /// `AppKitBackend+Button.swift:97,106`, `WinUIBackend+Button.swift:82,83`
    /// and `UIKitBackend+CustomButton.swift:139`; GtkBackend and AndroidBackend
    /// had nothing, so those two are the real work.
    ///
    /// The handler is called on **every** transition, including the one to
    /// `false` when a press is abandoned by dragging off the button. A style that
    /// only ever saw `true` would latch.
    ///
    /// 用於回報「某個按鈕目前是否被按住」的 backend 方法。
    ///
    /// 它的存在只為一個呼叫端：``ButtonStyleConfiguration/isPressed``。SwiftUI 的 ``ButtonStyle``
    /// 會收到 `isPressed`，並被預期在按鈕按下期間畫得不一樣；因此若沒有來自平台的即時訊號，整個
    /// protocol 就只是裝飾——自訂樣式編得過、畫得出來，然後永遠不會變化。
    ///
    /// **為何獨立成一個 protocol，而不是在 `updateButton` 上加參數。**
    /// `BackendFeatures/ViewLabelButtons` 是 upstream 的，加寬它任何一項 requirement 都會在每次合併
    /// 時衝突。此處採取新增的做法，並比照 ``BackendFeatures/HoverGestures`` 的形狀——後者為 hover
    /// 回答的是同一個問題：「當這個 widget 的某個布林值改變時通知我」。
    ///
    /// **與 `HoverGestures` 不同的是，此處沒有 `create` 那一半。** hover 必須包裝一個對指標一無所知的
    /// view；而按鈕本來就已存在，也本來就為了繪製自身的高亮而追蹤自己是否被按住。2026-09-08 實測：
    /// 五個 backend 中有三個早已具備該狀態，只是宣告為私有——`AppKitBackend+Button.swift:97,106`、
    /// `WinUIBackend+Button.swift:82,83`、`UIKitBackend+CustomButton.swift:139`；GtkBackend 與
    /// AndroidBackend 則完全沒有，那兩個才是真正的工作。
    ///
    /// handler 會在**每一次**轉換時被呼叫，包含「按住之後把指標拖離按鈕而放棄」所產生的那一次
    /// `false`。一個只看得到 `true` 的樣式會卡在按下狀態。
    @MainActor
    public protocol ButtonPressState: Core {
        /// Installs the handler called whenever `button`'s pressed state changes.
        ///
        /// The new handler replaces any previous one, matching
        /// `updateHoverTarget(_:environment:action:)`. Backends must call it with
        /// `true` when the button goes down and `false` when it comes up **or**
        /// when the press is abandoned.
        ///
        /// - Parameters:
        ///   - button: A widget previously returned by `createButton(wrapping:)`
        ///     or `createSimpleButton()`.
        ///   - handler: Receives `true` while the button is held down.
        ///
        /// 安裝一個 handler，於 `button` 的按下狀態改變時被呼叫。
        ///
        /// 新的 handler 會取代先前的，行為比照 `updateHoverTarget(_:environment:action:)`。backend
        /// 必須在按鈕按下時以 `true` 呼叫它，並在放開**或**該次按壓被放棄時以 `false` 呼叫。
        ///
        /// - Parameters:
        ///   - button: 先前由 `createButton(wrapping:)` 或 `createSimpleButton()` 回傳的 widget。
        ///   - handler: 在按鈕被按住期間收到 `true`。
        func updateButtonPressHandler(
            _ button: Widget,
            handler: @escaping (Bool) -> Void
        )
    }
}
