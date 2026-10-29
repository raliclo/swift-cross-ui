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
        let elements = self.elements
        return VStack(spacing: 0) {
            if elements.count > 1 {
                navigationBar(
                    backTitle: titleStore.title(
                        atDepth: elements.count - 2,
                        for: elements[elements.count - 2]
                    )
                )
            }
            currentDestination(elements)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The platform's own Back pops this stack too, while it has anything
        // pushed; see ``backTarget``.
        // 只要推入了任何內容，平台自己的返回也會彈出這個堆疊；見 ``backTarget``。
        .navigationBackRegistration(
            target: backTarget,
            canPop: elements.count > 1,
            pop: { [path] in
                guard !path.wrappedValue.isEmpty else { return nil }
                let previous = path.wrappedValue.independentCopy()
                path.wrappedValue.removeLast()
                return { path.wrappedValue = previous }
            }
        )
    }

    /// A back control, shown whenever anything has been pushed.
    ///
    /// Built from ordinary views rather than asked of the backend, so every
    /// backend gets it and none has to implement anything. A navigation bar is
    /// a button and a label; there is nothing here a backend could do better,
    /// and a `BackendFeatures` protocol for it would mean a stack with no way
    /// back on any backend that had not implemented it yet.
    ///
    /// **The label is the title of the screen it returns to**, as in SwiftUI:
    /// the root view's ``View/navigationTitle(_:)`` one level down, the
    /// previous destination's further down, and "Back" when that screen set no
    /// title.
    ///
    /// The title cannot be read in the same pass that draws the bar.
    /// `navigationTitle` is a ``PreferenceValues`` entry, and a preference
    /// travels *upward*, out of the destination and past this bar, which is its
    /// preceding sibling in the same `VStack`; by the time a destination's
    /// title exists, the bar above it has been laid out. The title shown here
    /// is therefore one that survived *between* passes: ``titleStore``, owned
    /// by the stack and keyed by path depth, is written by each screen (the
    /// root included) when it is committed, and read when the next screen is
    /// pushed on top of it. The screen being returned to was on screen before
    /// the push, so its title is always there when it is needed.
    ///
    /// Each entry also records which path element wrote it, so a title is
    /// never shown for a different screen that later took the same depth.
    /// A screen that has never been on screen -- a path restored from storage
    /// or assigned several levels at once -- has no entry, and its back control
    /// says "Back", SwiftUI's own fallback.
    ///
    /// **Native navigation bars.** UIKitBackend and AndroidBackend draw the
    /// *current* title in a bar of their own (`setToolbar(ofWindow:to:title:)`
    /// on UIKit, the title row of `hasNavigationTitle` on Android). Neither
    /// draws a back control, so this one is the only one on every backend, and
    /// it names the previous screen while the native bar names the current
    /// one.
    ///
    /// 只要曾經推入任何內容，就會顯示的返回控制項。
    ///
    /// 由一般 view 組成，而非向 backend 索取，因此每個 backend 都能取得，且無需任何實作。導覽列
    /// 不過是一個按鈕加一段文字，此處沒有任何 backend 能做得更好之處；而若為它另立
    /// `BackendFeatures` 協定，只會導致「在尚未實作它的 backend 上，堆疊完全無法返回」。
    ///
    /// **標籤是它所要返回的那個畫面的標題**,與 SwiftUI 相同：往下一層時是根 view 的 ``View/navigationTitle(_:)``,
    /// 更深時是前一個 destination 的標題；該畫面沒有設定標題時則是「Back」。
    ///
    /// 標題無法在繪製這條列的同一次計算中讀取。`navigationTitle` 是一個 ``PreferenceValues`` 項目，而 preference 是
    /// **向上**傳遞的：它從 destination 往外走，越過這條列——這條列在同一個 `VStack` 中是它的前一個兄弟節點；當某個
    /// destination 的標題存在時，它上方的列早已完成版面計算。因此此處顯示的是一個**跨越**多次計算而存續的標題:
    /// ``titleStore`` 由堆疊持有、以路徑深度為鍵，每個畫面(含根)在 commit 時寫入，並在下一個畫面被推到它上面時讀取。
    /// 要返回的那個畫面在推入之前就在螢幕上，因此需要它的標題時，標題一定已經在那裡。
    ///
    /// 每一筆也記錄是哪個路徑元素寫入的，因此標題絕不會顯示給之後佔用同一深度的另一個畫面。從未出現在螢幕上的畫面——
    /// 從儲存區還原的路徑、或一次指定好幾層——沒有紀錄，它的返回控制項顯示 SwiftUI 自己的後備文字「Back」。
    ///
    /// **原生導覽列。** UIKitBackend 與 AndroidBackend 會在自己的列中畫出**目前**的標題(UIKit 是
    /// `setToolbar(ofWindow:to:title:)`,Android 是 `hasNavigationTitle` 的那一列標題)。兩者都不畫返回控制項，因此在每個
    /// backend 上都只有這一個返回控制項，它稱呼前一個畫面，而原生列稱呼目前的畫面。
    @ViewBuilder
    private func navigationBar(backTitle: String?) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button("‹ \(backTitle ?? "Back")") {
                    path.wrappedValue.removeLast()
                }
                Spacer()
            }
            .padding(8)

            Divider()
        }
    }

    /// The top screen, wrapped so that it reports its title to ``titleStore``.
    /// 最上層的畫面，包裝起來以便向 ``titleStore`` 回報它的標題。
    @ViewBuilder
    private func currentDestination(_ elements: [any Codable]) -> some View {
        if let element = elements.last {
            if let content = child(element) {
                NavigationTitleRecorder(
                    content,
                    store: titleStore,
                    depth: elements.count - 1,
                    element: element
                )
            } else {
                fatalError(
                    "Failed to find detail view for \"\(element)\", make sure you have called .navigationDestination for this type."
                )
            }
        } else {
            Text("Empty navigation path")
        }
    }

    /// The titles the stack's screens reported, read by the back control.
    /// See ``navigationBar(backTitle:)``.
    /// 堆疊中各畫面所回報的標題，由返回控制項讀取。見 ``navigationBar(backTitle:)``。
    @State private var titleStore = NavigationTitleStore()

    /// This stack as its window's Back sees it -- the system Back and back
    /// gesture on Android, the left-edge swipe on iOS, Command-[ and the
    /// mouse's back button on macOS, Alt+Left, the Back key and the mouse's
    /// back button on GTK and WinUI. While the path is not empty, Back pops it
    /// as the drawn back control does; see ``NavigationBackRegistry`` for which
    /// of several stacks it pops.
    /// 視窗的返回所看到的這個堆疊——Android 的系統返回與返回手勢、iOS 的左緣滑動、macOS 的 Command-[ 與滑鼠返回鍵、
    /// GTK 與 WinUI 的 Alt+Left、返回鍵與滑鼠返回鍵。路徑不為空時，返回會像畫出的返回控制項一樣彈出它；多個堆疊時彈出
    /// 哪一個，見 ``NavigationBackRegistry``。
    @State private var backTarget = NavigationBackTarget()

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

/// The navigation titles a ``NavigationStack``'s screens reported, by path
/// depth, kept between layout passes for the stack's back control.
///
/// A reference type held in the stack's `@State`, written while a screen is
/// committed and read when the stack's body is next computed. Writing it does
/// not schedule an update: the value is only read for a screen *below* the
/// top one, and that screen reported its title while it was on top. It is an
/// `ObservableObject` with no `@Published` property, which is how `@State`
/// keeps one instance for the life of the stack without observing it.
///
/// ``NavigationStack`` 各畫面所回報的導覽標題，以路徑深度為鍵，跨越多次版面計算保存，供堆疊的返回控制項使用。
///
/// 一個放在堆疊 `@State` 裡的參考型別，在畫面 commit 時寫入，於堆疊的 body 下一次計算時讀取。寫入它不會排程更新：
/// 這個值只會為最上層**之下**的畫面讀取，而那個畫面在位於最上層時就已回報了它的標題。它是一個沒有 `@Published` 屬性的
/// `ObservableObject`,`@State` 因此在堆疊的整個生命期間保有同一個實例，而不觀察它。
@MainActor
final class NavigationTitleStore: ObservableObject {
    private struct Entry {
        var element: String
        var title: String?
    }

    private var entries: [Int: Entry] = [:]

    /// The title the screen at `depth` reported, if `element` is the path
    /// element that screen was showing.
    /// 位於 `depth` 的畫面所回報的標題——前提是 `element` 正是該畫面當時所顯示的路徑元素。
    func title(atDepth depth: Int, for element: any Codable) -> String? {
        guard let entry = entries[depth], entry.element == Self.key(for: element) else {
            return nil
        }
        return entry.title
    }

    /// Records the title of the screen at `depth`.
    /// 記錄位於 `depth` 之畫面的標題。
    func record(_ title: String?, atDepth depth: Int, for element: any Codable) {
        entries[depth] = Entry(element: Self.key(for: element), title: title)
    }

    /// Identifies a path element by its type and its value. Path elements are
    /// `Codable` but not necessarily `Hashable`, so the description stands in.
    /// 以型別與值識別一個路徑元素。路徑元素是 `Codable` 但不一定是 `Hashable`,因此以其描述代替。
    private static func key(for element: any Codable) -> String {
        "\(String(reflecting: type(of: element))):\(String(describing: element))"
    }
}

/// Passes its content through unchanged and records the content's navigation
/// title in a ``NavigationTitleStore`` when it is committed.
///
/// 原樣傳遞其內容，並在 commit 時把內容的導覽標題記錄到 ``NavigationTitleStore``。
struct NavigationTitleRecorder<Child: View>: View {
    var body: TupleView1<Child>
    var store: NavigationTitleStore
    var depth: Int
    var element: any Codable

    init(_ child: Child, store: NavigationTitleStore, depth: Int, element: any Codable) {
        self.body = TupleView1(child)
        self.store = store
        self.depth = depth
        self.element = element
    }

    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: any ViewGraphNodeChildren,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        body.computeLayout(
            widget,
            children: children,
            proposedSize: proposedSize,
            environment: environment,
            backend: backend
        )
    }

    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: any ViewGraphNodeChildren,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        store.record(layout.preferences.navigationTitle, atDepth: depth, for: element)
        body.commit(
            widget,
            children: children,
            layout: layout,
            environment: environment,
            backend: backend
        )
    }
}
