import Foundation

/// Opens a URL with the default application.
///
/// May present an application picker if multiple applications are registered
/// for the given URL protocol.
///
/// An app can replace it for a subtree, as in SwiftUI:
/// `.environment(\.openURL, OpenURLAction { url in ... })`. The handler's
/// ``Result`` says whether the URL was handled, discarded, or passed on to the
/// system action (``Link`` and every other caller of
/// ``EnvironmentValues/openURL`` then go through it).
///
/// 以預設應用程式開啟 URL。
///
/// app 可以為某個子樹替換它，與 SwiftUI 相同:`.environment(\.openURL, OpenURLAction { url in ... })`。handler 的
/// ``Result`` 表示 URL 已被處理、被捨棄，或交給系統動作(``Link`` 以及 ``EnvironmentValues/openURL`` 的其他每個呼叫者
/// 都會經過它)。
@MainActor
public struct OpenURLAction {
    var action: (URL) -> Void

    /// The handler given to ``init(handler:)``; `nil` for the system action.
    /// 傳給 ``init(handler:)`` 的 handler;系統動作時為 `nil`。
    let handler: (@MainActor (URL) -> Result)?

    init<Backend: BaseAppBackend>(backend: Backend) {
        handler = nil
        action = { url in
            guard let backend = backend as? any BackendFeatures.ExternalURLs else {
                logger.warnOnce("\(type(of: backend)) doesn't support opening URLs")
                return
            }

            do {
                try backend.openExternalURL(url)
            } catch {
                logger.warning(
                    "failed to open external url",
                    metadata: [
                        "url": "\(url)",
                        "error": "\(error)",
                    ]
                )
            }
        }
    }

    /// Creates an action that opens URLs with `handler`.
    ///
    /// - Parameter handler: Called with each URL; its result says what
    ///   happened to it. ``Result/systemAction`` hands the URL (or another) to
    ///   the system action.
    ///
    /// 建立一個以 `handler` 開啟 URL 的動作。``Result/systemAction`` 會把該 URL(或另一個)交給系統動作。
    public init(handler: @escaping @MainActor (URL) -> Result) {
        self.handler = handler
        // Replaced by `resolved(fallingBackTo:)` when read from the environment.
        // 從 environment 讀取時由 `resolved(fallingBackTo:)` 取代。
        action = { url in _ = handler(url) }
    }

    /// This action, with ``Result/systemAction`` reaching `system`.
    /// 本動作，且 ``Result/systemAction`` 會送到 `system`。
    func resolved(fallingBackTo system: OpenURLAction) -> OpenURLAction {
        guard let handler else { return self }
        var resolved = self
        resolved.action = { url in
            switch handler(url).kind {
                case .handled, .discarded:
                    break
                case .systemAction(let replacement):
                    system(replacement ?? url)
            }
        }
        return resolved
    }

    /// Opens a URL with the default application.
    ///
    /// - Parameter url: The URL to open.
    public func callAsFunction(_ url: URL) {
        action(url)
    }

    /// What an ``OpenURLAction`` handler did with a URL.
    /// ``OpenURLAction`` 的 handler 如何處理一個 URL。
    public struct Result: Sendable {
        enum Kind: Sendable {
            case handled
            case discarded
            case systemAction(URL?)
        }

        let kind: Kind

        /// The handler opened the URL. / handler 已開啟該 URL。
        public static let handled = Result(kind: .handled)
        /// The handler declined the URL; nothing opens it. / handler 拒絕了該 URL;沒有東西會開啟它。
        public static let discarded = Result(kind: .discarded)
        /// The system action opens the URL. / 由系統動作開啟該 URL。
        public static let systemAction = Result(kind: .systemAction(nil))

        /// The system action opens `url` instead. / 改由系統動作開啟 `url`。
        public static func systemAction(_ url: URL) -> Result {
            Result(kind: .systemAction(url))
        }
    }
}

/// Holds the action an app put in place of the system one.
/// 存放 app 用來取代系統動作的動作。
struct CustomOpenURLKey: EnvironmentKey {
    static var defaultValue: OpenURLAction? { nil }
}

extension EnvironmentValues {
    /// The action an app put in place of the system one with
    /// `.environment(\.openURL, ...)`, or `nil`. Read through
    /// ``EnvironmentValues/openURL``.
    /// app 以 `.environment(\.openURL, ...)` 取代系統動作所放入的動作，或 `nil`。經由 ``EnvironmentValues/openURL`` 讀取。
    var customOpenURL: OpenURLAction? {
        get { self[CustomOpenURLKey.self] }
        set { self[CustomOpenURLKey.self] = newValue }
    }
}
