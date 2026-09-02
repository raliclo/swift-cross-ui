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
                // Empty here on purpose. This branch is the degenerate one --
                // the stack was proposed zero, infinity or nothing, or it has a
                // single child -- and the sizes above were chosen against that
                // proposal rather than measured as minimums. Handing them over
                // as a floor would stop a later redistribution from compressing
                // anything. `computeLayouts` treats an empty array as no floor,
                // which is what this path did before minimums were kept at all.
                // 此處刻意留空。本分支是退化情況——stack 被提議的是零、無限大或未指定，或它只有
                // 一個子元件——而上方那些尺寸是「針對該提議所選擇的結果」，並非量測而得的最小值。
                // 把它們當作下限交出去，會使後續的重新分配無法壓縮任何東西。`computeLayouts` 會把
                // 空陣列視為「沒有下限」，那正是本路徑在「保留最小值」這件事存在之前的行為。
                minimumLengths: [],
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
        var minimumLengths = [Double](repeating: 0, count: children.count)
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
            minimumLengths[i] = minimum
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
            minimumLengths: minimumLengths,
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

        // Which child, if any, was offered nothing. See ``StackOverflowReport``
        // for why this is worth carrying through the loop.
        // 哪一個子元件（若有的話）什麼都沒被分到。理由見 ``StackOverflowReport``。
        var firstStarvedChild: String?

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

                // Never below the child's own minimum.
                //
                // The share can reach zero: earlier children take their natural
                // size, which for a rigid child is more than its share, and the
                // clamp above then leaves nothing for the last one. Proposing
                // zero does not change what that child returns -- it returns its
                // minimum either way -- so the stack's total is identical with
                // this line and without it. What changes is what the child's own
                // children are offered, and that is where the damage was.
                //
                // Measured on the iPhone 16 simulator, P43: four columns each
                // holding a fixed 120pt shape and a caption, offered 350 points
                // against the 528 they need. The shares came out 76, 61, 31 and
                // 0, so the fourth column's `Text` was proposed zero width and
                // wrapped to one character per line. That made its column three
                // times the height of its siblings, and a centred `HStack` then
                // lifted its shape out of line with the other three -- which
                // reads as a rendering bug in the last column and is not one.
                // With this line all four are offered 120, all four captions
                // wrap the same way, and the row is level.
                //
                // 絕不低於子元件自身的最小值。
                //
                // 份額有可能歸零：先前的子元件會取用其自然尺寸，而剛性元件的自然尺寸大於它的份額，
                // 上方的夾限便使最後一個什麼都不剩。提議零並不會改變該子元件所回傳的值——它無論如何
                // 都回傳自身最小值——因此有沒有這一行，stack 的總長度完全相同。改變的是「該子元件
                // 自己的子元件被提議了什麼」，而傷害正是發生在那裡。
                //
                // 於 iPhone 16 模擬器上實測，P43：四個欄位各含一個固定 120pt 的形狀與一行說明文字，
                // 在需要 528 點的情況下只被提議 350 點。四份份額為 76、61、31 與 0，因此第四欄的
                // `Text` 被提議零寬，變成每行一個字。那使該欄的高度成為其兄弟欄的三倍，而置中的
                // `HStack` 便把它的形狀頂出與其他三欄的對齊線之外——讀起來像是最後一欄有算繪 bug，
                // 而它並不是。加上這一行之後，四欄都被提議 120，四行說明文字以相同方式換行，整列齊平。
                let minimum = index < cache.minimumLengths.count ? cache.minimumLengths[index] : 0
                proposedChildSize[component: orientation] = max(share, minimum)
                proposedChildSize[component: perpendicularOrientation] = proposedPerpendicular

                if share == 0, firstStarvedChild == nil {
                    firstStarvedChild = child.tag ?? "<unknown type>"
                }

                let childResult = child.computeLayout(
                    proposedSize: proposedChildSize,
                    environment: environment
                )

                renderedChildren[index] = childResult
                childrenRemaining -= 1

                spaceUsedAlongStackAxis += childResult.size[component: orientation]
            }
        }

        StackOverflowReport.check(
            orientation: orientation,
            proposedLength: proposedLength,
            usedLength: spaceUsedAlongStackAxis + cache.totalSpacing,
            childCount: children.count,
            starvedChild: firstStarvedChild
        )

        return renderedChildren
    }
}

/// Says out loud when a stack could not fit its children.
///
/// The allocation above gives each child `(proposal - spacing - what earlier
/// children took) / children remaining`, and clamps that at zero. When a stack
/// is proposed less than its children need, the clamp is reached and the last
/// child is offered **nothing**. It still renders -- a child enforces its own
/// minimum by returning it -- but it renders as though it had been asked for
/// zero width. A `Text` offered zero wraps to one character per line, which
/// makes its column very tall, and a centred stack then lifts that column's
/// shape out of line with its siblings.
///
/// **That is the whole of the "misalignment" in P43 on a phone.** Measured on
/// the iPhone 16 simulator 2026-09-02, this warning reported: `horizontal stack
/// ran out of space: 4 children were offered 350 and took 528`, naming
/// `VStack<TupleView2<StrictFrameView<StyledShapeImpl<Circle>>, Text>>` -- the
/// stroked circle's column, the fourth and last.
///
/// **macOS cannot reach this, which is why it needs saying on the others.** A
/// window's minimum size is derived from its content, so AppKit refuses to make
/// the window smaller than the stack needs: P43's window would not go below 568
/// points. A phone's window is whatever the device is, so the content is
/// proposed less than its minimum and the shortfall lands on the last child.
///
/// Nothing said so before. The layout was not wrong and it was not explicable
/// either: a stack silently running out of room looks like a rendering bug in
/// whichever child happens to be last. This follows the policy
/// `ResolvedFillStyleDegradation` sets -- something that draws *plausible and
/// wrong* has to announce itself, because it otherwise reads as a defect in the
/// wrong place.
///
/// 在 stack 塞不下它的子元件時明說出來。
///
/// 上方的分配讓每個子元件取得「(提議 - spacing - 先前子元件已取用) / 尚未放置的數量」，並在零處
/// 夾住。當 stack 被提議的空間少於其子元件所需時，就會碰到那個夾限，最後一個子元件被分到的是
/// **零**。它仍然會算繪——子元件會以回傳自身 minimum 的方式強制其下限——但它的算繪結果就像是
/// 「被要求零寬」一樣。被提議零寬的 `Text` 會變成每行一個字，使該欄變得極高，而置中的 stack 便會
/// 把該欄的形狀頂出與其兄弟元件的對齊線之外。
///
/// **這就是 P43 在手機上「錯位」的全部成因。** 2026-09-02 於 iPhone 16 模擬器上實測，本警告回報：
/// `horizontal stack ran out of space: 4 children were offered 350 and took 528`，並指名
/// `VStack<TupleView2<StrictFrameView<StyledShapeImpl<Circle>>, Text>>`——也就是描邊圓所在的那一欄，
/// 第四欄、也是最後一欄。
///
/// **macOS 碰不到這個情況，而那正是它在其他平台上更需要被說出來的原因。** 視窗的最小尺寸是由其內容
/// 推導出來的，因此 AppKit 拒絕把視窗縮得比 stack 所需更小：P43 的視窗低於 568 點就縮不下去了。而
/// 手機的視窗就是裝置本身的尺寸，因此內容被提議的空間少於其最小需求，短缺便落在最後一個子元件身上。
///
/// 先前沒有任何東西說出這件事。該版面並沒有算錯，卻也無從解釋：一個默默把空間用完的 stack，看起來
/// 就像「剛好排在最後的那個子元件」有算繪 bug。此處遵循 `ResolvedFillStyleDegradation` 所確立的
/// 政策——會畫出「看似合理但其實不對」之物者必須自報身分，否則它會讓人把缺陷歸咎到錯誤的地方。
@MainActor
enum StackOverflowReport {
    /// Keyed on the shape of the situation, not on its numbers.
    ///
    /// A window being resized produces a new length on every frame, so a key
    /// containing the proposal would grow without bound and report on every
    /// pixel of the drag. The orientation, the child count and the starved
    /// child's type stay put while the window moves.
    ///
    /// 以「情況的形狀」為鍵，而非以其數值為鍵。
    ///
    /// 被拖曳縮放的視窗每一幀都會產生一個新的長度，因此若鍵中含有提議寬度，它會無限增長並在拖曳的
    /// 每一個像素上回報一次。而方向、子元件數量與「被餓到的那個子元件的型別」在視窗移動時是不變的。
    private static var reported: Set<String> = []

    static func check(
        orientation: Orientation,
        proposedLength: Double,
        usedLength: Double,
        childCount: Int,
        starvedChild: String?
    ) {
        // Only when a child was actually offered nothing. A stack that merely
        // overflows a little still gave every child a share, and its children
        // chose to be bigger than that -- a layout the app asked for, not a
        // shortage worth a line in the log.
        // 僅在確實有子元件被分到零時才回報。只是稍微溢出的 stack 仍給了每個子元件一份額度，是其
        // 子元件自行選擇比那份額度更大——那是 app 自己要求的版面，不是值得寫進 log 的短缺。
        guard let starvedChild else { return }

        let key = "\(orientation)|\(childCount)|\(starvedChild)"
        guard !reported.contains(key) else { return }
        reported.insert(key)

        // Assembled rather than written as a multi-line literal. A `"""` block
        // with backslash continuations keeps each line's indentation, so the
        // message reached the log with runs of spaces inside it -- measured on
        // the simulator before this was changed.
        // 以組裝方式產生，而非寫成多行字面值。帶有反斜線續行的 `"""` 區塊會保留每一行的縮排，
        // 使訊息抵達 log 時夾帶著連續空白——這是在改成現在這樣之前於模擬器上量到的。
        let message = [
            "\(orientation) stack ran out of space:",
            "\(childCount) children were offered \(Int(proposedLength.rounded()))",
            "and took \(Int(usedLength.rounded())).",
            "At least one child was offered zero, so it is drawn at its own",
            "minimum rather than at a size this stack chose.",
            "Text offered zero wraps one character per line, which makes its",
            "column tall and pushes a centred stack's other children out of line.",
        ].joined(separator: " ")

        logger.warning(
            "\(message)",
            metadata: ["firstStarvedChild": "\(starvedChild)"]
        )
    }
}
