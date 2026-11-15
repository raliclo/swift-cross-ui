import CGtk
import Foundation
import Gtk
import GtkCHelpers
@_spi(Backends) import SwiftCrossUI

/// `windowIcon(_:)` on GTK.
///
/// GTK 4 has no call that takes an image for a window: a window's icon is a
/// name, resolved through the icon theme. Two places use that name, and they
/// do not resolve it the same way:
/// - The titlebar GTK draws looks the name up as is, and finds a loose PNG in
///   any directory on the theme's search path. That is what SoftPCB-UI did
///   (SoftPCB-UI 15af374, Support/WindowIcon.swift).
/// - The icon handed to the platform -- `WM_SETICON` on Windows, so the
///   taskbar and Alt+Tab, and `_NET_WM_ICON` on X11 -- is built from the sizes
///   an icon THEME declares for the name (`icon_list_from_theme` in
///   gtkwindow.c, through `gtk_icon_theme_get_icon_sizes`). A loose PNG
///   belongs to no theme and has no sizes, so that list was empty and the
///   HWND had no icon: P118 read `WM_GETICON` back as nothing on Windows GTK
///   while the titlebar showed the icon (2026-11-15).
///
/// So the PNG is copied into a small private `hicolor` theme under the
/// temporary directory (`hicolor/<N>x<N>/apps/<name>.png` for each of `iconSizes`, and an
/// `index.theme`), which joins the search path; hicolor is the fallback every
/// theme ends in. The file's name without its extension is the icon name.
/// The titlebar shows only what its `decoration-layout` lists, and GTK's
/// default lists no icon, so the window adds `icon` to its own header bars
/// (`Gtk.Window.showsIcon`) rather than to the global `gtk-decoration-layout`
/// setting, which would change every window in the process.
///
/// GtkBackend 上的 `windowIcon(_:)`。GTK 4 沒有接受圖片的視窗圖示呼叫：視窗圖示是一個名稱，經由圖示主題解析。用到這個名稱的
/// 地方有兩處，解析方式不同：GTK 自己畫的標題列直接查名稱，搜尋路徑上任何目錄裡的散裝 PNG 都找得到——SoftPCB-UI 就是這樣做
/// (SoftPCB-UI 15af374,Support/WindowIcon.swift)。交給平台的圖示——Windows 上的 `WM_SETICON`,也就是工作列與
/// Alt+Tab,X11 上的 `_NET_WM_ICON`——則由圖示**主題**為該名稱宣告的尺寸建立(gtkwindow.c 的 `icon_list_from_theme`,經由
/// `gtk_icon_theme_get_icon_sizes`)。散裝 PNG 不屬於任何主題、沒有尺寸，所以清單是空的,HWND 沒有圖示:P118 在 Windows GTK
/// 上讀回的 `WM_GETICON` 是空的，而標題列卻顯示圖示(2026-11-15)。因此把 PNG 複製到暫存目錄下小型私有的 `hicolor` 主題
/// (`iconSizes` 每個尺寸一份 `hicolor/<N>x<N>/apps/<名稱>.png`,加上 `index.theme`),並加入搜尋路徑;hicolor 是每個主題最後的後備。檔名去掉副檔名就是
/// 圖示名稱。標題列只顯示 `decoration-layout` 列出的東西,GTK 預設沒有圖示，所以由視窗把 `icon` 加進自己的 header bar
/// (`Gtk.Window.showsIcon`),而不是改全域的 `gtk-decoration-layout` 設定——那會改變行程裡的每個視窗。
extension GtkBackend: BackendFeatures.WindowIcons {
    /// Whether the theme root below is on the search path yet.
    /// 下方的主題根目錄是否已在搜尋路徑上。
    nonisolated(unsafe) private static var addedIconThemeRoot = false

    static let iconThemeRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("scui-window-icons-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)

    static let indexTheme = """
        [Icon Theme]
        Name=Hicolor
        Comment=SwiftCrossUI window icons
        Directories=32x32/apps,48x48/apps,256x256/apps

        [32x32/apps]
        Size=32
        Context=Applications
        Type=Threshold

        [48x48/apps]
        Size=48
        Context=Applications
        Type=Threshold

        [256x256/apps]
        Size=256
        Context=Applications
        Type=Threshold

        """

    /// The sizes the theme declares, each holding the same PNG; GTK renders
    /// it at each size for the platform icon list. Not 256 alone: GDK's X11
    /// backend silently drops an icon larger than the server's maximum
    /// request, and 256x256 is 65538 longs against WSLg's 65435, so X11 got no
    /// `_NET_WM_ICON` at all (P118, 2026-11-15).
    /// 主題宣告的尺寸，每個都放同一張 PNG;GTK 為平台圖示清單把它畫成各個尺寸。不只 256:GDK 的 X11 backend 會默默丟掉超過
    /// 伺服器最大請求的圖示,256x256 是 65538 個 long,WSLg 的上限是 65435,所以 X11 完全拿不到 `_NET_WM_ICON`
    /// (P118,2026-11-15)。
    static let iconSizes = [32, 48, 256]

    public func setIcon(ofWindow window: Window, to icon: URL?) {
        guard let icon else {
            window.iconName = nil
            window.showsIcon = false
            scui_window_clear_platform_icon(window.widgetPointer)
            return
        }
        let name = icon.deletingPathExtension().lastPathComponent
        do {
            try Self.installInIconTheme(icon, named: name)
        } catch {
            // Said, not fatal: the window opens with the default icon.
            // 只說明、不中止：視窗以預設圖示開啟。
            logger.warning("windowIcon: \(icon.lastPathComponent) could not be used: \(error)")
        }
        window.iconName = name
        window.showsIcon = true
    }

    /// Copies `png` into the private hicolor theme, unless an identical copy
    /// is there, and makes the icon theme see it.
    /// 把 `png` 複製進私有的 hicolor 主題(已有相同副本時不複製),並讓圖示主題看到它。
    static func installInIconTheme(_ png: URL, named name: String) throws {
        let index = iconThemeRoot.appendingPathComponent("hicolor/index.theme")
        try FileManager.default.createDirectory(
            at: index.deletingLastPathComponent(), withIntermediateDirectories: true)
        if (try? Data(contentsOf: index)) != Data(indexTheme.utf8) {
            try Data(indexTheme.utf8).write(to: index, options: .atomic)
        }
        let data = try Data(contentsOf: png)
        var changed = false
        for size in iconSizes {
            let apps = iconThemeRoot.appendingPathComponent("hicolor/\(size)x\(size)/apps", isDirectory: true)
            try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
            let copy = apps.appendingPathComponent(name + ".png")
            if (try? Data(contentsOf: copy)) != data {
                try data.write(to: copy, options: .atomic)
                changed = true
            }
        }
        guard changed else { return }

        guard let display = gdk_display_get_default(), let theme = gtk_icon_theme_get_for_display(display),
            let root = iconThemeRoot.withUnsafeFileSystemRepresentation({ $0.map { String(cString: $0) } })
        else { return }
        if !addedIconThemeRoot {
            addedIconThemeRoot = true
            gtk_icon_theme_add_search_path(theme, root)
        } else if let paths = gtk_icon_theme_get_search_path(theme) {
            // A file added to a directory the theme has already read is not
            // seen until the theme reloads; setting the same search path
            // again is the public way to make it.
            // 主題已讀過的目錄裡新增的檔案，要等主題重新載入才看得到；重設同一條搜尋路徑是讓它重新載入的公開做法。
            paths.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: 1) {
                gtk_icon_theme_set_search_path(theme, $0)
            }
            g_strfreev(paths)
        }
    }
}
