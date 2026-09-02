# AndroidBackend — open defects

Measured on the Android emulator (`swift-cross-ui-api36`, API 36, 1080 x 2400,
density 2.625) unless a line says otherwise. Everything here came from a run.

## Open: the window goes blank after a tab button is pressed

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

What happens between the press and the blank page is still not established.

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

## 未解：按下分頁按鈕之後視窗變成空白

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

從按下到空白之間發生了什麼，仍然尚未確立。

**為何先前沒有人看到。** 在此之前，從未有任何一次點擊由動作檔抵達 Android app。
`test_android.zsh` 解析了 `--actionfile` 之後就丟掉、`AndroidBackend.entrypoint` 呼叫的是
`main(0, nil)` 因此任何旗標都無法送達、而 `Sources/InputEvent` 沒有 Android 的 synthesiser。這三者
都在 2026-09-02 修好，而這就是該機制找到的第一件事。

可能的原因，皆未查證：

- `setSize(ofWindow:)` 在本 backend 上只會警告、不做任何事。若分頁切換導致 view graph 去調整視窗
  大小，那行警告就是它的拒絕，而空白頁面則是版面在其後的結果。
- 該分頁列屬於 `#580`「狀態跨越旋轉」那一節，因此該次按壓會改變 `@State` 並強制整個根視圖重新算繪。
