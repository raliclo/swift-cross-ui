import AndroidKit
import Foundation
@_spi(Backends) import SwiftCrossUI
import SwiftJava

/// `BackendFeatures.IncomingURLs`: the URL an app is opened with, and every one
/// sent to it while it runs.
///
/// Two sources, because Android has two. An app *launched* by a link gets it as
/// the data of the intent that started the activity, which is read once when
/// the handler is first set. An app *already running* -- `singleTop`, or a
/// link opened while it is in front -- gets `onNewIntent`, which reaches Swift
/// through an `ActivityListener` this file installs whether or not the app
/// passed its own `ActivityDelegate`. URLs that arrive before the view graph
/// sets its handler are queued and replayed, as UIKitBackend does.
///
/// Until 2026-10-06 Android was the one shipped backend without this: the
/// conformance was absent and `setIncomingURLHandler` was upstream's commented
/// stub, so `.onOpenURL` never fired.
///
/// `BackendFeatures.IncomingURLs`:app 被開啟時帶的 URL,以及執行中送給它的每一個 URL。來源有兩個，因為
/// Android 有兩個：被連結**啟動**的 app,從啟動 activity 的那個 intent 的 data 取得，於第一次設定處理器時讀一次；
/// **已在執行**的 app 收到 `onNewIntent`,經由本檔安裝的 `ActivityListener` 到達 Swift——不論 app 有沒有傳入自己的
/// `ActivityDelegate`。在 view graph 設定處理器之前抵達的 URL 會先排隊、之後重播，與 UIKitBackend 相同。
/// 2026-10-06 之前 Android 是唯一沒有此功能的已發布 backend:沒有 conformance,`setIncomingURLHandler` 是上游
/// 註解掉的樁，所以 `.onOpenURL` 從未觸發。
extension AndroidBackend: BackendFeatures.IncomingURLs {
    public func setIncomingURLHandler(to action: @escaping (URL) -> Void) {
        Self.installIncomingURLListener(helpers: helpers)
        if !Self.didReadLaunchURL {
            Self.didReadLaunchURL = true
            if let url = Self.url(in: Self.activity.getIntent(), helpers: helpers) {
                Self.queuedURLs.append(url)
            }
        }
        let queued = Self.queuedURLs
        Self.queuedURLs = []
        Self.incomingURLHandler = action
        runInMainThread {
            for url in queued {
                action(url)
            }
        }
    }

    nonisolated(unsafe) static var incomingURLHandler: ((URL) -> Void)?
    nonisolated(unsafe) static var queuedURLs: [URL] = []
    nonisolated(unsafe) static var didReadLaunchURL = false
    nonisolated(unsafe) static var didInstallIncomingURLListener = false

    static func url(in intent: Intent?, helpers: AndroidBackendHelpers) -> URL? {
        guard let string = helpers.getIntentDataString(intent)?.toString(),
            !string.isEmpty
        else {
            return nil
        }
        guard let url = URL(string: string) else {
            logger.warning("incoming intent data is not a URL", metadata: ["data": "\(string)"])
            return nil
        }
        return url
    }

    static func deliver(_ url: URL) {
        logger.info("incoming URL", metadata: ["url": "\(url.absoluteString)"])
        if let incomingURLHandler {
            incomingURLHandler(url)
        } else {
            queuedURLs.append(url)
        }
    }

    static func installIncomingURLListener(helpers: AndroidBackendHelpers) {
        guard !didInstallIncomingURLListener else { return }
        didInstallIncomingURLListener = true
        let listener = IncomingURLListener(helpers: helpers)
        // Kept alive by the activity, as `init(delegate:)` relies on too.
        // 由 activity 保持存活，與 `init(delegate:)` 所依賴的相同。
        _ = ActivityListener(
            activity.as(FragmentActivity.self)!,
            SwiftObject(listener, environment: env),
            environment: env
        )
    }
}

/// Hands `onNewIntent`'s URL to the backend.
/// 把 `onNewIntent` 的 URL 交給 backend。
/// `@unchecked Sendable` as `ActivityListener` is: it is only ever called on
/// the main thread, from the activity's callbacks.
/// `@unchecked Sendable`,與 `ActivityListener` 相同：它只會在主執行緒上、從 activity 的回呼被呼叫。
final class IncomingURLListener: ActivityDelegate, @unchecked Sendable {
    let helpers: AndroidBackendHelpers

    init(helpers: AndroidBackendHelpers) {
        self.helpers = helpers
    }

    func onNewIntent(for activity: FragmentActivity, intent: Intent, env: JNIEnvironment?) {
        // On the main thread already -- `ActivityListener.onNewIntent` runs this
        // inside `MainActor.assumeIsolated` -- but the protocol requirement is
        // nonisolated, so it is said again here.
        // 已在主執行緒上——`ActivityListener.onNewIntent` 在 `MainActor.assumeIsolated` 內呼叫此處——
        // 但協定要求是 nonisolated,所以這裡再宣告一次。
        MainActor.assumeIsolated {
            if let url = AndroidBackend.url(in: intent, helpers: helpers) {
                AndroidBackend.deliver(url)
            }
        }
    }
}
