# Re-aiming Android action files

testapp/reaim_android.zsh with test_support/reaim_android.py; done and
measured on swift-cross-ui-tablet36 2026-10-20 (queue.md item 12).

## Why

An action file holds positions. Every change to where a root starts, how wide
an app is laid out, or what sits above the content leaves them stale: the
2026-10-12 origin change moved about 60 apps by 6-290 pt. Re-aiming moves each
point to the **widget it was recorded on**, not by arithmetic on coordinates.

## How to apply

```
zsh testapp/reaim_android.zsh record FILE.actions ...   # on the build the files are right on
zsh testapp/reaim_android.zsh aim    FILE.actions ...   # on the new build
zsh testapp/reaim_android.zsh report [-v]
zsh testapp/reaim_android.zsh write  STEM ... | --all   # clean files only
zsh testapp/reaim_android.zsh check  FILE.actions ...   # replay as written, compare with aim
```

`record` writes an aim record per point (`<file>.aims`, read by
`AndroidSynthesiser.aim`; matching rule in AndroidBackendHelpers.kt
`aimDescribe`). Everything goes under `testapp/output/reaim/` (`REAIM_DIR`).

A file is **clean** only if it replayed to the end, every point matched inside
its recorded widget under the same widget class, and no parking row left the
screen. `write` refuses the rest, by name:

- `class-changed`: P35, P2, P45's toggle resolved to the label beside what is
  now a Switch, and the label toggles nothing;
- `near/unmatched`: the widget was not found;
- `park off screen`: a `move` that only parks before a scroll matched a widget
  past the edge (P48, P51);
- `labels empty`: the label capture was empty in both runs, so "same" says
  nothing (P57, P72).

`write` changes only the moved rows; a refused write exits 1. With no device
the script says so at once (exit 3) instead of hanging in `adb logcat`.

## Evidence

2026-10-20 on tablet36: same-build record/aim of P83, P103, P80, P102 gave 4
clean, 0 moved; P83 rebuilt with one extra 40 pt line moved 2 points 25-30 pt
and `check` replayed the written file to the same labels; one `write` for P83
and P103 changed exactly the five moved rows (results.csv2, android, P83).

## Limits

Re-aiming keeps points on their widgets for one AVD; it does not convert a
phone file into a tablet file. Files that press by `taplabel` need none of this.

---

# 重新瞄準 Android 動作檔

testapp/reaim_android.zsh 搭配 test_support/reaim_android.py;2026-10-20 在 swift-cross-ui-tablet36 上完成並量測
(queue.md 第 12 項)。

## 為什麼

動作檔存的是位置。根從哪裡開始、app 排多寬、內容上方有什麼，任何一項改變都會讓它們過期:2026-10-12 的原點變更讓約 60 支 app
移動了 6–290 pt。重新瞄準是把每個點移到**它當初記錄時所在的 widget**,而不是對座標做加減。

## 怎麼用

指令見上方英文段落:`record` 在檔案原本正確的那個建置上跑,`aim` 與 `check` 在新建置上跑,`report` 列出結果,`write`
只寫回乾淨的檔案。

`record` 為每個點寫下瞄準紀錄(`<file>.aims`,由 `AndroidSynthesiser.aim` 讀取；比對規則在 AndroidBackendHelpers.kt 的
`aimDescribe`)。所有輸出放在 `testapp/output/reaim/`(`REAIM_DIR` 可改)。

檔案只有在以下條件都成立時才算**乾淨**:重播跑到最後、每個點都落在記錄的 widget 內且 widget 類別相同、沒有停放列跑出螢幕。
其餘的 `write` 會依名稱拒絕:

- `class-changed`:P35、P2、P45 的開關解析到現在是 Switch 旁邊的標籤，而按標籤不會切換任何東西;
- `near/unmatched`:找不到該 widget;
- `park off screen`:捲動前只用來停放的 `move` 比對到超出邊緣的 widget(P48、P51);
- `labels empty`:兩次執行的標籤擷取都是空的，「相同」什麼也沒說明(P57、P72)。

`write` 只改移動過的列；被拒絕的寫入以 1 結束。沒有裝置時腳本立刻說明(以 3 結束),不會卡在 `adb logcat`。

## 證據

2026-10-20 於 tablet36:P83、P103、P80、P102 在同一建置上 record/aim,4 個乾淨、移動 0;P83 加上一行 40 pt 後重建，有 2 個點
移動 25–30 pt,`check` 照寫回的檔案重播得到相同標籤；一次 `write` 處理 P83 與 P103,恰好只改了那五列移動過的列
(results.csv2,android,P83)。

## 限制

重新瞄準讓點在同一台 AVD 上留在自己的 widget 上；它不會把手機的檔案轉成平板的檔案。用 `taplabel` 按的檔案完全不需要這些。
