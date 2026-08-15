# P7 修正計畫

## 目標

P7 用來追蹤 Linux/GTK backend 的 List 與 NavigationSplitView 行為，主要涵蓋：

- #476 (Fixed)：GTK/Gtk3 backend 上 `List` 啟動時不應自動選取第一項。
- #556 (Open)：GTK backend 上 `NavigationSplitView` 的 pane aspect / split ratio 應接近 Windows，且 resize 後仍維持合理比例。

目前測試結果顯示：#476 已修正並由 GTK4/GTK3 確認；P7 啟動時 selection 綁定維持 `nil`，狀態列顯示 `Selection: none`，plain List 不再自動選取 `Apple`。#556 仍為 Open：split-view pane ratio 和 Windows 明顯不同，需要後續調查。

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

目前觀察重點不是 collapse，而是 Windows 與 WSLg/GTK 的 pane aspect / split ratio 不一致。P7 step 7 / step 8 功能上穩定，但 #556 仍為 Open。

可疑位置：

- `SplitView.computeLayout` 讀取 `backend.sidebarWidth(ofSplitView:)`，用 backend/native paned position 反推 layout。
- GtkBackend `setSidebarWidthBounds` 使用 `splitView.getNaturalSize().width` 計算 bounds，但 P7 外層已指定 `.frame(width: 420)`，native natural width 不一定等於 SwiftCrossUI proposed width。
- Gtk4 `Paned` 有 `resizeStartChild` / `resizeEndChild` / `shrinkStartChild` / `shrinkEndChild`，目前只設定 shrink，沒有明確指定 resize policy。

可行方向：

- 先在 P7 或 inspection modifier 加上 pane width / ratio 顯示，讓 Windows 與 GTK 可用數字比較。
- 調查 GtkBackend `setSidebarWidthBounds` 是否應避免使用 native natural width，改由 SwiftCrossUI layout size 或 committed size 決定 bounds。
- 明確設定 Gtk4 Paned resize policy，讓 resize 時 detail pane 吃剩餘空間，或維持和 Windows 更接近的 sidebar/detail ratio。
- 若 backend-only 修正不足，再考慮在 SwiftCrossUI `SplitView` 保存 framework 層級的 sidebar width / ratio，避免完全依賴 native `Paned.position`。

優先順序：先加量測，再修 GtkBackend bounds / resize policy；暫時避免一開始就大改 core `SplitView`。

## #556 調查步驟

1. 讓 P7 顯示或記錄 split view 的 sidebar width、detail width、total width、ratio。
2. 在 Windows 與 WSLg/GTK 使用相同視窗大小截圖，確認差異是否來自 content area、window decoration、DPI scaling，或 GTK Paned allocation。
3. 檢查 GtkBackend `setSidebarWidthBounds` 中 `getNaturalSize().width` 的實際值是否等於 P7 指定的 420 px。
4. 嘗試設定 Gtk4 Paned resize policy，並比較 resize 前後 pane ratio。
5. 若 ratio 仍不一致，再評估 `SplitView` 是否需要保存跨 backend 的 logical sidebar width。

## 建議實作順序

1. #476 已完成：signal guard 與 nil-selection cleanup 已實作並驗證。
2. 為 #556 加 pane ratio instrumentation，先取得數字。
3. 調整 GtkBackend Paned bounds / resize policy。
4. 重新執行 P7 Windows 與 WSLg/GTK 對照測試。
5. 更新 `UI-test-results_overall_en.md` 與 `UI-test-results_overall_zhTW.md`。

## 驗收條件

- #476 (Fixed)：P7 啟動後 plain List 沒有任何 highlighted row，狀態列顯示 `Selection: none`。
- #476 (Fixed)：點選、清除、程式設定 selection 仍正確更新 UI 與 binding。
- #556：P7 split-view detail pane 不 collapse。
- #556：Windows 與 WSLg/GTK 在相同 content size 下的 pane ratio 明顯更接近，或至少能用量測結果解釋差異來源。
- #556：加長文字與 resize 不造成 split division 跳動。
