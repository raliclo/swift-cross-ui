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
3. #121 shortcuts: **DONE on both Windows backends, 2026-09-16.**
   `actions/win/P20-ctrl-k-shortcut.csv` replayed 5 actions on each, and
   `SHORTCUT FIRED` appears in `p20-debug-events.log` exactly **once** per run --
   not zero, which would mean the accelerator never reached the item, and not
   twice, which is the `began=5` shape this tree has hit before. Regenerate:
   `zsh testapp/compile.zsh P20 [-gtk4]`, run with `--debug -actionfile
   ../actions/win/P20-ctrl-k-shortcut.csv`, then
   `grep -c 'SHORTCUT FIRED' p20-debug-events.log`. Other backend coverage is separate.
   快捷鍵:**2026-09-16 於兩個 Windows backend 完成。** 各重放 5 個動作,
   `SHORTCUT FIRED` 每次執行**恰好出現一次**——不是 0(加速鍵沒抵達該項目),也不是 2
   (本樹曾遇過的 `began=5` 形狀)。其餘 backend 的覆蓋另計。
4. #32 gestures: drag has prior evidence; magnify/rotate need gesture input and
   callback/value checks. Do not label compile-only paths verified.
   手勢：縮放與旋轉仍待真實手勢輸入及數值驗證。
5. #122/#123 focus/accessibility: **both DONE on both Windows backends,
   2026-09-16, and both DRIVEN by action files rather than only built.**

   #122: FocusableViews now has all five backends. P70-focus.csv and
   P70-focus-gtk4.csv drive all four protocol methods plus one refusal, 13
   actions each. GtkEventControllerFocus is hand-written (zero hits in
   Sources/Gtk/Generated, none needed -- CGtk/header.h is the whole gtk.h).

   #123: Accessibility now has all five. P69 had NO Windows readback -- the
   `#else` branch printed its own success marker having read nothing -- so add
   one first; all four modifiers then read back on the right element.

   TWO LIMITS, stated so nobody has to discover them: the readback is
   in-process, so it confirms the backend ATTACHED what the modifier asked for
   and says nothing about what Narrator resolves; and GTK has NO readback at
   all, because gtkaccessible.h has update_property/update_state and no getters
   -- reading needs AT-SPI, which is Linux-only. Win-gtk4 can set these
   correctly and have nothing able to read them.

   #122/#123:**2026-09-16 於兩個 Windows backend 皆完成,且都以動作檔驅動驗證,不只是編過。**
   細節見上方英文段。**兩個限制**寫明如下,免得有人自己去踩:讀回是**行程內**的,它確認的是
   「backend 掛上了該 modifier 所要求的東西」,對 Narrator 實際解析出什麼**一句話都沒說**;
   而 **GTK 完全沒有讀回**,因為 `gtkaccessible.h` 只有 `update_property`/`update_state`、
   沒有任何 getter——要讀必須靠 AT-SPI,而那僅限 Linux。Win-gtk4 可以正確設定,卻沒有東西讀得到。
6. #79 GTK: **DONE 2026-09-16, and measured rather than hardcoded -- which was
   the whole of option (c).** The decoration IS queryable before present: create
   a window, do NOT set a titlebar, realize it, and walk its children for the
   `GtkHeaderBar` GTK built for itself. That reports 39 before the window is ever
   shown. Shortfall on an app with no menu bar went `0x-9` -> `0x0`, exact.
   #79 GTK:**2026-09-16 完成,而且是量出來的、不是寫死的——那正是選項 (c) 的全部要求。**
   該裝飾在 present 之前**是**查得到的:建一個視窗、**不要**設 titlebar、realize 它,然後走訪它的
   子節點找出 GTK 為自己建立的那條 `GtkHeaderBar`。它在視窗被顯示之前就回報 39。
   沒有選單列的 app,shortfall 由 `0x-9` 變為 `0x0`,精確。
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

- 2026-09-16 (Win-gtk4): **#79 closed by measuring GTK's own decoration, and the
  reason it resisted for so long was that every probe measured the wrong widget.**

  Three probe kinds existed and all three reported 47, while the header GTK lays
  out for itself is 39. They agreed because they were all measuring the same
  thing: a `GtkHeaderBar` this code had built, either detached or installed with
  `gtk_window_set_titlebar`. GTK's own decoration is a different instance.

  A comment in `Window.swift` blamed realization -- "an unrealized header bar
  measures 47 and the one in a live window is 39, so the difference is
  realization". That is false and is now struck through in place: the
  `.insideAWindow` branch DOES realize, and still reports 47.

  `gtk_window_get_titlebar` cannot reach GTK's own bar -- it answers only for a
  CUSTOM titlebar -- but the widget is an ordinary child, so walking the
  children finds it. `.gtkOwnDecoration` creates a window, sets no titlebar,
  realizes it, walks for a `GtkHeaderBar` and measures its minimum:

      decoration probe BEFORE present:
        headerbar bare=47 titlebarClass=47 inWindow=47 gtkOwn=39
      decoration probe AFTER map:
        GtkHeaderBar=39

  39 before present, matching what the live window lays out. Switching the
  allowance from `.bare` to `.gtkOwnDecoration`:

      P57 (no menu bar)   requested 640x700  allocated 640x700  shortfall 0x0
      P20 (menu bar)      requested 660x460  allocated 660x461  shortfall 0x-1

  Exact where there is no menu bar, and 1px on the menu-bar path -- down from 9.
  That remaining pixel is the menu-bar path's, not the titlebar's, and is not
  claimed as fixed. Regenerate with `SCUI_DEBUG_DECORATION=1 zsh
  testapp/run.zsh P57 --debug` and read the `content size settled` lines.

- 2026-09-16(Win-gtk4):**#79 以「量測 GTK 自己的裝飾」收尾,而它之所以拖了這麼久,是因為
  每一個探針量的都是錯的 widget。**

  原有三種探針全都回報 47,而 GTK 為自己排版的那條是 39。它們會一致,是因為它們量的是同一種東西:
  **這段程式碼自己建立的** `GtkHeaderBar`——不是游離的,就是用 `gtk_window_set_titlebar` 裝上去的。
  GTK 自己的裝飾是另一個實例。

  `Window.swift` 裡有一段註解把原因歸給 realize——「未 realize 的量得 47、活在視窗中的是 39,
  所以差別在 realize」。**那是錯的**,現已就地加上刪除線:`.insideAWindow` 分支**確實有** realize,
  而它依然回報 47。

  `gtk_window_get_titlebar` 構不著 GTK 自己那條(它只回答**自訂**的 titlebar),但那個 widget 是
  一個普通的子節點,因此走訪子節點就找得到。數據與結果見上方英文區塊:present 之前量到 39,
  與真實視窗的排版一致;把 allowance 由 `.bare` 改為 `.gtkOwnDecoration` 之後,無選單列的 app
  shortfall 為 `0x0`(精確),有選單列的為 `0x-1`(原本是 −9)。**剩下那 1px 屬於選單列路徑、
  不屬於 titlebar,此處不宣稱它已修好。**

- 2026-09-16 (Windows): **#121 verified on both backends, after a harness fix
  that is worth more than the item itself.**

  The replay refused every key-carrying file whenever another application held
  the foreground, reporting `AttachThreadInput ... failed (87)`. 87 is
  ERROR_INVALID_PARAMETER, not the ACCESS_DENIED the code anticipated: the
  foreground was a `ConsoleWindowClass` window belonging to PowerToys.Awake.exe,
  and a console host thread cannot be attached to.

  `Win32Synthesiser.takeForegroundByAttachingInput` was judging the MECHANISM
  rather than the OUTCOME -- it returned false the moment the attach failed,
  without ever asking for the foreground. `SetForegroundWindow` is permitted for
  several reasons besides an attached input queue. It now asks anyway and reads
  `GetForegroundWindow()` back, which is what the function's own verification
  loop was already doing on the other path.

  With that, both backends pass without touching the offending application:

      Win-WinUI   replayed 5 actions   SHORTCUT FIRED x1   (took the foreground
                                                            WITHOUT attaching)
      Win-gtk4    replayed 5 actions   SHORTCUT FIRED x1   (attached to Progman)

  Exactly once is the assertion. Zero would mean the accelerator never reached
  the item; twice is the `began=5` shape.

- 2026-09-16(Windows):**#121 於兩個 backend 驗證通過,而其中那個 harness 修正,價值高過這個項目本身。**

  只要有別的應用程式佔著前景,該 replay 就會拒絕每一個含按鍵的檔案,回報
  `AttachThreadInput ... failed (87)`。87 是 ERROR_INVALID_PARAMETER,**不是**程式碼所預期的
  ACCESS_DENIED:當時的前景是 PowerToys.Awake.exe 的一個 `ConsoleWindowClass` 視窗,
  而 console host 的執行緒是附加不上去的。

  `Win32Synthesiser.takeForegroundByAttachingInput` 判定的是**機制**而非**結果**——attach 一失敗
  就回傳 false,從未真的去請求前景。而除了「輸入佇列已附加」之外,`SetForegroundWindow` 在數種情況下
  同樣被允許。現在它會照樣請求,並把 `GetForegroundWindow()` 讀回來驗證——那正是該函式在另一條路徑上
  本來就在做的事。

  如此一來,**不必動到那個佔著前景的應用程式**,兩個 backend 都通過(數字見上方英文區塊)。
  **恰好一次**才是那個斷言:0 代表加速鍵從未抵達該項目,2 則是 `began=5` 的形狀。

- 2026-09-16 (Windows, later the same day): **WinUI's rows render, and the cause
  was one line.** A container WinUI GENERATES for a data item carries a
  `ContentTemplate` whose job is to render that item -- here the boxed `Int32`
  placeholder. A `UIElement` assigned as `Content` is normally shown directly,
  but not while a template is in place to render it through: the element goes in
  and nothing comes out. Clearing `container.contentTemplate` before assigning
  the content fixes it. The eager path never hit this, which is exactly what made
  it such a good control -- it builds its own `ListViewItem`s, and those have no
  template.

  The conformance is back on. Re-measured with rows actually rendering:

  | rows | eager (control) | lazy |
  | --- | --- | --- |
  | 1 | -- | 130 MB |
  | 400 | 143 MB | 139 MB |
  | 10,000 | **328 MB** | **146 MB** |

  Pointer pass, `actions/win/P57-lazy-list-winui.csv`, 20 actions replayed --
  the same sequence GTK passed, at WinUI's own coordinates:

      selection=1 -> selection=9   same y after six wheel notches, so it scrolled
      revision=1                   content update reached the rows
      selection=none               Clear
      rows=1 -> rows=10000         count both ways
      selection=9999               selected outside the realized window
      selection=none               Clear again

  Capture `screen-20260916-081927.png`: 96.0% non-black, rows reading
  "row N revision 1". Both Windows backends now pass memory, scrolling, pointer
  selection, content update and count change.

  **Three hypotheses were guessed before the first probe was written, and all
  three were wrong.** Reading the container back after the assignment is what
  ruled out "the assignment failed"; reading `row.widget.parent` is what ruled
  out "the widget is already parented". Both probes were a few lines.

- 2026-09-16(Windows,同日稍晚):**WinUI 的列算繪出來了,而成因只有一行。** WinUI 為某個
  data item **產生**的容器,會帶著一個 `ContentTemplate`,其職責是算繪那個 item——此處就是那個
  boxed `Int32` 佔位值。一個被指派為 `Content` 的 `UIElement` 通常會被直接顯示,**但在「還有一個
  template 要拿來算繪它」的情況下並非如此**:元素進得去,卻什麼都出不來。在指派內容之前先清掉
  `container.contentTemplate` 即可修正。eager 路徑從未遇上這件事,而那正是它作為對照組如此好用的
  原因——它是自己建 `ListViewItem` 的,那些沒有 template。

  conformance 已接回。在**列確實算繪**的前提下重新量測(數字見上表),並以
  `actions/win/P57-lazy-list-winui.csv` 重放 20 個動作,走完與 GTK 相同的序列:
  `selection=1 → selection=9`(同一個 y、滾輪六格之後,代表確實捲動了)、`revision=1`、
  `selection=none`、`rows=1 → rows=10000`、`selection=9999`(選到已實體化窗口之外)、`selection=none`。
  擷圖 `screen-20260916-081927.png`:非黑 96.0%,列文字為「row N revision 1」。
  **兩個 Windows backend 現在在記憶體、捲動、指標選取、內容更新與列數變更上全部通過。**

  **在寫下第一個探針之前猜了三次,三次全錯。** 「指派之後把容器讀回來」排除了「指派失敗」;
  「讀 `row.widget.parent`」排除了「該 widget 已經有 parent」。兩個探針都只有幾行。

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
