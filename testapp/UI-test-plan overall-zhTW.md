# UI 測試計畫：P0-P17

本文件整理 `testapp` 測試程式的手動與輔助 UI 測試步驟。測試目標是快速重現與確認 WinUIBackend、GtkBackend、AppKitBackend、UIKitBackend 與 AndroidBackend 的 backend-specific issues。

## 測試前準備

1. 進入專案根目錄：

   ```zsh
   cd /c/Users/lowei/proj/swift-cross-ui
   ```

2. 編譯測試程式：

   ```zsh
   zsh testapp/compile.zsh
   ```

3. 進入輸出目錄：

   ```zsh
   cd testapp/output
   ```

4. 確認 runtime resource 存在：

   ```zsh
   test -f swift-winui_CWinAppSDK.resources/Microsoft.WindowsAppRuntime.Bootstrap.dll && echo ok
   ```

   預期結果：輸出 `ok`。

## 跨平台測試流程

- Linux / GtkBackend 相關 issues 一律先測 WSLg，再用 Windows 作為對照（若該 app 支援）。
- 不要在 WSL 內從 `/mnt/c` 編譯。先同步 `testapp` 的 Swift/zsh 檔案，再於 `~/proj/swift-cross-ui` 下建置。
- 只使用 zsh scripts。目前 helper scripts 包含 `compile.zsh`、`rsync_WSL.zsh`、`screenshot.zsh`、`videoshot.zsh`、`test_p7.zsh` 與 `test_p8.zsh`。
- P8 的自動 dry-run 預設會在每個平台 render 後保留視窗 30 秒，再拍 final screenshot，方便 tester 共同觀察並回報變化。
- 截圖會寫到 `testapp/output/screenshots`，檔名含平台與階段，例如 `p8-wslg-1s-...png`、`p8-wslg-final-...png`、`p8-windows-1s-...png`、`p8-windows-final-...png`。

## 共通觀察項目

- App 是否能開啟主視窗。
- Console 是否出現 fatal error 或 stack trace。
- 視窗是否可互動，按鈕、輸入框、選單是否回應。
- 關閉 app 後 process 是否正常結束。
- 若發生 crash，記錄：
  - 執行哪個 exe
  - 按下哪個控制項
  - crash 前最後一行 log
  - stack trace 中的 Swift / WinUIBackend 檔案與行號

## P0：Critical Lifecycle

執行：

```powershell
.\P0.exe
```

涵蓋 issues：

- #493 (Fixed)：WinUIBackend 太早呼叫 environment action 可能 crash
- #548 (Fixed)：`@AppStorage` 在 Windows crash
- 無專屬 issue (Fixed)：WinUIBackend `setSizeLimits` unimplemented log
- 無專屬 issue (Fixed)：WinUIBackend `setIncomingURLHandler` unimplemented log

測試步驟：

1. 啟動 `P0.exe`。
2. 確認主視窗 `P0 WinUI critical checks` 出現。
3. 檢查 console 不應出現下列未實作 log：
   - `setSizeLimits(ofWindow:minimum:maximum:) unimplemented`
   - `setIncomingURLHandler(to:) not implemented`
4. 按 `Increment @AppStorage` 多次，確認 #548 (Fixed)。
5. 按 `Reset`，確認 #548 (Fixed)。
6. 關閉 app，重新開啟，確認 launch count 仍能正常更新，確認 #548 (Fixed)。
7. 按 `Show AlertScene`，確認 alert 出現且 OK 可關閉，確認 #493 (Fixed)。
8. 按 `Present environment alert after 1 second`，確認 1 秒後 alert 出現，確認 #493 (Fixed)。
9. 按 `Present environment alert now`，確認 alert 出現，確認 #493 (Fixed)。

預期結果：

- App 不應在啟動時 crash。
- `@AppStorage` 按鈕不應造成 crash，若 crash 表示 #548 (Fixed) 發生 regression。
- AlertScene 與 environment alert 可以正常顯示。
- 若 alert crash 且錯誤包含 `XamlRoot`，表示 #493 (Fixed) 發生 regression。

## P1：Dialogs And Sheets

執行：

```powershell
.\P1.exe
```

涵蓋 issues：

- #523 (Fixed)：Windows file open/save dialog 顯示過慢
- #659 (Fixed)：Nested sheets not supported
- #660 (Fixed)：Sheets have default padding

測試步驟：

1. 啟動 `P1.exe`。
2. 按 `Open file dialog`。
3. 選擇任一檔案或取消，記錄 dialog 出現與返回時間，確認 #523 (Fixed)。
4. 按 `Open folder dialog`。
5. 選擇任一資料夾或取消，記錄 dialog 出現與返回時間，確認 #523 (Fixed)。
6. 按 `Save file dialog`。
7. 選擇儲存位置或取消，記錄 dialog 出現與返回時間，確認 #523 (Fixed)。
8. 按 `Open root sheet`。
9. 觀察 root sheet 內容周圍 padding，確認 #660 (Fixed)。
10. 按 `Open nested sheet`。
11. 確認 nested sheet 是否可正常出現與關閉，確認 #659 (Fixed)。

預期結果：

- File/folder/save dialogs 應能開啟，不應 crash。
- Dialog 顯示時間不應明顯超過 2 秒，若仍明顯超過 2 秒，記錄為 #523 (Fixed) regression。
- Nested sheet 若無法顯示或 crash，記錄為 #659 (Fixed) regression。
- Root sheet 紅色 bar 若仍被明顯 padding 包住，記錄為 #660 (Fixed) regression。

## P2：Controls And Styling

執行：

```powershell
.\P2.exe
```

涵蓋 issues：

- #449 (Fixed)：Picker options 更新不正確
- #471 (Fixed)：TextEditor unfocused thin border
- #401 (Fixed)：Window resizing disabled 時 full screen button 未停用
- #390 (Fixed)：Disabled buttons 視覺不明顯

測試步驟：

1. 啟動 `P2.exe`。
2. 開啟 Picker，確認初始 options 只有 `Vanilla`、`Chocolate`，確認 #449 (Fixed)。
3. 勾選 `Use expanded Picker options`，確認 #449 (Fixed)。
4. 再開 Picker，確認 options 增加 `Strawberry`、`Mint`、`Coffee` 且可切換選項，確認 #449 (Fixed)。
5. 點 TextEditor，輸入 `12345`，確認不漏字，確認 #471 (Fixed)。
6. 點其他控制項讓 TextEditor 失焦，確認失焦時無細邊框，確認 #471 (Fixed)。
7. 觀察 disabled button 與 enabled button 是否有明顯視覺差異，確認 #390 (Fixed)。
8. 切換 `Enable button row`，確認 disabled 狀態視覺更新，確認 #390 (Fixed)。
9. 切換 `Allow window resizing`，確認 #401 (Fixed)。
10. 觀察視窗 resize / full screen button 行為，確認 #401 (Fixed)。

預期結果：

- Picker options 應隨 state 更新，dropdown 不應立即消失，若失敗則記錄為 #449 (Fixed) regression。
- 點開 Picker 時不應出現 `BVI-*`、`rcBackdropLocal`、`CachedNewBlur` 等 WinUI/Composition rendering diagnostic log；若出現，記錄為 #204 (Fixed) regression。
- TextEditor 輸入不應漏字，失焦時應符合預期無邊框，若失敗則記錄為 #471 (Fixed) regression。
- Disabled controls 應明顯看起來 disabled，若不明顯則記錄為 #390 (Fixed) regression。
- Window resizing disabled 時，使用者不應能正常 resize 或 full screen，若仍可操作則記錄為 #401 (Fixed) regression。

## P3：Layout And Clipping

執行：

```powershell
.\P3.exe
```

涵蓋 issues：

- #389 (Fixed)：Images are not clipped
- P3 三欄測試板初始 layout regression (Fixed)

測試步驟：

1. 啟動 `P3.exe`。
2. 不調整視窗，先觀察 sidebar、middle、detail 三欄是否都完整可見。
3. 確認 image detail 欄沒有蓋住 sidebar 或 middle column。
4. 按 `Force state update`，確認三欄位置不應突然修正或跳動。
5. 拖曳調整視窗大小，再觀察三欄是否仍合理。
6. 在 image size 控制中依序按 `Small`、`Medium`、`Large`。
7. 觀察黑色背景中的測試 image，確認 #389 (Fixed)。
8. 確認 Large image 是否被 220x140 frame 裁切，確認 #389 (Fixed)。
9. 切回 Small / Medium，確認 image 更新正常且仍在 frame 內，確認 #389 (Fixed)。

預期結果：

- 初始三欄 layout 應該正確，不應等 state update / resize 才修正。
- Oversized image 不應溢出黑色 frame。
- 若圖片超出 frame，記錄為 #389 (Fixed) regression。
- 若初始 layout 錯誤但 resize 後恢復，記錄為 P3 三欄 layout (Fixed) regression。

## P4：WinUI Native And Callback Stress

執行：

```powershell
.\P4.exe
```

涵蓋 issues：

- #190 (Fixed)：Callbacks stored in backend-wide hashmaps
- #156 (Fixed)：WinUI-specific escape hatch / native API
- #204 (Fixed)：Update to latest stable WinUI / WinUI console noise
- #470 (Fixed)：Regenerate WinUI bindings with latest swift-winrt

測試步驟：

1. 啟動 `P4.exe`。
2. 確認 native WinUI banner 顯示，確認 #156 (Fixed)。
3. 在 `Native inspection text` 輸入文字，確認 #156 (Fixed)。
4. 確認 native banner 內容可跟著更新，確認 #156 (Fixed)。
5. 按 `Force update` 多次，確認 #190 (Fixed)。
6. 按多個 `Run N` callback buttons，確認 #190 (Fixed)。
7. 確認 `callbacks` 計數增加，`Selected row` 更新，確認 #190 (Fixed)。
8. 按 `More rows` 多次增加 rows，確認 #190 (Fixed)。
9. 將列表捲到接近底部，確認 row 視窗自動前移（顯示範圍前進）且捲動位置視覺上保持連續。
10. 按 `Rows 250`，再按 `Run last`，確認顯示最後一段 row 視窗且 UI 不應長時間卡住。
11. 按 `Run 249`，確認 `callbacks` 與 `Selected row` 快速更新為 249，確認 #190 (Fixed)。
12. 按 `Fewer rows` 多次減少 rows，確認 #190 (Fixed)。
13. 再按現有 row button，確認 #190 (Fixed)。
14. 點開 Picker 或觸發 WinUI backdrop 更新，確認 console 不再出現 `BVI-*`、`rcBackdropLocal` 或裸矩陣/尺寸 noise，確認 #204 (Fixed)。

預期結果：

- callback 不應錯亂、遺失或 crash。
- 捲動接近底部/頂部時 row 視窗應前移/後移，且同時渲染的 row 數量上限維持約 50（僅 Windows；其他平台用 `Load next rows`）。
- row count 增減後，新舊 buttons 都應能觸發正確 row。
- WinUI native inspection 應能改變 underlying control 的樣式。
- `Force update` 與修改 `Native inspection text` 應更新 native banner。
- row count 很大時，visible row callbacks 仍應快速更新。
- 若大量 update 後 callback 指向錯誤 row，記錄為 #190 (Fixed) regression。
- 若 console 再次出現 WinUI backdrop diagnostic noise，記錄為 #204 (Fixed) regression。

## P5：Multi-Window Alerts

執行：

```powershell
.\P5.exe
```

涵蓋 issues：

- #675 (Fixed)：WinUIBackend 先前全 app 只能同時顯示一個 dialog（跨視窗會排隊，同視窗無法疊加）

測試步驟：

1. 啟動 `P5.exe`。
2. 確認主視窗 `P5: Main window` 出現。
3. 按 `Open another window` 開啟第二個視窗，確認 `P5: Secondary window` 出現。
4. 在主視窗按 `Show Alert A`，確認 `Alert A (Main)` 出現。
5. 在 `Alert A (Main)` 仍開啟時切到第二個視窗按 `Show Alert A`，確認 `Alert A (Secondary)` 立即出現，不需等主視窗的 alert 關閉，確認 #675 (Fixed)。
6. 關閉兩個 alert。
7. 在主視窗按 `Show Alert A`，接著在不關閉 Alert A 的情況下按 `Show Alert B (stacks on A)`，確認畫面上 `Alert B (Main)` 取代 `Alert A (Main)`，確認 #675 (Fixed)。
8. 不關閉 Alert B，按 `Show Alert C (stacks on A+B)`，確認 `Alert C (Main)` 疊加在最上層，確認 #675 (Fixed)。
9. 關閉 `Alert C (Main)`，確認 `Alert B (Main)` 重新出現，確認 #675 (Fixed)。
10. 關閉 `Alert B (Main)`，確認 `Alert A (Main)` 重新出現，確認 #675 (Fixed)。
11. 關閉 `Alert A (Main)`，確認畫面上已無 alert 且視窗可正常互動。
12. 在第二個視窗重複步驟 7-11，確認非主視窗也有相同的疊加/還原行為。
13. 從任一視窗再按一次 `Open another window`，確認第三個視窗開啟，且三個視窗可同時各自獨立顯示/疊加 alert。

預期結果：

- 不同視窗的 alert 應能同時顯示；若第二個視窗的 alert 要等第一個視窗的 alert 關閉才出現，記錄為 #675 (Fixed) regression。
- 同一視窗在既有 alert 仍開啟時疊加顯示 Alert B（或 C），應隱藏舊 alert 並顯示新 alert；若同一視窗同時顯示兩個 alert，或 app crash，記錄為 #675 (Fixed) regression。
- 關閉疊加的 alert 應依正確順序（C → B → A）還原下層 alert；若還原的 alert 被跳過或順序錯誤，記錄為 #675 (Fixed) regression。
- 關閉某一個視窗不應影響其他視窗的 alert。

## P7：Lists And Split Views（Linux）

執行：

```sh
./P7
```

輔助 WSLg/Windows 對照流程：

```zsh
zsh testapp/test_p7.zsh --both
```

涵蓋 issues：

- #476 (Fixed)：GTK backend 上 List 一啟動就已選取第一項
- #556 (Open)：Gtk List 的 NavigationSplitView 尺寸判斷異常

測試步驟：

1. 啟動 `P7`。
2. **先不要點任何東西**，觀察左側 List 與狀態列。selection 綁定初始為 nil，因此不應有任何列被選取，狀態列應顯示 `Selection: none`，確認 #476。
3. 點選 List 中的 `Cherry`，確認狀態列更新且只有該列被選取。
4. 按 `Clear selection`，確認兩個 List 都沒有選取項目。
5. 按 `Select Cherry`，確認由程式設定選取時 List 會標示出來。
6. 觀察 NavigationSplitView：sidebar 與 detail 兩側應各自佔據 420 px 中合理的比例，確認 #556。
7. 按 `Add a fruit's worth of text` 讓上方文字變長，確認 split view 的分割比例不會突然改變。
8. 調整視窗大小，確認分割仍維持合理比例。

預期結果：

- 啟動時沒有任何選取項目；若第一列已被標示，即為 #476 regression。已在 WSLg 下以 GTK4 與 GTK3 確認修正。
- detail 區可見且不會塌成零寬，且不因無關文字變動而改變分割；任一項不符即為 #556。

## P8：Scroll Views（Linux）

執行：

```sh
./P8
```

輔助 WSLg-first 流程：

```zsh
zsh testapp/test_p8.zsh --both
zsh testapp/test_p8.zsh --both --showtime 60
zsh testapp/test_p8.zsh --both --no-showtime
```

輔助流程會等待 P8 的 `RENDER COMPLETE` marker，預設讓 WSLg 視窗保留 30 秒，
拍下 final screenshot 後，再用同樣流程測 Windows。當 tester 需要即時觀察視窗、
共同回報可見問題時，使用這個流程。

涵蓋 issues：

- #417 (Open)：ScrollView 的 cornerRadius 不影響其子元件
- #426 (Open)：水平 ScrollView 吞掉了外層垂直 ScrollView 的滾輪輸入

測試步驟：

1. 啟動 `P8`。
2. 觀察第一個 ScrollView 中紅色區塊的四個角。該框有 `cornerRadius(20)`，紅色應在四角被切成圓角，確認 #417。
3. 將游標移到第二個 ScrollView、避開水平長條，滾動滾輪，確認外層列會移動。
4. 將游標移到**水平長條上**再垂直滾動，確認外層仍會捲動，確認 #426。
5. 在長條上水平滾動，確認長條本身會移動。
6. 將長條捲到最右端後繼續滾動，確認改由外層接手，而不是整個停住。

預期結果：

- 紅色不應觸及方角；若觸及即為 #417。
- 游標在任何位置（含水平長條上）都能垂直捲動；若在長條上外層凍結即為 #426。

## P9：Text And Field Sizing（Linux）

執行：

```sh
./P9
```

涵蓋 issues：

- #504 (Open)：GtkBackend 的 TextField/SecureField 在第一次更新後高度縮水
- #295 (Open)：Text 未在必要時裁切至零寬

測試步驟：

1. 啟動 `P9`。記下文字欄位、密碼欄位與旁邊 `Reference` 按鈕的高度；啟動時三者應一致。
2. 按一次 `Force update`。該按鈕只會增加計數，不會碰到欄位。
3. 再次比對欄位與 `Reference` 按鈕的高度，確認 #504。
4. 多按幾次 `Force update`，確認高度不會持續縮水。
5. 在兩個欄位輸入文字，確認文字仍完整可見。
6. 下半部連續按 `Narrower`。藍色色帶標示該標籤被賦予的框，文字必須留在框內，確認 #295。
7. 按 `Zero width`，確認標籤縮到零寬而非拒絕縮小。
8. 按 `Wider`，確認框變大後文字重新出現。

預期結果：

- 無關的更新不應改變欄位高度；任何縮水即為 #504。
- 文字不得超出藍色色帶，且被要求時應能縮到零寬；溢出即為 #295。

## P10：Hit Testing And Shortcuts（Linux）

執行：

```sh
./P10
```

涵蓋 issues：

- #454 (Open)：透明容器會吃掉點擊事件（AppKitBackend、GtkBackend）
- #478 (Open)：GtkBackend 下 Ctrl-Q/Cmd-Q 無法結束程式

測試步驟：

1. 啟動 `P10`。
2. 連按 `Click me` 數次，確認 `Direct clicks` 會增加。
3. 在 `Transparent overlay present` 勾選的狀態下，點擊位於透明 `Color.clear` 圖層下方的 `Click me too`，確認 `Covered clicks` 會增加，確認 #454。
4. 取消勾選 `Transparent overlay present` 後再點一次，確認此時會增加。
5. 兩者對照：若被覆蓋的按鈕只有在移除透明圖層後才有反應，即為 #454。
6. 按 Ctrl-Q（macOS 為 Cmd-Q），確認 #478。

預期結果：

- 透明圖層不應阻擋點擊；若被覆蓋的按鈕需移除圖層才有反應，即為 #454。
- Ctrl-Q 應結束程式；若視窗仍開著即為 #478。

## P11：AppKit Sliders, Scrollbars And Pickers（macOS）

執行：

```sh
./P11
```

涵蓋 issues：

- #82 (Open)：AppKitBackend 中兩個互相限制的 sliders 會 jitter
- #485 (Open)：AppKitBackend scrollbar 方向顯示錯誤
- #473 (Open)：Liquid Glass 下 compact DatePicker 尺寸錯誤
- #404 (Open，僅記錄)：View > Show Tab Bar 會影響 window content size
- #425 (Open，僅記錄)：window 啟動時 focus 狀態不穩定

測試步驟：

1. 啟動 `P11`。
2. 將 minimum slider 拖過 maximum slider，觀察兩邊 write counters 是否在數值幾乎不動時仍一起增加，確認 #82。
3. 按 `Separate them` 後正常拖曳，再按 `Collide them` 後重測，比對穩定路徑與受限制路徑。
4. 觀察 scroll section 的垂直 scrollbar，確認 thumb 方向與移動方向正確，確認 #485。
5. 比對 compact DatePicker 與旁邊 reference button 的高度，確認 #473。
6. #404 需手動使用 app menu：View > Show Tab Bar，記錄 content size 是否異常改變。
7. #425 需多次重新啟動，記錄 window 是否有啟動時未 focus 的情況。

預期結果：

- Slider writes 應跟隨正在拖曳的 slider，不應進入明顯 feedback loop。
- Scrollbar thumb 方向與移動方向應符合預期。
- Compact DatePicker 應與鄰近控制項視覺對齊。
- #404 與 #425 僅列為手動觀察，不作為嚴格 pass/fail。

## P12：Android Margins, Rotation State And Toggles（Android）

在 Android backend 建置並部署到 Android device/emulator 後執行。Host build 仍可用來快速檢查 layout。

涵蓋 issues：

- #632 (Open)：AndroidBackend buttons 有不必要 margin
- #580 (Open)：旋轉螢幕會重置 `@State`
- #544 (Open)：button-style Toggle 沒有明顯表示 on/off 狀態
- #610 (Open，僅記錄)：sheet sizing 需要更深入量測

測試步驟：

1. 在 Android device 或 emulator 啟動 `P12`。
2. 切換 tab 並增加 counter，接著旋轉裝置，確認 #580。
3. 比對 button 背景與綠色 reference bands；任何可見縫隙即為 #632。
4. 並排比較 forced-on 與 forced-off 的 button-style toggles，確認 #544。
5. 按 toggle state buttons，確認視覺狀態跟著 forced values 改變。
6. 若正在調查 #610，另外記錄 sheet sizing；P12 不把它簡化成單一 pass/fail。

預期結果：

- 旋轉不應重置 selected tab 或 counter。
- Button 背景應延伸到 button bounds，不應有額外 margin。
- Toggle 的 on/off 狀態應有明顯視覺差異。

## P13：Layout And View Graph（AppKit/Gtk）

執行：

```sh
./P13
```

涵蓋 issues：

- #415 (Open)：non-Identifiable `ForEach` elements 可能讓 AppKitBackend crash
- #595 (Open)：ScrollView 內的 Text 被裁切
- #291 (Open)：NavigationSplitView 推導出 minimum width 但沒有移動 split 以符合它
- #158 (Open)：ZStack 內的 Group 沿錯誤軸向排版

測試步驟：

1. 啟動 `P13`；先不要按會 crash 的路徑。
2. 比對 Identifiable list 與 hidden non-Identifiable section；只有準備測 #415 時才按 `Show unidentified list (may crash)`。
3. 在 ScrollView text section 比對 plain text 與 `.fixedSize()` control，確認 #595。
4. 調整 split width，確認 sidebar minimum width 有反映到可見 divider 位置，而不是讓 pane collapse，確認 #291。
5. 觀察 Group-in-ZStack section，確認 children 疊在 z 軸上，而不是沿垂直或水平軸排列，確認 #158。

預期結果：

- Identifiable list 應保持穩定；non-Identifiable 路徑若 crash，記錄為 #415。
- ScrollView text 應換行且不被裁切。
- Split view minimum widths 應反映到可見 divider 位置。
- ZStack 中的 Group content 應重疊，而不是沿 container orientation 排列。

## P14：UIKit Rotation And Theme（iOS）

編譯與執行：

```sh
zsh testapp/compile.zsh -ios P14
xcrun simctl install swift-cross-ui testapp/output/P14.app
xcrun simctl launch swift-cross-ui dev.swiftcrossui.testapp.P14
```

涵蓋 issues：

- #324 (Open)：旋轉時 content 會短暫收到錯誤 size proposal
- #254 (Open)：UIKitBackend 在系統主題變更後會重設 controls，但 app background 未同步更新

測試步驟：

1. 在 iOS simulator 啟動 `P14`。
2. 旋轉裝置後立即讀取 width history，確認 #324。
3. 按 `Clear history`，旋轉一次，確認 settled width 前是否出現短暫過寬 proposal。
4. App 開啟時切換系統 appearance，可用 simulator menu 或 `xcrun simctl ui <device> appearance dark`。
5. 比對 app background、controls 與 explicit adaptive colour block，確認 #254。

預期結果：

- Width history 不應在旋轉後顯示比 settled layout 更寬的短暫 proposal。
- 系統主題變更時，app background 應與 controls、adaptive colours 一起更新。

## P15：Colour Scheme And Window Height（Linux）

執行：

```sh
./P15                                   # 沿用系統主題
GTK_THEME=Adwaita:dark ./P15            # #386 真正的測試方式
```

涵蓋 issues：

- #386 (Open)：GTK 不支援深色模式，文字顏色仍是淺色模式的
- #289 (Open)：Gtk 自繪標題列（CSD）的環境下，視窗最小高度設定錯誤

先讀原始碼確認過的前提：`GtkBackend.swift` 宣告 `canOverrideWindowColorScheme = false`，且第 200 行留有
`TODO(stackotter): Support preferredColorScheme`。因此配色按鈕在 GtkBackend 上**預期無效**，它們的作用是對照組——同一份程式在 WinUIBackend 上會生效，藉此把「缺少覆寫能力」和「顏色算錯」分開。

測試步驟：

1. 以 `GTK_THEME=Adwaita:dark ./P15` 啟動。
2. 檢視「Plain text on the default background」等文字，確認 #386。文字是否在深色背景上仍為深色而難以辨識。
3. 逐一比對 `TextField`、`Toggle`、`Button` 的前景色是否跟隨主題。
4. 記下畫面上的 `Requested` 與 `Resolved` 兩個值。
5. 按 `Dark`、`Light`、`System`，再看 `Resolved` 是否改變。GtkBackend 預期不變。
6. 在 Windows 上以 WinUIBackend 執行同一支程式，重複步驟 5 作為對照。
7. 拖曳視窗下緣往上縮到不能再縮，確認 #289。
8. 記下 `Content area` 顯示的尺寸，並檢查最小高度下是否有內容被裁掉。
9. 按 `Use tall content` 後重複步驟 7-8：最小高度應隨內容變高。
10. 按 `Use short content`，確認視窗能再縮回去。

預期結果：

- 深色主題下文字與控制項應跟隨主題。文字維持淺色模式配色即為 #386。
- 視窗縮到最小時不應有內容被裁切。若最小高度未計入 Gtk 自繪標題列的高度，即為 #289。
- WSLg 是 Wayland，Gtk 在此會使用 CSD，故 #289 的前提成立；但這與 Fedora + GNOME 並不相同，因此「測不出來」只能縮小範圍，不足以關閉該 issue。

## P16：Split View Initial Layout（Windows）

執行：

```sh
./P16.exe
```

涵蓋 issues：

- #160 (Open)：WinUIBackend 的 NavigationSplitView 初次載入時 layout 錯誤，一旦有狀態變更或視窗縮放就會跳回正確

**先讀數字再動任何東西。** 這個 bug 由「第一次 render」定義，而縮放視窗正是兩種會修正它的操作之一，任何互動都會破壞證據。

測試步驟：

1. 啟動 `P16.exe`，不要移動或縮放視窗。
2. 立刻記下 `sidebar` 與 `detail` 兩個 pane 顯示的尺寸。
3. 目視判斷版面是否明顯錯誤（例如 sidebar 佔滿、detail 被擠掉）。
4. 按 `Force update`，這只改變一個與版面無關的計數器。
5. 再次記下兩個 pane 的尺寸。步驟 2 與步驟 5 的差值就是 #160。
6. 重新啟動程式，這次改以拖曳縮放視窗來觸發，確認兩種方式都能讓版面修正。
7. 重新啟動後按 `Switch to 3 column`，對三欄版面重複步驟 2-5。
8. 在 Linux 上以 GtkBackend 執行同一支程式作為對照。

預期結果：

- 首次 render 的 pane 尺寸就應該正確，與強制更新後相同。
- 若步驟 2 與步驟 5 的數字不同，即為 #160，且差值就是「錯得多離譜」的量化結果。
- 尺寸為即時顯示而非在首次 render 時寫入 state：在 layout 過程中寫 state 會回饋到它正在量測的 layout，而 `GeometryReader` 的文件也說明內容可能會以不同尺寸被評估多次。

## P17：Cross-Backend Layout Comparison（Linux 與 Windows）

執行：

```sh
./testapp/output/P17          # WSL 上的 GtkBackend
./testapp/output/P17.exe      # Windows 上的 WinUIBackend
```

涵蓋 issues：

- #264 (Open)：`frame(idealWidth:idealHeight:)` 沒有設定 `idealWidthForHeight` /
  `idealHeightForWidth`，而那正是 `fixedSize(horizontal:vertical:)` 讀取的值
- #161 (Open)：各 backend 對 `Picker` 該依「目前選中項」還是「最長項」決定尺寸並不一致
- #266 (Open)：upstream 在制定 layout 演算法規格時記下的兩個邊界案例

和 P7-P16 不同，這支 app 不針對單一 backend。**每一項檢查都是對照**：同一份程式在
兩個 backend 上各跑一次，比對數字。#161 的對照本身就是 issue——它講的就是 backend
之間不一致，單一 backend 的結果無法回答它。

每個受測 view 會回報自己的尺寸，並疊在一個顯示其範圍的藍色方框上。讀數**刻意蓋住**
受測對象：這裡要測的是它的方框，不是它的內容。

測試步驟：

1. 在其中一個 backend 上啟動 `P17`，在改動任何東西之前先記下所有回報的尺寸。
2. 比對第一段的 `subject` 與 `control`，確認 #264。兩者是同樣的文字、同樣的
   `idealWidth: 160`，差別只在 subject 多了 `fixedSize(horizontal: true, vertical: false)`。
3. subject 寬度接近 160 表示 ideal width 有傳達到 `fixedSize`。若與 control 相同、
   或等於文字的完整自然寬度，即為 #264。
4. 記下 `picker` 的寬度，接著依序按 `Shortest`、`Medium`、`Longest`，每次都記下寬度，
   確認 #161。
5. 寬度隨選取改變表示依「選中項」決定尺寸；寬度固定表示依「最長項」。記下是哪一種，
   因為 issue 的重點是兩個 backend 不同。
6. 用 `Shorter` 與 `Taller` 逐格調整 aspect ratio scroll view 的高度，確認 #266a。
   內容是 2:1 的方塊，因此顯示捲軸會使其變窄、進而變矮。
7. 注意捲軸出現與消失的高度。出現或消失都可以，但必須穩定下來。在兩種狀態之間持續
   閃爍而無法收斂即為失敗。
8. 最後一段比較三條色帶，確認 #266b。它們是三個自然寬度不同的 `VStack` 子元件，
   並被給定固定高度。
9. 按 `Less height` 與 `More height`，確認每一格高度下三條色帶寬度都相等。
10. 在另一個 backend 上重複全部步驟，比對兩份紀錄。

預期結果：

- #264：subject 寬度應約為 160。若與 control 相同，表示 ideal width 從未傳達到
  `fixedSize`。
- #161：無論採用哪一種尺寸規則，兩個 backend 應採用同一種。兩邊規則不同即為此 issue。
- #266a：每一個高度下捲軸都應收斂穩定。
- #266b：任何 stack 高度下，三條色帶都應為最寬子元件的寬度。

## P6：Zstd Stream Player

編譯與執行：

```sh
zsh testapp/compile.zsh P6
./testapp/output/P6.exe
```

macOS 的輸出檔名可能是 `P6` 而不是 `P6.exe`：

```sh
zsh testapp/compile.zsh P6
./testapp/output/P6
./testapp/output/P6 -core
./testapp/output/P6 --debug
./testapp/output/P6 --frame-drop
./testapp/test_P6.zsh /path/to/video.webm
./testapp/test_P6.zsh -rss --debug /path/to/video.webm
```

Metal 是 macOS 預設的 renderer。加上 `-core` 可改用 Core Animation fallback，
或用 `-metal` 明確選用 Metal；若同時給多個 renderer flag，以最後一個為準。
預設輸出速率為 30 FPS。加上 `--debug` 可啟用完整 frame 的 duplicate 比對與
詳細 frame 診斷資訊；一般播放不會付出這兩項成本。
Late-frame dropping 預設為關閉。加上 `--frame-drop` 可在啟動時就開啟，或使用
執行期的 `Frame drop` toggle 按鈕切換。播放中變更此 toggle 會從目前時間戳
重新啟動 video 與 audio，讓新設定立即生效。
若需無人值守的測試，`-f` 可略過檔案對話框直接選檔：單獨使用 `-f` 會挑選檔名
含 `恩典365` 的第一個媒體檔，`-f <關鍵字>` 可比對其他檔名，`-f <路徑>` 則直接
指定路徑。搜尋範圍包含目前目錄、執行檔所在目錄與預設輸入目錄。`-autoplay`
會立即開始播放，`-enable-dropframe` 會開啟丟幀，因此
`P6.exe -f -autoplay -enable-dropframe` 完全不需要點擊任何按鈕。
`test_P6.zsh -win` 與 `P6-test.zsh` 都封裝了這組參數，其中
`P6-test.zsh [檔名關鍵字]` 是較精簡的寫法。
`compile.zsh` 預設以 release 編譯，讓 GUI timing 更接近一般使用情境。只有需要
未最佳化的 compiler-level debugging 時才使用 `BUILD_CONFIG=debug`；app 診斷應由
`--debug` 等 app flag 控制。

`test_P6.zsh` 在未帶任何參數時會印出使用說明，否則會把 renderer flags、
`--debug`、`--frame-drop` 與媒體路徑轉送給編譯好的 P6 binary。它專屬的
`-rss` 選項會每秒取樣一次 P6 process 的 RSS，並把 `rss_kb`、`peak_rss_kb`
與最終結束狀態附加到獨立的 `p6-debug-events-rss.log`；每次帶 `-rss` 啟動
都會先清空該檔案再記錄新的一次執行，且 `-rss` 不會轉送給 P6。

Runtime tools：

- `ffmpeg`、`ffprobe` 必須在 `PATH` 上。
- 選擇 `.zst` 檔時，`zstd` 必須在 `PATH` 上。
- 若要播放音訊，`ffplay` 必須在 `PATH` 上。
- LZFSE2/swift_tar `.zst` storybook streams 視為 zstd level 9 sources。
- macOS tool lookup 也會檢查 `/opt/homebrew/bin`、`/usr/local/bin`、
  `/opt/local/bin`、`/usr/bin`、`/bin`，涵蓋 Apple Silicon Homebrew、
  Intel Homebrew、MacPorts 與系統工具，即使 app 是以最小 GUI 環境啟動也一樣。
- 預設 file dialog 目錄會檢查 `~/proj/LZFSE2/swift_tar/images`
  與 `~/proj/lzfse2/swift_tar/images`。

診斷紀錄：

- P6 只把生命週期與錯誤訊息寫入目前工作目錄下的 `p6-debug-events.log`，
  終端機輸出維持安靜。詳細的 frame upload、呈現與逐格計時訊息需要 `--debug`，
  且同樣只會寫入該檔案。
- `testapp/.compile-work/` 與 `testapp/output/` 屬於暫存區：`compile.zsh` 會把
  選定的原始碼複製到 `.compile-work/TestApps/Sources/<name>/main.swift` 並
  產生對應的 `Package.swift`，因此這兩個目錄都不應納入 commit。

測試步驟：

1. 啟動 `P6.exe`，按 `Choose file`。
2. 選擇 `storybook-1min-4k60.mp4`、一個 WebM 輸入檔，或
   `storybook-1min-4k60.y4m.zst`。
3. 確認第一張 frame 出現，且在 duration 可取得時，可選取的進度文字使用
   `Current: 01:17 / 04:02 (32%)` 格式。在文字上拖曳選取並複製，確認文字
   選取功能正常。
4. 按 `Show resolution`，確認按鈕背景切換為啟用狀態，且底部另外出現一行
   顯示 input resolution、output resolution 與 960x540 viewport。再按一次，
   確認底部那行消失、按鈕恢復未啟用背景。
5. 按 `Play`，確認影片開始播放；若輸入檔有音軌且 `ffplay` 可用，確認聲音也
   同步開始。確認 log 會顯示 `playback clock started <time>`，並帶有內插的
   media timestamp，例如 `00:12`。
6. 播放中按下固定標籤的 `Sound` toggle，確認啟用時背景為藍色、停用時恢復
   一般按鈕外觀。確認開啟聲音會從目前 media timestamp 重新啟動解碼，讓
   audio 與 video 共用同一個起始點，且播放會從原本位置繼續而不是跳回零秒。
7. 在有音軌播放的情況下，讓直接的 MP4/WebM 輸入連續播放至少三分鐘；在各個
   output resolution 下測量並記錄 video 是否會逐漸落後 audio。
8. 按 `Stop`，確認 Stop 會保留目前位置，且 Play 可從該位置繼續。
9. 拖曳 timeline slider 經過數個位置後停在指定時間。確認 `Seek target` 會
   持續更新，但只有在最後一次拖曳變更 200 ms 後才會啟動一個 decoder session。
10. 按 `Seek`，確認顯示的 frame/時間跳到 slider 指定位置；若原本正在播放，
    應從該目標位置繼續播放。
11. 使用指定的 WebM 樣本，seek 到 00:50，確認畫面字幕與口白皆約為
    `卻看我是祂的孩子`。透過獨立的 ffplay 診斷確認 `-seek2any 1 -ss 50` 會讓
    audio clock 從約 50.01 秒開始，而不是退回到約 46.05 秒。
12. 按 `-5s` 與 `+5s`，確認顯示的 frame 與時間會移動 5 秒，並在開頭／結尾
    clamp。
13. 選擇 `1x`、`2x`、`3x`，確認選擇速度不會切換焦點到其他 terminal，也不會
    立即重啟 decoder；按 Play 或 Seek 後才套用新速度。
14. 確認預設選中 `30` FPS。選擇 `45` 與 `60` FPS，確認選擇 FPS 不會切換焦點
    到其他 terminal，也不會立即重啟 decoder；按 Play 或 Seek 後才套用新的
    呈現速率。
15. 選擇 `Preview 960x540`、`1080p 1920x1080`、`4K 3840x2160`，確認選擇
    resolution 不會切換焦點到其他 terminal，也不會立即重啟 decoder；按 Play
    或 Seek 後才套用新的 output mode。
16. 在 macOS 上，確認所有可選取的播放控制項（包含 `Sound`、`Frame drop`、
    `Show resolution`）都出現在同一列，且標籤絕不會附加 `on`／`off`。點擊每個
    toggle，確認啟用時背景為藍色、停用時恢復一般按鈕外觀。啟用 `Frame drop`，
    確認 `Show resolution` 會自動啟用並鎖定為開啟，直到 Frame Drop 停用為止。
    確認狀態列會回報 Frame Drop 狀態。播放中切換 Frame Drop，確認會從目前
    時間戳重啟一次 decoder／audio session。
17. 以 `--debug --frame-drop` 重新啟動，選擇 `4K 3840x2160` 與 `60` FPS，
    確認 Frame Drop 與 Show Resolution 兩者一開始就是啟用狀態，preview 仍為
    960x540，底部資訊行會回報每秒丟棄的 frame 數，且詳細 log 會回報
    3840x2160 frame 上傳與累積的 late-frame drop 次數。
18. 載入一個檔案，接著 seek 或載入另一個檔案；確認終端機在前一個 decoder
    停止時，不會出現來自 ffmpeg 的 `Broken pipe`、`Error muxing a packet`
    或 `Error writing trailer` 輸出。
19. 播放中關閉視窗，確認出現關閉提示，並確認 FFmpeg/Zstd/FFplay 子程序都會
    結束，`P6` 程序本身也會結束並歸還 shell prompt。
20. 從 `test_P6.zsh` 啟動播放，從 `p6-debug-events.log` 取得 ffplay 的 PID，
    在該終端機按 Ctrl-C。確認 log 檔中記錄 P6 收到訊號、等待 ffplay 結束，
    且沒有殘留對應的 ffplay 程序。確認終端機沒有印出 P6 的診斷行。由於腳本
    不再使用 `exec`，當 zsh 與 P6 同時收到 Ctrl-C 時，觀察到的結束狀態會因
    shell 而異。
21. 先在 `p6-debug-events-rss.log` 放一行可辨識的舊內容，再透過
    `test_P6.zsh -rss` 重新啟動，播放並 seek 至少一分鐘，然後關閉 P6 或按
    Ctrl-C。確認舊內容已被清空，檔案只包含新一次執行的起始行、每秒一筆的
    RSS 取樣、最終取樣筆數、峰值 RSS（KiB）與 P6 結束狀態。確認終端機沒有
    RSS 診斷行，且 `p6-debug-events.log` 仍只保留給 P6 診斷訊息使用。

預期結果：

- MP4、WebM、Y4M、Y4M.ZST inputs 都能以選定的 output resolution decode。
- 有音軌的直接輸入檔可透過 `ffplay` 播放聲音；Y4M / `.zst` video-only path
  不應 crash。
- 可用 timeline slider 快速選取指定時間，按 `Seek` 後從該時間顯示或播放。
- 經過時間、總長與百分比共用同一個可選取的 `Current` 進度文字；options row
  中不再有獨立的百分比欄位。
- 所有可選取的播放控制項都會一起出現在同一個 options row。
- 連續的 slider 變更會做 200 ms debounce，讓拖曳過程中的中間位置不會反覆
  重啟 FFmpeg 與 ffplay。
- 選擇 speed、FPS 或 output resolution 都不應切換焦點到其他 terminal、
  不應偷焦點，也不應立即重啟 decoder。
- 可見 viewport 保持 960x540，並將 decoded frame 縮小以配合一般測試視窗。
- `Sound`、`Frame drop`、`Show resolution` 使用固定的按鈕標籤。每個 toggle
  各自透過 `.toggleColor(.blue)` 選用藍色，啟用時使用該背景色，停用時恢復
  一般按鈕外觀；狀態不會附加到標籤文字。
- `Frame drop` 是一個執行期 toggle，其狀態會出現在狀態列；啟用它也會同時
  啟用並鎖定 `Show resolution`，讓每秒丟棄的 frame 數值持續可見。
  `--frame-drop` 會讓兩者一開始就是啟用狀態。
- `Show resolution` 啟用時使用啟用中的按鈕背景，並在視窗底部加上一行資訊；
  當 frame dropping 啟用時，該行也會顯示取樣到的每秒丟棄 frame 數值。
- macOS 透過可重複使用的三張 texture 組成的 Metal pool 呈現 decoded RGBA
  frame，而不是每個 frame 都配置新 texture 或重建 SwiftCrossUI image。
- 音訊只會在第一個 video frame 解碼完成後才開始播放，且 video 節奏使用絕對
  單調時鐘（absolute monotonic clock），以減少逐格累積的計時漂移。
- 每個 session 的 log 都會記錄自己的 token、seek 時間、擷取到的速度、FPS、
  resolution 與模式；audio 與 playback-clock 的 log 會沿用相同的 token 與
  擷取到的速度。
- 播放中開啟聲音會從目前 media timestamp 重新啟動解碼，讓新的 `ffplay`
  程序與 video stream 共用同一個起始點，而不是各自使用不相關的時鐘。
- Audio seeking 啟用了非 keyframe 的 demuxer 目標，讓 WebM 播放能從接近
  slider 指定時間開始，而不是退回到前一個 video keyframe（可能相差數秒）。
- 播放控制項在解碼於 UI thread 之外執行時仍保持 responsive。
- 一般播放不會逐格掃描完整 RGBA frame 做相等比對，也不會同步記錄每一個
  frame 的 log；`--debug` 會在需要時啟用這些診斷。
- 預設情況下，每個 decoded frame 都仍有機會被呈現。加上 `--frame-drop` 後，
  晚於 audio-anchored 單調 deadline 的 frame 會在送到 UI 與 Metal renderer
  前被捨棄；搭配 `--debug` 會回報累積的 late-frame drop 次數。
- 提早停止 decoder 是正常操作，且必須保持安靜：子程序的 stderr 會被緩衝而
  不會轉送到終端機，因此 ffmpeg 預期中的 EPIPE 回報不會顯示出來。真正的解碼
  失敗仍會把緩衝的工具輸出顯示在狀態列上。
- 關閉視窗會終止 `P6` 程序本身，不只是它的子程序，因此不需要手動 `Ctrl-C`
  就能拿回 shell prompt。
- 終端機的 SIGINT 與 SIGTERM handler 會在 P6 結束前終止並同步 reap 保留的
  ffplay 程序。由於 wrapper script 不再使用 `exec`，最終 shell 看到的
  Ctrl-C 結束狀態不保證就是 P6 內部的 130 狀態。
- `test_P6.zsh -rss` 會在啟動時清空 `p6-debug-events-rss.log`，之後每秒只
  測量 P6 process 本身的 resident memory，並記錄取樣值與峰值 RSS；FFmpeg、
  ffplay 與 zstd 子程序的 RSS 不會被計入。
- 缺少 tools 或 malformed input 應在 status line 顯示錯誤，不應 crash。

驗證狀態：

- 先前回報的「timeline seek 後 A/V 不同步」問題，在提供的 WebM 樣本上確認
  已解決。以 00:50 為 seek 目標時，預設的 ffplay demuxer seeking 讓 audio
  約從 46.05 秒開始，而 `-seek2any 1` 讓它約從 50.01 秒開始。該時間點附近的
  可見字幕與口白皆為 `卻看我是祂的孩子`。
- 此次確認涵蓋一般播放與未加 `--debug` 的 timeline seeking。各種速度與
  Frame Drop 組合下的長時間 4K 播放，仍屬於獨立的壓力測試情境，尚未被視為
  已確認的迴歸測試。
- 2026-08-11：修正一個可重現的 Windows 專屬當機（例外碼 `0xc000001d`，
  `dispatch.dll` 內的 illegal instruction），發生在第一張影格發布的當下，
  在單張影格 seek（會立即終止 decoder session）的情境下最容易重現。透過
  `cdb` 解析 crash dump 的呼叫堆疊，根因追到 `P6DecoderSession.terminate()`
  在自己的 `readabilityHandler` callback 內部同步關閉 `outputHandle`，
  對「自己當下正在執行的那個 queue」做同步派發（`dispatch_sync`）造成死鎖，
  `dispatch.dll` 偵測到後直接中止程式而非真的卡住。修正方式是把關閉動作改到
  另一個 queue 上非同步執行（`DispatchQueue.global().async`）。已透過重複的
  單張影格 seek 與一般播放測試確認不再當機，也沒有新的 crash dump 產生。
- 2026-08-11：在預設設定（30 FPS、Frame Drop 關閉）下的一般播放中，觀察到
  Windows 上每秒約丟棄 17 張影格；切換至 4K 時升高到每秒約 25 張，播放幾乎
  停止。調查結果：
  - ffmpeg **不是**瓶頸。以 P6 完全相同的 4K filter chain 單獨執行，20 秒的
    影片僅需 5 秒完成解碼（約 4 倍實時速度）。
  - 改用 release 編譯（`BUILD_CONFIG=release`）並未改善，代表成本不只是
    「未最佳化的程式碼」。
  - 瓶頸在 Windows 的顯示路徑。原本每張 4K 影格需要：從 pipe 讀取 33 MB、
    `Array` 複製 33 MB、建構 `ImageFormats.Image`、重新配置 33 MB 的
    `WriteableBitmap`、`memcpy` 33 MB、830 萬次的逐像素 RGBA→BGRA 迴圈，
    以及一次 SwiftCrossUI view graph 更新；在 30 FPS 下約等於每秒 4 GB 的
    記憶體流量。
- 2026-08-11：已為 Windows 建立 GPU 呈現路徑，架構比照 macOS 的 Metal 設計
  （`Sources/WinUIBackend/D3D11VideoInterop.swift` 中的 `P6D3D11VideoSurface`）：
  D3D11 swap chain 搭配三張輪替的 staging texture，由影格抵達驅動呈現，影格
  直接寫入已對映的 GPU 記憶體。不再有 `Array`、`ImageFormats.Image`、
  `WriteableBitmap`，也不需要像素格式轉換（ffmpeg 的 `rgba` 輸出與
  `DXGI_FORMAT_R8G8B8A8_UNORM` 位元組完全相同）。目前仍保留一次 `memcpy`，
  因為 Windows 上無法使用 `FileHandle.fileDescriptor`；若要移除，需以具名管線
  搭配 `ReadFile` 取代 Foundation 的 `Pipe`。
- 2026-08-11：**GPU 路徑尚無法使用。** 已嘗試兩種承載方式，皆受阻：
  - `SwapChainPanel`：swift-winui 未提供其 projection。透過 `RoActivateInstance`
    啟動可成功（`GetRuntimeClassName` 確認 runtime class 正確，
    `ISwapChainPanelNative` 的 QI 也成功），但產生出來的 wrapper 類別以 `try!`
    延遲解析 COM 介面，因此一碰觸被包裝型別的屬性，行程便以非法指令中止。
  - 子視窗 `HWND` + `CreateSwapChainForHwnd`：swap chain 建立成功、`Present`
    也成功，畫面卻完全看不到。由於子視窗即使位置錯誤仍與可見的 client 區域
    重疊，影像卻完全不存在，指向 WinUI 3 的 airspace 行為——XAML 透過
    DirectComposition 合成，會遮蔽傳統子視窗。
  - 剩餘選項：將 swap chain 掛載於 DirectComposition visual，或由 C++/WinRT
    shim 建立 `SwapChainPanel` 並直接掛入 visual tree，讓 Swift 端完全不建立
    任何 wrapper。
- 2026-08-11：**黑畫面已解除，GPU 路徑可正常顯示。** 不需要 C++ shim：
  `SwapChainPanel` 全程只走原始 COM（`IPanel::get_Children` +
  `IVector<UIElement>::Append` 掛入一個已投影的 `Canvas`，尺寸以
  `IFrameworkElement::put_Width/put_Height` 設定），Swift 端完全不建立 wrapper，
  也就不會踩到延遲 QI 的 `try!`。swap chain 改以
  `CreateSwapChainForComposition` 建立，並在 UI 執行緒呼叫
  `ISwapChainPanelNative::SetSwapChain` 綁定（該 API 僅能在 UI 執行緒使用），
  解碼執行緒仍只負責 Map/CopyResource/Present。
- 2026-08-11：**影片畫在黑框右下角的根因，是 `WinUI.Canvas` 的 DesiredSize 恆為
  零。** Canvas 不會依子元件量測，而 `WinUIElementRepresentable` 的預設
  `sizeThatFits` 正是去問元件的 desired size，因此該 view 被當成 0x0，版面配置把
  它置中，swap chain 就從黑框正中心往右下畫，其餘被裁掉。修法是在該
  representable 自行實作 `sizeThatFits` 回傳固定尺寸。**這是 upstream 的通用陷阱**
  ：任何以 `Canvas` 為根的 representable 都會被錯誤定位。
- 2026-08-11：**縮放已解決，960x540／1080p／4K 皆正確。** SwapChainPanel 以
  「一個 buffer 像素對一個 DIP」合成，因此 buffer 依實體像素建立（維持清晰），再以
  `IDXGISwapChain2::SetMatrixTransform(viewport DIP ÷ buffer 像素)` 映射回檢視區；
  影格小於檢視區時由 `SetSourceSize` 交給 DXGI 拉伸，大於時（如 4K）則以矩陣縮小，
  兩者都不需要 shader。所有幾何變更集中在單一 API
  `P6D3D11VideoSurface.setViewport(_:frameWidth:frameHeight:)`，只有尺寸真的改變才
  重建 swap chain 與 texture pool。
- 2026-08-11：幾何以 `-calib` 驗證（以紅框／綠色中心十字／角落色塊填滿 swap chain，
  再對截圖做像素掃描，不靠肉眼）。960x540 與 4K 皆量得內容佔 `x=360..1559`
  ＝ 1200 px ＝ 960 DIP 檢視區，左右邊框與中心十字位置皆吻合。
- 2026-08-12：**Windows 的瓶頸是管線，不是 GPU；而且現在是量出來的，不是推論。**
  每秒會記錄一次逐階段計時（log 中的 `stage timings:`）。1080p 下讀取階段每幀花
  102–164 ms，而預算只有 33 ms，呈現只花 0–4 ms。原因在 Foundation 的 `Pipe`：
  swift-corelibs-foundation 在 Windows 呼叫 `CreatePipe(..., 0)`，緩衝區是系統
  預設的數 KB，因此一張 8 MB 影格會被拆成數千次讀取，每次 `read(upToCount:)` 還
  各配置一個 `Data`，再累積進不斷增長的緩衝區並第二次複製進已對映的 texture。
  **該緩衝區大小沒有任何 API 可調整。**
- 2026-08-12：P6 改為自行建立 8 MB 緩衝的 Win32 管線，並以 `ReadFile` 直接讀入已
  對映的 staging texture（對映列間距與影格列長相同時一次讀完）。讀取階段降到每幀
  0–17 ms，**1080p 在所有 GPU 模式下皆為 0 dropped frames/sec**。
- 2026-08-12：新增 GPU 選擇旗標 `-amd`／`-nvidia`／`-both-gpu`／`-no-gpu`
  （`-both-gpu` 由 Nvidia 解碼、由顯示器所屬介面卡呈現；`-no-gpu` 走 Microsoft
  Basic Render Driver 作為 CPU 基準線），以及 `testapp/gpu-matrix.zsh`：逐一執行所有
  模式並把結果寫入 `testapp/P6_findings/gpu-modes.csv`（含 date_tested、mode、
  resolution、target_fps、measured_fps、dropped/s、逐階段耗時與完整 ffmpeg 參數，
  確保可重現）。本機 adapter 0 是 AMD Radeon iGPU、adapter 1 是 Nvidia RTX 4060。
  結論：**五種模式在 1080p/4K、30/60 FPS 下差異都在雜訊範圍內，連完全不用 GPU 也
  一樣**；呈現階段一律只花 0–6 ms。選哪張 GPU 對這個工作負載不是槓桿。
- 2026-08-12：以相同濾鏡鏈單獨執行 ffmpeg 輸出到 NUL，4K@60 可達約 123 fps
  （約 2.1x 即時），遠高於 P6 的消耗速度，因此**解碼也不是瓶頸**。剩下的疑點是
  CPU 競爭：4K@60 時 ffmpeg 會佔滿整台機器去產生沒人等待的影格，同一張 33 MB 影格
  在 4K@30 只需 58 ms、在 4K@60 卻要十倍時間。下一步應嘗試以 `-re`／`-readrate`
  把解碼速率壓到播放速率。
- 2026-08-12：**真正的天花板是 publish，不是管線。** 修好管線後，所有設定仍卡在
  7–8 fps，且與解析度、影格率幾乎無關 —— 這是「每幀固定成本」而非頻寬限制的徵兆。
  量測主執行者往返後真相大白：`acceptFrame` 會設定 `currentTime`、`seekPosition`、
  `status` 三個 `@Published` 屬性，因此**每一幀都重建 view graph 並執行一次 WinUI
  版面配置，實測每幀 97 ms**，而預算只有 16–33 ms。影片本身完全不經過 view graph，
  所以時間軸與狀態文字改為每秒發佈兩次。每組設定量測 20 秒：

  | 設定 | 修改前 | 修改後 |
  |---|---|---|
  | 1080p @ 30 | 7.8 fps | **26.6–29.2 fps**，丟幀 0.7–2.9/s |
  | 1080p @ 60 | 7.7 fps | **49.5–50.8 fps**，丟幀 7.9–10.1/s |
  | 4K @ 30 | 6.9 fps | **27.5–28.2 fps**，丟幀 1.2–2.1/s |
  | 4K @ 60 | 1.1 fps | 0.9–25.7 fps，丟幀 33–57/s |

  「單次狀態更新要花約 100 ms」本身就是 WinUIBackend 的一項發現，值得另案追查。
- 2026-08-12：修正兩則先前的紀錄。回報為 0.0 的丟幀數是 `gpu-matrix.zsh` 的 bug
  （awk 取錯欄位），實際上 4K 一直都是每秒數十幀。另外以 ffmpeg 的 `-readrate`
  限制解碼速率（`-pace` 旗標）並無可量測的差異，因此先前的 CPU 競爭推論是錯的。
- 2026-08-12：**4K @ 60 受限於傳輸量，仍然不可用。** 它需要約 2 GB/s 的 RGBA 穿過
  管線，而丟幀救不了 —— 管線無法 seek，**每一張要丟棄的影格仍得整張讀完**。
  4K @ 30 是 1 GB/s、可達 28 fps，因此實測上限大約落在 1 GB/s。重複測三輪後，五種
  GPU 模式的數字劇烈跳動（`-both-gpu` 分別量到 25.7、10.2、5.6 fps），沒有可重現的
  優劣順序；唯一穩定的是 `-no-gpu` 永遠最差，因為 CPU 光柵化會與讀取端搶 CPU。
  出路是減少位元組數：NV12 為 12 bpp、RGBA 為 32 bpp，可讓 4K @ 60 從 2 GB/s 降到
  750 MB/s。
- 2026-08-12：**4K@60 已由「解碼成 NV12、在 GPU 上轉換」解決。** ffmpeg 改為輸出
  `-pix_fmt nv12`（每像素 12 位元，RGBA 為 32），再由 D3D11 video processor 轉換並
  縮放進 back buffer，該路徑不再使用 `SetSourceSize` 拉伸。NV12 與 Nvidia 無關
  （"NV" 是 FourCC），因此是否採用它是以「呈現用的介面卡能否建立該轉換」來探測，
  而非判斷廠商。`-rgba` 可強制回舊路徑作為對照。4K@60、每模式 20 秒：

  | 模式 | 格式 | fps | 丟幀/s | read |
  |---|---|---|---|---|
  | default | nv12 | **52.1** | 8.0 | 2.6 ms |
  | `-amd` | nv12 | **51.3** | 7.8 | 2.8 ms |
  | `-nvidia` | nv12 | **49.4** | 9.5 | 3.5 ms |
  | `-both-gpu` | nv12 | **51.3** | 7.8 | 4.3 ms |
  | `-no-gpu` | rgba（已退回） | 13.4 | 53.3 | 62.1 ms |

  相較於 RGBA 路徑的 0.9–25.7 fps 與 33–57 丟幀/s。唯一退回的模式就是同一輪內的
  對照組：決定性因素是像素格式，而非 GPU。也已目視確認：色彩正確（輸入
  `DXGI_COLOR_SPACE_YCBCR_STUDIO_G22_LEFT_P709`、輸出
  `RGB_FULL_G22_NONE_P709`），畫面仍精準落在 1200 px 的檢視區（非最大化視窗下量得
  `x=173..1372`）。
- 2026-08-12：建置該路徑時發現三個值得記住的 bug：
  - 已對映 NV12 texture 的色度平面偏移量**就是 `rowPitch * height`**，不可由對映
    大小回推。此驅動回報的 `DepthPitch` 是 `rowPitch * height`（2048 × 1080），而非
    `rowPitch * height * 3/2`，因此減去色度一半後會把色度放進亮度平面正中央，畫面
    呈現為整片亮綠且下半部損壞。
  - video processor 的輸入 texture 需要 `D3D11_BIND_DECODER` 而非
    `D3D11_BIND_SHADER_RESOURCE`：讀取它的是視訊引擎，不是著色器單元；否則
    `CreateVideoProcessorInputView` 會回 `E_INVALIDARG`。
  - NV12 能力探測必須在「實際要呈現的那張介面卡」上執行。在預設介面卡上探測、卻由
    軟體裝置呈現，會在無法轉換的裝置上選用 NV12，接著 NV12 位元組流入 RGBA 影像的
    後備路徑而直接中止。現在探測會跟隨介面卡，且後備路徑絕不會用 NV12 位元組建立
    RGBA 影像。
- 2026-08-12：加大解碼管線緩衝區沒有幫助。4K@60 下：25 MB（兩張影格，預設）得
  49.9 fps、128 MB 得 51.6、512 MB 得 48.2，而 **2 GB 得 45.3** —— 比預設還略差。
  `CreatePipe` 確實接受 2 GB，但管線緩衝的作用是吸收抖動而非提高吞吐量；讓解碼器
  領先數秒只是浪費記憶體，且 seek 時還得全部丟棄。先前 8 MB 的修正之所以有效，只是
  因為當時緩衝區小於一張影格。可用 `-pipe-mb <n>` 複測。
- 2026-08-13：**解碼器不再開出主控台視窗。** P6 會生出 ffmpeg、ffplay、zstd 與兩個
  ffprobe，且每次變更解析度或影格率都會重啟解碼器；只要 P6 沒有可繼承的主控台
  （從檔案總管或以 pty 為基礎的終端機啟動時即是如此），每次生成都會開出一個主控台
  視窗。Foundation 的 `Process` 只傳 `CREATE_UNICODE_ENVIRONMENT`，且無從加上
  `CREATE_NO_WINDOW`，因此五個生成點全部改走 `P6WindowlessProcess`，直接呼叫
  `CreateProcessW`。連帶也要自行實作引數引號處理、handle 繼承、終止與結束碼；其他
  平台維持 Foundation 路徑。詳見 `testapp/todo-foundation.md`。
- 2026-08-13：曾嘗試把各 app 連結成 GUI 子系統執行檔，已收回。它雖能消掉檔案總管
  開啟時附帶的主控台，但只要子行程仍由 Foundation 生成就會更糟：沒有可繼承的主控台
  時，ffmpeg 與 ffplay 會各自開出一個、且在其執行期間都存在的主控台視窗。理由已記在
  `compile.zsh`，避免在未先修好子行程生成方式前又再嘗試一次。
- 2026-08-13：**`-maximized` 與將視窗帶到前景現在都正常了**，關鍵是改以「視窗標題」
  辨識目標視窗。先前的作法是取呼叫執行緒的第一個可見視窗，找不到就退回
  `GetForegroundWindow()`；因此在 XAML 視窗尚未建立前，被最大化與啟動的是使用者當下
  正在用的視窗 —— 也就是啟動 P6 的終端機。另外重試的計時是從行程啟動開始算，而視窗
  要數秒後才出現，等到有東西可處理時寬限期早已過期。兩者皆已修正：以標題比對，並自
  「首次找到視窗」起重試五秒。
- 2026-08-13：**960x540 在 NV12 路徑下會被裁切**，而 1080p 與 4K 正常。兩條路徑呈現的
  區域不同：RGBA 是把影格複製到 buffer 角落再由 DXGI 拉伸該區域，因此來源是「影格」；
  NV12 走 video processor，它會把影格縮放填滿整個 buffer，因此來源是「整個 buffer」。
  若在此仍指定影格區域，呈現出來的只會是其左上角並被拉伸。影格不小於檢視區時看不出
  差異（此時 buffer 就等於影格尺寸），所以只有最小的預設值會顯現。修正後重新校準：
  各種預設下影片皆橫跨 `x=360..1559`，寬 1200 px。
- Windows P6 待辦（尚未實作）：
  - 影片顯示區目前固定 960x540，**不會隨視窗縮放**。`setViewport` 已是縮放的入口，
    只要傳入新的 viewport 即可；缺的是把視窗尺寸接上去，並在測試步驟中加入
    「拉動視窗大小，影片區域應同步縮放且不變形」的檢查。
  - **4K 播放仍不會自行前進**（丟幀約 20/秒，進度條停住）；拖動進度條後畫面正確
    顯示，可見瓶頸不在呈現路徑，而在每幀 33MB 走 Foundation `Pipe` 的讀取。要根治
    需改用 `ReadFile` 具名管線，或導入硬體解碼／CUDA。
  - CUDA 尚未實作；目前完全是 D3D11／DXGI。

RSS 壓力測試紀錄：

- `p6-debug-events-rss-8845476c-speed3x,fps60,4k_3840x2160_sound_on_frame_drop.log`
  記錄的是 P6 commit `8845476c`，在 3x 速度、60 FPS、3840x2160 輸出、
  Sound On、Frame Drop 啟用條件下的執行結果。
- 該次執行從 2026-08-04 18:25:39 UTC 持續到 18:28:58 UTC，共收集 196 筆有效
  的一秒取樣，並以狀態 0 順利結束。
- P6 的峰值 RSS 為 2,398,896 KiB（約 2.29 GiB），平均取樣 RSS 約為 1.92 GiB。
  這些數值不包含 FFmpeg、ffplay 與 zstd 子程序。

## P18：File Dialogs（Linux 與 Windows）

執行：

```sh
./testapp/output/P18          # GtkBackend，於 WSL
./testapp/output/P18.exe      # WinUIBackend，於 Windows
```

不對應特定 issue。GtkBackend 已從 `GtkFileChooserNative`（GIR 標記
`deprecated="1"`，且在無 xdg-desktop-portal 的 Wayland 下不會關閉對話框）遷移至
`GtkFileDialog`。該遷移改寫了四條路徑，而其中只有「單檔開啟」執行過。本 app 負責跑
其餘幾條，並與 WinUIBackend 對照。

未涵蓋：多重選取。`PresentSingleFileOpenDialogAction` 將
`allowMultipleSelections` 寫死為 false，因此任何應用程式都無法觸達
`gtk_file_dialog_open_multiple`。

測試步驟：

1. 於其中一個 backend 啟動 P18。每個按鈕開啟一個對話框，並在其下方那一行回報結果。
2. 按 `Open a file`，選擇任一檔案，確認**對話框關閉**且該行顯示路徑。
   **對話框是否關閉本身就是結果的一部分**——原始缺陷正是「檔案已交回、視窗卻留在畫面上」。
3. 以 Cancel 重複一次，確認對話框關閉且該行顯示 `cancelled`。
4. 按 `Choose a folder`，選擇一個目錄，確認同樣兩件事。這是與檔案開啟不同的 GTK 呼叫。
5. 按 `Choose a save destination`，確認檔名欄位已預填 `p18-example.txt`——這是唯一會
   用到初始檔名的路徑。
6. 於另一個 backend 重複所有步驟並比較。重點在於兩邊是否都交回路徑、都關閉對話框，
   而非兩者外觀是否相同。

## P19：Flat Menus（Linux 與 Windows）

執行：

```sh
./testapp/output/P19          # GtkBackend，於 WSL
./testapp/output/P19.exe      # WinUIBackend，於 Windows
```

兩個 backend 以不同機制呈現同一個 `Menu`，而 app 端無法選擇。GtkBackend 符合
`PopoverMenus`，自行建立並定位一個獨立的選單 widget；WinUIBackend 符合
`AttachedMenus`，把選單交給按鈕、由平台建構。兩者是同一功能的兩種實作，並非任一方
缺少能力。

P19 只保留單一平面層級，使任何差異都能明確歸屬於「項目如何呈現」。巢狀屬於 P20。

測試步驟：

1. 啟動 P19，按 `Open the menu`。
2. 確認五個項目全部出現：兩個按鈕、一個不可點的文字項目、一個分隔線、一個切換項。
3. 留意文字項目與分隔線是否確實出現。若某個 backend 略過其一，那就是發現。
4. 按 `Button item`，確認 `last action` 更新。
5. 再次開啟選單並操作切換項，確認 `toggle item` 反映新狀態。同時留意操作切換項後
   選單是保持開啟或關閉。
6. 記錄選單相對於按鈕的出現位置。兩種機制的定位方式不同，這正是對照的重點。
7. 於另一個 backend 重複。

## P20：Nested Menus（Linux 與 Windows）

執行：

```sh
./testapp/output/P20          # GtkBackend，於 WSL
./testapp/output/P20.exe      # WinUIBackend，於 Windows
```

刻意與 P19 分開。巢狀是兩種機制分歧空間最大之處：一邊由平台提供整棵樹，另一邊必須
自行建立並定位每一層。

每一層都放置可點擊的項目，如此才能區分「第二層打得開但按鈕沒有反應」與「第三層根本
不出現」這兩種不同的缺陷。

測試步驟：

1. 啟動 P20，按 `Open the menu`。
2. 按 `Level 1 item`，確認 `last action` 顯示 `level 1`。
3. 再次開啟選單，以滑鼠停留或點擊 `Level 2 submenu`。記錄是哪一種方式開啟——
   停留與點擊都屬合理行為，兩個 backend 可能不同。
4. 按 `Level 2 item`，確認 `last action` 顯示 `level 2`。
5. 開啟 `Level 3 submenu`，確認它確實出現。這是最可能在其中一邊失敗的步驟。
6. 按 `Level 3 item`，再操作 `Level 3 toggle`，確認兩者都傳達到 app：
   `last action` 顯示 `level 3`，且 `level 3 toggle` 翻轉。
7. 記錄每個子選單相對於其父層的落點，特別是靠近螢幕邊緣時。
8. 於另一個 backend 重複。

## 測試完成紀錄格式

建議每次測試後用以下格式記錄：

```text
Date:
Commit:
OS:
Swift:
App:
Result: Pass / Fail
Steps:
Observed:
Expected:
Logs:
Screenshots:
Notes:
```
