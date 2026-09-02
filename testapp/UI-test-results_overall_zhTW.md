# WinUI 手動測試結果紀錄

## 2026-07-12

### P2：Controls And Styling

- #449 Picker：點開 `Flavor` picker 時，曾觀察到 WinUI/Composition `BVI-*`、`rcBackdropLocal`、`CachedNewBlur` console diagnostic log。已嘗試在 WinUIBackend 覆寫 `ComboBoxDropDownBackground` 為 solid brush，待重新測試確認 console noise 是否消失。
- #449 Picker：先前 dropdown 會立即消失，且無法選擇其他 option。已調整 WinUI ComboBox：options 未變時不更新 items，selected index 未變時不重設 selection，待重新測試確認。
- #471 TextEditor：先前輸入可能漏字，例如快速輸入 `12345` 只顯示 `1235`。已移除 TextEditor 的一次性 `shouldBlockNextChangedSignal` 阻擋邏輯，改用最後同步文字避免同值 binding write，待重新測試確認。
- #390 (Fixed)：disabled button 與 enabled button 視覺差異目前回報為 no issue。
- #401 (Fixed)：window resizing / full screen button 行為目前回報為 no issue。

### P3：Layout And Clipping

- #160：截圖顯示初始或特定視窗尺寸下 NavigationSplitView 欄位可能被裁切或配置不穩，需繼續記錄 resize / force state update 前後差異。
- #389：截圖顯示 oversized image 仍可能超出預期 frame，需記錄為 image clipping 相關現象並後續修正。

### P4：WinUI Native And Callback Stress

- #156：截圖顯示 native WinUI banner 與 `TextField.inspect` 修改後的 border 可見，初步看起來 native API escape hatch 有生效。
- #190：截圖顯示 row buttons 與 scroll view 正常出現；仍需逐一點擊 `Run N`、增減 rows、重複 force update 來確認 callback 是否錯亂。
- Row size 增加延遲：目前判斷和 WinUIBackend 有關。P4 每個 row 會建立 Button/Text/Spacer 等多個 native widgets；row count 增加時，SwiftCrossUI `ForEach` 會重用舊 row 並新增新 row，但 ScrollView/VStack 仍會 layout 所有 rows。WinUIBackend 原本每次 `updateButton` 都重建 button content 的 `TextBlock`，大量 row update 時會放大延遲。已先改成 `CustomButton` 重用 label TextBlock，待重新測試比較延遲是否下降。

## 2026-08-16

### P7：Lists And Split Views

- #476 (Fixed)：Windows `P7.exe` 啟動時 plain list 沒有任何列被選取，狀態列顯示 `Selection: none`，符合預期。
- #476 (Fixed)：WSLg/GTK4 `P7` 現在啟動時 selection binding 仍維持 `nil`；plain List 沒有 highlighted row，狀態列顯示 `Selection: none`。
- #476 (Fixed)：安裝 `libgtk-3-dev` 後也已確認 WSLg/Gtk3；`swift build -c release --target Gtk3Backend` 通過，Gtk3 P7 執行時也不再於啟動時選取 `Apple`。
- #476 (Fixed)：修正後點選 `Cherry`、`Clear selection`、`Select Cherry` 仍會正確更新或清除選取列。
- #386 / GTK theme 觀察：WSLg/GTK 使用原生 GTK theme metrics 與顏色，因此背景、文字對比、間距、selected row 樣式會和 WinUI 不同。在 `GTK_THEME=Adwaita:dark` 下，app 背景變深，但截圖中仍可看到部分文字對比偏低，後續驗證 GTK theme 行為時應一併注意。
- #556（已由 2026-09-01 量測修正判讀）：當時截圖看起來像 Windows 與 WSLg/GTK 的 pane aspect / split ratio 不一致。後續診斷顯示這是量測誤讀：把 content width 當成 pane width。
- #556：點選 plain List 的 `Cherry` 後，NavigationSplitView 的 detail pane 仍顯示 `No sidebar selection`。以目前 P7 測試內容來看，plain List selection 與 NavigationSplitView sidebar selection 是分開的，這應屬預期；但閱讀對照截圖時需要注意這點。
- #556：Step 7 功能上穩定。按 `Add a fruit's worth of text` 後，上方較長文字出現，split view 沒有跳動或塌陷。後續診斷顯示此情境下 WSLg 與 Windows 的實際 pane ratio 相同。
- #556：Step 8 功能上穩定。調整視窗大小後，包含大幅加寬視窗的情境，Windows 與 WSLg/GTK 的 detail pane 都保持可見。後續診斷顯示此情境目前不再重現 pane-ratio mismatch。
- #556 / Windows Light mode：Windows Light mode 下，右側第三 pane 沒有顯示預期的垂直分隔線（`|`）；相較之下，WSLg/GTK 對照截圖中可看到 pane boundary。先記錄為 split-view detail pane 的 Windows/GTK 視覺一致性問題。
- WSL/Windows GUI comparison：同一個 P7 測試情境下，Windows `P7.exe` 與 WSLg/GTK `P7` 的視窗尺寸理論上應該一致，但截圖對照顯示兩者有明顯尺寸差異。這需要進一步調查，否則不能直接把跨 backend 的 layout screenshot 視為等比例比較；後續需確認差異來自 requested content size、backend window-sizing semantics、DPI scaling、window decorations，或 WSLg compositor 行為。**（已於 2026-08-18 以 P6 解答：成因為 DPI scaling，詳見該日紀錄。）**

### P8：Scroll Views

- #426 (Confirmed/Open, WSLg/GtkBackend only)：已確認此問題只在 WSLg / GtkBackend 發生；Windows / WinUIBackend 對照未重現。WSLg 上水平與垂直 scroll 都完全不移動，包含游標位於內層水平長條上並嘗試水平或垂直滾動的情境；外層垂直 scroll view 沒有如預期接收/接手滾輪事件。
- #426：後續修正應優先在 WSLg / GtkBackend 上重現與驗證，再用 Windows / WinUIBackend 作為 non-regression 對照。可使用 `zsh testapp/test.zsh P8 --both`；腳本會先跑 WSLg、render 後保留 30 秒並拍 final screenshot，再跑 Windows。
- #417（WSLg/GtkBackend 未重現）：紅色子元件明顯被 `cornerRadius(20)` 裁切——WSLg 截圖中四個角都是圓的，與「內容從圓角穿出」的回報症狀相反。同時量到 `cornerScroll: 260x120` 對 `redChild: 260x300`，子元件確實超出容器 180px，也就是說有東西可被裁切。僅在 WSLg 下以靜態截圖確認；未檢視 Windows，也未在真實 Linux 桌面工作階段驗證。
- #266（附帶重現，僅 WinUIBackend）：內層水平長條在 Windows 上被量到兩次，先 `420x48` 後 `408x48`；WSLg 只量到一次 `420x48` 且維持不變。那 12px 是**外層** ScrollView 的垂直捲軸：WinUI 在後續的 layout pass 從內容寬度扣除，GTK 則以 overlay 呈現而不佔寬度。這正是 #266 描述的取捨——顯示捲軸會改變內容可用寬度，寬度改變可能改變內容高度，進而改變是否還需要捲軸。此處無害，因為沒有東西依賴該寬度，且 P8 並非為 #266 設計；記錄下來是因為若要處理 #266，這是現成的重現點。

## 2026-08-18

### P6：Stream Player

- P6 首次在 WSLg 上實際執行。先前從未跑過的原因不是 Linux 呈現路徑缺失，而是 `testapp/output/` 同時被 git 與 rsync 排除（該目錄屬各機器自有），因此 WSL 端沒有媒體檔可播。複製媒體檔後，ffmpeg 解碼管線、視窗、播放控制與版面皆正常，00:24 的截圖畫面完整正確。
- 判讀提醒：測試用影片開頭數秒為淡入，畫面接近全黑，僅右緣有轉場內容。單看該時段的截圖會誤判為呈現異常（本次即發生過一次）。判讀 P6 截圖應取播放中段而非開頭。
- `-seek`（已修正）：該旗標原本定義於 Windows 專屬的 `P6WindowFlags`，唯一使用處也包在 `#if os(Windows)` 內，因此在 Linux 與 macOS 上會被接受卻毫無作用。移至平台中立的 `P6DecoderFlags` 後，以同一個 binary 對照：無 `-seek` 時 play session 起始 `0.000s`、第一格 00:00；`-seek 90` 時起始 `90.000s`、第一格 01:30。Windows 端重建後仍為 `90.000s`，無回歸。
- `-maximized`（已修正）：原本同樣只存在於 Windows。GTK 端改由 `@Environment(\.window)` 取得 backend 視窗、轉型為 `Gtk.ApplicationWindow` 並呼叫新增的 `Gtk.Window.maximize()`；截圖確認 WSLg 視窗滿版 1920x1080。SwiftCrossUI 先前在任何 backend 都沒有 maximize 概念。
- `-topmost`（維持 Windows 專屬）：GTK4 沒有置頂 API（`gtk_window_set_keep_above` 屬 GTK3 且已移除），Wayland 亦依設計不允許 client 自我抬升，因此刻意不提供 Linux 路徑，而非留待日後補上。
- WSL 缺少 CJK 字型（已修正）：原始 WSL 映像的 `fc-list :lang=zh-tw` 為 0，zh-TW 的 fc-match 回退到不含漢字的 DejaVu Sans，GTK 因而把中文 UI 文字畫成豆腐框。此症狀極易被誤判為 backend 的算繪缺陷——同一張截圖中，影片壓製的中文字幕清晰可辨（那是像素），只有 UI 文字是方框（那是文字），且全程沒有任何錯誤訊息。安裝 `fonts-noto-cjk` 後 zh-TW 字型由 0 增為 30，檔名完整顯示；已寫入 `install_tool_wsl.sh`。Windows 端不受影響，因為它使用含 CJK 的系統字型。
- 音訊（已解決）：P6 在 WSLg 上沒有聲音。**唯一的成因是 WSLg 的 PulseAudio server 停止監聽**，`pactl`、`paplay` 與 SDL 三個客戶端在同一時刻都得到 `Connection refused`。在 Windows 執行 `wsl --shutdown` 後重開 WSL，伺服器即恢復（`Server Name: pulseaudio`、`Server Version: 17.0`、`Default Sink: RDPSink`、`RDP Sink - Connected to fd 20`），播放經使用者實聽確認。Windows 端音訊裝置本來就全部正常（Realtek(R) Audio `oem10.inf`、NVIDIA HD Audio、AMD HD Audio、NVIDIA Virtual Audio Device，狀態皆為 Started）。
- 音訊誤判紀錄（重要，避免重蹈）：中途一度把 32 行 `ALSA lib confmisc.c:855:(parse_card) cannot find card '0'` 當成根本原因，並為此在 P6 中加入 `SDL_AUDIODRIVER=pulse`。那是**症狀而非病因**——pulse 連不上時 SDL 才退回 ALSA。伺服器修復後實測：不設任何變數時 exit 0 且 0 行 ALSA 錯誤，SDL 自己就會選擇 pulse；強制 `SDL_AUDIODRIVER=alsa` 才會產生那 32 行。因此該程式碼改動已撤除。當初之所以誤判為「pulse 修好了」，是因為判定用的 grep 只匹配 `ALSA|error`，看不見 pulse 路徑真正的失敗訊息 `Could not initialize SDL - Could not connect to PulseAudio`：ALSA 路徑是吵鬧的失敗，pulse 路徑是安靜的失敗，兩者都沒有播放。**教訓：用退出碼判定成敗，不要用只匹配特定字串的過濾器。**
- 判別要點：若沒有 `pactl`，此問題無法與「client 端設定錯誤」區分——socket 存在、`PULSE_SERVER` 指向正確、檔案權限也正常，看起來完全設定妥當。`pactl info` 是唯一能分辨兩者的檢查，因此 `pulseaudio-utils` 已列入 `install_tool_wsl.sh`。伺服器可在 socket 檔案仍留在原處的情況下停止服務，所以「socket 存在」不足以作為判斷依據。
- WSL 安裝腳本從未被同步到 WSL：`rsync_WSL.zsh` 的 include 樣式只涵蓋 `*.swift` 與 `testapp/**/*.zsh`，因此 `install_tool_wsl.sh` 從未送達 WSL。實際發現 WSL 端的副本仍停留在 8 月 16 日的版本，而本機已改過多次。已於 include 清單加入該檔並註明理由。
- 安裝腳本已拆分：`install_tool_wsl.sh` 僅保留引導職責（檢查 root、安裝 zsh、交棒），實際邏輯移入新的 `install_tool_wsl.zsh`。維持 `.sh` 進入點的理由無法迴避——該腳本面對的是尚未安裝 zsh 的機器，而安裝 zsh 正是它的工作；若用 zsh shebang，核心會因找不到直譯器而使它完全無法啟動。形狀與「自我提權後立刻交棒」的 `.ps1` launcher 相同。兩個進入點的 `--help` 皆在 0.2 秒內回應且不安裝任何東西。
- 第三方套件庫會中止整個安裝：本機於 2026-08-17 的 GPU 調查期間加入了 NVIDIA CUDA repo 卻沒有一併安裝 keyring，`apt-get update` 因而以 `NO_PUBKEY A4B469963BF863CC` 失敗；在 `set -e` 下安裝腳本在裝任何東西之前就中止——而它需要的每個套件其實都取得得到。已改為「回報但繼續」，讓真正找不到套件時由安裝指令自行失敗。該 repo 本身仍待處理：補上金鑰或移除（GPU 調查已確認問題不在驅動）。
- GTK 檔案選擇器不關閉（Open，**僅限 Wayland**）：完整 2×2 對照如下，四格皆為實測。

  | | Wayland | XWayland |
  |---|---|---|
  | 無修正 | **不關閉** | 關閉 |
  | 加上 `gtk_native_dialog_destroy()` | **不關閉** | 關閉 |

  結論：**`gtk_native_dialog_destroy()` 沒有任何作用，該修正已撤除。** 先前提出的 refcount 假說（`GObject.init` 對 `gtk_file_chooser_native_new` 已交付的參考再 `g_object_ref` 一次，使物件永不終結）**已被推翻**——若成立，加上明確 destroy 應當有效。
- 檔案選擇器：已確認 response handler 有正常觸發。日誌顯示使用者選檔後出現 `load /mnt/c/.../20260721 …`、`session token 2`、`frame 00:00`、`Frame ready`，亦即 URL 有交回、檔案有載入、影格有解出。**只有對話框沒有消失**，因此問題不在 signal 傳遞，而在對話框視窗的生命週期，且僅發生於 Wayland。XWayland 下同一份程式碼完全正常。
- 檢驗方法備忘：判斷「是否為本專案的缺陷」的下一步，是拿一個非 SwiftCrossUI 的原生 GTK4 app（例如 `gtk4-demo` 的檔案選擇器）在 WSLg Wayland 下測試。若它同樣不關閉，則問題屬於 GTK 或 WSLg，與 GtkBackend 無關；若它正常關閉，才需要回頭查 backend。尚未執行。
- Wayland 與 XWayland 必須分開驗證：Wayland 依設計不允許一個行程驅動另一個 client，因此 xdotool 在預設的 WSLg 工作階段中看不到任何視窗。這代表兩者是真正不同的測試目標——在其中一邊重現的錯誤不能作為另一邊的證據，上述檔案選擇器即為實例。
- WSL GUI 自動化已可用：`xdotool` 搭配 `xwd`／`netpbm` 可在 XWayland 下點擊控制項並擷取視窗內容，且不依賴 Windows 端解鎖。座標須使用 `xdotool mousemove --window`（視窗相對），絕對座標會因視窗裝飾而失準——實測絕對座標點擊完全沒有反應，改為相對座標後立即成功。注意 `xwd` 位於 `x11-apps` 而非 `x11-utils`。
- WSLg 視窗完全不出現（已解決，成因為 COPY MODE）：回報症狀是「P6 啟動後點工作列圖示也不會到前景，甚至根本看不到視窗」。App 本身完全正常——日誌有 `auto-load`、`frame 00:00`、`Frame ready`，代表 `onAppear` 已執行、視窗已建立、影格持續解碼；`/mnt/wslg/weston.log` 也顯示視窗已註冊給 RDP peer（`associateWindowId: 1`、`appWindowId: 0x10`）。真正的原因是 **WSLg 處於 COPY MODE**：其算繪路徑降級，視窗雖存在卻無法被帶到前景。於 Windows 執行 `wsl --shutdown` 後重開即恢復，視窗立即正常顯示。
- 觸發時機：期間 WSL 自我更新（2.7.11.0 → 2.7.12.0），而執行中的 WSLg 實例仍停留在舊狀態，自此進入 COPY MODE。這與稍早的 PulseAudio 失效屬同一類——**WSLg 的橋接（視窗或音訊）會在 socket／視窗看似正常的情況下降級，且不會有任何錯誤訊息**。兩次的補救都是 `wsl --shutdown` 後重開。
- WSLg 會改寫視窗標題，這使得以標題尋找視窗的工具失效：正常時為 `P6 stream player (Ubuntu)`，降級時為 `[WARN:COPY MODE] P6 stream player (Ubuntu)`。AppActivate 比對的是標題開頭或結尾，因此該前綴會讓「P6 stream player」的搜尋直接失敗——而失敗的表現形式是「拍到螢幕上的其他內容」，不是「找不到視窗」。`screenshot.zsh` 現在會以子字串解析真實標題，並在偵測到 COPY MODE 時直接指出補救方式。
- P6 在 Linux 上不會回收 ffplay 子行程：關閉 P6 後仍留下三個各約 8.3 小時的 ffplay 孤兒行程。`P6ChildProcessReaper` 的 job object 機制是 `#if os(Windows)` 專屬，Linux 側沒有對應實作。尚未修正。
- GTK 檔案選擇器（Open，未修正）：在 WSLg 上，`Choose file` 選好檔案後對話框不會關閉。程式位置為 `Sources/GtkBackend/GtkBackend.swift` 的 `showFileChooserDialog`：它呼叫 `gtk_native_dialog_show()`，但 response handler 只處理結果，沒有任何 hide 或 destroy。`Sources/Gtk3Backend/Gtk3Backend.swift` 的同一段結構相同。尚未實地驗證修法。
- WSL/Windows GUI comparison（2026-08-16 該項的解答）：兩端的尺寸差異來自 **DPI scaling**，而非 requested content size、backend window-sizing semantics、window decorations 或 WSLg compositor 行為。在同一台 1920x1080 螢幕、兩端皆 `-maximized` 的條件下量到：Windows 影片區為 1200x675 px，WSLg/GTK 為 960x540 px。Windows 日誌本身即記錄 `viewport 960.0x540.0 dip (1200x675 px), panel actual 960.0x540.0 dip, rasterization scale 1.25`，並有 `window metrics: dpi 120`。亦即 WinUIBackend 套用了 1.25 的 rasterization scale，GtkBackend 則以 1:1 呈現。因此跨 backend 的 layout 截圖在換算 DPI 之前，不可直接視為等比例比較。

## 2026-08-19

### GTK 檔案選擇器：根因確認

- **根因是所使用的 API，而非我們的用法。** 判別方式是拿一個完全不含 SwiftCrossUI 的原生 GTK4 app（`gtk4-node-editor`）在同一個 WSLg Wayland 工作階段下測試：它的檔案對話框**正常關閉**。以 `nm -D --undefined-only` 比對兩者實際連結的符號：

  | | 使用的 API | Wayland 結果 |
  |---|---|---|
  | `gtk4-node-editor` | `gtk_file_dialog_new` / `gtk_file_dialog_open`（**GtkFileDialog**） | 關閉 |
  | SwiftCrossUI GtkBackend | `gtk_file_chooser_native_new` / `gtk_native_dialog_show`（**GtkFileChooserNative**） | 不關閉 |

  同一台機器、同一個 GTK 4.22、同一個 compositor，差別只在 API。
- `GtkFileChooserNative` 在 GIR 中標記為 `deprecated="1"`（`Gtk-4.0.gir`）。標頭檔本身沒有 `GDK_DEPRECATED` 巨集，因此以標頭檔查詢會得到「未標記淘汰」的錯誤結論——GIR 才是權威來源，也正是 `GtkCodeGen` 產生 Swift 綁定所依據的同一份資料。
- 取代用的 `GtkFileDialog` 自 **GTK 4.10** 起提供（`GDK_AVAILABLE_IN_4_10`），系統標頭中所需函式齊備：`open`／`open_multiple`／`save`／`select_folder` 及各自的 `_finish`，加上 `set_title`、`set_initial_folder`、`set_filters`、`set_accept_label`。它是**非同步 API**（`GAsyncResult` callback），與現行以 `response` signal 為中心的實作模型不同，因此遷移需要改寫而非替換函式名稱。
- 方法備忘：先前三次嘗試修正都失敗，因為都在假設「我們用錯了」。真正有效的一步是**切開責任歸屬**——用原生 app 做對照，確認同一環境下別人做得到。這比任何一個新假說都便宜。

### 放棄 GTK3 支援

- 已移除 `Sources/Gtk3`（179 檔／16,365 行）、`Sources/Gtk3Backend`（2,448 行）、`Sources/CGtk3`、`Sources/Gtk3CHelpers`、`Sources/Gtk3Example`、`Tests/Gtk3BackendTests`、`Scripts/generate_gtk3.sh` 與 docc 的 Gtk3Backend 頁面。
- 實際的程式碼依賴**只有兩處**：`Package.swift`（products／targets／測試開關 `SCUI_TEST_GTK3BACKEND`）與 `Sources/DefaultBackend`（`#elseif canImport(Gtk3Backend)` 的後備選擇）。其餘散落的引用全是註解或條件編譯分支。
- `Examples` 內的 `#if canImport(Gtk3Backend)` 分支在模組消失後會自動編譯掉，不會破壞建置，但仍一併移除；`ControlsApp.swift` 的 `#if !canImport(Gtk3Backend)` 則相反——它在移除後永遠為真，因此拆掉包裹讓內容無條件編譯。
- 文件與註解清理另外揪出**兩個真正的破損**，不只是文字：`Scripts/generate_gtk.sh` 仍呼叫已刪除的 `./generate_gtk3.sh`；`GtkCodeGen` 的 `gtk3AllowListedClasses` 與 `version == "3.0"` 分支是實際的產生邏輯。CI workflow 也還在建置與產生 `Gtk3Backend` 的文件（三個步驟＋docc 合併清單）。`Publisher.swift` 另有一個 ``` ``Gtk3Backend`` ``` 的 DocC 符號連結，目標消失後會變成無法解析的連結。
- 刻意**保留**的三處：`gtk_helpers.h` 中作者記述某次 macOS 建置異常的第一人稱說明、`AppBackend refactor.md`（開頭即言明是某 PR 的變更清單，本質為歷史文件），以及 `GtkCodeGen` 中 `populate-popup` 的停用理由——後者已改寫為「GTK3 已移除故該理由不再適用，但尚未在 GTK4 上驗證重新啟用」，而不是直接開啟該訊號，因為那是行為變更。改寫歷史記述等同偽造記錄。
- **rsync 不會傳播刪除，且建置成功會掩蓋這件事**：`rsync_WSL.zsh` 刻意不使用 `--delete`（WSL 端的 `output/`、build 快取與本地修改應保留）。因此本機刪除 193 個 GTK3 檔案後，WSL 端**全部仍在**；而 SwiftPM 會忽略 `Package.swift` 不再宣告的目錄，所以 WSL 上四個 target 依然建置成功——一棵已經與本機不一致的樹，看起來完全正常。已手動清除 WSL 端並重新驗證，同時把這個後果寫進 `rsync_WSL.zsh` 的標頭。
- 驗證：`Gtk`、`GtkBackend`、`DefaultBackend`、`GtkExample` 四個 target 皆建置成功；所有編輯過的檔案通過 `swiftc -parse`。整包 `swift build` 與 `Examples` 在 Linux 上仍會停在 `WinUIInterop`／`swift-winui` 缺 `Windows.h`、`wtypesbase.h`——那是既有的平台限制，與本次移除無關。

### GtkBackend 已能在 Windows 上建置

- 動機是編譯時間：Windows 上以 WinUIBackend 建置 P6 需 95-103 秒，WSL 上以 GtkBackend 僅需 13-22 秒，成本來自 WinAppSDK。WinUIBackend **維持為 baseline**，不移除。
- ABI 是前提：Swift on Windows 以 MSVC ABI 為目標並連結 UCRT。MSYS2 的 GTK 4 是 MinGW 建置，不列入考慮；改用 gvsbuild 的 MSVC 建置版本（`testapp/install_gtk4_windows.zsh`，來源與授權記於 `Acknowledgements/gvsbuild/`）。
- 路徑改寫改由**簽入的 patch** 提供（`testapp/patches/gtk4-pkgconfig-relocate.patch`），行尾則由單一 `tr` 另外處理。分開的理由可量化：兩者混在同一步時，diff 為 8397 行 / 391 KB，因為每個檔案的每一行都因 CR 而不同；分開後是 2745 行，其中約 600 行是實際變更，其餘為 302 個檔案的 diff 標頭。
- 順序被工具鏈決定，而非由設計選擇：**MSYS 工具以文字模式讀檔，只要碰到檔案就會丟棄 CR**。實測一個「只改 prefix 那一行」的 `sed -i`，就讓 gtk4.pc 的 CR 由 14 個變為 0 個。因此行尾無法留到最後處理——必須先正規化，patch 才會套用在內容確實相符的檔案上。
- patch 綁定於單一 gvsbuild 發行版，因此保留規則式的 fallback：若 `patch` 無法套用（換版本時的預期情況），安裝腳本會回退到與 patch 相同的兩條替換規則並明講。實測：patch 乾淨套用至 302 個檔案，`swift build --target GtkBackend` 於 Windows exit code 0。
- gvsbuild 套件**無法直接重新定位**：302 個 `.pc` 檔中有 301 個硬編碼建置機器的 `C:/gtk-build/gtk/x64/release`，且全部使用 CRLF。
- **SwiftPM 的 `.pc` 解析器會被 Windows 磁碟機代號打斷**：它先以第一個冒號切分 keyword，因此 `prefix=C:/gtk4` 被讀成 keyword `prefix=C`，變數 `prefix` 從未定義，回報 `Expected a value for variable 'prefix'`。改寫為不含冒號的 `prefix=${pcfiledir}/../..` 後即可解析；其餘殘留路徑一律代入 `${prefix}`，同樣是為了不引入冒號。
- **SwiftPM 在 Windows 上不套用 systemLibrary 的 pkgConfig cflags**：實測 `GtkCHelpers` 的 clang 呼叫只帶自身 include 目錄，`gtk4.pc` 的內容一項也沒有，即使 `PKG_CONFIG_PATH` 已設定且 pkg-config 回報正確。必須以 `-Xcc -I…` 明確傳入；安裝腳本會印出現成的指令。
- 兩個真正的可攜性缺陷（皆為 Linux/Windows 的 C 型別匯入差異，修法不需要 `#if os(Windows)`）：
  - `gulong` 在 Linux 為 64 位元、Windows 為 **32** 位元（LLP64）。`connectSignal` 原本把它轉成 `UInt` 回傳，於是 disconnect／block／unblock 全部無法編譯。改為全程保持 `gulong`。
  - `gsize` 在 Linux 匯入為 `UInt`、Windows 為 `UInt64`，寬度相同但在 Swift 是不同的具名型別。改為直接以 `gsize(...)` 轉換。
- 結果：`swift build --target GtkBackend` 於 Windows 上 exit code 0。Linux 端同步驗證無回歸。尚未做的是執行期驗證與編譯時間對照，計畫見 `testapp/plan/plan-windows-gtk-backend.md`。

### WSLg 幽靈視窗

- `gtk4-widget-factory` 行程結束後，Windows 端的 `msrdc.exe` 仍持續顯示 `GTK Widget Factory (Ubuntu)` 視窗。WSL 內 `pgrep` 確認無任何對應行程。
- 這是繼 PulseAudio 停止監聽、COPY MODE 之後，**WSLg 橋接第三種靜默失效**：視窗已無擁有者卻不被移除。判讀 WSL GUI 測試結果時，「Windows 上看得到視窗」不足以證明該 app 仍在執行。

## 2026-08-29

### P21-P41 Loader 覆蓋

- 補上 P21、P22、P23、P24、P25、P27、P29、P37、P38、P39、P40、P41 缺少的 `test_support/test_Pn.zsh` loader。所有新 loader 與 `test_support/test_common.zsh` 都通過 `zsh -n`。
- common loader 現在會記錄 screenshot failure，但不會因 `set -e` 中止整個流程。這是必要修正：先前 1 秒截圖失敗時，流程會在 cleanup trap 釋放 `ui-lock` 前退出。
- 測試順序遵守目前規則：先 WSLg，再 Windows。第一批先跑 P27/P29/P37/P38/P39/P40/P41，第二批補跑 P21-P25。

### 自動 Smoke Test 結果

以下 final screenshot 都使用 `wincap` 擷取，並以 PIL 量測。每張 final capture 都是可見且非黑畫面。

| App | WSLg final screenshot | Windows final screenshot | 備註 |
| --- | --- | --- | --- |
| P21 | 848x749，93.0% 非黑 | 836x759，93.2% 非黑 | Windows render marker 8 秒後出現；WSLg 立即出現。 |
| P22 | 788x729，92.6% 非黑 | 776x739，93.0% 非黑 | wrapped text 診斷不同：WSLg `300 x 46`，Windows `300 x 32`。 |
| P23 | 848x649，92.4% 非黑 | 836x659，92.5% 非黑 | 兩平台皆建置成功並抵達 final capture。 |
| P24 | 748x589，91.5% 非黑 | 736x599，91.8% 非黑 | 兩平台皆建置成功並抵達 final capture。 |
| P25 | 748x549，91.2% 非黑 | 736x559，91.3% 非黑 | 自動流程只驗證啟動與截圖；live drag/drop 仍需要手動互動。 |
| P27 | 788x726，92.6% 非黑 | 776x702，92.8% 非黑 | 兩平台皆建置成功並抵達 final capture。 |
| P29 | 796x657，82.8% 非黑 | 736x599，91.7% 非黑 | 已新增並驗證 WSLg `P29-texteditor-disabled.csv`：final capture 顯示 replay 後 editor 已切成 enabled。Windows smoke final 可見，但本輪 WinUI actionfile replay 沒有產生 `-actionfile` report，仍待查。 |
| P37 | 788x569，91.5% 非黑 | 776x579，91.6% 非黑 | WSLg 回報 supported levels 為 `automatic, normal`；Windows 回報 `automatic, normal, floating`。Window-level 行為仍需要第二視窗 foreground/topmost 挑戰；本次只驗證 baseline launch/capture 與 backend capability report。 |
| P38 | 848x692，92.6% 非黑 | 836x699，92.8% 非黑 | 最新一輪 WSLg 1 秒與 final capture 都可見，並顯示預期的 GtkBackend placeholder。Windows final capture 可見，但 WebView 區域仍是灰色空框，且 `Navigations reported: 0`。 |
| P39 | 888x649，92.5% 非黑 | 876x659，92.5% 非黑 | WSLg 可見 opacity、blur、saturation、brightness、contrast、grayscale 與 hue-rotation 效果。~~Windows 只有 opacity 明顯；blur 與多數色彩效果看起來與 control 相同，因此 WinUI visual effects 仍可疑。~~ **2026-09-02 起已被取代**（劃掉保留而非刪除，讓過時主張留在紀錄裡）：Windows 現已透過真正的 Win2D effect graph 套用全部七項。2026-09-02 驗證：`applied=8 failed=0 total=8`；重跑指令為 `cd testapp/output && SCUI_DEBUG_VISUAL_EFFECTS=1 ./P39-WinUI.exe`，再讀 `winui-visual-effects-debug.log`。 |
| P40 | 928x736，93.1% 非黑 | 916x708，93.0% 非黑 | 已修正 WSLg geometry no-op / clipping：PIL 現在可量到七個 transformed color components，scale / rotate / shear 的 bounding box 接近 WinUI。exact / near hotpink pixels：兩平台皆為 0。背景色差異來自平台 theme：WSLg 預設為 light；此處 WinUI 為 dark。 |
| P41 | 968x649，92.5% 非黑 | 956x659，92.7% 非黑 | 最新截圖中 Windows `.graphical` DatePicker 已可見，不是 blank sliver。WSLg `.wheel` 明顯不同；Windows `.wheel` 仍像 segmented date input，應記錄為 style parity / fallback observation。 |

### 時序觀察

- WSLg 上這批 release build 在 source sync 後約 12-13 秒完成。
- Windows 上 P27 早前 build 耗時 231.84 秒；後續 P37-P41 build 大多約 38-75 秒。Windows build 即使成功建出 WinUI app，仍會印出 `pkg-config` / `gtk4.pc` 警告。
- 多個 Windows app 在 1 秒截圖時尚未被找到，但 final capture 正常可見。除非 final capture 也失敗，否則先記錄為 startup/window-discovery timing。
- `--actionfile <relative path>` 暴露 Windows loader bug：路徑 containment check 直接拿相對路徑與絕對 `testapp` 路徑比較。WSLg 先用裸 `--actionfile` 避開；`test_common.zsh` 現已加入本地 path converter，因此 Windows 不再依賴 `cygpath`。

## 2026-08-30

### P30-P36 Loader 與 Baseline 覆蓋

- 已新增 P30、P31、P32、P33、P34、P35、P36 的可編譯 baseline apps 與 `test_support/test_Pn.zsh` loaders。
- `testapp/compile.zsh` 現在 Windows 與 WSLg 都預設使用 release build；若需要 debug build，必須明確設定 `BUILD_CONFIG=debug`。
- 測試順序遵守目前規則：先 WSLg，再 Windows。WSLg 端先透過 `testapp/rsync_WSL.zsh` 同步，再於 `/home/lowei/proj/swift-cross-ui` 內編譯。

### 自動 Smoke Test 結果

以下 final screenshot 都以 PIL 量測。每張 final capture 都可見且非黑畫面。

| App | WSLg final screenshot | Windows final screenshot | 備註 |
| --- | --- | --- | --- |
| P30 | 888x649，92.5% 非黑 | 876x659，92.6% 非黑 | WSLg 可見 blur / grayscale 類效果；Windows 可見 opacity 與幾何 transform，但 blur / grayscale 看起來像 no-op，先記錄為 WinUI visual-effect parity 仍待查。 |
| P31 | 808x589，91.8% 非黑 | 796x599，91.9% 非黑 | 兩平台都能渲染 focus / keyboard baseline controls。真正的 Tab 順序、Space/Return 觸發、Escape 與 Ctrl+Q 仍需人工鍵盤測試。 |
| P32 | 788x589，91.7% 非黑 | 776x599，91.8% 非黑 | 兩平台都能渲染 accessibility baseline controls。角色與名稱驗證仍需 Linux 上的 Accerciser，以及 Windows 上的 Accessibility Insights 或 `inspect.exe`。 |
| P33 | 848x649，92.4% 非黑 | 836x659，92.5% 非黑 | 兩平台都能渲染 missing-view 清單與手寫近似 UI。這是可編譯 baseline，不代表缺席的 SwiftUI views 已經存在。 |
| P34 | 808x649，92.2% 非黑 | 796x659，92.4% 非黑 | Smoke run 使用 `--debug -rows 100`。更大的 row count / performance 測試仍需另外執行。 |
| P35 | 788x589，91.7% 非黑 | 776x599，91.8% 非黑 | 兩平台都能渲染 state baseline。Scene composition 缺口仍屬編譯期問題。 |
| P36 | 848x649，92.4% 非黑 | 836x659，92.5% 非黑 | 可用的 SwiftCrossUI API 形狀能正常渲染；SwiftUI-shaped missing calls 以文字列出，避免破壞日常測試 build。 |

### 時序觀察

- WSLg release build 在同步後很快完成：P30 13.66 秒，P31-P36 各約 6-10 秒。
- Windows release rebuild 明顯較慢，尤其是改變 build configuration 後的第一個 target：P30 900.34 秒，P31-P36 之後約 11-29 秒。
- Windows 多個 1 秒截圖只拍到接近空白的 first frame，但 10 秒 final screenshot 都正常。除非 final screenshot 也失敗，先記錄為 WinUI first-paint / window-capture timing。
- WSLg 執行時視窗標題仍回報 `[WARN:COPY MODE]`，雖然 final capture 可見。這些結果可用於 UI layout smoke test，但不適合作為 GPU rendering performance 驗證。

## 2026-08-31

### P16：WinUI NavigationSplitView 初始 layout（#160）

- 已重建並執行 Windows `P16.exe`。final screenshot 可見，尺寸為 916x639，非黑像素 92.5%。
- 初始診斷仍顯示不穩定的首次量測路徑：`sidebar: 0 x 22`、`detail: 0 x 22`，接著 `detail: 734 x 22`。截圖上可見左側 pane 存在，但 sidebar probe 沒有回報穩定的非零寬度。
- 已找到一個 runner bug：`compile.zsh` 接受 `SCUI_DEBUG=1`，但沒有把 `-Xswiftc -DSCUI_DEBUG` 傳給 `swift build`。此點已在工作樹中修正，並把 build-plan hash 納入 `SCUI_DEBUG`，避免切換 debug feature 後重用錯的 SwiftPM plan。
- 目前 actionfile hook 已可觀察：WinUI `show(window:)` 會排程 replay，`ActionFileReplay` 也會把幾何與 replay 結果寫入 `actionfile-replay.log`，避免 WinUI console redirection 讓 runner 誤判為沒有執行。
- 但 P16 的 actionfile replay 尚未讓 UI 出現預期變化：Force update counter、sidebar selection 與 column switch 仍未在 final screenshot 中確認。這表示剩餘問題較可能在 Win32 synthetic input 對 WinUI 控制的命中 / focus / activation，而不是單純沒有載入 actionfile。
- 重新以乾淨 `actionfile-replay.log` 跑 `P16 --windows --no-build --showtime 10` 後，`SendInput` 回報 `ERROR_ACCESS_DENIED`。此輪不能當作 app 行為證據；需在 unlocked desktop、且沒有 elevated foreground window 的情境重跑。
- 修正 WinUI `createSplitView` 初始 `openPaneLength` 後，P16 final screenshot 改為顯示 `sidebar: 180 x 22`、`detail: 660 x 22`，且 `Science` / `Humanities` 不再被壓窄換行。此修正與 GTK 的初始 200px sidebar guess 對齊，避免 core `SplitView.computeLayout` 第一次讀到 0-width sidebar。
- 目前結論：#160 的初始 layout repro 已修正；仍未完成的是 actionfile 對 Force update / sidebar selection / column switch 的自動互動驗證。最新 actionfile report 可回 `replayed`，但畫面上的 counter 沒變，所以此部分仍需人工驗證或更可靠的 WinUI control activation。

### P7：NavigationSplitView pane ratio（#556）

- P7 已依規則先跑 WSLg，再跑 Windows。兩邊 final screenshot 都可見，尺寸皆為 748x509。
- WSLg 診斷：`[SplitView] total=420.0 minLeading=31.0 minTrailing=36.0 -> bounds min=31 max=384 currentSidebar=200`。
- Windows 診斷：`[SplitView] total=420.0 minLeading=31.0 minTrailing=35.0 -> bounds min=31 max=385 currentSidebar=200`。
- 因此本輪兩平台使用相同實際 split ratio：sidebar 200 / total 420，也就是 47.6%。
- 先前類似 87px 的結論是量測錯誤：把 content width 當成 pane width。P7 程式中的註解已指出此點；content probe 可以遠小於承載它的 pane。
- 目前結論：目前 P7 執行中，#556 不再以 pane-ratio mismatch 重現。除非其他 resize/content 情境仍能重現，否則 plan 應由「ratio mismatch」改為「量測防呆 / regression coverage」。

### P30/P39：WinUI visual effects

- 已執行 Windows P30/P39，並補跑 WSLg P39 作為對照。
- Windows P39 的 PIL crop comparison 顯示只有 opacity 會改變像素。control crop 與 blur、saturation、brightness、contrast、grayscale、hueRotation 比對，全部得到 `mean_diff=0.00`；blur text edge 指標也與 control 完全相同。
- WSLg P39 的 PIL crop comparison 則顯示預期的非零差異：saturation 0 與 grayscale 1 的 chroma 為 0，hue rotation 有大幅 mean diff，blur 也有可量測差異。
- ~~程式碼審查也確認截圖結果：`WinUIBackend+VisualEffects.swift` 目前只設定 `widget.opacity`；其他 visual effects 明確記錄為需要尚未實作的 Microsoft.UI.Composition effect graph。~~（2026-09-02 起已被取代——見本節最後一條。）
- ~~目前結論：這不是測試樣本不明顯。WinUI visual effects 除 opacity 外，今日確實是 no-op。~~（2026-09-02 起已被取代——見本節最後一條。）
- 2026-09-01 重跑：WSLg 與 Windows 的 P30/P39 都能啟動、抵達 final screenshot 並正常關閉。最新 P39 PIL comparison 與先前結果一致：Windows `opacity mean_diff=59.73`，但 blur、saturation、brightness、contrast、grayscale、hue rotation 都仍是 `mean_diff=0.00`；WSLg 則每個非 control sample 都有非零差異。
- 2026-09-01 後續：`WinUIBackend+VisualEffects.swift` 現在對未支援效果只會依效果名稱各警告一次，降低一般 update pass 期間的重複 console warning。~~這不改變 rendering 語意：WinUI 目前仍只有 opacity 已實作。~~（2026-09-02 起已被取代——見本節最後一條。）
- 本次變更後最新 P39 final screenshots：WSLg `p39-wslg-final-20260901-071259.png`，Windows `p39-windows-final-20260901-071318.png`。PIL comparison 仍顯示 Windows `opacity mean_diff=69.20`；blur、saturation、brightness、contrast、grayscale、hue rotation 仍是 `mean_diff=0.00`。WSLg 則每個非 control sample 都有非零差異。
- **2026-09-02 起已被取代：WinUI 七項 visual effects 全部已實作。** 上面劃掉的各條刻意保留而非刪除——它們在當時是誠實且量測正確的判讀，而留下「看似合理但為假的查證長什麼樣子」比一張乾淨的頁面更有價值。改變的是程式碼，不是量測方法。`WinUIBackend+VisualEffects.swift` 現已建立真正的 Win2D effect graph（`Win2DEffectGraph`）：blur 用 `GaussianBlurEffect`，saturation 與 brightness 用 `ColorMatrixEffect`，另有 `ContrastEffect`、`GrayscaleEffect`、`HueRotationEffect`；opacity 保留為 `needsOnlyOpacity` 快速路徑，完全跳過 effect graph。用的是 Win2D，而非舊條目所預測的 `Microsoft.UI.Composition` graph，且 `Microsoft.Graphics.Canvas.dll` 隨 `testapp/output/` 一起出貨。2026-09-02 驗證：`applied=8 failed=0 total=8`——此數字的重跑指令為 `cd testapp/output && SCUI_DEBUG_VISUAL_EFFECTS=1 ./P39-WinUI.exe`，再讀 `winui-visual-effects-debug.log`。2026-09-02 亦以 wincap 截圖做像素層級驗證，各 cell 的 mean HSV saturation：saturation 0 → 0.000、saturation 0.5 → 0.515、control（=1）→ 0.818、saturation 2.5 → 0.992——一條單調遞增的階梯，先前那組全為 0 的結果不可能產生它。在 2026-09-02 之前確實有一項是真的壞的：`saturation 2.5` 會以 `0x80070057` `E_INVALIDARG` 失敗，因為 Win2D 的 `SaturationEffect` 無法過飽和；已改用 `ColorMatrixEffect`。
- 2026-09-01 P16 重跑，對象是同一小時重新建置的 binary：**三個點擊全部命中，取代先前那條「狀態變化未被確認」的紀錄。** 判讀方式是對照 `P16.swift` 中的初始值，而非目測：`updateCount` 起始為 `0`，截圖顯示 `Force update (1)`；`selectedArea` 起始為 `nil`，截圖顯示 `Science` 為選取狀態；`columns` 起始為 `.two`，而按鈕顯示 `Switch to 2 column`——那是 `.three` 時的標籤，且三個窗格皆在。先前回報「沒有狀態變化」的那次執行，正是同時回報 `SendInput` 為 `ERROR_ACCESS_DENIED` 的那一次。
- 同一次執行回報 `-actionfile: warning: the window never took the foreground. This file only moves and clicks, so it ran on the topmost pin alone`。這並非失敗：點擊是依座標投遞給該處最上層的視窗，而 `SetWindowPos(HWND_TOPMOST)` 已把我方視窗置於該處，這正是三個點擊都命中的原因。之所以值得知道，是因為任何與焦點相關的行為，都可能與「確實取得前景」的那次執行不同。
- **#160 剩下的症狀在高度，不在寬度。** 最終截圖回報 `sidebar: 180 x 22`、`middle: 180 x 22`、`detail: 460 x 22`。寬度現在是正確的，而它原本是這個 bug 中看得見的那一半；高度 22 不可能正確，因為窗格是填滿視窗的。同一次執行回報的變化過程為 `sidebar 0 -> 180`、`middle 0 -> 180`、`detail 0 -> 460 -> 660`——寬度會安定下來，高度則從未離開 22。
- 2026-09-01，更正上一條：**寬度同樣不可信，因此「剩下的症狀在高度」是錯的。** 那個探針是位於窗格 `VStack` 之內、且套在 `.frame(height: 22)` 之下的 `GeometryReader`，所以高度只可能是 22，而寬度量到的是內容欄、不是窗格。將 reader 移入 `.overlay(alignment: .topLeading)`（`P7SplitProbe` 成功採用的形狀）會弄壞 P16：視窗從未出現，wincap 在第一秒與結束時都找不到可擷取的視窗，動作檔從未重放，窗格回報 `sidebar 200 x 142` 與 `detail 20 x 46`。已還原。`.overlay` 在此的行為與 SwiftUI 不同，而它在本專案本就有前科——它曾吞掉指標事件。
- **因此 #160 目前無法由 P16 的數字定案**，任何方向都不行。上方關於三個點擊的結果仍然成立，因為那是從 app 自身的狀態讀出的，而非來自探針。
- 2026-09-01，為上一條定案：**窗格現在量得到了，而 #160 在 WinUIBackend 上並未重現。** 量測被完全移出 view tree。`SplitView.commit` 原本就有一個 `SCUI_DEBUG_SPLIT` 診斷，會印出各 minimum 與交給 backend 的上下界；現在它也印出每個窗格實際獲得的尺寸。view tree 中不新增任何東西，因此不會擾動被量測的對象——而那正是先前每一次嘗試失敗的原因。
- Run A：`SCUI_DEBUG_SPLIT=1 ./P16-WinUI.exe --debug`，不帶動作檔，8 秒後結束。恰好一次 committed layout：
  `total=880.0 minLeading=126.0 minTrailing=20.0 -> bounds min=126 max=860 currentSidebar=200 leadingPane=200.0x486.0 trailingPane=680.0x486.0`
- Run B：同上再加 `-actionfile actions/win/P16-force-update.csv`，12 秒後結束。共五行。**第 1 至 3 行與 Run A 的那一行逐位元組相同**；Run A 已確立「首次算繪只有一行」，因此第 2、3 行分別是 `Force update` 點擊之後與 `Science` 選取之後的版面。第 4、5 行是三欄狀態，也就是兩層巢狀的 split view：內層 `total=680.0 minLeading=20.0 minTrailing=20.0 -> bounds min=20 max=660 currentSidebar=200 leadingPane=200.0x486.0 trailingPane=480.0x486.0`，外層 `total=880.0 minLeading=113.0 minTrailing=220.0 -> bounds min=113 max=660 currentSidebar=200 leadingPane=200.0x486.0 trailingPane=680.0x486.0`。
- **首次算繪時各窗格獲得的尺寸，與經過兩次狀態改變之後完全相同。** #160 的說法是「分割視圖在第一次算繪時排版嚴重錯誤，之後只要有任何狀態改變就會跳成正確的排版」；此處沒有那次跳正，因為沒有可跳的錯誤起點。
- 這個否定結論之所以可信，在於第 4、5 行確實不同：同一次執行中，該診斷對一次真實的版面變化有反應，因此「第 1 至 3 行不變」是量到的不變，而非一份已經停止輸出的日誌。少了這個對照組，兩者在畫面上完全一樣。
- 順帶也解決了高度的問題：窗格高 **486**，不是 22。那個 22 是探針自己的 `.frame(height: 22)`，卻被當成窗格高度回報了兩週。
- 本結論的適用範圍：這是 SwiftCrossUI 版面系統所決定的結果，不是 WinUI 實際畫出來的東西；繪製端的落差在此看不到。值得特別說明，因為同幾次執行的 1 秒截圖是**全黑**的——WinUI 在一秒時還沒畫，這也是動作檔要先 `sleep 1800000` 才點第一下的原因——所以 harness 的「1s」截圖從來就不是首次算繪的畫面。
- 重現方式：`cd testapp/output && rm -f splitview-debug.log && SCUI_DEBUG_SPLIT=1 ./P16-WinUI.exe --debug`，然後讀 `splitview-debug.log`。需要以 `SCUI_DEBUG=1` 建置的執行檔。
- 更正上面第三條中的一句話——它寫「overlay 在 P7 可行是因為它包的是 `List`」：P7 的 **sidebar** overlay 確實包 `List`，但它的 **detail** overlay 包的是加了 padding 的 `VStack`，與 P16 形狀相同。真正的區別在於：P7 的窗格中沒有 `Spacer`，且它整個 split view 位於 `.frame(width: 420, height: 180)` 之內，其中沒有東西能自由長大；而 P16 每個窗格都以貪婪的 `Spacer` 結尾，該 split view 也沒有固定框架。
- **更正上面所使用的欄位名稱。** 它們最初輸出為 `leadingPane` / `trailingPane`，那是錯的：`leadingResult.size` 是窗格的**子視圖**在收到窗格寬度的提議後所選擇的尺寸，可以小於窗格本身。在 P16 上兩者恰好相同，因此這個錯誤在那裡看不出來；是 P7 揭穿了它——trailing 子視圖對 **420 − 200 = 220** 的提議回答 **207**。已改名為 `leadingContent` / `trailingContent`。窗格寬度則是 `currentSidebar` 以及 `total` 減去它。這正是把內容讀成窗格、曾對 #556 造成兩次錯誤判斷的同一種混淆，所以現在的名稱直接說明它是哪一個。上方引用的數字沒有改變，#160 的比較也依然成立，因為那是同類相比；錯的只有標籤。

### P16 與 P7 在 GtkBackend（WSLg）上的同一診斷

- 2026-09-01。以 `rsync` 同步後在 WSL 副本上建置，並在 WSL 端以 `grep -c lastLeadingPaneSize` 作為對照，確認 Windows 端的修改確實送達（4 處命中）——未同步就在 WSL 建置，會對著舊程式碼回報成功。
- **P16 在 GTK 上的行為與在 WinUI 上不同。** WinUI 對首次算繪只 commit 一次；GTK commit 三次，而且高度會變動：`leadingContent=200x485`、`200x446`、`200x446`，寬度始終為 200 / 680，`minLeading=104 minTrailing=33 bounds 104..847 currentSidebar=200`。連續三次執行輸出逐位元組相同，因此那個 485 是可重現的，不是雜訊。
- 這次安定是自行發生的，在首次算繪之內、任何互動之前，因此它也不是 #160——#160 指的是「一直錯到狀態改變為止」。它是一個 39px 的暫態，稱不上「嚴重錯誤」，而且寬度從未變動。
- **兩者哪一個才對：WinUI 的。GTK 少了 39px，而那 39 就是一條標題列。** P16 要求 `.defaultSize(width: 900, height: 600)`。量測 `p16-gtk-headerbar-20260901-165737.png`：GTK 視窗表面恰為 **900x600**，其**內**有一條 **39px** 的 client-side decoration 標題列，實際內容區為 **900x561**。485 − 446 正好等於 39。GTK 的**第一輪**才是遵守了要求的那一次；它隨後正確地為「實際比要求更小的視窗」重新排版。有問題的不是版面系統，是視窗。
- 成因：`GtkBackend.createWindow` 把要求的尺寸直接交給 `window.defaultSize`（GtkBackend.swift:994-997），也就是 `gtk_window_set_default_size`（Sources/Gtk/Widgets/Window.swift:63），而在 GTK4 中它設定的是**含 CSD 標題列的整個視窗**。在 Windows 上標題列屬於 non-client 區域——同一支 app 量到 916x639 的外框包著 900x600 的 client——所以 WinUI 交付了所要求的尺寸。已另立任務追蹤；寬度不受影響，兩個 backend 都回報 `total=880` = 900 − 2×10 padding。
- SwiftUI 在此的行為**尚未驗證**——需要 Mac，而本機不在範圍內。待查證的預期是：`.defaultSize` 設定的是**內容**尺寸，因為在 macOS 上它對應視窗的 content rect，標題列另計，那會讓 SwiftUI 站在 WinUI 這一邊。此處記為「待量測的事項」，不是結論。
- **P7 在 GTK 上，現在帶有內容尺寸：** `total=420.0 minLeading=31.0 minTrailing=36.0 -> bounds min=31 max=384 currentSidebar=200 leadingContent=200.0x140.0 trailingContent=207.0x77.0`，三行相同。當初為 #556 定案的「sidebar 200 / 420」在版面層級得到確認。
- **收回上一句裡的「值得一併檢視」。** 「207 對 220」與「140 對 77」是在查證之前就被稱為異常的；量測 `p7-gtk-556-20260901-165945.png` 之後，每一個都有解釋，而且沒有一個是缺陷：
  - detail 的文字在畫面上確實斷成兩行，兩行的 ink 寬度為 186 與 140，因此最長那一行是 186；再加上 `VStack` 左右各 10px 的 padding，子視圖寬度就是 206–207。**換行後的 `Text` 回報的是最長那一行的寬度，不是它被提議的寬度**——SwiftUI 也是如此。提議是 220、回答是 207，因為文字在單字邊界斷行。
  - 那個 207 接著被置中於 220 寬的窗格中，正如 `SplitView.commit` 所述它會置中窗格子視圖：(220−207)/2 = 6.5，再加 10 的 padding，文字左緣應在 505.5（分隔線在 x=488）。實測 **505**。第一行「No sidebar selection」的 ink 中心在 598，窗格中心為 599。
  - `leadingContent` 的 140 是五列清單、列距 28px，直接從列本身量得。置中於 180 高的方框中，上方應留 20px，因此第一列應在方框頂端下方 20px 處開始。實測：第一列 ink 在 y=248，方框頂端 228。
  - 兩者高度不同，只是因為兩者的內容不同，而且都沒有填滿窗格。那正是非貪婪內容的行為，而框架是刻意將其置中的。
- 這些數字唯一真正引出的問題與 #556 無關，不該歸入該條目：**`List` 在垂直方向是否應該貪婪？** SwiftUI 的 List 兩個軸向都會填滿容器；這裡它填滿了 200 的寬度，高度卻回答 140 而非 180。尚未對真正的 SwiftUI 建置驗證——那需要 Mac。

### macOS 端回覆之後，三個 backend 的全貌

- macOS 的答案在 `mac-test-results-20260901.md`，同日於 AppKitBackend 上量測。此處僅摘要，因為這次練習的目的就是三方比較；原始輸出與方法在該檔案中。
- **Q1 定案，GTK 是異類。** AppKit 給出 900x628 的外框、28pt 標題列，因此**內容 900x600——恰為所要求的值**，且取自兩個彼此獨立的來源（`CGWindowListCopyWindowInfo` 取外框，以及 InputEvent 重放以 AppKit 自己回報的 frame 對照 client 原點，120 對 148）。這與 WinUI 一致，並證實了本檔案先前標為「未驗證」而非直接斷言的那個預期。GTK 的 900x561 是唯一短少的，現已修正——見 `todo.md`。
- **Q2 把一個觀察拆成了兩個。** AppKit 對 P16 的首次算繪 commit **三次**，與 GTK 相同、與 WinUI 的一次不同——但它的高度全程不動，而 GTK 是 485 → 446 → 446。因此「commit 三次」與「高度收斂」是彼此獨立的兩件事，而其中只有後者曾構成證據。三者的寬度一致，皆為 200 / 680。安定後的高度差異，恰好等於各平台放在內容之上的裝飾：**AppKit 497 / WinUI 486 / GTK 修正前 446**。
- **Q3 是最有價值的答案。** AppKit 的 `List` 在 180 高的窗格中同樣回報 **140**——與 GTK 給出的是同一個數字。兩個各自獨立撰寫的 backend 給出相同答案，就把該行為定位在**共用的版面程式碼**，而非任一 backend，這正是這次量測設計要分辨的事。因此「`List` 在垂直方向不貪婪」是 SwiftCrossUI 本身一個真實的 SwiftUI parity 缺口。
- 值得帶出此任務之外的一點：他們的檔案記載 `AppKitBackend.createWindow` 會呼叫 `setFrameAutosaveName(id)`，而 `id` 衍生自 root view 的型別，因此大多數測試 app **共用同一把 key**（`"NSWindow Frame TupleView1<HotReloadableView>-0"`）。已儲存的 frame 會完全蓋過 `.defaultSize`——同一個 binary、同一個 commit 的 P28，會因該 key 的內容而開成 680x448 或 1076x907。任何先前未清除該 key 就量測視窗尺寸的 macOS 結果，都應存疑。

## 2026-09-02

### P39 與 P40 於 AppKitBackend 與 UIKitBackend：兩個效果系列皆已實作

- 在此日期之前，兩個系列在 AppKit 上都是**降級**——警告一次、以未經修飾的樣貌算繪——而 UIKit 只有
  `GeometricEffects`。相對於它在 2026-09-01 所取代的 `fatalError`，降級確實是真正的改善，但它依然
  是錯的答案：它產出的是「對缺失功能的如實回報」，而那在截圖裡看起來與「功能正常」一模一樣。
- **AppKit `VisualEffects`**：一條套在 layer-backed container 上的 `CIFilter` 鏈。
  `CIColorControls` 一次承載 saturation、brightness 與 contrast；grayscale 另用
  `CIColorMonochrome`，如此它能停在中途，也不會與 `.saturation` 互相打架；hue 是以弧度為單位的
  `CIHueAdjust`。opacity 走 `alphaValue` 而非 filter，因此子樹以一組的方式合成，與 SwiftUI 的
  `.opacity` 相同。已對 P39 量測：**九格全部算繪，且每一種效果都與對照格有可見差異。**
- 有一個陷阱值得記錄，因為它看起來像算繪失敗而不像設定錯誤：無條件設定
  `layerUsesCoreImageFilters` 會讓**每一格**都變空白，連 identity 對照格也不例外。現在只在確實有
  filter 要跑時才設定。
- **iOS 的 `VisualEffects` 不是同一份實作，而逼出這項差異的量測至今仍然為真。**
  `CALayer.filters` 在 iOS 上不參與合成。該屬性在兩個平台的標頭中都存在，但只有 AppKit 的合成器
  會讀取它。這是在 iPhone 16 模擬器上量出來的，量了兩次，不是查來的：`opacity 0.35` 明顯變淡，
  而 `blur 3`、`saturation 2.5`、`brightness 0.4`、`grayscale 1` 與 `hueRotation 120` 與對照格
  **逐像素相同**。七項中只有一項有效。
- 錯的是由該量測推出的結論——*因此七項中有六項在 iOS 上無路可走*——而不是量測本身。iOS 確實提供的
  路徑，是去過濾子樹的**算繪結果**而非活的 layer：`CALayer.render(in:)` 畫進點陣圖、`CIFilter` 鏈
  在點陣圖上執行、結果成為覆蓋在子元件之上的 layer 的內容，而子元件以一個**空的 `CALayer` mask**
  隱藏，而非以 `alpha` 或 `isHidden`——`UIView.hitTest` 會跳過 alpha 小於等於 0.01 的 view，而那
  兩個屬性都存在 layer 上，沒有辦法只為繪製而設定它們。子元件因此仍可被 hit test。
- 於 P39、iPhone 16 模擬器、iOS 18.4 量測：**九格現在全部與對照格不同。** 擷取影像為
  `p39-ios-final-20260902-143209.png` 與 `p39-ios-final-20260902-144424.png`。
- 代價是明說而非隱藏的：看得見的像素是每次排版重新產生的算繪結果——而那是 view graph 每次寫入
  尺寸或位置時都會發生的事，因此被過濾的容器內部若有狀態變更，確實會反映到畫面上——但若其中有一個
  由 Core Animation 而非 view graph 驅動的動畫，它會凍結在最後一次排版所捕捉到的那一格。`opacity`
  不走這條路，維持即時。
- **「這個平台沒有對應的 API」在此處通過了一次真實的量測，卻依然是錯的。** 那才是能留下來的結論；
  `bugs/bug-UIkit.md` 保存了它。
- **兩者的 `GeometricEffects`。** AppKit 的是一個 `CATransform3D`，需要兩次轉換：transform 傳入時
  位於左上原點、y 向下的空間，而非 flipped 的 `NSView` 底下的 `CALayer` 是左下原點、y 向上，且
  CoreAnimation 是繞 `anchorPoint` 而非繞原點套用 transform。UIKit 少一次轉換，因為它的 layer
  本來就是左上、y 向下，但同樣需要錨點修正。
- 於 Mac 上對 P40 量測：offset 向右下移動、rotation 為順時針，且 **`rotate 30 centre` 與
  `rotate 30 topLeading` 不同**——這正是錨點運算正確與否的檢查點，因為錯誤的錨點運算會使兩者相同，
  或把 tile 丟到畫面外。於 iPhone 16 模擬器上對 P40 量測：**七格全部正確算繪。** 擷取影像為
  `p40-ios-final-20260902-143258.png` 與 `p40-ios-final-20260902-143444.png`。
- 兩邊的容器都把子元件的四個邊都釘住，而這花了兩次錯誤猜測才找到。完全不加 constraint 時每一格
  都是空白；只加左邊與上邊仍是空白；探針讀到 `container=(0,0,200,109)` 對上
  `child=(0,109,0,0)`，且子元件沒有任何 constraint。modifier 的 commit 只設定容器的尺寸，沒有
  任何東西為容器內部的元件設定尺寸——這在 GTK 上看不見，因為那裡是容器決定子元件的尺寸。
- 此處未量測、且僅列出而不猜測的是：**Android**。`matrix_coverage/results.csv2` 中沒有任何
  AndroidBackend 上的 P39 或 P40 執行紀錄，因此其欄位維持 `-`。

### P43 的漸層填充於 macOS 與 iOS

- `BackendFeatures.Paths.renderPath(…fillStyle:)` 是「以漸層填充或描邊一個形狀」，而不是把它壓成
  中點顏色。單位座標乘上的是**路徑**自身的範圍而非 widget 的，這正是漸層能被裁進圓形、而不是填滿
  漸層視圖自己那個矩形的原因。
- 協定的預設實作會壓平並每個 backend 警告一次。那個預設是在一台沒有 Mac 的機器上寫的，而它自己
  也說明了這一點；盲寫 AppKit 與 UIKit 會讓下一個 pull 的人拿到建置失敗。這兩份實作是**在 Mac 上
  寫成並量測的**。
- 兩者都在 `draw(_:)` 中以 `CGGradient` 繪製——它接受兩個半徑。平面色的情況維持原有的低成本路徑
  不變。`CAShapeLayer` 無法繪製漸層，也沒有對應屬性；而常見的「以形狀遮蔽 `CAGradientLayer`」變通
  做法根本表達不了這項功能：它的 `.radial` 型別是一個從某點到另一點的橢圓，沒有起始半徑，因此
  `radialGradient(startRadius:endRadius:)` 無從表述。
- **兩個檔案恰好差一個正負號，而那是被逼出來的，不是選出來的。** AppKit 的路徑抵達時已被翻轉——
  `applyActions` 最後會做 `scaleByX: 1, byY: -1`，而 `NSBezierPathView` 並非 flipped——因此
  `UnitPoint.top` 在那裡是方框中**最大**的 y，在 UIKit 中則是**最小**的。P43 的漸層是紅到藍、
  由上往下，那正是讓這個正負號看得出來的原因：紅色在兩個平台上都必須在上方。對稱的漸層會把它藏
  起來。
- AppKit 另外還需要一次 `NSBezierPath` 到 `CGPath` 的轉換，因為「裁切到描邊區域」得用
  `CGContext.replacePathWithStrokedPath`，而 `NSBezierPath.cgPath` 需要 macOS 14，本套件卻部署到
  macOS 11。
- 於兩個平台以 P43 量測，四格全部成立：**漸層圓形是圓的而不是方的、平面色對照組未變、矩形由紅
  跑到藍，而描邊圓形是一個中間空心的環**——最後一項正是 P43 自己指出「沒有任何 backend 在測」的
  情況，連 GtkBackend 也不例外。擷取影像為 `p43-macos-gradient-fills.png` 與
  `p43-ios-gradient-fills.png`。
- **AndroidBackend 仍取用壓平的預設實作**，因此記為已知缺口而非未測試：它會畫出一個看似合理的
  平面形狀，並記錄一次警告。要關閉它需要一台能建置並執行 Android 的機器。

### iPhone 上的 NavigationSplitView

- 在緊湊寬度的 iPhone 上，`UISplitViewController` 無論 `preferredDisplayMode` 為何都會收合成一個
  navigation stack；沒有任何設定能把 sidebar 放在 detail 窗格旁邊。因此 `PhoneSplitWidget` 並非
  它的包裝——它就是把兩個窗格並排放置，而那正是 `NavigationSplitView` 的語意，也是其他每一個
  backend 所產生的結果。
- 寬度是**推導出來的，不是存起來的**：`sidebarWidth` 必須能在 `computeLayout` 期間、任何 layout
  pass 執行之前就回答，因此它由 `setSize(of:)` 剛寫入的 `width` 推導，而那與 `layoutSubviews`
  稍後所用的是同一個數字。
