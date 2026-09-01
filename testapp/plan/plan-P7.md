# P7 修正計畫

## 目標

P7 用來追蹤 Linux/GTK backend 的 List 與 NavigationSplitView 行為，主要涵蓋：

- #476 (Fixed)：GTK/Gtk3 backend 上 `List` 啟動時不應自動選取第一項。
- #556 (Monitoring)：GTK backend 上 `NavigationSplitView` 的 pane aspect / split ratio 應接近 Windows，且 resize 後仍維持合理比例。

目前測試結果顯示：#476 已修正並由 GTK4/GTK3 確認；P7 啟動時 selection 綁定維持 `nil`，狀態列顯示 `Selection: none`，plain List 不再自動選取 `Apple`。

2026-09-01 重新量測 #556 後，P7 目前不再重現「GTK 與 Windows pane ratio 不一致」：WSLg 與 Windows 都回報 `total=420`、`currentSidebar=200`，也就是 47.6%。先前的 87px 類結論是把 content probe 寬度誤讀為 pane width。此 plan 保留作為防止量測誤讀與 regression coverage；若要繼續判定 #556，需要找出另一個仍可重現的 resize/content 情境。

## Brainstorm 結論

### #476：GTK List 初始 selection（Fixed）

最可能的原因是 GTK `ListBox` 在 rows append 或 single-selection 初始化期間自動送出 `row-selected` signal，導致 SwiftCrossUI 的 selection binding 從 `nil` 被回寫成第一列。

目前 `List.commit` 的順序大致是：

1. `setItems(...)`
2. `setSize(...)`
3. `setSelectionHandler(...)`
4. 從 binding 計算 `selectedIndex`
5. `updateSelectableListView(...)`
6. `setSelectedItem(..., nil)`

如果 GTK 在 `setItems` 或 selection 同步期間送出 signal，backend 可能會把這個程式化狀態誤判成 user selection。

實作結果：

- GtkBackend / Gtk3Backend 以 backend-side `SelectableListState` 保存目前 selection 與程式化更新狀態，不依賴 `CustomListBox`。
- `setItems` / `setSelectedItem(nil)` 期間會執行 `preserveNilSelection`，並在下一個 main-loop tick 再清一次 GTK 自動 selection。
- GTK 自動送出的 `row-selected` signal 在 nil-selection cleanup 期間不會回寫到 SwiftCrossUI binding；使用者之後手動點選仍會正常更新 binding。

驗證結果：

- GTK4：WSLg `P7` 啟動時顯示 `Selection: none`，plain List 沒有 highlighted row。
- GTK3：使用 Gtk3 backend 測試後確認同樣修正；`swift build -c release --target Gtk3Backend` 也通過。

## #476 調查步驟（完成）

1. 在 GtkBackend `setSelectionHandler` 暫時加 diagnostic log，記錄是否在初始 render 或 `setItems` 期間收到 `rowSelected = Apple`。
2. 確認 `setSelectedItem(nil)` 是否有呼叫，以及呼叫後 GTK 是否仍保留 visual selection。
3. 實作 programmatic update guard 與 nil-selection cleanup。
4. 在 WSLg 執行 P7，確認啟動時狀態列為 `Selection: none`，且 plain List 沒有 highlighted row。
5. 回歸測試：點 `Cherry`、`Clear selection`、`Select Cherry`，確認使用者互動仍會更新 binding。

## #556：NavigationSplitView pane ratio

目前觀察重點不是 collapse。2026-09-01 的 P7 WSLg/Windows 對照中，兩平台實際 pane ratio 一致：sidebar 200 / total 420。P7 step 7 / step 8 功能上穩定，且此輪未看到 pane aspect / split ratio 不一致。

仍需注意的是量測來源：P7 的 content probes 只量 pane 內內容實際佔用的寬度，不等於 pane width。sidebar content 可回報 31，而 split view 實際 sidebar 仍是 200；detail content 同理。

可疑位置：

- `SplitView.computeLayout` 讀取 `backend.sidebarWidth(ofSplitView:)`，用 backend/native paned position 反推 layout。
- GtkBackend `setSidebarWidthBounds` 使用 `splitView.getNaturalSize().width` 計算 bounds，但 P7 外層已指定 `.frame(width: 420)`，native natural width 不一定等於 SwiftCrossUI proposed width。
- Gtk4 `Paned` 有 `resizeStartChild` / `resizeEndChild` / `shrinkStartChild` / `shrinkEndChild`，目前只設定 shrink，沒有明確指定 resize policy。

可行方向：

- 先在 P7 或 inspection modifier 加上 pane width / ratio 顯示，讓 Windows 與 GTK 可用數字比較。
- 調查 GtkBackend `setSidebarWidthBounds` 是否應避免使用 native natural width，改由 SwiftCrossUI layout size 或 committed size 決定 bounds。
- 明確設定 Gtk4 Paned resize policy，讓 resize 時 detail pane 吃剩餘空間，或維持和 Windows 更接近的 sidebar/detail ratio。
- 若 backend-only 修正不足，再考慮在 SwiftCrossUI `SplitView` 保存 framework 層級的 sidebar width / ratio，避免完全依賴 native `Paned.position`。

優先順序：先保留量測，不再直接修 GtkBackend bounds / resize policy。只有在新的可重現情境證明實際 pane ratio 仍錯時，才進入 backend 修正。

## #556 調查步驟

1. 已完成：P7 記錄 split view 的 sidebar width、detail width、total width、ratio。
2. 已完成：Windows 與 WSLg/GTK 使用相同視窗大小對照，本輪兩邊實際 pane ratio 一致。
3. 已完成：P7 指定的 420 px total 有進入 SplitView 診斷。
4. 待新 repro：若其他 resize/content 情境仍顯示 ratio mismatch，再嘗試設定 Gtk4 Paned resize policy。
5. 待新 repro：若 backend-only 修正不足，再評估 `SplitView` 是否需要保存跨 backend 的 logical sidebar width。

## 建議實作順序

1. #476 已完成：signal guard 與 nil-selection cleanup 已實作並驗證。
2. #556 pane ratio instrumentation 已完成，並已取得 WSLg/Windows 數字。
3. 暫停 GtkBackend Paned bounds / resize policy 修改，直到有新的 failing scenario。
4. 重新執行 P7 Windows 與 WSLg/GTK 對照測試已完成。
5. 已更新 `UI-test-results_overall_en.md` 與 `UI-test-results_overall_zhTW.md`。

## 驗收條件

- #476 (Fixed)：P7 啟動後 plain List 沒有任何 highlighted row，狀態列顯示 `Selection: none`。
- #476 (Fixed)：點選、清除、程式設定 selection 仍正確更新 UI 與 binding。
- #556：P7 split-view detail pane 不 collapse。
- #556：Windows 與 WSLg/GTK 在相同 content size 下的 pane ratio 明顯更接近，或至少能用量測結果解釋差異來源。
- #556：加長文字與 resize 不造成 split division 跳動。
