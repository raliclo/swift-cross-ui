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
