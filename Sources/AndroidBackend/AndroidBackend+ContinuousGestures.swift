import AndroidKit
import SwiftCrossUI

extension AndroidBackend: BackendFeatures.DragGestures,
    BackendFeatures.MagnifyGestures,
    BackendFeatures.RotateGestures
{
    public func createDragGestureTarget(wrapping child: Widget) -> Widget {
        container(wrapping: child, kind: 0)
    }

    public func updateDragGestureTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (DragGestureValue) -> Void,
        onEnd: @escaping (DragGestureValue) -> Void
    ) {
        let target = target.as(ContinuousGestureContainer.self)!
        let value = { @MainActor in
            DragGestureValue(
                startLocation: SIMD2(Double(target.getStartX()), Double(target.getStartY())),
                location: SIMD2(Double(target.getCurrentX()), Double(target.getCurrentY()))
            )
        }
        target.setOnChange(
            environment.isEnabled
                ? SwiftAction(action: { MainActor.assumeIsolated { onChange(value()) } }) : nil
        )
        target.setOnEnd(
            environment.isEnabled
                ? SwiftAction(action: { MainActor.assumeIsolated { onEnd(value()) } }) : nil
        )
    }

    public func createMagnifyGestureTarget(wrapping child: Widget) -> Widget {
        container(wrapping: child, kind: 1)
    }

    public func updateMagnifyGestureTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (MagnifyGestureValue) -> Void,
        onEnd: @escaping (MagnifyGestureValue) -> Void
    ) {
        let target = target.as(ContinuousGestureContainer.self)!
        let value = { @MainActor in
            MagnifyGestureValue(magnification: Double(target.getMagnification()))
        }
        target.setOnChange(
            environment.isEnabled
                ? SwiftAction(action: { MainActor.assumeIsolated { onChange(value()) } }) : nil
        )
        target.setOnEnd(
            environment.isEnabled
                ? SwiftAction(action: { MainActor.assumeIsolated { onEnd(value()) } }) : nil
        )
    }

    public func createRotateGestureTarget(wrapping child: Widget) -> Widget {
        container(wrapping: child, kind: 2)
    }

    public func updateRotateGestureTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (RotateGestureValue) -> Void,
        onEnd: @escaping (RotateGestureValue) -> Void
    ) {
        let target = target.as(ContinuousGestureContainer.self)!
        let value = { @MainActor in RotateGestureValue(radians: Double(target.getRadians())) }
        target.setOnChange(
            environment.isEnabled
                ? SwiftAction(action: { MainActor.assumeIsolated { onChange(value()) } }) : nil
        )
        target.setOnEnd(
            environment.isEnabled
                ? SwiftAction(action: { MainActor.assumeIsolated { onEnd(value()) } }) : nil
        )
    }

    private func container(wrapping child: Widget, kind: Int32) -> Widget {
        let container = ContinuousGestureContainer(
            context: Self.activity,
            kind: kind
        )
        container.addView(child)
        return container.as(AndroidKit.View.self)!
    }
}
