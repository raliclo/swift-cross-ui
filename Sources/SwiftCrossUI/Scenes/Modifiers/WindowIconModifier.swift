import Foundation

extension Scene {
    /// Sets the icon shown for this scene's windows: in the titlebar where the
    /// platform draws one there, and in the taskbar or window switcher.
    ///
    /// `url` is a PNG file, normally one bundled with the app
    /// (`Bundle.module.url(forResource:withExtension:)`); `nil` leaves the
    /// platform's default. A square image of 256x256 or more gives every
    /// platform something to scale down from.
    ///
    /// - GtkBackend finds icons by name, so the file's name without its
    ///   extension becomes the icon name and its directory joins the icon
    ///   search path. Give the file a distinctive name (the app's id, say):
    ///   an icon theme that already has an icon of that name wins over it.
    ///   The titlebar GTK draws itself shows the icon at its leading edge.
    /// - WinUIBackend sets it on the `AppWindow`, which covers the titlebar,
    ///   the taskbar and Alt+Tab.
    ///
    /// The icon of an executable file, as a file manager shows it, is a
    /// resource fixed when the program is built and is not changed by this.
    ///
    /// 設定本 scene 的視窗所顯示的圖示：平台在標題列畫圖示時在標題列，以及工作列或視窗切換器。
    ///
    /// `url` 是一個 PNG 檔，通常隨 app 打包(`Bundle.module.url(forResource:withExtension:)`);`nil`
    /// 保留平台預設。256x256 以上的正方形圖片讓每個平台都有東西可以縮小。
    ///
    /// - GtkBackend 以名稱找圖示，所以檔名(不含副檔名)成為圖示名稱，其所在目錄加入圖示搜尋路徑。檔名要
    ///   有辨識度(例如 app 的 id):圖示主題若已有同名圖示，會蓋過它。GTK 自己畫的標題列在前緣顯示圖示。
    /// - WinUIBackend 設定在 `AppWindow` 上，涵蓋標題列、工作列與 Alt+Tab。
    ///
    /// 檔案管理員顯示的執行檔圖示是建置時固定的資源，這裡不會改變它。
    public func windowIcon(_ url: URL?) -> some Scene {
        environment(\.windowIcon, url)
    }
}
