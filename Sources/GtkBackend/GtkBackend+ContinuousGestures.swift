import CGtk
import Gtk
import SwiftCrossUI

extension GtkBackend: BackendFeatures.DragGestures,
    BackendFeatures.MagnifyGestures,
    BackendFeatures.RotateGestures
{
    /// GTK's own gesture controllers, through the classes the Windows side
    /// generated for #32.
    ///
    /// **NOT COMPILED HERE (2026-09-10).** This machine has no GTK. The three
    /// controllers exist as `Sources/Gtk/Generated/Gesture{Drag,Zoom,Rotate}.swift`
    /// and their signal shapes were read from those files rather than guessed:
    /// `dragBegin`/`dragUpdate`/`dragEnd` each carry two `Double` OFFSETS,
    /// `scaleChanged` carries a factor, `angleChanged` carries an angle and a
    /// delta. What to check first is the offsets: `drag-update` gives the
    /// movement SINCE the drag began, not a position, which is why the start
    /// point is captured at `drag-begin` and added back here.
    ///
    /// GTK 自身的手勢控制器，透過 Windows 端為 #32 產生的那三個類別。
    ///
    /// **此處未編譯(2026-09-10)。** 這台機器沒有 GTK。那三個控制器以
    /// `Sources/Gtk/Generated/Gesture{Drag,Zoom,Rotate}.swift` 存在，而它們的 signal 形狀是**讀**那些
    /// 檔案得知的、不是猜的:`dragBegin`/`dragUpdate`/`dragEnd` 各帶兩個 `Double` **位移**、
    /// `scaleChanged` 帶一個倍率、`angleChanged` 帶一個角度與一個差量。首先要查的是那些位移:
    /// `drag-update` 給的是「自拖曳開始以來的移動量」而不是一個位置——這正是此處在 `drag-begin` 記下
    /// 起點、之後再加回去的原因。
    public func createDragGestureTarget(wrapping child: Widget) -> Widget {
        wrap(child)
    }

    public func updateDragGestureTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (DragGestureValue) -> Void,
        onEnd: @escaping (DragGestureValue) -> Void
    ) {
        let box = GtkGestureState.of(target)
        box.reset(on: target)
        guard environment.isEnabled else { return }

        let gesture = GestureDrag()
        gesture.dragBegin = { _, x, y in
            box.startX = x
            box.startY = y
        }
        gesture.dragUpdate = { _, dx, dy in
            onChange(box.dragValue(dx: dx, dy: dy))
        }
        gesture.dragEnd = { _, dx, dy in
            onEnd(box.dragValue(dx: dx, dy: dy))
        }
        target.addEventController(gesture)
        box.controller = gesture
    }

    public func createMagnifyGestureTarget(wrapping child: Widget) -> Widget {
        wrap(child)
    }

    public func updateMagnifyGestureTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (MagnifyGestureValue) -> Void,
        onEnd: @escaping (MagnifyGestureValue) -> Void
    ) {
        let box = GtkGestureState.of(target)
        box.reset(on: target)
        guard environment.isEnabled else { return }

        let gesture = GestureZoom()
        gesture.scaleChanged = { _, scale in
            box.lastMagnification = scale
            onChange(MagnifyGestureValue(magnification: scale))
        }
        target.addEventController(gesture)
        box.controller = gesture
        // `GestureZoom` has no end signal of its own -- there is only
        // `scale-changed` -- so the last value is reported again when the
        // controller's sequence ends. Stated here because "magnify never calls
        // onEnded on GTK" would otherwise be discovered rather than known.
        // `GestureZoom` 自身沒有結束訊號——只有 `scale-changed`——因此在該控制器的序列結束時，會把
        // 最後一個值再回報一次。此處寫明，否則「GTK 上的 magnify 從不呼叫 onEnded」這件事就會變成
        // 被人發現的，而不是被人知道的。
        box.onSequenceEnd = { onEnd(MagnifyGestureValue(magnification: box.lastMagnification)) }
    }

    public func createRotateGestureTarget(wrapping child: Widget) -> Widget {
        wrap(child)
    }

    public func updateRotateGestureTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (RotateGestureValue) -> Void,
        onEnd: @escaping (RotateGestureValue) -> Void
    ) {
        let box = GtkGestureState.of(target)
        box.reset(on: target)
        guard environment.isEnabled else { return }

        let gesture = GestureRotate()
        gesture.angleChanged = { _, angle, _ in
            // GTK's angle grows counter-clockwise and this package reports
            // clockwise positive, the same flip the AppKit side needs.
            // GTK 的角度逆時針增加，而本套件回報順時針為正——與 AppKit 那一側需要的是同一次翻轉。
            box.lastRadians = -angle
            onChange(RotateGestureValue(radians: -angle))
        }
        target.addEventController(gesture)
        box.controller = gesture
        box.onSequenceEnd = { onEnd(RotateGestureValue(radians: box.lastRadians)) }
    }

    private func wrap(_ child: Widget) -> Widget {
        let box = Gtk.Box(orientation: .vertical, spacing: 0)
        box.add(child)
        return box
    }
}

/// Per-target gesture state, because GTK's callbacks carry offsets rather than
/// positions and something has to remember where the drag started.
///
/// 逐目標的手勢狀態——因為 GTK 的 callback 帶的是位移而非位置，總得有東西記住拖曳從哪裡開始。
final class GtkGestureState {
    private nonisolated(unsafe) static var states: [ObjectIdentifier: GtkGestureState] = [:]

    var startX = 0.0
    var startY = 0.0
    var lastMagnification = 1.0
    var lastRadians = 0.0
    var controller: EventController?
    var onSequenceEnd: (() -> Void)?

    static func of(_ widget: Gtk.Widget) -> GtkGestureState {
        let key = ObjectIdentifier(widget)
        if let existing = states[key] { return existing }
        let state = GtkGestureState()
        states[key] = state
        return state
    }

    func reset(on widget: Gtk.Widget) {
        controller = nil
        onSequenceEnd = nil
    }

    func dragValue(dx: Double, dy: Double) -> DragGestureValue {
        DragGestureValue(
            startLocation: SIMD2(startX, startY),
            location: SIMD2(startX + dx, startY + dy)
        )
    }
}
