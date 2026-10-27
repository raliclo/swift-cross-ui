import CGtk
import Gtk
@_spi(Backends) import SwiftCrossUI

/// Pull-to-refresh on `GtkScrolledWindow`, through its `edge-overshot` signal.
///
/// GTK 4 is the one of the five toolkits here that reports the gesture
/// directly: `edge-overshot` fires when the user drags a scrolled window past
/// an edge, with the edge as its argument, and it is emitted for touch and for
/// kinetic scrolling alike. `GTK_POS_TOP` is 2.
///
/// A mouse wheel does not produce the overshoot, so a Refresh button is shown
/// as well; see `setRefreshHandler(ofScrollContainer:to:)`.
///
/// 在 `GtkScrolledWindow` 上以它的 `edge-overshot` 訊號實作下拉重新整理。
///
/// GTK 4 是此處五個 toolkit 中唯一直接回報這個手勢的:當使用者把 scrolled window 拖過某個邊緣時,
/// `edge-overshot` 會以該邊緣為引數觸發,而它對觸控與慣性捲動都會發出。`GTK_POS_TOP` 為 2。
///
/// 滑鼠滾輪不會產生 overshoot,因此同時顯示一顆 Refresh 按鈕;見 `setRefreshHandler(ofScrollContainer:to:)`。
extension GtkBackend {
    /// `GTK_POS_TOP`, from `GtkPositionType`.
    /// `GTK_POS_TOP`,來自 `GtkPositionType`。
    private static let positionTop = 2

    public func setRefreshHandler(
        ofScrollContainer scrollView: Widget,
        to handler: (@MainActor @Sendable () -> Void)?
    ) {
        guard let scrolledWindow = Self.scrolledWindow(of: scrollView) else { return }
        // A visible Refresh button as well as the overshoot, as AppKit and WinUI
        // float one in the corner: GTK emits `edge-overshot` for touch and kinetic
        // scrolling, not for a mouse wheel on content that does not overflow, and
        // P54 on GtkBackend on macOS stayed at "refreshes: 0" through two wheel
        // turns past the top (2026-10-16).
        // 除了 overshoot 之外再加一顆看得見的 Refresh 按鈕，與 AppKit、WinUI 浮在角落的那顆相同:GTK 只在觸控與
        // 慣性捲動時發出 `edge-overshot`,內容沒有溢出時的滑鼠滾輪不會;P54 在 macOS 的 GtkBackend 上經過兩次越過
        // 頂端的滾輪仍是「refreshes: 0」(2026-10-16)。
        if let container = scrollView as? ScrollContainer {
            container.setRefreshAction(handler)
        }

        guard let handler else {
            Self.refreshHandlers[ObjectIdentifier(scrolledWindow)] = nil
            return
        }

        // The closure is stored and the signal connected once. `addSignal` has
        // no counterpart that disconnects, so connecting on every update would
        // add a handler per update and fire the action as many times as the
        // scroll view had been updated -- growing without bound, and looking
        // like a refresh that runs twice, then five times, then twenty.
        // 閉包被存起來,而訊號只連接一次。`addSignal` 沒有對應的中斷連接方式,因此每次更新都連接會
        // 每更新一次就多一個 handler,並讓該動作被觸發的次數等於這個捲動視圖被更新過的次數——無上限地
        // 增長,而看起來會像是一次重新整理跑了兩次、接著五次、接著二十次。
        let key = ObjectIdentifier(scrolledWindow)
        let isFirst = Self.refreshHandlers[key] == nil
        Self.refreshHandlers[key] = handler
        guard isFirst else { return }

        // Through ``Gtk/ScrolledWindow/edgeOvershot``, not `addSignal`:
        // `addSignal` is internal to the `Gtk` module, and its overload without
        // a marshaller takes a NO-ARGUMENT callback, so `edge` could not be
        // delivered through it even with access.
        //
        // 走 ``Gtk/ScrolledWindow/edgeOvershot``，而非 `addSignal`:`addSignal` 對 `Gtk` 模組而言是
        // internal，且不帶 marshaller 的那個多載收的是**無參數** callback，因此就算存取層級允許，
        // `edge` 也送不進來。
        scrolledWindow.edgeOvershot = { _, edge in
            guard edge == Self.positionTop else { return }
            MainActor.assumeIsolated {
                Self.refreshHandlers[key]?()
            }
        }
    }

    nonisolated(unsafe) static var refreshHandlers:
        [ObjectIdentifier: @MainActor @Sendable () -> Void] = [:]
}

extension GtkBackend {
    /// The ScrolledWindow behind a scroll container widget. 捲動容器 widget 背後的 ScrolledWindow。
    static func scrolledWindow(of widget: Widget) -> ScrolledWindow? {
        (widget as? ScrollContainer)?.scrolled ?? (widget as? ScrolledWindow)
    }
}

/// A scroll view's widget: a GtkOverlay holding the ScrolledWindow, so that a
/// Refresh button can float over its top-leading corner without scrolling with
/// the content. A GtkScrolledWindow lays out only its scrolled child, so the
/// button cannot be its own child.
/// 捲動視圖的 widget:一個包著 ScrolledWindow 的 GtkOverlay,讓 Refresh 按鈕能浮在左上角、不隨內容捲動。
/// GtkScrolledWindow 只排它捲動的那個子元件，因此按鈕不能是它的子元件。
final class ScrollContainer: Widget {
    let scrolled: ScrolledWindow
    private var refreshButton: Gtk.Button?
    private var refreshAction: (@MainActor @Sendable () -> Void)?

    init(_ scrolled: ScrolledWindow) {
        self.scrolled = scrolled
        super.init(OpaquePointer(gtk_overlay_new()))
        gtk_overlay_set_child(OpaquePointer(widgetPointer), scrolled.widgetPointer)
        // Setting the parent is what registers the child's signals (Widget.parentWidget).
        // 設定 parent 才會註冊子元件的訊號(Widget.parentWidget)。
        scrolled.parentWidget = self
    }

    /// Shows the Refresh button with `action`, or removes it for nil.
    /// 以 `action` 顯示 Refresh 按鈕;nil 則移除它。
    func setRefreshAction(_ action: (@MainActor @Sendable () -> Void)?) {
        refreshAction = action
        guard action != nil else {
            if let refreshButton {
                gtk_overlay_remove_overlay(OpaquePointer(widgetPointer), refreshButton.widgetPointer)
                self.refreshButton = nil
            }
            return
        }
        guard refreshButton == nil else { return }
        let button = Gtk.Button()
        button.label = "Refresh"
        gtk_widget_set_halign(button.widgetPointer, GTK_ALIGN_START)
        gtk_widget_set_valign(button.widgetPointer, GTK_ALIGN_START)
        gtk_widget_set_margin_start(button.widgetPointer, 6)
        gtk_widget_set_margin_top(button.widgetPointer, 6)
        gtk_widget_add_css_class(button.widgetPointer, "osd")
        button.clicked = { [weak self] _ in
            let action = self?.refreshAction
            MainActor.assumeIsolated { action?() }
        }
        gtk_overlay_add_overlay(OpaquePointer(widgetPointer), button.widgetPointer)
        button.parentWidget = self
        refreshButton = button
    }
}
