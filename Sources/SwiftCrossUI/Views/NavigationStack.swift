/// Type to indicate the root of the NavigationStack. This is internal to prevent root accidentally showing instead
/// of a detail view.
struct NavigationStackRootPath: Codable {}

/// A view that displays a root view and enables you to present additional views
/// over the root view.
///
/// Use ``navigationDestination(for:destination:)`` on this view instead of its
/// children, unlike Apple's SwiftUI API.
public struct NavigationStack<Detail: View>: View {
    public var body: some View {
        // Default alignment, deliberately. Forcing `.leading` here put the bar
        // where it belongs but also dragged every existing stack's content to
        // the left edge -- measured on P24, whose centred content moved. The
        // bar's own `Spacer` already makes it fill the width and hold the
        // button at the leading edge, so the wrapper does not need an opinion
        // and should not have one.
        //
        // 刻意使用預設對齊。在此強制 `.leading` 雖能把返回列放到正確位置，卻同時把所有既有堆疊的
        // 內容一併拉到左緣——於 P24 實測，其原本置中的內容位移了。返回列自身的 `Spacer` 已使其撐滿
        // 寬度並將按鈕固定在前緣，因此外層包裝不需要、也不應該有自己的對齊主張。
        // Greedy in both axes at every depth, which is what makes a push not
        // move anything outside the stack.
        //
        // Without this the stack's footprint depended on whether it had a back
        // bar. At the root there is none, so the stack sized to its content and
        // an enclosing centred layout placed it accordingly; after one push the
        // bar appeared, its `Spacer` claimed the whole width, and the stack --
        // and therefore every sibling above it -- jumped. Measured on P24 in a
        // 720-wide window: content at x 225..492 at the root, x 16..704 after
        // one push. Identical on WinUIBackend, ~305px inside the frame becoming
        // ~22px, which is what showed it was here rather than in a backend.
        //
        // Height for the same reason, and it is the same bug in the other axis:
        // the bar and its divider make the stack taller, and a vertically
        // centred enclosing layout then moved everything up. Measured after the
        // width fix alone -- P24's title sat at y 141 at the root and y 116
        // after a push, while x had stopped moving.
        //
        // SwiftUI's NavigationStack fills the space it is offered whatever its
        // depth; a push replaces what is inside that footprint and moves
        // nothing around it. This is that.
        //
        // 高度亦然，且那是同一個 bug 在另一個軸上的表現：返回列與其分隔線使堆疊變高，而外層垂直置中
        // 的版面便將所有東西上移。此為僅修正寬度之後所實測——P24 的標題在根層位於 y 141，推入一層後
        // 位於 y 116，而此時 x 已不再移動。
        //
        // 在任何深度都貪婪地佔滿寬度，這正是「推入不會移動堆疊外任何東西」的關鍵。
        //
        // 沒有這一行時，堆疊的佔位取決於它是否帶有返回列。位於根層時沒有返回列，因此堆疊依內容縮放，
        // 外層的置中版面便據此擺放它；推入一層後返回列出現，其 `Spacer` 索取了整個寬度，於是堆疊
        // ——連同其上方的每一個同層視圖——整個跳位。於 P24、720 寬的視窗中實測：根層時內容位於
        // x 225..492，推入一層後位於 x 16..704。WinUIBackend 上完全相同，距 frame 左緣由約 305px
        // 變為約 22px，正是這一點顯示問題在此處而非某個 backend。
        //
        // SwiftUI 的 NavigationStack 不論深度都會填滿被給予的空間；推入只替換該佔位內的內容，不會
        // 移動其周圍的任何東西。此處即是如此。
        VStack(spacing: 0) {
            if elements.count > 1 {
                navigationBar
            }
            currentDestination
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A back control, shown whenever anything has been pushed.
    ///
    /// Built from ordinary views rather than asked of the backend, so every
    /// backend gets it and none has to implement anything. A navigation bar is
    /// a button and a label; there is nothing here a backend could do better,
    /// and a `BackendFeatures` protocol for it would mean a stack with no way
    /// back on any backend that had not implemented it yet.
    ///
    /// Until this existed a `NavigationStack` could be pushed but never popped:
    /// `body` rendered only `elements.last`, on every backend, so the only way
    /// back was whatever the application happened to provide. Measured on P24,
    /// which pushed to level 3 and then had nowhere to go.
    ///
    /// The label matches SwiftUI's fallback. SwiftUI shows the previous view's
    /// title and says "Back" when there is none; there are no navigation titles
    /// here yet, so the fallback is the whole of it. When
    /// ``View/navigationTitle(_:)`` lands, this is where it reads from.
    ///
    /// 只要曾經推入任何內容，就會顯示的返回控制項。
    ///
    /// 由一般 view 組成，而非向 backend 索取，因此每個 backend 都能取得，且無需任何實作。導覽列
    /// 不過是一個按鈕加一段文字，此處沒有任何 backend 能做得更好之處；而若為它另立
    /// `BackendFeatures` 協定，只會導致「在尚未實作它的 backend 上，堆疊完全無法返回」。
    ///
    /// 在此之前，`NavigationStack` 只能推入、無法彈出：`body` 在所有 backend 上都只繪製
    /// `elements.last`，因此唯一的返回途徑是應用程式自行提供的。此問題於 P24 實測發現——推入至
    /// 第 3 層後便無路可退。
    ///
    /// 標籤沿用 SwiftUI 的後備文字。SwiftUI 會顯示前一個視圖的標題，沒有標題時則顯示「Back」；
    /// 此處尚無導覽標題，因此後備文字即為全部。待 ``View/navigationTitle(_:)`` 加入後，此處便是
    /// 它的讀取點。
    @ViewBuilder
    private var navigationBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button("‹ Back") {
                    path.wrappedValue.removeLast()
                }
                Spacer()
            }
            .padding(8)

            Divider()
        }
    }

    @ViewBuilder
    private var currentDestination: some View {
        if let element = elements.last {
            if let content = child(element) {
                content
            } else {
                fatalError(
                    "Failed to find detail view for \"\(element)\", make sure you have called .navigationDestination for this type."
                )
            }
        } else {
            Text("Empty navigation path")
        }
    }

    /// A binding to the current navigation path.
    var path: Binding<NavigationPath>
    /// The types handled by each destination (in the same order as their
    /// corresponding views in the stack).
    var destinationTypes: [any Codable.Type]
    /// Gets a recursive ``EitherView`` structure which will have a single view
    /// visible suitable for displaying the given path element (based on its
    /// type).
    ///
    /// It's implemented as a recursive structure because that's the best way to keep this
    /// typesafe without introducing some crazy generated pseudo-variadic storage types of
    /// some sort. This way we can easily have unlimited navigation destinations and there's
    /// just a single simple method for adding a navigation destination.
    var child: (any Codable) -> Detail?
    /// The elements of the navigation path. The result can depend on
    /// ``NavigationStack/destinationTypes`` which determines how the keys are
    /// decoded if they haven't yet been decoded (this happens if they're loaded
    /// from disk for persistence).
    var elements: [any Codable] {
        let resolvedPath = path.wrappedValue.path(
            destinationTypes: destinationTypes
        )
        return [NavigationStackRootPath()] + resolvedPath
    }

    /// Creates a navigation stack with heterogeneous navigation state that you
    /// can control.
    ///
    /// - Parameters:
    ///   - path: A ``Binding`` to the navigation state for this stack.
    ///   - root: The view to display when the stack is empty.
    public init(
        path: Binding<NavigationPath>,
        @ViewBuilder _ root: @escaping () -> Detail
    ) {
        self.path = path
        destinationTypes = []
        child = { element in
            if element is NavigationStackRootPath {
                return root()
            } else {
                return nil
            }
        }
    }

    /// Associates a destination view with a presented data type for use within
    /// a navigation stack.
    ///
    /// Add this view modifer to describe the view that the stack displays when
    /// presenting a particular kind of data. Use a ``NavigationLink`` to
    /// present the data. You can add more than one navigation destination
    /// modifier to the stack if it needs to present more than one kind of data.
    ///
    /// - Parameters:
    ///   - data: The type of data that this destination matches.
    ///   - destination: A view builder that defines a view to display when the
    ///     stack's navigation state contains a value of type data. The closure
    ///     takes one argument, which is the value of the data to present.
    public func navigationDestination<D: Codable, C: View>(
        for data: D.Type,
        @ViewBuilder destination: @escaping (D) -> C
    ) -> NavigationStack<EitherView<Detail, C>> {
        // Adds another detail view by adding to the recursive structure of either views created
        // to display details in a type-safe manner. See NavigationStack.child for details.
        return NavigationStack<EitherView<Detail, C>>(
            previous: self,
            destination: destination
        )
    }

    /// Add a destination for a specific path element (by adding another layer of ``EitherView``).
    private init<PreviousDetail: View, NewDetail: View, Component: Codable>(
        previous: NavigationStack<PreviousDetail>,
        destination: @escaping (Component) -> NewDetail?
    ) where Detail == EitherView<PreviousDetail, NewDetail> {
        path = previous.path
        destinationTypes = previous.destinationTypes + [Component.self]
        child = {
            if let previous = previous.child($0) {
                // Either root or previously defined destination returned a view
                return EitherView(previous)
            } else if let component = $0 as? Component, let new = destination(component) {
                // This destination returned a detail view for the current element
                return EitherView(new)
            } else {
                // Possibly a future .navigationDestination will handle this path element
                return nil
            }
        }
    }

    /// Attempts to compute the detail view for the given element (the type of
    /// the element decides which detail is shown). Crashes if no suitable detail
    /// view is found.
    func childOrCrash(for element: some Codable) -> Detail {
        guard let child = child(element) else {
            fatalError(
                "Failed to find detail view for \"\(element)\", make sure you have called .navigationDestination for this type."
            )
        }

        return child
    }
}
