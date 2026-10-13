/// Which window scenes open when the app launches, decided over all of them at once.
///
/// Measured on a SwiftUI app with `WindowGroup("Alpha")`, `WindowGroup("Beta")`
/// and `Window("Solo")` (macOS, 2026-10-14):
///
/// | scenes | windows at launch |
/// | --- | --- |
/// | Alpha, Beta, Solo, nothing set | Alpha |
/// | Solo, Alpha, Beta, nothing set | Solo |
/// | Beta `.presented` | Beta only -- not Alpha |
/// | Solo `.presented` | Solo only -- not Alpha |
/// | Alpha `.suppressed` | none -- Beta does not take its place |
///
/// So: the scenes marked `.presented` open, and where none is marked the first
/// scene opens unless it is `.suppressed`. A scene cannot decide that in its own
/// initialiser, which is where each used to: it does not know what follows it.
/// Every `WindowGroup` opened a window that way, two for two groups (P93).
///
/// app 啟動時開哪些視窗場景，由全部場景一起決定。在 SwiftUI 上量到的結果如上表:標了 `.presented` 的場景會開;
/// 都沒標時只開第一個場景，除非它是 `.suppressed`。單一場景在自己的初始化式裡做不了這個決定，因為它不知道後面還有什麼;
/// 以前每個 `WindowGroup` 都各開一個視窗(P93 兩個 group 就是兩個)。
@MainActor
enum SceneLaunch {
    private struct Candidate {
        var behavior: SceneLaunchBehavior
        var open: @MainActor () -> Void
    }

    private static var candidates: [Candidate] = []
    private static var isCollecting = false

    /// Collects the window scenes made while `makeScenes` runs, then opens the
    /// ones the rule picks.
    /// 收集 `makeScenes` 執行期間建立的視窗場景，再開啟規則選中的那些。
    static func launch<T>(_ makeScenes: () -> T) -> T {
        isCollecting = true
        candidates = []
        let result = makeScenes()
        isCollecting = false
        let collected = candidates
        candidates = []
        if collected.contains(where: { $0.behavior == .presented }) {
            for candidate in collected where candidate.behavior == .presented {
                candidate.open()
            }
        } else if let first = collected.first, first.behavior == .automatic {
            first.open()
        }
        return result
    }

    /// A window scene's node calls this from its initialiser instead of opening
    /// its window there.
    ///
    /// A node made after launch has no other scenes to be weighed against, so it
    /// opens for `.presented` and, where `opensAlone` says the kind of scene
    /// always did, for `.automatic`.
    ///
    /// 視窗場景的節點在初始化式裡呼叫這個，而不是直接在那裡開視窗。啟動之後才建立的節點沒有其他場景可比，
    /// 所以 `.presented` 會開;`opensAlone` 表示這類場景一向如此時，`.automatic` 也會開。
    static func register(
        _ behavior: SceneLaunchBehavior,
        opensAlone: Bool,
        open: @escaping @MainActor () -> Void
    ) {
        if isCollecting {
            candidates.append(Candidate(behavior: behavior, open: open))
        } else if behavior == .presented || (behavior == .automatic && opensAlone) {
            open()
        }
    }
}
