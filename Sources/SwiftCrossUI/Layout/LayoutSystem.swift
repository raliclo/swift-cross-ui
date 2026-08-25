public enum LayoutSystem {
    static func width(forHeight height: Double, aspectRatio: Double) -> Double {
        Double(height) * aspectRatio
    }

    static func height(forWidth width: Double, aspectRatio: Double) -> Double {
        Double(width) / aspectRatio
    }

    @_spi(Backends) public static func roundSize(_ size: Double) -> Int {
        if size.isInfinite {
            logger.warning("LayoutSystem.roundSize(_:) called with infinite size")
        }

        let size = size.rounded(.up)
        return if size >= Double(Int.max) {
            Int.max
        } else if size <= Double(Int.min) {
            Int.min
        } else {
            Int(size)
        }
    }

    static func clamp(_ value: Double, minimum: Double?, maximum: Double?) -> Double {
        var value = value
        if let minimum {
            value = max(minimum, value)
        }
        if let maximum {
            value = min(maximum, value)
        }
        return value
    }

    static func aspectRatio(of frame: ViewSize) -> Double {
        aspectRatio(of: SIMD2(frame.width, frame.height))
    }

    static func aspectRatio(of frame: SIMD2<Double>) -> Double {
        if frame.x == 0 || frame.y == 0 {
            // Even though we could technically compute an aspect ratio when the
            // ideal width is 0, it leads to a lot of annoying usecases and isn't
            // very meaningful, so we default to 1 in that case as well as the
            // division by zero case.
            return 1
        } else {
            return frame.x / frame.y
        }
    }

    public struct LayoutableChild {
        private var computeLayout:
            @MainActor (
                _ proposedSize: ProposedViewSize,
                _ environment: EnvironmentValues
            ) -> ViewLayoutResult
        private var _commit: @MainActor () -> ViewLayoutResult
        var tag: String?

        public init(
            computeLayout: @escaping @MainActor (ProposedViewSize, EnvironmentValues)
                -> ViewLayoutResult,
            commit: @escaping @MainActor () -> ViewLayoutResult,
            tag: String? = nil
        ) {
            self.computeLayout = computeLayout
            self._commit = commit
            self.tag = tag
        }

        init<Child: View>(
            _ node: AnyViewGraphNode<Child>,
            child: @escaping @Sendable @MainActor () -> Child?
        ) {
            self.init(
                computeLayout: { proposedSize, environment in
                    node.computeLayout(
                        with: child(),
                        proposedSize: proposedSize,
                        environment: environment
                    )
                },
                commit: {
                    node.commit()
                }
            )
        }

        @MainActor
        public func computeLayout(
            proposedSize: ProposedViewSize,
            environment: EnvironmentValues
        ) -> ViewLayoutResult {
            computeLayout(proposedSize, environment)
        }

        @MainActor
        public func commit() -> ViewLayoutResult {
            _commit()
        }
    }

    /// Sizes a container that overlaps its children rather than arranging them
    /// along an axis.
    ///
    /// Shared by ``ZStack`` and by ``Group`` when it finds itself inside one.
    /// `Group` is meant to be invisible to the layout system, so the two have to
    /// agree exactly; they disagreed while `ZStack` kept its own copy, and a
    /// `Group` inside a `ZStack` laid its children out vertically.
    @MainActor
    static func computeOverlapLayout(
        children: [LayoutableChild],
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues
    ) -> ViewLayoutResult {
        let childResults = children.map { child in
            child.computeLayout(
                proposedSize: proposedSize,
                environment: environment
            )
        }

        let size = ViewSize(
            childResults.map(\.size.width).max() ?? 0,
            childResults.map(\.size.height).max() ?? 0
        )
        return ViewLayoutResult(size: size, childResults: childResults)
    }

    /// Positions overlapping children, each aligned within the container.
    @MainActor
    static func commitOverlapLayout<Backend: BaseAppBackend>(
        container: Backend.Widget,
        children: [LayoutableChild],
        cache: StackLayoutCache,
        layout: ViewLayoutResult,
        alignment: Alignment,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        if cache.redistributeSpaceOnCommit {
            for child in children {
                _ = child.computeLayout(
                    proposedSize: ProposedViewSize(layout.size),
                    environment: environment
                )
            }
        }

        let size = layout.size
        for (index, childLayout) in children.map({ $0.commit() }).enumerated() {
            let position = alignment.position(
                ofChild: childLayout.size.vector,
                in: size.vector
            )
            backend.setPosition(ofChildAt: index, in: container, to: position)
        }

        backend.setSize(of: container, to: size.vector)
    }

    /// - Parameter inheritStackLayoutParticipation: If `true`, the stack layout
    ///   will have ``ViewSize/participateInStackLayoutsWhenEmpty`` set to `true`
    ///   if all of its children have it set to true. This allows views such as
    ///   ``Group`` to avoid changing stack layout participation (since ``Group``
    ///   is meant to appear completely invisible to the layout system).
    @MainActor
    static func computeStackLayout<Backend: BaseAppBackend>(
        container: Backend.Widget,
        children: [LayoutableChild],
        cache: inout StackLayoutCache,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend,
        inheritStackLayoutParticipation: Bool = false
    ) -> ViewLayoutResult {
        let spacing = environment.layoutSpacing
        let orientation = environment.layoutOrientation
        let perpendicularOrientation = orientation.perpendicular

        let stackLength = proposedSize[component: orientation]
        if stackLength == 0 || stackLength == .infinity || stackLength == nil || children.count == 1
        {
            var resultLength: Double = 0
            var resultWidth: Double = 0
            var results: [ViewLayoutResult] = []
            for child in children {
                let result = child.computeLayout(
                    proposedSize: proposedSize,
                    environment: environment
                )
                resultLength += result.size[component: orientation]
                resultWidth = max(resultWidth, result.size[component: perpendicularOrientation])
                results.append(result)
            }

            let visibleChildrenCount = results.count { result in
                result.participatesInStackLayouts
            }

            let totalSpacing = Double(max(visibleChildrenCount - 1, 0) * spacing)
            var size = ViewSize.zero
            size[component: orientation] = resultLength + totalSpacing
            size[component: perpendicularOrientation] = resultWidth

            // In this case, flexibility and layout priority don't matter. We set
            // the grouping to the trivial grouping so that commitStackLayout
            // effectively ignores flexibility.
            let group = LayoutPriorityGroup(
                children: Array(children.indices)[...],
                priority: 0
            )
            cache = StackLayoutCache(
                priorityGroups: [group],
                isHidden: results.map(\.participatesInStackLayouts).map(!),
                // A TODO stood here asking how SwiftUI handles space reservation
                // during relayouts, and guessing that it probably does not use
                // minimum lengths. The guess was right, and the question no
                // longer arises: computeLayouts reserves only the spacing, so
                // there is no reservation for a relayout to be inconsistent
                // about. See the note at the share calculation.
                // 此處原有一則 TODO，詢問 SwiftUI 在重新佈局時如何處理空間保留，並推測它多半
                // 不使用 minimum 長度。該推測是對的，而這個問題也已不復存在：computeLayouts
                // 只保留 spacing，因此不存在任何可能在重新佈局時前後不一致的保留量。
                // 詳見份額計算處的說明。
                totalSpacing: totalSpacing,
                redistributeSpaceOnCommit: shouldRedistributeSpaceOnCommit(
                    proposedSize: proposedSize,
                    orientation: orientation
                )
            )

            return ViewLayoutResult(
                size: size,
                childResults: results,
                participateInStackLayoutsWhenEmpty: results
                    .contains(where: \.participateInStackLayoutsWhenEmpty),
                preferencesOverlay: nil
            )
        }

        guard let stackLength else {
            fatalError("unreachable")
        }

        cache = recomputeCache(
            children: children,
            proposedSize: proposedSize,
            environment: environment
        )

        let renderedChildren = computeLayouts(
            of: children,
            proposedLength: stackLength,
            proposedPerpendicular: proposedSize[component: perpendicularOrientation],
            cache: cache,
            environment: environment,
            ignoreHiddenChildrenEntirely: false
        )

        var size = ViewSize.zero
        size[component: orientation] =
            renderedChildren.map(\.size[component: orientation]).reduce(0, +) + cache.totalSpacing
        size[component: perpendicularOrientation] =
            renderedChildren.map(\.size[component: perpendicularOrientation]).max() ?? 0

        return ViewLayoutResult(
            size: size,
            childResults: renderedChildren,
            participateInStackLayoutsWhenEmpty: renderedChildren
                .contains(where: \.participateInStackLayoutsWhenEmpty)
        )
    }

    /// Computes whether or not we have to redistribute space on commit. Returns true
    /// if and only if the perpendicular component of the proposed size is nil.
    static func shouldRedistributeSpaceOnCommit(
        proposedSize: ProposedViewSize,
        orientation: Orientation
    ) -> Bool {
        // When the perpendicular axis is unspecified (nil), we need
        // to re-run the space distribution algorithm with our final size during
        // the commit phase. This opens the door to certain edge cases, but SwiftUI
        // has them too, and there's not a good general solution to these edge
        // cases, even if you assume that you have unlimited compute. The reason for
        // this distribution is so that flexible children get a chance to use up any
        // unused space within the final perpendicular size of the stack.
        proposedSize[component: orientation.perpendicular] == nil
    }

    /// Computes the cache from scratch for the slow path (this is our last
    /// resort if shortcuts can't be made), preparing it for subsequent layout
    /// operations.
    @MainActor
    static func recomputeCache(
        children: [LayoutableChild],
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues
    ) -> StackLayoutCache {
        let orientation = environment.layoutOrientation
        let spacing = environment.layoutSpacing

        // My thanks go to this great article for investigating and explaining
        // how SwiftUI determines child view 'flexibility':
        // https://www.objc.io/blog/2020/11/10/hstacks-child-ordering/
        var minimumProposedSize = proposedSize
        minimumProposedSize[component: orientation] = 0
        var maximumProposedSize = proposedSize
        maximumProposedSize[component: orientation] = .infinity
        var isHidden = [Bool](repeating: false, count: children.count)
        var priorities = [Double](repeating: 0, count: children.count)
        let flexibilities = children.enumerated().map { i, child in
            let minimumResult = child.computeLayout(
                proposedSize: minimumProposedSize,
                environment: environment.with(\.allowLayoutCaching, true)
            )
            let maximumResult = child.computeLayout(
                proposedSize: maximumProposedSize,
                environment: environment.with(\.allowLayoutCaching, true)
            )
            isHidden[i] = !minimumResult.participatesInStackLayouts
            priorities[i] = minimumResult.preferences.layoutPriority
            let maximum = maximumResult.size[component: orientation]
            let minimum = minimumResult.size[component: orientation]
            return maximum - minimum
        }
        let visibleChildrenCount = isHidden.filter { hidden in
            !hidden
        }.count
        let totalSpacing = Double(max(visibleChildrenCount - 1, 0) * spacing)

        let sortedChildren = zip(children.indices, zip(priorities.map(-), flexibilities))
            .sorted { first, second in
                // Sort by descending priority and then by ascending flexibility
                first.1 <= second.1
            }
            .map { index, _ in
                index
            }

        var priorityGroups: [LayoutPriorityGroup] = []
        var previousPriority: Double? = nil
        var startIndex: Int?
        for (sortedIndex, originalIndex) in sortedChildren.enumerated() {
            let priority = priorities[originalIndex]
            if priority != previousPriority {
                if let startIndex, let previousPriority {
                    let group = LayoutPriorityGroup(
                        children: sortedChildren[startIndex..<sortedIndex],
                        priority: previousPriority
                    )
                    priorityGroups.append(group)
                }
                startIndex = sortedIndex
                previousPriority = priority
            }
        }

        if let startIndex, let previousPriority {
            let group = LayoutPriorityGroup(
                children: sortedChildren[startIndex..<sortedChildren.endIndex],
                priority: previousPriority
            )
            priorityGroups.append(group)
        }

        return StackLayoutCache(
            priorityGroups: priorityGroups,
            isHidden: isHidden,
            totalSpacing: totalSpacing,
            redistributeSpaceOnCommit: shouldRedistributeSpaceOnCommit(
                proposedSize: proposedSize,
                orientation: orientation
            )
        )
    }

    @MainActor
    static func commitStackLayout<Backend: BaseAppBackend>(
        container: Backend.Widget,
        children: [LayoutableChild],
        cache: inout StackLayoutCache,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        let size = layout.size
        backend.setSize(of: container, to: size.vector)

        let alignment = environment.layoutAlignment
        let spacing = environment.layoutSpacing
        let orientation = environment.layoutOrientation
        let perpendicularOrientation = orientation.perpendicular

        if cache.redistributeSpaceOnCommit {
            _ = computeLayouts(
                of: children,
                proposedLength: layout.size[component: orientation],
                proposedPerpendicular: layout.size[component: perpendicularOrientation],
                cache: cache,
                environment: environment,
                ignoreHiddenChildrenEntirely: true
            )
        }

        let renderedChildren = children.map { $0.commit() }

        var position = Position.zero
        for (index, child) in renderedChildren.enumerated() {
            // Avoid the whole iteration if the child is hidden. If there
            // are weird positioning issues for views that do strange things
            // then this could be the cause.
            if !child.participatesInStackLayouts {
                continue
            }

            // Compute alignment
            switch alignment {
                case .leading:
                    position[component: perpendicularOrientation] = 0
                case .center:
                    let outer = size[component: perpendicularOrientation]
                    let inner = child.size[component: perpendicularOrientation]
                    position[component: perpendicularOrientation] = (outer - inner) / 2
                case .trailing:
                    let outer = size[component: perpendicularOrientation]
                    let inner = child.size[component: perpendicularOrientation]
                    position[component: perpendicularOrientation] = outer - inner
            }

            backend.setPosition(ofChildAt: index, in: container, to: position.vector)

            position[component: orientation] += child.size[component: orientation] + Double(spacing)
        }
    }

    /// The main stack layout space allocation algorithm. Used during
    /// computeLayout, and sometimes during commit when we have to redistribute
    /// space (due to an unspecified perpendicular size proposal).
    @MainActor
    static func computeLayouts(
        of children: [LayoutableChild],
        proposedLength: Double,
        proposedPerpendicular: Double?,
        cache: StackLayoutCache,
        environment: EnvironmentValues,
        ignoreHiddenChildrenEntirely: Bool
    ) -> [ViewLayoutResult] {
        var renderedChildren = [ViewLayoutResult](
            repeating: .leafView(size: .zero),
            count: children.count
        )

        let orientation = environment.layoutOrientation
        let perpendicularOrientation = orientation.perpendicular
        var spaceUsedAlongStackAxis = 0.0
        for group in cache.priorityGroups {
            var childrenRemaining = group.children.count { index in
                !cache.isHidden[index]
            }

            for index in group.children {
                let child = children[index]

                // No need to render visible children.
                if cache.isHidden[index] {
                    if ignoreHiddenChildrenEntirely {
                        continue
                    }

                    // Update child in case it has just changed from visible to hidden,
                    // and to make sure that the view is still hidden (if it's not then
                    // it's a bug with either the view or the layout system).
                    let result = child.computeLayout(
                        proposedSize: .zero,
                        environment: environment
                    )
                    if result.participatesInStackLayouts {
                        logger.warning(
                            "hidden view became visible on second update; layout may break",
                            metadata: [
                                "view": "\(child.tag ?? "<unknown type>")"
                            ]
                        )
                    }
                    renderedChildren[index] = result
                    renderedChildren[index].participateInStackLayoutsWhenEmpty = false
                    renderedChildren[index].size = .zero
                    continue
                }

                // Each child's share is the space left for children, divided by
                // how many are still to be placed. "Left for children" is the
                // proposal minus the fixed spacing and minus what earlier
                // children took -- and nothing else.
                //
                // It used to also subtract the *minimum lengths* of the children
                // not yet placed. That double-reserved: the children are already
                // sorted least-flexible first, so a rigid child takes its small
                // natural size and leaves the rest, and a flexible child last
                // absorbs the leftover -- there is no need to hold back space for
                // a minimum a later child will claim anyway. Reserving it as well
                // shrank every child's share, and the first (least flexible) one
                // was pushed below its own natural width and truncated while a
                // later child rendered in full. Measured on P21: an outer HStack
                // of two toggle switches, proposed 172, offered its first child
                // 60.5 against a natural of 79 -- the "Enabled" label became "...".
                // Reserving only the spacing offers 81 instead, and it renders.
                //
                // This matches the algorithm the ordering is taken from:
                // https://www.objc.io/blog/2020/11/10/hstacks-child-ordering/
                // A child that genuinely cannot fit still enforces its own
                // minimum by returning it, so nothing here has to reserve it.
                //
                // 每個子元件的份額，是「留給子元件的空間」除以「尚未放置的子元件數」。「留給子元件的
                // 空間」是提議寬度減去固定的 spacing、再減去先前子元件已取用的量——僅此而已。
                //
                // 此處原本還會扣掉「尚未放置之子元件的 minimum 長度」。那是雙重保留：子元件早已依
                // 「最不彈性優先」排序，因此剛性元件取其較小的自然尺寸後即讓出其餘，而最後的彈性元件
                // 會吸收剩餘空間——無需為某個後續元件反正會取用的 minimum 預留空間。額外保留它會縮減
                // 每個子元件的份額，使排在最前（最不彈性）的那個被壓到低於自身自然寬度而遭截斷，後面
                // 的元件卻完整呈現。於 P21 實測：一個包含兩個 toggle switch 的外層 HStack，提議寬度
                // 172，其第一個子元件在自然寬度為 79 的情況下只被提議 60.5——「Enabled」標籤變成
                // 「...」。改為只保留 spacing 後，該子元件被提議 81，得以完整呈現。
                //
                // 這與排序所依據的演算法一致（如上連結）。確實放不下的子元件仍會以回傳自身 minimum 的
                // 方式強制其下限，因此此處無需為其預留。
                var proposedChildSize = ProposedViewSize.unspecified
                let share = max(
                    proposedLength - spaceUsedAlongStackAxis - cache.totalSpacing,
                    0
                ) / Double(childrenRemaining)
                proposedChildSize[component: orientation] = share
                proposedChildSize[component: perpendicularOrientation] = proposedPerpendicular

                let childResult = child.computeLayout(
                    proposedSize: proposedChildSize,
                    environment: environment
                )

                renderedChildren[index] = childResult
                childrenRemaining -= 1

                spaceUsedAlongStackAxis += childResult.size[component: orientation]
            }
        }

        return renderedChildren
    }
}
