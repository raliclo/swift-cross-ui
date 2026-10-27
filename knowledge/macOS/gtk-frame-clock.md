# GtkBackend on macOS: the frame clock at the display rate

## What

GDK 4.24 on macOS stops its CVDisplayLink after every presented frame and starts
it again from the next paint. A CVDisplayLink started less than about 10 ms
before the next callback slot calls back one refresh late. So an animation ran
at 33-58 fps depending on where in the refresh each paint ended, with the main
thread mostly idle.

`Sources/GtkCHelpers/gtk_display_link_macos.c` (226ebb6b, 2026-10-19) replaces
libgtk-4's imports of `CVDisplayLinkStart`, `CVDisplayLinkStop` and
`CVDisplayLinkRelease` (its `__got` slots, found by name through the indirect
symbol table) with functions that keep a link running while
`scui_macos_display_link_keep_running(1)` is on. GtkBackend turns it on in
`startFrameClock` and off in `stopFrameClock`, so the link stops when
animations end. GDK's own paused flag is untouched: its source still ignores
callbacks while GDK has it paused.

## How it was found

`testapp/test_support/measure/gtk_frame_trace.c`, injected with
`DYLD_INSERT_LIBRARIES` (build and run lines in `measure/README.md`), logs GDK's
display-link starts and stops, every callback, and every frame-clock tick and
after-paint on one clock; `gtk_frame_trace.py` summarises a window. One P96 run:
498 ticks, 498 starts, 497 stops. Starts 0-10 ms before the slot: 0 on time, 147
late; 12-18 ms before: 95 on time, 2 late. Tick to start: median 3-4 ms. The
frames themselves took 3-4 ms.

## Measured effect

| | before | after |
|---|---|---|
| P96 driven panel, ticks per 3 s | 103/100/103 (33-34 fps) | 177/177/176 (58.7-59 fps) |
| P96 dots alone, ticks per 3 s | 173/169/174 | 180/180/180 (60.0 fps) |
| P104 WITH, frames in 1 s | 58/35/33 | 61/61/60/61 |

(results.csv2: mac, gtk4, P96 and P104, 2026-10-19.) Curve error stayed 0.000 pt.

## Related fixes and findings

- **First tick after an idle period.** After an animation ended, the next GTK
  frame-clock start gave its first tick 1.5-4.2 s late (end_updating then
  begin_updating with nothing invalidated). A 60 Hz main-queue tick now runs until
  the first clock tick arrives; the first tick then came 0.05 s after P108's
  second fling (results.csv2: mac, gtk4, P108, 2026-10-19).
- **Shapes as GSK nodes** (f84ee359, 2026-10-19). With GskPath (GTK 4.14+) a
  Shape is flattened once and drawn as GSK fill and stroke nodes; the cairo draw
  function replayed and re-uploaded every stroke each frame (about 2.7 -> 0.8 ms
  a frame in P96). `SCUI_GTK_CAIRO_PATHS=1` keeps the cairo path for comparison.
  `measure/png_diff.swift` on window captures of both: P27 and P40 identical,
  P43 at most 7/255, P89 at most 2. The frame rate did not follow this change; the
  display link above was the limit.
- **Effects via the GtkFixed child transform**, not CSS (see
  `gtk-css-and-metrics.md`).

## Limits (open)

- **First tick ~0.15 s after the call** (P97, checked 2026-10-20). onAppear runs
  inside the window's first probe layout, which took 112 ms; 82-90 ms of it was
  the first text measurement, Pango creating its font map. A warm-up on a
  background thread with its own font map did not help (the cost is per font
  map); GSK_RENDERER cairo, gl and default all gave 0.134-0.146 s. Nothing is
  changed; AppKit's first tick is about 0.11 s. On 2026-10-22 a sweep run read a
  0.42 s first tick (results.csv2: mac, gtk4, P97, 2026-10-22), unexplained.
- **One slow first animation.** In one P105 run the first step took 14.7 s with
  4 frames (the frame clock started late for the app's first animation); the
  other run gave 1.03 s (results.csv2: mac, gtk4, P105, 2026-10-19). Not
  reproduced or explained.
- P106 PHASE was one frame outside its 17 ms limit in one of three runs
  (2026-10-19); PHASE goes through code the velocity change did not touch.

---

# macOS 上的 GtkBackend:讓幀時鐘跟上螢幕更新率

## 是什麼

macOS 上的 GDK 4.24 每呈現一幀就停掉 CVDisplayLink,下一次繪製時再啟動。在下一個回呼時槽前不到約 10 ms 才啟動的
CVDisplayLink,會晚一次更新才回呼。所以動畫的幀率取決於每次繪製結束在更新週期的哪個位置，在 33–58 fps 之間，而主執行緒大多閒置。

`Sources/GtkCHelpers/gtk_display_link_macos.c`(226ebb6b,2026-10-19)把 libgtk-4 對 `CVDisplayLinkStart`、
`CVDisplayLinkStop`、`CVDisplayLinkRelease` 的匯入(其 `__got` 槽，經 indirect symbol table 依名稱找到)換成自己的函式：
`scui_macos_display_link_keep_running(1)` 期間讓 link 持續執行。GtkBackend 在 `startFrameClock` 開啟、`stopFrameClock`
關閉，動畫結束後 link 就停。GDK 自己的 paused 旗標不動。

## 怎麼找到的

`testapp/test_support/measure/gtk_frame_trace.c` 以 `DYLD_INSERT_LIBRARIES` 注入(指令見 `measure/README.md`),在同一個時鐘上
記錄 GDK 的 display link 啟停、每次回呼、每次 tick 與 after-paint。一次 P96 執行:498 次 tick、498 次啟動、497 次停止。在時槽前
0–10 ms 啟動的：準時 0、遲到 147;12–18 ms 前：準時 95、遲到 2。tick 到啟動中位數 3–4 ms,每幀本身只花 3–4 ms。

## 量到的效果

| | 之前 | 之後 |
|---|---|---|
| P96 driven 面板，每 3 秒 tick 數 | 103/100/103(33–34 fps) | 177/177/176(58.7–59 fps) |
| P96 只有點，每 3 秒 tick 數 | 173/169/174 | 180/180/180(60.0 fps) |
| P104 WITH,1 秒內幀數 | 58/35/33 | 61/61/60/61 |

(results.csv2:mac、gtk4、P96 與 P104,2026-10-19。)曲線誤差維持 0.000 pt。

## 相關修正與發現

- **閒置後的第一個 tick。** 動畫結束後，下一次 GTK 幀時鐘啟動的第一個 tick 晚 1.5–4.2 秒。現在在第一個時鐘 tick 到來前先跑
  60 Hz 的 main queue tick;P108 第二次甩動後 0.05 秒就有第一個 tick(results.csv2:mac、gtk4、P108、2026-10-19)。
- **Shape 改為 GSK 節點**(f84ee359,2026-10-19)。有 GskPath(GTK 4.14+)時，路徑只攤平一次並以 GSK fill/stroke 節點繪製；
  cairo 版每幀重播並重新上傳每一條筆畫(P96 每幀約 2.7 → 0.8 ms)。`SCUI_GTK_CAIRO_PATHS=1` 保留 cairo 路徑供比對。
  `measure/png_diff.swift` 比對兩種模式的視窗擷圖:P27、P40 相同,P43 最多差 7/255,P89 最多 2。幀率沒有因此提升，瓶頸是上述 display link。
- **效果走 GtkFixed child transform** 而非 CSS(見 `gtk-css-and-metrics.md`)。

## 限制(未解)

- **第一個 tick 約在呼叫後 0.15 秒**(P97,2026-10-20 確認)。onAppear 在視窗第一次探測排版裡執行，該排版花 112 ms,其中
  82–90 ms 是第一次量文字時 Pango 建立 font map。在背景執行緒以自己的 font map 預熱無效(成本是每個 font map 一次);
  GSK_RENDERER 用 cairo、gl、預設都是 0.134–0.146 秒。未改程式;AppKit 約 0.11 秒。2026-10-22 一次 sweep 讀到 0.42 秒，
  原因不明(results.csv2:mac、gtk4、P97、2026-10-22)。
- **一次很慢的第一個動畫。** 某次 P105 的第一步花了 14.7 秒、只有 4 幀(app 第一個動畫的幀時鐘晚啟動);另一次是 1.03 秒
  (results.csv2:mac、gtk4、P105、2026-10-19)。未重現、未解釋。
- P106 的 PHASE 三次中有一次超出 17 ms 上限一幀(2026-10-19);PHASE 走的程式碼與該次修改無關。
