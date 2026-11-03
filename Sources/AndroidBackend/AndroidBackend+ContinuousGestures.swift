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
        // Weakly, through Java: the container holds these actions, and a captured
        // wrapper would be a JNI global reference back to it -- a cycle neither
        // collector can free. See `JavaWeakReference`.
        // 經由 Java 弱參照:容器持有這些 action,被捕捉的包裝物件會是指回它的 JNI 全域參照——兩邊的回收機制
        // 都釋放不了的循環。見 `JavaWeakReference`。
        let weakTarget = JavaWeakReference(target, environment: Self.env)
        let value = { @MainActor () -> DragGestureValue? in
            guard let target = weakTarget.get()?.as(ContinuousGestureContainer.self) else {
                return nil
            }
            return DragGestureValue(
                startLocation: SIMD2(Double(target.getStartX()), Double(target.getStartY())),
                location: SIMD2(Double(target.getCurrentX()), Double(target.getCurrentY()))
            )
        }
        target.setOnChange(
            environment.isEnabled
                ? SwiftAction(action: {
                    MainActor.assumeIsolated { if let value = value() { onChange(value) } }
                }) : nil
        )
        target.setOnEnd(
            environment.isEnabled
                ? SwiftAction(action: {
                    MainActor.assumeIsolated { if let value = value() { onEnd(value) } }
                }) : nil
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
        let weakTarget = JavaWeakReference(target, environment: Self.env)
        let value = { @MainActor () -> MagnifyGestureValue? in
            guard let target = weakTarget.get()?.as(ContinuousGestureContainer.self) else {
                return nil
            }
            return MagnifyGestureValue(magnification: Double(target.getMagnification()))
        }
        target.setOnChange(
            environment.isEnabled
                ? SwiftAction(action: {
                    MainActor.assumeIsolated { if let value = value() { onChange(value) } }
                }) : nil
        )
        target.setOnEnd(
            environment.isEnabled
                ? SwiftAction(action: {
                    MainActor.assumeIsolated { if let value = value() { onEnd(value) } }
                }) : nil
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
        let weakTarget = JavaWeakReference(target, environment: Self.env)
        let value = { @MainActor () -> RotateGestureValue? in
            guard let target = weakTarget.get()?.as(ContinuousGestureContainer.self) else {
                return nil
            }
            return RotateGestureValue(radians: Double(target.getRadians()))
        }
        target.setOnChange(
            environment.isEnabled
                ? SwiftAction(action: {
                    MainActor.assumeIsolated { if let value = value() { onChange(value) } }
                }) : nil
        )
        target.setOnEnd(
            environment.isEnabled
                ? SwiftAction(action: {
                    MainActor.assumeIsolated { if let value = value() { onEnd(value) } }
                }) : nil
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
