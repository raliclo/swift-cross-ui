# Linux（GtkBackend）測試計畫，透過 WSL

目標：在這台機器上重現 open 的 GtkBackend/Gtk3Backend issues，能修的就修，並將修正提交 upstream。工作方式和 WinUI 工作相同：先重現，量測而非推論，並保留證據。

哪個 app 涵蓋哪個 issue，以及 WSLg 執行結果是能判定 issue 還是只能顯示症狀，請看 `UI-test-plan platform-en.md`。下方 Tier 1 / Tier 2 的區分就來自那份文件；但請注意，Tier 2 不等於「WSLg 會扭曲它」：要讀 caveat 欄，因為只有 #556 是關於 window sizing 本身。

## 目前環境

已檢查，不是假設：

| | |
|---|---|
| WSL | Ubuntu 26.04 LTS, WSL2, running |
| WSLg | 可用 -- `DISPLAY=:0`, `WAYLAND_DISPLAY=wayland-0`，所以 GTK windows 會 native 顯示 |
| Swift | **6.3.3**，從官方 tarball 安裝到 `/usr/local/swift` |
| GTK 4 | **4.22.4**（已安裝 `libgtk-4-dev`） |
| GTK 3 | 未安裝，而且是刻意不安裝 |

WSLg 提供的是 Wayland compositor。任何關於 window sizing、minimum sizes 或 resizing 的行為，都會和真正 desktop session 不同，因此這些 issues 需要 caveat（見 Tier 2）。

## Phase 0 -- toolchain

已完成。`testapp/install_tool_wsl.sh` 會處理全部設定，也記錄了需要做什麼；請以 root 執行，因為此 distribution 裡的 `sudo` 會要求密碼：

```sh
wsl -d Ubuntu -u root -- bash testapp/install_tool_wsl.sh
```

它解決的事項如下，沒有任何一項是猜測：

1. swift.org **沒有**發布 Ubuntu 26.04 build -- 26.04 tarball URL 會 404，而 24.04 的 URL 回 200 -- 所以安裝的是 24.04 build，從官方 tarball 放到 `/usr/local/swift`。不是 Swiftly。
2. 該 build 在 26.04 上啟動時會連續遇到兩個問題：26.04 提供 `libxml2.so.16`，但 Swift 要 `.so.2`；另外 26.04 是 ICU 78，但 Swift 要 ICU 74。兩者都從 24.04 `.deb` package 解出到 `/usr/local/lib/swift-compat`。
3. 已安裝 GTK 4：`libgtk-4-dev` 4.22.4，pkg-config 2.5.1。
4. 驗證：`pkg-config --modversion gtk4` 和 `swift --version`。

**範圍：只包含 GtkBackend。** Gtk3Backend 不在 scope 內，所以不安裝 GTK 3，也不追 Gtk3-only 的 issues。這直接排除 #286 和 #166，也代表 #426 只會針對 GTK 4 測試。

GTK 4.22.4 很新，所以 #702（關於*較舊* GTK 4）在開始前就已經判定：這裡無法重現。

## Phase 1 -- 先證明 toolchain end to end 可用

在碰任何 issue 前，先於 WSLg 下 build 並執行 repository 自己的一個 example。如果 window 沒出現，那是環境問題，不是被測程式的 bug；後續所有結果都會可疑。

```sh
./Scripts/test.sh                    # unit tests
swift build --target GtkBackend      # not --product
```

`--target GtkBackend` 不是偏好，而是必要。單純 `swift build` 或 `--product SwiftCrossUI` 會讓 SwiftPM 建置 default target set，其中包含 `WinUIInterop` C target，Linux 上會因 `'Windows.h' file not found` 失敗。直接指定 target 才能繞過。

本機量測：clean 狀態下 `--target GtkBackend` 需要 61.7 秒；warm 後 `testapp/compile.sh` 建一個 repro app 約 5-15 秒。

## Phase 2 -- 既有 test apps 提供的免費覆蓋率

`testapp` 中每個 app 都使用 `DefaultBackend`，Linux 上會選 GtkBackend；`testapp/compile.sh` 已處理非 `.exe` 輸出。P0-P3 與 P5 應可不改直接 build/run；P4 和 P6 的 Windows-specific sections 都包在 `#if os(Windows)` 後面。

這很重要，因為 **P2 和 P3 已經有兩個 open issues 的測試步驟**，那些步驟是在 WinUI 版本修正時寫的：

- P2 step 7-8 涵蓋 #390：disabled buttons 看起來不像 disabled
- P3 step 6-9 涵蓋 #389：images 未被裁切

所以第一次真正測試不需要寫新 app。執行 P0-P3 和 P5，記錄哪些 WinUI 已修行為在 GTK 上仍壞。應該擴充 `UI-test-plan overall-zhTW.md` / `UI-test-plan overall-en.md`，加入 Linux 欄位或 section，而不是另開一份文件。

此計畫寫成後，已新增 P7-P10 來涵蓋下方 Tier 1 / Tier 2 issues，也新增 P13 來測三個非 GTK-specific 但此處可觸及的 core-layout issues。它們都能在 WSL 的 GtkBackend 下 build 與 link，所以剩下只需要有人看著畫面測試。

## Phase 3 -- open issues triage

截至此計畫，Linux/GTK 對應 12 個 open issues。其中兩個（#286、#166）是 Gtk3Backend-only，因 Gtk3 排除而移除，剩下 10 個。之後 Tier 2 又從 `issues.csv` 補進三個標為 `core/unspecified`、而非 GtkBackend 的 issues：它們不是 GTK bugs，但可從此處觸及；在第二個 backend 上檢查 core layout bug，比只在一個 backend 上檢查更有價值。

**Tier 1 -- 一般 widget 行為，應可在 WSLg 重現**

| # | Title | App | Notes |
|---|---|---|---|
| 389 | Images aren't clipped | P3 | 已測過；WinUI 半邊已修，GTK 半邊 open |
| 390 | Disabled buttons don't appear disabled | P2 | 已測過；WinUI 半邊已修，GTK 半邊 open |
| 417 | ScrollView cornerRadius doesn't affect children | P8 | |
| 426 | Horizontal ScrollView swallows parent's scroll wheel | P8 | nested-scroll case |
| 454 | Transparent containers consume click events | P10 | 也影響 AppKitBackend |
| 476 | List starts with the first item selected | P7 | |
| 478 | Ctrl-Q does not quit | P10 | keyboard handling，WSLg 會傳遞 keys |
| 504 | TextField/SecureField shrinks in height after first update | P9 | |

**Tier 2 -- layout 與 window sizing，WSLg 可能扭曲結果**

| # | Title | App | Caveat |
|---|---|---|---|
| 556 | List NavigationSplitView makes weird size decisions | P7 | |
| 295 | Clip text when necessary to reach zero width | P9 | Gtk3Backend 半邊不在 scope |
| 595 | Text inside a ScrollView is cut off | P13 | 非 GTK-specific；要和其他 backends 比較 |
| 291 | NavigationSplitView minimum width sizing | P13 | 回報為 AppKit affected、Gtk unaffected |
| 158 | Group behaviour in ZStacks | P13 | 非 GTK-specific |

先重現這些；但在宣稱 fix 前，請在真正的 Linux desktop session 上確認，或至少明確說明只在 WSLg 下檢查過。

**Tier 3 -- 需要目前沒有的東西，或不是 bug**

| # | Title | Why |
|---|---|---|
| 702 | Older GTK 4 breaks button label centering | 26.04 提供 4.22.4；需要較舊 GTK |
| 386 | Support dark mode | feature；需要設定 dark theme |
| 594 | EventControllerKey.keyPressed cannot return Bool | binding generation，不需要 GUI 也可測 |
| 52 | libadwaita support | feature request |

先從 Tier 1、成本最低的開始：#389 和 #390 不需要新增測試程式。

## Phase 4 -- 每個 issue 的流程

1. 重現，並擷取觀察結果（screenshot 或描述症狀）。若無法重現，也在 issue 上說明；這也是有用結果，尤其是那些早於目前 GTK 版本的 issues。
2. 新增或擴充一個能隔離問題的 `testapp` app，沿用既有 P0-P6 慣例，並將步驟加入兩份 test plan 文件。
3. 在 `Sources/GtkBackend` 修正，變更範圍保持和 bug 一樣小。若 issue 同時點名兩個 backends，修 GtkBackend，並在 pull request 中說明 Gtk3Backend 未測。
4. 用 test app 驗證，並檢查鄰近行為沒有 regression。
5. 每個 issue 一個 commit，風格沿用這裡已使用的格式（`GtkBackend: ...`）。

## 提交 upstream 前

- `Scripts/format.sh`（SwiftFormat 已安裝在 Windows 端；也可在 WSL 安裝，或從 Windows format）。
- 專案的 LLM policy 適用：pull request description 必須揭露使用情況，作者必須理解程式碼，而且 **description 必須由作者撰寫，不可由 LLM 代寫**。
- 優先一個 issue 一個 pull request。Contributing guide 要求 focused changes，而這裡較小的項目正好符合。

## 風險

- **Ubuntu 26.04 沒有對應 Swift build**，所以這裡使用的是 24.04 toolchain 搭配 26.04 libraries，並用從 24.04 packages 取出的 `libxml2` 和 ICU shim。它能 build 與 link，但不是 swift.org 測試的組合。若 failure 看起來像 Swift 或 Foundation bug，回報前應先懷疑是這個組合造成的。
- **WSLg 是 Wayland**，所以 window-level 行為與一般 desktop 不完全相同。Tier 2 結果需要附上這個 caveat。
- **GTK version skew**：4.22.4 很新，所以關於較舊 GTK 的 bugs 無法在此重現；在它上面驗證的 fix 也不能假設能幫助較舊 distributions 的使用者。
- 其中幾個 issues 很舊。有些可能已經修好；確認並關閉它們也是合理結果。
