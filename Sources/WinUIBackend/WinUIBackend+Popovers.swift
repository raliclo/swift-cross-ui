@_spi(Backends) import SwiftCrossUI
import UWP
import WinUI
import WindowsFoundation

/// `.popover` for WinUI, built on `Flyout`.
///
/// `Flyout` rather than `Popup`. Both put content above the page, but `Popup`
/// takes raw coordinates and leaves light dismiss, placement, flipping at the
/// screen edge, the beak and the shadow to the caller. `Flyout` is the control
/// Windows itself uses for exactly this, and `showAt(_:)` takes the anchor
/// directly -- which is the parameter the whole protocol exists for.
///
/// 為 WinUI 實作的 `.popover`，建構於 `Flyout` 之上。
///
/// 選 `Flyout` 而非 `Popup`。兩者都能把內容放到頁面之上，但 `Popup` 接受的是原始座標，並把點擊
/// 外部關閉、定位、在螢幕邊緣翻轉、尖角與陰影全部留給呼叫端。`Flyout` 則是 Windows 自己就用於
/// 此事的控制項，而 `showAt(_:)` 直接接受錨點——那正是整個 protocol 之所以存在的那個參數。
extension WinUIBackend: BackendFeatures.Popovers {
    @MainActor
    public final class Popover {
        let flyout: WinUI.Flyout
        var dismissHandler: (() -> Void)?
        /// Set immediately before ``dismissPopover(_:)`` hides the flyout.
        ///
        /// `closed` fires for both user and programmatic dismissals and carries
        /// nothing to tell them apart, and the protocol requires that
        /// `onDismiss` runs only for the former. This is the same flag, for the
        /// same reason, as `Sheet.isProgrammaticDismissal` in
        /// `WinUIBackend+Sheets.swift`.
        ///
        /// 在 ``dismissPopover(_:)`` 隱藏該 flyout 之前立即設定。
        ///
        /// 使用者關閉與程式關閉都會觸發 `closed`，且它沒有攜帶任何足以區分兩者的資訊，而 protocol
        /// 要求 `onDismiss` 只在前者發生時執行。這與 `WinUIBackend+Sheets.swift` 中的
        /// `Sheet.isProgrammaticDismissal` 是同一個旗標，理由也相同。
        var isProgrammaticDismissal = false

        init(content: WinUI.FrameworkElement) {
            flyout = WinUI.Flyout()
            flyout.content = content
            flyout.closed.addHandler { [weak self] _, _ in
                guard let self else { return }
                let wasProgrammatic = self.isProgrammaticDismissal
                self.isProgrammaticDismissal = false
                guard !wasProgrammatic else { return }
                self.dismissHandler?()
            }
        }
    }

    public func createPopover(content: Widget) -> Popover {
        Popover(content: content)
    }

    public func updatePopover(
        _ popover: Popover,
        environment: EnvironmentValues,
        size: SIMD2<Int>,
        attachmentEdge: SwiftCrossUI.Edge,
        backgroundColor: SwiftCrossUI.Color.Resolved?,
        onDismiss: @escaping () -> Void
    ) {
        popover.dismissHandler = onDismiss

        popover.flyout.placement = switch attachmentEdge {
            case .top: .top
            case .bottom: .bottom
            case .leading: .left
            case .trailing: .right
        }

        if let content = popover.flyout.content as? WinUI.FrameworkElement {
            content.width = Double(size.x)
            content.height = Double(size.y)

            // Only a `Panel` has a background, and the backend's own containers
            // are panels. A cast rather than a wrapper element: inserting a Grid
            // here to hold a colour would put a second sizing container between
            // the flyout and the laid-out content, and the layout system has
            // already decided the size.
            //
            // 只有 `Panel` 才有背景，而本 backend 自己的容器就是 panel。此處採轉型而非包一層：
            // 為了承載一個顏色而在此插入一個 Grid，會在 flyout 與已完成版面的內容之間多塞一個
            // 決定尺寸的容器，而版面系統早已決定好尺寸。
            if let panel = content as? WinUI.Panel {
                if let backgroundColor {
                    panel.background = WinUI.SolidColorBrush(backgroundColor.uwpColor)
                } else {
                    try? panel.clearValue(WinUI.Panel.backgroundProperty)
                }
            }
        }

        // The presenter's own padding is left alone. WinUI's `FlyoutPresenter`
        // inserts a margin around flyout content, and removing it needs a
        // `FlyoutPresenter` `Style` -- `FlyoutBase` is a `DependencyObject`, not
        // a `FrameworkElement`, so it has no `resources` dictionary to override
        // the way `WinUIBackend+Sheets.swift` overrides `ContentDialog`'s. The
        // result is a popover slightly larger than its content, which is what a
        // Windows popover looks like anyway.
        //
        // 此處不動 presenter 自身的內距。WinUI 的 `FlyoutPresenter` 會在 flyout 內容周圍加上邊距，
        // 而要移除它需要一個 `FlyoutPresenter` 的 `Style`——`FlyoutBase` 是 `DependencyObject` 而非
        // `FrameworkElement`，因此它沒有 `resources` 字典可供覆寫，不像
        // `WinUIBackend+Sheets.swift` 覆寫 `ContentDialog` 的那樣。其結果是 popover 會比其內容略大，
        // 而 Windows 上的 popover 本來就是這個樣子。
    }

    public func showPopover(_ popover: Popover, relativeTo widget: Widget, window: Window) {
        popover.flyout.xamlRoot = window.content.xamlRoot
        do {
            try popover.flyout.showAt(widget)
        } catch {
            // Not fatal. A flyout whose anchor has left the tree throws rather
            // than crashing, and taking the process down for a popover is
            // exactly what this backend's presentation code already refuses to
            // do elsewhere -- see `presentSheetNow`.
            // 非致命。錨點已離開 tree 的 flyout 會擲出錯誤而非崩潰，而為了一個 popover 就終止行程，
            // 正是本 backend 的呈現程式碼在別處已經拒絕做的事——見 `presentSheetNow`。
            print("Error: \(error)")
        }
    }

    public func dismissPopover(_ popover: Popover) {
        popover.isProgrammaticDismissal = true
        do {
            try popover.flyout.hide()
        } catch {
            popover.isProgrammaticDismissal = false
            print("Error: \(error)")
        }
    }
}
