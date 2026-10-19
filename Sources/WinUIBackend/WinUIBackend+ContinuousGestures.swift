import Foundation
import SwiftCrossUI
import WinAppSDK
import WinUI

extension WinUIBackend: BackendFeatures.DragGestures,
    BackendFeatures.MagnifyGestures,
    BackendFeatures.RotateGestures
{
    /// WinUI's manipulation events, which report all three at once.
    ///
    /// **One event stream for three gestures, unlike everywhere else.** A
    /// `UIElement` with `manipulationMode` set raises `ManipulationDelta`
    /// carrying translation, scale AND rotation together; the three
    /// implementations here differ only in which field they read and which mode
    /// they ask for. Asking for only the mode that is wanted matters: with
    /// `.all`, a one-finger drag also produces scale noise.
    ///
    /// ~~**NOT COMPILED HERE (2026-09-10).**~~ Compiled since, and DRIVEN
    /// 2026-09-17 with real synthetic touch (`testapp/touch_gesture.zsh`)
    /// against P65: drag (180, 20) reported translation (173, 23); a pinch from
    /// a 40 px gap to 160 px reported magnification 3.478; a 90-degree rotate
    /// reported 1.531 rad. Manipulations need touch or pen -- a mouse never
    /// raises them -- which is why the earlier mouse-only action files could
    /// not have driven any of this.
    ///
    /// **"A mouse never raises them" is wrong (2026-10-19).** A mouse drag sent as
    /// SendInput moves raises ManipulationDelta like a finger: P108's card was
    /// thrown with the mouse, translation 2.5 ... 47.2 over ten moves. What raised
    /// nothing was Win32Synthesiser moving with `SetCursorPos` while the button
    /// was down, which places the cursor without any pointer input. It now moves
    /// with SendInput while a button is held.
    /// **「滑鼠永遠不會觸發」是錯的(2026-10-19)。** 以 SendInput 移動送出的滑鼠拖曳會像手指一樣觸發
    /// ManipulationDelta:P108 的卡片用滑鼠拋出,十次移動 translation 由 2.5 到 47.2。什麼都沒觸發的,是
    /// Win32Synthesiser 在按住時用 `SetCursorPos` 移動——那只擺放游標，不產生任何指標輸入。現在按住時改用 SendInput。
    ///
    /// WinUI 的 manipulation 事件，它一次回報全部三者。
    ///
    /// **三種手勢共用一條事件流，這與其他每一處都不同。** 一個設定了 `manipulationMode` 的
    /// `UIElement` 會發出 `ManipulationDelta`，其中同時帶著位移、縮放**與**旋轉;此處的三份實作，
    /// 差別只在於各自讀哪個欄位、以及要求哪一種模式。只要求「所要的那個模式」是有意義的:若用
    /// `.all`，一次單指拖曳也會產生縮放的雜訊。
    ///
    /// ~~**此處未編譯(2026-09-10)。**~~ 之後已編譯,並於 2026-09-17 以真實的合成觸控
    /// (`testapp/touch_gesture.zsh`)對 P65 **驅動**:拖曳 (180, 20) 回報 translation (173, 23);
    /// 間距 40 px → 160 px 的捏合回報 magnification 3.478;90 度旋轉回報 1.531 rad。manipulation 需要
    /// 觸控或筆——滑鼠從不觸發——這就是先前那些只用滑鼠的動作檔不可能驅動其中任何一項的原因。
    public func createDragGestureTarget(wrapping child: Widget) -> Widget {
        // `ManipulationModes` is a `typealias` to a C enum with `static var`
        // members bolted on -- not a Swift `OptionSet` -- so `.union` does not
        // exist and the combination is a bitwise or on `rawValue`. Measured by
        // building: "value of type 'ManipulationModes' has no member 'union'".
        // `ManipulationModes` 是一個 `typealias` 指向 C enum、再外掛上 `static var` 成員——
        // **不是** Swift 的 `OptionSet`——因此 `.union` 並不存在,組合的方式是對 `rawValue`
        // 做位元或。以建置量得:「value of type 'ManipulationModes' has no member 'union'」。
        ManipulationTarget(
            child: child,
            mode: ManipulationModes(
                rawValue: ManipulationModes.translateX.rawValue
                    | ManipulationModes.translateY.rawValue
            )
        )
    }

    public func updateDragGestureTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (DragGestureValue) -> Void,
        onEnd: @escaping (DragGestureValue) -> Void
    ) {
        let target = target as! ManipulationTarget
        guard environment.isEnabled else {
            target.clearHandlers()
            return
        }
        target.onDelta = { (cumulative: WinAppSDK.ManipulationDelta, start: SIMD2<Double>) in
            onChange(
                DragGestureValue(
                    startLocation: start,
                    location: start + SIMD2(
                        Double(cumulative.translation.x), Double(cumulative.translation.y)
                    )
                )
            )
        }
        target.onCompleted = { (cumulative: WinAppSDK.ManipulationDelta, start: SIMD2<Double>) in
            onEnd(
                DragGestureValue(
                    startLocation: start,
                    location: start + SIMD2(
                        Double(cumulative.translation.x), Double(cumulative.translation.y)
                    )
                )
            )
        }
        target.onMouseDrag = { start, location, ended in
            let value = DragGestureValue(startLocation: start, location: location)
            if ended { onEnd(value) } else { onChange(value) }
        }
    }

    public func createMagnifyGestureTarget(wrapping child: Widget) -> Widget {
        ManipulationTarget(child: child, mode: .scale)
    }

    public func updateMagnifyGestureTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (MagnifyGestureValue) -> Void,
        onEnd: @escaping (MagnifyGestureValue) -> Void
    ) {
        let target = target as! ManipulationTarget
        guard environment.isEnabled else {
            target.clearHandlers()
            return
        }
        target.onDelta = { cumulative, _ in
            onChange(MagnifyGestureValue(magnification: Double(cumulative.scale)))
        }
        target.onCompleted = { cumulative, _ in
            onEnd(MagnifyGestureValue(magnification: Double(cumulative.scale)))
        }
    }

    public func createRotateGestureTarget(wrapping child: Widget) -> Widget {
        ManipulationTarget(child: child, mode: .rotate)
    }

    public func updateRotateGestureTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (RotateGestureValue) -> Void,
        onEnd: @escaping (RotateGestureValue) -> Void
    ) {
        let target = target as! ManipulationTarget
        guard environment.isEnabled else {
            target.clearHandlers()
            return
        }
        target.onDelta = { cumulative, _ in
            onChange(RotateGestureValue(radians: radians(cumulative.rotation)))
        }
        target.onCompleted = { cumulative, _ in
            onEnd(RotateGestureValue(radians: radians(cumulative.rotation)))
        }
    }
}

/// A `Grid` that owns its manipulation handlers, registered exactly once.
/// (A `Grid` rather than the `Border` this used to wrap with, because `Border`
/// is `final` in the binding and a subclass is what holds the state.)
/// (用 `Grid` 而不是原本包裹用的 `Border`,因為 `Border` 在綁定中是 `final`,而持有狀態需要子類別。)
///
/// **The handlers used to be added in `update*GestureTarget`, which runs on
/// every update, and nothing ever removed them.** Measured 2026-09-17 on P65
/// with synthetic touch: ONE drag logged `drag ended` 12 times, the pinch after
/// it logged `magnify ENDED` 18 times, and the rotate after that 23 times -- the
/// count growing with each gesture because each gesture's own updates added
/// more. Same shape as the slider that reported `began=5`. Now the events are
/// subscribed in `init` and `update` only swaps the closures they call.
///
/// Disabling also clears the closures. Before, the `isEnabled` guard returned
/// early and left every previously added handler live, so a disabled gesture
/// kept firing.
///
/// **`startLocation` was hard-coded to zero**, and `location` was the raw
/// translation, so WinUI reported "start (0, 0)" for every drag while AppKit
/// reports where the finger went down. The start now comes from
/// `ManipulationStarted.position`.
///
/// 一個自己持有 manipulation handler、且**只註冊一次**的 `Border`。
///
/// **handler 以前是在 `update*GestureTarget` 裡加上的——那個方法每次更新都會執行——而且沒有任何東西
/// 移除它們。** 2026-09-17 以合成觸控在 P65 實測:**一次**拖曳印了 12 次 `drag ended`,之後的捏合印了
/// 18 次 `magnify ENDED`,再之後的旋轉印了 23 次——次數隨每個手勢遞增,因為每個手勢自己的更新又加掛了
/// 更多。與回報 `began=5` 的 slider 同一個形狀。現在事件在 `init` 中訂閱,`update` 只替換它們呼叫的
/// 閉包。停用時也會清掉閉包;以前 `isEnabled` 的 guard 提早 return,讓先前加上的 handler 全部保持
/// 有效,於是被停用的手勢仍會觸發。
///
/// **`startLocation` 以前寫死為零**,`location` 則是原始的位移量,所以 WinUI 對每次拖曳都回報
/// 「start (0, 0)」,而 AppKit 回報的是手指按下的位置。起點現在取自 `ManipulationStarted.position`。
final class ManipulationTarget: WinUI.Grid {
    typealias Handler = (WinAppSDK.ManipulationDelta, SIMD2<Double>) -> Void

    var onDelta: Handler?
    var onCompleted: Handler?
    private var startLocation: SIMD2<Double> = .zero
    /// A mouse drag's start, location and whether it ended (drag targets only).
    /// 滑鼠拖曳的起點、位置與是否結束(僅拖曳目標)。
    var onMouseDrag: ((SIMD2<Double>, SIMD2<Double>, Bool) -> Void)?

    init(child: WinUI.UIElement, mode: ManipulationModes) {
        super.init()
        children.append(child)
        manipulationMode = mode

        _ = manipulationStarted.addHandler { [weak self] _, args in
            guard let self, let args, !self.isMouseHandledElsewhere(args.pointerDeviceType) else { return }
            self.startLocation = SIMD2(Double(args.position.x), Double(args.position.y))
        }
        _ = manipulationDelta.addHandler { [weak self] _, args in
            guard let self, let args, !self.isMouseHandledElsewhere(args.pointerDeviceType) else { return }
            self.onDelta?(args.cumulative, self.startLocation)
        }
        _ = manipulationCompleted.addHandler { [weak self] _, args in
            guard let self, let args, !self.isMouseHandledElsewhere(args.pointerDeviceType) else { return }
            self.onCompleted?(args.cumulative, self.startLocation)
        }
        // A mouse drag goes through pointer events instead. A mouse does raise
        // manipulations when the input is real (SendInput), but WinUI delivers
        // them late and in batches, every 47-78 ms: P108's throw read a release
        // velocity of 0 pt/s on most runs, because SwiftCrossUI measures it over
        // the last 0.1 s of points as they arrive and none had arrived
        // (2026-10-19). Pointer events arrive with each move. Touch and pen keep
        // the manipulation path, and a mouse is not reported through both.
        // 滑鼠拖曳改走 pointer 事件。真正的滑鼠輸入(SendInput)確實會觸發 manipulation,但 WinUI 會延遲並成批送出，
        // 每 47 到 78 ms 一次:P108 的拋擲多數時候讀到放開速度 0 pt/s,因為 SwiftCrossUI 以實際到達的最後 0.1 秒的點
        // 計算速度，而那段時間沒有點到達(2026-10-19)。pointer 事件每次移動都會到。觸控與觸控筆仍走 manipulation,
        // 滑鼠不會兩條路都回報。
        _ = pointerPressed.addHandler { [weak self] _, args in
            self?.mousePressed(args)
        }
        _ = pointerMoved.addHandler { [weak self] _, args in
            self?.mouseMoved(args)
        }
        _ = pointerReleased.addHandler { [weak self] _, args in
            self?.mouseReleased(args)
        }
        _ = pointerCaptureLost.addHandler { [weak self] _, _ in
            self?.mouseCaptureLost()
        }
    }

    /// The mouse drag in progress: where it started (in this target and against
    /// the window's content) and where it is. A press and release without
    /// movement is a click, not a drag, and reports nothing.
    /// 進行中的滑鼠拖曳：起點(相對於本目標與相對於視窗內容)與目前位置。沒有移動的按下與放開是點擊，不是拖曳，不回報。
    private struct MouseDrag {
        var start: SIMD2<Double>
        var rootStart: SIMD2<Double>
        var location: SIMD2<Double>
        var moved = false
    }

    private var mouseDrag: MouseDrag?

    /// Whether a mouse manipulation is left to the pointer path.
    /// 滑鼠的 manipulation 是否交給 pointer 路徑處理。
    private func isMouseHandledElsewhere(_ device: WinAppSDK.PointerDeviceType) -> Bool {
        device == .mouse && onMouseDrag != nil
    }

    private func point(_ args: PointerRoutedEventArgs?, against element: WinUI.UIElement?) -> SIMD2<Double>? {
        guard let args, args.pointer.pointerDeviceType == .mouse,
            let point = try? args.getCurrentPoint(element)
        else { return nil }
        return SIMD2(Double(point.position.x), Double(point.position.y))
    }

    private func mousePressed(_ args: PointerRoutedEventArgs?) {
        guard onMouseDrag != nil, let args,
            let position = point(args, against: self), let root = point(args, against: nil),
            (try? args.getCurrentPoint(self))?.properties.isLeftButtonPressed == true
        else { return }
        mouseDrag = MouseDrag(start: position, rootStart: root, location: position)
        _ = try? capturePointer(args.pointer)
        args.handled = true
    }

    // Moved against the window's content, which stays put while the target
    // may move with what it drags.
    // 以視窗內容為參考計算移動——拖曳目標可能隨著被拖的東西移動，視窗內容則不動。
    private func mouseMoved(_ args: PointerRoutedEventArgs?) {
        guard var drag = mouseDrag, let args, let root = point(args, against: nil) else { return }
        drag.location = drag.start + root - drag.rootStart
        drag.moved = drag.moved || drag.location != drag.start
        mouseDrag = drag
        if drag.moved {
            onMouseDrag?(drag.start, drag.location, false)
        }
        args.handled = true
    }

    private func mouseReleased(_ args: PointerRoutedEventArgs?) {
        guard var drag = mouseDrag else { return }
        mouseDrag = nil
        if let args, let root = point(args, against: nil) {
            drag.location = drag.start + root - drag.rootStart
            drag.moved = drag.moved || drag.location != drag.start
            try? releasePointerCapture(args.pointer)
            args.handled = true
        }
        if drag.moved {
            onMouseDrag?(drag.start, drag.location, true)
        }
    }

    private func mouseCaptureLost() {
        guard let drag = mouseDrag else { return }
        mouseDrag = nil
        if drag.moved {
            onMouseDrag?(drag.start, drag.location, true)
        }
    }

    func clearHandlers() {
        onDelta = nil
        onCompleted = nil
        onMouseDrag = nil
        mouseDrag = nil
    }
}

private func radians(_ degrees: Float) -> Double {
    Double(degrees) * .pi / 180
}
