# WSLg: dark mode and fonts come from Windows

Written 2026-10-24 from 8f0fcad6, 97539442, 1e2ae4b0,
`Sources/GtkCHelpers/gtk_wsl_fonts.c` and `testapp/install_tool_wsl.zsh`.

## What

WSLg's GTK has no desktop to follow: no settings daemon, no portal theme
setting it reads, Adwaita light, and DejaVu Sans (regular and bold only). On a
dark Windows desktop every app drew light, and P22's nine weights drew as two.
On WSL (`WSL_DISTRO_NAME` or `WSLInterop` present) GtkBackend now:

- reads `AppsUseLightTheme` once at launch through `reg.exe` (59 ms, a 2 s
  limit, nil on any failure). A change made while the app runs is followed at
  the next launch, not live;
- adds Windows' Segoe UI files from `/mnt/c/Windows/Fonts` to fontconfig
  before Pango builds its font map, then swaps the family in `gtk-font-name`
  and keeps the size. Only the named files are added: scanning about a
  thousand fonts over WSL's 9p file system costs seconds per launch.
  `SCUI_GTK_NO_WINDOWS_FONT=1` keeps the distribution's font.

P22 then draws dark with five weights (light, regular, semibold, bold, black).

## Test runs are forced dark

`test_common.zsh` puts `SCUI_GTK_COLOR_SCHEME=dark` in every launch's
environment, on Windows, WSL and macOS, so the three GTK captures of one app
differ in layout, not theme (97539442; on 2026-10-22 WSL had drawn P0 and P44
light). `=light` or `=system` overrides it. Only GtkBackend reads it.

## Fonts the distribution must have

A stock WSL image has neither CJK nor emoji fonts. Nothing errors; text just
draws wrong, which reads as a rendering bug:

- `fonts-noto-cjk`: without it fontconfig had 0 fonts for zh-TW, `fc-match`
  answered DejaVu Sans, and Chinese drew as tofu boxes (P6's file name);
- `fonts-noto-color-emoji`: without it `fc-list | grep -ci emoji` was 0 and
  each emoji drew as a hex code-point box (P103's picker, 2026-10-22).

`install_tool_wsl.zsh` installs both.

## How to apply

- Boxes instead of characters under WSLg: check `fc-list` before GtkBackend.
- Layout moved after the Segoe UI change (8f0fcad6): action files aimed
  before 2026-10-20 may need re-aiming (P74's rows moved 16 px, P92's field
  moved).

---

# WSLg:深色模式與字型取自 Windows

2026-10-24 依 8f0fcad6、97539442、1e2ae4b0、`Sources/GtkCHelpers/gtk_wsl_fonts.c` 與 `testapp/install_tool_wsl.zsh` 寫成。

## 是什麼

WSLg 的 GTK 沒有桌面可以跟隨：沒有設定 daemon、沒有它會讀的 portal 主題設定，用的是 Adwaita 淺色與 DejaVu Sans
(只有一般與粗體)。在深色的 Windows 桌面上，每支 app 都畫成淺色,P22 的九種字重只畫出兩種。在 WSL 上
(有 `WSL_DISTRO_NAME` 或 `WSLInterop`)GtkBackend 現在會:

- 啟動時經 `reg.exe` 讀一次 `AppsUseLightTheme`(59 毫秒，上限 2 秒，任何失敗都回傳 nil)。app 執行中所做的變更
  在下次啟動才生效，不是即時的;
- 在 Pango 建立字型對照之前，把 `/mnt/c/Windows/Fonts` 中 Windows 的 Segoe UI 檔案加進 fontconfig,再替換
  `gtk-font-name` 的字族、保留大小。只加指名的檔案：經由 WSL 的 9p 檔案系統掃描上千個字型，每次啟動要花數秒。
  `SCUI_GTK_NO_WINDOWS_FONT=1` 保留發行版的字型。

之後 P22 以深色、五種字重(light、regular、semibold、bold、black)繪製。

## 測試執行強制深色

`test_common.zsh` 在每次啟動的環境中放入 `SCUI_GTK_COLOR_SCHEME=dark`,Windows、WSL 與 macOS 皆然，讓同一支 app
的三張 GTK 擷圖只差在版面而非主題(97539442;2026-10-22 WSL 曾把 P0 與 P44 畫成淺色)。`=light` 或 `=system`
可以覆寫。只有 GtkBackend 會讀它。

## 發行版必須有的字型

原始 WSL 映像既沒有 CJK 也沒有 emoji 字型。不會有任何錯誤，只是字畫錯，看起來像算繪缺陷:

- `fonts-noto-cjk`:沒有它時 fontconfig 對 zh-TW 有 0 個字型,`fc-match` 回答 DejaVu Sans,中文畫成豆腐框
  (P6 的檔名);
- `fonts-noto-color-emoji`:沒有它時 `fc-list | grep -ci emoji` 為 0,每個 emoji 畫成寫著十六進位碼位的方框
  (P103 的選擇器,2026-10-22)。

`install_tool_wsl.zsh` 兩者都會安裝。

## 怎麼用

- WSLg 下出現方框而非文字：先查 `fc-list`,再懷疑 GtkBackend。
- 換成 Segoe UI(8f0fcad6)後版面有位移:2026-10-20 之前瞄準的動作檔可能需要重新瞄準(P74 的列下移 16 px,
  P92 的欄位也移動了)。
