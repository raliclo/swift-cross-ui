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
- 音訊（部分修正，WSL 端仍無聲）：P6 在 WSLg 上沒有聲音。成因有兩層，只修好第一層。第一層是 ffplay 透過 SDL 播放，而 SDL 會優先嘗試 ALSA；WSL 沒有音效卡，因此每次都失敗——實測四次執行皆出現 32 行錯誤，開頭為 `ALSA lib confmisc.c:855:(parse_card) cannot find card '0'`，改為 `SDL_AUDIODRIVER=pulse` 後四次皆為 0 錯誤。P6 已改為在 `PULSE_SERVER` 存在時為 ffplay 子行程設定該變數（只有 ALSA 的實體 Linux 機器不受影響）。第二層尚未解決：WSLg 的 PulseAudio server 已停止監聽，`pactl --server=unix:/mnt/wslg/PulseServer info` 回報 `Connection refused`，但 socket 檔案仍在原處（時戳為 WSL 開機時的 14:27），因此一切看起來設定正確卻毫無聲音。WSLg 自身的 `/mnt/wslg/pulseaudio.log` 顯示它確實啟動過（`RDP Sink - Connected to fd 12`）。Windows 端音訊裝置全部正常（Realtek(R) Audio `oem10.inf`、NVIDIA HD Audio、AMD HD Audio、NVIDIA Virtual Audio Device，狀態皆為 Started），所以問題不在 Windows。後續動作：由使用者執行 `wsl --shutdown` 後重開 WSL 以重啟 WSLg 的 pulseaudio，再以 `pactl info` 確認。
- 判別要點：若沒有 `pactl`，此問題無法與「client 端設定錯誤」區分——socket 存在、`PULSE_SERVER` 指向正確、ffplay 也不報錯，看起來完全正常。`pactl info` 是唯一能分辨兩者的檢查，因此 `pulseaudio-utils` 已列入 `install_tool_wsl.sh`。
- GTK 檔案選擇器（Open，未修正）：在 WSLg 上，`Choose file` 選好檔案後對話框不會關閉。程式位置為 `Sources/GtkBackend/GtkBackend.swift` 的 `showFileChooserDialog`：它呼叫 `gtk_native_dialog_show()`，但 response handler 只處理結果，沒有任何 hide 或 destroy。`Sources/Gtk3Backend/Gtk3Backend.swift` 的同一段結構相同。尚未實地驗證修法。
- WSL/Windows GUI comparison（2026-08-16 該項的解答）：兩端的尺寸差異來自 **DPI scaling**，而非 requested content size、backend window-sizing semantics、window decorations 或 WSLg compositor 行為。在同一台 1920x1080 螢幕、兩端皆 `-maximized` 的條件下量到：Windows 影片區為 1200x675 px，WSLg/GTK 為 960x540 px。Windows 日誌本身即記錄 `viewport 960.0x540.0 dip (1200x675 px), panel actual 960.0x540.0 dip, rasterization scale 1.25`，並有 `window metrics: dpi 120`。亦即 WinUIBackend 套用了 1.25 的 rasterization scale，GtkBackend 則以 1:1 呈現。因此跨 backend 的 layout 截圖在換算 DPI 之前，不可直接視為等比例比較。
