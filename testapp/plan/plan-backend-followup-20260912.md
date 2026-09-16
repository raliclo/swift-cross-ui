# Backend follow-up / Backend 接續工作

Updated 2026-09-14 on develop. Verify WSLg first, then Windows. A build is not
a GUI pass. Preserve action files, logs and screenshots; use PIL measurements
for geometry or visual assertions. No commit is requested for this work yet.

2026-09-14，develop。先 WSLg，再 Windows。編譯通過不等於 GUI 通過；保留動作檔、
log 與截圖，幾何及外觀判定須有 PIL 量測。本次尚未要求 commit。

1. #117 GTK: in progress. Connect the existing ListView draft to LazyListRows;
   test P57 at 1/400/10,000 rows, scroll, change content/count and clear selection.
   GTK：進行中。接入 LazyListRows，驗證列數、捲動、內容更新與 nil selection。
2. #117 Android: pending implementation and emulator/device verification.
   Android：待實作及模擬器或實機驗證。
3. #121 shortcuts: Windows implementations compiled previously; Ctrl+K replay
   still needs to prove one callback on GTK/WinUI. Other backend coverage is separate.
   快捷鍵：待 GTK/WinUI 動作重放確認一次按鍵只觸發一次。
4. #32 gestures: drag has prior evidence; magnify/rotate need gesture input and
   callback/value checks. Do not label compile-only paths verified.
   手勢：縮放與旋轉仍待真實手勢輸入及數值驗證。
5. #122/#123 focus/accessibility: protocol plan exists; inspect and implement
   GTK/WinUI reporting and native accessibility exposure.
   焦點／無障礙：待 GTK/WinUI 實作與原生讀取驗證。
6. #79 GTK: content-height shortfall remains open; measure native frame/content
   sizes before choosing compensation, without a hardcoded 39-pixel allowance.
   GTK 高度差：待量測及修正，不以固定 39px 補償。
7. P38/P41 WinUI: reproduce WebView completion and graphical DatePicker binding
   against current sources before changing their implementations.
   WebView／DatePicker：先以現行版本重現 callback 與 binding 問題。
8. #125 Table: selection and sorting need backend-to-view events and tests.
   Table：待 selection／sortOrder 回報與驗證。
9. #109 popover: arrowEdge hint implementation and placement tests remain.
   Popover：待 arrowEdge 提示及位置驗證。
10. #128: already implemented in source. PaddingModifier.swift has Double top,
    bottom, leading and trailing. Fractional-padding regression verification is
    still distinct from this source check; do not repeat the Int-to-Double change.
    EdgeInsets：原始碼已完成 Double 化；小數 padding 回歸驗證另計。

## Verification log / 驗證紀錄

- 2026-09-16 (Windows): **the visual and pointer pass GTK owed is DONE, and it
  found that WinUI's half has never rendered.**

  GTK4, driven by `actions/win/P57-lazy-list-gtk4.csv` (25 actions replayed, real
  synthesised pointer input, not an API probe). The app's own log:

      selection=1                 click selected row 1
      selection=10                after 6 wheel clicks at the SAME y -- the list
                                  scrolled, so the click landed on a different row
      revision=1                  Update rows
      selection=none              Clear
      rows=1 -> rows=10000        Toggle count both ways
      selection=9999              Select last, far outside the realized window
      selection=none, selection=1 clear and re-select

  Capture `screen-20260916-074154.png`: 92.2% non-black, bbox (14,12)-(654,759),
  every row reading "row N revision 1" with row 1 highlighted. Scroll, pointer
  selection, content update, count change and virtualization boundary all pass.

  **WinUI: the rows do not render, and never have.** Commit bde16de0 recorded
  the memory win and said "NOT visually confirmed"; it now is confirmed, as a
  failure. Three arrangements were measured, all at 10,000 rows:

      content set in phase 0           rows draw their placeholder index, "0",
                                       "1", "2" -- ListViewBase's preparation
                                       runs after the handler and assigns
                                       Content from the data item
      args.handled = true              blank; preparation skipped wholesale,
                                       including presenting the content. Probe
                                       read back content=Canvas, so the
                                       assignment itself had worked
      registerUpdateCallback, later    blank; the callback fires and replaces the
      phase                            placeholder (the numbers vanish) and the
                                       Canvas still shows nothing

  The EAGER path renders correctly with the same Canvas widgets in the same
  ListViewItem containers -- `screen-20260916-080315.png`, "row 0 revision 0"
  down the list -- so a Canvas can be a ListViewItem's content and the difference
  is somewhere in the lazy path, not yet found.

  **The WinUI conformance is therefore withheld** (the `: BackendFeatures
  .LazyListRows` is off the extension in `WinUIBackend+LazyListRows.swift`, with
  the evidence in a header comment). The backend is back on the correct eager
  path at its memory cost. Both backends build 0 errors after the change.

  **What this cost is worth recording:** the memory ladder could not see any of
  it. Containers virtualized and the provider was called in all three broken
  arrangements, so 10,000 rows measured flat at 143 MB against 328 eager every
  time. Right size, right cost, wrong content -- and only a screenshot separated
  them.

- 2026-09-16(Windows):**GTK 所欠的外觀與指標驗證已完成,並且發現 WinUI 那一半從未算繪過。**

  GTK4 由 `actions/win/P57-lazy-list-gtk4.csv` 驅動(重放 25 個動作,真實合成指標輸入,不是 API 探針)。
  app 自己的 log 依序記下:選取第 1 列 → 滾輪 6 格後在**同一個 y** 點擊得到 `selection=10`(代表清單
  確實捲動了)→ `revision=1` → `selection=none` → `rows=1` → `rows=10000` → `selection=9999`
  (遠在已實體化窗口之外)→ 清除並重新選取。擷圖 `screen-20260916-074154.png`:非黑 92.2%、
  bbox (14,12)-(654,759)、每一列都是「row N revision 1」且第 1 列高亮。捲動、指標選取、內容更新、
  列數變更與虛擬化邊界全部通過。

  **WinUI:那些列畫不出來,而且從來沒畫出來過。** 提交 `bde16de0` 記下了記憶體的成果並註明
  「未經視覺確認」;現在確認了,而結果是失敗。三種安排都在一萬列下量過(見上方英文表)。
  **eager 路徑用同樣的 Canvas widget、放在同樣的 ListViewItem 容器裡,算繪是正確的**
  (`screen-20260916-080315.png`),因此差異在 lazy 路徑上,目前尚未找到。

  **因此 WinUI 的 conformance 被收回**(`WinUIBackend+LazyListRows.swift` 的 extension 上已拿掉
  `: BackendFeatures.LazyListRows`,證據寫在該檔的檔頭註解)。該 backend 回到正確的 eager 路徑,
  代價是記憶體。改動後兩個 backend 建置皆 0 錯誤。

  **這次的代價值得記下:** 記憶體階梯**看不到**上述任何一種失敗。三種壞掉的安排裡,容器都有虛擬化、
  provider 都有被呼叫,因此一萬列每次都平穩地量到 143 MB(對照 eager 的 328 MB)。尺寸對、成本對、
  內容錯——而只有截圖能把它們分開。

- 2026-09-15 (Windows GTK4): the eager CONTROL was taken, which the earlier
  260-288 MB figure lacked. Conformance dropped, rebuilt, measured, restored,
  rebuilt; both backends 0 errors afterwards. Working set via tasklist:

  | rows | eager (control) | lazy |
  | --- | --- | --- |
  | 1 | 257 MB | 256 MB |
  | 400 | 270 MB | 266 MB |
  | 10,000 | **410 MB** | **265 MB** |

  Lazy is FLAT: 1 -> 10,000 costs +9 MB, against +153 MB eager. 145 MB saved at
  10,000 rows. The lazy 10,000 figure sits 9 MB ABOVE its own one-row baseline,
  which is what says rows are really being built rather than the list being
  empty -- the failure mode plan-117 warns about. Matches the 205/206 realized
  containers recorded on 2026-09-14, and the same shape as WinUI (328 -> 143).

  Regenerate: `zsh testapp/compile.zsh P57 -gtk4`, then
  `zsh testapp/run.zsh P57 --debug -rows N` and read Mem Usage from
  `tasklist //fi "IMAGENAME eq P57-gtk4.exe"`. For the control, drop
  `: BackendFeatures.LazyListRowLifetimes` from
  `Sources/GtkBackend/GtkBackend+LazyListRows.swift` and rebuild.

  NOT covered by this: scrolling, visuals, and pointer selection. A memory
  ladder says nothing about any of them.

- 2026-09-15 (Windows GTK4):取得了 eager **對照組**——先前 260-288 MB 那個數字缺的正是它。
  作法為移除 conformance、重建、量測、還原、再重建;事後兩個 backend 皆 0 錯誤。工作集取自 tasklist:

  | 列數 | eager(對照) | lazy |
  | --- | --- | --- |
  | 1 | 257 MB | 256 MB |
  | 400 | 270 MB | 266 MB |
  | 10,000 | **410 MB** | **265 MB** |

  lazy 是**平的**:1 → 10,000 只多 9 MB,而 eager 多了 153 MB;在一萬列時省下 145 MB。
  lazy 的一萬列數字比它**自己的**單列基準高出 9 MB,而那正是「列確實有被建出來、清單不是空的」
  的證據——那是 plan-117 所警告的失效樣態。與 2026-09-14 記錄的 205/206 個已實體化容器一致,
  也與 WinUI(328 → 143)是同一個形狀。

  **本次未涵蓋**:捲動、外觀與指標選取。一條記憶體階梯對這三者一句話都沒說。
  Build only under /home/lowei/proj/swift-cross-ui, never /mnt/c.
- GTK #117 now has a LazyListRows conformance and a native GtkListView factory.
  WSL release P57 builds. The 10,000-row startup reported 202 MB and reached
  RENDER COMPLETE. This is not a memory-scaling or visual pass yet.
- WSLg hardware preflight: D3D12 (NVIDIA GeForce RTX 4060 Laptop GPU).
  The earlier black captures came from a stale WSLg COPY MODE bridge and the
  old PrintWindow-only helper. Wincap now uses Windows Graphics Capture first.
  After `wsl --shutdown` and restart, COPY MODE disappeared and WGC captured
  the GL window directly at 92.2% non-black.
- Found a shared lazy-List regression: commit returned before installing the
  selection handler, applying selection or updating style; restored these calls.
- Fixed the provider committing cached layout probes; GTK now releases row nodes
  on native unbind instead of relying on an LRU smaller than GTK's overscan.
- Final lifetime implementation built in release on WSL and Windows GTK4.
  WSL native probes at 1/400/10,000 rows settled at 320/326/327 MB. The final
  10,000-row sequence stayed at 327-328 MB. Containers changed 205/206 -> 1 -> 205
  when scrolling and changing count. Selection started nil, became 9999, then
  cleared. Both first and last labels updated to revision 1.
- 2026-09-14 Windows GTK4 repeated the seven-phase native probe and remained
  open for 30 seconds after the render marker. Selection, content and count
  transitions matched WSL; memory ranged 260-288 MB after settling. Allocated
  list size changed from 608x332 to 608x340 (WSL: 608x305). These are native
  geometry readings, not screenshot-based geometry approval.
- Final GL captures now pass on both platforms: WSLg 92.2% and Windows 92.1%
  non-black. PIL measured both at 668x776 with bbox (14,12)-(654,759).
  Evidence: output/screenshots/p57-wslg-final-20260914-102707.png and
  output/screenshots/p57-windows-final-20260914-102723.png. Native-state evidence
  remains in output/p57-gtk-windows-10000-final.log and the Linux checkout's
  output/p57-gtk-10000-final.log.
- Probe calls GTK selection/scroll/button APIs; it is not real pointer replay.
  The saved smoke action files are observation-only and were not replayed in
  these runs. Pointer input, visual correctness and WinUI regression remain open.

GTK 接入與生命週期修正已通過 WSL、Windows GTK4 release 編譯、原生狀態及截圖測試。
兩端皆確認初始 nil、選取末列、清除選取、更新首尾文字及 10,000 -> 1 -> 10,000 列。
試算 layout commit 問題已修正。wincap 改用 WGC，並重啟過期的 WSLg COPY MODE bridge 後，
兩端 GL 截圖均通過；PIL 尺寸與內容邊界一致。真實滑鼠操作及 WinUI 回歸仍待驗證。
