import DefaultBackend
import Foundation
import SwiftCrossUI

// P26 networking, compared against SwiftUI, in three tabs.
//
// SwiftUI does not exist on Linux or Windows, so nothing here runs SwiftUI --
// and the app says so rather than leaving a blank tab to be explained. The
// SwiftUI tab describes what SwiftUI would show, drawn with SwiftCrossUI; the
// SwiftCrossUI tab is the real thing, running.
//
// The pairing is the point. A description on its own is a claim, and a running
// view on its own has nothing to be judged against; side by side, a difference
// is visible without either being trusted.
//
// P26：網路功能與 SwiftUI 的比較，分為三個分頁。
//
// SwiftUI 在 Linux 與 Windows 上並不存在，因此此處沒有任何 SwiftUI 程式碼在執行——而本 app 會
// 明說此事，而非留下一個需要另行解釋的空白分頁。SwiftUI 分頁描述 SwiftUI 會呈現的內容，以
// SwiftCrossUI 繪製；SwiftCrossUI 分頁則是真正在執行的實作。
//
// 「成對呈現」正是重點。單獨的描述只是一項主張，單獨的執行畫面則無從評斷；兩者並列時，差異便無需
// 信任任何一方即可看見。
//
// Build this file as a standalone app target.

enum P26Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P26] \(message)")

        guard let data = "P26 \(Date()) \(message)\n".data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p26-debug-events.log")
        if FileManager.default.fileExists(atPath: url.path),
            let handle = try? FileHandle(forWritingTo: url)
        {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    static func renderComplete() {
        guard !didAnnounceRender else { return }
        didAnnounceRender = true
        write("RENDER COMPLETE -- P26 ready for networking checks")
    }
}

/// Where the cache would live, and whether it is switched on.
///
/// Read from the same place `AppCache` reads it so the two cannot disagree. A
/// report claiming "on" while the cache looked elsewhere would be worse than no
/// report.
///
/// 快取應存在的位置，以及它是否已啟用。
///
/// 與 `AppCache` 讀取同一處，因此兩者不可能不一致。一份宣稱「已啟用」但快取實際上另尋他處的報告，
/// 比沒有報告更糟。
enum P26Cache {
    /// `<platform caches>/<executable>/appCache`, mirroring `AppCache`.
    ///
    /// Not beside the executable, which is where an earlier version put it and
    /// where iOS cannot write at all -- the bundle is signed and read-only.
    ///
    /// 與 `AppCache` 一致：`<平台快取目錄>/<執行檔>/appCache`。
    ///
    /// 不在執行檔旁邊——早先的版本放在那裡，而 iOS 根本無法寫入該處：bundle 已簽章且唯讀。
    static var directory: URL? {
        guard
            let caches = FileManager.default.urls(
                for: .cachesDirectory,
                in: .userDomainMask
            ).first
        else { return nil }

        let name =
            Bundle.main.executableURL?.deletingPathExtension().lastPathComponent
            ?? "SwiftCrossUIApp"
        return caches.appendingPathComponent(name).appendingPathComponent("appCache")
    }

    /// Whether the directory exists yet.
    ///
    /// Not the same as whether caching is on: the cache is on by default and
    /// creates this on the first remote fetch, so a run reports `false` here
    /// until something has actually been fetched. Reporting it as "off" would
    /// be wrong; reporting the directory is the honest thing to show.
    ///
    /// 該目錄是否已存在。
    ///
    /// 這與「快取是否開啟」並非同一件事：快取預設開啟，並於第一次遠端抓取時建立此目錄，因此在真正
    /// 抓取任何東西之前，此處都會回報 `false`。把它說成「已關閉」是錯的；如實回報「目錄狀態」才是
    /// 誠實的呈現。
    static var exists: Bool {
        guard let directory else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// Rows in the index, not counting **two** header rows.
    ///
    /// A `.csv2` carries two, the second in Chinese. Subtracting one would
    /// report an extra entry that is not there, which is exactly the kind of
    /// off-by-one a cache report should not introduce.
    ///
    /// 索引中的資料列數，不計入**兩列**標頭。
    ///
    /// `.csv2` 帶有兩列標頭，第二列為中文。只減去一列會多報一筆並不存在的項目，而那正是快取報告
    /// 最不該引入的那種一位之差。
    static var indexRowCount: Int {
        guard let directory,
            let text = try? String(
                contentsOf: directory.appendingPathComponent("appCache.csv2"),
                encoding: .utf8
            )
        else { return 0 }
        return max(0, text.split(whereSeparator: \.isNewline).count - 2)
    }

    static var artifactCount: Int {
        guard let directory,
            let files = try? FileManager.default.contentsOfDirectory(
                atPath: directory.appendingPathComponent("artifacts").path
            )
        else { return 0 }
        return files.count
    }
}

/// One row of the comparison.
struct P26Feature: Identifiable {
    var id: Int
    var feature: String
    var swiftUI: String
    var swiftCrossUI: String
    var note: String
}

/// What each framework offers, as data rather than as prose.
///
/// Every row was checked against this repository rather than recalled: the
/// absent ones are absent from `Sources/` entirely, and the present ones name
/// the file they live in.
///
/// 各框架提供了什麼，以資料而非散文呈現。
///
/// 每一列都經由查閱本 repository 確認，而非憑記憶：標示為「無」者在 `Sources/` 中完全不存在，
/// 標示為「有」者則指出其所在的檔案。
let p26Features: [P26Feature] = [
    P26Feature(
        id: 0,
        feature: "URLSession",
        swiftUI: "Foundation, not SwiftUI",
        swiftCrossUI: "same, usable today",
        note: "FoundationNetworking on Linux"
    ),
    P26Feature(
        id: 1,
        feature: ".task { }",
        swiftUI: "yes",
        swiftCrossUI: "yes, both forms",
        note: "task(priority:) and task(id:priority:)"
    ),
    P26Feature(
        id: 2,
        feature: "AsyncImage",
        swiftUI: "yes",
        swiftCrossUI: "yes, added here",
        note: "Views/AsyncImage.swift"
    ),
    P26Feature(
        id: 3,
        feature: "AsyncImagePhase",
        swiftUI: "empty/success/failure",
        swiftCrossUI: "same three cases",
        note: "top-level, not nested in the generic"
    ),
    P26Feature(
        id: 4,
        feature: ".refreshable { }",
        swiftUI: "yes",
        swiftCrossUI: "no",
        note: "not implemented"
    ),
    P26Feature(
        id: 5,
        feature: "Image(url:) over http",
        swiftUI: "not offered",
        swiftCrossUI: "file URLs only now",
        note: "used to block layout; use AsyncImage"
    ),
    P26Feature(
        id: 6,
        feature: "disk cache",
        swiftUI: "URLCache",
        swiftCrossUI: "AppCache, opt-in",
        note: "appCache/ beside the executable"
    ),
    P26Feature(
        id: 7,
        feature: "cache revalidation",
        swiftUI: "URLCache policy",
        swiftCrossUI: "ETag / Last-Modified",
        note: "7 day ceiling, then pruned"
    ),
]

@main
struct P26NetworkingApp: App {
    var body: some Scene {
        WindowGroup("P26: networking") {
            P26RootView()
        }
        .defaultSize(width: 900, height: 660)
    }
}

struct P26RootView: View {
    @State var tab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TabView(selection: $tab) {
                Tab("Summary") { P26SummaryTab() }
                Tab("SwiftUI") { P26SwiftUITab() }
                Tab("SwiftCrossUI") { P26SwiftCrossUITab() }
            }
        }
        .onAppear {
            P26Diagnostics.write("cache dir \(P26Cache.directory?.path ?? "unknown")")
            P26Diagnostics.write("cache dir exists \(P26Cache.exists)")
            P26Diagnostics.write(
                "index rows \(P26Cache.indexRowCount), artifacts \(P26Cache.artifactCount)"
            )
            P26Diagnostics.renderComplete()
        }
    }
}

/// The comparison, as a selectable table.
///
/// Selectable because the point of a comparison is to be quoted somewhere else
/// -- an issue, a commit message, a note -- and a table you cannot copy out of
/// forces the reader to retype it. Off by default everywhere, so it is asked
/// for here explicitly.
///
/// 比較內容，以可選取的表格呈現。
///
/// 之所以可選取，是因為比較的用途正是被引用到別處——issue、commit 訊息、筆記——而一張無法複製的
/// 表格只會逼讀者重打一遍。此功能在各處預設關閉，因此在此明確要求開啟。
struct P26SummaryTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Networking: SwiftUI compared with SwiftCrossUI")
                .font(.system(size: 17))

            Text(
                "Drag across any cell to select it. Selection is opt-in per "
                    + "table, and this one asks for it."
            )

            Table(p26Features) {
                TableColumn("feature") { (row: P26Feature) in Text(row.feature) }
                TableColumn("SwiftUI") { (row: P26Feature) in Text(row.swiftUI) }
                TableColumn("SwiftCrossUI") { (row: P26Feature) in Text(row.swiftCrossUI) }
                TableColumn("note") { (row: P26Feature) in Text(row.note) }
            }
            .tableTextSelection()
        }
        .padding(14)
    }
}

/// What SwiftUI would show, described rather than run.
///
/// SwiftUI does not exist on Linux or Windows. A tab that tried to run it would
/// be empty, and an empty tab reads as a defect in this app rather than as a
/// fact about the platform -- so the tab says which it is.
///
/// SwiftUI 會呈現什麼，以描述而非執行的方式呈現。
///
/// SwiftUI 在 Linux 與 Windows 上並不存在。若某個分頁試圖執行它，結果會是一片空白，而空白分頁看
/// 起來像是本 app 的缺陷，而非關於平台的事實——因此該分頁會明說這是哪一種情況。
struct P26SwiftUITab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SwiftUI: expected behaviour")
                .font(.system(size: 17))

            Text(
                "Nothing on this tab is running SwiftUI. SwiftUI ships with "
                    + "Apple's platforms and does not exist on Linux or "
                    + "Windows, so this is what it would show, drawn with "
                    + "SwiftCrossUI."
            )

            Divider()

            Text("AsyncImage(url:) passes through three phases:")
            Text("   .empty      nothing loaded yet; the placeholder shows")
            Text("   .success    the image, handed to the content closure")
            Text("   .failure    the error, so a caller can tell it from a wait")

            Text("Caching is URLCache, on by default, in memory and on disk.")
            Text("Freshness follows Cache-Control, ETag and Last-Modified.")

            Divider()

            Text("Where SwiftCrossUI differs, and why:")
            Text("   the cache lives under the platform caches directory")
            Text("   entries expire after 7 days rather than being evicted by size")
            Text("   an expired entry is kept until a fetch succeeds, so offline keeps working")
            Text("   AsyncImage takes a cache policy; SwiftUI's does not")
            Text("   .refreshable has no equivalent yet")
        }
        .padding(14)
    }
}

/// The SwiftCrossUI implementation, running.
struct P26SwiftCrossUITab: View {
    @State var url = P26SwiftCrossUITab.requestedURL
    @State var clicks = 0

    static var requestedURL: URL? {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "-url"), index + 1 < arguments.count {
            return URL(string: arguments[index + 1])
        }
        return URL(string: "https://httpbin.org/image/png")
    }

    var policy: AppCache.CachePolicy {
        CommandLine.arguments.contains("-force")
            ? .reloadIgnoringLocalCacheData
            : .useProtocolCachePolicy
    }

    static func describe(_ phase: AsyncImagePhase) -> String {
        switch phase {
            case .empty: "loading..."
            case .success: "loaded"
            case .failure(let error): "failed -> \(error)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SwiftCrossUI: running")
                .font(.system(size: 17))

            Text("backend -> \(String(describing: DefaultBackend.self))")
            Text("url -> \(url?.absoluteString ?? "none")")
            // The path, not a yes/no. The cache is on by default and creates
            // the directory on the first fetch, so "off" would be wrong before
            // anything has been fetched -- and the path is what a tester
            // actually needs in order to go and look.
            // 顯示路徑而非是/否。快取預設開啟，並於第一次抓取時建立目錄，因此在抓取任何東西之前
            // 顯示「已關閉」是錯的——而測試者真正需要的，正是那個可以前往查看的路徑。
            Text("cache dir -> \(P26Cache.directory?.path ?? "unknown")")
            Text(
                "dir exists -> \(P26Cache.exists)   "
                    + "index rows -> \(P26Cache.indexRowCount)   "
                    + "artifacts -> \(P26Cache.artifactCount)"
            )

            // Press this while the image is loading. A response means the fetch
            // is not on the layout path, which is the whole difference between
            // AsyncImage and the old Image(url:) behaviour, and the one thing a
            // screenshot cannot show.
            // 請在影像載入期間按下此按鈕。有反應即代表該次抓取不在 layout 路徑上——那正是
            // AsyncImage 與舊的 Image(url:) 行為之間的全部差異，也是截圖唯一無法呈現的東西。
            Button("Clicks during load: \(clicks)") { clicks += 1 }

            // `-force` picks the policy that always fetches the body, so a
            // tester can see the difference between a cached run and a forced
            // one without editing anything.
            // `-force` 會選用「一律抓取完整 body」的政策，使測試者無須修改任何內容，即可看出
            // 「使用快取的執行」與「強制更新的執行」之間的差異。
            AsyncImage(url: url, policy: policy) { phase in
                if let image = phase.image {
                    image.resizable()
                } else {
                    Text(P26SwiftCrossUITab.describe(phase))
                }
            }
            .frame(width: 300, height: 200)
        }
        .padding(14)
    }
}
