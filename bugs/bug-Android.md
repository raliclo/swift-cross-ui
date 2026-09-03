# AndroidBackend — open defects

Measured on the Android emulator (`swift-cross-ui-api36`, API 36, 1080 x 2400,
density 2.625) unless a line says otherwise. Everything here came from a run.

Defects in the backend, not errors in what I said about it. A claim of mine that
turned out to be false goes in `mistakes/mistakes.csv2`, whose subject is me;
this file's subject is the backend. The two get confused because an expensive
mistake feels like it belongs somewhere permanent -- it does, and that somewhere
is the other file. See `flow.md` section 3h.

本檔收的是 backend 的缺陷，不是「我對它說錯的話」。我說過而後來被證明為假的主張，屬於
`mistakes/mistakes.csv2`——那一份的主詞是我，本檔的主詞是這個 backend。兩者容易混淆，是因為一個
代價高昂的錯誤會讓人覺得它該被永久記下來；它確實該，只是該記在另一份檔案裡。見 `flow.md` 第 3h 節。

## Fixed 2026-09-03: the window went blank after a widening state change

Measured 2026-09-02, on P12, by the first synthesised tap this backend has ever
received.

| moment | what the screen showed |
| --- | --- |
| 1 second after launch | the whole app: title, tab row, counter, the #632 margin block, four toggles, the switch |
| after the action file replayed | nothing — a blank page, status bar and home indicator only |

The process did not die. `pidof` still returned it, there was no
`AndroidRuntime` exception and no tombstone. Between the two screenshots the log
carries one line of its own:

    D swift : warning: Attempted to set size of Android window

The action file is `testapp/actions/android/P12-android-smoke.csv`. Its two
clicks are at (90, 260) and (128, 306) points, and at density 2.625 those are
(236, 682) and (336, 803) pixels. Against the launch screenshot the first lands
on the "Selected tab: Second counter: 0" label, which does nothing, and the
second lands squarely on **First** — the tab button spans roughly x 178..390,
y 750..845.

So one press of a tab button empties the window.

**It is this backend and not the harness, and that was measured rather than
assumed.** Three runs settle it:

| what pressed what | result |
| --- | --- |
| synthesised tap on empty space below the last control | nothing changed, 377531 non-white pixels in the content area |
| synthesised tap on "Increment counter" at the correctly derived (149, 359) points | "counter: 1", page intact, 378653 non-white pixels |
| **`adb shell input tap 283 798`** — a real system injection, nothing to do with the synthesiser — **on the First tab button** | **blank, 0 non-white pixels** |

The first two say the synthesiser delivers a touch faithfully. The third says a
touch that never went near this repository's code does the same thing, so the
blank page belongs to AndroidBackend.

A wrong turn worth recording, because it was taken for a plausible reason.
Synchronous delivery was blamed first -- the view graph's update runs nested
inside a block already on the main queue -- and `DispatchQueue.main.async` was
tried and made no difference. The actual cause of *that* confusion was a
mis-derived coordinate: 299 points at density 2.625 is 785 pixels, which is the
tab row, not the 942 where "Increment counter" sits. Both of the first two
synthesised taps had been pressing tab buttons.

**The rule, measured 2026-09-03.** It is not any state change. It is a state
change that makes the content need more width.

| control | what it changes | result |
| --- | --- | --- |
| Increment counter, taps 1 to 9 | `counter: 0` becomes `counter: 9` — same width | intact, 378953 non-white |
| Increment counter, tap 10 | `counter: 9` becomes `counter: 10` — one digit wider | **blank, 0 non-white** |
| Switch | a toggle's own state, no text | intact, 375289 |
| First tab | `Selected tab: Second` becomes `First`, and a longer status line | **blank** |
| Set both on | two toggles, and a much longer status line | **blank** |

The tenth tap is the whole finding. Nine presses of the same button in the same
place do nothing bad; the tenth does, and the only thing that changed is that
the number needs one more digit. So the trigger is the layout asking for a
larger size, which is consistent with the one line the app logs for itself:

    D swift : warning: Attempted to set size of Android window

`setSize(ofWindow:)` warns and does nothing on this backend. Something asks for
a new window size, is refused, and what the layout does afterwards is the blank
page.

**Consequence for action files.** A file that presses a control whose label or
status text keeps its width will run and can be verified. A file that widens
anything will end on a blank page, and that is the app being emptied rather than
the file being wrong. Until this is fixed, an Android file should either avoid
widening the content or claim the blanking on purpose.

### What it actually is, measured 2026-09-03

**The page is not empty. It is laid out 2440 points below the window.**

Probes in `CustomContainer.onLayout` and in `setPosition(ofChildAt:in:to:)`, on
the root VStack's container, across three states:

| state | position | size |
| --- | --- | --- |
| at rest | `78, 212` px | `918 x 1779` px |
| after a width-stable tap (Increment counter) | `78, 212` | `918 x 1779` |
| after a widening tap (First tab) | `2, **6405**` | `1073 x 1779` |

The x is right in both: it is the centring offset, `(1078 - 918) / 2 = 80` and
`(1078 - 1073) / 2 = 2`. The height does not change at all -- 1779 pixels either
way, in a container that stays 2207. Only y moves, from 212 to 6405.

`setPosition` is handed **`points = 1, 2440`** by the layout system, so the bad
number is not AndroidBackend's conversion -- `2440 x 2.625 = 6405`, and the
density is right.

2440 is the vertical centring result, `(outer - inner) / 2`, with `inner` = 678
points (1779 px) and therefore **`outer` = 5558 points**. And `size(ofWindow:)`
reports **411 x 841 both before and after** -- so the window did not change. What
grew is the stack's own computed height, from about 841 points to about 5558,
against a window that is still 841.

So the defect is in what the layout system computes for the root stack after a
widening state change, not in how Android draws it.

### Ruled out, each by measurement

| suspect | ruled out by |
| --- | --- |
| the action-file machinery | `adb shell input tap` blanks it identically |
| synchronous touch delivery | dispatching asynchronously changed nothing |
| `MATCH_PARENT` (-1) multiplied by density into `WRAP_CONTENT` (-2) | fixed; blanking survived |
| no root scroll host | added; blanking survived |
| `CustomContainer.onMeasure` passing the sentinel through as a dimension | fixed -- the root now measures 1080x2400 instead of -1x-1; blanking survived |
| the window size changing | `size(ofWindow:)` is 411x841 before and after |

The last two fixes are real and are kept. Neither was the cause.

### The cause, and the fix

`WindowReference.update` takes `windowSizeIsFinal`, defaulting to `false`. Three
call sites hand it the answer for the backend in use -- the resize handler, the
environment-change handler, and the public entry point all pass
`!backend.isWindowProgrammaticallyResizable(window)`. **A fourth did not.** The
`onResize` closure built into the window's environment called `update` without
it, so it took the default.

`false` permits the restart a few lines further down, which re-proposes
`clampedWindowSize`: the content's size when offered **zero width**, which for a
page of text is a very tall, very narrow column. On a backend that can resize,
the window then becomes that size and the arithmetic is honest. On one that
cannot, `setSize(ofWindow:)` does nothing, the window stays as it was, and the
content is centred against a window that does not exist:

    y = (proposedWindowSize.y - contentHeight) / 2
      = (5558 - 678) / 2
      = 2440 points = 6405 pixels, down a 2400-pixel screen

Adding the argument at that fourth call site fixes it. Measured after, on P12:
at rest 377531 non-white pixels, First tab 380457, Set both on 381325 -- the two
that had been 0 -- and ten presses of Increment counter reach `counter: 10` with
the page intact, which is the case that first pinned the defect down.

Nothing changes on a resizable backend: there `isWindowProgrammaticallyResizable`
is true, so the new argument is `false`, which is what the default already was.
Checked anyway -- P21's action file still reports `clicks: 1` on iOS and macOS
replays unchanged.

### Environment this was measured on

| | value | latest? |
| --- | --- | --- |
| device under test | Android 16 / API 36 | **yes** -- the emulator is API 36 |
| `compile_sdk` | 35 | no; android-36 is installed in the SDK |
| `target_sdk` | 35 | no; same |
| `min_sdk` | 31 | as specified for this project |

Worth knowing because API 36 applies compatibility behaviour to an app whose
target is below it, and windows and insets are among the areas Android 16
changed most -- `AndroidBackendHelpers.getSafeWindowHeight` already branches on
`SDK_INT <= 34`. It did not matter here: `size(ofWindow:)` reported a steady
411 x 841 throughout, and the bad number came from the shared layout system, not
from anything the platform reported. Raising `compile_sdk` and `target_sdk` to
36 is a separate change and has not been made.

### 成因與修正

`WindowReference.update` 接受一個 `windowSizeIsFinal` 參數，預設為 `false`。有三個呼叫點會依所用的
backend 傳入正確答案——resize handler、環境變更 handler，以及公開的進入點，三者都傳
`!backend.isWindowProgrammaticallyResizable(window)`。**第四個沒有傳。** 建構於視窗環境中的
`onResize` closure 呼叫 `update` 時省略了它，於是取到預設值。

`false` 使下方數行處的重啟得以執行，而它重新提議的是 `clampedWindowSize`：內容在被提議**寬度 0**
時的尺寸——對一個文字頁面而言，那是一根極高極窄的長條。在可調整大小的 backend 上，視窗接著會變成
那個尺寸，這個算式因而誠實；在不能調整的 backend 上，`setSize(ofWindow:)` 什麼都不做、視窗維持原狀，
而內容被對著一個並不存在的視窗置中：

    y = (proposedWindowSize.y - 內容高度) / 2
      = (5558 - 678) / 2
      = 2440 點 = 6405 像素，位於一個 2400 像素高的螢幕之下方

在第四個呼叫點補上該參數即可修正。修正後於 P12 上實測：靜止 377531 個非白像素、First tab 380457、
Set both on 381325——後兩者原本都是 0——而按 Increment counter 十次會顯示 `counter: 10` 且頁面完好，
那正是最初把這個缺陷釘下來的案例。

在可調整大小的 backend 上不會有任何改變：該處 `isWindowProgrammaticallyResizable` 為 true，因此新
傳入的值是 `false`，與原本的預設值相同。仍然實測確認過——P21 的動作檔在 iOS 上依然回報 `clicks: 1`，
macOS 的重放也毫無變化。

### 此次量測所在的環境

| | 值 | 是不是最新 |
| --- | --- | --- |
| 受測裝置 | Android 16 / API 36 | **是**——emulator 就是 API 36 |
| `compile_sdk` | 35 | 否，SDK 中已裝有 android-36 |
| `target_sdk` | 35 | 否，同上 |
| `min_sdk` | 31 | 本專案先前指定的值 |

值得記下，是因為 API 36 會對「target 低於它」的 app 套用相容性行為，而視窗與 insets 正是 Android 16
改動最多的區域之一——`AndroidBackendHelpers.getSafeWindowHeight` 本身就以 `SDK_INT <= 34` 分支。
不過此處並不影響結論：`size(ofWindow:)` 全程穩定回報 411 x 841，而那個壞掉的數字來自共用的版面系統，
不是來自平台回報的任何東西。把 `compile_sdk` 與 `target_sdk` 提升到 36 是另一件事，尚未進行。

### 實際上是什麼，2026-09-03 量得

**頁面不是空的。它被排到視窗下方 2440 點的地方。**

在 `CustomContainer.onLayout` 與 `setPosition(ofChildAt:in:to:)` 中放入探測，對根 VStack 的容器，
三個狀態：

| 狀態 | 位置 | 尺寸 |
| --- | --- | --- |
| 靜止 | `78, 212` px | `918 x 1779` px |
| 寬度不變的點擊後（Increment counter） | `78, 212` | `918 x 1779` |
| 會變寬的點擊後（First tab） | `2, **6405**` | `1073 x 1779` |

兩種情況下 x 都是對的：那是置中偏移，`(1078 - 918) / 2 = 80` 與 `(1078 - 1073) / 2 = 2`。高度
完全沒有改變——兩者都是 1779 像素，而容器維持 2207。只有 y 動了，從 212 變成 6405。

`setPosition` 收到的是版面系統交下來的 **`points = 1, 2440`**，因此那個壞掉的數字不是
AndroidBackend 的換算——`2440 x 2.625 = 6405`，density 是對的。

2440 正是垂直置中的結果 `(outer - inner) / 2`，其中 `inner` = 678 點（1779 px），因此
**`outer` = 5558 點**。而 `size(ofWindow:)` 在前後都回報 **411 x 841**——視窗根本沒有改變。變大的
是那個 stack 自己算出來的高度，從約 841 點變成約 5558 點，而視窗仍然是 841。

也就是說，缺陷在於「版面系統在一次會變寬的狀態變更之後，為根 stack 算出了什麼」，而不在於 Android
怎麼把它畫出來。

### 已排除的嫌疑，每一個都以量測排除

| 嫌疑 | 以什麼排除 |
| --- | --- |
| 動作檔機制 | `adb shell input tap` 造成完全相同的清空 |
| 同步投遞觸控 | 改為非同步毫無改變 |
| `MATCH_PARENT`(-1) 乘上 density 變成 `WRAP_CONTENT`(-2) | 已修；清空依舊 |
| 缺少根捲動宿主 | 已加；清空依舊 |
| `CustomContainer.onMeasure` 把哨兵值當尺寸傳出 | 已修——根容器現在量到 1080x2400 而非 -1x-1；清空依舊 |
| 視窗尺寸改變 | `size(ofWindow:)` 前後都是 411x841 |

後兩項修正是真的，並予以保留。兩者都不是成因。

**Why this had not been seen before.** No tap had ever reached an Android app
from an action file. `test_android.zsh` parsed `--actionfile` and dropped it,
`AndroidBackend.entrypoint` called `main(0, nil)` so no flag could arrive, and
`Sources/InputEvent` had no Android synthesiser. All three were fixed on
2026-09-02, and this was the first thing the machinery found.

Candidates, none of them checked:

- `setSize(ofWindow:)` warns and does nothing on this backend. If the tab change
  makes the view graph resize the window, the warning is that refusal, and the
  blank page is what the layout does afterwards.
- The tab row is the `#580` state-across-rotation section, so the press changes
  `@State` and forces a full re-render of the root.

## 已修 2026-09-03：一次讓內容變寬的狀態變更會使視窗變成空白

2026-09-02 量測，對象為 P12，由本 backend 有史以來第一次收到的合成觸控所觸發。

| 時間點 | 畫面所顯示的內容 |
| --- | --- |
| 啟動後 1 秒 | 整支 app：標題、分頁列、計數器、#632 的邊界方塊、四個 toggle、開關 |
| 動作檔重放之後 | 什麼都沒有——空白頁面，只剩狀態列與 home indicator |

行程並未死亡。`pidof` 仍然回傳它，沒有 `AndroidRuntime` 例外，也沒有 tombstone。兩張截圖之間，
log 中只有它自己的一行：

    D swift : warning: Attempted to set size of Android window

該動作檔為 `testapp/actions/android/P12-android-smoke.csv`。它的兩次點擊位於 (90, 260) 與
(128, 306) 點，在 density 2.625 下即為 (236, 682) 與 (336, 803) 像素。對照啟動時的截圖，第一次
落在「Selected tab: Second counter: 0」這行標籤上，不會有任何作用；第二次則正好落在 **First** 上
——該分頁按鈕大致橫跨 x 178..390、y 750..845。

也就是說，按一次分頁按鈕就會清空整個視窗。

**這屬於本 backend 而非測試工具，而這是量出來的，不是假設的。** 三次執行即可定案：

| 什麼按了什麼 | 結果 |
| --- | --- |
| 合成觸控點在最後一個控制項下方的空白處 | 什麼都沒變，內容區域有 377531 個非白像素 |
| 合成觸控點在正確推導出的 (149, 359) 點，即「Increment counter」 | 「counter: 1」，頁面完好，378653 個非白像素 |
| **`adb shell input tap 283 798`**——真實的系統注入，與 synthesiser 毫無關係——**點在 First 分頁按鈕上** | **空白，0 個非白像素** |

前兩者說明 synthesiser 忠實地投遞了觸控。第三者說明「一個從未接近本 repository 程式碼的觸控」做出了
同樣的事，因此那個空白頁面屬於 AndroidBackend。

一段值得記下的歧路，因為當初走上它的理由聽起來很合理。最初怪罪的是同步投遞——view graph 的更新是在
一個已於 main queue 上執行的區塊內嵌套執行——於是試了 `DispatchQueue.main.async`，毫無差別。造成
**那次**困惑的真正原因，是一個算錯的座標：299 點在 density 2.625 下是 785 像素，那是分頁列，而不是
「Increment counter」所在的 942。前兩次合成觸控其實都一直在按分頁按鈕。

**規則，2026-09-03 量得。** 它不是「任何狀態變更」，而是「會讓內容需要更多寬度的狀態變更」。

| 控制項 | 它改變了什麼 | 結果 |
| --- | --- | --- |
| Increment counter，第 1 至 9 次點擊 | `counter: 0` 變成 `counter: 9`——寬度相同 | 完好，378953 個非白像素 |
| Increment counter，第 10 次點擊 | `counter: 9` 變成 `counter: 10`——多了一位數 | **空白，0 個非白像素** |
| Switch | 某個 toggle 自身的狀態，沒有文字變化 | 完好，375289 |
| First tab | `Selected tab: Second` 變成 `First`，以及一行更長的狀態文字 | **空白** |
| Set both on | 兩個 toggle，以及一行長得多的狀態文字 | **空白** |

第十次點擊就是整個發現。同一個按鈕在同一個位置按九次都毫無問題；第十次出事了，而唯一改變的是
那個數字需要多一位數。因此觸發條件是「版面要求一個更大的尺寸」——這與該 app 為自己記錄的那唯一
一行是一致的：

    D swift : warning: Attempted to set size of Android window

`setSize(ofWindow:)` 在本 backend 上只會警告、不做任何事。有東西要求了一個新的視窗尺寸、被拒絕，
而版面在那之後所做的事，就是那個空白頁面。

**對動作檔的影響。** 一份「按下某個控制項，而其標籤或狀態文字寬度不變」的檔案可以執行也可以驗證。
一份會讓任何東西變寬的檔案，會結束在一個空白頁面上——而那是 app 被清空，不是該檔案寫錯。在這個問題
修好之前，Android 的動作檔要嘛避免讓內容變寬，要嘛刻意主張那個清空行為。

**為何先前沒有人看到。** 在此之前，從未有任何一次點擊由動作檔抵達 Android app。
`test_android.zsh` 解析了 `--actionfile` 之後就丟掉、`AndroidBackend.entrypoint` 呼叫的是
`main(0, nil)` 因此任何旗標都無法送達、而 `Sources/InputEvent` 沒有 Android 的 synthesiser。這三者
都在 2026-09-02 修好，而這就是該機制找到的第一件事。

可能的原因，皆未查證：

- `setSize(ofWindow:)` 在本 backend 上只會警告、不做任何事。若分頁切換導致 view graph 去調整視窗
  大小，那行警告就是它的拒絕，而空白頁面則是版面在其後的結果。
- 該分頁列屬於 `#580`「狀態跨越旋轉」那一節，因此該次按壓會改變 `@State` 並強制整個根視圖重新算繪。
