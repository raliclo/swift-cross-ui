# UI 測試計畫(正體中文)

**一種語言一個檔案,而這是中文的那一個。** 它原本是五份——整體計畫、缺陷計畫、Linux 計畫、
平台矩陣,以及結果紀錄——而英文那一半是另外五份。十個檔案裝兩份文件,意味著讀者必須先知道答案在
哪一份裡才查得到,而改一個步驟會有五個地方可能是它該待的位置。

**合併過程中沒有重寫任何內容。** 下面每一部分都是原本那些檔案之一:標題各降一級以嵌進所屬的部分、
原本的標題行被移除(因為部分標題已經取代了它)、原先各檔之間的互相引用改成連結。
其餘每一行都未更動。

**`UI-test-plan_zhTW.md`(WinUI P0-P6)刻意沒有併進來。** 它列在 `.git/info/exclude` 裡,
是一份**只存在於本機**的檔案;把它折進一個會被提交的檔案,等於替使用者決定把它發佈出去。
它仍在 `testapp/` 底下,原地未動。

英文那一半是 `UI-test-plan-en.md`。兩者不是逐行對譯——本來就不是。

## 各部分

- [整體計畫:P0-P41](#整體計畫p0-p41) — 每一支 app 的步驟,依序排列。最長的一部分,也是最先該讀的。
- [缺陷計畫:AppKit、UIKit 與 AndroidBackend](#缺陷計畫appkituikit-與-androidbackend) — 針對 Apple 與 Android backend 特定缺陷所寫的那些 app。
- [Linux 計畫:透過 WSL 的 GtkBackend](#linux-計畫透過-wsl-的-gtkbackend) — 工具鏈、各階段,以及一個 WSLg 的結果能證明什麼、不能證明什麼。
- [平台矩陣](#平台矩陣) — 哪個 issue 在哪裡跑,以及那個答案算不算數。
- [結果紀錄](#結果紀錄) — 帶日期的人工測試結果。那是一份執行紀錄,不是計畫。

---

## 整體計畫:P0-P41

本文件整理 `testapp` 測試程式的手動與輔助 UI 測試步驟。測試目標是快速重現與確認 WinUIBackend、GtkBackend、AppKitBackend、UIKitBackend 與 AndroidBackend 的 backend-specific issues。

### 測試前準備

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

### Windows 上的執行檔命名

每個 Windows 測試執行檔都以檔名後綴標示其 backend：`Pn-WinUI.exe` 是 WinUIBackend
build，`Pn-gtk4.exe` 是 GtkBackend build。沒有後綴的 `Pn.exe` 已不存在，因此以下每一
條執行指令都會明確指名其中之一。

這個後綴不是裝飾。2026-09-02 曾發生一次以視窗標題比對的截圖拍到了另一個 backend 的視
窗：兩種 build 註冊的標題相同，而兩個 `Pn.exe` 被複製到一起之後，檔名上再也沒有任何線
索可以分辨它們。後綴把 backend 放進執行指令、process 清單與檔名本身，讓拿錯 build 這件
事看得見，而不是無聲通過。

重新產生的指令：

```zsh
cd testapp && zsh compile.zsh          # -> testapp/output/Pn-WinUI.exe
cd testapp && zsh compile.zsh -gtk4    # -> testapp/output/Pn-gtk4.exe
```

有兩個 app 依設計只有單一 build：`P6` 是 D3D11 影片測試、且連結 WinUI 產品，因此沒有
`P6-gtk4.exe`；`P6-v2` 是純 GTK app，因此沒有 `P6-v2-WinUI.exe`。

### 跨平台測試流程

- Linux / GtkBackend 相關 issues 一律先測 WSLg，再用 Windows 作為對照（若該 app 支援）。
- 不要在 WSL 內從 `/mnt/c` 編譯。先同步 `testapp` 的 Swift/zsh 檔案，再於 `~/proj/swift-cross-ui` 下建置。
- 只使用 zsh scripts。目前 helper scripts 包含 `compile.zsh`、`rsync_WSL.zsh`、`screenshot.zsh`、`videoshot.zsh` 與 `test.zsh`。
- 透過 `zsh testapp/test.zsh Pn --both` 執行的自動 dry-run 會先跑 WSLg，再跑 Windows。每個平台預設會在 render 後保留視窗 30 秒，再拍 final screenshot，方便 tester 共同觀察並回報變化。
- 截圖會寫到 `testapp/output/screenshots`，檔名含平台與階段，例如 `p8-wslg-1s-...png`、`p8-wslg-final-...png`、`p8-windows-1s-...png`、`p8-windows-final-...png`。

### 共通觀察項目

- App 是否能開啟主視窗。
- Console 是否出現 fatal error 或 stack trace。
- 視窗是否可互動，按鈕、輸入框、選單是否回應。
- 關閉 app 後 process 是否正常結束。
- 若發生 crash，記錄：
  - 執行哪個 exe
  - 按下哪個控制項
  - crash 前最後一行 log
  - stack trace 中的 Swift / WinUIBackend 檔案與行號

### P0：Critical Lifecycle

執行：

```zsh
./testapp/output/P0-WinUI.exe      # WinUIBackend，Windows 上
```

涵蓋 issues：

- #493 (Fixed)：WinUIBackend 太早呼叫 environment action 可能 crash
- #548 (Fixed)：`@AppStorage` 在 Windows crash
- 無專屬 issue (Fixed)：WinUIBackend `setSizeLimits` unimplemented log
- 無專屬 issue (Fixed)：WinUIBackend `setIncomingURLHandler` unimplemented log

測試步驟：

1. 啟動 `P0-WinUI.exe`。
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

### P1：Dialogs And Sheets

執行：

```zsh
./testapp/output/P1-WinUI.exe      # WinUIBackend，Windows 上
```

涵蓋 issues：

- #523 (Fixed)：Windows file open/save dialog 顯示過慢
- #659 (Fixed)：Nested sheets not supported
- #660 (Fixed)：Sheets have default padding

測試步驟：

1. 啟動 `P1-WinUI.exe`。
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

### P2：Controls And Styling

執行：

```zsh
./testapp/output/P2-WinUI.exe      # WinUIBackend，Windows 上
```

涵蓋 issues：

- #449 (Fixed)：Picker options 更新不正確
- #471 (Fixed)：TextEditor unfocused thin border
- #401 (Fixed)：Window resizing disabled 時 full screen button 未停用
- #390 (Fixed)：Disabled buttons 視覺不明顯

測試步驟：

1. 啟動 `P2-WinUI.exe`。
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

### P3：Layout And Clipping

執行：

```zsh
./testapp/output/P3-WinUI.exe      # WinUIBackend，Windows 上
```

涵蓋 issues：

- #389 (Fixed)：Images are not clipped
- P3 三欄測試板初始 layout regression (Fixed)

測試步驟：

1. 啟動 `P3-WinUI.exe`。
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

### P4：WinUI Native And Callback Stress

執行：

```zsh
./testapp/output/P4-WinUI.exe      # WinUIBackend，Windows 上
```

涵蓋 issues：

- #190 (Fixed)：Callbacks stored in backend-wide hashmaps
- #156 (Fixed)：WinUI-specific escape hatch / native API
- #204 (Fixed)：Update to latest stable WinUI / WinUI console noise
- #470 (Fixed)：Regenerate WinUI bindings with latest swift-winrt

測試步驟：

1. 啟動 `P4-WinUI.exe`。
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

### P5：Multi-Window Alerts

執行：

```zsh
./testapp/output/P5-WinUI.exe      # WinUIBackend，Windows 上
```

涵蓋 issues：

- #675 (Fixed)：WinUIBackend 先前全 app 只能同時顯示一個 dialog（跨視窗會排隊，同視窗無法疊加）

測試步驟：

1. 啟動 `P5-WinUI.exe`。
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

### P7：Lists And Split Views（Linux）

執行：

```zsh
./P7
```

輔助 WSLg/Windows 對照流程：

```zsh
zsh testapp/test.zsh P7 --both
```

涵蓋 issues：

- #476 (Fixed)：GTK backend 上 List 一啟動就已選取第一項
- #556 (Monitoring)：Gtk List 的 NavigationSplitView 尺寸判斷異常

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
- detail 區可見且不會塌成零寬，且不因無關文字變動而改變分割。依 2026-09-01 量測，P7 在 WSLg 與 Windows 回報相同 split ratio：sidebar 200 / total 420，也就是 47.6%。若之後再失敗，視為新的 #556 repro，先保留診斷數字再改 backend。

### P8：Scroll Views（Linux）

執行：

```zsh
./P8
```

輔助 WSLg-first 流程：

```zsh
zsh testapp/test.zsh P8 --both
zsh testapp/test.zsh P8 --both --showtime 60
zsh testapp/test.zsh P8 --both --no-showtime
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

### P9：Text And Field Sizing（Linux）

執行：

```zsh
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

### P10：Hit Testing And Shortcuts（Linux）

執行：

```zsh
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
6. 點擊右側橘色方塊的中央，確認 `Hidden clicks` 會增加。該方塊完全**不透明**、將按鈕完全遮住，唯有 `allowsHitTesting(false)` 能讓點擊穿透——這正是使本步驟成為「對該 modifier 的測試」而非又一次透明度測試的原因。
7. 按 Ctrl-Q（macOS 為 Cmd-Q），確認 #478。

預期結果：

- 透明圖層不應阻擋點擊；若被覆蓋的按鈕需移除圖層才有反應，即為 #454。
- 套用 `allowsHitTesting(false)` 的不透明圖層同樣不應阻擋點擊；若 `Hidden clicks` 停在 0，代表該 modifier 沒有傳達到 backend。
- Ctrl-Q 應結束程式；若視窗仍開著即為 #478。

### P11：AppKit Sliders, Scrollbars And Pickers（macOS）

執行：

```zsh
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

### P12：Android Margins, Rotation State And Toggles（Android）

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

### P13：Layout And View Graph（AppKit/Gtk）

執行：

```zsh
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

### P14：UIKit Rotation And Theme（iOS）

編譯與執行：

```zsh
zsh testapp/compile.zsh -ios P14
xcrun simctl install swift-cross-ui testapp/output/P14-ios.app
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

### P15：Colour Scheme And Window Height（Linux）

執行：

```zsh
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

### P16：Split View Initial Layout（Windows）

執行：

```zsh
./P16-WinUI.exe
```

涵蓋 issues：

- #160 (Fixed)：WinUIBackend 的 NavigationSplitView 初次載入時 layout 錯誤，一旦有狀態變更或視窗縮放就會跳回正確

**先讀數字再動任何東西。** 這個 bug 由「第一次 render」定義，而縮放視窗正是兩種會修正它的操作之一，任何互動都會破壞證據。

測試步驟：

1. 啟動 `P16-WinUI.exe`，不要移動或縮放視窗。
2. 立刻記下 `sidebar` 與 `detail` 兩個 pane 顯示的尺寸。
3. 目視判斷版面是否明顯錯誤（例如 sidebar 佔滿、detail 被擠掉）。
4. 按 `Force update`，這只改變一個與版面無關的計數器。
5. 再次記下兩個 pane 的尺寸。步驟 2 與步驟 5 的差值就是 #160。
6. 重新啟動程式，這次改以拖曳縮放視窗來觸發，確認兩種方式都能讓版面修正。
7. 重新啟動後按 `Switch to 3 column`，對三欄版面重複步驟 2-5。
8. 在 Linux 上以 GtkBackend 執行同一支程式作為對照。

預期結果：

- 首次 render 的 pane 尺寸就應該正確，與強制更新後相同。
- 2026-09-01 驗證：WinUI `createSplitView` 初始設定 sidebar width 後，P16 首次 render 顯示 `sidebar: 180 x 22`、`detail: 660 x 22`，row 文字不再被壓窄換行。
- 若步驟 2 與步驟 5 的數字不同，即為 #160，且差值就是「錯得多離譜」的量化結果。
- actionfile 自動互動仍可能受 Windows desktop / foreground / elevation 狀態影響；若 Force update counter 沒變，先以人工點擊確認 state update 後 layout 是否穩定。
- 尺寸為即時顯示而非在首次 render 時寫入 state：在 layout 過程中寫 state 會回饋到它正在量測的 layout，而 `GeometryReader` 的文件也說明內容可能會以不同尺寸被評估多次。

### P17：Cross-Backend Layout Comparison（Linux 與 Windows）

執行：

```zsh
./testapp/output/P17          # WSL 上的 GtkBackend
./testapp/output/P17-WinUI.exe      # Windows 上的 WinUIBackend
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

### P6：Zstd Stream Player

編譯與執行：

```zsh
zsh testapp/compile.zsh P6
./testapp/output/P6-WinUI.exe      # WinUIBackend，Windows 上；P6 沒有 -gtk4 build
```

macOS 的輸出檔名可能是 `P6` 而不是 `P6-WinUI.exe`：

```zsh
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
`P6-WinUI.exe -f -autoplay -enable-dropframe` 完全不需要點擊任何按鈕。
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
- `testapp/.compile-work-<backend>/` 與 `testapp/output/` 屬於暫存區：`compile.zsh` 會把
  選定的原始碼複製到 `.compile-work-<backend>/TestApps/Sources/<name>/main.swift` 並
  產生對應的 `Package.swift`，因此這兩個目錄都不應納入 commit。後綴即 backend 名稱——
  `-winui`、`-gtk4`、`-appkit`、`-android`、`-ios`——不存在無後綴的樹。

測試步驟：

1. 啟動 `P6-WinUI.exe`，按 `Choose file`。
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

### P18：File Dialogs（Linux 與 Windows）

執行：

```zsh
./testapp/output/P18          # GtkBackend，於 WSL
./testapp/output/P18-WinUI.exe      # WinUIBackend，於 Windows
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

### P19：Flat Menus（Linux 與 Windows）

執行：

```zsh
./testapp/output/P19          # GtkBackend，於 WSL
./testapp/output/P19-WinUI.exe      # WinUIBackend，於 Windows
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

### P20：Nested Menus（Linux 與 Windows）

執行：

```zsh
./testapp/output/P20          # GtkBackend，於 WSL
./testapp/output/P20-WinUI.exe      # WinUIBackend，於 Windows
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

### P6-v2：Video Playback on GtkBackend（Linux 與 Windows）

執行：

```zsh
./testapp/output/P6-v2 -i <檔案> -autoplay              # GtkBackend，於 WSL
./testapp/output/P6-v2-gtk4.exe -i <檔案> -autoplay          # GtkBackend，於 Windows
```

請以 `-gtk4` 建置。在 Windows 上，P6 **不是**一般意義下的比較對象：P6 是 WinUI/D3D11 的
實作，而 `compile.zsh -gtk4` 會直接拒絕建置它，因為 SwapChainPanel 與 D3D11 composition
swap chain 在 GtkBackend 中沒有對應物。P6-v2 是同一個問題的 GTK 答案，採全新撰寫，並保留
P6 的量測語彙，使兩者的數字可以對齊。

重要旗標：

| 旗標 | 作用 |
|---|---|
| `-cpu` | 強制軟體解碼 |
| `-gpu` | 強制硬體解碼；若無可用者則拒絕啟動 |
|（預設） | 嘗試硬體，失敗則回退軟體，並明白說出實際執行者 |
| `-mute` | 不啟動 ffplay；量測執行時使用 |
| `-seconds N` | N 秒後結束並印出摘要 |
| `-speed` `-fps` `-res` | 預設各選單，使執行無需點擊 |

測試步驟：

1. 以 `-autoplay -seconds 20 --debug` 啟動，確認視窗有繪製。Windows 上該視窗不回應
   AppActivate，因此請以
   `zsh testapp/screenshot.zsh -w "P6-v2 GTK playback" <標籤>` 擷取——它直接讀取視窗本身，
   而非桌面。
2. 閱讀狀態列。它會分別陳述解碼路徑與呈現路徑——`decode d3d11va, present memory-texture
   (CPU)`。目前所有模式的呈現都是 CPU 路徑；旗標只切換解碼。
3. 確認音訊。它是獨立的 ffplay 行程，因此不保證同步：1x 時貼合到足以觀看，3x 時會飄移。
   這是預期行為。
4. 在相同速度、幀率與解析度下連續執行 `-cpu` 與 `-gpu`，比較兩份摘要。在本機上兩者的差距
   落在雜訊範圍內，因為瓶頸是 RGBA 管線的讀取，而非解碼。
5. 將速度推到 `3x` 並觀察 `dropped/sec`。只有當幀的到達速度快於可顯示速度時才會掉幀；單純
   慢於目標速率的解碼器會把每一幀都顯示出來，並回報較低的 fps。
6. 於另一平台重複並比較。WSL 完全沒有 GPU 路徑——缺少 render node，因此 GTK 跑在 llvmpipe
   上——所以此處的 Windows 對 WSL 比較，量的是兩套不同的繪製堆疊，而非兩個作業系統。

### P21：Input Controls（Linux 與 Windows）

執行：

```zsh
./testapp/output/P21          # GtkBackend，於 WSL
./testapp/output/P21-WinUI.exe      # WinUIBackend，於 Windows
```

目前未涵蓋範圍中最廣的一塊。ToggleSwitch、ToggleButton 與 Checkbox 完全沒有出現在任何其他
測試 app 中。每個控制項都出現兩次：啟用與停用。

測試步驟：

1. 按下 Button 區的 `Enabled`，確認 `clicks` 增加。
2. 按下 `Disabled`，確認 `clicks` **沒有**增加。「已停用卻仍接受輸入」正是此處要抓的發現，
   而它在截圖上看起來完全正確。
3. 逐一操作各種 toggle 樣式——一般、`.switch`、`.button`、`.checkbox`——操作啟用的那個，並
   確認停用的那個拒絕輸入。
4. 比較兩個 backend 如何呈現停用狀態：標籤變灰、整個 widget 變暗，或外觀完全不變。
5. 拖曳兩個 slider；停用的那個不得移動。
6. 於 `TextField`、`SecureField` 與 `TextEditor` 輸入文字，再試其停用版本。
7. 確認 `ContentUnavailableView` 同時顯示標題與說明文字。
8. 於另一個 backend 重複上述步驟。

### P22：Text Styles（Linux 與 Windows）

執行：

```zsh
./testapp/output/P22 --debug          # GtkBackend，於 WSL
./testapp/output/P22-WinUI.exe --debug      # WinUIBackend，於 Windows
```

值得優先進行，因為字型度量是其他所有版面比較的量尺。若某個 backend 的文字系統性地較寬，它
會在 P17 的尺寸檢查與 P7 的 split 比例中產生不同結果；少了這支 app，該差異會被歸咎於版面
程式碼而非字型。

測試步驟：

1. 以 `--debug` 執行，蒐集八個樣本各自回報的尺寸。這些是數字，而非對截圖的印象。
2. 逐一樣本比較兩個 backend。八個樣本呈現一致比例代表字型差異；只有單一字級不同則是版面
   缺陷。
3. 按 `Narrower` 與 `Wider`，記錄各寬度下的斷行位置。
4. 檢查固定 320pt 框內的三列對齊。
5. 於另一個 backend 重複上述步驟。

### P23：Tables（Linux 與 Windows）

執行：

```zsh
./testapp/output/P23 --debug          # GtkBackend，於 WSL
./testapp/output/P23-WinUI.exe --debug      # WinUIBackend，於 Windows
```

欄寬是有趣之處。API 中並未指定寬度，因此各 backend 自行決定：依標題、依最寬的儲存格、依第
一屏，或平分可用空間。第二欄刻意寬於其標題、第三欄則較窄，使當前採用哪一種規則一眼即可
分辨。

測試步驟：

1. 記錄各欄邊界落點，並判斷這代表四種規則中的哪一種。
2. 觀察第 3 列，其儲存格遠長於任何標題。記錄它是撐寬該欄，還是被截斷。
3. 按 `More rows` 超過視窗高度，確認表格是捲動還是裁切。
4. 按 `Fewer rows`，確認版面能恢復而非留下空缺。
5. 於另一個 backend 重複上述步驟。

### P24：Navigation Stack（Linux 與 Windows）

執行：

```zsh
./testapp/output/P24 --debug          # GtkBackend，於 WSL
./testapp/output/P24-WinUI.exe --debug      # WinUIBackend，於 Windows
```

`NavigationStack` 與 `NavigationLink` 未出現在任何其他測試 app 中。此缺口先前被以「P7 與
P16 已涵蓋導覽」為由劃掉，那是錯的：那兩支測的是 `NavigationSplitView`，屬於不同型別、不同
的版面模型。側邊欄加詳細內容的分割，並不等同於推入與彈出的堆疊。

堆疊有而分割檢視沒有的東西是「歷史」。

測試步驟：

1. 以 `Push level N` 推入三層，確認每一畫面都出現。
2. 逐層返回，確認依序退回。
3. 於每一層按下 `Record a push`，並將 `pushes recorded` 與畫面顯示的層級比對。該計數器刻意
   置於堆疊之外：若畫面顯示第 2 層而計數器顯示 3，該不一致就是發現。
4. 在深層按下 `Increment counter`，再返回，確認路徑在狀態變更後仍然存續。
5. 按 `Pop to root`，確認畫面與計數器同時歸零。
6. 於另一個 backend 重複上述步驟。

### P25：拖放（Linux 與 Windows）

執行：

```zsh
./testapp/output/P25 --debug          # WSL 中的 GtkBackend
./testapp/output/P25-gtk4.exe --debug      # Windows 上的 -gtk4 build
```

拖放未出現在任何其他測試 app，因為在 `onDrop(of:isTargeted:perform:)` 加入之前，SwiftCrossUI
並沒有相應的 API。值得詢問的是「兩平台有分歧空間」的問題，而非「拖放到底會不會抵達」：Windows
透過 `CF_HDROP` 傳遞路徑，X11 傳遞 `text/uri-list`，因此 `received` 一律原樣印出、永不正規化。

測試步驟：

1. 自檔案管理員拖曳一個檔案至接受區上方，確認它在**放開按鍵之前**即高亮。僅在放開後才反應的
   backend 雖可使用但並不正確，而少了可供對照之處便無從察覺。
2. 放下該檔案，確認 `state` 顯示 `accepted`、`count` 為 1，且 `received` 以平台原本交付的形式
   顯示酬載。
3. 將同一檔案拖至拒絕區上方，確認它**不會**高亮、也不回報任何內容。這正是設置兩個區域的理由：
   一個「默默吞掉無法處理之物」的放置區，與一個明確拒絕的放置區，在並排之前看起來完全相同。
4. 一次放下多個檔案，記錄它們是以多個項目抵達，還是合併為單一字串。
5. 於另一個平台重複，並比較兩者的 `received` 值。

註記：此項無法以動作檔驅動。拖放是作業系統層級的協商，而非一連串滑鼠事件，`InputEvent` 無法合成
它；步驟 1 起皆需要一次真實的拖曳。

### P26：網路與 App Cache（Linux 與 Windows）

執行：

```zsh
./testapp/output/P26 --debug
zsh testapp/test.zsh P26 --cache-only   # 不開視窗，只做快取斷言
```

涵蓋 `AsyncImage`、`appCache` 與網路功能比較表。與其他每一個 Pn 不同，本項有一半的行為唯有跨多次
執行才觀察得到——快取要證明自己，靠的是「第二次抓取時什麼都沒下載」。

測試步驟：

1. 在沒有快取的情況下啟動，確認圖片載入，且快取目錄於首次抓取時建立。
2. 重新啟動，確認沒有任何下載，且圖片仍然出現。
3. 檢查 `not_latest` 欄位回報的是「過期」而非刪除該項目——快取副本必須能在抓取失敗後存活，否則
   一旦離線，便會失去它原本要保護的內容。
4. 切換至 SwiftUI 分頁，確認它在 Linux 上不渲染任何內容，這是正確的：SwiftUI 在該平台不存在。
5. 確認 Summary 表格的儲存格可被選取與複製。

### P27：Backend 功能覆蓋（Linux 與 Windows）

執行：

```zsh
zsh testapp/test.zsh P27 --both
```

涵蓋 backend 功能缺口；缺席時應暴露為可見 fallback 或診斷行為，而不是 silent no-op 或 hard crash。

缺少的 backend conformance 會經由 `@CastBackend`，被轉為
`fatalError("'GtkBackend' does not implement ...")`。因此含有 `WebView` 的 app 會在該 view 進行
版面配置的當下中止，`AngularGradient` 亦然——在 Linux 與 Windows `-gtk4` 上皆如此。AppKit 兩者
皆有實作。

測試步驟：

1. 顯示一個 `WebView`，確認 app 不會中止。
2. 將 `AngularGradient` 與 `LinearGradient`、`RadialGradient` 並排顯示，確認三者皆能渲染。
3. 於 WinUIBackend 與 AppKit 重複並比較。
4. 確認「backend 確實無法提供的功能」會以可見的方式降級（例如空白區域）而非中止——這正是本 app
   存在所要迫使做出的決定。

### P28：控制項樣式（Linux 與 Windows）

**已規劃，尚未撰寫。** 涵蓋「在 debug build 中觸發 assert、在 release 中悄悄降級」的樣式。

GtkBackend 的 `supportedPickerStyles` 僅為 `[.menu]`，而 AppKit 為
`[.menu, .segmented, .radioGroup]`；`supportedDatePickerStyles` 則缺少 `.compact`。樣式 modifier
會觸發 `assertionFailure` 並退回 `.automatic`，因此 `.pickerStyle(.segmented)` 會使 debug 的 GTK
build 崩潰，並在 release 中悄悄變成下拉選單——一個與其他所有平台外觀都不同的控制項。

規劃的測試步驟：

1. 每種樣式各顯示一個 picker——`.menu`、`.segmented`、`.radioGroup`、`.palette`——記錄哪些如實
   渲染、哪些悄悄變成下拉選單。
2. 對 `.datePickerStyle(.compact)` 與 `.graphical` 做相同比對。
3. 確認 debug build 不會因不支援的樣式而中止。
4. 設定 `displayedComponents: .hourAndMinute`，確認出現時間輸入。GtkBackend 目前會記錄
   `time picker is unimplemented` 並顯示一個純月曆格線，且使用錯誤的曆法與時區。
5. 將以上全部與 WinUIBackend 比較。

### P29：視覺保真度（Linux 與 Windows）

執行：

```zsh
zsh testapp/test.zsh P29 --both
```

涵蓋「某個 backend 輸出錯誤、卻完全沒有任何診斷訊息」的情況——那是日誌永遠不會揭露的失敗。

測試步驟：

1. 顯示一個沒有值的不確定進度 `ProgressView()`。GtkBackend 會把 fraction 設為零且從不 pulse，
   因此渲染為靜止的空白進度條，看起來像「卡住」；AppKit 與 WinUI 會使其動態呈現。
2. 將一張超尺寸圖片放入 `.cornerRadius(20)`。GtkBackend 的裁切為矩形，因此圓角邊框之下的角落
   仍是方的；AppKit 與 WinUI 會裁切成圓角形狀。
3. 顯示一個各列具明確 `.frame(height:)` 的 `List`，比較渲染高度與版面配置。GtkBackend 會丟棄
   收到的列高，並回報零基礎內距，而主題實際上加了真實的內距，因此該 list 的量測與其繪製並不一致。
4. 將 `TextEditor` 置於 `.disabled(true)` 之中，確認無法輸入。GtkBackend 從未對它設定
   `sensitive`。
5. 比較 `.fontWeight(.semibold)` 與 `.bold`；在 GtkBackend 上兩者對應到相同的 CSS 字重。

### P30：效果與動畫（Linux 與 Windows）

**已撰寫 baseline app，並已在 WSLg 與 Windows smoke test。** 涵蓋協定層最大的缺口：
SwiftCrossUI 完全沒有動畫層；目前只能測專案中已存在的 effect modifiers。

沒有 `Animation`、`withAnimation`、`.animation(_:value:)`、`.transition` 或 `Namespace`，也沒有
任何相應的 backend 協定。~~visual effects 與 geometric effects 現在已有部分覆蓋，但 backend
parity 仍不完整：~~GtkBackend 會 render blur 與 color filters，~~WinUIBackend 目前只套用
opacity~~——**2026-09-02 起已被取代**（保留不刪，讓過時主張留在紀錄裡）：WinUIBackend 現已透過
Win2D effect graph render 全部七項，2026-09-02 驗證為 `applied=8 failed=0 total=8`（重跑指令：
`cd testapp/output && SCUI_DEBUG_VISUAL_EFFECTS=1 ./P39-WinUI.exe`，再讀
`winui-visual-effects-debug.log`）。**同樣於 2026-09-02 被取代：這兩個效果系列在已出貨的桌面與
行動目標上現已達成完整的 backend parity。** AppKitBackend 兩者都已實作——一條 `CIFilter` 鏈與一個
`CATransform3D`；UIKitBackend 兩者也都已實作，其 visual effects 是透過 Core Image 作用於
`CALayer.render(in:)` 的點陣圖，而不是透過 `CALayer.filters`——後者在 iOS 上不參與合成。已於 P39
與 P40 驗證，詳見該兩節。
`.shadow`、`.zIndex`、`.clipShape` 與 `.mask` 仍不存在。SwiftUI 中每一次狀態變更都隱含可動畫化，
因此 animation 仍是本工具組中最大的行為分歧。

本 app 起初是功能完成前的邊界文件，現在則是已存在 effect APIs 的可編譯 baseline。後續仍用它區分
「API 不存在」與「API 存在但某個 backend render 成 no-op」。

目前自動流程：

```zsh
zsh testapp/test.zsh P30 --both
```

app 會顯示可編譯的 visual/geometric effect 範例，並把缺少的 animation API 以文字列在畫面上。
以 `--debug` 執行時會寫入 `p30-debug-events.log`。~~目前 WinUI 支援是 partial：opacity 已實作；
blur、grayscale、saturation、brightness、contrast、hue rotation 已確認仍是 no-op，直到 backend
建立真正的 Composition / Win2D effect graph。~~
**2026-09-02 起已被取代：** 上面劃掉的那句刻意保留而非刪除，因為它在當時對該版 binary 是成立的，
留著才看得出「看似合理但如今已為假」的主張長什麼樣子。WinUI 現已七項全部實作：
`WinUIBackend+VisualEffects.swift` 建立了真正的 Win2D effect graph（`Win2DEffectGraph`），
`Microsoft.Graphics.Canvas.dll` 也隨 `testapp/output/` 一起出貨。2026-09-02 驗證：
`applied=8 failed=0 total=8`——此數字的重跑指令為
`cd testapp/output && SCUI_DEBUG_VISUAL_EFFECTS=1 ./P39-WinUI.exe`，再讀
`winui-visual-effects-debug.log`。

測試步驟：

1. 切換一個會改變 frame 的 `@State` 值，確認該變更是瞬間完成（目前行為）還是帶有動畫。
2. 將 opacity、blur、grayscale samples 與 control 比較。
3. 將 offset、scale、rotation samples 與 control 比較。
4. 確認 animation-only APIs 仍以 missing API 文字記錄，而不是放入無法編譯的 sample code。
5. 若 AppKit backend 在測試範圍內，將每一項與 AppKit 下的相同程式碼比較。

### P31：焦點與鍵盤（Linux 與 Windows）

**已撰寫 baseline app，並已在 WSLg 與 Windows smoke test。** 本 app 要檢查的內容約有一半
現在就能寫；另一半仍是一份「無法編譯的呼叫清單」。

SwiftCrossUI 中沒有任何東西提到焦點。沒有 `@FocusState`、沒有 `.focused(_:)`、也沒有
`.focusable()`，因此 app 無法指定哪個欄位起始取得焦點、無法在按下按鈕後移動焦點，也無法讀取
焦點目前落在何處。平台預設怎麼做，就是全部的行為。

鍵盤捷徑是同樣的形狀。沒有 `.keyboardShortcut`、沒有 `KeyEquivalent`、也沒有 `EventModifiers`。
`Commands` 與 `CommandMenu` 確實能建出選單列，但它們會解析成 `ResolvedMenu.Item`，其 `button`
case 只帶有一個標籤與一個 action，別無其他——沒有任何欄位可以承載 key equivalent，所以這個缺口
在資料結構，而不只在 modifier。`CommandGroup` 則完全不存在。

有兩項 backend 行為值得單獨量測。GtkBackend 只安裝了一個加速鍵：`installQuitShortcut()` 中將
`<Control>q` 綁定至 `app.quit`；那是整個工具組唯一建立的按鍵綁定。而 `createAlert()` 會掛上一個
shortcut controller 來吃掉 `Escape`，使其無法關閉對話框，回應處理器也會丟棄 GTK 的 delete-event
回應。兩者都是刻意為之，而且在 app 真正按下該鍵並回報結果之前，兩者都不可見。

測試步驟：

1. 在一個含 `TextField`、`Button`、`Toggle` 與 `Slider` 的視窗中按 Tab 巡覽，記錄焦點造訪的順序，
   以及取得焦點的控制項是否有可見標示。這完全是平台自身的行為，因此此處的差異是 GTK 對 WinUI 的
   差異，而非 SwiftCrossUI 的差異。
2. 對每個取得焦點的控制項按 Space 與 Return，記錄哪些會被觸發。「可到達但無法用鍵盤操作」的控制項
   在截圖上看起來完全正確。
3. 按 Ctrl+Q。在 GtkBackend 下 app 必須結束。在 WinUIBackend 下應該毫無反應，因為沒有安裝對應的
   綁定；該不對稱本身就是發現，而不是任一 backend 的缺陷。
4. 開啟 alert 並按 Escape，確認對話框仍然開著。接著按下它的其中一個按鈕，確認回應有抵達。
   「Escape 毫無作用」與「Escape 關掉了對話框卻沒有回報任何回應」是不同的失敗，唯有事後再按一次
   按鈕才能把兩者分開。
5. 僅用鍵盤到達某個 `CommandMenu` 項目——透過選單列自身的巡覽，因為沒有任何項目能宣告捷徑。記錄
   需要幾次按鍵。
6. 把無法編譯的呼叫清單留在 app 之中：`@FocusState`、`.focused($field)`、`.focusable()`、
   `.keyboardShortcut("s", modifiers: .command)`、`CommandGroup(replacing: .newItem) { ... }`。
   每有一行開始能夠編譯，即為進度報告。
7. 於另一個 backend 重複上述步驟。

自動流程：

```zsh
zsh testapp/test.zsh P31 --both
```

自動流程只驗證啟動、render marker、final screenshot 與可見 baseline controls。真正的焦點巡覽、
Escape 行為與 Ctrl+Q 仍需要人工鍵盤互動確認。

#### 2026-09-03 於 Windows / GtkBackend 實測——步驟 1、2 通過，步驟 4 無法執行

以 `testapp/actions/win/P31-tab-and-escape.csv` 驅動；這是本樹中第一個真的對對話框按下按鍵的動作檔。

重新產生：`zsh testapp/run.zsh P31 -actionfile testapp/actions/win/P31-tab-and-escape.csv`，
再讀取**你執行該指令所在目錄下**的 `p31-debug-events.log`——見下方說明，它不在 `testapp/output/`。

- **步驟 1 與 2 通過。** `key tab` 把焦點移出 `TextField`，緊接的 `key space` 觸發了按鈕：
  `p31-debug-events.log` 記錄了 `button clicked count=1`。因此 Tab 巡覽與 Space 觸發在
  Windows/GtkBackend 上**確實存在**。由於 SwiftCrossUI 完全沒有 focus API，這一切都是平台自身的
  行為——正如步驟 1 所預期，而這是第一次被實際量到，而非被假定。
- **步驟 4 無法由動作檔執行，因此那不是一項 P31 的結果。** Escape 確實沒有關閉 alert，但該次執行
  無法告訴你 GTK 是否如 `createAlert()` 所意圖地吃掉了該按鍵，因為**按鍵從未抵達對話框**。
  `Win32Synthesiser.ownWindow()` 挑選本行程中面積最大的可見 top-level 視窗，而
  `Gtk.MessageDialog` 是較小的獨立 top-level 視窗，因此永遠選不到；合成器接著又對主視窗呼叫
  `SetForegroundWindow`，把焦點從 modal 手上拿走。完整記述見 `bugs/Gtk4-bugs.md` 第 6 節。
  **在該問題修好之前，步驟 4 維持為人工步驟；重放沒有回報錯誤，對任一方向都不構成證據。**
- **步驟 3、5、6、7 在本平台上仍未量測。**

**Escape 不是一種可攜的 modal 關閉方式。** `testapp/actions/mac/README.md` 之所以推薦 Escape，
正是因為它「無需座標即可抵達 key window」，而這在 macOS 上為真。**在 Windows 上則為假**，理由如上：
按鍵被送往一個「以面積挑出來」的視窗，而非那個處於 modal 狀態的視窗。請勿把 mac 動作檔中的 Escape
列直接搬到 `win/`，並把「沒有回報錯誤」讀成通過。

**P31 的 log 落在哪裡。** P31 以 `FileManager.default.currentDirectoryPath` 組出路徑，因此
`p31-debug-events.log` 會落在啟動它的那個目錄——透過 `testapp/run.zsh` 驅動時就是 repo 根目錄，
而不是 `testapp/output/`。這並非 P31 特有：**`testapp/P*.swift` 中會寫 debug log 的 35 支 app
全部使用 `currentDirectoryPath`**，`splitview-debug.log` 亦然
（`Sources/SwiftCrossUI/Views/SplitView.swift:215`）；其餘 12 支則完全不寫 log。可用
`grep -c currentDirectoryPath testapp/P*.swift` 重新推導。因此此處只有**一種**慣例，不是兩種——
mac 文件寫成 `testapp/output/p28-debug-events.log` 之所以正確，只是因為該流程會先 `cd` 進
`testapp/output`，而 `run.zsh` 是以絕對路徑啟動、從不切換目錄。

### P32：無障礙（Linux 與 Windows）

**已撰寫 baseline app，並已在 WSLg 與 Windows smoke test。** 本 app 不呼叫任何缺席的東西，
它存在的目的是被外部工具檢視。

SwiftCrossUI 沒有無障礙 API。沒有 `.accessibilityLabel`、`.accessibilityHint`、
`.accessibilityValue`、`.accessibilityAddTraits`、`.accessibilityHidden`、`.accessibilityElement`
或 `.accessibilityIdentifier`，也沒有任何對應的 backend 協定，因此沒有任何 backend 能被要求設定
其中之一。最接近的是 `.help(_:)`，它經由 `BackendFeatures.Tooltips` 設定滑鼠停留提示；UIKitBackend
會額外由它指派 `accessibilityHint`，GTK 與 WinUI 則不會。

這並不代表無障礙樹是空的。GTK 提供 AT-SPI、WinUI 提供 UI Automation、AppKit 提供 NSAccessibility，
三者都會給 widget 一個預設角色，而且通常會由其標籤取得預設名稱。因此本 app 要回答的問題不是「有沒有
無障礙」，而是「在沒有 API 的情況下還剩多少」：哪些元素會出現、哪些帶有可用的名稱、哪些只是匿名的
方框。這份基線正是日後任何標示 API 的比較對象，而且必須在該 API 出現之前先記錄下來，否則將無可比對。

測試步驟：

1. 建一個視窗，內含一個有標籤的 `Button`、一個沒有文字的純圖示 `Button`、一個帶提示文字的
   `TextField`、一個 `Toggle`、一個 `Slider`、一個 `ProgressView` 與一個 `Image`。
2. 在 Linux 上以 Accerciser 讀取該樹，記錄每個元素的角色與名稱。
3. 在 Windows 上以 Accessibility Insights 或 `inspect.exe` 讀取同一個視窗，記錄每個元素的控制項型別
   與 Name。
4. 逐一元素比較兩份清單。只出現在其中一個平台的元素是 backend 缺口；兩邊都出現但名稱為空的元素，
   才是本節所談的 API 缺口，兩者需要的修法並不相同。
5. 對純圖示按鈕套用 `.help("...")`，記錄該文字是抵達無障礙樹、僅止於提示框，還是兩者皆非。兩個平台
   都要檢查；它們的程式路徑並不共用。
6. 以螢幕閱讀器操作該視窗——Linux 用 Orca、Windows 用 Narrator——並逐字寫下它對純圖示按鈕的朗讀
   內容。今日的預期結果是「Button」而沒有名稱；請記錄確切的朗讀字串，而非它的摘要。
7. 確認朗讀順序與視覺順序一致。版面容器可能在樹中重排子元素而完全不改變繪製結果，畫面上看不出來。

自動流程：

```zsh
zsh testapp/test.zsh P32 --both
```

自動流程只驗證 baseline controls 有渲染出來。角色與名稱檢查仍需在 Linux 使用 Accerciser，在
Windows 使用 Accessibility Insights 或 `inspect.exe`。

### P33：缺席的 Views（Linux 與 Windows）

**已撰寫 baseline app，並已在 WSLg 與 Windows smoke test。** 涵蓋在 SwiftCrossUI 中完全沒有
對應物的 SwiftUI views——移植過來的程式碼是無法編譯，而非渲染不同。

~~`Sources/SwiftCrossUI/Views` 底下沒有 `Form`、`Section`、`Label(_:systemImage:)`、`Stepper`、
`Gauge`、`DisclosureGroup`、`LabeledContent`、`ColorPicker` 或 `Link` 之中的任何一個。~~

**九個全部存在。2026-09-09 重新推導**,使用的是 `todo.md` 中「Re-derived 2026-09-09」一節所記錄的
那道與型別形狀無關的迴圈——它回報 16/17 個常見 view 存在,並且**自帶對照組**(`VStack` 必須回 1、
`ZZZNotARealType` 必須回 0)。該普查中唯一缺席的名稱是 `LazyHGrid`。

這是目前在這棵樹裡找到的**最大一筆過期主張**——九個名字,全部是錯的,而且方向全都是「工作其實早就
做完了」。此處以劃線保留而非刪除,因為它教的不是「這九個存在」,而是**這種清單如何腐化**:它寫下時
是對的,之後沒有任何東西重跑過它,而那九個各自分別落地,期間沒有人打開過這份說它們不存在的文件。

保留其後的推理,因為它對 `Section` 依然正確,也正是 `Section` 值得最先被做掉的理由:在 SwiftUI 中它
與其說是一個獨立的 view,不如說是 `List`、`Form`、`Picker` 與 `Menu` 共同接受的結構元素,因此它的
缺席會弄壞那些「看起來與 section 無關」的呼叫點。其餘各自只影響一個呼叫點。

**這一步現在是什麼。** 不再是「記錄九個缺口」,而是**驗證那九個在此 backend 上真的畫得出來**。
「存在」與「畫得出來」是兩種不同的主張,而測試計畫要驗的是後者。

目前自動流程：

```zsh
zsh testapp/test.zsh P33 --both
```

app 會顯示 missing-view 清單，並以手寫方式近似 Stepper、DisclosureGroup 與 LabeledContent。
刻意缺席的 SwiftUI 呼叫點目前以文字記錄，而不是保留為會破壞 build 的程式碼。

測試步驟：

1. 每個缺席的 view 各顯示一個實例，記錄哪些能通過編譯。本 app 一開始就是一個無法 build 的檔案，
   而「被迫註解掉的行」的清單就是量測結果。
2. 對 `Section`，分別測試全部四種容器——`List`、`Form`、`Picker`、`Menu`。「在其中一種可用、其餘
   不可用」與「哪一種都不可用」是不同的結果。
3. 對可以手工近似的 view——`Stepper` 以兩個按鈕加一個標籤、`LabeledContent` 以一個 `HStack`——在缺口
   旁邊做出近似版本，記錄它要花幾行，以及它仍然做不到什麼：鍵盤可達性、與相鄰列的對齊、停用狀態。
4. ~~`Label(_:systemImage:)` 需要一個系統圖示，而 `Image(systemName:)` 同樣不存在（見 P36）。記錄
   「只有文字的退路」是否可接受，或這兩個缺口必須一起補上。~~
   **兩者現在都存在,2026-09-09 查證:`Label` 的 `public init(_ title: String, systemImage: String)`
   位於 `Views/Label.swift:143`,`Image(systemName:)` 位於 `Views/Image.swift:62`。** 這一步因此不再是
   「記錄一個缺口」,而是「驗證那兩者在此 backend 上真的畫得出符號」——那是不同的工作,而且是要**跑**
   的,不是要查的。
5. 將每一項與 AppKit 下的相同程式碼比較。

### P34：Lazy 容器與大型集合（Linux 與 Windows）

**已撰寫 baseline app，並已在 WSLg 與 Windows smoke test。** 涵蓋「集合大於顯示它的視窗」
時會發生什麼事。

~~沒有 `LazyVStack`、`LazyHStack`、`LazyVGrid`、`LazyHGrid` 或 `Grid`，也沒有 `ScrollViewReader` 或
`ScrollViewProxy`。~~ **那七個裡現在有六個是存在的。2026-09-09 重新查證，仍然缺席的只有
`LazyHGrid`(任務 #118)。** `LazyVStack`、`LazyHStack`、`LazyVGrid` 與 `Grid` 皆已於 2026-09-08
之前落地，`ScrollViewReader`／`ScrollViewProxy` 則在 2026-09-09——並已由
`actions/win/P34-scroll-to-row-50.csv` 在 Win-gtk4 上驅動並驗證：其 log 為
`scrollTo row 50 requested, anchor top`，其擷圖顯示最上方可見列由 `Row 0` 變為 `Row 50`。因此被
劃掉那段的最後一句——「同樣也沒有以程式捲動至特定列的方法」——現在是錯的，而那正是整段的結論。

**保留被劃掉的文字，是因為它「錯得下去」的方式。** P34 自己畫在畫面上的標籤帶著同一份清單與同一個
錯誤，於是一位拿執行中的 app 來對照本文件的讀者，會發現兩者互相吻合。**同一個過期主張的兩份副本
並不互相佐證，只會讓它更難被懷疑。** 它是靠逐一去問原始碼樹、並附上對照組(`VStack` 找得到、
`ZZZNotARealType` 不存在，證明搜尋本身有效)才被抓到的。

仍然成立的部分：`VStack` 與 `HStack` 會建出每一個子項，而 `ScrollView` 只捲動交給它的東西，因此
放在 `ScrollView` 內的集合是完全實體化的：10,000 列就是 10,000 個 widget，無論其中有沒有任何一個
在畫面上。**`LazyVStack` 與 `LazyHStack` 並未改變這件事**——它們存在，但不是惰性的；版面與
`VStack`／`HStack` 完全相同，所有子項仍舊預先建立。這一點見任務 #85，當時判定為「已記錄的分歧」
而非 bug；而 #117 談的是虛擬化 `List`，那才是平台 widget 本來就會回收的地方。

「感覺很慢」不是發現。本 app 由命令列接收列數並印出數字，因此結果是一張表格，而不是一種印象。

目前自動流程：

```zsh
zsh testapp/test.zsh P34 --both
```

loader 目前使用 `--debug -rows 100` 做快速 smoke pass。若要量測 first-paint 時間與記憶體，需明確
用更大的 row count 重新執行。

測試步驟：

1. 以 100、1,000、10,000 與 100,000 列各執行一次，記錄各自從啟動到首次繪製的時間。四個點足以看出
   形狀：與列數成正比的成長代表完全實體化；持平則代表某處出現了預期之外的 lazy 行為，應該找出它。
2. 於同一批執行中記錄尖峰 resident set size。單看時間無法分辨「把全部東西慢慢建出來」與「把全部
   東西建出來並且留著」，而記憶體數字正是區分兩者的依據。
3. 量測 10,000 列時的捲動延遲——從捲動事件到反映該事件的那一幀之間的時間——並與 100 列比較。積極
   建構付出的是啟動時間；它未必付出捲動成本，把兩者混為一談會把成本歸給錯誤的原因。
4. 找出 app 開始失敗的列數，並記錄它「如何」失敗：拒絕啟動、配置記憶體失敗、X11 或 WinUI 的 widget
   數量上限，或單純是長到無法使用的啟動時間。各種情況的解法不同，因此失敗模式與那個數字同樣重要。
5. 寫下 `ScrollViewReader { proxy in ... }` 並記錄編譯錯誤，接著以工具組現有的任何手段跳至第 5,000
   列，並記錄那樣做的代價。
6. 於另一個 backend 重複。GTK 與 WinUI 的 widget 建立成本不同，因此兩條曲線預期會在斜率上有差異，
   而不只是整體偏移。

### P35：狀態與 Scene 組合（Linux 與 Windows）

**已撰寫 baseline app，並已在 WSLg 與 Windows smoke test。** 涵蓋那些讓 SwiftUI app 的
「結構」無法被表達的缺口——與外觀無關。

`@State`、`@Binding`、`@Environment` 與 `ObservableObject` 都存在。`@StateObject` 與 `@ObservedObject`
不存在，因此參考型別的 model 沒有可用來觀察它的 property wrapper。`@SceneStorage` 同樣不存在，
`Binding.constant(_:)` 也沒有，而 `.environmentObject(_:)` 亦未作為環境 modifier 的別名提供。

Scene 這一側更偏結構。`Scene` 只宣告了 `associatedtype Node`——沒有 `var body: some Scene`，因此
scene 無法像 view 由其他 view 組成那樣，由其他 scene 組成。`SceneBuilder` 僅提供 `buildBlock`：
沒有 `buildIf`、沒有 `buildOptional`、沒有 `buildEither`。因此 `App.body` 中的 `if` 無法編譯，這排除了
「有條件地開啟視窗」這個 SwiftUI 常見寫法。`ViewBuilder` 確實有 `buildIf` 與 `buildEither`，但沒有
`buildLimitedAvailability`，所以 `if #available` 在 view body 中同樣不可用。

目前自動流程：

```zsh
zsh testapp/test.zsh P35 --both
```

app 會測一個簡單的 `@State` counter/toggle，並列出目前仍無法表達的 state/scene API。scene 組合
仍屬編譯期缺口，因此本測試主要是追蹤 baseline。

測試步驟：

1. 宣告一個符合 `ObservableObject` 且帶有 `@Published` 屬性的 class，試著先以 `@StateObject`、再以
   `@ObservedObject` 持有它。記錄哪些能編譯；對能編譯者，記錄變更該 published 屬性是否會重繪 view。
2. 寫一個 `body` 中含有 `if showSecondWindow { WindowGroup ... }` 的 `App`，記錄編譯錯誤。失敗點在
   `SceneBuilder`，不在視窗型別，錯誤訊息是否如此陳述必須確認——把責任指向錯誤型別的訊息，會把下一個
   人送去錯誤的檔案。
3. 在 view body 中寫 `if #available(macOS 14, *) { ... }`，同樣記錄其錯誤。它與步驟 2 缺少的是不同的
   需求、位於不同的 builder，兩者不應被歸成同一個 issue。
4. 將 `Binding.constant(true)` 傳給 `Toggle` 並記錄錯誤，再傳 `Binding(get: { true }, set: { _ in })`
   並確認可用。後者就是替代寫法，而它的存在正是使這成為便利性缺口、而非功能性缺口的原因。
5. 設定一個值，關閉視窗再重新開啟，記錄該值是否存續。既然沒有 `@SceneStorage`，就沒有東西會還原它；
   請確認實際情況確實如此，而不是由「API 缺席」直接推論。
6. 於另一個 backend 重複。這些都是編譯期缺口，因此結果應該完全相同。若有差異，代表此處有東西是依
   backend 而定的，值得把它找出來。

### P36：API 形狀相容性（Linux 與 Windows）

**已撰寫 baseline app，並已在 WSLg 與 Windows smoke test。** 涵蓋「view 存在，但 SwiftUI 的
呼叫點無法編譯」的情況。本節中的每個缺口在功能清單上都不可見，因為型別在，只有 initialiser 不在。

- `Picker` 是 `Picker(of: [Value], selection: Binding<Value?>)`。沒有 label 參數、沒有 `@ViewBuilder`
  內容、也沒有 `.tag`，而且 selection 必須是 `Optional`，因此對非 optional 的 `@State` 做選取需要一個
  橋接用的 binding。
- `Button` 是 `Button(_ label: String, action:)`。沒有 trailing-closure 形式的 label，因此
  `Button { ... } label: { Image(...) }` 寫不出來。
  ~~「也沒有 `ButtonRole`，因此 `.destructive` 根本無從表達。」~~——**假,2026-09-09 重新推導。**
  `ButtonRole` 位於 `Values/ButtonRole.swift`,`Button` 接受 `role:`,而 `EnvironmentValues` 也承載它。
- `Text` 接受 `String`。沒有 `LocalizedStringKey`，因此沒有 markdown，也沒有 `Text` + `Text` 串接。
  (`.textCase` **確實存在**,位於 `Modifiers/Style/TextCaseModifier.swift`。)
- `Image` 接受 `URL` 或 `ImageFormats.Image<RGBA>`,~~也沒有 `Image(systemName:)`~~——**假,
  2026-09-09:`public init(systemName:)` 位於 `Views/Image.swift:62`。** 仍然沒有 bundle 資產查找,
  因此移植後 app 中以檔案為來源的圖片仍需要一個路徑。
- `List` 的每一個 initialiser 都要求 `selection:`，並限制 `Data.Index == Int`。~~沒有 `Section`~~
  ——**假,`Views/Section.swift` 存在。** 仍然沒有 `.onDelete`、也沒有 `.swipeActions`。
- `TextField` 沒有 `axis:`、沒有 `prompt:`、也沒有 `value:format:`。(`.textFieldStyle` **存在**,
  五個 backend 皆有——那是已關閉的任務 #31。)

> **本節有四項主張在 2026-09-09 重查時是假的,方向全部是「其實早就實作了」,而
> `testapp/plan/parity-gaps-survey.md` 早已把其中三項連同檔案與行號正確記錄下來。這棵樹裡,一份文件
> 握有正確答案、另一份握有錯誤答案,而沒有任何東西標示哪一份比較舊。** 此處以劃線保留而非刪除,因為
> 「一個看似合理的過期主張長什麼樣子」才是有用的部分。**更正一項主張時,請 grep 它——你眼前這一份,
> 很少是唯一的一份。**
- 幾何量是 `Int`：`padding(_ amount: Int?)`、`cornerRadius(_ radius: Int)`、`HStack(spacing: Int?)`。
  SwiftUI 全程使用 `CGFloat`，因此移植程式中的 `.padding(8.5)` 是編譯錯誤，而不是捨入差異。

目前自動流程：

```zsh
zsh testapp/test.zsh P36 --both
```

app 會把目前可用的 SwiftCrossUI 寫法渲染出來，旁邊列出仍無法編譯的 SwiftUI-shaped calls。這樣
可以讓 porting cost surface 可見，同時不破壞一般測試 build。

測試步驟：

1. 把上述每一段 SwiftUI 宣告原封不動放入 app，記錄它產生的編譯錯誤。錯誤訊息本身就是產出；「無法編譯」
   不足以讓任何人據以行動。
2. 在每一項旁邊，寫出確實能編譯、且最接近同樣結果的 SwiftCrossUI 寫法，並記錄行數差。該差值即為移植
   成本，也是本節存在所要產出的數字。
3. 對 `Picker`，以 `@State` 持有一個非 optional 的 selection，記錄當 picker 的 selection 變成 `nil` 時
   橋接 binding 必須做什麼。既然沒有 `.tag`，請確認 selection 實際上是依什麼身分比對的——值本身的
   `Equatable` conformance。
4. 對整數幾何量，分別設定 spacing 為 `8` 與 `9`，量測各 backend 下渲染出的間距。若某個 backend 會依
   display factor 縮放，那麼該整數就不是像素數，捨入發生在別處；請記錄發生於何處，因為只檢查「8 小於 9」
   的測試在兩種情況下都會通過。
5. 記錄 `Image(systemName: "gear")` 究竟是編譯錯誤，還是執行期的一片空白。功能清單無法分辨兩者，而
   「無聲的空白」是其中較糟的一種。
6. 於另一個 backend 重複。凡是在其中一邊能編譯、另一邊不能的東西，都是依 backend 而定的 API，與本節
   其餘內容屬於不同的發現。

### P37：視窗層級（Linux 與 Windows）

執行：

```zsh
zsh testapp/run.zsh P37                    # Windows 上的 GtkBackend
./testapp/output/P37-WinUI.exe                   # Windows 上的 WinUIBackend
./testapp/output/P37                       # WSL 中的 GtkBackend
```

唯一一個「看它自己視窗的圖也判斷不出來」的 Pn。其他每個 app 都以「其視窗內含什麼」來評判；
這一個則以「什麼沒有蓋住它」來評判。因此測試需要第二個視窗，而值得注意的結果正是那個乏味的
結果：什麼都沒變。

此 app 套用 `.topmost()`，它就是 `.windowLevel(.floating)`，只是採用平台 API 慣用的名稱。兩者都
經由 `BackendFeatures.WindowLevels`；無法實現某個 level 的 backend 會退回 `.normal` 並記錄一次，
而非崩潰或悄無聲息。

兩個平台確實不同，不知情的測試者會把 Linux 的結果當成缺陷回報：

- **Windows** 上兩個 backend 都支援。WinUIBackend 使用
  `OverlappedPresenter.isAlwaysOnTop`；GtkBackend 則對 GTK 視窗底層的 `HWND` 呼叫
  `SetWindowPos(HWND_TOPMOST, SWP_NOACTIVATE)`。`SWP_NOACTIVATE` 很重要：此操作不得竊取焦點，
  而「取得前景」是另一件事，Windows 只允許已在前方的行程進行。
- **Linux 不支援。** GTK 4 移除了 `gtk_window_set_keep_above` 且無替代品，因此答案只能來自窗口
  管理員。在 Wayland 下，client 依設計無法把自己抬到其他應用程式之上。X11 有
  `_NET_WM_STATE_ABOVE`，但 WSLg 的窗口管理員並未宣告支援它：實測於 2026-08-26，其 root 的
  `_NET_SUPPORTED` 只列出 `_NET_WM_MOVERESIZE`、`_NET_WM_STATE`、`_NET_WM_STATE_FULLSCREEN`
  與兩個 `MAXIMIZED` atom。在把此事視為仍然成立之前，請以 `xprop -root _NET_SUPPORTED` 重新
  確認；在桌面 Linux 上答案通常不同，該處一般是有實作 `_NET_WM_STATE_ABOVE` 的。

測試步驟：

1. 啟動 P37，讀取它在視窗中印出的 `supported levels` 那一行。在 Windows 上應列出
   `automatic, normal, floating`；在 WSL 中則只有前兩者。該行等於是 app 在告訴你，接下來的兩個
   步驟該套用哪一個。
2. 支援 floating 之處：點擊另一個應用程式的視窗使其取得焦點，然後再看一次。P37 必須仍然可見且
   位於其上。請擷取「桌面」而非「視窗」——視窗擷取無法呈現「什麼沒有蓋住它」。
3. 不支援 floating 之處：P37 會跑到後方，此為該平台的正確結果。請確認 app 在步驟 1 已明說此事，
   而不是留給你去猜。
4. 檢查日誌中的退回訊息。在沒有 floating 的 backend 上，SwiftCrossUI 應恰好記錄一次
   `window level floating is not supported by ... using .normal`，而非每一次版面配置都記錄一次。
5. 關閉 P37，並確認桌面上沒有任何東西被遺留在「釘選於其他視窗之上」的狀態。一個比其視窗更長壽的
   window level，會壓在使用者接下來所做的每一件事上。

### P38：WebView（Linux 與 Windows）

執行：

```zsh
zsh testapp/test.zsh P38 --both
```

涵蓋 issues：

- WinUI WebView async / render delay 行為。
- GtkBackend WebView 覆蓋率與 graceful fallback 行為。

測試步驟：

1. 先在 WSLg 啟動 P38，再跑 Windows。
2. 確認 app 視窗會出現，且不會在 final screenshot 前卡住。
3. 檢查 WebView 區域是顯示可用內容、刻意 fallback，還是空白。
4. 檢查 log 是否有 navigation 或 async completion 訊息。
5. Windows 上保留預設 30 秒，確認 WebView 載入期間 app 仍可回應。

預期結果：

- 測試不應 crash，也不應卡住 loader。
- 若 initial screenshot 為黑畫面但 final screenshot 可見，記錄為啟動／render timing，不直接判為 UI failure。
- 若 Windows 無法抵達 final screenshot 或無法乾淨關閉，記錄為 WinUI async WebView issue。

### P39：Visual Effects（Linux、Windows、macOS 與 iOS）

執行：

```zsh
zsh testapp/test.zsh P39 --both
```

涵蓋 issues：

- GtkBackend 與 WinUIBackend 的 visual-effect rendering 差異。
- 非預期 diagnostic noise 或 silent no-op effects。

測試步驟：

1. 先在 WSLg 啟動 P39，再跑 Windows。
2. 確認 final screenshot 中所有 effect samples 都可見。
3. 判斷 rendering issue 時使用影像量測檢查顏色與可視性，不只靠肉眼。
4. 比較 WSLg 與 Windows 截圖是否有明顯 missing effects、clipped content 或 theme-driven contrast 問題。

預期結果：

- 兩個平台都應 render 出可見 samples。
- Backend-specific theme 差異可接受。
- GTK 上 blur 與色彩效果應明顯不同於 control。
- ~~WinUI 上 opacity 應不同於 control；blur、grayscale、saturation、brightness、contrast、hue rotation 目前預期仍為 no-op，需保留文件紀錄直到實作完成。~~
  **2026-09-02 起已被取代**（保留不刪，讓這條過時主張的樣態留在紀錄裡）：WinUI 上七項效果都應明顯不同於 control，與 GTK 相同。2026-09-02 驗證為 `applied=8 failed=0 total=8`（重跑指令：`cd testapp/output && SCUI_DEBUG_VISUAL_EFFECTS=1 ./P39-WinUI.exe`，再讀 `winui-visual-effects-debug.log`），並以 wincap 截圖做像素層級確認：saturation 0、0.5、control（=1）、2.5 各 cell 的 mean HSV saturation 依序為 0.000／0.515／0.818／0.992，是一條單調遞增的階梯。
- **macOS/AppKit 上九格全部都應不同於 control**，2026-09-02 量測。`AppKitBackend+VisualEffects.swift` 是一條套在 layer-backed container 上的 `CIFilter` 鏈，opacity 走 `alphaValue`，使子樹以一組的方式合成。若連 identity 對照格在內每一格都變空白，請懷疑 `layerUsesCoreImageFilters` 在沒有 filter 要跑時仍被設定——那正是它的樣子。
- **iOS/UIKit 上九格全部都應不同於 control**，2026-09-02 於 iPhone 16 模擬器量測。判定失敗前請先讀懂機制：`CALayer.filters` 在 iOS 上**不**參與合成——這量過兩次，而且至今仍為真：`opacity 0.35` 變淡，`blur 3`、`saturation 2.5`、`brightness 0.4`、`grayscale 1` 與 `hueRotation 120` 與對照格逐像素相同。效果之所以仍然有效，是因為已經不再那樣做了：它們改為透過 Core Image 作用於 `CALayer.render(in:)` 的點陣圖，結果覆蓋在子元件之上，子元件則以一個空的 `CALayer` mask 遮蔽，因此仍可被 hit test。要預期的後果是：被過濾的格子是「排版時重新產生的算繪結果」，而非活的子樹，所以其中若有由 Core Animation 驅動的動畫，看起來會是凍結的；`opacity` 不走這條路。

### P40：Geometric Effects（Linux、Windows、macOS 與 iOS）

執行：

```zsh
zsh testapp/test.zsh P40 --both
```

涵蓋 issues：

- Geometric effect rendering。
- Hotpink fallback / incorrect geometry detection。

測試步驟：

1. 先在 WSLg 啟動 P40，再跑 Windows。
2. 確認 final screenshot 中 transformed shapes 可見。
3. 聲稱 hotpink fallback 不存在或已修正前，先用 PIL 量測 final screenshot。
4. 量測橘色／藍色測試 tile 的 color-component bounding box。通過條件是 scale、offset、
   rotation 與 shear sample 必須依預期方向不同於 control；只有 hotpink 為 0 不足以判定通過。
5. 記錄 screenshot 尺寸、非黑像素比例，以及 exact / near hotpink 像素數。
6. 平台 theme / background 另行記錄。WSLg 可能預設為 light Adwaita，WinUI 則跟隨 Windows
   theme；這不是 geometry failure。

預期結果：

- 兩個平台都應產生可見且非黑的截圖。
- 除非 app 的測試案例刻意顯示 fallback 色，否則 exact hotpink pixels 應為 0。
- transformed samples 不應全部和 control tile 有相同 bounding box。
- **macOS/AppKit 與 iOS/UIKit 上七格全部都應正確算繪**，2026-09-02 分別於 Mac 與 iPhone 16 模擬器量測。最關鍵的檢查不是「有東西動了」：請比較 `rotate 30 centre` 與 `rotate 30 topLeading`，兩者必須**不同**。錨點運算錯誤會使這兩格相同，或把 tile 丟到畫面外，而這兩種失敗看起來都像是 transform 正常運作。某一格空白代表容器的子元件沒有被四個邊都釘住——modifier 的 commit 只設定容器的尺寸，沒有任何東西為容器內部的元件設定尺寸。

### P41：Date Picker Styles（Linux 與 Windows）

執行：

```zsh
zsh testapp/test.zsh P41 --both
```

涵蓋 issues：

- WinUI `.graphical` DatePicker blank sliver / binding 行為。
- 跨 backend DatePicker style fallback 行為。

測試步驟：

1. 先在 WSLg 啟動 P41，再跑 Windows。
2. 確認每個 DatePicker 區塊都有可見空間。
3. Windows 上特別檢查 `.graphical`，確認它沒有 render 成 blank sliver。
4. 可操作時更改日期，確認顯示的 binding value 有更新。
5. 記錄 log 中 style-specific fallback 訊息。

預期結果：

- Final screenshot 應在兩個平台都顯示可見 DatePicker 內容。
- 若 Windows `.graphical` 是空白或更新錯誤 binding value，記錄為 WinUI DatePicker issue。

### 測試完成紀錄格式

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

---

## 缺陷計畫:AppKit、UIKit 與 AndroidBackend

涵蓋可從 macOS workstation 測到的 upstream open bugs。選取來源是 `issues.csv`：其中有 33 列標記為 `bug` 且尚未修正，而這裡列出的是 backend 可在該機器上執行的 10 個。Gtk、Gtk3、WinUI bugs 則屬於 Windows workstation。

`UI-test-plan-en.md#platform-matrix` 是同一份資料的跨平台視角，可查詢哪個 app 在哪個平台涵蓋哪個 issue。

數量可用指令確認，不靠記憶：

```sh
awk -F, 'NR>1 && $2 ~ /bug/ && $4 !~ /^fixed-p/' testapp/issues.csv | wc -l
```

工作方式和 WinUI、Linux 計畫相同：先重現，量測而非推論，並記錄實際觀察到的內容。

### 範圍

| App | Backend | Issues | 執行位置 |
| --- | --- | --- | --- |
| P11 | AppKitBackend | #82, #485, #473 | macOS native |
| P12 | AndroidBackend | #632, #580, #544 | Android device 或 emulator |
| P13 | core layout / view graph | #595, #291, #158 | 任意 backend |
| P13 | AppKitBackend | #415 | macOS native |
| P14 | UIKitBackend | #324, #254 | iOS Simulator |

P13 刻意分成兩列。`issues.csv` 把 #595、#291、#158 歸在 `core/unspecified`，不是某個 backend，所以 app 能跑的地方都可測；只有 #415 是回報在 AppKitBackend。已量測，不是假設：P13 在 WSL 的 GtkBackend 下可 build 與 link，因此那三個 issue 不必等 Mac 才能檢查；如果某個 backend **沒有**出現問題，這本身也是有用結果。

同一組 bug 中刻意排除的項目，會在各節的「未涵蓋」中列出並附原因。

#### macOS workstation 無法觸及的項目

記錄下來是為了讓缺口清楚可見，而不是被忘掉。這裡的 "Blocked" 指的是**從 macOS blocked**：前兩列在 Windows workstation 上是例行工作，而且 #289 與 #160 在那裡已經有 repro app：

| Issues | 應改在哪裡處理 |
| --- | --- |
| #289, #594 | Windows workstation 的 WSLg。#289 由 P15 涵蓋 |
| #160, #231 | Windows workstation。#160 由 P16 涵蓋 |
| #286, #166, #179 | Gtk3Backend，所有地方都不在目前範圍內 |
| #189 | macOS 上的 GtkBackend，但兩台 workstation 都不跑這個組合；Gtk3 半邊也不在範圍內 |
| #227 | Mac Catalyst build target，尚未設定 |
| #226 | tvOS |
| #645 | 需要同時對多個平台做比較，因此要先等其他平台結果 |

---

### P11：Sliders、Scrollbars And Pickers（macOS）

Build and run：

```sh
zsh testapp/compile.zsh P11
./testapp/output/P11
```

涵蓋 issues：

- #82 (Open)：RandomNumberGeneratorExample 中兩個 sliders 互相限制時會 jitter
- #485 (Open)：Scrollbar 方向顯示相反
- #473 (Open)：Liquid Glass 下 Compact DatePicker sizing 錯誤

測試步驟：

1. 啟動 `P11`。
2. 點 `Separate them`，讓 minimum 為 20、maximum 為 80，且兩邊都沒有 clamp 啟用。點 `Reset counters`。
3. 慢慢把 **minimum** slider 往上拖過 80。觀察兩個 write counters，以確認 #82。
4. 放開後讀取 counters。一次拖曳應讓 `min` roughly 跟著 pointer 前進；當 sliders 分開時，`max` 不應前進。
5. 點 `Collide them`，再點 `Reset counters`，接著把 minimum slider 往右拖更遠。此時兩個值被 pin 在一起，這裡會觸發 clamp feedback。
6. 拖曳時觀察 slider handle：它必須停在 pointer 放置的位置，而不是來回跳動。
7. 用 scroll wheel 捲動 row list 並觀察 vertical scrollbar，以確認 #485。記錄 list 位於 row 1 時 thumb 在 track 的哪一端。
8. 捲到底部，記錄此時 thumb 的位置。
9. 比較 compact `DatePicker` 與旁邊的 `Reference` button，以確認 #473。檢查高度是否相符，且 date text 與 stepper 都沒有被裁切。
10. 點進 DatePicker 並改變日期；確認控制項不會因內容改變而 resize。

預期結果：

- 拖曳一個 slider 時，兩者分開的狀態下不會寫入另一個。若兩個 counters 一起上升，或 handle 在放開後跳回，就是 #82。
- List 在 row 1 時 scrollbar thumb 位於 **top**，捲到底時位於 bottom。若方向相反，就是 #485。
- DatePicker 符合 reference button 的高度且沒有裁切。若明顯較高、較矮或被裁切，就是 #473。

P11 未涵蓋：

- **#404**（`View > Show Tab Bar` 後 window content size）需要 app 無法從自身 view tree 驅動的 system menu item。重現方式是手動切換 menu 並觀察 content area 是否跟著調整；值得手動測，但不是 P11 能 assert 的東西。
- **#425**（window launch 後沒有 focus）upstream 描述為 intermittent：「every once in a while」。Pass/fail step 幾乎每次都會回報成功，不論 bug 是否修好。若它出現，請記錄 launch method、是否使用 Swift Bundler，以及 sidebar 是否有 transparency。

---

### P12：Button Margins、State And Toggles（Android）

Build and run：

```sh
cd Examples
SCUI_ANDROID=1 swift build --swift-sdk aarch64-unknown-linux-android28 --product P12
```

或依照 `Scripts/build-tool-install-android-on-Mac.sh` bundle 並安裝成 APK。P12 也能在 host platform render，這對部署前檢查 layout 很有用，但只有 Android run 能驗證這些 issues。

涵蓋 issues：

- #632 (Open)：Buttons 有不必要 margin
- #580 (Open)：旋轉螢幕會 reset `@State`
- #544 (Open)：Toggle button state 沒有視覺呈現

測試步驟：

1. 在已啟用 auto-rotate 的 device 或 emulator 上啟動 `P12`。
2. 在 margins section，觀察 green bands 之間的兩個 blue buttons，以確認 #632。Blue background 應延伸到每個 button 的邊緣。
3. 量測或目視 blue 與上下 green 之間的間隙。只要兩者之間有穩定的 background colour strip，就是 margin。
4. 點 `Second` 或 `Third`，讓 selected tab 不再是 default，然後點幾次 `Increment counter`。記錄兩個值。
5. 不做其他操作，將 device 旋轉到 landscape，以確認 #580。
6. 再讀一次 tab 和 counter。兩者都必須維持不變。
7. 旋轉回 portrait，並再次讀取。
8. 在 toggle section 中並排比較 `Forced on` 和 `Forced off` toggles，以確認 #544。
9. 點 `Set both on`；確認兩者現在彼此看起來相同。
10. 點 `Set opposite`；確認兩者現在彼此看起來不同。
11. 與下方使用不同 component 的 `switch` style toggle 比較，確認問題是否只存在於 button style。

預期結果：

- Blue background 會延伸到 button 邊緣。若 blue 和 green 之間有間隙，就是 #632。
- Tab selection 與 counter 在旋轉後保持不變。若回到第一個 tab，或 counter 回到 0，就是 #580。
- 兩個 button-style toggles 在 opposite states 時看起來不同。若看起來相同，就是 #544。

P12 未涵蓋：

- **#610**（Android sheet sizing）在 upstream 是兩個耦合 defect：layout system 沒尊重 backend 回報的 sheet size，以及 AndroidBackend 本身回報錯誤 size。要區分兩者，需要從兩層量測 size，而不是單純視覺檢查，所以它需要自己的 instrumented app，不適合只放成這裡的一個 step。

---

### P13：Layout And View Graph（任意 backend，外加一個 macOS-only check）

Build and run：

```sh
zsh testapp/compile.zsh P13
./testapp/output/P13          # .exe on Windows
```

依檢查位置分類的涵蓋 issues：

任意 backend：

- #595 (Open)：ScrollView 內文字被不必要裁切
- #291 (Open)：NavigationSplitView minimum width sizing
- #158 (Open)：ZStack 中的 Group 行為

macOS only：

- #415 (Open)：Message list benchmark 在 AppKitBackend crash

#415 是刻意 crash 的測試，因此藏在按鈕後面。先完成其他三項檢查，再最後觸發它。步驟 1-8 值得在所有可用 backend 上執行並分別記錄：尤其 #291 upstream 回報為影響 AppKitBackend、不影響 GtkBackend，因此兩邊是否一致本身就是 finding。

測試步驟：

1. 啟動 `P13`。確認 window 開啟，且左側 identifiable list render 三個相同 rows。
2. 比較兩個 ScrollViews。左邊是 plain，右邊套用 `.fixedSize(horizontal: false, vertical: true)`；upstream 回報這是 workaround，用來確認 #595。
3. 確認 plain ScrollView 顯示完整 wrapped sentence。若最後一行被裁切，而 `.fixedSize()` 那個沒有，就是 #595。
4. 觀察 ZStack section，以確認 #158。紅、綠、藍 blocks 位於 `ZStack` 內的 `Group` 中，尺寸依序遞減。
5. 確認它們重疊，且最小的在最上方，因此三者都像 nested rectangles 一樣可見。若它們被排成 side by side 或垂直堆疊，代表 Group 採用了 container orientation 而不是 z axis，這就是 #158。
6. 重複點 `Narrower` 並觀察 NavigationSplitView，以確認 #291。Frame 會每次縮小 60 px。
7. 確認 frame 變窄時 detail pane 仍保持可見。若 split 停止移動，且 sidebar 保持寬度而 detail pane 被擠出或裁切，就是 #291。
8. 點 `Wider` 並確認 split 恢復。
9. macOS 上：點幾次 `More duplicates`，再點 `Show unidentified list`，以確認 #415。這會 render 一個 `ForEach`，其元素不是 `Identifiable`，且彼此都 compare equal。
10. 記錄 app 是否 crash；若 crash，擷取訊息。Upstream 認為原因是 backend 收到 duplicate child views。在其他 backend 上此 step 預期不會 crash；仍請執行並記錄，因為這能界定 bug 是否限於 AppKitBackend。

預期結果：

- Plain ScrollView 不會裁切文字。若需要 `.fixedSize()` 才正常，就是 #595。
- Group children 沿 z 軸重疊。任何 side-by-side 或 vertical layout 都是 #158。
- Detail pane 在縮窄時仍存活。若被擠出，就是 #291。
- Render non-Identifiable list 不應 crash。Crash 就是 #415，而旁邊 identifiable list 是 control，證明相同資料在 identity 明確時沒問題。

---

### P14：Rotation Size Proposals And Theme（iOS Simulator）

Build、install、run：

```sh
zsh testapp/compile.zsh -ios P14
xcrun simctl boot swift-cross-ui
open -a Simulator
xcrun simctl install swift-cross-ui testapp/output/P14-ios.app
xcrun simctl launch swift-cross-ui dev.swiftcrossui.testapp.P14
```

`compile.zsh -ios` 會透過 `install_tools_ios.zsh` 自行 provision simulator，所以缺少 device 時會建立，而不是直接報錯。

涵蓋 issues：

- #324 (Open)：Orientation change 時 content 收到錯誤 size proposal
- #254 (Open)：System theme 變更時 app background colour 沒有更新

兩者都是關於值而不是外觀，所以 P14 會記錄收到的值，而不是要求你捕捉 flicker。#324 會在下一次 layout pass 自行修正；#254 則是其中一個 surface 和其他 surface 不一致。

測試步驟：

1. 在 portrait 啟動 `P14`。記錄 reported proposed width；它應該符合 device portrait width。
2. 點 `Clear history`。
3. 將 simulator 旋轉到 landscape（Cmd-Left Arrow），以確認 #324。
4. 讀取 `Width history`。它會依序記錄最多八次 width changes。
5. 確認 history 直接從 portrait width 到 landscape width。若中間出現一筆**大於 landscape width** 的 entry，接著才是正確值，就是 #324：app 曾被 proposal 到比實際可用空間更大的尺寸，之後才修正。
6. 旋轉回 portrait，再讀一次 history。
7. App 開啟時切換 system appearance，以確認 #254。Simulator 中可用 Features > Toggle Appearance，或從 terminal 執行：`xcrun simctl ui swift-cross-ui appearance dark`。
8. 比較三個編號 surfaces。Text、button、adaptive colour block 都應該和它們背後的 window background 一起變化。
9. 切回 light 再比較一次。

預期結果：

- Width history 只包含 portrait 與 landscape widths，且順序正確。兩者之間若出現額外 oversized entry，就是 #324。
- 每個 surface 都跟著 theme 變化。若 controls 和 adaptive block 改變，但它們背後的 background 還停在前一個 theme 的顏色，就是 #254。Adaptive block 在這裡是 control：它證明 theme change 已抵達，因此忽略它的 background 是 app 自身 bug。

P14 未涵蓋：

- **#227**（Mac Catalyst button sizing）同樣屬於 UIKitBackend，但需要 Catalyst destination，而不是 iOS Simulator；upstream 也只提供一張 screenshot，沒有描述，因此重現條件不清楚。

---

### 沒有 upstream issue 的 macOS 功能覆蓋

下列 app 覆蓋尚未分配 upstream issue 的 AppKit 功能：

| App | 功能 | macOS 檢查 |
| --- | --- | --- |
| P25 | Drag and drop | 將檔案拖到接受區，確認懸停回饋與收到的 file URL payload。 |
| P28 | Hit testing | 點擊藍色 overlay；點擊必須穿透並增加下方按鈕的計數。 |
| P29 | 視覺保真度 | 依文件中的對照項目檢查不確定進度條、裁切與停用 editor。 |
| P37 | Window levels | 將另一個視窗覆蓋到 app 上，確認選定的 window-level 行為。 |

P28 的可量測結果是 `Clicks received` 計數器，以及
`p28-debug-events.log` 中的 `underlying button clicked` 記錄。若可見的 overlay
吃掉點擊，即使 overlay 本身繪製正確，仍是 AppKit regression。

### 測試紀錄模板

```text
Date:
Commit:
OS / device:
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

---

## Linux 計畫:透過 WSL 的 GtkBackend

目標：在這台機器上重現 open 的 GtkBackend/Gtk3Backend issues，能修的就修，並將修正提交 upstream。工作方式和 WinUI 工作相同：先重現，量測而非推論，並保留證據。

哪個 app 涵蓋哪個 issue，以及 WSLg 執行結果是能判定 issue 還是只能顯示症狀，請看 `UI-test-plan-en.md#platform-matrix`。下方 Tier 1 / Tier 2 的區分就來自那份文件；但請注意，Tier 2 不等於「WSLg 會扭曲它」：要讀 caveat 欄，因為只有 #556 是關於 window sizing 本身。

### 目前環境

已檢查，不是假設：

| | |
|---|---|
| WSL | Ubuntu 26.04 LTS, WSL2, running |
| WSLg | 可用 -- `DISPLAY=:0`, `WAYLAND_DISPLAY=wayland-0`，所以 GTK windows 會 native 顯示 |
| Swift | **6.3.3**，從官方 tarball 安裝到 `/usr/local/swift` |
| GTK 4 | **4.22.4**（已安裝 `libgtk-4-dev`） |
| GTK 3 | 未安裝，而且是刻意不安裝 |

WSLg 提供的是 Wayland compositor。任何關於 window sizing、minimum sizes 或 resizing 的行為，都會和真正 desktop session 不同，因此這些 issues 需要 caveat（見 Tier 2）。

### Phase 0 -- toolchain

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

### Phase 1 -- 先證明 toolchain end to end 可用

在碰任何 issue 前，先於 WSLg 下 build 並執行 repository 自己的一個 example。如果 window 沒出現，那是環境問題，不是被測程式的 bug；後續所有結果都會可疑。

```sh
./Scripts/test.sh                    # unit tests
swift build --target GtkBackend      # not --product
```

`--target GtkBackend` 不是偏好，而是必要。單純 `swift build` 或 `--product SwiftCrossUI` 會讓 SwiftPM 建置 default target set，其中包含 `WinUIInterop` C target，Linux 上會因 `'Windows.h' file not found` 失敗。直接指定 target 才能繞過。

本機量測：clean 狀態下 `--target GtkBackend` 需要 61.7 秒；warm 後 `testapp/compile.zsh` 建一個 repro app 約 5-15 秒。

### Phase 2 -- 既有 test apps 提供的免費覆蓋率

`testapp` 中每個 app 都使用 `DefaultBackend`，Linux 上會選 GtkBackend；`testapp/compile.zsh` 已處理非 `.exe` 輸出。P0-P3 與 P5 應可不改直接 build/run；P4 和 P6 的 Windows-specific sections 都包在 `#if os(Windows)` 後面。

這很重要，因為 **P2 和 P3 已經有兩個 open issues 的測試步驟**，那些步驟是在 WinUI 版本修正時寫的：

- P2 step 7-8 涵蓋 #390：disabled buttons 看起來不像 disabled
- P3 step 6-9 涵蓋 #389：images 未被裁切

所以第一次真正測試不需要寫新 app。執行 P0-P3 和 P5，記錄哪些 WinUI 已修行為在 GTK 上仍壞。應該擴充 `#整體計畫p0-p41` / `UI-test-plan-en.md#overall-plan-p0-p41`，加入 Linux 欄位或 section，而不是另開一份文件。

此計畫寫成後，已新增 P7-P10 來涵蓋下方 Tier 1 / Tier 2 issues，也新增 P13 來測三個非 GTK-specific 但此處可觸及的 core-layout issues。它們都能在 WSL 的 GtkBackend 下 build 與 link，所以剩下只需要有人看著畫面測試。

### Phase 3 -- open issues triage

截至此計畫，Linux/GTK 對應 12 個 open issues。其中兩個（#286、#166）是 Gtk3Backend-only，因 Gtk3 排除而移除，剩下 10 個。之後 Tier 2 又從 `issues.csv` 補進三個標為 `core/unspecified`、而非 GtkBackend 的 issues：它們不是 GTK bugs，但可從此處觸及；在第二個 backend 上檢查 core layout bug，比只在一個 backend 上檢查更有價值。

**Tier 1 -- 一般 widget 行為，應可在 WSLg 重現**

| # | Title | App | Notes |
|---|---|---|---|
| 389 | Images aren't clipped | P3 | 已測過；WinUI 半邊已修，GTK 半邊 open |
| 390 | Disabled buttons don't appear disabled | P2 | 已測過；WinUI 半邊已修，GTK 半邊 open |
| 417 | ScrollView cornerRadius doesn't affect children | P8 | |
| 426 | Horizontal ScrollView swallows parent's scroll wheel | P8 | nested-scroll case |
| 454 | Transparent containers consume click events | P10 | 也影響 AppKitBackend |
| 476 | List starts with the first item selected | P7 | 已在 WSLg 下以 GTK4 與 Gtk3 確認修正 |
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

### Phase 4 -- 每個 issue 的流程

1. 重現，並擷取觀察結果（screenshot 或描述症狀）。若無法重現，也在 issue 上說明；這也是有用結果，尤其是那些早於目前 GTK 版本的 issues。
2. 新增或擴充一個能隔離問題的 `testapp` app，沿用既有 P0-P6 慣例，並將步驟加入兩份 test plan 文件。
3. 在 `Sources/GtkBackend` 修正，變更範圍保持和 bug 一樣小。若 issue 同時點名兩個 backends，修 GtkBackend，並在 pull request 中說明 Gtk3Backend 未測。
4. 用 test app 驗證，並檢查鄰近行為沒有 regression。
5. 每個 issue 一個 commit，風格沿用這裡已使用的格式（`GtkBackend: ...`）。

### 提交 upstream 前

- `Scripts/format.sh`（SwiftFormat 已安裝在 Windows 端；也可在 WSL 安裝，或從 Windows format）。
- 專案的 LLM policy 適用：pull request description 必須揭露使用情況，作者必須理解程式碼，而且 **description 必須由作者撰寫，不可由 LLM 代寫**。
- 優先一個 issue 一個 pull request。Contributing guide 要求 focused changes，而這裡較小的項目正好符合。

### 風險

- **Ubuntu 26.04 沒有對應 Swift build**，所以這裡使用的是 24.04 toolchain 搭配 26.04 libraries，並用從 24.04 packages 取出的 `libxml2` 和 ICU shim。它能 build 與 link，但不是 swift.org 測試的組合。若 failure 看起來像 Swift 或 Foundation bug，回報前應先懷疑是這個組合造成的。
- **WSLg 是 Wayland**，所以 window-level 行為與一般 desktop 不完全相同。Tier 2 結果需要附上這個 caveat。
- **GTK version skew**：4.22.4 很新，所以關於較舊 GTK 的 bugs 無法在此重現；在它上面驗證的 fix 也不能假設能幫助較舊 distributions 的使用者。
- 其中幾個 issues 很舊。有些可能已經修好；確認並關閉它們也是合理結果。

---

## 平台矩陣

此文件說明哪個 repro app 測哪個 issue，以及在各平台執行後能得到什麼結論。各 app 的逐步操作在 `UI-test-plan-en.md#overall-plan-p0-p41`；Linux 工作策略在 `UI-test-plan-en.md#linux-plan-gtkbackend-through-wsl`。本文件只回答一個問題：*這個 issue 要在哪裡跑，而結果算不算數？*

內容來自 `issues.csv`，它是 source of truth。若要重新產生 issue 與 app 的對應：

```sh
awk -F, 'NR>1 && $4 ~ /p[0-9]+$|p[0-9]+;/ {print $4"  #"$1"  "$3}' testapp/issues.csv
```

### 圖例

| | 意義 |
| --- | --- |
| 🎯 | Issue 回報在這個平台上。此平台的一次執行即可判定該 issue。 |
| 🔍 | Issue 不是回報在這個平台上，但執行結果可作為有用比較；一致或不一致本身就是 finding。 |
| ⬜ | 沒有可學到的資訊。App 可建置與執行，但此平台無法呈現這個 issue。 |
| ✅ | 此平台已修正。執行它是 regression check。 |
| 🚫 | 沒有對應硬體、simulator 或 toolchain。這是套用在哪台機器，請看下方表格。 |
| 〰️ | 可在 WSLg 執行，但結果不能判定 issue：這是 WSLg 會扭曲的 window-sizing 案例之一。先在這裡重現，再到 🐧 確認。 |

桌面平台欄位：🪟 Windows（WinUIBackend）· 🌊 WSLg（Wayland compositor 下的 GtkBackend）· 🐧 Linux（真實 desktop session 上的 GtkBackend）· 🍎 macOS（AppKitBackend）。Mobile：📱 iOS（UIKitBackend）· 🤖 Android（AndroidBackend）。

WSLg 和 Linux 分成不同欄位，因為兩者會有差異。WSLg 是 Wayland compositor，不是真正的 desktop session，因此 window sizing、minimum sizes、decorations 行為不同；這也是 `UI-test-plan-en.md#linux-plan-gtkbackend-through-wsl` 已記錄的 Tier 1 / Tier 2 分界來源。🌊 下標為 〰️、但 🐧 下標為 🎯 的兩列，就是分開兩欄的理由：WSLg 可以顯示症狀，但只有 desktop session 能判定。〰️ 不會出現在 🐧 下，因為它描述的是 WSLg 這個環境，而不是 GtkBackend 本身。

只有 #556 和 #289 使用 〰️。Tier 2 不等於「WSLg 不可信」：它只是收集需要*某種* caveat 的 issue，而原因各不相同。#595 和 #158 標示為非 GTK-specific，#291 回報為 Gtk **未**受影響，#295 的 caveat 則是 Gtk3Backend 半邊不在範圍內。這些都不是在談 WSLg fidelity，因此若把它們標成 〰️，反而會錯稱 compositor 會扭曲與它無關的結果。

### 各平台可在哪裡執行

此 repository 會在兩台機器上工作，所以「這裡」取決於你正在看的 checkout。以下以機器而非檔案說明：

| Platform | Windows workstation | macOS workstation |
| --- | --- | --- |
| 🪟 Windows | ✅ native | 🚫 |
| 🌊 WSLg | ✅ WSL2 + WSLg, GTK 4.22.4, Swift 6.3.3 | 🚫 |
| 🐧 Linux | 🚫 no desktop session | 🚫 |
| 🍎 macOS | 🚫 | ✅ native |
| 📱 iOS | 🚫 | ✅ Simulator, iOS 18.4 |
| 🤖 Android | 🚫 | ✅ SDK + NDK, device or emulator |

兩台機器都沒有真正的 Linux desktop session，因此 🐧 欄目前兩邊都不可達。它仍存在，是因為若干在 🌊 下量到的結果，在有人於 🐧 重跑前都明確只是 provisional。

### Binaries

目前 testapp 已到 P41。下方桌面 issue matrix 仍可判定其中列出的 upstream issue rows，但它已不再是所有本機 repro app 的完整 inventory。P18-P41 依需要記錄在 overall 與 bug plans。

在 Windows workstation 上，可達的桌面 app 預設以 release build 建置：🌊 WSLg 下是 `testapp/output/PN`，🪟 Windows 下是 `testapp/output/PN.exe`。目前沒有任何東西在 🐧 下建置過，所以該欄沒有結果。重新建置 matrix-era desktop set：

```sh
zsh testapp/compile.zsh P0 P1 P2 P3 P4 P5 P6 P7 P8 P9 P10 P11 P12 P13 P14 P15 P16 P17
```

較新的本機 app 請依 test plan 指名的 app 單獨建置，不要假設此 matrix 已經分類。

### 矩陣

#### Open issues 與 fixed regression coverage -- desktop

| Issue | App | 🪟 | 🌊 | 🐧 | 🍎 | 內容 |
| --- | --- | :-: | :-: | :-: | :-: | --- |
| #389 | P3 | ✅ | 🎯 | 🎯 | ⬜ | Images aren't clipped -- WinUI 半邊已修，GTK 半邊仍 open |
| #390 | P2 | ✅ | 🎯 | 🎯 | ⬜ | Disabled buttons 看起來不像 disabled -- 同樣是 split 狀態 |
| #476 (Fixed) | P7 | ⬜ | ✅ | ✅ | ⬜ | List 啟動時第一項已被選取 -- 已在 GTK4 與 Gtk3 確認修正 |
| #556 | P7 | ⬜ | 〰️ | 🎯 | ⬜ | NavigationSplitView size decisions 異常 |
| #417 | P8 | ⬜ | 🎯 | 🎯 | ⬜ | ScrollView cornerRadius 沒有裁切 children |
| #426 | P8 | ⬜ | 🎯 | 🎯 | ⬜ | Horizontal ScrollView 吞掉 parent 的 scroll wheel |
| #504 | P9 | ⬜ | 🎯 | 🎯 | ⬜ | TextField/SecureField 第一次更新後高度縮小 |
| #295 | P9 | ⬜ | 🎯 | 🎯 | ⬜ | Text 沒有被裁切到 zero width |
| #478 | P10 | ⬜ | 🎯 | 🎯 | ⬜ | Ctrl-Q 無法結束 |
| #454 | P10 | ⬜ | 🎯 | 🎯 | 🎯 | Transparent containers 吃掉 clicks -- 兩個 backends 都受影響 |
| #386 | P15 | 🔍 | 🎯 | 🎯 | ⬜ | 不支援 dark mode |
| #289 | P15 | ⬜ | 〰️ | 🎯 | ⬜ | Gtk-drawn title bars 下的 window minimum height |
| #160 (Fixed) | P16 | ✅ | 🔍 | 🔍 | ⬜ | Split view 第一次 render 時 layout 錯誤；WinUI initial layout 已修，互動重測仍可保留 |
| #595 | P13 | 🎯 | 🎯 | 🎯 | 🎯 | ScrollView 內文字被裁切（core） |
| #158 | P13 | 🎯 | 🎯 | 🎯 | 🎯 | ZStack 內的 Group 沿錯誤 axis layout（core） |
| #291 | P13 | 🔍 | 🔍 | 🔍 | 🎯 | NavigationSplitView minimum width -- AppKit 有問題，Gtk 沒問題 |
| #415 | P13 | 🔍 | 🔍 | 🔍 | 🎯 | Non-Identifiable ForEach 在 AppKit crash |
| #264 | P17 | 🎯 | 🎯 | 🎯 | 🎯 | frame(idealWidth:) 永遠沒有到達 fixedSize（core） |
| #266 | P17 | 🎯 | 🎯 | 🎯 | 🎯 | 兩個 layout edge cases（core） |
| #161 | P17 | 🎯 | 🎯 | 🎯 | 🎯 | Picker 依 selection 或最大項目決定大小 -- 需要 2+ platforms |
| #82 | P11 | ⬜ | ⬜ | ⬜ | 🎯 | 互相 clamp 的 sliders 會 jitter |
| #485 | P11 | ⬜ | ⬜ | ⬜ | 🎯 | Scrollbar 方向相反 |
| #473 | P11 | ⬜ | ⬜ | ⬜ | 🎯 | Compact DatePicker sizing |

#### Open issues -- mobile

| Issue | App | 📱 | 🤖 | 內容 |
| --- | --- | :-: | :-: | --- |
| #595 | P13 | 🎯 | 🎯 | ScrollView 內文字被裁切（core） |
| #158 | P13 | 🎯 | 🎯 | ZStack 內的 Group 沿錯誤 axis layout（core） |
| #264 | P17 | 🎯 | 🎯 | frame(idealWidth:) 永遠沒有到達 fixedSize（core） |
| #266 | P17 | 🎯 | 🎯 | 兩個 layout edge cases（core） |
| #161 | P17 | 🎯 | 🎯 | Picker 依 selection 或最大項目決定大小 -- 需要 2+ platforms |
| #324 | P14 | 🎯 | ⬜ | Orientation change 時 proposed size 錯誤 |
| #254 | P14 | 🎯 | ⬜ | App background 沒有跟著 system theme 更新 |
| #632 | P12 | ⬜ | 🎯 | Buttons 有不必要 margin |
| #580 | P12 | ⬜ | 🎯 | Rotation 會 reset @State |
| #544 | P12 | ⬜ | 🎯 | Toggle state 沒有視覺呈現 |

### Android action file 後續 TODO

Android runner、APK 傳送、emulator 啟動及 CSV action replay 已在 API 36 emulator
上以 P12 驗證。TODO：調查 P12 按鈕更新 state 後可能讓 render surface 變白的原因，並在 Android
action test 加入 screenshot 或 state assertion；在此之前，不可把 #632、#580 或 #544 視為 Android
已完成結果。

Core-layout issues 同時出現在兩張表中：它們是 backend-independent，所以任何平台執行都算數，而兩個平台之間的不一致本身就是 finding。

#### 已修正，保留作為 regression checks

| Issues | App | 🪟 | 內容 |
| --- | --- | :-: | --- |
| #493 #548 | P0 | ✅ | Launch-time crashes |
| #523 #659 #660 | P1 | ✅ | Dialogs and sheets |
| #204 #401 #449 #471 | P2 | ✅ | Controls and styling |
| #156 #190 #470 | P4 | ✅ | Bindings and callback storage |

P5 和 P6 沒有 upstream issue number：P5 是 multi-window alerts，P6 是 Windows GPU video path，NV12 工作就是從這裡延伸出來的。

### 依機器列出的執行項目

截至 2026-08-29，這份 matrix 在 Windows workstation 上仍視為尚未定案的缺口如下：

- 🪟 Windows：P16 驗 #160；P13 驗 #595/#158，並作為 #291/#415 comparison；P17 驗 #264/#266/#161；P15 作為 #386 control。
- 🌊 WSLg：P7 的 #556 仍是 provisional，因為 WSLg 會扭曲 window sizing；P15 的 #289 也因相同原因維持 provisional。除非各 app 的 result file 另有記錄，P2、P3、P8、P9、P10、P13、P15、P17 仍是 active WSLg matrix runs。
- 🐧 真實 Linux desktop：目前兩台機器都不可達。#556 與 #289 仍需要它才能定案。
- P18-P41：尚未完整納入這份 platform matrix。這些 app 請看 `UI-test-plan-en.md#overall-plan-p0-p41`、`UI-test-plan-en.md#bug-plan-appkit-uikit-and-androidbackend` 與各 feature result docs。

🌊 **WSLg**，在 Windows workstation 上 -- 17 個 issues，加上 #291 和 #415 作比較。#476 已在 GTK4 與 Gtk3 確認修正。〰️ rows 的結果在 🐧 存在前都維持 provisional：

```sh
./testapp/output/P2                            # 390
./testapp/output/P3                            # 389
./testapp/output/P7                            # 476 556
./testapp/output/P8                            # 417 426
./testapp/output/P9                            # 504 295
./testapp/output/P10                           # 478 454
./testapp/output/P13                           # 595 158, and 291 415 as comparisons
GTK_THEME=Adwaita:dark ./testapp/output/P15    # 386 289
./testapp/output/P17                           # 264 266 161
```

🪟 **Windows** -- 6 個 issues，加上 #291 和 #415 作比較：

```sh
./testapp/output/P16-WinUI.exe                 # 160，WinUIBackend
./testapp/output/P13-WinUI.exe                 # 595 158, and 291 415 as comparisons，WinUIBackend
./testapp/output/P17-WinUI.exe                 # 264 266 161，WinUIBackend
./testapp/output/P15-WinUI.exe                 # 386 as the control only，WinUIBackend
```

兩份清單在五個 core-layout issues 上重疊，這正是重點：它們是 backend-independent，所以在兩邊都跑，才能看出平台間是否不一致。其他項目則各自屬於特定欄位。

### 會讓結果無效的三件事

- **P15 若沒有 `GTK_THEME=Adwaita:dark`，就不算測 #386。** GtkBackend 宣告 `canOverrideWindowColorScheme = false`，所以 app 自己的 scheme buttons 無法改變任何東西。那些按鈕是 control；ambient theme 才是測試。
- **P16 若已經碰過視窗，就不算測 #160。** Resize 是會修正 layout 的兩件事之一，所以必須在移動任何東西前讀取 pane sizes。
- **P17 只在單一平台上跑，對 #161 沒有答案。** 這個 issue 是 backends 之間不一致，因此至少需要兩次執行來比較。

### 🌊 欄位的 caveats

WSLg 是 Wayland compositor，不是真正的 desktop session。Window sizing、minimum sizes、decorations 在那裡的行為不同，所以 🌊 和 🐧 分成兩欄，而不是合併成一欄。#556 和 #289 標為 〰️，因為兩者都和 window sizing 本身有關；Tier 2 其他項目有其他原因需要 caveat，但不受 compositor 影響。Gtk 在 Wayland 下確實會畫 client-side decorations，所以 #289 的前提成立；但這不是 Fedora + GNOME，因此 negative result 只能界定 bug 範圍，不能直接關閉它。

這裡的 GTK 是 4.22.4，夠新，因此 #702（關於*較舊* GTK 4）完全無法重現。Gtk3Backend 完全不在 scope 內，因此 #286 和 #166 被排除，也表示 #426 只會用 GTK 4 測。

---

## 結果紀錄

### 2026-09-14：P57 GTK Lazy Rows (#117)

先 WSLg、再 Windows GTK4；包含列生命週期修正的 release 編譯皆通過。
原生探針確認初始 nil、選取第 9999 列、清除選取、更新首尾文字，以及列數
10,000 -> 1 -> 10,000。10,000 列僅建立 205/206 個容器，縮至一列時降為 1。
這段流程穩定後記憶體：WSL 327-328 MB，Windows 260-288 MB。

兩端皆在 render marker 後保持顯示至少 30 秒。2026-09-14 已解決黑圖缺口：wincap
改用 Windows Graphics Capture，並保留 PrintWindow fallback。WSLg 當時也卡在過期的
COPY MODE；執行 `wsl --shutdown` 並重啟後，標題警告消失，WGC 可直接擷取。
最終 GL 截圖非黑比例為 WSLg 92.2%、Windows 92.1%；PIL 量得兩張皆為 668x776，
content bbox 皆為 (14,12)-(654,759)。原生 API 探針不等於真實指標輸入測試；WinUI
回歸仍待驗證。
證據及後續項目見 [backend 接續紀錄](plan/plan-backend-followup-20260912.md)。

### 2026-07-12

#### P2：Controls And Styling

- #449 Picker：點開 `Flavor` picker 時，曾觀察到 WinUI/Composition `BVI-*`、`rcBackdropLocal`、`CachedNewBlur` console diagnostic log。已嘗試在 WinUIBackend 覆寫 `ComboBoxDropDownBackground` 為 solid brush，待重新測試確認 console noise 是否消失。
- #449 Picker：先前 dropdown 會立即消失，且無法選擇其他 option。已調整 WinUI ComboBox：options 未變時不更新 items，selected index 未變時不重設 selection，待重新測試確認。
- #471 TextEditor：先前輸入可能漏字，例如快速輸入 `12345` 只顯示 `1235`。已移除 TextEditor 的一次性 `shouldBlockNextChangedSignal` 阻擋邏輯，改用最後同步文字避免同值 binding write，待重新測試確認。
- #390 (Fixed)：disabled button 與 enabled button 視覺差異目前回報為 no issue。
- #401 (Fixed)：window resizing / full screen button 行為目前回報為 no issue。

#### P3：Layout And Clipping

- #160：截圖顯示初始或特定視窗尺寸下 NavigationSplitView 欄位可能被裁切或配置不穩，需繼續記錄 resize / force state update 前後差異。
- #389：截圖顯示 oversized image 仍可能超出預期 frame，需記錄為 image clipping 相關現象並後續修正。

#### P4：WinUI Native And Callback Stress

- #156：截圖顯示 native WinUI banner 與 `TextField.inspect` 修改後的 border 可見，初步看起來 native API escape hatch 有生效。
- #190：截圖顯示 row buttons 與 scroll view 正常出現；仍需逐一點擊 `Run N`、增減 rows、重複 force update 來確認 callback 是否錯亂。
- Row size 增加延遲：目前判斷和 WinUIBackend 有關。P4 每個 row 會建立 Button/Text/Spacer 等多個 native widgets；row count 增加時，SwiftCrossUI `ForEach` 會重用舊 row 並新增新 row，但 ScrollView/VStack 仍會 layout 所有 rows。WinUIBackend 原本每次 `updateButton` 都重建 button content 的 `TextBlock`，大量 row update 時會放大延遲。已先改成 `CustomButton` 重用 label TextBlock，待重新測試比較延遲是否下降。

### 2026-08-16

#### P7：Lists And Split Views

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

#### P8：Scroll Views

- #426 (Confirmed/Open, WSLg/GtkBackend only)：已確認此問題只在 WSLg / GtkBackend 發生；Windows / WinUIBackend 對照未重現。WSLg 上水平與垂直 scroll 都完全不移動，包含游標位於內層水平長條上並嘗試水平或垂直滾動的情境；外層垂直 scroll view 沒有如預期接收/接手滾輪事件。
- #426：後續修正應優先在 WSLg / GtkBackend 上重現與驗證，再用 Windows / WinUIBackend 作為 non-regression 對照。可使用 `zsh testapp/test.zsh P8 --both`；腳本會先跑 WSLg、render 後保留 30 秒並拍 final screenshot，再跑 Windows。
- #417（WSLg/GtkBackend 未重現）：紅色子元件明顯被 `cornerRadius(20)` 裁切——WSLg 截圖中四個角都是圓的，與「內容從圓角穿出」的回報症狀相反。同時量到 `cornerScroll: 260x120` 對 `redChild: 260x300`，子元件確實超出容器 180px，也就是說有東西可被裁切。僅在 WSLg 下以靜態截圖確認；未檢視 Windows，也未在真實 Linux 桌面工作階段驗證。
- #266（附帶重現，僅 WinUIBackend）：內層水平長條在 Windows 上被量到兩次，先 `420x48` 後 `408x48`；WSLg 只量到一次 `420x48` 且維持不變。那 12px 是**外層** ScrollView 的垂直捲軸：WinUI 在後續的 layout pass 從內容寬度扣除，GTK 則以 overlay 呈現而不佔寬度。這正是 #266 描述的取捨——顯示捲軸會改變內容可用寬度，寬度改變可能改變內容高度，進而改變是否還需要捲軸。此處無害，因為沒有東西依賴該寬度，且 P8 並非為 #266 設計；記錄下來是因為若要處理 #266，這是現成的重現點。

### 2026-08-18

#### P6：Stream Player

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

### 2026-08-19

#### GTK 檔案選擇器：根因確認

- **根因是所使用的 API，而非我們的用法。** 判別方式是拿一個完全不含 SwiftCrossUI 的原生 GTK4 app（`gtk4-node-editor`）在同一個 WSLg Wayland 工作階段下測試：它的檔案對話框**正常關閉**。以 `nm -D --undefined-only` 比對兩者實際連結的符號：

  | | 使用的 API | Wayland 結果 |
  |---|---|---|
  | `gtk4-node-editor` | `gtk_file_dialog_new` / `gtk_file_dialog_open`（**GtkFileDialog**） | 關閉 |
  | SwiftCrossUI GtkBackend | `gtk_file_chooser_native_new` / `gtk_native_dialog_show`（**GtkFileChooserNative**） | 不關閉 |

  同一台機器、同一個 GTK 4.22、同一個 compositor，差別只在 API。
- `GtkFileChooserNative` 在 GIR 中標記為 `deprecated="1"`（`Gtk-4.0.gir`）。標頭檔本身沒有 `GDK_DEPRECATED` 巨集，因此以標頭檔查詢會得到「未標記淘汰」的錯誤結論——GIR 才是權威來源，也正是 `GtkCodeGen` 產生 Swift 綁定所依據的同一份資料。
- 取代用的 `GtkFileDialog` 自 **GTK 4.10** 起提供（`GDK_AVAILABLE_IN_4_10`），系統標頭中所需函式齊備：`open`／`open_multiple`／`save`／`select_folder` 及各自的 `_finish`，加上 `set_title`、`set_initial_folder`、`set_filters`、`set_accept_label`。它是**非同步 API**（`GAsyncResult` callback），與現行以 `response` signal 為中心的實作模型不同，因此遷移需要改寫而非替換函式名稱。
- 方法備忘：先前三次嘗試修正都失敗，因為都在假設「我們用錯了」。真正有效的一步是**切開責任歸屬**——用原生 app 做對照，確認同一環境下別人做得到。這比任何一個新假說都便宜。

#### 放棄 GTK3 支援

- 已移除 `Sources/Gtk3`（179 檔／16,365 行）、`Sources/Gtk3Backend`（2,448 行）、`Sources/CGtk3`、`Sources/Gtk3CHelpers`、`Sources/Gtk3Example`、`Tests/Gtk3BackendTests`、`Scripts/generate_gtk3.sh` 與 docc 的 Gtk3Backend 頁面。
- 實際的程式碼依賴**只有兩處**：`Package.swift`（products／targets／測試開關 `SCUI_TEST_GTK3BACKEND`）與 `Sources/DefaultBackend`（`#elseif canImport(Gtk3Backend)` 的後備選擇）。其餘散落的引用全是註解或條件編譯分支。
- `Examples` 內的 `#if canImport(Gtk3Backend)` 分支在模組消失後會自動編譯掉，不會破壞建置，但仍一併移除；`ControlsApp.swift` 的 `#if !canImport(Gtk3Backend)` 則相反——它在移除後永遠為真，因此拆掉包裹讓內容無條件編譯。
- 文件與註解清理另外揪出**兩個真正的破損**，不只是文字：`Scripts/generate_gtk.sh` 仍呼叫已刪除的 `./generate_gtk3.sh`；`GtkCodeGen` 的 `gtk3AllowListedClasses` 與 `version == "3.0"` 分支是實際的產生邏輯。CI workflow 也還在建置與產生 `Gtk3Backend` 的文件（三個步驟＋docc 合併清單）。`Publisher.swift` 另有一個 ``` ``Gtk3Backend`` ``` 的 DocC 符號連結，目標消失後會變成無法解析的連結。
- 刻意**保留**的三處：`gtk_helpers.h` 中作者記述某次 macOS 建置異常的第一人稱說明、`AppBackend refactor.md`（開頭即言明是某 PR 的變更清單，本質為歷史文件），以及 `GtkCodeGen` 中 `populate-popup` 的停用理由——後者已改寫為「GTK3 已移除故該理由不再適用，但尚未在 GTK4 上驗證重新啟用」，而不是直接開啟該訊號，因為那是行為變更。改寫歷史記述等同偽造記錄。
- **rsync 不會傳播刪除，且建置成功會掩蓋這件事**：`rsync_WSL.zsh` 刻意不使用 `--delete`（WSL 端的 `output/`、build 快取與本地修改應保留）。因此本機刪除 193 個 GTK3 檔案後，WSL 端**全部仍在**；而 SwiftPM 會忽略 `Package.swift` 不再宣告的目錄，所以 WSL 上四個 target 依然建置成功——一棵已經與本機不一致的樹，看起來完全正常。已手動清除 WSL 端並重新驗證，同時把這個後果寫進 `rsync_WSL.zsh` 的標頭。
- 驗證：`Gtk`、`GtkBackend`、`DefaultBackend`、`GtkExample` 四個 target 皆建置成功；所有編輯過的檔案通過 `swiftc -parse`。整包 `swift build` 與 `Examples` 在 Linux 上仍會停在 `WinUIInterop`／`swift-winui` 缺 `Windows.h`、`wtypesbase.h`——那是既有的平台限制，與本次移除無關。

#### GtkBackend 已能在 Windows 上建置

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

#### WSLg 幽靈視窗

- `gtk4-widget-factory` 行程結束後，Windows 端的 `msrdc.exe` 仍持續顯示 `GTK Widget Factory (Ubuntu)` 視窗。WSL 內 `pgrep` 確認無任何對應行程。
- 這是繼 PulseAudio 停止監聽、COPY MODE 之後，**WSLg 橋接第三種靜默失效**：視窗已無擁有者卻不被移除。判讀 WSL GUI 測試結果時，「Windows 上看得到視窗」不足以證明該 app 仍在執行。

### 2026-08-29

#### P21-P41 Loader 覆蓋

- 補上 P21、P22、P23、P24、P25、P27、P29、P37、P38、P39、P40、P41 缺少的 `test_support/test_Pn.zsh` loader。所有新 loader 與 `test_support/test_common.zsh` 都通過 `zsh -n`。
- common loader 現在會記錄 screenshot failure，但不會因 `set -e` 中止整個流程。這是必要修正：先前 1 秒截圖失敗時，流程會在 cleanup trap 釋放 `ui-lock` 前退出。
- 測試順序遵守目前規則：先 WSLg，再 Windows。第一批先跑 P27/P29/P37/P38/P39/P40/P41，第二批補跑 P21-P25。

#### 自動 Smoke Test 結果

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

#### 時序觀察

- WSLg 上這批 release build 在 source sync 後約 12-13 秒完成。
- Windows 上 P27 早前 build 耗時 231.84 秒；後續 P37-P41 build 大多約 38-75 秒。Windows build 即使成功建出 WinUI app，仍會印出 `pkg-config` / `gtk4.pc` 警告。
- 多個 Windows app 在 1 秒截圖時尚未被找到，但 final capture 正常可見。除非 final capture 也失敗，否則先記錄為 startup/window-discovery timing。
- `--actionfile <relative path>` 暴露 Windows loader bug：路徑 containment check 直接拿相對路徑與絕對 `testapp` 路徑比較。WSLg 先用裸 `--actionfile` 避開；`test_common.zsh` 現已加入本地 path converter，因此 Windows 不再依賴 `cygpath`。

### 2026-08-30

#### P30-P36 Loader 與 Baseline 覆蓋

- 已新增 P30、P31、P32、P33、P34、P35、P36 的可編譯 baseline apps 與 `test_support/test_Pn.zsh` loaders。
- `testapp/compile.zsh` 現在 Windows 與 WSLg 都預設使用 release build；若需要 debug build，必須明確設定 `BUILD_CONFIG=debug`。
- 測試順序遵守目前規則：先 WSLg，再 Windows。WSLg 端先透過 `testapp/rsync_WSL.zsh` 同步，再於 `/home/lowei/proj/swift-cross-ui` 內編譯。

#### 自動 Smoke Test 結果

以下 final screenshot 都以 PIL 量測。每張 final capture 都可見且非黑畫面。

| App | WSLg final screenshot | Windows final screenshot | 備註 |
| --- | --- | --- | --- |
| P30 | 888x649，92.5% 非黑 | 876x659，92.6% 非黑 | WSLg 可見 blur / grayscale 類效果；Windows 可見 opacity 與幾何 transform，但 blur / grayscale 看起來像 no-op，先記錄為 WinUI visual-effect parity 仍待查。 |
| P31 | 808x589，91.8% 非黑 | 796x599，91.9% 非黑 | 兩平台都能渲染 focus / keyboard baseline controls。~~真正的 Tab 順序、Space/Return 觸發、Escape 與 Ctrl+Q 仍需人工鍵盤測試。~~ **2026-09-03 起，四者中的兩者已被取代：** Tab 順序與 Space 觸發已在 Windows/GtkBackend 上量測，兩者皆可運作——見 2026-09-03 條目。Escape 與 Ctrl+Q 仍未量測，而 Escape **根本無法**由動作檔量測。 |
| P32 | 788x589，91.7% 非黑 | 776x599，91.8% 非黑 | 兩平台都能渲染 accessibility baseline controls。角色與名稱驗證仍需 Linux 上的 Accerciser，以及 Windows 上的 Accessibility Insights 或 `inspect.exe`。 |
| P33 | 848x649，92.4% 非黑 | 836x659，92.5% 非黑 | 兩平台都能渲染 missing-view 清單與手寫近似 UI。這是可編譯 baseline，不代表缺席的 SwiftUI views 已經存在。 |
| P34 | 808x649，92.2% 非黑 | 796x659，92.4% 非黑 | Smoke run 使用 `--debug -rows 100`。更大的 row count / performance 測試仍需另外執行。 |
| P35 | 788x589，91.7% 非黑 | 776x599，91.8% 非黑 | 兩平台都能渲染 state baseline。Scene composition 缺口仍屬編譯期問題。 |
| P36 | 848x649，92.4% 非黑 | 836x659，92.5% 非黑 | 可用的 SwiftCrossUI API 形狀能正常渲染；SwiftUI-shaped missing calls 以文字列出，避免破壞日常測試 build。 |

#### 時序觀察

- WSLg release build 在同步後很快完成：P30 13.66 秒，P31-P36 各約 6-10 秒。
- Windows release rebuild 明顯較慢，尤其是改變 build configuration 後的第一個 target：P30 900.34 秒，P31-P36 之後約 11-29 秒。
- Windows 多個 1 秒截圖只拍到接近空白的 first frame，但 10 秒 final screenshot 都正常。除非 final screenshot 也失敗，先記錄為 WinUI first-paint / window-capture timing。
- WSLg 執行時視窗標題仍回報 `[WARN:COPY MODE]`，雖然 final capture 可見。這些結果可用於 UI layout smoke test，但不適合作為 GPU rendering performance 驗證。

### 2026-08-31

#### P16：WinUI NavigationSplitView 初始 layout（#160）

- 已重建並執行 Windows `P16.exe`。final screenshot 可見，尺寸為 916x639，非黑像素 92.5%。
- 初始診斷仍顯示不穩定的首次量測路徑：`sidebar: 0 x 22`、`detail: 0 x 22`，接著 `detail: 734 x 22`。截圖上可見左側 pane 存在，但 sidebar probe 沒有回報穩定的非零寬度。
- 已找到一個 runner bug：`compile.zsh` 接受 `SCUI_DEBUG=1`，但沒有把 `-Xswiftc -DSCUI_DEBUG` 傳給 `swift build`。此點已在工作樹中修正，並把 build-plan hash 納入 `SCUI_DEBUG`，避免切換 debug feature 後重用錯的 SwiftPM plan。
- 目前 actionfile hook 已可觀察：WinUI `show(window:)` 會排程 replay，`ActionFileReplay` 也會把幾何與 replay 結果寫入 `actionfile-replay.log`，避免 WinUI console redirection 讓 runner 誤判為沒有執行。
- 但 P16 的 actionfile replay 尚未讓 UI 出現預期變化：Force update counter、sidebar selection 與 column switch 仍未在 final screenshot 中確認。這表示剩餘問題較可能在 Win32 synthetic input 對 WinUI 控制的命中 / focus / activation，而不是單純沒有載入 actionfile。
- 重新以乾淨 `actionfile-replay.log` 跑 `P16 --windows --no-build --showtime 10` 後，`SendInput` 回報 `ERROR_ACCESS_DENIED`。此輪不能當作 app 行為證據；需在 unlocked desktop、且沒有 elevated foreground window 的情境重跑。
- 修正 WinUI `createSplitView` 初始 `openPaneLength` 後，P16 final screenshot 改為顯示 `sidebar: 180 x 22`、`detail: 660 x 22`，且 `Science` / `Humanities` 不再被壓窄換行。此修正與 GTK 的初始 200px sidebar guess 對齊，避免 core `SplitView.computeLayout` 第一次讀到 0-width sidebar。
- 目前結論：#160 的初始 layout repro 已修正；仍未完成的是 actionfile 對 Force update / sidebar selection / column switch 的自動互動驗證。最新 actionfile report 可回 `replayed`，但畫面上的 counter 沒變，所以此部分仍需人工驗證或更可靠的 WinUI control activation。

#### P7：NavigationSplitView pane ratio（#556）

- P7 已依規則先跑 WSLg，再跑 Windows。兩邊 final screenshot 都可見，尺寸皆為 748x509。
- WSLg 診斷：`[SplitView] total=420.0 minLeading=31.0 minTrailing=36.0 -> bounds min=31 max=384 currentSidebar=200`。
- Windows 診斷：`[SplitView] total=420.0 minLeading=31.0 minTrailing=35.0 -> bounds min=31 max=385 currentSidebar=200`。
- 因此本輪兩平台使用相同實際 split ratio：sidebar 200 / total 420，也就是 47.6%。
- 先前類似 87px 的結論是量測錯誤：把 content width 當成 pane width。P7 程式中的註解已指出此點；content probe 可以遠小於承載它的 pane。
- 目前結論：目前 P7 執行中，#556 不再以 pane-ratio mismatch 重現。除非其他 resize/content 情境仍能重現，否則 plan 應由「ratio mismatch」改為「量測防呆 / regression coverage」。

#### P30/P39：WinUI visual effects

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

#### P16 與 P7 在 GtkBackend（WSLg）上的同一診斷

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

#### macOS 端回覆之後，三個 backend 的全貌

- macOS 的答案在 `mac-test-results-20260901.md`，同日於 AppKitBackend 上量測。此處僅摘要，因為這次練習的目的就是三方比較；原始輸出與方法在該檔案中。
- **Q1 定案，GTK 是異類。** AppKit 給出 900x628 的外框、28pt 標題列，因此**內容 900x600——恰為所要求的值**，且取自兩個彼此獨立的來源（`CGWindowListCopyWindowInfo` 取外框，以及 InputEvent 重放以 AppKit 自己回報的 frame 對照 client 原點，120 對 148）。這與 WinUI 一致，並證實了本檔案先前標為「未驗證」而非直接斷言的那個預期。GTK 的 900x561 是唯一短少的，~~現已修正——見 `todo.md`~~ **——但這個「現已修正」沒能通過重新量測。2026-09-03 在 GTK/Windows（gvsbuild）上，P16 仍記錄到同樣的 39px 落差：480 / 480 / 441。`correctContentSizeIfNeeded` 確實存在於 `GtkBackend.swift` 並由 `updateWindow` 呼叫，因此程式碼有落地；沒有被證明的是它有交付結果。見 2026-09-03 條目，並把 `todo.md` 中該項視為未結案。**
- **Q2 把一個觀察拆成了兩個。** AppKit 對 P16 的首次算繪 commit **三次**，與 GTK 相同、與 WinUI 的一次不同——但它的高度全程不動，而 GTK 是 485 → 446 → 446。因此「commit 三次」與「高度收斂」是彼此獨立的兩件事，而其中只有後者曾構成證據。三者的寬度一致，皆為 200 / 680。安定後的高度差異，恰好等於各平台放在內容之上的裝飾：**AppKit 497 / WinUI 486 / GTK 修正前 446**。
- **Q3 是最有價值的答案。** AppKit 的 `List` 在 180 高的窗格中同樣回報 **140**——與 GTK 給出的是同一個數字。兩個各自獨立撰寫的 backend 給出相同答案，就把該行為定位在**共用的版面程式碼**，而非任一 backend，這正是這次量測設計要分辨的事。因此「`List` 在垂直方向不貪婪」是 SwiftCrossUI 本身一個真實的 SwiftUI parity 缺口。
- 值得帶出此任務之外的一點：他們的檔案記載 `AppKitBackend.createWindow` 會呼叫 `setFrameAutosaveName(id)`，而 `id` 衍生自 root view 的型別，因此大多數測試 app **共用同一把 key**（`"NSWindow Frame TupleView1<HotReloadableView>-0"`）。已儲存的 frame 會完全蓋過 `.defaultSize`——同一個 binary、同一個 commit 的 P28，會因該 key 的內容而開成 680x448 或 1076x907。任何先前未清除該 key 就量測視窗尺寸的 macOS 結果，都應存疑。

### 2026-09-02

#### P39 與 P40 於 AppKitBackend 與 UIKitBackend：兩個效果系列皆已實作

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
- **Android 後來已經量測過，這一條已經過時。** `matrix_coverage/results.csv2` 中確實有
  AndroidBackend 上的 P39 與 P40 紀錄，記於 2026-09-03；兩者並於 2026-09-06 再次以其動作檔驅動。
  兩支都能建置、啟動、重放並算繪；兩支的內容都比手機寬——P39 的內容框是 (-325,0)-(1407,2400)、
  P40 是 (-320,0)-(1402,2400)——而在 root scroll host 修好之前那部分是碰不到的，這也是它們先前的
  截圖左右兩側看起來被切掉的原因。兩份動作檔都不預期畫面改變：各按一個格子，要求行程存活。

#### P43 的漸層填充於 macOS 與 iOS

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
- **AndroidBackend 也已實作，這一條已經過時。**
  `Sources/AndroidBackend/AndroidBackend+PathGradients.swift` 覆寫了
  `renderPath(…fillStyle:)`，它不再取用壓平的預設實作。以
  `p43-android-final-20260906-022713.png` 實測：漸層形狀中有 9,885 個紅色與 14,959 個藍色像素，
  旁邊的平面對照則有 19,410 個綠色像素。若是壓平的填充，每個形狀就會是單一顏色、完全沒有漸層。

#### iPhone 上的 NavigationSplitView

- 在緊湊寬度的 iPhone 上，`UISplitViewController` 無論 `preferredDisplayMode` 為何都會收合成一個
  navigation stack；沒有任何設定能把 sidebar 放在 detail 窗格旁邊。因此 `PhoneSplitWidget` 並非
  它的包裝——它就是把兩個窗格並排放置，而那正是 `NavigationSplitView` 的語意，也是其他每一個
  backend 所產生的結果。
- 寬度是**推導出來的，不是存起來的**：`sidebarWidth` 必須能在 `computeLayout` 期間、任何 layout
  pass 執行之前就回答，因此它由 `setSize(of:)` 剛寫入的 `width` 推導，而那與 `layoutSubviews`
  稍後所用的是同一個數字。

### 2026-09-03

#### P16：`.defaultSize` 的短少屬於 GtkBackend，而不屬於 WSLg

- 此處任何數字都可用 `SCUI_DEBUG_SPLIT=1 zsh testapp/run.zsh P16` 重新產生，再讀取
  **repo 根目錄下**的 `splitview-debug.log`。
- **39px 的內容短少在 Windows 版 GTK（gvsbuild）上同樣重現。** P16 要求
  `.defaultSize(900, 600)`，記錄了三輪：`leadingContent=200.0x480.0`、再一次
  `200.0x480.0`，接著 `200.0x441.0`。落差為 **39**——與 2026-09-01 WSLg（485 接著 446）
  完全相同的數字。WinUI/Windows 則一輪即回報穩定的 **486**，沒有修正輪。
- **這推翻了「WSLg 現象」的界定。** 2026-09-01 寫在本檔與 `bugs/Gtk4-bugs.md` 第 5 節中的一切，
  都把此短少描述為「在 WSLg 上量到的」，而那讀起來像是一項平台性質。它其實是 `GtkBackend` 的
  性質：client-side decoration 在兩個平台上都把標題列放進視窗之內。絕對高度不同（480/441 對
  485/446），只是因為兩個視窗系統在表面**外圍**加上的裝飾量不同。
- **這也代表該修正尚未被證明有效。** `correctContentSizeIfNeeded` 位於
  `Sources/GtkBackend/GtkBackend.swift`，並由 `updateWindow` 呼叫，因此產生上述數字的那份原始碼
  中確實有它，落差卻依然存在。`todo.md` 中的該項為未結案；而 2026-09-01 那句「現已修正」以註記
  方式保留而非刪除，因為「寫好了就假定它有效」正是最值得留在檯面上的失敗形狀。
- **2026-09-04 由「尚未被證明有效」升級為「已被證明無效」。** 在該修正之後加入了讀回，因此現在
  不只有**事前**的值，也有**事後**的值：

  ```
  content size: requested 900x600 allocated 900x561 shortfall 0x39
  content size: grew the window to 900x639
  content size after correction (+250ms):  allocated 900x561 shortfall 0x39
  content size after correction (+1500ms): allocated 900x561 shortfall 0x39
  ```

  刻意取兩個延遲：單一次的延後讀數無法分辨「修正沒有作用」與「修正有效但我量得太早」，因為兩者
  都會印出舊的數字。時序造成的假象會給出**兩個不同的**數字；同一個數字出現兩次，代表那個指派是
  no-op。

  它之所以藏了三天，是因為讀數與修正被放在**同一個 once-only guard** 內，於是「**執行過**」與
  「**有效**」印出來一模一樣。而原因就在同一個檔案裡：`setSizeLimits` 早已載明「toplevel 上的
  size request 在視窗 realise 之後只是啟動提示」，而 `gtk_window_set_default_size` 屬於同一類
  提示。該修正**依其構造**必然在視窗 map 之後才執行——因為差額在那之前量不到——於是**它唯一能
  量測的時刻，正是它已經無法作用的時刻。** 見 `bugs/Gtk4-bugs.md` 第 5 節與任務 #79。
- **同一組要求下的視窗外框尺寸，對每個 backend 是固定的，backend 之間則不同**——因此跨 backend
  比較外框，說不出誰遵守了要求：

  | app | `.defaultSize` | gtk4 外框 | WinUI 外框 |
  |---|---|---|---|
  | P31 | 780x560 | 808x589（+28/+29） | 796x599（+16/+39） |
  | P16 | 900x600 | 928x629（+28/+29） | 916x639（+16/+39） |

  WinUI 的 +16/+39 是 Windows 畫在「尺寸恰為所求」的 client **外圍**的 non-client 區域。WinUI
  遵守了要求；外框較大並不是短少。

#### P31 於 Windows/GtkBackend：Tab 與 Space 可運作，Escape 無法被測試

- 以新增的 `testapp/actions/win/P31-tab-and-escape.csv` 驅動。重新產生：
  `zsh testapp/run.zsh P31 -actionfile testapp/actions/win/P31-tab-and-escape.csv`，
  再讀取**你執行該指令所在目錄下**的 `p31-debug-events.log`。
- **焦點會移動，Space 會觸發。** 由 `TextField` 按 `key tab` 之後接 `key space`，產生了
  `button clicked count=1`。SwiftCrossUI 沒有任何 focus API——沒有 `@FocusState`、沒有
  `.focused`、沒有 `.focusable`——因此這完全是 GTK-on-Windows 的行為，也是 SwiftUI parity 中
  focus/keyboard 那項「焦點那一半」的真實正面結果。P31 計畫的步驟 1 與 2 已由量測取代假定。
- **Escape 沒有關閉 alert，而那不是一項 P31 結果。** 按鍵從未抵達對話框：
  `Win32Synthesiser.ownWindow()` 回傳本行程中面積最大的可見 top-level 視窗，而
  `Gtk.MessageDialog` 是較小的獨立 top-level 視窗；合成器接著對主視窗呼叫
  `SetForegroundWindow`，把焦點從 modal 手上拉走。完整記述見 `bugs/Gtk4-bugs.md` 第 6 節。
  目前任何出現在對話框內的東西，都無法由動作檔測試。
- **Escape 不是可攜的關閉手段。** `testapp/actions/mac/README.md` 推薦它，理由是「無需座標即可
  抵達 key window」。這在 macOS 上為真，在 Windows 上為假。兩份 README 現已寫明此事。

#### Pn 的 debug log 究竟落在哪裡

- **每一支會寫 debug log 的 `testapp/P*.swift`，都寫到當前工作目錄**，透過
  `FileManager.default.currentDirectoryPath`。**49 支中有 38 支**如此，其餘 11 支完全不寫 log。
  `splitview-debug.log` 亦同（`Sources/SwiftCrossUI/Views/SplitView.swift:215`）。可用
  `grep -l currentDirectoryPath testapp/P*.swift | wc -l` 重新推導。

  2026-09-07 由「47 支中有 35 支」更正，旁邊那道指令也一併更正：`grep -c` 印的是**每個檔案一列**
  的計數，因此它從來就產不出它被附上作為推導依據的那個總數。一道無法重新產生該數字的指令，
  比沒有指令更糟，因為它看起來可以查證。
- 因此只有**一種**慣例，不是兩種。凡是寫成 `testapp/output/p28-debug-events.log` 的文件，之所以
  正確，只是因為該流程會先 `cd` 進 `testapp/output`；而 `testapp/run.zsh` 以絕對路徑啟動、從不
  切換目錄，所以經由它驅動的一切都會把 log 留在 repo 根目錄。若在 `run.zsh` 啟動之後照著寫有
  `testapp/output/` 的文件去找，看到的會是一個空目錄，並且很容易讀成「這支 app 什麼都沒記錄」。

