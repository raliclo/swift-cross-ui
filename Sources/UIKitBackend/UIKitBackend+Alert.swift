@_spi(Backends) import SwiftCrossUI
import UIKit

extension UIKitBackend {
    public typealias Alert = UIAlertController

    final class CustomAlertAction: UIAlertAction {
        var handler: (() -> Void)?
    }

    public func createAlert() -> Alert {
        Alert(title: nil, message: nil, preferredStyle: .alert)
    }

    public func updateAlert(
        _ alert: Alert,
        title: String,
        actionLabels: [String],
        environment _: EnvironmentValues
    ) {
        alert.title = title

        for actionLabel in actionLabels {
            let action = CustomAlertAction(title: actionLabel, style: .default) { action in
                (action as! CustomAlertAction).handler?()
            }
            alert.addAction(action)
        }
    }

    public func showAlert(
        _ alert: Alert,
        window: Window?,
        responseHandler handleResponse: @escaping (Int) -> Void
    ) {
        guard let window = window ?? Self.mainWindow else {
            assertionFailure("Could not find window in which to display alert")
            return
        }

        for (index, action) in alert.actions.enumerated() {
            (action as! CustomAlertAction).handler = { handleResponse(index) }
        }
        Self.presentOnTop(alert, in: window)
    }

    /// Presents on whatever is on top, so alerts stack instead of being dropped.
    ///
    /// Presenting from the root view controller while it already presents
    /// something fails, and fails silently -- UIKit logs "already presenting"
    /// and returns. So with three alerts requested at once on one window (P5,
    /// "Show A+B+C at once") A appeared, B and C never did, and dismissing A left
    /// an empty window although both were still `isPresented`. Presenting from
    /// the top of the chain stacks them -- C on B on A -- and dismissing the top
    /// one shows the one below it, which is what #675 asks of a backend.
    ///
    /// A view controller that is mid-transition cannot present either, and
    /// three requests in one update all arrive while A is still animating in,
    /// so the next one waits for that transition to finish.
    ///
    /// 在最上層呈現,讓 alert 疊起來而不是被丟掉。
    ///
    /// root view controller 已經在呈現東西時再從它呈現,會失敗,而且是靜默失敗——UIKit 只記一行
    /// "already presenting" 就返回。因此同一個視窗同時要求三個 alert(P5 的 "Show A+B+C at once")
    /// 時 A 出現了,B 與 C 從未出現,而關掉 A 之後視窗是空的,雖然兩者仍是 `isPresented`。從鏈的最上層
    /// 呈現就會把它們疊起來——C 疊在 B 上、B 疊在 A 上——關掉最上面那一個就會露出下面那一個,那正是
    /// #675 對 backend 的要求。轉場中的 view controller 同樣不能呈現,而一次更新裡的三個要求都在 A 還在
    /// 動畫進場時抵達,所以下一個要等那段轉場結束。
    static func presentOnTop(_ alert: Alert, in window: Window) {
        guard var top = window.rootViewController else { return }
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        if let coordinator = top.transitionCoordinator {
            coordinator.animate(alongsideTransition: nil) { _ in
                presentOnTop(alert, in: window)
            }
            return
        }
        top.present(alert, animated: true)
    }

    public func dismissAlert(_ alert: Alert, window: Window?) {
        // Only one that is still up. An alert dismisses itself when one of its
        // buttons is tapped, and `isPresented` turning false then calls this
        // again; `dismiss` on an alert already gone is forwarded to whatever
        // presented it, which with stacked alerts is the alert below -- and that
        // would close the one the user is meant to see next.
        // 只處理仍在畫面上的那一個。alert 在它的按鈕被點時會自行關閉,接著 `isPresented` 變成 false
        // 又會呼叫到這裡;對一個已經不在的 alert 呼叫 `dismiss` 會被轉給呈現它的那一個,而在疊起來的
        // alert 中那是下面那一個——那會關掉使用者接下來該看到的那一個。
        //
        // Through the presenter, not `alert.dismiss`: on a view controller that is
        // itself presenting, `dismiss` closes what it presents, so closing A from
        // code while B is stacked on it would close B and leave A. UIKit cannot
        // take a view controller out of the middle of a chain, so this closes A
        // and whatever is above it.
        // 經由呈現者,而不是 `alert.dismiss`:對一個自己也在呈現東西的 view controller 呼叫 `dismiss`,
        // 關掉的是它所呈現的那一個,因此在 B 疊在 A 上時以程式關 A,會關掉 B 而留下 A。UIKit 無法從鏈的
        // 中間抽走一個 view controller,所以這會關掉 A 以及它上面的一切。
        guard let presenter = alert.presentingViewController, !alert.isBeingDismissed else {
            return
        }
        presenter.dismiss(animated: true)
    }
}
