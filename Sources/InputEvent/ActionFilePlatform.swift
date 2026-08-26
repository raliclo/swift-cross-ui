import Foundation

/// The backend family for which an action file was verified.
///
/// This is deliberately a backend-oriented label: WSLg and a native Linux
/// desktop both use `gtk`, while `macos` identifies AppKit.
///
/// 動作檔曾驗證過的 backend 類別。
///
/// 這裡刻意使用 backend 導向的標籤：WSLg 與原生 Linux desktop 都使用 `gtk`，
/// 而 `macos` 代表 AppKit。
public enum ActionFilePlatform: String, Equatable, Sendable {
    case any
    case macos
    case windows
    case gtk
    case ios
    case android

    /// The platform family of the current binary.
    ///
    /// 目前執行檔所屬的 platform family。
    public static var current: Self {
        #if os(macOS)
            .macos
        #elseif os(Windows)
            .windows
        #elseif os(Linux)
            .gtk
        #elseif os(iOS)
            .ios
        #elseif os(Android)
            .android
        #else
            .any
        #endif
    }

    public func matches(_ current: Self) -> Bool {
        self == .any || self == current
    }
}
