import DebugFeatures
@_spi(Backends) import SwiftCrossUI
import WinUI

// swiftlint:disable force_try

extension WinUIBackend: BackendFeatures.Alerts {
    /// A `ContentDialog` plus the stack bookkeeping WinUI does not do.
    ///
    /// WinUI shows one `ContentDialog` per XamlRoot, and sheets are
    /// `ContentDialog`s too, so every alert waits for the dialog below it to
    /// finish closing before it is shown: the hidden dialog's `showAsync`
    /// completion is what shows the next one (`next`), the same rule
    /// `presentSheet` follows for nested sheets. When an alert closes, its own
    /// completion -- and only that -- restores what it covered: the parent
    /// alert, or the sheet it suspended, or the sheets that were asked for
    /// while it was up.
    ///
    /// 一個 `ContentDialog`,外加 WinUI 不會替我們做的堆疊記帳。
    ///
    /// WinUI 每個 XamlRoot 只顯示一個 `ContentDialog`,而 sheet 也是 `ContentDialog`,因此每個 alert
    /// 都要等它底下的對話框關完才顯示：被隱藏之對話框的 `showAsync` 完成處理負責顯示下一個(`next`),
    /// 與 `presentSheet` 處理巢狀 sheet 的規則相同。alert 關閉時，由它自己的完成處理——而且只有它——
    /// 復原它所覆蓋的東西：parent alert、它暫停的 sheet,或它開著期間被要求顯示的 sheet。
    public class Alert: ContentDialog {
        /// Why the next `showAsync` completion arrives without the user.
        /// 下一次 `showAsync` 完成處理為何不是由使用者造成。
        enum HideReason {
            /// Hidden to make room for `next`; it comes back when `next` closes.
            /// 為了讓出空間給 `next` 而隱藏;`next` 關閉時它會回來。
            case suspended
            /// `dismissAlert`: closes without calling the response handler.
            /// `dismissAlert`:關閉但不呼叫回應 handler。
            case dismissedByCode
        }

        weak var backend: WinUIBackend?
        var window: Window?
        var parentAlert: Alert?
        var handleResponse: ((Int) -> Void)?
        /// How many action labels `updateAlert` was given. 給 `updateAlert` 的動作標籤數。
        var actionCount = 0
        /// Whether a `showAsync` promise is outstanding. 是否有尚未完成的 `showAsync` promise。
        var isShowing = false
        var pendingHideReason: HideReason?
        /// The alert to show once this one's hide has completed. 本 alert 隱藏完成後要顯示的 alert。
        var next: Alert?
        /// The sheet this alert hid to be shown; it is presented again when the
        /// alert stack closes. 本 alert 為了顯示而隱藏的 sheet;alert 堆疊關閉時會再次呈現。
        weak var suspendedSheet: Sheet?
        /// Set by `dismissAlert`; a dismissed alert is never shown again.
        /// 由 `dismissAlert` 設定;已關閉的 alert 不會再顯示。
        var isDismissed = false

        public override init() {
            super.init()
            // Escape on a two-button alert is ignored, as on GtkBackend: WinUI
            // answers it with `.none`, which is no action's index, and neither
            // button can be told apart as the cancel one. One button: Escape
            // answers with it, as on AppKit and GtkBackend (P31). Three: the
            // third is WinUI's close button, which is what Escape means.
            // Programmatic hides also arrive as `.none` and are never cancelled.
            // 兩顆按鈕的 alert 忽略 Escape,與 GtkBackend 相同:WinUI 以 `.none` 回應，那不是任何動作的
            // 索引，而兩顆按鈕也分不出哪顆是取消。一顆按鈕:Escape 以那顆回應，與 AppKit、GtkBackend 相同
            // (P31)。三顆：第三顆是 WinUI 的關閉按鈕，正是 Escape 的意思。程式發起的隱藏也以 `.none` 到達,
            // 永遠不會被取消。
            closing.addHandler { [weak self] _, args in
                guard let self, let args, self.pendingHideReason == nil else { return }
                if args.result == ContentDialogResult.none && self.actionCount == 2 {
                    args.cancel = true
                }
            }
        }

        /// Shows an alert that has already been attached to a window (via xamlRoot),
        /// and attached to the alert stack (via parentAlert and updating
        /// window.currentAlert)
        func showAttached() {
            if isDismissed {
                // `dismissAlert` came while this alert waited or was suspended:
                // it is skipped, and what it covered comes back instead.
                // `dismissAlert` 在本 alert 等待或暫停期間到來：略過它，改為讓它覆蓋的東西回來。
                restoreCovered()
                return
            }
            if let next {
                // A child arrived while this alert waited for a dialog to close:
                // the child goes up now, and this alert when the child closes.
                // 本 alert 等待對話框關閉期間來了一個子 alert:子 alert 現在上去，本 alert 在子 alert 關閉時才上去。
                self.next = nil
                next.showAttached()
                return
            }
            do {
                guard let promise = try showAsync() else {
                    logger.warning("WinUIBackend.Alert: showAsync returned no operation")
                    restoreCovered()
                    return
                }
                isShowing = true
                promise.completed = { [weak self] operation, status in
                    guard let self else { return }
                    // Read here, where the operation's type is inferred.
                    // 在此讀取，此處 operation 的型別由推論而得。
                    var result: ContentDialogResult?
                    var failure: (any Swift.Error)?
                    if status == .completed, let operation {
                        do {
                            result = try operation.getResults()
                        } catch {
                            failure = error
                        }
                    }
                    self.handleCompletion(result: result, failure: failure)
                }
            } catch {
                // Said out loud: the alert never appeared, so its response
                // handler will not run either. 明講:alert 沒有出現，因此它的回應 handler 也不會執行。
                logger.warning("WinUIBackend.Alert: showAsync failed -- \(error)")
                restoreCovered()
            }
        }

        private func handleCompletion(result: ContentDialogResult?, failure: (any Swift.Error)?) {
            isShowing = false
            let reason = pendingHideReason
            pendingHideReason = nil

            // Hidden for another alert: show it now that this dialog is gone.
            // What this alert covered is the other alert's to restore (it was
            // handed over), or this alert comes back when it closes (suspended).
            // 為另一個 alert 而隱藏：本對話框已關閉，現在顯示它。本 alert 所覆蓋的東西改由那個 alert 復原
            // (已交接),或在它關閉時本 alert 回來(暫停)。
            if let next {
                self.next = nil
                next.showAttached()
                return
            }
            if reason != nil {
                // `.dismissedByCode`: the protocol says no response handler.
                // `.dismissedByCode`:協定規定不呼叫回應 handler。
                restoreCovered()
                return
            }

            // Said out loud rather than `try?`: a failure here means the
            // alert closed and its response handler never ran, which looks
            // exactly like the user dismissing it.
            // 明講而不是 `try?`:此處失敗代表對話框關了、回應 handler 卻沒有執行,而那看起來與使用者
            // 關閉它一模一樣。
            guard let result else {
                DebugFeatures.log(
                    "WinUIBackend.Alert: no result -- \(failure.map { "\($0)" } ?? "not completed"). "
                        + "The response handler was NOT called."
                )
                restoreCovered()
                return
            }

            // `.none` is Escape (or the close button): the third action when
            // there is one, the only action on a one-button alert. Anything
            // else is no action, and indexing with it would trap in the
            // caller's `actions[index]`.
            // `.none` 是 Escape(或關閉按鈕):有第三個動作時就是它，一顆按鈕的 alert 則是那唯一的動作。
            // 其他情況不對應任何動作，拿它當索引會在呼叫端的 `actions[index]` 中止。
            let index: Int? =
                switch result {
                    case .primary: 0
                    case .secondary: 1
                    default: actionCount >= 3 ? 2 : (actionCount == 1 ? 0 : nil)
                }
            restoreCovered()
            if let index, index < actionCount {
                handleResponse?(index)
            } else {
                logger.warning(
                    "WinUIBackend.Alert: closed with no action (\(actionCount) actions)"
                )
            }
        }

        /// Puts back what this alert covered: its parent alert, else the sheets.
        /// Called from this alert's own completion only, so it runs once.
        /// 放回本 alert 所覆蓋的東西：它的 parent alert,否則是 sheet。只由本 alert 自己的完成處理呼叫，所以只執行一次。
        func restoreCovered() {
            let parent = parentAlert
            parentAlert = nil
            if let window, window.currentAlert === self {
                window.currentAlert = parent
            }
            if let parent {
                // The sheet stays suspended under the parent. sheet 繼續暫停在 parent 之下。
                if parent.suspendedSheet == nil {
                    parent.suspendedSheet = suspendedSheet
                }
                suspendedSheet = nil
                parent.showAttached()
                return
            }
            let sheet = suspendedSheet
            suspendedSheet = nil
            if let window, let backend {
                // Alert completions arrive on the UI thread, where the backend lives.
                // alert 的完成處理在 UI 執行緒上到達，也就是 backend 所在之處。
                MainActor.assumeIsolated {
                    backend.presentSheets(afterAlertsIn: window, suspended: sheet)
                }
            }
        }
    }

    public func createAlert() -> Alert {
        let alert = Alert()
        alert.backend = self
        return alert
    }

    public func updateAlert(
        _ alert: Alert,
        title: String,
        actionLabels: [String],
        environment: EnvironmentValues
    ) {
        alert.title = title
        alert.actionCount = actionLabels.count
        if actionLabels.count >= 1 {
            alert.primaryButtonText = actionLabels[0]
        }
        if actionLabels.count >= 2 {
            alert.secondaryButtonText = actionLabels[1]
        }
        if actionLabels.count >= 3 {
            alert.closeButtonText = actionLabels[2]
        }

        switch environment.colorScheme {
            case .light:
                alert.requestedTheme = .light
            case .dark:
                alert.requestedTheme = .dark
        }
    }

    public func showAlert(
        _ alert: Alert,
        window: Window?,
        responseHandler handleResponse: @escaping (Int) -> Void
    ) {
        guard let window = window ?? windows.first else {
            logger.warning("WinUI can't show alert without window")
            return
        }

        alert.xamlRoot = window.content.xamlRoot
        alert.window = window
        alert.backend = self
        alert.handleResponse = handleResponse

        // WinUI only allows one dialog at a time (a second `showAsync` throws),
        // so whatever dialog is up is hidden first and the new alert is shown
        // from that dialog's completion.
        // WinUI 一次只允許一個對話框(第二個 `showAsync` 會擲出錯誤),因此先隱藏目前的對話框，新的
        // alert 由該對話框的完成處理來顯示。
        if let currentAlert = window.currentAlert {
            window.currentAlert = alert
            if currentAlert.pendingHideReason == .dismissedByCode {
                // Already closing for good: take its place in the stack, and be
                // shown by its completion.
                // 已在永久關閉中：取代它在堆疊中的位置，由它的完成處理來顯示。
                alert.parentAlert = currentAlert.parentAlert
                alert.suspendedSheet = currentAlert.suspendedSheet
                currentAlert.parentAlert = nil
                currentAlert.suspendedSheet = nil
                currentAlert.next = alert
                return
            }
            alert.parentAlert = currentAlert
            currentAlert.next = alert
            guard currentAlert.isShowing else {
                // Not on screen yet -- itself waiting for a dialog to close --
                // so `showAttached` will put this alert up in its place.
                // 尚未上螢幕(它自己也在等某個對話框關閉),所以 `showAttached` 會改為讓本 alert 上去。
                return
            }
            currentAlert.pendingHideReason = .suspended
            do {
                try currentAlert.hide()
            } catch {
                logger.warning("WinUIBackend: hiding the current alert failed -- \(error)")
                currentAlert.pendingHideReason = nil
                currentAlert.next = nil
                alert.showAttached()
            }
            return
        }

        window.currentAlert = alert
        if let sheet = window.presentedSheet, sheet.isPresenting {
            // A sheet is a ContentDialog too: suspend it, and show the alert
            // once it has closed. It comes back when the alert stack closes.
            // sheet 也是 ContentDialog:暫停它，等它關完再顯示 alert。alert 堆疊關閉時它會回來。
            alert.suspendedSheet = sheet
            if suspendSheet(sheet, for: alert) {
                return
            }
            alert.suspendedSheet = nil
        }
        alert.showAttached()
    }

    public func dismissAlert(_ alert: Alert, window: Window?) {
        alert.isDismissed = true
        alert.handleResponse = nil
        guard alert.isShowing, alert.pendingHideReason == nil else {
            // Waiting to be shown, suspended under a child, or already closing:
            // no new `hide()` is needed. `isDismissed` makes `showAttached` skip
            // it when its turn comes, which restores what it covered instead.
            // 正在等待顯示、暫停在子 alert 之下，或已在關閉中：不需要新的 `hide()`。輪到它時,
            // `isDismissed` 讓 `showAttached` 略過它，改為復原它所覆蓋的東西。
            return
        }

        // The completion restores what the alert covered -- exactly once, and
        // only after this dialog has really closed -- and skips the response
        // handler, as the protocol requires.
        // 由完成處理復原 alert 所覆蓋的東西——恰好一次，而且是在這個對話框真正關閉之後——並略過回應
        // handler,如協定所要求。
        alert.pendingHideReason = .dismissedByCode
        do {
            try alert.hide()
        } catch {
            logger.warning("WinUIBackend: hiding an alert failed -- \(error)")
            alert.pendingHideReason = nil
            alert.isShowing = false
            alert.restoreCovered()
        }
    }
}
