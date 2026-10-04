import DummyBackend
import Testing
@testable @_spi(Backends) import SwiftCrossUI

/// A proxy captured on one update must still find anchors laid out on a later one.
///
/// A `ScrollViewReader` is a value, rebuilt every time its parent's body runs.
/// Until 2026-10-05 each one created its own registry in `init`, so the view graph
/// laid out with the newest registry while a proxy captured earlier -- by
/// `onAppear`, or by a closure dispatched a moment later -- looked in an older one
/// that held nothing. `scrollTo` did nothing and nothing failed; SoftPCB-UI's log
/// views never reached their last line.
///
/// 在某次更新中捕捉到的 proxy,必須仍找得到之後那次排版所登記的錨點。`ScrollViewReader` 是一個值,父層的
/// body 每執行一次就重建一次。2026-10-05 之前,每一個都在 `init` 中建立自己的 registry,於是 view graph
/// 以最新的 registry 排版,而較早被捕捉的 proxy 仍在一個空的舊 registry 裡找。`scrollTo` 什麼都沒做,
/// 也沒有任何東西失敗;SoftPCB-UI 的日誌區因此從未捲到最後一行。
@Suite("ScrollViewReader")
@MainActor
struct ScrollViewReaderTests {
    final class Captured {
        var proxies: [ScrollViewProxy] = []
    }

    func reader(_ captured: Captured) -> some View {
        ScrollViewReader { proxy in
            let _ = captured.proxies.append(proxy)
            ScrollView {
                Text("row").id(7)
            }
        }
    }

    @Test("a proxy from the first update sees anchors registered on a later one")
    func proxySurvivesARebuiltReader() {
        let captured = Captured()
        let environment = ViewGraphHelpers.environment
        let node = ViewGraphNode(
            for: reader(captured), backend: ViewGraphHelpers.backend, environment: environment)
        _ = node.computeLayout(proposedSize: .unspecified, environment: environment)
        _ = node.commit()

        // The parent's body ran again: a brand-new reader value for the same node.
        // 父層的 body 又執行了一次:同一個節點拿到一個全新的 reader 值。
        _ = node.computeLayout(
            with: reader(captured), proposedSize: .unspecified, environment: environment)
        _ = node.commit()

        let first = try! #require(captured.proxies.first)
        let last = try! #require(captured.proxies.last)
        #expect(captured.proxies.count >= 2)
        #expect(first.registry === last.registry)
        #expect(first.registry.anchors[AnyHashable(7)] != nil)
    }
}
