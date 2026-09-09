import Foundation

/// A view that is scrollable when it would otherwise overflow available space.
///
/// Use the ``View/frame(width:height:alignment:)-(Double?,_,_)`` modifier to
/// constrain width or height if necessary.
public struct ScrollView<Content: View>: TypeSafeView, View {
    public var body: VStack<Content>
    public var axes: Axis.Set

    /// Wraps a view in a scrollable container.
    ///
    /// - Parameters:
    ///   - axes: The axes of to enable scrolling on. Defaults to
    ///     ``Axis/Set/vertical``.
    ///   - content: The content of the scroll view.
    public init(_ axes: Axis.Set = .vertical, @ViewBuilder _ content: () -> Content) {
        self.axes = axes
        body = VStack(content: content())
    }

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> ScrollViewChildren<Content> {
        // TODO: Verify that snapshotting works correctly with this
        return ScrollViewChildren(
            wrapping: TupleViewChildren1(
                body,
                backend: backend,
                snapshots: snapshots,
                environment: environment
            ),
            backend: backend
        )
    }

    func layoutableChildren<Backend: BaseAppBackend>(
        backend: Backend,
        children: TupleViewChildren1<VStack<Content>>
    ) -> [LayoutSystem.LayoutableChild] {
        []
    }

    func asWidget<Backend: BaseAppBackend>(
        _ children: ScrollViewChildren<Content>,
        backend: Backend
    ) -> Backend.Widget {
        return backend.createScrollContainer(for: children.innerContainer.into())
    }

    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: ScrollViewChildren<Content>,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        // If all scroll axes are unspecified, then our size is exactly that of
        // the child view. This includes when we have no scroll axes.
        let willEarlyExit = Axis.allCases.allSatisfy({ axis in
            !axes.contains(axis) || proposedSize[component: axis] == nil
        })

        // Probe how big the child would like to be
        var childProposal = proposedSize
        for axis in Axis.allCases where axes.contains(axis) {
            childProposal[component: axis] = nil
        }

        let childResult = children.child.computeLayout(
            with: body,
            proposedSize: childProposal,
            environment: environment.with(
                \.allowLayoutCaching,
                !willEarlyExit || environment.allowLayoutCaching
            )
        )

        if willEarlyExit {
            return childResult
        }

        let contentSize = childResult.size

        // An axis is present when it's a scroll axis AND the corresponding
        // child content size is bigger then the proposed size. If the proposed
        // size along the axis is nil then we don't have a scroll bar.
        let hasHorizontalScrollBar: Bool
        if axes.contains(.horizontal), let proposedWidth = proposedSize.width {
            hasHorizontalScrollBar = contentSize.width > proposedWidth
        } else {
            hasHorizontalScrollBar = false
        }
        children.hasHorizontalScrollBar = hasHorizontalScrollBar

        let hasVerticalScrollBar: Bool
        if axes.contains(.vertical), let proposedHeight = proposedSize.height {
            hasVerticalScrollBar = contentSize.height > proposedHeight
        } else {
            hasVerticalScrollBar = false
        }
        children.hasVerticalScrollBar = hasVerticalScrollBar

        let scrollBarWidth = Double(backend.scrollBarWidth)
        let verticalScrollBarWidth = hasVerticalScrollBar ? scrollBarWidth : 0
        let horizontalScrollBarHeight = hasHorizontalScrollBar ? scrollBarWidth : 0

        // Compute the final size to propose to the child view. Subtract off
        // scroll bar sizes from non-scrolling axes.
        var finalContentSizeProposal = childProposal
        if !axes.contains(.horizontal), let proposedWidth = childProposal.width {
            finalContentSizeProposal.width = proposedWidth - verticalScrollBarWidth
        }

        if !axes.contains(.vertical), let proposedHeight = childProposal.height {
            finalContentSizeProposal.height = proposedHeight - horizontalScrollBarHeight
        }

        // Propose a final size to the child view.
        let finalChildResult = children.child.computeLayout(
            with: nil,
            proposedSize: finalContentSizeProposal,
            environment: environment
        )

        // Compute the outer size.
        var outerSize = finalChildResult.size
        if axes.contains(.horizontal) {
            outerSize.width =
                proposedSize.width
                    ?? (finalChildResult.size.width + verticalScrollBarWidth)
        } else {
            outerSize.width += verticalScrollBarWidth
        }

        if axes.contains(.vertical) {
            outerSize.height =
                proposedSize.height
                    ?? (finalChildResult.size.height + horizontalScrollBarHeight)
        } else {
            outerSize.height += horizontalScrollBarHeight
        }

        return ViewLayoutResult(
            size: outerSize,
            childResults: [finalChildResult],
            participateInStackLayoutsWhenEmpty: true
        )
    }

    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: ScrollViewChildren<Content>,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        let scrollViewSize = layout.size
        let finalContentSize = children.child.commit().size

        backend.setSize(of: widget, to: scrollViewSize.vector)
        backend.setSize(
            of: children.innerContainer.into(),
            to: SIMD2(
                max(finalContentSize.vector.x, scrollViewSize.vector.x),
                max(finalContentSize.vector.y, scrollViewSize.vector.y)
            )
        )

        let contentX: Double
        if finalContentSize.width < scrollViewSize.width {
            let alignment = axes.contains(.vertical)
                ? HorizontalAlignment.center : HorizontalAlignment.leading
            contentX = alignment.position(
                ofChild: finalContentSize.width,
                in: scrollViewSize.width
            )
        } else {
            contentX = 0
        }

        let contentY: Double
        if finalContentSize.height < scrollViewSize.height {
            let alignment = axes.contains(.horizontal)
                ? VerticalAlignment.center : VerticalAlignment.top
            contentY = alignment.position(
                ofChild: finalContentSize.height,
                in: scrollViewSize.height
            )
        } else {
            contentY = 0
        }

        backend.setPosition(
            ofChildAt: 0,
            in: children.innerContainer.into(),
            to: SIMD2(
                LayoutSystem.roundSize(contentX),
                LayoutSystem.roundSize(contentY)
            )
        )

        backend.updateScrollContainer(
            widget,
            environment: environment,
            bounceHorizontally: axes.contains(.horizontal),
            bounceVertically: axes.contains(.vertical),
            hasHorizontalScrollBar: children.hasHorizontalScrollBar,
            hasVerticalScrollBar: children.hasVerticalScrollBar
        )

        // After updateScrollContainer, not before. On the backends whose update
        // touches the container's own subviews, adding the refresh control
        // first would have it removed again by a pass that knows nothing about
        // it -- and a control that is created and then silently dropped looks
        // exactly like one that was never asked for.
        // 放在 updateScrollContainer 之後而非之前。在那些「更新時會動到容器自身子 view」的 backend 上,
        // 先加入 refresh 控制項會讓它被一個對它一無所知的流程再次移除——而一個「被建立、然後被靜默
        // 丟棄」的控制項,看起來與一個從未被要求過的控制項完全相同。
        backend.setRefreshHandler(ofScrollContainer: widget, to: environment.onRefresh)

        // The one point where the backend's type is still known.
        //
        // `ScrollAnchorRegistry` lives in `EnvironmentValues`, which is not
        // generic over a backend, so it cannot call
        // `scrollContainer(_:to:anchor:)` -- that needs `Backend.Widget`. This
        // closure captures the concrete backend and this container's widget, so
        // the type is recovered exactly once, here.
        //
        // Reinstalled on every update rather than once. The widget outlives an
        // update but not a rebuild, and a closure holding a dead container
        // would scroll something that is no longer on screen -- successfully,
        // and invisibly.
        //
        // 這是 backend 的型別仍為人所知的唯一地點。
        //
        // `ScrollAnchorRegistry` 存放在 `EnvironmentValues` 中,而後者並不對 backend 泛型化,因此它
        // 無法呼叫 `scrollContainer(_:to:anchor:)`——那需要 `Backend.Widget`。這個 closure 捕捉了
        // 具體的 backend 與本容器的 widget,因此型別只在此處被還原一次。
        //
        // 每次更新都重新安裝,而不是只安裝一次。widget 的生命長於一次更新、但不長於一次重建,而一個
        // 握著已死容器的 closure 會去捲動某個已經不在畫面上的東西——而且是成功地、無形地捲動。
        environment.scrollAnchors?.install(container: children.innerContainer) { child, anchor in
            // The backend ignores a widget that is not inside this container,
            // which is what makes it safe for the registry to ask every one.
            // backend 會忽略不在本容器內部的 widget,而那正是「讓 registry 逐一詢問每一個容器」
            // 得以安全的原因。
            backend.scrollContainer(widget, to: child.into(), anchor: anchor)
        }
    }
}

class ScrollViewChildren<Content: View>: ViewGraphNodeChildren {
    var children: TupleView1<VStack<Content>>.Children
    var innerContainer: AnyWidget

    var hasVerticalScrollBar = false
    var hasHorizontalScrollBar = false

    var child: AnyViewGraphNode<VStack<Content>> {
        children.child0
    }

    var widgets: [AnyWidget] {
        // The implementation of this property doesn't really matter. It doesn't
        // really have a reason to get used anywhere.
        children.widgets
    }

    var erasedNodes: [ErasedViewGraphNode] {
        children.erasedNodes
    }

    init<Backend: BaseAppBackend>(
        wrapping children: TupleView1<VStack<Content>>.Children,
        backend: Backend
    ) {
        self.children = children
        let innerContainer = backend.createContainer()
        backend.insert(children.child0.widget.into(), into: innerContainer, at: 0)
        self.innerContainer = AnyWidget(innerContainer)
    }
}
