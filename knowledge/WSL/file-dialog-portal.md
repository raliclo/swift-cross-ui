# WSLg: GtkFileDialog and xdg-desktop-portal

Written 2026-10-24 from `Sources/GtkBackend/GtkBackend.swift`
(`showFileChooserDialog`, the colour-scheme notes), `wslg_portal_display` in
`testapp/test_support/test_common.zsh`, and fb63d14a.

## What

- GtkBackend shows file dialogs with `GtkFileDialog`, not
  `GtkFileChooserNative` (deprecated in the GIR). On stock WSLg, which has no
  xdg-desktop-portal, the old API under Wayland returned the file but left the
  dialog on screen; a stock GTK 4 app using `GtkFileDialog` closed correctly in
  the same session.
- This distribution gained xdg-desktop-portal 1.21.1 and
  xdg-desktop-portal-gtk 1.15.3 on 2026-09-17. `GtkFileDialog` prefers the
  portal whenever one answers, and systemd starts portal-gtk with no `DISPLAY`
  and no `WAYLAND_DISPLAY`. P62's save went to the portal, the journal read
  "Failed to open X11 display", no dialog appeared, and the Return meant for
  the dialog went to P62; the window stayed "Untitled" with no error in the
  test's output (2026-10-20).

## Fix in the harness

Before every WSLg run, `wslg_portal_display` runs (through `wsl.exe`):

```sh
systemctl --user show-environment | grep -q ^WAYLAND_DISPLAY= && exit 0
dbus-update-activation-environment --systemd DISPLAY WAYLAND_DISPLAY
systemctl --user try-restart xdg-desktop-portal-gtk.service
```

The import does not survive a WSL restart, so it is repeated; with the
variables present it does nothing. After it, the same action file saved
Untitled.txt (P62, 2026-10-20).

## How to apply

- A file dialog that never appears under WSLg, with no error: check
  `systemctl --user show-environment` for `WAYLAND_DISPLAY` and the user
  journal for "Failed to open X11 display" before suspecting GtkBackend.
- Running an app by hand outside `test.zsh` after a WSL restart needs the
  same import once.

## Limits

- The desktop colour-scheme notification path (GtkSettings
  `gtk-theme-name`/`gtk-application-prefer-dark-theme`) produced no
  notifications under WSLg in an earlier measurement, when WSLg had no
  portal, no XSettings manager and an empty `XDG_CURRENT_DESKTOP`. Whether the
  installed portal's Settings interface changes that is unmeasured (open,
  2026-10-20). Dark mode on WSL is read from Windows instead; see
  [theme-and-fonts.md](theme-and-fonts.md).

---

# WSLg:GtkFileDialog 與 xdg-desktop-portal

2026-10-24 依 `Sources/GtkBackend/GtkBackend.swift`(`showFileChooserDialog`、配色註記)、
`testapp/test_support/test_common.zsh` 的 `wslg_portal_display` 與 fb63d14a 寫成。

## 是什麼

- GtkBackend 以 `GtkFileDialog` 顯示檔案對話框，而非 `GtkFileChooserNative`(GIR 標為 deprecated)。原版 WSLg
  沒有 xdg-desktop-portal,舊 API 在 Wayland 下會回傳檔案、卻把對話框留在螢幕上；同一工作階段裡使用
  `GtkFileDialog` 的原生 GTK 4 app 則正常關閉。
- 這個發行版在 2026-09-17 裝上了 xdg-desktop-portal 1.21.1 與 xdg-desktop-portal-gtk 1.15.3。只要 portal 有回應,
  `GtkFileDialog` 就交給它，而 systemd 啟動 portal-gtk 時沒有 `DISPLAY` 也沒有 `WAYLAND_DISPLAY`。P62 的存檔走到
  portal,journal 寫著「Failed to open X11 display」,沒有對話框出現，原本給對話框的 Return 落到 P62 身上；視窗標題
  停在「Untitled」,測試輸出裡沒有任何錯誤(2026-10-20)。

## harness 中的修正

每次 WSLg 執行之前,`wslg_portal_display` 會(經由 `wsl.exe`)執行上方三行指令。這個匯入在 WSL 重啟後不會保留，
所以每次都重做；變數已在時什麼都不做。之後同一份動作檔存下了 Untitled.txt(P62,2026-10-20)。

## 怎麼用

- WSLg 下檔案對話框一直不出現、也沒有錯誤：先查 `systemctl --user show-environment` 有沒有 `WAYLAND_DISPLAY`,
  以及使用者 journal 有沒有「Failed to open X11 display」,再懷疑 GtkBackend。
- WSL 重啟後在 `test.zsh` 之外手動執行 app,同樣需要先做一次這個匯入。

## 限制

- 桌面配色變更的通知路徑(GtkSettings 的 `gtk-theme-name`/`gtk-application-prefer-dark-theme`)在較早的量測中於
  WSLg 下沒有任何通知，當時 WSLg 沒有 portal、沒有 XSettings manager,`XDG_CURRENT_DESKTOP` 為空。已安裝的 portal
  的 Settings 介面是否改變這一點，尚未量測(未解決,2026-10-20)。WSL 上的深色模式改從 Windows 讀取；見
  [theme-and-fonts.md](theme-and-fonts.md)。
