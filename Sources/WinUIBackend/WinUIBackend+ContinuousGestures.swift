import Foundation
import SwiftCrossUI
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
    /// **NOT COMPILED HERE (2026-09-10).** This machine cannot build
    /// WinUIBackend. What to check, in order: the spelling of
    /// `manipulationMode` and the `ManipulationModes` cases; that
    /// `manipulationDelta` is an event with `addHandler`, as
    /// `CompositionTarget.rendering` is in the frame clock; and that
    /// `args.cumulative` carries `translation`, `scale` and `rotation` --
    /// rotation in DEGREES, which is why it is converted here.
    ///
    /// WinUI 的 manipulation 事件，它一次回報全部三者。
    ///
    /// **三種手勢共用一條事件流，這與其他每一處都不同。** 一個設定了 `manipulationMode` 的
    /// `UIElement` 會發出 `ManipulationDelta`，其中同時帶著位移、縮放**與**旋轉;此處的三份實作，
    /// 差別只在於各自讀哪個欄位、以及要求哪一種模式。只要求「所要的那個模式」是有意義的:若用
    /// `.all`，一次單指拖曳也會產生縮放的雜訊。
    ///
    /// **此處未編譯(2026-09-10)。** 這台機器建不了 WinUIBackend。依序要查的是:`manipulationMode`
    /// 的寫法與 `ManipulationModes` 的各個 case;`manipulationDelta` 是否為一個帶 `addHandler` 的
    /// 事件(一如 frame clock 中的 `CompositionTarget.rendering`);以及 `args.cumulative` 是否帶著
    /// `translation`、`scale` 與 `rotation`——其中旋轉的單位是**度**，這正是此處要換算的原因。
    public func createDragGestureTarget(wrapping child: Widget) -> Widget {
        wrap(child, mode: .translateX.union(.translateY))
    }

    public func updateDragGestureTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (DragGestureValue) -> Void,
        onEnd: @escaping (DragGestureValue) -> Void
    ) {
        guard environment.isEnabled else { return }
        _ = target.manipulationDelta.addHandler { _, args in
            guard let args else { return }
            let translation = args.cumulative.translation
            onChange(
                DragGestureValue(
                    startLocation: .zero,
                    location: SIMD2(Double(translation.x), Double(translation.y))
                )
            )
        }
        _ = target.manipulationCompleted.addHandler { _, args in
            guard let args else { return }
            let translation = args.cumulative.translation
            onEnd(
                DragGestureValue(
                    startLocation: .zero,
                    location: SIMD2(Double(translation.x), Double(translation.y))
                )
            )
        }
    }

    public func createMagnifyGestureTarget(wrapping child: Widget) -> Widget {
        wrap(child, mode: .scale)
    }

    public func updateMagnifyGestureTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (MagnifyGestureValue) -> Void,
        onEnd: @escaping (MagnifyGestureValue) -> Void
    ) {
        guard environment.isEnabled else { return }
        _ = target.manipulationDelta.addHandler { _, args in
            guard let args else { return }
            onChange(MagnifyGestureValue(magnification: Double(args.cumulative.scale)))
        }
        _ = target.manipulationCompleted.addHandler { _, args in
            guard let args else { return }
            onEnd(MagnifyGestureValue(magnification: Double(args.cumulative.scale)))
        }
    }

    public func createRotateGestureTarget(wrapping child: Widget) -> Widget {
        wrap(child, mode: .rotate)
    }

    public func updateRotateGestureTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (RotateGestureValue) -> Void,
        onEnd: @escaping (RotateGestureValue) -> Void
    ) {
        guard environment.isEnabled else { return }
        _ = target.manipulationDelta.addHandler { _, args in
            guard let args else { return }
            onChange(RotateGestureValue(radians: radians(args.cumulative.rotation)))
        }
        _ = target.manipulationCompleted.addHandler { _, args in
            guard let args else { return }
            onEnd(RotateGestureValue(radians: radians(args.cumulative.rotation)))
        }
    }

    /// WinUI reports rotation in degrees, clockwise positive, which is this
    /// package's direction already -- so this converts the unit and nothing else.
    /// WinUI 以**度**回報旋轉、順時針為正，方向與本套件一致——因此此處只換算單位，不做別的。
    private func radians(_ degrees: Float) -> Double {
        Double(degrees) * .pi / 180
    }

    private func wrap(_ child: Widget, mode: ManipulationModes) -> Widget {
        let border = Border()
        border.child = child
        border.manipulationMode = mode
        return border
    }
}
