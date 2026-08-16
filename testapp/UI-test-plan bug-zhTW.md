# Bug 測試計畫：AppKitBackend 與 AndroidBackend

涵蓋可從 macOS workstation 測到的 upstream open bugs。選取來源是 `issues.csv`：其中有 33 列標記為 `bug` 且尚未修正，而這裡列出的是 backend 可在該機器上執行的 10 個。Gtk、Gtk3、WinUI bugs 則屬於 Windows workstation。

`UI-test-plan platform-en.md` 是同一份資料的跨平台視角，可查詢哪個 app 在哪個平台涵蓋哪個 issue。

數量可用指令確認，不靠記憶：

```sh
awk -F, 'NR>1 && $2 ~ /bug/ && $4 !~ /^fixed-p/' testapp/issues.csv | wc -l
```

工作方式和 WinUI、Linux 計畫相同：先重現，量測而非推論，並記錄實際觀察到的內容。

## 範圍

| App | Backend | Issues | 執行位置 |
| --- | --- | --- | --- |
| P11 | AppKitBackend | #82, #485, #473 | macOS native |
| P12 | AndroidBackend | #632, #580, #544 | Android device 或 emulator |
| P13 | core layout / view graph | #595, #291, #158 | 任意 backend |
| P13 | AppKitBackend | #415 | macOS native |
| P14 | UIKitBackend | #324, #254 | iOS Simulator |

P13 刻意分成兩列。`issues.csv` 把 #595、#291、#158 歸在 `core/unspecified`，不是某個 backend，所以 app 能跑的地方都可測；只有 #415 是回報在 AppKitBackend。已量測，不是假設：P13 在 WSL 的 GtkBackend 下可 build 與 link，因此那三個 issue 不必等 Mac 才能檢查；如果某個 backend **沒有**出現問題，這本身也是有用結果。

同一組 bug 中刻意排除的項目，會在各節的「未涵蓋」中列出並附原因。

### macOS workstation 無法觸及的項目

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

## P11：Sliders、Scrollbars And Pickers（macOS）

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

## P12：Button Margins、State And Toggles（Android）

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

## P13：Layout And View Graph（任意 backend，外加一個 macOS-only check）

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

## P14：Rotation Size Proposals And Theme（iOS Simulator）

Build、install、run：

```sh
zsh testapp/compile.zsh -ios P14
xcrun simctl boot swift-cross-ui
open -a Simulator
xcrun simctl install swift-cross-ui testapp/output/P14.app
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

## 測試紀錄模板

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
