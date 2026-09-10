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
        // `ManipulationModes` is a `typealias` to a C enum with `static var`
        // members bolted on -- not a Swift `OptionSet` -- so `.union` does not
        // exist and the combination is a bitwise or on `rawValue`. Measured by
        // building: "value of type 'ManipulationModes' has no member 'union'".
        // `ManipulationModes` 是一個 `typealias` 指向 C enum、再外掛上 `static var` 成員——
        // **不是** Swift 的 `OptionSet`——因此 `.union` 並不存在,組合的方式是對 `rawValue`
        // 做位元或。以建置量得:「value of type 'ManipulationModes' has no member 'union'」。
        wrap(
            child,
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

    private func wrap(_ child: Widget, mode: ManipulationModes) -> Widget {
        let border = Border()
        border.child = child
        border.manipulationMode = mode
        return border
    }
}

/// WinUI reports rotation in degrees, clockwise positive, which is this
/// package's direction already -- so this converts the unit and nothing else.
///
/// **A file-scope function rather than a method, and that is the fix rather
/// than a style choice.** As a method it was called from inside the
/// `manipulationDelta` closures, which made it an implicit `self` capture:
/// "implicit use of 'self' in closure; use 'self.' to make capture semantics
/// explicit", twice. Writing `self.radians(...)` would silence it and would
/// also make each closure retain the backend for as long as the gesture lives,
/// for a function that touches no instance state at all.
///
/// WinUI 以**度**回報旋轉、順時針為正，方向與本套件一致——因此此處只換算單位，不做別的。
///
/// **它是檔案層級的函式而非方法,而那是修法本身、不是風格選擇。** 作為方法時,它被
/// `manipulationDelta` 的 closure 從內部呼叫,於是構成一次隱含的 `self` 捕獲:
/// 「implicit use of 'self' in closure」,兩次。改寫成 `self.radians(...)` 可以消掉那個錯誤,
/// 但也會讓每個 closure 在手勢存活期間一直持有 backend——**而這個函式根本不碰任何實例狀態**。
private func radians(_ degrees: Float) -> Double {
    Double(degrees) * .pi / 180
}
