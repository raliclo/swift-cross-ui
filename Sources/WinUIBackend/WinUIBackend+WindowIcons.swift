import Foundation
@_spi(Backends) import SwiftCrossUI
import WinAppSDK
import WinSDK

/// `windowIcon(_:)` on WinUI.
///
/// `AppWindow.SetIcon` sets the titlebar, taskbar and Alt+Tab icon at once,
/// but takes the path of an `.ico` file. An ICO may hold its image as PNG
/// data (Windows Vista onwards), so the PNG is wrapped as it is -- a 6-byte
/// header and one 16-byte directory entry in front of the file's bytes -- and
/// written to a cache directory under the temporary directory. No decoding,
/// no resampling: Windows scales the one image to each size it draws.
///
/// WinUI 上的 `windowIcon(_:)`。`AppWindow.SetIcon` 一次設定標題列、工作列與 Alt+Tab 的圖示，但接受的是 `.ico`
/// 檔的路徑。ICO 可以以 PNG 資料存放影像(Windows Vista 起),所以 PNG 原樣包起來——檔案位元組前面加 6 位元組的標頭與
/// 一筆 16 位元組的目錄項——寫到暫存目錄下的快取目錄。不解碼、不重新取樣:Windows 把這一張影像縮放成它要畫的每個尺寸。
extension WinUIBackend: BackendFeatures.WindowIcons {
    public func setIcon(ofWindow window: Window, to icon: URL?) {
        guard !window.isClosed else { return }
        guard let icon else {
            // Back to the window class's icon. / 回到視窗類別的圖示。
            if let hwnd = window.getHWND() {
                _ = SendMessageW(hwnd, UINT(WM_SETICON), WPARAM(ICON_BIG), 0)
                _ = SendMessageW(hwnd, UINT(WM_SETICON), WPARAM(ICON_SMALL), 0)
            }
            return
        }
        do {
            let ico = try Self.icoFile(wrapping: icon)
            let path = ico.withUnsafeFileSystemRepresentation { $0.map { String(cString: $0) } } ?? ico.path
            try window.appWindow.setIcon(path)
        } catch {
            // Said, not fatal: the window keeps the default icon.
            // 只說明、不中止：視窗保留預設圖示。
            logger.warning("windowIcon: \(icon.lastPathComponent) could not be set: \(error)")
        }
    }

    struct WindowIconError: Swift.Error, CustomStringConvertible {
        var description: String
    }

    /// Writes `png` wrapped as a one-image ICO and returns its location; the
    /// name carries a hash of the bytes, so a changed PNG gets a new file.
    /// 把 `png` 包成單張影像的 ICO 寫出並回傳位置；檔名帶有位元組的雜湊，所以 PNG 改了就是新檔。
    static func icoFile(wrapping png: URL) throws -> URL {
        let data = try Data(contentsOf: png)
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard data.count > 24, Array(data.prefix(8)) == signature else {
            throw WindowIconError(description: "not a PNG file")
        }
        // IHDR is the first chunk: width and height, big-endian, at 16 and 20.
        // IHDR 是第一個 chunk:寬與高為 big-endian,位於 16 與 20。
        func bigEndian(_ offset: Int) -> Int {
            data[data.startIndex + offset..<data.startIndex + offset + 4].reduce(0) { $0 << 8 | Int($1) }
        }
        let width = bigEndian(16)
        let height = bigEndian(20)
        func littleEndian16(_ value: Int) -> [UInt8] { [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF)] }
        func littleEndian32(_ value: Int) -> [UInt8] { littleEndian16(value & 0xFFFF) + littleEndian16(value >> 16) }
        // A dimension byte of 0 means 256 or more. / 尺寸位元組 0 表示 256 以上。
        var ico: [UInt8] = littleEndian16(0) + littleEndian16(1) + littleEndian16(1)
        ico += [UInt8(width >= 256 ? 0 : width), UInt8(height >= 256 ? 0 : height), 0, 0]
        ico += littleEndian16(1) + littleEndian16(32) + littleEndian32(data.count) + littleEndian32(22)

        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in data {
            hash = (hash ^ UInt64(byte)) &* 0x0100_0000_01B3
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("scui-window-icons", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = png.deletingPathExtension().lastPathComponent + "-" + String(hash, radix: 16) + ".ico"
        let url = directory.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) {
            try (Data(ico) + data).write(to: url, options: .atomic)
        }
        return url
    }
}
