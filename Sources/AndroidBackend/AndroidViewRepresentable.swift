import AndroidKit
@_spi(Backends) import SwiftCrossUI
import SwiftJava

@MainActor
public struct AndroidViewRepresentableContext<Representable: AndroidViewRepresentable> {
    public let coordinator: Representable.Coordinator
    public internal(set) var environment: EnvironmentValues
}

public protocol AndroidViewRepresentable: SwiftCrossUI.View where Content == Never {
    associatedtype ViewType: AndroidKit.View
    associatedtype Coordinator = Void

    /// Make the coordinator for this view.
    ///
    /// The coordinator is used when the view needs to communicate changes to the rest of
    /// the view hierarchy (i.e. through bindings).
    @MainActor
    func makeCoordinator() -> Coordinator

    /// Create the initial `android.view.View` instance.
    @MainActor
    func makeAndroidView(context: Self.Context) -> ViewType

    /// Update the view with new values.
    /// - Parameters:
    ///   - view: The view to update.
    ///   - context: The context, including the coordinator and potentially new environment
    ///     values.
    /// - Note: This may be called even when `context` has not changed.
    @MainActor
    func updateAndroidView(
        _ view: ViewType,
        context: Self.Context
    )

    /// Compute the view's preferred size.
    ///
    /// The default implementation uses `view.measure(_:_:)` to determine the view's preferred size.
    /// - Parameters:
    ///   - proposal: The proposed size for the view.
    ///   - view: The view being queried for its preferred size.
    ///   - context: The context, including the coordinator and environment values.
    /// - Returns: The view's preferred size.
    @MainActor
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        view: ViewType,
        context: Self.Context
    ) -> ViewSize

    /// Called when the view leaves the view graph, to undo what
    /// `makeAndroidView` set up (observers, timers, listeners). The default does
    /// nothing.
    ///
    /// Run when the view graph node holding the view is released, the same
    /// moment UIKitBackend calls `dismantleUIView` -- not from an Android View
    /// lifecycle callback, which has no single "this view is done" event (a
    /// detach also happens on every scroll-out). Upstream left this as a TODO
    /// for that reason; added 2026-10-06.
    ///
    /// view 離開 view graph 時呼叫，用來撤銷 `makeAndroidView` 所設定的東西(觀察者、計時器、監聽器)。
    /// 預設什麼都不做。在持有該 view 的 view graph 節點被釋放時執行，與 UIKitBackend 呼叫
    /// `dismantleUIView` 的時機相同——而不是來自 Android View 的生命週期回呼，那裡沒有單一的「這個 view
    /// 結束了」事件(每次捲出畫面也會 detach)。上游因此留下 TODO;2026-10-06 加入。
    @MainActor
    static func dismantleAndroidView(_ view: ViewType, coordinator: Coordinator)
}

extension AndroidViewRepresentable {
    public typealias Context = AndroidViewRepresentableContext<Self>

    @MainActor
    public func sizeThatFits(
        _ proposal: ProposedViewSize,
        view: ViewType,
        context: Self.Context
    ) -> ViewSize {
        let density = context.environment.windowScaleFactor

        // 0x80000000 = View.MeasureSpec.AT_MOST
        // 0x3FFFFFFF = View.MeasureSpec.makeMeasureSpec(Int32.max, View.MeasureSpec.UNSPECIFIED)
        let widthMeasureSpec =
            if
                let proposedWidth = proposal.width,
                proposedWidth > 0
            {
                Int32(bitPattern: 0x80000000 | UInt32(min(proposedWidth * density, 0x3FFFFFFF)))
            } else {
                0x3FFFFFFF as Int32
            }

        let heightMeasureSpec =
            if
                let proposedHeight = proposal.height,
                proposedHeight > 0
            {
                Int32(bitPattern: 0x80000000 | UInt32(min(proposedHeight * density, 0x3FFFFFFF)))
            } else {
                0x3FFFFFFF as Int32
            }

        view.measure(widthMeasureSpec, heightMeasureSpec)

        let width = Double(view.getMeasuredWidth()) / density
        let height = Double(view.getMeasuredHeight()) / density

        return ViewSize(width, height)
    }
}

extension AndroidViewRepresentable {
    @MainActor
    public static func dismantleAndroidView(_: ViewType, coordinator _: Coordinator) {}
}

/// The representable's node children: none, plus the dismantle call, made
/// when the node -- and so this object -- is released.
/// representable 節點的 children:沒有子節點，只帶著 dismantle 呼叫；在節點(因而此物件)被釋放時執行。
final class AndroidRepresentableChildren: ViewGraphNodeChildren {
    var widgets: [AnyWidget] { [] }
    var erasedNodes: [ErasedViewGraphNode] { [] }
    var dismantle: (@MainActor () -> Void)?

    deinit {
        if let dismantle {
            Task { @MainActor in dismantle() }
        }
    }
}

extension AndroidViewRepresentable where Coordinator == Void {
    public func makeCoordinator() {}
}

@JavaClass(
    "dev.swiftcrossui.androidbackend.RepresentingView",
    extends: AndroidKit.FrameLayout.self
)
class RepresentingView: AndroidKit.FrameLayout {
    @JavaMethod
    convenience init(
        _ activity: AndroidKit.Activity?,
        environment: JNIEnvironment? = nil
    )

    @JavaMethod
    func getSwiftContext() -> SwiftObject?

    @JavaMethod
    func setSwiftContext(_ swiftContext: SwiftObject?)

    @JavaMethod
    func getChild() -> AndroidKit.View?

    @JavaMethod
    func setChild(_ value: AndroidKit.View?)
}

extension RepresentingView {
    @MainActor
    func updateAndGetSize<T: AndroidViewRepresentable>(
        environment: EnvironmentValues,
        proposedSize: ProposedViewSize,
        representable: T
    ) -> ViewSize {
        var context: T.Context
        if let untypedContext = getSwiftContext()?.value() {
            context = untypedContext as! T.Context
            context.environment = environment
        } else {
            context = AndroidViewRepresentableContext(
                coordinator: representable.makeCoordinator(),
                environment: environment
            )
        }

        setSwiftContext(SwiftObject(context, environment: environment.jniEnv))

        let child: T.ViewType
        if let untypedChild = getChild() {
            child = untypedChild.as(T.ViewType.self)!
        } else {
            child = representable.makeAndroidView(context: context)
            setChild(child)
        }

        representable.updateAndroidView(child, context: context)

        return representable.sizeThatFits(proposedSize, view: child, context: context)
    }
}

extension SwiftCrossUI.View where Self: AndroidViewRepresentable {
    public var body: Never {
        preconditionFailure("This should never be called")
    }

    public func children<Backend: BaseAppBackend>(
        backend _: Backend,
        snapshots _: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment _: EnvironmentValues
    ) -> any ViewGraphNodeChildren {
        AndroidRepresentableChildren()
    }

    public func layoutableChildren<Backend: BaseAppBackend>(
        backend _: Backend,
        children _: any ViewGraphNodeChildren
    ) -> [LayoutSystem.LayoutableChild] {
        []
    }

    public func asWidget<Backend: BaseAppBackend>(
        _: any ViewGraphNodeChildren,
        backend _: Backend
    ) -> Backend.Widget {
        if let widget = RepresentingView(
            AndroidBackend.activity,
            environment: AndroidBackend.env
        ) as? Backend.Widget {
            return widget
        } else {
            fatalError("AndroidViewRepresentable requested by \(Backend.self)")
        }
    }

    public func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: any ViewGraphNodeChildren,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        let widget = (widget as! AndroidBackend.Widget).as(RepresentingView.self)!
        let size = widget.updateAndGetSize(
            environment: environment,
            proposedSize: proposedSize,
            representable: self
        )
        if let children = children as? AndroidRepresentableChildren, children.dismantle == nil {
            children.dismantle = {
                guard let child = widget.getChild()?.as(ViewType.self),
                    let context = widget.getSwiftContext()?.value() as? Context
                else {
                    return
                }
                Self.dismantleAndroidView(child, coordinator: context.coordinator)
            }
        }
        return ViewLayoutResult.leafView(size: size)
    }

    public func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: any ViewGraphNodeChildren,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        backend.setSize(of: widget, to: layout.size.vector)
    }
}
