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

WinUI 版的外部探針,七項檢查與 AT-SPI 版相同,在 **control** 與 **content** 兩個 view 各跑一次,並在每份
傾印中寫明 view——raw view 會列出螢幕閱讀器走不到的元素。第一次使用時以 clang 建置 `uia_tree.c`。
2026-09-17:P69-WinUI 14/14、exit 0;反向對照為 Windows 上的 P69-gtk4.exe(無無障礙後端):exit 1,
label/hint/value/text_label 皆為 false——證明檢查不是空轉。
