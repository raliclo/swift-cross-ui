import SwiftCrossUI
import UIKit

extension UIKitBackend: BackendFeatures.FocusableViews {
    /// Makes this widget the first responder.
    ///
    /// **The widget is usually not the responder**, the same asymmetry the
    /// accessibility file records: a ``TextField`` is a `UIView` around a
    /// `UITextField`, and `becomeFirstResponder()` on the wrapper returns
    /// `false` because `UIView.canBecomeFirstResponder` is `false`. So the
    /// responder is looked for beneath it.
    ///
    /// UIKit already returns `Bool` here, which is the return type this protocol
    /// took from Android for the same reason: a view that is not in a window,
    /// is disabled, or is off screen declines, and declining is ordinary.
    ///
    /// 讓這個 widget 成為 first responder。
    ///
    /// **widget 通常不是那個 responder**,與無障礙那個檔案所記載的是同一種不對稱:一個 ``TextField``
    /// 是一個包著 `UITextField` 的 `UIView`,而對那層包裝呼叫 `becomeFirstResponder()` 會回傳
    /// `false`,因為 `UIView.canBecomeFirstResponder` 是 `false`。因此 responder 要往它底下找。
    ///
    /// UIKit 這裡本來就回傳 `Bool`,而本協定之所以採用這個回傳型別,理由與 Android 相同:一個不在
    /// 視窗裡、被停用、或不在畫面上的 view 會拒絕,而拒絕是常態。
    @discardableResult
    public func focus(_ widget: Widget) -> Bool {
        responder(in: widget.view).becomeFirstResponder()
    }

    public func unfocus(_ widget: Widget) {
        guard isFocused(widget) else { return }
        // `resignFirstResponder` on the responder that HAS it, not on the
        // wrapper: the wrapper never became one, so asking it to resign is a
        // no-op that reads as a working call.
        // 對**真正持有**焦點的那個 responder 呼叫 `resignFirstResponder`,而不是對那層包裝:那層包裝
        // 從來沒有成為過 responder,因此要求它放棄是一次「什麼都沒做、卻讀起來像成功」的呼叫。
        focusedDescendant(of: widget.view)?.resignFirstResponder()
    }

    public func isFocused(_ widget: Widget) -> Bool {
        focusedDescendant(of: widget.view) != nil
    }

    /// Reports focus arriving and leaving, for any reason.
    ///
    /// **Two notifications, not a delegate.** `UITextFieldDelegate` would report
    /// the field's own editing and nothing else, and the delegate slot is
    /// already taken by whatever wired the field's text up. The notifications
    /// are posted for every text field and text view in the process, so one
    /// observer per watched widget sees moves it did not cause -- which is the
    /// half of this protocol that cannot be simulated.
    ///
    /// **`didBegin` is not enough on its own.** A field that loses the focus to
    /// another field posts only the other field's `didBegin`, so the check runs
    /// on both notifications and compares, rather than trusting which one fired.
    ///
    /// 回報焦點的抵達與離開,無論原因為何。
    ///
    /// **用兩個通知,而不是 delegate。** `UITextFieldDelegate` 只會回報該欄位自己的編輯、別的都不報,
    /// 而且那個 delegate 位置早就被「把欄位文字接起來」的那段程式佔走了。這些通知是為行程內**每一個**
    /// 文字欄位與文字視圖發出的,因此每個被觀察的 widget 各有一個 observer,就看得見它自己沒有造成的
    /// 移動——而那正是本協定中無法被模擬的那一半。
    ///
    /// **只靠 `didBegin` 是不夠的。** 一個「把焦點輸給另一個欄位」的欄位,只會看到對方的 `didBegin`;
    /// 因此檢查在兩個通知上都執行並做比較,而不是去相信是哪一個觸發的。
    public func setFocusChangeHandler(
        ofWidget widget: Widget,
        to handler: @escaping (Bool) -> Void
    ) {
        // Handler swapped, observer kept -- see the AppKit file for the
        // measurement that made this necessary: a rebuilt observer starts from
        // the current value and reports nothing when the frame beats the
        // notification.
        // 換掉 handler、保留 observer——讓這件事成為必要的那次量測見 AppKit 那個檔案:一個被重建的
        // observer 會從當下的值開始,而當那一幀跑贏通知時,它什麼都不會回報。
        if let existing = Self.focusObservers[ObjectIdentifier(widget.view)] {
            existing.handler = handler
        } else {
            Self.focusObservers[ObjectIdentifier(widget.view)] = FocusObserver(
                view: widget.view,
                handler: handler,
                backend: self
            )
        }
    }

    @MainActor static var focusObservers: [ObjectIdentifier: FocusObserver] = [:]

    /// `@MainActor` on the class so it is `Sendable` and a `@Sendable`
    /// notification closure can hold it; see the AppKit file for the full
    /// reasoning.
    /// `@MainActor` 標在類別上,好讓它是 `Sendable` 的、能被一個 `@Sendable` 的通知 closure 持有;
    /// 完整的推理見 AppKit 那個檔案。
    @MainActor
    final class FocusObserver {
        private weak var view: UIView?
        var handler: (Bool) -> Void
        private let backend: UIKitBackend
        private var lastValue: Bool
        private nonisolated(unsafe) var observations: [NSObjectProtocol] = []

        init(view: UIView, handler: @escaping (Bool) -> Void, backend: UIKitBackend) {
            self.view = view
            self.handler = handler
            self.backend = backend
            self.lastValue = backend.focusedDescendant(of: view) != nil

            for name: Notification.Name in [
                UITextField.textDidBeginEditingNotification,
                UITextField.textDidEndEditingNotification,
                UITextView.textDidBeginEditingNotification,
                UITextView.textDidEndEditingNotification,
            ] {
                observations.append(
                    NotificationCenter.default.addObserver(
                        forName: name,
                        object: nil,
                        queue: .main
                    ) { [weak self] _ in
                        MainActor.assumeIsolated { self?.check() }
                    }
                )
            }
        }

        deinit {
            for observation in observations {
                NotificationCenter.default.removeObserver(observation)
            }
        }

        private func check() {
            guard let view else { return }
            let now = backend.focusedDescendant(of: view) != nil
            guard now != lastValue else { return }
            lastValue = now
            handler(now)
        }
    }

    /// The responder inside this view that currently holds the focus, if any.
    /// 這個 view 裡面目前持有焦點的那個 responder(若有)。
    fileprivate func focusedDescendant(of view: UIView) -> UIView? {
        if view.isFirstResponder { return view }
        for subview in view.subviews {
            if let found = focusedDescendant(of: subview) { return found }
        }
        return nil
    }

    /// The thing inside this widget that can take the keyboard.
    ///
    /// Falls back to the view itself when there is no candidate or more than
    /// one, so `focus` fails visibly through its `Bool` rather than moving the
    /// keyboard somewhere the caller did not name.
    /// 這個 widget 裡面那個拿得到鍵盤的東西。
    ///
    /// 沒有候選、或候選超過一個時,退回 view 本身;如此 `focus` 會透過它的 `Bool` **明顯地**失敗,
    /// 而不是把鍵盤移到呼叫端沒有指名的地方。
    private func responder(in view: UIView) -> UIView {
        if view.canBecomeFirstResponder { return view }
        return firstResponderCandidate(in: view) ?? view
    }

    private func firstResponderCandidate(in view: UIView) -> UIView? {
        var found: UIView?
        for subview in view.subviews {
            let candidate =
                subview.canBecomeFirstResponder ? subview : firstResponderCandidate(in: subview)
            guard let candidate else { continue }
            if found != nil { return nil }
            found = candidate
        }
        return found
    }
}
