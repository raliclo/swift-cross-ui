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
- #556 (Open)：Windows 與 WSLg/GTK 截圖中都能看到 `NavigationSplitView` 區域，但兩個 backend 的 pane aspect / split ratio 不一致。這符合 GTK NavigationSplitView 尺寸判斷異常的回報，因此即使 detail pane 沒有塌陷，#556 仍維持 open。
- #556：點選 plain List 的 `Cherry` 後，NavigationSplitView 的 detail pane 仍顯示 `No sidebar selection`。以目前 P7 測試內容來看，plain List selection 與 NavigationSplitView sidebar selection 是分開的，這應屬預期；但閱讀對照截圖時需要注意這點。
- #556：Step 7 功能上穩定。按 `Add a fruit's worth of text` 後，上方較長文字出現，split view 沒有跳動或塌陷，但 Windows 與 WSLg/GTK 的 pane ratio 仍不一致。
- #556：Step 8 功能上穩定。調整視窗大小後，包含大幅加寬視窗的情境，Windows 與 WSLg/GTK 的 detail pane 都保持可見。不過 WSLg/GTK 的 split-view aspect / pane ratio 仍明顯不同於 Windows，因此仍屬 #556。
- #556 / Windows Light mode：Windows Light mode 下，右側第三 pane 沒有顯示預期的垂直分隔線（`|`）；相較之下，WSLg/GTK 對照截圖中可看到 pane boundary。先記錄為 split-view detail pane 的 Windows/GTK 視覺一致性問題。
- WSL/Windows GUI comparison：同一個 P7 測試情境下，Windows `P7.exe` 與 WSLg/GTK `P7` 的視窗尺寸理論上應該一致，但截圖對照顯示兩者有明顯尺寸差異。這需要進一步調查，否則不能直接把跨 backend 的 layout screenshot 視為等比例比較；後續需確認差異來自 requested content size、backend window-sizing semantics、DPI scaling、window decorations，或 WSLg compositor 行為。**（已於 2026-08-18 以 P6 解答：成因為 DPI scaling，詳見該日紀錄。）**

### P8：Scroll Views

- #426 (Confirmed/Open, WSLg/GtkBackend only)：已確認此問題只在 WSLg / GtkBackend 發生；Windows / WinUIBackend 對照未重現。WSLg 上水平與垂直 scroll 都完全不移動，包含游標位於內層水平長條上並嘗試水平或垂直滾動的情境；外層垂直 scroll view 沒有如預期接收/接手滾輪事件。
- #426：後續修正應優先在 WSLg / GtkBackend 上重現與驗證，再用 Windows / WinUIBackend 作為 non-regression 對照。可使用 `zsh testapp/test_p8.zsh --both`；腳本會先跑 WSLg、render 後保留 30 秒並拍 final screenshot，再跑 Windows。
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
- 驗證：`Gtk`、`GtkBackend`、`DefaultBackend`、`GtkExample` 四個 target 皆建置成功；所有編輯過的檔案通過 `swiftc -parse`。整包 `swift build` 與 `Examples` 在 Linux 上仍會停在 `WinUIInterop`／`swift-winui` 缺 `Windows.h`、`wtypesbase.h`——那是既有的平台限制，與本次移除無關。

### WSLg 幽靈視窗

- `gtk4-widget-factory` 行程結束後，Windows 端的 `msrdc.exe` 仍持續顯示 `GTK Widget Factory (Ubuntu)` 視窗。WSL 內 `pgrep` 確認無任何對應行程。
- 這是繼 PulseAudio 停止監聽、COPY MODE 之後，**WSLg 橋接第三種靜默失效**：視窗已無擁有者卻不被移除。判讀 WSL GUI 測試結果時，「Windows 上看得到視窗」不足以證明該 app 仍在執行。
