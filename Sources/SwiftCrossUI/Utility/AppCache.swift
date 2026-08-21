import Foundation

// URLSession lives in FoundationNetworking on Linux, and in Foundation on
// Apple platforms and Windows. Without this the module builds on Windows and
// fails on Linux with "cannot find 'URLSession' in scope", which reads as a
// missing dependency rather than as a missing import.
// 在 Linux 上 URLSession 位於 FoundationNetworking，在 Apple 平台與 Windows 上則位於
// Foundation。少了這段，此模組在 Windows 上建置成功、在 Linux 上卻以「cannot find 'URLSession'
// in scope」失敗，而該訊息看起來像是缺少依賴，而非缺少 import。
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// An on-disk cache for things fetched over the network.
///
/// On by default, creating its directory on the first remote fetch, and turned
/// off with ``disable()``.
///
/// In the platform's cache directory, under the executable's name:
///
/// ```
/// <caches>/<executable>/appCache/
///   appCache.csv2      the index -- RFC 4180 CSV with two header rows
///   artifacts/
///     <uuid>.<suffix>  the payload, named so nothing collides
/// ```
///
/// `<caches>` is `Library/Caches` on Apple's platforms, `~/.cache` on Linux and
/// `%LOCALAPPDATA%` on Windows. **Not beside the executable**, which was the
/// first design and does not work on iOS at all: an app bundle is signed and
/// read-only, so writing into it fails and would break the signature even if it
/// did not. Apple's storage guidelines also require regenerable data to live
/// here, and put it outside the device backup.
///
/// Not the temporary directory either, though that is writable on every
/// platform too. iOS purges `tmp` whenever the app is not running, and most
/// Linux distributions clear `/tmp` on boot -- so a cache kept there is emptied
/// by the system at exactly the moments this one is careful not to empty it.
/// The point of surviving a failed fetch is lost if the files are gone anyway.
///
/// Artifacts are named by UUID rather than by anything derived from the URL. A
/// URL is not a filename: it can be longer than the filesystem allows, contain
/// separators, differ from another only in case, or be the same resource spelled
/// two ways. The index maps one to the other, and the suffix is kept so the file
/// is still openable by hand.
///
/// 網路資源的磁碟快取。
///
/// 在應用程式呼叫 ``enable()`` 之前不啟用。一個 UI 框架若只因某個 view 收到 `https` URL 就開始
/// 寫入使用者的磁碟，等於做了作者從未同意的事。
///
/// 位置為平台的快取目錄，並以執行檔名稱作為子目錄（如上）。
///
/// `<caches>` 在 Apple 平台為 `Library/Caches`，Linux 為 `~/.cache`，Windows 為
/// `%LOCALAPPDATA%`。**不放在執行檔旁邊**——那是最初的設計，而它在 iOS 上根本行不通：app bundle
/// 已簽章且唯讀，寫入會失敗；即使寫得進去也會破壞簽章。Apple 的儲存指引亦要求可重新產生的資料放在
/// 此處，並將其排除於裝置備份之外。
///
/// 也不使用暫存目錄，儘管它在每個平台上同樣可寫。iOS 會在 app 未執行時清除 `tmp`，而多數 Linux
/// 發行版會在開機時清空 `/tmp`——因此放在那裡的快取，會被系統在「本實作正小心翼翼不去清空它」的
/// 那些時刻清空。若檔案終究會消失，「撐過一次失敗的抓取」也就失去了意義。
///
/// artifact 以 UUID 命名，而非由 URL 衍生。URL 不是檔名：它可能超過檔案系統允許的長度、含有分隔
/// 字元、與另一個僅大小寫不同，或是同一資源的兩種寫法。索引負責兩者之間的對應，而保留副檔名是為了
/// 讓該檔案仍能以人手開啟。
public actor AppCache {
    public static let shared = AppCache()

    /// How long an entry may live. After this it is deleted, payload and row
    /// together, on the next time the index is opened.
    ///
    /// A ceiling rather than a freshness window. Freshness is decided per
    /// request by revalidating against the server -- see ``data(for:)`` -- so
    /// this is the point past which an entry is not kept at all, even if the
    /// resource has not changed.
    ///
    /// 一筆項目可存活多久。逾期後，其內容與索引列會在下一次開啟索引時一併刪除。
    ///
    /// 這是上限而非新鮮度視窗。新鮮度由每次請求向伺服器重新驗證決定（見 ``data(for:)``），因此
    /// 此處是「即使資源未變更也不再保留」的界線。
    public static let maximumAge: TimeInterval = 7 * 24 * 60 * 60

    private var index: [String: Entry]?
    private var directory: URL?
    /// On by default. The directory is created on the first remote fetch.
    ///
    /// Two earlier designs made this opt-in -- a directory the developer
    /// created by hand, then an explicit call -- on the grounds that a UI
    /// framework should not write to the user's disk unbidden. That argument
    /// held while the cache lived beside the executable. It does not hold here:
    /// the platform's cache directory exists for exactly this, the operating
    /// system manages and purges it, and an application that fetches a remote
    /// image has already asked for the network.
    ///
    /// ``disable()`` is still there for a test that wants a cold fetch every
    /// time, or an application that would rather not keep anything.
    ///
    /// 預設開啟。目錄於第一次遠端抓取時建立。
    ///
    /// 先前兩版設計都是 opt-in——先是由開發者手動建立目錄，後是顯式呼叫——理由是「UI 框架不應不問
    /// 自明地寫入使用者的磁碟」。當快取位於執行檔旁時，該理由成立；在此處則否：平台的快取目錄正是
    /// 為此而存在，由作業系統管理與清除，而一個會去抓取遠端影像的應用程式，本來就已經要求了網路。
    ///
    /// ``disable()`` 仍然保留，供「每次都要冷抓取」的測試，或不願保留任何東西的應用程式使用。
    private var isEnabled = true

    /// Switches the cache on again after ``disable()``.
    public func enable() {
        isEnabled = true
    }

    /// Switches the cache off. Files already written stay; this stops new ones.
    /// 關閉快取。已寫入的檔案會保留，此方法只是停止寫入新的檔案。
    public func disable() {
        isEnabled = false
    }

    private struct Entry {
        var artifact: String
        var fetchedAt: Date
        /// The server's `Last-Modified`, verbatim. Sent back as
        /// `If-Modified-Since` and compared by the server, not by us -- HTTP
        /// dates have three legal formats and re-formatting one is how a
        /// revalidation silently stops matching.
        /// 伺服器的 `Last-Modified` 原文。原樣回送為 `If-Modified-Since`，由伺服器而非我們比對
        /// ——HTTP 日期有三種合法格式，重新格式化正是使重新驗證悄悄失效的原因。
        var lastModified: String
        /// The server's `ETag`, verbatim, for `If-None-Match`.
        var etag: String
        var bytes: Int

        /// Whether the server gave us anything to ask with.
        ///
        /// Decides what ``AppCache/maximumAge`` does to this entry: an entry
        /// that can be revalidated is re-checked past the ceiling, and one that
        /// cannot is deleted, because there is no other way to tell whether it
        /// is still right.
        ///
        /// 伺服器是否給了我們任何可據以詢問的依據。
        ///
        /// 這決定了 ``AppCache/maximumAge`` 對此項目的作用：可重新驗證者在超過上限後會被重新
        /// 檢查，不可者則刪除——因為除此之外，沒有任何方式能判斷它是否仍然正確。
        var canBeRevalidated: Bool {
            !etag.isEmpty || !lastModified.isEmpty
        }

        /// Past ``AppCache/maximumAge``, so not to be served without a
        /// successful round trip first.
        ///
        /// Expired is not the same as deleted. An expired entry stays on disk
        /// until something replaces it, which is what keeps a cache useful to
        /// an application that has lost its network.
        ///
        /// 已超過 ``AppCache/maximumAge``，因此未經一次成功的往返便不應被提供。
        ///
        /// 「過期」不等於「已刪除」。過期項目會留在磁碟上直到有東西取代它——這正是讓快取對一個
        /// 失去網路連線的應用程式仍然有用的關鍵。
        var isExpired: Bool {
            Date().timeIntervalSince(fetchedAt) > AppCache.maximumAge
        }

        /// This copy was served without the server confirming it.
        ///
        /// Set when a fetch was attempted and failed -- offline, a timeout, a
        /// server error -- and the cached bytes were handed over anyway. Not
        /// set for an entry served inside its freshness window, which is the
        /// arrangement rather than a compromise, nor after a `304`, which is
        /// the server saying the copy is right.
        ///
        /// Named for what it is rather than for how it feels. `warning` would
        /// describe the reader's reaction; `not_latest` describes the data, and
        /// a developer scanning the index wants to know which rows are behind,
        /// not which rows once produced a message.
        ///
        /// Persisted rather than kept in memory so it survives the process. A
        /// stale copy is still stale on the next launch, and the whole point is
        /// that someone can open the index afterwards and see which rows were
        /// not current.
        ///
        /// 此副本在未經伺服器確認的情況下被提供。
        ///
        /// 當「嘗試抓取但失敗」——離線、逾時、伺服器錯誤——而仍將快取內容交出時設定。若項目是在其
        /// 新鮮度視窗內被提供則不設定，那是既定安排而非妥協；`304` 之後亦不設定，因為那是伺服器
        /// 表示該副本正確。
        ///
        /// 命名依據「它是什麼」而非「它讓人感覺如何」。`warning` 描述的是讀者的反應；`not_latest`
        /// 描述的是資料本身，而一位瀏覽索引的開發者想知道的是「哪幾列落後了」，不是「哪幾列曾經
        /// 產生過訊息」。
        ///
        /// 予以持久化而非僅存於記憶體，使其能跨行程存活。過期的副本在下次啟動時依然過期，而此欄位
        /// 的全部意義正在於：日後有人打開索引時，能看出哪幾列並非最新。
        var notLatest: Bool = false
    }

    /// How much of the cache a request is willing to trust.
    ///
    /// Named after `URLRequest.CachePolicy` rather than invented, because a
    /// reader who knows Foundation already knows what these mean and a new
    /// vocabulary would only make them check.
    ///
    /// 一次請求願意信任快取到什麼程度。
    ///
    /// 命名沿用 `URLRequest.CachePolicy` 而非自創，因為熟悉 Foundation 的讀者已經知道這些名稱的
    /// 意義，另立一套詞彙只會讓他們得回頭查證。
    public enum CachePolicy {
        /// Serve from disk while an entry is current, revalidating when the
        /// server gave us something to revalidate with. The default, and what
        /// a cache is for.
        /// 在項目仍為最新期間由磁碟提供，並在伺服器給了可據以驗證的依據時重新驗證。此為預設值，
        /// 也是快取存在的目的。
        case useProtocolCachePolicy

        /// Always ask the server, but ask conditionally: a `304` still serves
        /// the payload from disk. For something that changes often, where the
        /// window would hide an update but the body is not worth re-downloading
        /// when it has not changed.
        /// 一律詢問伺服器，但採條件式詢問：`304` 仍由磁碟提供內容。適用於經常變動的資源——時間窗
        /// 會遮蔽更新，但在內容未變時又不值得重新下載整個 body。
        case reloadRevalidatingCacheData

        /// Fetch the whole body and replace what is there. For a resource whose
        /// server offers no validators and which must not be stale -- the only
        /// case where paying for the body every time is the right answer.
        /// 抓取整個 body 並取代既有內容。適用於「伺服器不提供任何驗證標頭、且絕不容許過期」的
        /// 資源——那是唯一「每次都付出整個 body 代價」屬於正確答案的情形。
        case reloadIgnoringLocalCacheData
    }

    private init() {}

    /// The bytes for a URL, from disk when the server says the copy is current.
    ///
    /// A `file:` URL is read directly and never cached; it is already on disk
    /// and the index would only add a way for the two to disagree.
    ///
    /// For anything else, and with a live entry in hand, the request carries
    /// `If-None-Match` and `If-Modified-Since`. A `304` means the copy is
    /// current, so the payload is served from disk and its age reset. A `200`
    /// replaces it. Anything else, including no network at all, falls back to
    /// the cached copy if there is one -- an application that displayed content
    /// a minute ago should not lose it because a request timed out.
    ///
    /// With the cache off, this is a plain fetch, and the caller gets exactly
    /// what it would have got without any of this.
    ///
    /// 取得某個 URL 的內容；當伺服器表示副本仍為最新時，直接由磁碟提供。
    ///
    /// `file:` URL 直接讀取且從不快取；它本就在磁碟上，納入索引只會多出一個讓兩者不一致的管道。
    ///
    /// 其餘情況下，若手上有有效項目，請求會帶上 `If-None-Match` 與 `If-Modified-Since`。`304`
    /// 代表副本仍為最新，於是由磁碟提供內容並重置其年齡；`200` 則將其替換。其他任何情況（包括
    /// 完全沒有網路）都會退回使用既有的快取副本——一個應用程式不該因為一次請求逾時，就失去它一分鐘
    /// 前還顯示得出來的內容。
    public func data(
        for url: URL,
        policy: CachePolicy = .useProtocolCachePolicy
    ) async throws -> Data {
        if url.isFileURL {
            return try Data(contentsOf: url)
        }

        guard let directory = try? openDirectory() else {
            return try await fetch(url, validating: nil).data
        }

        let key = url.absoluteString
        let existing = index?[key]
        let artifactURL = existing.map { directory.appendingPathComponent("artifacts/\($0.artifact)") }

        // A live entry the server gave us no way to check is served as-is.
        //
        // Revalidation needs an `ETag` or a `Last-Modified` to send back; with
        // neither, a conditional request is an ordinary request and the answer
        // is always the whole body again. Measured against httpbin, which sends
        // neither: every run re-downloaded and wrote a new artifact, so the
        // cache cost a request and saved nothing.
        //
        // This is where ``maximumAge`` earns its name. Within it, an
        // uncheckable entry is treated as current -- the same heuristic a
        // browser applies to a response with no validators and no
        // `Cache-Control` -- and past it the entry is gone, pruned on open. The
        // cost is that a resource which changes inside the window, on a server
        // that offers no way to notice, is not noticed.
        //
        // 對於「伺服器未提供任何檢查方式」的有效項目，直接原樣提供。
        //
        // 重新驗證需要有 `ETag` 或 `Last-Modified` 可回送；兩者皆無時，條件式請求就只是普通請求，
        // 而回應永遠是整個 body。對 httpbin 實測（它兩者都不送）：每次執行都重新下載並寫入新的
        // artifact，快取因此付出了一次請求卻毫無節省。
        //
        // 這正是 ``maximumAge`` 名副其實之處。在該期限內，無法檢查的項目視為最新——這與瀏覽器對
        // 「沒有驗證標頭也沒有 `Cache-Control` 的回應」所採用的啟發式相同——超過期限則該項目已在
        // 開啟時被清除。代價是：若某資源在此期限內變更，而其伺服器又不提供任何察覺的方式，便無從
        // 察覺。
        if policy == .useProtocolCachePolicy,
            let existing, !existing.canBeRevalidated, !existing.isExpired,
            let artifactURL, let data = try? Data(contentsOf: artifactURL)
        {
            return data
        }

        do {
            // `reloadIgnoringLocalCacheData` sends no validators, so the server
            // has nothing to answer 304 with and returns the body. That is the
            // point of asking for it, and the only way to be current against a
            // server that offers no validators at all.
            // `reloadIgnoringLocalCacheData` 不送出任何驗證標頭，伺服器因此無從以 304 作答，只能
            // 回傳整個 body。這正是指定該政策的目的，也是面對「完全不提供驗證標頭的伺服器」時，
            // 唯一能保持最新的方式。
            let validators = policy == .reloadIgnoringLocalCacheData ? nil : existing
            let response = try await fetch(url, validating: validators)

            if response.notModified, let artifactURL,
                let data = try? Data(contentsOf: artifactURL)
            {
                // Current after all. The age moves, and the flag clears --
                // the server has just said this copy is right, so a row that
                // was behind is not behind any more. Leaving it set would make
                // the column mean "was stale once", which nobody can act on.
                // 確實仍為最新。年齡更新，旗標清除——伺服器剛剛表示此副本正確，因此原本落後的列
                // 已不再落後。若保留該旗標，此欄的意義會變成「曾經過期」，而那是沒有人能據以行動
                // 的資訊。
                var entry = existing!
                entry.fetchedAt = Date()
                entry.notLatest = false
                index?[key] = entry
                try? writeIndex()
                return data
            }

            try store(response, for: key, in: directory, replacing: existing)
            return response.data
        } catch {
            if var entry = existing, let artifactURL,
                let data = try? Data(contentsOf: artifactURL)
            {
                // Served without confirmation. Recorded in the index so it can
                // be reviewed later, and announced so an application can tell
                // the person looking at the screen.
                //
                // Announced rather than presented. A cache putting a dialog on
                // screen would be a utility deciding how an application talks
                // to its user -- wrong, and untestable without a window. The
                // application decides; ``staleServeHandler`` is where it says
                // how.
                //
                // 在未經確認的情況下提供。此事會記錄於索引以供日後檢視，並對外公告，使應用程式能
                // 告知正在看螢幕的人。
                //
                // 採「公告」而非「呈現」。若由快取自行在畫面上彈出對話框，等於一個工具程式替應用
                // 程式決定它該如何與使用者對話——那是錯的，而且沒有視窗就無法測試。決定權在應用
                // 程式；``staleServeHandler`` 正是它表達方式的地方。
                entry.notLatest = true
                index?[key] = entry
                try? writeIndex()

                let handler = Self.staleServeHandler
                Task { @MainActor in handler?(url, error) }

                return data
            }
            throw error
        }
    }

    /// Called when a cached copy was served because the fetch failed.
    ///
    /// Set it to show the person a warning; leave it and nothing is shown, and
    /// the `not_latest` column in the index is the only record. It is called on
    /// the main actor with the URL and the error that caused the fallback.
    ///
    /// 當「因抓取失敗而改用快取副本」時呼叫。
    ///
    /// 設定它即可向使用者顯示警告；不設定則不顯示任何內容，索引中的 `not_latest` 欄位便是唯一的
    /// 紀錄。呼叫發生於 main actor 上，並帶入該 URL 與導致退回的錯誤。
    public nonisolated(unsafe) static var staleServeHandler:
        (@MainActor @Sendable (URL, any Error) -> Void)?

    // MARK: - Directory and index

    /// The cache directory, or a thrown error when the application has not
    /// created one. Creates `appCache.csv2` and `artifacts/` inside it, and
    /// prunes anything past ``maximumAge`` on the way.
    /// 快取目錄；若應用程式未建立則擲出錯誤。會在其中建立 `appCache.csv2` 與 `artifacts/`，並在
    /// 過程中清除所有超過 ``maximumAge`` 的項目。
    private func openDirectory() throws -> URL {
        guard isEnabled else { throw AppCacheError.disabled }
        if let directory, index != nil { return directory }

        guard let directory = Self.cacheDirectory() else {
            throw AppCacheError.locationUnknown
        }

        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("artifacts"),
            withIntermediateDirectories: true
        )

        self.directory = directory
        index = Self.readIndex(at: directory.appendingPathComponent("appCache.csv2"))
        prune(in: directory)
        try? writeIndex()
        return directory
    }

    /// Deletes the artifacts the index does not name. **Nothing else.**
    ///
    /// Age does not delete anything here, and that is the whole point. This
    /// runs when the directory is opened, which is the one moment that knows
    /// nothing about whether the network is reachable -- and deleting an
    /// expired entry offline destroys the only copy the application has, with
    /// no way to fetch another. The user is left with less than they had a
    /// moment earlier, because of a clock.
    ///
    /// ``maximumAge`` is enforced in ``data(for:)`` instead, where the answer
    /// is known: past the ceiling an entry is not served without a successful
    /// round trip, and the old payload is removed by ``store(_:for:in:replacing:)``
    /// only once a replacement is in hand. Deletion is a consequence of
    /// succeeding, never of failing.
    ///
    /// So an expired entry outlives 7 days while offline. That is deliberate:
    /// the alternative is a cache that empties itself exactly when it is the
    /// only thing left.
    ///
    /// The orphan sweep is safe to do here because an artifact the index does
    /// not name cannot be served to anyone. It is what a run killed between
    /// writing a payload and writing the index leaves behind, and without this
    /// the directory would grow forever with files no rule can see.
    ///
    /// 刪除索引未指名的 artifact。**僅此而已。**
    ///
    /// 此處不因年齡刪除任何東西，而這正是重點。本函式在開啟目錄時執行，而那恰是唯一「對網路是否
    /// 可用一無所知」的時刻——在離線狀態下刪除過期項目，等於銷毀應用程式手上唯一的副本，且無從再
    /// 取得另一份。使用者會因為一個時鐘，而擁有比片刻之前更少的東西。
    ///
    /// ``maximumAge`` 改由 ``data(for:)`` 執行，因為在那裡答案是已知的：超過上限的項目，未經一次
    /// 成功的往返便不會被提供；而舊有內容只在替代品到手之後，才由
    /// ``store(_:for:in:replacing:)`` 移除。刪除永遠是「成功」的後果，絕不是「失敗」的後果。
    ///
    /// 因此離線時，過期項目會存活超過 7 天。這是刻意的：另一個選項是「快取恰好在它成為唯一依靠時
    /// 清空自己」。
    ///
    /// 孤兒檔案的清掃可以安全地放在此處，因為索引未指名的 artifact 不可能被提供給任何人。它正是
    /// 某次執行在「寫入內容」與「寫入索引」之間被中止所遺留的產物；少了這一步，該目錄會無止境地
    /// 累積任何規則都看不見的檔案。
    private func prune(in directory: URL) {
        let artifacts = directory.appendingPathComponent("artifacts")
        let named = Set((index ?? [:]).values.map(\.artifact))
        let onDisk =
            (try? FileManager.default.contentsOfDirectory(atPath: artifacts.path)) ?? []
        for file in onDisk where !named.contains(file) {
            try? FileManager.default.removeItem(at: artifacts.appendingPathComponent(file))
        }
    }

    private func store(
        _ response: Response,
        for key: String,
        in directory: URL,
        replacing existing: Entry?
    ) throws {
        let artifacts = directory.appendingPathComponent("artifacts")
        if let existing {
            try? FileManager.default.removeItem(
                at: artifacts.appendingPathComponent(existing.artifact)
            )
        }

        let suffix = response.suffix
        let artifact = suffix.isEmpty
            ? UUID().uuidString
            : "\(UUID().uuidString).\(suffix)"
        try response.data.write(to: artifacts.appendingPathComponent(artifact))

        index?[key] = Entry(
            artifact: artifact,
            fetchedAt: Date(),
            lastModified: response.lastModified,
            etag: response.etag,
            bytes: response.data.count
        )
        try writeIndex()
    }

    // MARK: - The index file

    /// **Two** header rows, which is what makes this a `.csv2` rather than a
    /// `.csv`.
    ///
    /// A `.csv2` is an ordinary RFC 4180 CSV whose first *two* rows are
    /// headers, the second carrying the same columns in Chinese. There is no
    /// marker and no separator -- the suffix declares it, and the `csv2` tool
    /// refuses a `.csv2` that has only one, rather than silently reading the
    /// first record as the missing second header.
    ///
    /// Getting this wrong is not a formatting nit. With one header row, `csv2`
    /// would take the first cached entry as the Chinese header and that entry
    /// would vanish from every listing -- a file that still parses, with one
    /// row quietly missing.
    ///
    /// `fetched_at` is ISO 8601 so it sorts as text and reads as a date. Every
    /// field is quoted: a URL may contain a comma, and so may an `ETag`.
    ///
    /// **兩列**標頭，這正是本檔為 `.csv2` 而非 `.csv` 的原因。
    ///
    /// `.csv2` 是一般的 RFC 4180 CSV，但其前**兩**列皆為標頭，第二列以中文列出相同欄位。它沒有
    /// 標記、也沒有分隔符——由副檔名宣告；而 `csv2` 工具會拒絕只有一列標頭的 `.csv2`，而不是把
    /// 第一筆記錄當成缺少的第二列標頭去讀。
    ///
    /// 弄錯這一點並非格式上的細枝末節。若只寫一列標頭，`csv2` 會把第一筆快取項目當作中文標頭，
    /// 該項目便會從所有列表中消失——檔案仍可解析，卻靜默地少了一列。
    ///
    /// `fetched_at` 採 ISO 8601，如此既能以文字排序、又能被當作日期閱讀。所有欄位一律加引號：
    /// URL 可能含有逗號，`ETag` 亦然。
    private static let headers = [
        "url,artifact,fetched_at,last_modified,etag,bytes,not_latest",
        "網址,檔案,取得時間,最後修改,實體標籤,位元組,非最新",
    ]

    private func writeIndex() throws {
        guard let directory, let index else { return }
        var lines = Self.headers
        for (url, entry) in index.sorted(by: { $0.key < $1.key }) {
            lines.append(
                [
                    url,
                    entry.artifact,
                    Self.formatter.string(from: entry.fetchedAt),
                    entry.lastModified,
                    entry.etag,
                    "\(entry.bytes)",
                    // "Y" or empty rather than true/false. The column is read
                    // by a person scanning for problems, and an empty cell
                    // disappears while "N" would be one more thing to skim
                    // past on every healthy row.
                    // 使用 "Y" 或留空，而非 true/false。此欄是供人掃視以尋找問題之用；空白儲存格
                    // 會自然隱去，而 "N" 只會在每一列正常資料上多出一個需要略過的東西。
                    entry.notLatest ? "Y" : "",
                ]
                .map(Self.quote)
                .joined(separator: ",")
            )
        }
        try (lines.joined(separator: "\n") + "\n").write(
            to: directory.appendingPathComponent("appCache.csv2"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static func readIndex(at url: URL) -> [String: Entry] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }

        var index: [String: Entry] = [:]
        // Split on isNewline, not "\n": Swift treats "\r\n" as one Character,
        // so a CRLF file split on the literal returns a single element and
        // every row disappears without an error.
        // 以 isNewline 而非 "\n" 切分：Swift 將 "\r\n" 視為單一 Character，因此以字面值切分 CRLF
        // 檔案會得到單一元素，所有列都會在毫無錯誤的情況下消失。
        // Two header rows skipped, not one. Dropping by position rather than by
        // matching their text: a row is a header because of where it is, and a
        // cached URL that happened to read "網址" would otherwise be dropped.
        // 略過兩列標頭而非一列。以位置而非文字比對來丟棄：一列之所以是標頭，取決於它的位置；
        // 否則若某個被快取的 URL 恰好是「網址」，該列便會被丟掉。
        for line in text.split(whereSeparator: \.isNewline).dropFirst(2) {
            let fields = parseRow(String(line))
            guard fields.count >= 6 else { continue }
            guard let fetchedAt = formatter.date(from: fields[2]) else { continue }
            index[fields[0]] = Entry(
                artifact: fields[1],
                fetchedAt: fetchedAt,
                lastModified: fields[3],
                etag: fields[4],
                bytes: Int(fields[5]) ?? 0,
                // Column added after the first release of this format, so a
                // row written before it exists is short. Read positionally with
                // a default rather than requiring the column, because an index
                // that refused to load would throw away every cached artifact
                // to gain one flag.
                // 此欄位於本格式首次釋出之後才加入，因此更早寫入的列會較短。以位置讀取並帶預設值，
                // 而非強制要求該欄存在——因為一個「拒絕載入」的索引，等於為了取得一個旗標而丟棄
                // 所有已快取的 artifact。
                notLatest: fields.count > 6 && fields[6] == "Y"
            )
        }
        return index
    }

    private static func quote(_ field: String) -> String {
        "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func parseRow(_ row: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var characters = Array(row)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if inQuotes {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        current.append("\"")
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.append(character)
                }
            } else if character == "\"" {
                inQuotes = true
            } else if character == "," {
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }
            index += 1
        }
        fields.append(current)
        return fields
    }

    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    // MARK: - Fetching

    private struct Response {
        var data: Data
        var notModified: Bool
        var lastModified: String
        var etag: String
        var suffix: String
    }

    private func fetch(_ url: URL, validating existing: Entry?) async throws -> Response {
        var request = URLRequest(url: url)

        // A short timeout when there is something to fall back to.
        //
        // URLRequest defaults to 60 seconds. With a cached copy in hand that is
        // a minute of `loading...` before showing a picture that was on disk
        // the whole time -- and the offline case, which is the one the fallback
        // exists for, is exactly the case that waits the full minute.
        //
        // Measured while trying to test the fallback: a request pointed at a
        // dead proxy was still in flight after fourteen seconds, and the test
        // concluded nothing had happened because nothing had yet.
        //
        // With no cached copy the default stands. There is nothing better to
        // show, so giving up early only turns a slow success into a failure.
        //
        // 當有東西可退回時，使用較短的逾時。
        //
        // URLRequest 預設為 60 秒。在手上已有快取副本的情況下，那意味著一分鐘的 `loading...`，
        // 之後才顯示一張自始至終都在磁碟上的圖片——而離線情境，正是此退回機制存在的理由，也正是
        // 會完整等滿那一分鐘的情境。
        //
        // 此數值是在嘗試測試該退回機制時量到的：一個指向無效 proxy 的請求在十四秒後仍在進行中，
        // 而測試因此認定「什麼都沒發生」——其實只是還沒發生。
        //
        // 若沒有快取副本則沿用預設值。此時並沒有更好的東西可顯示，提早放棄只會把「較慢的成功」
        // 變成「失敗」。
        if existing != nil {
            request.timeoutInterval = 10
        }

        if let existing {
            if !existing.etag.isEmpty {
                request.setValue(existing.etag, forHTTPHeaderField: "If-None-Match")
            }
            if !existing.lastModified.isEmpty {
                request.setValue(existing.lastModified, forHTTPHeaderField: "If-Modified-Since")
            }
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse

        // A 404 body is not the resource. Without this check an error page was
        // written to the cache as if it were the payload and served for the
        // next seven days -- and an image view would show a broken decode with
        // nothing to say why.
        //
        // Thrown rather than returned, so it joins the same path as a timeout:
        // the caller falls back to the cached copy if there is one, marks it
        // `not_latest`, and only fails outright when there is nothing to fall
        // back to. A server that is briefly returning 500 should not cost an
        // application the content it already had.
        //
        // 404 的內容不是該資源。若無此檢查，錯誤頁會被當成內容寫入快取，並在往後七天內持續被提供
        // ——而影像視圖只會顯示一個解碼失敗，且無從說明原因。
        //
        // 採用擲出而非回傳，使其與逾時走同一條路徑：呼叫端若有快取副本便退回使用，並標記為
        // `not_latest`，唯有在無可退回時才真正失敗。一台短暫回傳 500 的伺服器，不該讓應用程式
        // 失去它原本就已擁有的內容。
        if let status = http?.statusCode, status != 304, !(200..<300).contains(status) {
            throw AppCacheError.httpStatus(status)
        }

        // The suffix comes from the URL path, not from the content type. A
        // mapping from MIME type to extension would be another table to keep
        // right, and the extension is only there so the file can be opened by
        // hand -- nothing reads it back.
        // 副檔名取自 URL 路徑而非 content type。從 MIME 型別對映到副檔名等於又一張需要維護正確性的
        // 對照表，而此處保留副檔名只是為了讓檔案能以人手開啟——沒有任何程式會回頭讀取它。
        return Response(
            data: data,
            notModified: http?.statusCode == 304,
            lastModified: http?.value(forHTTPHeaderField: "Last-Modified") ?? "",
            etag: http?.value(forHTTPHeaderField: "ETag") ?? "",
            suffix: url.pathExtension
        )
    }

    /// `<platform caches>/<executable name>/appCache`.
    ///
    /// The executable's name, not its directory: the cache goes in the
    /// platform's place and is merely *named* after the application, so two
    /// applications on the same machine do not share an index.
    ///
    /// A fixed name is used if the executable cannot be identified. Failing to
    /// cache would be a worse answer than sharing a directory, and the index is
    /// keyed by URL either way.
    ///
    /// `<平台快取目錄>/<執行檔名稱>/appCache`。
    ///
    /// 取執行檔的「名稱」而非其所在目錄：快取存放於平台指定的位置，僅以應用程式*命名*，使同一台
    /// 機器上的兩個應用程式不會共用同一份索引。
    ///
    /// 若無法辨識執行檔，則使用固定名稱。「無法快取」是比「共用目錄」更糟的結果，而無論如何索引
    /// 都是以 URL 作為鍵。
    private static func cacheDirectory() -> URL? {
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
}

public enum AppCacheError: Error, CustomStringConvertible {
    /// No `appCache` directory beside the executable, so caching is off. Not a
    /// failure: it is how the cache stays opt-in.
    case disabled
    case locationUnknown
    case httpStatus(Int)

    public var description: String {
        switch self {
            case .disabled:
                "the cache is disabled"
            case .locationUnknown:
                "could not determine the platform's cache directory"
            case .httpStatus(let status):
                "the server answered \(status)"
        }
    }
}
