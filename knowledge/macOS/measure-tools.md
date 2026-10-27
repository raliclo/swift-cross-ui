# macOS: measurement tools (test_support/measure)

Written 2026-10-24 from testapp/test_support/measure/README.md and the tools.

## What

Small programs that produce numbers, kept so a measurement can be re-derived.
Build each with `swiftc -O -o /tmp/<name> testapp/test_support/measure/<name>.swift`.
Tools marked **real pointer** post HID events and press whatever window is on
top: they need the Accessibility grant, and on a shared desktop an action file
is the safer choice.

| Tool | Does | Found |
| --- | --- | --- |
| `ax_dump.swift` | Prints the external AX tree of an app: buttons, static text, descriptions, values; `--children` shows what sits under each button; prints identifiers | every AXButton had an empty title (2026-09-10); `.accessibilityLabel` on a Text sat in the description while the value still read 12:30 (P69, 2026-09-17); identifiers p32.* (2026-10-19) |
| `colour_bbox.swift` | Box of one colour in a PNG (no PIL here); sample the capture first, the screen colour is not the scene's | P95 circle square at every drawable size (todo.md P2) |
| `drag_at.swift` | **Real pointer**: one drag in screen coordinates | the way to resize GTK windows; System Events `set size` does not redraw the GL area |
| `window_shots.swift` | `screencapture -l` of every on-screen window of an app, sheets included | the runner's final capture finds the window by title, so an untitled AppKit sheet never reached it (P103, 2026-10-17) |
| `real_click.swift` | **Real pointer**: one HID click, refused unless the top window at the point belongs to the named owner | separated "the component fails" from "the synthesiser does not reach a sheet" (P103) |
| `real_mouse_latency.swift` | Real mouse click to body latency on P28 | 16 ms cold, 2.9-9.9 ms warm; CGEvent through the HID tap works once the process is trusted (2026-09-10) |
| `long_press_drag.swift` | **Real pointer**: press, hold, drag in 12 steps, release | same P102 numbers as the in-process action file (2026-10-17) |
| `synthesise_magnify_probe.swift` | Tries to synthesise a trackpad magnify NSEvent | AppKit rejects type 30 ("unrecognized type is 30"); there is no public gesture initialiser. P65 gestures were later driven as HID gesture events (2026-09-30) |
| `png_diff.swift` | Pixels differing by more than a tolerance, largest difference, box | GSK shape nodes against cairo: 0 pixels over 8 (2026-10-19); a difference only in the title bar is focus |
| `gtk_frame_trace.c` + `.py` | Injected with `DYLD_INSERT_LIBRARIES`; logs GDK's CVDisplayLink start/stop, callbacks, frame-clock ticks and after-paint on one clock | GDK 4.24 stops its display link after every frame; a start <10 ms before a slot calls back one refresh late. Fixed by keeping the link running during animations (226ebb6b; P96 33 -> 59 fps) |
| `frames_during.zsh` | Takes COUNT frames while a command runs (simulator, or `mac` = whole screen 0.4 s apart), starting at a log marker | states that last only while held: P88 hover orange in 8-9 of 30 frames |

`gtk_frame_trace.c` builds with
`cc -dynamiclib -O2 ... -framework CoreVideo -L/opt/homebrew/lib -lgtk-4 -lgobject-2.0`.

## How to apply

- When a click "does nothing", photograph where the pointer went first
  (`screencapture -C`; mistakes.md entry 28) before eliminating code.
- Whole-screen frames show the rest of the desktop; keep them in a scratch
  directory.

---

# macOS:量測工具(test_support/measure)

2026-10-24 依 testapp/test_support/measure/README.md 與各工具寫成。

## 內容

產出數字的小程式，留下來讓量測能被重跑。以 `swiftc -O -o /tmp/<名稱> testapp/test_support/measure/<名稱>.swift` 建置。
標為**真實指標**的工具會送 HID 事件，按到當時最上層的視窗：需要「輔助使用」權限，在共用桌面上動作檔較安全。

| 工具 | 做什麼 | 找到什麼 |
| --- | --- | --- |
| `ax_dump.swift` | 印出 app 的外部 AX 樹：按鈕、靜態文字、description、value;`--children` 顯示每顆按鈕底下有什麼;也印 identifier | 每顆 AXButton 的標題都是空的(2026-09-10);Text 上的 `.accessibilityLabel` 只在 description,value 仍讀 12:30(P69,2026-09-17);identifier p32.*(2026-10-19) |
| `colour_bbox.swift` | PNG 中某顏色的外框(這裡沒有 PIL);先取樣擷圖，螢幕上的顏色不是場景的顏色 | P95 的圓在每種 drawable 尺寸下都是正方形(todo.md P2) |
| `drag_at.swift` | **真實指標**:在螢幕座標做一次拖曳 | 改 GTK 視窗大小要用它;System Events `set size` 不會重繪 GL area |
| `window_shots.swift` | 對 app 每個畫面上的視窗(含 sheet)做 `screencapture -l` | runner 最後的擷圖依標題找視窗，沒有標題的 AppKit sheet 拍不到(P103,2026-10-17) |
| `real_click.swift` | **真實指標**:一次 HID 點擊，該點最上層視窗不屬於指定擁有者就拒絕 | 分開「元件壞了」與「synthesiser 到不了 sheet」(P103) |
| `real_mouse_latency.swift` | P28 上真實滑鼠點擊到 body 的延遲 | 冷啟動 16 ms、熱身後 2.9–9.9 ms;行程取得信任後經 HID tap 的 CGEvent 可用(2026-09-10) |
| `long_press_drag.swift` | **真實指標**:按下、停住、分 12 步拖曳、放開 | 與行程內動作檔得到相同的 P102 數字(2026-10-17) |
| `synthesise_magnify_probe.swift` | 嘗試合成觸控板 magnify NSEvent | AppKit 拒收 type 30(「unrecognized type is 30」),沒有公開的手勢初始化方法。P65 的手勢後來以 HID 手勢事件驅動(2026-09-30) |
| `png_diff.swift` | 超過容差的像素數、最大差異、外框 | GSK shape node 對 cairo:超過 8 的像素為 0(2026-10-19);只有標題列不同是焦點造成的 |
| `gtk_frame_trace.c` + `.py` | 以 `DYLD_INSERT_LIBRARIES` 注入，在同一時鐘上記錄 GDK 的 CVDisplayLink 啟停、回呼、frame clock tick 與 after-paint | GDK 4.24 每畫完一幀就停掉 display link;在下一格前不到 10 ms 啟動會晚一次刷新才回呼。以動畫期間保持 link 運轉修正(226ebb6b;P96 33 -> 59 fps) |
| `frames_during.zsh` | 指令執行期間從 log 出現標記起擷取 COUNT 張(模擬器，或 `mac` = 整個螢幕、每 0.4 秒) | 只在按住時存在的狀態:P88 hover 30 張中 8–9 張是橘色 |

`gtk_frame_trace.c` 以 `cc -dynamiclib -O2 ... -framework CoreVideo -L/opt/homebrew/lib -lgtk-4 -lgobject-2.0` 建置。

## 如何運用

- 點擊「沒作用」時，先拍下指標去了哪裡(`screencapture -C`;mistakes.md 第 28 條),再去排除程式碼。
- 整個螢幕的擷圖會拍到桌面其他內容，放在暫存目錄。
