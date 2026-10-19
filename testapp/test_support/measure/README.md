# measure/ — 兩支一次性的量測工具,留下來是為了讓結論可以被重跑

這裡的東西**不是測試**,它們不會通過或失敗;它們產生數字。放在樹裡的理由只有一個:
一個沒有辦法重新導出的量測,與一個猜測讀起來一模一樣。

Neither of these is a test. They produce numbers, and they live here because a
measurement nobody can re-derive reads exactly like a guess.

## `real_mouse_latency.swift` — P28 的那兩條未量路徑

```sh
swiftc -O -o /tmp/realmouse testapp/test_support/measure/real_mouse_latency.swift
/tmp/realmouse /tmp/p28.log "$PWD/testapp/output/P28"
```

它啟動 P28、用 accessibility API 找到那顆按鈕、以 `CGEvent.post(tap: .cghidEventTap)`
送出**真正的**滑鼠事件,再從 P28 自己寫的 `click at uptime` 那一行讀回抵達時間。兩端都用
`ProcessInfo.systemUptime`,那是機器層級的時鐘,因此不需要對齊任何東西。

**它需要 Accessibility 授權。** `AXIsProcessTrusted()` 為 false 時,`CGEvent.post` 會
**靜默地**送出 0 個事件——那正是 `AppKitSynthesiser` 的檔頭所記錄的量測,也正是「這條路徑
合成不出來」這個說法的由來。2026-09-10 在已授權的機器上重量,它會送達。

## `ax_dump.swift` — 列出一支 app 的每一顆 AXButton 叫什麼名字

```sh
swiftc -O -o /tmp/axdump testapp/test_support/measure/ax_dump.swift
/tmp/axdump "$PWD/testapp/output/P34"
```

它就是抓到「每一個 `AXButton` 的 title 與 desc 都是空的」那一支。修好之後,同一支工具會
印出 `desc='Show +100'`——**同一個量測、修前修後各跑一次**,而不是換一個更容易通過的量測。

It is the tool that caught every `AXButton` having an empty title and
description, and the same tool prints the labels afterwards -- the same
measurement before and after, not an easier one after.


## `synthesise_magnify_probe.swift` — 能不能合成一個觸控板手勢?**不能**,而這是證據

```sh
swiftc -O -o /tmp/magnify testapp/test_support/measure/synthesise_magnify_probe.swift
/tmp/magnify
```

它開一個帶 `NSMagnificationGestureRecognizer` 的視窗,然後嘗試唯一一條由公開 API 組成的途徑:
用 `CGEvent(source:)` 建事件、把 `type` 設為 30(`NSEventTypeMagnify`)、在欄位 113 放進倍率、
以 `NSEvent(cgEvent:)` 包起來,再用 `NSApp.postEvent` 投遞——那正是 `AppKitSynthesiser` 投遞點擊所
使用的同一條路徑。

2026-09-11 的結果:

```
2026-09-11 06:54:15.770 magnify[77923] unrecognized type is 30
built an NSEvent of type 30
RESULT fired=0 lastMagnification=0.0
```

那個 `NSEvent` **建得起來**、也被投遞了,而 AppKit 拒絕了它:`unrecognized type is 30`。一個真正的
手勢事件帶著 `CGEvent(source:)` 不會填入的東西(手勢階段、裝置識別),而 `NSEvent` 沒有任何公開的
gesture 初始化器——只有 `mouseEvent`、`keyEvent`、`otherEvent`、`enterExit`。

**這就是「已嘗試的具體 API 與它的結果」**,而不是憑印象的斷言。P65 的縮放與旋轉因此仍然只能由
「一雙手在觸控板上」驅動;拖曳不受影響,它走的是真實滑鼠事件,已經量過。

Route tried and closed: build a `CGEvent`, set `type` to 30, wrap it with
`NSEvent(cgEvent:)`, post it through the same path clicks use. The event is
built and delivered; AppKit rejects it with "unrecognized type is 30". There is
no public gesture initialiser on `NSEvent`. This is the specific API and what it
did, rather than a claim from memory.

## `p69_atspi.zsh` + `p69_atspi.py` — P69 在**外部** AT-SPI 上長什麼樣子(Linux/WSLg)

```sh
cd ~/proj/swift-cross-ui/testapp/output
dbus-run-session -- zsh ../test_support/measure/p69_atspi.zsh "$PWD/P69"
```

需要 `python3-pyatspi`。以行程 ID 挑出 P69,走訪整棵樹並印出 JSON,再檢查 label、hint、value、
隱藏與「原本的 `X` 不應出現」。2026-09-17 的結果不是完整通過:`X` 子節點仍在,詳見
`testapp/plan/verification-followup-20260917.md`。

Reads P69 through the external AT-SPI bus -- what a screen reader sees -- rather
than P69's in-process readback. The 2026-09-17 run is not a full pass: the
original `X` child is still exposed.

**Later on 2026-09-17:** that was fixed in GtkBackend, and the probe gained two
checks for `.accessibilityLabel` on a `Text` (`text_label`,
`no_original_text`). WSLg run: all 7 checks true, exit 0.
**2026-09-17 稍晚:** 上述問題已在 GtkBackend 修正;探針新增兩項 `Text` 上 `.accessibilityLabel` 的
檢查。WSLg:7 項全過、exit 0。

## `p69_uia.zsh` + `uia_tree.c` — P69 在**外部** UI Automation 上長什麼樣子(Windows)

```sh
zsh testapp/test_support/measure/p69_uia.zsh testapp/output/P69-WinUI.exe
```

The WinUI counterpart of the AT-SPI probe, with the same seven checks. It runs
each check in both the CONTROL and the CONTENT view, and names the view in
every dump (`testapp/output/p69-uia-<view>.txt`), because a raw-view reading
lists elements a screen reader never reaches. It builds `uia_tree.c` with clang
on first use.
2026-09-17: 14/14 true and exit 0 on P69-WinUI. The negative control is
P69-gtk4.exe, the GTK build on Windows, which has no accessibility backend (see
todo.md): exit 1, with label, hint, value and text_label all false. That shows
the checks can fail.
Later the same day, two UIA-only checks were added, `derived_names` and
`no_duplicate_text`, which test that an unlabelled button is named from its
text. Both were false on the previous build. After the WinUIBackend fix:
18/18, exit 0.
同日稍晚新增兩項僅 UIA 的檢查(未設標籤按鈕以文字命名、文字不重複);前一版建置兩項皆 false,
WinUIBackend 修正後 18/18、exit 0。

WinUI 版的外部探針,七項檢查與 AT-SPI 版相同,在 **control** 與 **content** 兩個 view 各跑一次,並在每份
傾印中寫明 view——raw view 會列出螢幕閱讀器走不到的元素。第一次使用時以 clang 建置 `uia_tree.c`。
2026-09-17:P69-WinUI 14/14、exit 0;反向對照為 Windows 上的 P69-gtk4.exe(無無障礙後端):exit 1,
label/hint/value/text_label 皆為 false——證明檢查不是空轉。

## `colour_bbox.swift` — 一種顏色在截圖中的外框(代替 PIL)

```sh
swiftc -O -o /tmp/colour_bbox testapp/test_support/measure/colour_bbox.swift
/tmp/colour_bbox --sample capture.png               # 先看螢幕上實際是什麼顏色
/tmp/colour_bbox 8 232 248 capture1.png capture2.png  # 再量那個顏色的外框
/tmp/colour_bbox 102 230 255 --from-row 110 capture.png  # 第 110 列以上不算(排除同色的色塊)
```

這台 Mac 的 `python3` 沒有 PIL,所以用 CoreGraphics 寫成。每張圖印出該顏色像素的外框、寬高比、像素數,
以及「drawable」:超過一半為近黑像素的列與欄所圍成的區域(mesh view 的預設背景)。容差預設 75,
可用 `--tolerance N` 調整;取樣後縮小它:P95 在 AppKit 的擷圖以 75 量到 602x761(標題列的像素也算進去了),以 40 量到 602x602。
「drawable」只認超過一半為深色的列與欄：深色區不到截圖寬度(或高度)的一半時抓不到——P95 成長模式窄的那一半量成 720x27。

**先取樣。** 螢幕上的顏色不等於場景給的顏色:P95 的圓是 `(0.4, 0.9, 1)`,即 102 230 255,而在 macOS 上
GtkBackend 的擷圖約為 8 232 248,以 102 為中心根本抓不到。

2026-10-14 為 todo.md P2 而寫:P95 的 mesh view 填滿視窗,以 `drag_at.swift` 拖曳視窗角落改變大小 6 次，
正對鏡頭的圓在 5 種尺寸下寬高比都是 1.000,直徑與 drawable 高度的比例 6 次都在 0.715–0.717。唯一的例外
(512x800,0.928)是圓比 drawable 寬、左右被切掉，高度比例同樣是 0.715——不是變形。

Written for todo.md P2 because python3 here has no PIL. It prints the box of one
colour and the near-black area around it. Sample the capture first: the colour on
screen is not the scene's. With P95 resized six times by `drag_at.swift`, the
circle's box was square at five sizes and its height kept the same share of the
drawable's at all six; the one exception was clipped at the sides, not stretched.

## `drag_at.swift` — 在螢幕座標上做一次真正的滑鼠拖曳

```sh
swiftc -O -o /tmp/drag_at testapp/test_support/measure/drag_at.swift
/tmp/drag_at 600 500 900 700      # 起點 x y、終點 x y,螢幕座標(點)
```

以 `CGEvent.post(tap: .cghidEventTap)` 送出按下、8 步拖曳、放開。需要 Accessibility 授權。

**改視窗大小用它，不要用 System Events。** 2026-10-14 在 macOS 上的 GtkBackend:以 System Events 設定
`size of window 1`,視窗回報新尺寸，但 GL area 沒有重繪，截圖裡的內容停在舊尺寸;拖曳視窗右下角則每次都
重繪,P95 也記下了新的 drawable 尺寸。另外，視窗不能超出螢幕：靠近螢幕底部的視窗往下拉不會變高，先把它移到上方。
由程式改變的尺寸則會重繪:P95 的成長模式(`SCUI_P95_GROW=1`,內容寬度每 3 秒在 360 與 720 間切換，視窗為 `.contentSize`)
8 張擷圖中 drawable 在 720 與 1440 像素寬之間切換，圓皆為 430x430、置中(2026-10-14)。所以不重繪的只有 System Events 這條路。

Resize a window with this, not with System Events: on GtkBackend on macOS a size
set through System Events was reported but the GL area did not redraw, while a
drag of the corner redrew every time. Move the window up first; it cannot grow
past the bottom of the screen.

## `frames_during.zsh` — 在測試執行「期間」由外部連續擷圖

```sh
zsh testapp/test_support/measure/frames_during.zsh OUTDIR 30 "replaying P88" LOG <模擬器 UDID 或 mac> -- \
    zsh testapp/test_ios.zsh P88 --no-build --device "iPhone 17" --actionfile hold.actions
```

先在背景啟動 `--` 之後的指令(輸出寫到 LOG),等 LOG 出現 WAIT_FOR 這段字之後，連拍 COUNT 張:來源是模擬器 UDID 時用
`simctl io screenshot`,是 `mac` 時用 `screencapture` 拍整個螢幕(每 0.4 秒一張)。再用 `colour_bbox.swift` 量每一張。

測試執行器只在最後擷圖，所以只在「手指按著」時才存在的狀態從來拍不到。2026-10-15 為 P88 的長按 hover 而寫:
iPhone 17 模擬器上 XCUITest 按住 3 秒，30 張中第 10–18 張面板是橘色(1080x720 像素，即整個面板),前後都是藍色;
再跑一次同樣是 9 張。macOS 上的 GtkBackend,30 張螢幕畫面中第 21–28 張是橘色。整個螢幕的畫面會拍到桌面上其他視窗，
只放在暫存區，不要放進 repo 或發布。

A test runner captures only at the end, so a state that lasts only while a
finger is held never reached a capture. This starts the command in the
background, waits for a marker in its log, and takes COUNT frames from the
simulator (simctl) or the whole Mac screen. On the iPhone 17 simulator, 9 of 30
frames during a 3 s press showed the panel orange, twice. Whole-screen frames
show the rest of the desktop: keep them in the scratchpad.

## `long_press_drag.swift` — 一次真正的長按拖曳(P102 的 longPressTextSelection)

```sh
swiftc -O -o /tmp/lpdrag testapp/test_support/measure/long_press_drag.swift
/tmp/lpdrag P102 60 163 200 163 0.8     # 視窗 owner、起點 x y、終點 x y(視窗內容座標，點)、按住秒數
```

以 HID event tap 按下左鍵、靜止按住(預設 0.8 秒，超過 0.5 秒的長按延遲)、分 12 步拖曳後放開。座標是視窗**內容**
的點(左上為原點，標題列預設 28 點),視窗以 owner 名稱在 CGWindowList 中找，取一般層級中最大的那個——AppKit 會在
取得焦點的文字視圖旁另開一個約 53 x 48 的小視窗，第一個符合的曾經就是它。傳 `0.1` 當按住秒數就是對照組：一次普通拖曳。

2026-10-17,P102 在 AppKit 上:FIELD 從 x 60 拖到 200,`began anchor 5 extent 5`、`ended 5..<27`;EDITOR 從第三行
往左上拖，`ended anchor 94 extent 6 backward`——與 `actions/mac/P102-long-press-drag.actions`(行程內 NSApp.postEvent)
量到的完全相同。**它移動的是真正的指標，會點到最上層的任何視窗**:同一天另一個視窗(系統權限對話框、別人的當機報告)
蓋在 P102 上時，拖曳落在那裡。共用的桌面上請改用動作檔。

Real HID events: press, hold still (0.8 s by default), drag in 12 steps,
release, in window-content points of the largest normal-layer window owned by
the given name. On 2026-10-17 it gave the same P102 numbers on AppKit as the
in-process action file. It moves the real pointer, so it presses whatever
window is on top -- on a shared desktop, use the action file instead.

Android has no tool file: the same press is a few `adb shell input motionevent`
lines run on the device in one `sh` (pushed to /data/local/tmp), so the 0.9 s
hold is not stretched by adb round trips. P102 on the 2560x1600 tablet
emulator, device pixels: `DOWN 160 356`, `sleep 0.9`, `MOVE 250 356`,
`MOVE 380 356`, `MOVE 490 356`, `UP 490 356` gave FIELD `7..<28`; from
`DOWN 300 560` up to `UP 100 472`, EDITOR `anchor 89 extent 3 backward`.
Android 沒有工具檔：同一個按壓是幾行 `adb shell input motionevent`,寫成一個 sh 推到 /data/local/tmp 在裝置上一次
執行，0.9 秒的按住才不會被 adb 往返拉長。座標與結果見上方英文。


## `window_shots.swift` — 一支 app 的每一個畫面上視窗各拍一張(包括 sheet)

```sh
swiftc -O -o /tmp/window_shots testapp/test_support/measure/window_shots.swift
/tmp/window_shots debugTarget /tmp/p103     # 擁有者名稱或 pid;每個視窗印一行並存成 /tmp/p103-<id>.png
```

`screencapture -l <視窗編號>` 拍的是視窗本身，不是螢幕上看到的樣子：被別的 app 蓋住也拍得到。測試執行器的最後
擷圖按標題找視窗，所以 AppKit 的 sheet(另一個沒有標題的視窗)從來不在圖裡;整個螢幕的擷圖則會拍到前面別人的視窗
(2026-10-17 是另一個 session 的 Android 模擬器)。在 showtime 期間執行一次，P103 長按叫出的選擇器就在
`<id>.png` 裡:🏪 排第一、淺紫色。

`screencapture -l` captures a window as it is, covered or not. The runner's
final capture finds the window by title, so an AppKit sheet -- a second,
untitled window -- never reached it, and a whole-screen capture showed another
session's emulator in front (2026-10-17). Run once during showtime; P103's
long-press picker sheet is one of the files.


## `real_click.swift` — 一次真正的點擊，只在那一點屬於指定的 app 時

```sh
swiftc -O -o /tmp/real_click testapp/test_support/measure/real_click.swift
/tmp/real_click 884 365 debugTarget     # 螢幕座標(點);那一點最上層的視窗不屬於 debugTarget 就拒絕
```

經 HID event tap 送出的移動、按下、放開，與手的點擊走同一條路。先查 `CGWindowListCopyWindowInfo`:那一點最上層的
一般視窗若不屬於指定的擁有者就拒絕，不會點到別人的視窗。為 P103 而寫(2026-10-17):AppKitSynthesiser 以
`NSApp.postEvent` 送進 sheet 視窗的點擊，到不了 sheet 裡的手勢辨識器(sheet 的 Button 則可以),所以「點選擇器裡的
一格沒反應」可能是工具、也可能是元件。這支在同一格上點一次:`ROW 便利商店 emoji ⛽`、sheet 關閉——元件沒問題，
是合成器到不了。

One real HID click, refused unless the top window under the point belongs to
the named owner. Written for P103 (2026-10-17): clicks posted into a sheet by
AppKitSynthesiser did not reach a gesture recognizer there (the sheet's Button
did), which leaves "the cell did nothing" ambiguous between the tool and the
component. A real click on the same cell logged `ROW 便利商店 emoji ⛽` and
closed the sheet: the component works; the synthesiser does not reach it.

## `png_diff.swift` — 同一個視窗的兩張擷圖相差多少

```sh
swiftc -O -o /tmp/png_diff testapp/test_support/measure/png_diff.swift
/tmp/png_diff a.png b.png [容許值，預設 8]
```

印出最大通道差超過容許值的像素數、任一處的最大差值，以及相異像素的外框。寫來比較 GtkBackend 以 cairo 與以
GSK 節點畫出的形狀(2026-10-19):同一支 app 以 `SCUI_GTK_CAIRO_PATHS=1` 與未設定各跑一次、各用 `window_shots`
拍一張。P27、P40 完全相同;P43(漸層填色與漸層線條)最大差 7、P89(14 x 14 的圓配 2 點線寬)最大差 2,都在 8 以內，
是邊緣反鋸齒的差別。P95 有 57794 個像素超過，外框是 0,0 到 1039,55:那是標題列，一次截圖時視窗有焦點、一次沒有;
內容區相同。

It prints how many pixels differ by more than the tolerance in their largest
channel, the largest difference anywhere and the box around the differing
pixels. Written to compare GtkBackend's shapes drawn through cairo and as GSK
nodes (2026-10-19): run the app once with `SCUI_GTK_CAIRO_PATHS=1` and once
without, take each with `window_shots`, and compare. A difference confined to
the title bar is window focus, not drawing.
## `gtk_frame_trace.c` + `gtk_frame_trace.py` — macOS 上的 GTK 何時畫下一幀

```sh
cc -dynamiclib -O2 -o /tmp/gtk_frame_trace.dylib testapp/test_support/measure/gtk_frame_trace.c \
   -framework CoreVideo -L/opt/homebrew/lib -lgtk-4 -lgobject-2.0
GTK_FRAME_TRACE=/tmp/p96.trace DYLD_INSERT_LIBRARIES=/tmp/gtk_frame_trace.dylib \
   SCUI_DEBUG_EVENTS_DIR=/tmp/p96 testapp/output/P96-gtk4      # 約 13 秒後結束它
python3 -I testapp/test_support/measure/gtk_frame_trace.py /tmp/p96.trace 5.3 8.3
```

以 `DYLD_INSERT_LIBRARIES` 注入，不修改 app 也不修改 GTK:記錄 GDK 的每一次 `CVDisplayLinkStart`/`Stop`、每一次
CVDisplayLink callback、每一個 frame clock tick 與 after-paint,全部用同一個時鐘(mach_absolute_time 的微秒)。
`.py` 印出一段時間內的 tick 速率、以更新週期為單位的 tick 間隔、每幀工作量(tick 到 after-paint),以及每次
`CVDisplayLinkStart` 在下一個 callback 時槽之前多久發出、第一次 callback 落在哪一個時槽。

2026-10-19 用它找出 P96 在 GTK(macOS)上只有 33-58 fps 的原因:GDK 4.24 每畫完一幀就停掉 display link、下一次
繪製再啟動(P96 一次執行中 498 個 tick、498 次 start、497 次 stop),而在時槽前不到約 10 毫秒才啟動的 link 一律晚一個更新週期
(0-10 毫秒:0 次準時、147 次晚一週期;12-18 毫秒:95 次準時、2 次晚)。每幀工作只有 3-4 毫秒。GtkBackend 修正後
(`scui_macos_display_link_keep_running`)同一工具量到 0 次 start、每個間隔都是 1 個更新週期。

It is injected with `DYLD_INSERT_LIBRARIES` and changes neither the app nor
GTK. It logs every `CVDisplayLinkStart`/`Stop` GDK makes, every CVDisplayLink
callback, and every frame-clock tick and after-paint, all on one clock. The
`.py` prints the tick rate over a window, the tick intervals in refresh
intervals, the work per frame (tick to after-paint), and for each start how
long before the next callback slot it was made and which slot its first
callback came at. It found why P96 ticked 33-58 fps on GTK on macOS
(2026-10-19): GDK stops its display link after every frame, and a link started
less than about 10 ms before a slot calls back one refresh late; the frames
themselves took 3-4 ms.
