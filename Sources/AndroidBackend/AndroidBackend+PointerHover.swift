@_spi(Backends) import SwiftCrossUI
import AndroidKit
import SwiftJava

@JavaClass(
    "dev.swiftcrossui.androidbackend.PointerHoverContainer",
    extends: AndroidKit.ViewGroup.self
)
class PointerHoverContainer: AndroidKit.ViewGroup {
    @JavaMethod
    @_nonoverride convenience init(
        _ activity: AndroidKit.Activity!,
        environment: JNIEnvironment? = nil
    )

    @JavaMethod func setChangeAction(_ action: SwiftAction?)
    @JavaMethod func getInside() -> Bool
    @JavaMethod func getPointX() -> Float
    @JavaMethod func getPointY() -> Float
    @JavaMethod func getMetaState() -> Int32
}

extension AndroidBackend: BackendFeatures.PointerHover {
    public func createPointerHoverTarget(wrapping child: Widget) -> Widget {
        let container = PointerHoverContainer(Self.activity, environment: Self.env)
        container.addView(child)
        return container.as(AndroidKit.View.self)!
    }

    public func updatePointerHoverTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        action: @escaping (PointerHoverPhase) -> Void
    ) {
        guard let container = target.as(PointerHoverContainer.self) else { return }
        // Weakly, through Java: the container holds this action. See `JavaWeakReference`.
        // 經由 Java 弱參照:容器持有這個 action。見 `JavaWeakReference`。
        let weakContainer = JavaWeakReference(container, environment: Self.env)
        let report = { @MainActor in
            guard let container = weakContainer.get()?.as(PointerHoverContainer.self) else {
                return
            }
            if container.getInside() {
                action(
                    .active(
                        location: SIMD2(Double(container.getPointX()), Double(container.getPointY())),
                        modifiers: Self.modifiers(fromMetaState: container.getMetaState())))
            } else {
                action(.ended)
            }
        }
        container.setChangeAction(
            environment.isEnabled
                ? SwiftAction(action: { MainActor.assumeIsolated { report() } }) : nil
        )
    }
}
