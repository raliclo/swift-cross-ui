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
        let box = GestureBox(child)
        let gesture = GestureDrag()
        gesture.dragBegin = { [weak box] _, x, y in
            box?.startX = x
            box?.startY = y
        }
        gesture.dragUpdate = { [weak box] _, dx, dy in
            guard let box else { return }
            box.onDragChange?(box.dragValue(dx: dx, dy: dy))
        }
        gesture.dragEnd = { [weak box] _, dx, dy in
            guard let box else { return }
            box.onDragEnd?(box.dragValue(dx: dx, dy: dy))
        }
        box.addEventController(gesture)
        return box
    }

    public func updateDragGestureTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (DragGestureValue) -> Void,
        onEnd: @escaping (DragGestureValue) -> Void
    ) {
        guard let box = target as? GestureBox else { return }
        box.onDragChange = environment.isEnabled ? onChange : nil
        box.onDragEnd = environment.isEnabled ? onEnd : nil
    }

    public func createMagnifyGestureTarget(wrapping child: Widget) -> Widget {
        let box = GestureBox(child)
        let gesture = GestureZoom()
        gesture.scaleChanged = { [weak box] _, scale in
            guard let box else { return }
            box.lastMagnification = scale
            box.onMagnifyChange?(MagnifyGestureValue(magnification: scale))
        }
        // `GestureZoom` has no end signal of its own -- there is only
        // `scale-changed` -- so the last value is reported again on `Gesture`'s
        // own `end`, which every gesture controller inherits
        // (`Sources/Gtk/Generated/Gesture.swift:219`).
        //
        // **The version this replaces stored that closure in a box property
        // named `onSequenceEnd` and never called it**, so `onEnded` for magnify
        // and rotate could not fire at all. It compiled, and the comment above
        // it described the behaviour as though it worked.
        //
        // `GestureZoom` 自身沒有結束訊號——只有 `scale-changed`——因此最後一個值會在 `Gesture` 自身的
        // `end` 上再回報一次;那個訊號是每一個手勢控制器都繼承到的
        // (`Sources/Gtk/Generated/Gesture.swift:219`)。
        //
        // **被取代的那個版本把該 closure 存進一個名為 `onSequenceEnd` 的屬性,然後從未呼叫它**,
        // 於是 magnify 與 rotate 的 `onEnded` 根本不可能觸發。它編得過,而它上方的註解把那個行為
        // 描述得像是會動一樣。
        gesture.end = { [weak box] _, _ in
            guard let box else { return }
            box.onMagnifyEnd?(MagnifyGestureValue(magnification: box.lastMagnification))
        }
        box.addEventController(gesture)
        return box
    }

    public func updateMagnifyGestureTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (MagnifyGestureValue) -> Void,
        onEnd: @escaping (MagnifyGestureValue) -> Void
    ) {
        guard let box = target as? GestureBox else { return }
        box.onMagnifyChange = environment.isEnabled ? onChange : nil
        box.onMagnifyEnd = environment.isEnabled ? onEnd : nil
    }

    public func createRotateGestureTarget(wrapping child: Widget) -> Widget {
        let box = GestureBox(child)
        let gesture = GestureRotate()
        gesture.angleChanged = { [weak box] _, _, angleDelta in
            guard let box else { return }
            // `angle_delta`, the SECOND Double, and not negated. Both were wrong
            // until 2026-09-17, found by driving it with synthetic touch
            // (testapp/touch_gesture.zsh, a 90-degree clockwise turn on P65):
            //
            //   - It read `angle`, the absolute angle of the line between the
            //     two fingers. The log started at -4.752 -- the line's own
            //     angle, not any rotation -- climbed to -6.243, wrapped, and the
            //     gesture ENDED at -0.000 rad.
            //   - It negated, per a comment saying GTK's angle grows
            //     counter-clockwise "the same flip the AppKit side needs". That
            //     holds in AppKit's y-up coordinates. GTK's are y-down, and the
            //     absolute angle measurably INCREASED (4.75 -> 6.24) during a
            //     clockwise turn. WinUIBackend reports +1.571 rad for the same
            //     injection, so no flip here.
            //
            // **讀的是 `angle_delta`(第二個 Double),而且不取負號。** 兩者在 2026-09-17 之前都是錯的,
            // 是以合成觸控驅動時發現的(testapp/touch_gesture.zsh,在 P65 上順時針轉 90 度):
            //
            //   - 它讀的是 `angle`——兩指連線的**絕對**角度。log 從 -4.752 開始(那是連線本身的角度,
            //     不是任何旋轉量),爬到 -6.243 後繞回,手勢以 -0.000 rad 結束。
            //   - 它取了負號,依據一句「GTK 角度逆時針增加,與 AppKit 那一側需要同一次翻轉」的註解。
            //     那在 AppKit 的 y 軸向上座標中成立;GTK 是 y 軸向下,而順時針旋轉時絕對角度**實測是
            //     增加的**(4.75 → 6.24)。WinUIBackend 對同一個注入回報 +1.571 rad,所以這裡不翻轉。
            //
            // UNWRAPPED, because GTK normalises `angle_delta` into [0, 2pi).
            // Measured with a 45-degree COUNTER-clockwise turn: GTK reported
            // 5.498 rad (2pi - 0.785). WinUIBackend reports the same injection
            // as -0.772 and a 200-degree turn as 3.515 -- signed and unbounded --
            // so each step here adds the shortest signed difference from the
            // previous raw delta, and `begin` resets both.
            //
            // **展開(unwrap)**,因為 GTK 把 `angle_delta` 正規化到 [0, 2π)。以**逆時針** 45 度實測:
            // GTK 回報 5.498 rad(2π − 0.785)。WinUIBackend 對同一個注入回報 -0.772,200 度回報
            // 3.515——**有號、不設上限**——所以這裡每一步加上「與前一個原始 delta 的最短有號差」,
            // 並在 `begin` 時把兩者歸零。
            var step = angleDelta - box.lastRawAngleDelta
            if step > .pi { step -= 2 * .pi }
            if step < -.pi { step += 2 * .pi }
            box.lastRawAngleDelta = angleDelta
            box.lastRadians += step
            box.onRotateChange?(RotateGestureValue(radians: box.lastRadians))
        }
        gesture.begin = { [weak box] _, _ in
            box?.lastRadians = 0
            box?.lastRawAngleDelta = 0
        }
        gesture.end = { [weak box] _, _ in
            guard let box else { return }
            box.onRotateEnd?(RotateGestureValue(radians: box.lastRadians))
        }
        box.addEventController(gesture)
        return box
    }

    public func updateRotateGestureTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (RotateGestureValue) -> Void,
        onEnd: @escaping (RotateGestureValue) -> Void
    ) {
        guard let box = target as? GestureBox else { return }
        box.onRotateChange = environment.isEnabled ? onChange : nil
        box.onRotateEnd = environment.isEnabled ? onEnd : nil
    }
}

/// The wrapper a gesture modifier puts around its child, holding both the
/// controller and the state GTK's callbacks do not carry.
///
/// **The controller is installed ONCE, in `create`, and `update` only swaps
/// closures.** The version this replaces added a fresh controller on every
/// `update…GestureTarget` call, and update runs on every layout pass -- the same
/// defect measured on this backend's slider three days ago, where a click
/// gesture added per update reported `began=5` for one press. Nothing there
/// errored either; the count was simply five times too high.
///
/// It is a `Box` subclass rather than a `[ObjectIdentifier: State]` side table
/// for a second reason: the table this replaces was `static`, was never pruned,
/// and `ObjectIdentifier` is a pointer value that GLib will hand out again after
/// a widget is freed -- so a long-running app would eventually read one widget's
/// drag origin out of another's entry.
///
/// 手勢 modifier 包在其 child 外面的那個 wrapper,同時持有控制器,以及 GTK 的 callback 不帶的那些狀態。
///
/// **控制器只在 `create` 中安裝一次,而 `update` 只換掉 closure。** 被取代的版本在每一次
/// `update…GestureTarget` 呼叫時新增一個控制器,而 update 每一次 layout pass 都會跑——這正是三天前在
/// 本 backend 的 slider 上量到的同一個缺陷:一個逐 update 新增的 click gesture,讓「按一次」回報成
/// `began=5`。那裡同樣沒有任何東西報錯;只是那個數字大了五倍。
///
/// 它是 `Box` 的子類別、而非一張 `[ObjectIdentifier: State]` 的側表,還有第二個理由:被取代的那張表是
/// `static`、從不清理,而 `ObjectIdentifier` 是一個指標值——GLib 在一個 widget 被釋放後會再次發出同一個
/// 位址,於是一支長時間運行的 app 終將從別人的條目裡讀出某個 widget 的拖曳起點。
final class GestureBox: Box {
    var startX = 0.0
    var startY = 0.0
    var lastMagnification = 1.0
    var lastRadians = 0.0
    /// GTK's own `angle_delta` from the previous `angle-changed`, kept to
    /// unwrap the next one. See `createRotateGestureTarget`.
    /// 上一次 `angle-changed` 時 GTK 的 `angle_delta`,用來展開下一次。見 `createRotateGestureTarget`。
    var lastRawAngleDelta = 0.0

    var onDragChange: ((DragGestureValue) -> Void)?
    var onDragEnd: ((DragGestureValue) -> Void)?
    var onMagnifyChange: ((MagnifyGestureValue) -> Void)?
    var onMagnifyEnd: ((MagnifyGestureValue) -> Void)?
    var onRotateChange: ((RotateGestureValue) -> Void)?
    var onRotateEnd: ((RotateGestureValue) -> Void)?

    init(_ child: Widget) {
        // The raw constructor, not `Box.init(orientation:spacing:)`, which is a
        // convenience initialiser and so cannot be reached through `super` --
        // the same note DateWheel and TimeRow carry.
        // 使用原生建構式而非 `Box.init(orientation:spacing:)`——後者是 convenience initialiser，
        // 無法透過 `super` 呼叫。這與 DateWheel 和 TimeRow 所記的是同一件事。
        super.init(gtk_box_new(GTK_ORIENTATION_VERTICAL, 0))
        add(child)
    }

    /// `drag-update` reports the movement SINCE the drag began, not a position,
    /// which is why the start point is captured at `drag-begin` and added back.
    /// `drag-update` 回報的是「自拖曳開始以來的移動量」而不是一個位置——這正是此處在 `drag-begin`
    /// 記下起點、之後再加回去的原因。
    func dragValue(dx: Double, dy: Double) -> DragGestureValue {
        DragGestureValue(
            startLocation: SIMD2(startX, startY),
            location: SIMD2(startX + dx, startY + dy)
        )
    }
}
