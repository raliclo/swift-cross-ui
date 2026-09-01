import Foundation
import SwiftCrossUI

extension WinUIBackend: BackendFeatures.RevealFiles {
    /// Opens File Explorer with the file selected.
    ///
    /// `explorer.exe /select,<path>` is the documented way to do this, and the
    /// comma is part of the switch: `/select,C:\x` works, `/select C:\x` opens
    /// the user's Documents folder instead, which looks like the call being
    /// ignored rather than misparsed.
    ///
    /// **Its exit status is not a success signal.** `explorer.exe` returns 1 on
    /// a perfectly successful reveal, because it hands the request to the
    /// already-running shell process and exits. Gating the fallback on the exit
    /// code would therefore open the parent directory *as well*, every single
    /// time, leaving the user with two windows and the selection lost in the
    /// second. So the decision is made before launching, from whether the path
    /// exists, and the status is only read to log it.
    ///
    /// 開啟檔案總管並選取該檔案。
    ///
    /// `explorer.exe /select,<path>` 是官方記載的做法，而那個逗號是參數的一部分：
    /// `/select,C:\x` 有效，`/select C:\x` 則會改為開啟使用者的「文件」資料夾——看起來像是呼叫
    /// 被忽略，而非被解析錯誤。
    ///
    /// **它的退出碼不是成敗訊號。** 即使選取完全成功，`explorer.exe` 仍常回傳 1，因為它把請求交給
    /// 已在執行的 shell process 之後就結束了。若以退出碼決定是否 fallback，就會在**每一次**成功時
    /// 又額外開啟一次上層資料夾，使用者會得到兩個視窗，而選取狀態消失在第二個裡。因此判斷改為在
    /// 啟動之前依「路徑是否存在」決定，退出碼僅用於記錄。
    public func revealFile(_ url: URL) throws {
        let path = Self.windowsPath(of: url)

        guard FileManager.default.fileExists(atPath: path) else {
            // Nothing to select. Opening the enclosing directory is still
            // useful and is what the Gtk backend falls back to.
            // 沒有可選取的對象。開啟其上層目錄仍有意義，這也是 Gtk backend 的 fallback。
            try openExternalURL(url.deletingLastPathComponent())
            return
        }

        let explorer =
            ProcessInfo.processInfo.environment["SYSTEMROOT"].map {
                "\($0)\\explorer.exe"
            } ?? "C:\\Windows\\explorer.exe"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: explorer)
        // One argument, not two. Splitting at the comma is the same mistake as
        // using a space.
        // 一個引數，不是兩個。在逗號處拆開，與使用空白是同一個錯誤。
        process.arguments = ["/select,\(path)"]

        do {
            try process.run()
            process.waitUntilExit()
            // The status is deliberately not read. See above: it is 1 on
            // success, so there is nothing here worth branching on.
            // 刻意不讀取退出碼。理由見上：它在成功時就是 1，此處沒有值得據以分支的東西。
        } catch {
            // Explorer could not be started at all -- a different failure from a
            // reveal that did not work, and the only one this can detect. Fall
            // back rather than throw, since opening the enclosing directory is
            // still what the caller wanted; if that fails too, its error is the
            // one worth propagating.
            // 完全無法啟動 Explorer——這與「選取沒有生效」是不同的失敗，也是此處唯一偵測得到的
            // 一種。此時採用 fallback 而非拋出，因為開啟上層目錄仍是呼叫端想要的；若連它也失敗，
            // 那個錯誤才值得往上傳。
            try openExternalURL(url.deletingLastPathComponent())
        }
    }

    /// A path `explorer.exe` accepts: drive-lettered and backslash-separated.
    ///
    /// `URL.path` yields forward slashes, and on some Foundation versions a
    /// leading slash before the drive letter. Explorer takes neither, and its
    /// response to a path it does not understand is to open Documents rather
    /// than to report an error.
    ///
    /// `explorer.exe` 能接受的路徑形式：帶磁碟機代號、以反斜線分隔。
    ///
    /// `URL.path` 產生的是正斜線，且在某些 Foundation 版本中會在磁碟機代號前多一個斜線。Explorer
    /// 兩者都不接受，而它對看不懂的路徑的反應是開啟「文件」資料夾，而不是回報錯誤。
    private static func windowsPath(of url: URL) -> String {
        var path = url.path
        if path.count >= 3, path.hasPrefix("/") {
            let afterSlash = path.index(after: path.startIndex)
            let colon = path.index(afterSlash, offsetBy: 1)
            if path[colon] == ":" {
                path.removeFirst()
            }
        }
        return path.replacingOccurrences(of: "/", with: "\\")
    }
}
