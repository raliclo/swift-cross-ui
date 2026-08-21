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

/// An on-disk cache for things fetched over the network, next to the executable.
///
/// Off unless the application asks for it, and it asks by creating an
/// `appCache` directory beside its executable. Nothing else switches it on.
/// A UI framework that started writing to the user's disk because a view was
/// given an `https` URL would be doing something the author never agreed to;
/// requiring the directory makes it a decision someone made on purpose, and
/// deleting the directory is how it is turned off again.
///
/// Inside it:
///
/// ```
/// appCache/
///   appCache.csv2      the index -- RFC 4180 CSV, one row per URL
///   artifacts/
///     <uuid>.<suffix>  the payload, named so nothing collides
/// ```
///
/// Artifacts are named by UUID rather than by anything derived from the URL.
/// A URL is not a filename: it can be longer than the filesystem allows,
/// contain separators, differ from another only in case, or be the same
/// resource spelled two ways. The index is what maps one to the other, and the
/// suffix is kept so the file is still openable by hand.
///
/// 位於執行檔旁的網路資源磁碟快取。
///
/// 除非應用程式主動要求，否則不啟用；而要求的方式是在其執行檔旁建立一個 `appCache` 目錄。除此
/// 之外沒有任何開關。一個 UI 框架若只因某個 view 收到 `https` URL 就開始寫入使用者的磁碟，等於
/// 做了作者從未同意的事；要求該目錄存在，使這件事成為某人刻意做出的決定，而刪除該目錄就是關閉
/// 它的方式。
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
    public func data(for url: URL) async throws -> Data {
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
        if let existing, existing.etag.isEmpty, existing.lastModified.isEmpty,
            let artifactURL, let data = try? Data(contentsOf: artifactURL)
        {
            return data
        }

        do {
            let response = try await fetch(url, validating: existing)

            if response.notModified, let artifactURL,
                let data = try? Data(contentsOf: artifactURL)
            {
                // Current after all. Only the age moves.
                // 確實仍為最新。只更新年齡。
                var entry = existing!
                entry.fetchedAt = Date()
                index?[key] = entry
                try? writeIndex()
                return data
            }

            try store(response, for: key, in: directory, replacing: existing)
            return response.data
        } catch {
            if let artifactURL, let data = try? Data(contentsOf: artifactURL) {
                return data
            }
            throw error
        }
    }

    // MARK: - Directory and index

    /// The cache directory, or a thrown error when the application has not
    /// created one. Creates `appCache.csv2` and `artifacts/` inside it, and
    /// prunes anything past ``maximumAge`` on the way.
    /// 快取目錄；若應用程式未建立則擲出錯誤。會在其中建立 `appCache.csv2` 與 `artifacts/`，並在
    /// 過程中清除所有超過 ``maximumAge`` 的項目。
    private func openDirectory() throws -> URL {
        if let directory, index != nil { return directory }

        guard let executable = Self.executableDirectory() else {
            throw AppCacheError.locationUnknown
        }
        let directory = executable.appendingPathComponent("appCache")

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            throw AppCacheError.disabled
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

    /// Deletes every entry past ``maximumAge``, and every artifact the index
    /// does not name.
    ///
    /// The second half matters as much as the first: a run that was killed
    /// between writing a payload and writing the index leaves a file nothing
    /// refers to, and without this the directory would grow forever with
    /// exactly the files the age rule can never see.
    ///
    /// 刪除所有超過 ``maximumAge`` 的項目，以及所有索引未指名的 artifact。
    ///
    /// 後半與前半同等重要：若某次執行在「寫入內容」與「寫入索引」之間被中止，便會留下一個無人指涉
    /// 的檔案；少了這一步，該目錄會無止境地累積正好是年齡規則永遠看不見的那些檔案。
    private func prune(in directory: URL) {
        let cutoff = Date().addingTimeInterval(-Self.maximumAge)
        let artifacts = directory.appendingPathComponent("artifacts")

        for (key, entry) in index ?? [:] where entry.fetchedAt < cutoff {
            try? FileManager.default.removeItem(
                at: artifacts.appendingPathComponent(entry.artifact)
            )
            index?[key] = nil
        }

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
        "url,artifact,fetched_at,last_modified,etag,bytes",
        "網址,檔案,取得時間,最後修改,實體標籤,位元組",
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
                bytes: Int(fields[5]) ?? 0
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

    private static func executableDirectory() -> URL? {
        guard let path = Bundle.main.executablePath else { return nil }
        return URL(fileURLWithPath: path).deletingLastPathComponent()
    }
}

public enum AppCacheError: Error, CustomStringConvertible {
    /// No `appCache` directory beside the executable, so caching is off. Not a
    /// failure: it is how the cache stays opt-in.
    case disabled
    case locationUnknown

    public var description: String {
        switch self {
            case .disabled:
                "no appCache directory beside the executable; caching is off"
            case .locationUnknown:
                "could not determine the executable's directory"
        }
    }
}
