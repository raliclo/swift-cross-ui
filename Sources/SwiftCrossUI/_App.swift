import DebugFeatures
import Foundation

// TODO: This could possibly be renamed to ``SceneGraph`` now that that's basically the role
//   it has taken on since introducing scenes.
/// A top-level wrapper providing an entry point for the app. Exists to be able to persist
/// the view graph alongside the app (we can't do that on a user's ``App`` implementation because
/// we can only add computed properties).
@MainActor
class _App<AppRoot: App> {
    /// The app being run.
    let app: AppRoot
    /// An instance of the app's selected backend.
    let backend: AppRoot.Backend
    /// The root of the app's scene graph.
    var sceneGraphRoot: AppRoot.Body.Node?
    /// Cancellables for observations of the app's state properties.
    var cancellables: [Cancellable]
    /// The root level environment.
    var environment: EnvironmentValues
    /// The dynamic property updater for ``app``.
    var dynamicPropertyUpdater: DynamicPropertyUpdater<AppRoot>

    /// Wraps a user's app implementation.
    init(_ app: AppRoot, backend: AppRoot.Backend) {
        self.backend = backend
        self.app = app
        self.environment = EnvironmentValues(backend: backend)
        self.cancellables = []

        dynamicPropertyUpdater = DynamicPropertyUpdater(for: app)
    }

    func refreshSceneGraph() {
        // TODO: Do we have to update dynamic properties on state changes?
        //   We can probably get away with only doing it when the root
        //   environment changes.
        dynamicPropertyUpdater.update(app, with: environment, previousValue: nil)

        if let sceneGraphRoot {
            let result = sceneGraphRoot.updateNode(app.body, environment: environment)
            if let backend = backend as? any BackendFeatures.ApplicationMenus {
                backend.setApplicationMenu(
                    result.preferences.commands.resolve(),
                    environment: environment
                )
            }
            sceneGraphRoot.update(
                backend: backend,
                environment: environment
            )
        }
    }

    /// Selects the graphics adapter the user asked for, and says what happened.
    ///
    /// This is the caller ``BackendFeatures/GraphicsAdapters`` did not have. Its
    /// own documentation recorded the hole on 2026-09-02 -- "there is no such
    /// caller ... nothing aborts today, because nothing asks" -- and a protocol
    /// nothing asks is a protocol whose conformances are never exercised, so a
    /// backend can conform incorrectly and no run will show it.
    ///
    /// Called before the scene graph is built, because ``applyAdapter(_:)`` is
    /// documented as running once before anything renders, and on Windows the
    /// answer can be ``AdapterOutcome/needsRestart(reason:)`` -- which is only
    /// useful if it arrives before a window exists.
    ///
    /// ALWAYS on stderr, never through the logger, and that is the same rule
    /// `GtkBackend.ensureGpuPreference` already follows: a request that cannot
    /// be honoured must not be answered by quietly doing something else. The
    /// whole reason the flag exists is to make the choice visible, and a
    /// notice-level line is exactly how it would go unnoticed. Nothing is
    /// printed when no selection was asked for.
    ///
    /// 選定使用者所要求的繪圖介面卡，並說明結果。
    ///
    /// 這正是 ``BackendFeatures/GraphicsAdapters`` 一直缺少的呼叫端。它自己的文件在 2026-09-02
    /// 記下了這個缺口——「並不存在那樣的呼叫端……今天不會有任何東西中止，因為根本沒有東西在問」
    /// ——而一個沒有人詢問的協定，其 conformance 永遠不會被執行到，因此某個 backend 可以實作錯誤
    /// 而沒有任何一次執行會顯示出來。
    ///
    /// 在建立 scene graph 之前呼叫，因為 ``applyAdapter(_:)`` 的文件載明它「在任何繪製之前執行
    /// 一次」；而在 Windows 上，答案可能是 ``AdapterOutcome/needsRestart(reason:)``——那個答案
    /// 只有在視窗尚未存在時抵達才有用。
    ///
    /// **一律輸出至 stderr**，不經 logger；這與 `GtkBackend.ensureGpuPreference` 早已遵循的規則
    /// 相同：一個無法被遵從的要求，絕不能以「安靜地做別的事」來回應。這個旗標存在的全部理由就是
    /// 讓選擇是可見的，而 notice 等級的一行正是它會被忽略的方式。未提出任何選擇時則不輸出。
    private func selectGraphicsAdapter() {
        // `1` is the default in every build including release, so treating it as
        // "nothing was asked for" is what keeps an ordinary run silent. `0` is a
        // real request -- software rendering -- and must not be swallowed by a
        // `!= 0` test, which is the mistake this guard is written to avoid.
        // `1` 在包含 release 的每一種建置中都是預設值，因此把它視為「什麼都沒要求」，正是讓一般
        // 執行保持安靜的關鍵。而 `0` 是一個**真實的**要求——軟體繪製——絕不能被 `!= 0` 之類的
        // 判斷吞掉；這個 guard 正是為了避開那個錯誤而寫成這樣。
        let number = DebugFeatures.gpuSelection
        guard number != 1 else { return }
        let requested = GraphicsAdapterSelection(number: number)

        guard let adapters = backend as? any BackendFeatures.GraphicsAdapters else {
            FileHandle.standardError.write(
                Data(
                    """
                    -GPU \(number): \(type(of: backend)) does not implement adapter selection, so \
                    the request was not honoured and rendering continues on whatever the platform \
                    chose.\n
                    """.utf8
                )
            )
            return
        }

        let resolution = requested.resolve(among: adapters.availableAdapters)
        let outcome = adapters.applyAdapter(resolution)
        let target = resolution.adapter?.name ?? "software rendering"
        let description: String
        switch outcome {
            case .applied: description = "using \(target)"
            case .alreadyActive: description = "already using \(target)"
            case .needsRestart(let reason): description = "not applied this run -- \(reason)"
            case .unavailable(let reason): description = "not available -- \(reason)"
        }

        // The fallback reason is printed WITH the outcome, never instead of it.
        // `GraphicsAdapterResolution` carries it for exactly this reason: a
        // selection that quietly resolved to something other than what was asked
        // for is the failure the whole feature exists to prevent, and `.applied`
        // on its own reads as success even when the answer is a different card.
        // 退路原因與結果**一併**輸出，絕不取代它。`GraphicsAdapterResolution` 之所以攜帶它，正是
        // 為了這件事：一個悄悄解析成別的東西的選擇，正是整個功能所要防止的失敗；而單獨的
        // `.applied` 即使答案是另一張卡，讀起來仍然像成功。
        let fallback = resolution.fellBackBecause.map { " (fell back: \($0))" } ?? ""
        FileHandle.standardError.write(
            Data("-GPU \(number): \(description)\(fallback)\n".utf8)
        )
    }

    /// Runs the app using the app's selected backend.
    func run() {
        backend.runMainLoop { [self] in
            selectGraphicsAdapter()

            let baseEnvironment = EnvironmentValues(backend: backend)
            environment = backend.computeRootEnvironment(
                defaultEnvironment: baseEnvironment
            )

            dynamicPropertyUpdater.update(app, with: environment, previousValue: nil)

            forEachField(of: app) { name, _, fieldValue in
                // Ungated. This is a migration notice for code that compiles and
                // then does nothing: an `App.state` that used to be observed no
                // longer is, and the app simply stops updating. Under `#if DEBUG`
                // it was missing from the release builds this project makes by
                // default, so the one configuration a user is likely to hit the
                // problem in was the one that would not explain it. The reflection
                // walk runs regardless, so the added cost is a string compare per
                // field, once, at startup.
                //
                // 不設條件。這是給「能編譯、但什麼也不做」的程式碼的遷移提示：原本會被觀察的
                // `App.state` 不再被觀察，於是 app 就此停止更新。原本置於 `#if DEBUG` 之下時，
                // 它在本專案預設產生的 release 建置中並不存在——也就是說，使用者最可能遇到此
                // 問題的那個組態，正是不會給出解釋的那一個。這趟 reflection 走訪本來就會執行，
                // 因此新增的代價只是啟動時每個欄位一次的字串比較。
                if name == "state", fieldValue is ObservableObject {
                    logger.warning(
                        """
                        the App.state protocol requirement has been removed in favour of \
                        SwiftUI-style @State annotations; decorate \(AppRoot.self).state \
                        with the @State property wrapper to restore previous behaviour
                        """
                    )
                }

                guard let value = fieldValue as? any ObservableProperty else {
                    return // i.e. continue
                }

                let cancellable =
                    value.didChange.observeAsUIUpdater(backend: backend) { [weak self] in
                        self?.refreshSceneGraph()
                    }
                cancellables.append(cancellable)
            }

            let rootNode = AppRoot.Body.Node(
                from: app.body,
                backend: backend,
                environment: environment
            )

            backend.setRootEnvironmentChangeHandler {
                self.environment = self.backend.computeRootEnvironment(
                    defaultEnvironment: baseEnvironment
                )
                self.refreshSceneGraph()
            }

            let result = rootNode.updateNode(nil, environment: environment)

            // Update application-wide menu
            if let backend = backend as? any BackendFeatures.ApplicationMenus {
                backend.setApplicationMenu(
                    result.preferences.commands.resolve(),
                    environment: environment
                )
            }

            rootNode.update(backend: backend, environment: environment)
            self.sceneGraphRoot = rootNode
        }
    }
}
