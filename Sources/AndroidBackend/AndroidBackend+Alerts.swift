import AndroidKit
@_spi(Backends) import SwiftCrossUI

extension AndroidBackend: BackendFeatures.Alerts {
    public typealias Alert = AlertFragment

    public func createAlert() -> AlertFragment {
        AlertFragment(environment: Self.env)
    }

    public func updateAlert(
        _ alert: AlertFragment,
        title: String,
        actionLabels: [String],
        environment: EnvironmentValues
    ) {
        alert.update(title, actionLabels)
    }

    public func showAlert(
        _ alert: AlertFragment,
        window: Window?,
        responseHandler handleResponse: @escaping (Int) -> Void
    ) {
        let action = SwiftAction(environment: Self.env) {
            let index = alert.getButtonIndex()
            handleResponse(Int(index))
        }

        alert.setAction(action)
        // The alert's window's activity: from a later window, its own
        // ScuiWindowActivity, so the alert shows over that window (2026-10-07).
        // alert 所屬視窗的 activity:來自之後的視窗時是它自己的 ScuiWindowActivity,讓 alert 顯示在那個視窗上。
        let fragmentActivity = presentingActivity(for: window).as(FragmentActivity.self)!
        alert.show(fragmentActivity.getSupportFragmentManager(), "AlertFragment")
    }

    public func dismissAlert(_ alert: AlertFragment, window: Window?) {
        alert.dismiss()
    }
}
