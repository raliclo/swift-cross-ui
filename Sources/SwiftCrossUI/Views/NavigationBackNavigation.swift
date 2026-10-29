import Foundation

extension EnvironmentValues {
    /// How many ``NavigationStack``s enclose the current view. Read by a stack
    /// to tell the window's Back how deeply it is nested.
    /// 包住目前 view 的 ``NavigationStack`` 有幾層。堆疊讀取它，以告訴視窗的返回自己巢狀在多深的位置。
    @Entry var navigationStackNesting: Int = 0
}
/// Pops a stack's top screen and returns what puts it back, or returns `nil`
/// when there was nothing to pop.
/// 彈出堆疊最上層的畫面，並回傳把它放回去的動作；沒有東西可彈出時回傳 `nil`。
typealias NavigationBackPop = () -> (() -> Void)?

/// Undoes the last Back, for a backend whose Back follows the finger.
///
/// An interactive swipe (UIKitBackend's edge swipe) pops as soon as the swipe
/// begins, so that the screen underneath is the real previous screen while
/// the finger moves, and calls ``undoLastBack()`` if the swipe is cancelled.
/// Only the most recent Back can be undone, and only once.
///
/// 復原上一次返回，供返回會跟著手指移動的 backend 使用。互動式滑動(UIKitBackend 的邊緣滑動)在滑動開始時就彈出，
/// 讓手指移動期間底下的畫面就是真正的前一個畫面；滑動取消時呼叫 ``undoLastBack()``。只有最近一次返回可以復原，且只能一次。
@_spi(Backends)
@MainActor
public enum BackNavigationUndo {
    /// Restores the path the last Back changed. Returns `false` when there is
    /// nothing to undo.
    /// 還原上一次返回改變的路徑。沒有可復原的東西時回傳 `false`。
    @discardableResult
    public static func undoLastBack() -> Bool {
        guard let undo = NavigationBackRegistry.takeLastUndo() else { return false }
        undo()
        return true
    }
}


/// One ``NavigationStack`` as its window's Back sees it.
///
/// Held in the stack's `@State`, so there is one per stack for as long as the
/// stack is in the view graph. ``NavigationBackRegistry`` refers to it weakly;
/// when the stack leaves the graph the target is released and the registry
/// forgets it.
///
/// 視窗的返回所看到的一個 ``NavigationStack``。
///
/// 放在堆疊的 `@State` 中，因此只要堆疊還在 view graph 裡，每個堆疊就恰好有一個。``NavigationBackRegistry``
/// 以弱參考指向它；堆疊離開 graph 時 target 被釋放，registry 也就忘了它。
@MainActor
final class NavigationBackTarget: ObservableObject {
    /// Pops the stack's top screen. Replaced on every commit, because the
    /// stack's path binding can be a different binding each time.
    /// 彈出堆疊最上層的畫面。每次 commit 都會替換，因為堆疊的路徑 binding 每次都可能是不同的 binding。
    var pop: NavigationBackPop?
    /// Whether the stack's path has anything on it. 堆疊的路徑上是否有任何東西。
    var canPop = false
    /// The number of stacks around this one. 包住此堆疊的堆疊數。
    var nesting = 0
    /// When the stack last went from nothing pushed to something pushed; among
    /// stacks nested equally deep, the latest one is the one Back pops.
    /// 堆疊最近一次從「沒有推入」變成「有推入」的時間順序；在巢狀深度相同的堆疊之間，返回彈出最晚的那個。
    var order = 0

    /// The window this target is registered in. Read by `deinit`, which is not
    /// isolated to the main actor; it is written only on the main actor.
    /// 此 target 登記所在的視窗。由不屬於 main actor 的 `deinit` 讀取；只在 main actor 上寫入。
    nonisolated(unsafe) var windowKey: ObjectIdentifier?

    deinit {
        // The window's handler may now have nothing left to pop; let the
        // registry decide whether to remove it. A target that was never
        // registered -- `@State` builds and discards one each time the stack's
        // initializer runs -- has nothing to tell.
        // 視窗的 handler 現在可能已沒有東西可彈出；交由 registry 決定是否移除它。從未登記過的 target
        // ——每次堆疊的初始化執行時,`@State` 都會建一個再丟掉——沒有任何事要通知。
        if let windowKey {
            Task { @MainActor in
                NavigationBackRegistry.refresh(windowKey)
            }
        }
    }
}

/// The ``NavigationStack``s of each window, for the platform's own Back.
///
/// **Which stack Back pops.** The innermost stack whose path is not empty:
/// the one with the most stacks around it, and among equally nested stacks
/// the one whose path most recently became non-empty. A stack inside a pushed
/// screen of another is nested deeper, so Back empties the inner stack before
/// it pops the screen that holds it, as nested navigation does on every
/// platform.
///
/// **When the backend has a handler.** Only while some stack in the window can
/// pop. With nothing to pop the handler is removed, so the platform's Back
/// does what it does without one -- on Android, finishing the activity or
/// meeting the `windowDismissBehavior` interception. Stacks report on every
/// commit, which is also when a pop shows up: the pop changes the path, the
/// stack's body is computed again and the stack reports its new depth. A stack
/// that leaves the graph is noticed when its target is released.
///
/// **A stack in a sheet is registered with the sheet**, not its window: the
/// sheet's own window on macOS and GTK, its presented controller on iOS, its
/// dialog on Android and WinUI. While a stack in the sheet can pop, Back pops
/// it; otherwise Back in the sheet does what the platform did before (on
/// Android, dismissing the sheet only if it was dismissable). The window's
/// Back never reaches under a sheet into a stack of the window.
///
/// 每個視窗的 ``NavigationStack``,供平台自己的返回使用。
///
/// **返回彈出哪個堆疊。** 路徑不為空的最內層堆疊：包住它的堆疊最多的那個；巢狀深度相同時，取路徑最近一次變成
/// 非空的那個。位於另一個堆疊之推入畫面內的堆疊巢狀更深，因此返回會先清空內層堆疊，再彈出容納它的那個畫面，與每個
/// 平台上的巢狀導覽相同。
///
/// **backend 何時有 handler。** 只在視窗中有某個堆疊可以彈出的期間。沒有可彈出的東西時 handler 會被移除，平台的
/// 返回便做它沒有 handler 時會做的事——在 Android 上是結束 activity,或遇上 `windowDismissBehavior` 的攔截。
/// 堆疊在每次 commit 時回報，而彈出也正是在那時顯現：彈出改變了路徑，堆疊的 body 重新計算，堆疊回報新的深度。
/// 離開 graph 的堆疊，在它的 target 被釋放時被察覺。
///
/// **sheet 中的堆疊登記在該 sheet 上**,而不是它的視窗:macOS 與 GTK 上是 sheet 自己的視窗,iOS 上是被呈現的 controller,
/// Android 與 WinUI 上是 dialog。sheet 中有可彈出的堆疊時，返回彈出它；否則 sheet 的返回維持平台原本的行為(例如 Android
/// 只在 sheet 本來可關閉時才關閉它)。視窗的返回永遠不會穿到 sheet 底下，彈出視窗中的堆疊。
@MainActor
enum NavigationBackRegistry {
    private final class WeakTarget {
        weak var target: NavigationBackTarget?

        init(_ target: NavigationBackTarget) {
            self.target = target
        }
    }

    private final class WindowEntry {
        var targets: [WeakTarget] = []
        /// Whether the backend currently has this registry's handler.
        /// backend 目前是否持有此 registry 的 handler。
        var isInstalled = false
        /// Sets (`true`) or removes (`false`) the backend's handler.
        /// 設定(`true`)或移除(`false`)backend 的 handler。
        let install: @MainActor (Bool) -> Void

        init(install: @escaping @MainActor (Bool) -> Void) {
            self.install = install
        }
    }

    private static var windows: [ObjectIdentifier: WindowEntry] = [:]
    private static var nextOrder = 0
    /// Puts back what the last Back popped, for ``BackNavigationUndo``.
    /// 把上一次返回彈出的東西放回去，供 ``BackNavigationUndo`` 使用。
    private static var lastUndo: (() -> Void)?

    static func takeLastUndo() -> (() -> Void)? {
        defer { lastUndo = nil }
        return lastUndo
    }

    /// Records a stack's state after it has been committed.
    /// 在堆疊 commit 之後記錄它的狀態。
    static func update<Backend: BaseAppBackend>(
        _ target: NavigationBackTarget,
        canPop: Bool,
        pop: @escaping NavigationBackPop,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        // A stack in a sheet belongs to the sheet: Back in the sheet pops it,
        // and the window's Back never reaches under the sheet.
        // sheet 中的堆疊屬於該 sheet:sheet 中的返回彈出它，而視窗的返回永遠不會穿到 sheet 底下。
        let owner: AnyObject
        let makeInstaller: (ObjectIdentifier) -> @MainActor (Bool) -> Void
        if let sheet = environment.sheet.map({ $0 as AnyObject }) {
            guard let navigation = backend as? any BackendFeatures.SheetBackNavigation else {
                return
            }
            owner = sheet
            makeInstaller = { sheetInstaller(navigation, sheet: sheet, key: $0) }
        } else {
            guard
                let window = environment.window.map({ $0 as AnyObject }),
                let navigation = backend as? any BackendFeatures.BackNavigation
            else {
                return
            }
            owner = window
            makeInstaller = { installer(navigation, window: window, key: $0) }
        }

        let key = ObjectIdentifier(owner)
        if let previous = target.windowKey, previous != key {
            remove(target, from: previous)
        }

        let entry: WindowEntry
        if let existing = windows[key] {
            entry = existing
        } else {
            entry = WindowEntry(install: makeInstaller(key))
            windows[key] = entry
        }

        if canPop && !target.canPop {
            target.order = nextOrder
            nextOrder += 1
        }
        target.canPop = canPop
        target.pop = pop
        target.nesting = environment.navigationStackNesting
        target.windowKey = key
        if !entry.targets.contains(where: { $0.target === target }) {
            entry.targets.append(WeakTarget(target))
        }
        refresh(key)
    }

    /// Pops the innermost stack that can pop. Returns `false` when none can,
    /// which tells the backend to let Back through.
    /// 彈出可彈出的最內層堆疊。沒有任何堆疊可彈出時回傳 `false`,告訴 backend 讓返回通過。
    static func goBack(in key: ObjectIdentifier) -> Bool {
        guard let entry = windows[key] else { return false }
        entry.targets.removeAll { $0.target == nil }
        let candidate = entry.targets
            .compactMap(\.target)
            .filter(\.canPop)
            .max { ($0.nesting, $0.order) < ($1.nesting, $1.order) }
        guard let candidate, let pop = candidate.pop, let undo = pop() else {
            refresh(key)
            return false
        }
        lastUndo = undo
        return true
    }

    /// Gives the window's backend a handler while some stack can pop, and
    /// removes it once none can.
    /// 有堆疊可彈出時給視窗的 backend 一個 handler,沒有任何堆疊可彈出時移除它。
    static func refresh(_ key: ObjectIdentifier) {
        guard let entry = windows[key] else { return }
        entry.targets.removeAll { $0.target == nil }
        let canGoBack = entry.targets.contains { $0.target?.canPop == true }
        if canGoBack != entry.isInstalled {
            entry.isInstalled = canGoBack
            entry.install(canGoBack)
        }
        if entry.targets.isEmpty {
            windows[key] = nil
        }
    }

    /// Sets or removes the registry's handler on `window`, which the closure
    /// holds weakly: the registry must not keep a closed window alive.
    /// 在 `window` 上設定或移除 registry 的 handler;closure 以弱參考持有視窗:registry 不可讓已關閉的視窗繼續存活。
    private static func installer<NewBackend: BackendFeatures.BackNavigation>(
        _ backend: NewBackend,
        window: AnyObject,
        key: ObjectIdentifier
    ) -> @MainActor (Bool) -> Void {
        return { @MainActor [weak window] (isInstalled: Bool) -> Void in
            guard let object = window, let window = object as? NewBackend.Window else {
                return
            }
            if isInstalled {
                backend.setBackNavigationHandler(ofWindow: window) { @MainActor () -> Bool in
                    NavigationBackRegistry.goBack(in: key)
                }
            } else {
                backend.setBackNavigationHandler(ofWindow: window, to: nil)
            }
        }
    }

    /// The same for a sheet: its own window on macOS and GTK, its presented
    /// controller on iOS, its dialog on Android and WinUI.
    /// sheet 的同一件事:macOS 與 GTK 上是它自己的視窗,iOS 上是它被呈現的 controller,Android 與 WinUI 上是它的 dialog。
    private static func sheetInstaller<NewBackend: BackendFeatures.SheetBackNavigation>(
        _ backend: NewBackend,
        sheet: AnyObject,
        key: ObjectIdentifier
    ) -> @MainActor (Bool) -> Void {
        return { @MainActor [weak sheet] (isInstalled: Bool) -> Void in
            guard let object = sheet, let sheet = object as? NewBackend.Sheet else {
                return
            }
            if isInstalled {
                backend.setBackNavigationHandler(ofSheet: sheet) { @MainActor () -> Bool in
                    NavigationBackRegistry.goBack(in: key)
                }
            } else {
                backend.setBackNavigationHandler(ofSheet: sheet, to: nil)
            }
        }
    }

    private static func remove(_ target: NavigationBackTarget, from key: ObjectIdentifier) {
        windows[key]?.targets.removeAll { $0.target === target || $0.target == nil }
        refresh(key)
    }
}

extension View {
    /// Reports the enclosing ``NavigationStack`` to its window's Back. See
    /// ``NavigationBackRegistry``.
    /// 把外層的 ``NavigationStack`` 回報給它所在視窗的返回。見 ``NavigationBackRegistry``。
    func navigationBackRegistration(
        target: NavigationBackTarget,
        canPop: Bool,
        pop: @escaping NavigationBackPop
    ) -> NavigationBackRegistrar<Self> {
        NavigationBackRegistrar(self, target: target, canPop: canPop, pop: pop)
    }
}

/// Passes its content through with one more level of
/// ``EnvironmentValues/navigationStackNesting``, and reports the stack it
/// belongs to to ``NavigationBackRegistry`` when it is committed.
///
/// 原樣傳遞其內容，但把 ``EnvironmentValues/navigationStackNesting`` 加一層，並在 commit 時把它所屬的堆疊回報給
/// ``NavigationBackRegistry``。
struct NavigationBackRegistrar<Child: View>: View {
    var body: TupleView1<Child>
    var target: NavigationBackTarget
    var canPop: Bool
    var pop: NavigationBackPop

    init(_ child: Child, target: NavigationBackTarget, canPop: Bool, pop: @escaping NavigationBackPop) {
        self.body = TupleView1(child)
        self.target = target
        self.canPop = canPop
        self.pop = pop
    }

    private func inner(_ environment: EnvironmentValues) -> EnvironmentValues {
        environment.with(\.navigationStackNesting, environment.navigationStackNesting + 1)
    }

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> any ViewGraphNodeChildren {
        body.children(
            backend: backend,
            snapshots: snapshots,
            environment: inner(environment)
        )
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
            environment: inner(environment),
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
        body.commit(
            widget,
            children: children,
            layout: layout,
            environment: inner(environment),
            backend: backend
        )
        NavigationBackRegistry.update(
            target,
            canPop: canPop,
            pop: pop,
            environment: environment,
            backend: backend
        )
    }
}
