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

So one press of a tab button empties the window. That is the whole of what is
established; what happens between the press and the blank page is not.

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

也就是說，按一次分頁按鈕就會清空整個視窗。以上是已確立的全部；從按下到空白之間發生了什麼，尚未確立。

**為何先前沒有人看到。** 在此之前，從未有任何一次點擊由動作檔抵達 Android app。
`test_android.zsh` 解析了 `--actionfile` 之後就丟掉、`AndroidBackend.entrypoint` 呼叫的是
`main(0, nil)` 因此任何旗標都無法送達、而 `Sources/InputEvent` 沒有 Android 的 synthesiser。這三者
都在 2026-09-02 修好，而這就是該機制找到的第一件事。

可能的原因，皆未查證：

- `setSize(ofWindow:)` 在本 backend 上只會警告、不做任何事。若分頁切換導致 view graph 去調整視窗
  大小，那行警告就是它的拒絕，而空白頁面則是版面在其後的結果。
- 該分頁列屬於 `#580`「狀態跨越旋轉」那一節，因此該次按壓會改變 `@State` 並強制整個根視圖重新算繪。
