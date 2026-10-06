import CGtk
import Foundation
import Gtk
@_spi(Backends) import SwiftCrossUI

// Five optional features GTK did not declare until 2026-10-06 -- `Cursors`,
// `ContextMenus`, `KeyEvents`, `ScrollGestures`, `WidgetSnapshots` -- while
// AppKit, UIKit and Android had all five. Each target is a `Fixed` with the
// child at the origin, the shape `TooltipContainer` already uses, so the
// feature's controller or cursor belongs to the target and two modifiers on
// one view do not overwrite each other on a shared child.
//
// GTK 在 2026-10-06 之前沒有宣告的五項選用功能——`Cursors`、`ContextMenus`、`KeyEvents`、
// `ScrollGestures`、`WidgetSnapshots`——而 AppKit、UIKit 與 Android 五項都有。每個 target 都是一個把子
// widget 放在原點的 `Fixed`,與 `TooltipContainer` 的形狀相同；如此功能的 controller 或游標屬於 target,
// 同一個 view 上的兩個 modifier 不會在共用的子 widget 上互相覆寫。

// MARK: Cursors

extension GtkBackend: BackendFeatures.Cursors {
    public func createCursorTarget(wrapping child: Widget) -> Widget {
        GtkFeatureTarget(child)
    }

    public func updateCursorTarget(_ target: Widget, cursor: Cursor, environment: EnvironmentValues) {
        // CSS cursor names, which GDK resolves on every platform it runs on.
        // CSS 游標名稱,GDK 在它支援的每個平台上都能解析。
        let name =
            switch cursor {
                case .arrow: "default"
                case .pointingHand: "pointer"
                case .crosshair: "crosshair"
                case .text: "text"
                case .resizeHorizontal: "ew-resize"
                case .resizeVertical: "ns-resize"
                case .notAllowed: "not-allowed"
            }
        gtk_widget_set_cursor_from_name(target.widgetPointer, name)
    }
}

// MARK: Context menus

extension GtkBackend: BackendFeatures.ContextMenus {
    public func createContextMenuTarget(wrapping child: Widget) -> Widget {
        let target = GtkFeatureTarget(child)
        let click = GestureClick()
        gtk_gesture_single_set_button(click.opaquePointer, guint(GDK_BUTTON_SECONDARY))
        target.addEventController(click)
        // A long press too, the touch-screen way of asking for a context menu.
        // 也接受長按，那是觸控螢幕要求內容選單的方式。
        target.addEventController(GestureLongPress())
        return target
    }

    public func updateContextMenuTarget(
        _ target: Widget,
        menu: ResolvedMenu,
        environment: EnvironmentValues
    ) {
        let target = target as! GtkFeatureTarget
        // A fresh popover for each showing, as `Menu` does on this backend:
        // one popover kept and shown again opened once and never again
        // (measured on GtkBackend on macOS, 2026-10-06; `popUpAtWidget` parents
        // it to the target each time). The finished one is unparented on the next turn of the
        // main loop, after its item's action has run.
        // 每次顯示都用新的 popover,與本 backend 上的 `Menu` 相同：保留同一個 popover 再次顯示時，只開了一次就再也
        // 不開(2026-10-06 在 macOS 的 GtkBackend 上實測;`popUpAtWidget` 每次都把它掛到 target 底下)。用完的那個在主迴圈下一輪、其項目的
        // 動作執行之後才 unparent。
        let show: (Double, Double) -> Void = { [weak self, weak target] x, y in
            guard let self, let target, environment.isEnabled else { return }
            let popover = self.createPopoverMenu()
            self.updatePopoverMenu(popover, content: menu, environment: environment)
            target.contextMenu = popover
            self.showPopoverMenu(popover, at: SIMD2(Int(x), Int(y)), relativeTo: target) {
                [weak self] in
                self?.runInMainThread {
                    gtk_widget_unparent(popover.widgetPointer)
                    if target.contextMenu === popover { target.contextMenu = nil }
                }
            }
        }
        for controller in target.eventControllers {
            if let click = controller as? GestureClick {
                click.pressed = { _, _, x, y in show(x, y) }
            } else if let press = controller as? GestureLongPress {
                press.pressed = { _, x, y in show(x, y) }
            }
        }
    }
}

// MARK: Key events

extension GtkBackend: BackendFeatures.KeyEvents {
    public func createKeyEventTarget(wrapping child: Widget) -> Widget {
        let target = GtkFeatureTarget(child)
        gtk_widget_set_focusable(target.widgetPointer, 1)
        target.addEventController(EventControllerKey())
        // Focus when shown, as AppKitBackend claims first responder: a key
        // handler that waits for a click before it hears anything looks
        // like one that never works.
        // 顯示時取得焦點，與 AppKitBackend 取得 first responder 相同：要先點一下才聽得到按鍵的處理器，
        // 看起來就像從來不會動。
        claimFocusWhenMapped(target, attemptsLeft: 20)
        return target
    }

    /// Grabs focus once the target is on screen, retrying on the main loop
    /// until it is mapped (a target is created before its window shows).
    /// 目標上了螢幕就取得焦點；在主迴圈上重試，直到它被 map(target 在視窗顯示前就已建立)。
    private func claimFocusWhenMapped(_ target: GtkFeatureTarget, attemptsLeft: Int) {
        runInMainThread { [weak self, weak target] in
            guard let self, let target, attemptsLeft > 0 else { return }
            if gtk_widget_get_mapped(target.widgetPointer) != 0 {
                if target.keyEventsEnabled { gtk_widget_grab_focus(target.widgetPointer) }
            } else {
                self.claimFocusWhenMapped(target, attemptsLeft: attemptsLeft - 1)
            }
        }
    }

    public func updateKeyEventTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        onKey: @escaping (KeyPress) -> Void
    ) {
        let target = target as! GtkFeatureTarget
        target.keyEventsEnabled = environment.isEnabled
        let controller =
            target.eventControllers.first { $0 is EventControllerKey } as! EventControllerKey
        controller.keyPressed = { [weak target] _, keyval, keycode, state in
            guard let target, target.keyEventsEnabled else { return false }
            let isRepeat = !target.pressedKeycodes.insert(keycode).inserted
            return Self.report(keyval, state, phase: isRepeat ? .repeat : .down, onKey)
        }
        controller.keyReleased = { [weak target] _, keyval, keycode, state in
            guard let target, target.keyEventsEnabled else { return }
            target.pressedKeycodes.remove(keycode)
            _ = Self.report(keyval, state, phase: .up, onKey)
        }
    }

    /// One key event as a `KeyPress`. A modifier key alone reports `key: nil`
    /// with the modifiers as they are after the event, as AppKit's
    /// `flagsChanged` does; GDK hands over the state from before it.
    /// 把一個按鍵事件轉成 `KeyPress`。單獨的修飾鍵回報 `key: nil`,修飾鍵狀態為事件之後的狀態，與 AppKit
    /// 的 `flagsChanged` 相同;GDK 交來的是事件之前的狀態。
    static func report(
        _ keyval: UInt,
        _ state: GdkModifierType,
        phase: KeyPress.Phase,
        _ onKey: (KeyPress) -> Void
    ) -> Bool {
        var modifiers = eventModifiers(from: state)
        if let modifier = modifierKey(keyval) {
            if phase == .up { modifiers.remove(modifier) } else { modifiers.insert(modifier) }
            onKey(KeyPress(key: nil, characters: "", modifiers: modifiers, phase: phase))
            return true
        }
        let scalar = gdk_keyval_to_unicode(guint(keyval))
        let characters = scalar > 0 ? Unicode.Scalar(scalar).map { String($0) } ?? "" : ""
        let key: KeyEquivalent? =
            namedKey(keyval) ?? characters.first.map { KeyEquivalent($0) }
        guard let key else { return false }
        onKey(KeyPress(key: key, characters: characters, modifiers: modifiers, phase: phase))
        return true
    }

    /// Control is `.control`, Super and Meta are `.command`, Alt is `.option`.
    /// Reported as pressed, not translated the way shortcuts are (where
    /// `.command` becomes Control): an app reading key events asked what was
    /// held down.
    /// Control 是 `.control`,Super 與 Meta 是 `.command`,Alt 是 `.option`。照實回報按下的鍵，不像快捷鍵那樣
    /// 轉換(那裡 `.command` 會變成 Control):讀取按鍵事件的 app 問的是「按住了什麼」。
    static func eventModifiers(from state: GdkModifierType) -> EventModifiers {
        var modifiers: EventModifiers = []
        if state.rawValue & GDK_CONTROL_MASK.rawValue != 0 { modifiers.insert(.control) }
        if state.rawValue & GDK_SHIFT_MASK.rawValue != 0 { modifiers.insert(.shift) }
        if state.rawValue & GDK_ALT_MASK.rawValue != 0 { modifiers.insert(.option) }
        if state.rawValue & (GDK_SUPER_MASK.rawValue | GDK_META_MASK.rawValue) != 0 {
            modifiers.insert(.command)
        }
        return modifiers
    }

    static func modifierKey(_ keyval: UInt) -> EventModifiers? {
        switch Int32(keyval) {
            case GDK_KEY_Shift_L, GDK_KEY_Shift_R: .shift
            case GDK_KEY_Control_L, GDK_KEY_Control_R: .control
            case GDK_KEY_Alt_L, GDK_KEY_Alt_R: .option
            case GDK_KEY_Super_L, GDK_KEY_Super_R, GDK_KEY_Meta_L, GDK_KEY_Meta_R: .command
            default: nil
        }
    }

    static func namedKey(_ keyval: UInt) -> KeyEquivalent? {
        switch Int32(keyval) {
            case GDK_KEY_Up: .upArrow
            case GDK_KEY_Down: .downArrow
            case GDK_KEY_Left: .leftArrow
            case GDK_KEY_Right: .rightArrow
            case GDK_KEY_Escape: .escape
            case GDK_KEY_BackSpace: .delete
            case GDK_KEY_Delete: .deleteForward
            case GDK_KEY_Home: .home
            case GDK_KEY_End: .end
            case GDK_KEY_Page_Up: .pageUp
            case GDK_KEY_Page_Down: .pageDown
            case GDK_KEY_Clear: .clear
            case GDK_KEY_Tab, GDK_KEY_ISO_Left_Tab: .tab
            case GDK_KEY_Return, GDK_KEY_KP_Enter: .return
            case GDK_KEY_space: .space
            default: nil
        }
    }
}

// MARK: Scroll gestures

extension GtkBackend: BackendFeatures.ScrollGestures {
    public func createScrollGestureTarget(wrapping child: Widget) -> Widget {
        let target = GtkFeatureTarget(child)
        target.addEventController(
            EventControllerScroll(flags: GTK_EVENT_CONTROLLER_SCROLL_BOTH_AXES)
        )
        return target
    }

    public func updateScrollGestureTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (ScrollGestureValue) -> Void,
        onEnd: @escaping (ScrollGestureValue) -> Void
    ) {
        let target = target as! GtkFeatureTarget
        let controller =
            target.eventControllers.first { $0 is EventControllerScroll } as! EventControllerScroll
        // A touchpad reports begin and end; a wheel reports neither, so each
        // notch is a gesture of its own -- AppKitBackend's rule for an event
        // with no phase. GTK's dx/dy are already in the content's direction,
        // which is what AppKit reaches by negating NSEvent's deltas.
        // 觸控板會回報開始與結束；滾輪兩者都不回報，因此每一格都是一個獨立的手勢——AppKitBackend 對沒有階段的
        // 事件的規則。GTK 的 dx/dy 已經是內容的方向，AppKit 是把 NSEvent 的 delta 取負號才得到的。
        controller.scrollBegin = { [weak target] _ in
            target?.scrollTranslation = .zero
            target?.isScrolling = true
        }
        controller.scroll = { [weak target] controller, dx, dy in
            guard let target, environment.isEnabled else { return false }
            let isPrecise = controller.unitIsSurface
            let delta = SIMD2(dx, dy) * (isPrecise ? 1 : Self.pointsPerScrollLine)
            if !target.isScrolling { target.scrollTranslation = .zero }
            target.scrollTranslation += delta
            let value = ScrollGestureValue(
                delta: delta,
                translation: target.scrollTranslation,
                isPrecise: isPrecise
            )
            onChange(value)
            if !target.isScrolling {
                onEnd(ScrollGestureValue(delta: .zero, translation: value.translation, isPrecise: isPrecise))
            }
            return true
        }
        controller.scrollEnd = { [weak target] controller in
            guard let target, target.isScrolling else { return }
            target.isScrolling = false
            onEnd(
                ScrollGestureValue(
                    delta: .zero,
                    translation: target.scrollTranslation,
                    isPrecise: controller.unitIsSurface
                )
            )
        }
    }

    /// Points per wheel notch, AppKitBackend's figure.
    /// 每一格滾輪的點數，與 AppKitBackend 相同。
    static let pointsPerScrollLine: Double = 16
}

// MARK: Widget snapshots

extension GtkBackend: BackendFeatures.WidgetSnapshots {
    /// The widget rendered NOW through its window's own renderer, read back
    /// as premultiplied RGBA -- the layout AppKitBackend produces. A widget
    /// that is not in a realised window has no renderer and no pixels: `nil`.
    /// 以 widget 所在視窗自己的 renderer **現在**繪製，讀回成 premultiplied RGBA——與 AppKitBackend 產出的
    /// 排列相同。不在已 realize 之視窗中的 widget 沒有 renderer、也沒有像素：回傳 `nil`。
    public func snapshotWidget(_ widget: Widget) -> WidgetSnapshot? {
        Self.snapshot(of: widget)
    }

    /// The same, without a backend instance: it needs only the widget's
    /// window. Public so a test can read back any widget it reached through
    /// `.inspect`.
    /// 同上，但不需要 backend 實例：只需要 widget 所在的視窗。公開，讓測試能讀回任何經由 `.inspect` 取得的 widget。
    public static func snapshot(of widget: Widget) -> WidgetSnapshot? {
        let width = Int(gtk_widget_get_width(widget.widgetPointer))
        let height = Int(gtk_widget_get_height(widget.widgetPointer))
        guard width > 0, height > 0,
            let native = gtk_widget_get_native(widget.widgetPointer),
            let renderer = gtk_native_get_renderer(native)
        else { return nil }

        let paintable = gtk_widget_paintable_new(widget.widgetPointer)
        defer { g_object_unref(UnsafeMutableRawPointer(paintable)) }
        let snapshot = gtk_snapshot_new()
        gdk_paintable_snapshot(paintable, snapshot, Double(width), Double(height))
        guard let node = gtk_snapshot_free_to_node(snapshot) else { return nil }
        defer { gsk_render_node_unref(node) }
        guard let texture = gsk_renderer_render_texture(renderer, node, nil) else { return nil }
        defer { g_object_unref(UnsafeMutableRawPointer(texture)) }

        let textureWidth = Int(gdk_texture_get_width(texture))
        let textureHeight = Int(gdk_texture_get_height(texture))
        var rgba = [UInt8](repeating: 0, count: textureWidth * textureHeight * 4)
        let downloader = gdk_texture_downloader_new(texture)
        defer { gdk_texture_downloader_free(downloader) }
        gdk_texture_downloader_set_format(downloader, GDK_MEMORY_R8G8B8A8_PREMULTIPLIED)
        rgba.withUnsafeMutableBufferPointer { buffer in
            gdk_texture_downloader_download_into(downloader, buffer.baseAddress, gsize(textureWidth * 4))
        }
        return WidgetSnapshot(width: textureWidth, height: textureHeight, rgbaData: rgba)
    }
}

/// The wrapper every target above uses.
/// 上方每個 target 所用的包裝。
final class GtkFeatureTarget: Fixed {
    var contextMenu: Gtk.PopoverMenu?
    var keyEventsEnabled = true
    var pressedKeycodes: Set<UInt> = []
    var scrollTranslation = SIMD2<Double>(0, 0)
    var isScrolling = false

    init(_ child: Widget) {
        super.init()
        put(child, x: 0, y: 0)
    }
}
