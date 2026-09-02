# win

Action files that have been run on Windows and seen to work. A file appears
here only after that; a copy of another platform's file would be a claim nobody
checked.

To see what is here, list the folder — a hard-coded list in this file would be
wrong the first time somebody added one without reading this far.

```zsh
ls testapp/actions/win/*.csv
```

What each of them found, and what happened on the apps that have no file, is in
`testapp/P0-P26-windows-findings.md`.

已在 Windows 上實際執行並確認可運作的動作檔。檔案唯有通過驗證之後才會出現在此；從其他平台複製
過來的檔案，只會是一項無人查證過的主張。

要知道這裡有什麼，請直接列出資料夾——若在本檔中寫死清單，只要有人加了檔案卻沒讀到這一行，該清單
第一次就會是錯的。

各檔案的發現，以及那些沒有動作檔的 app 上發生了什麼，記錄於 `testapp/P0-P26-windows-findings.md`。

## A file here is for one backend, not for Windows

Windows runs two backends, and a Pn built for each puts its controls in
different places. `P24-push-one-level.csv` and `P24-push-one-level-winui.csv`
are the same app and the same first click at different coordinates, measured
2026-08-27. So a file without a backend suffix was written against GtkBackend
(`-gtk4`), which is what most of this folder was driven with; a `-winui` suffix
means the other one.

Reaching for the wrong one does not fail loudly. The click lands somewhere
inside the window and nothing happens, which reads as the app ignoring input —
the same appearance that made a coordinate mistake look like a defect in
`P24-push-one-level.csv`.

## 此處的檔案針對某一個 backend，而非針對 Windows

Windows 上有兩個 backend，同一支 Pn 分別建置後，控制項的位置並不相同。
`P24-push-one-level.csv` 與 `P24-push-one-level-winui.csv` 是同一支 app、同一次的第一個點擊，座標
卻不同，量測於 2026-08-27。因此沒有 backend 後綴的檔案是針對 GtkBackend（`-gtk4`）而寫的——本資料夾
大多數檔案都是以它驅動的；帶 `-winui` 後綴者則是另一個。

取錯檔案不會大聲失敗。點擊會落在視窗內的某處而什麼也沒發生，看起來就像 app 忽略了輸入——正是那個
讓 `P24-push-one-level.csv` 把座標錯誤誤判成缺陷的外觀。

## Nothing inside a dialog can be driven from here yet

**Measured 2026-09-03 with `P31-tab-and-escape.csv`.** Keys work: `key tab`
moved focus out of a `TextField` and `key space` activated the button,
`p31-debug-events.log` recording `button clicked count=1`. Escape at an open
alert did nothing, and **the key never reached the dialog**:
`Win32Synthesiser.ownWindow()` returns this process's **largest-area** visible
top-level window, a `Gtk.MessageDialog` is a smaller separate top-level window
so it can never be selected, and `SetForegroundWindow` on the main window then
takes focus off the modal. Write-up and the proposed fix
(`GetWindow(hwnd, GW_ENABLEDPOPUP)`) are in `bugs/Gtk4-bugs.md` §6.

So an alert's buttons, Escape at a dialog, and a file dialog's contents are all
out of reach from a file in this folder — and a replay that touches one reports
no error at all, which is the dangerous part. `P5-stacked-alerts.csv` already
avoided this without naming it.

**`testapp/actions/mac/README.md` recommends Escape** for exactly this job,
because on macOS it "reaches a key window without a coordinate". That is true
there and **false here**. Do not port an Escape row from `mac/` to `win/`.

## Where a Pn writes its debug log — the current directory, not `testapp/output/`

Every `testapp/P*.swift` that writes a debug log builds its path from
`FileManager.default.currentDirectoryPath`; 35 of the 47 do, and the other 12
write no log. `splitview-debug.log` is the same
(`Sources/SwiftCrossUI/Views/SplitView.swift:215`). Re-derive with
`grep -c currentDirectoryPath testapp/P*.swift`.

`testapp/run.zsh` launches the executable by absolute path and never `cd`s, so
driving a file from the repo root leaves `p31-debug-events.log` **at the repo
root**. Docs that name `testapp/output/pNN-debug-events.log` are describing a
flow that `cd`s into `testapp/output` first — same convention, different
starting directory. Looking in the wrong one produces an empty directory, which
reads as "the app logged nothing" rather than "you are standing in the wrong
place".

## 此處尚無法驅動對話框內的任何東西

**2026-09-03 以 `P31-tab-and-escape.csv` 實測。** 按鍵是可用的：`key tab` 把焦點移出 `TextField`，
`key space` 觸發了按鈕，`p31-debug-events.log` 記錄了 `button clicked count=1`。但在已開啟的 alert
上按 Escape 毫無作用，而且**該按鍵從未抵達對話框**：`Win32Synthesiser.ownWindow()` 回傳本行程中
**面積最大**的可見 top-level 視窗，而 `Gtk.MessageDialog` 是較小的獨立 top-level 視窗，因此永遠
選不到；合成器接著又對主視窗呼叫 `SetForegroundWindow`，把焦點從 modal 手上拿走。記述與建議的
修法（`GetWindow(hwnd, GW_ENABLEDPOPUP)`）見 `bugs/Gtk4-bugs.md` 第 6 節。

因此 alert 的按鈕、對話框上的 Escape、檔案對話框的內容，對本資料夾中的檔案而言全都構不到——而
碰到這些的重放**完全不會回報錯誤**，那才是危險之處。`P5-stacked-alerts.csv` 早已繞過此事，只是
不曾指出它。

**`testapp/actions/mac/README.md` 正是為了這件工作而推薦 Escape**，理由是它在 macOS 上「無需座標
即可抵達 key window」。那句話在該處為真，在此處為假。請勿把 `mac/` 的 Escape 列搬到 `win/`。

## Pn 的 debug log 寫在哪裡——當前目錄，不是 `testapp/output/`

每一支會寫 debug log 的 `testapp/P*.swift`，其路徑都以 `FileManager.default.currentDirectoryPath`
組成；47 支中有 35 支如此，其餘 12 支不寫 log。`splitview-debug.log` 亦同
（`Sources/SwiftCrossUI/Views/SplitView.swift:215`）。可用
`grep -c currentDirectoryPath testapp/P*.swift` 重新推導。

`testapp/run.zsh` 以絕對路徑啟動執行檔且從不 `cd`，因此從 repo 根目錄驅動某個檔案時，
`p31-debug-events.log` 會落在 **repo 根目錄**。凡是寫成 `testapp/output/pNN-debug-events.log` 的
文件，描述的是一個會先 `cd` 進 `testapp/output` 的流程——同一種慣例，只是起始目錄不同。找錯目錄
會看到一個空目錄，而那會被讀成「這支 app 什麼都沒記錄」，而不是「你站錯地方了」。

## Two things every file here has to get right

Both were paid for in a failed run rather than in an error message.

**`frame` origin, not `client`.** `testapp/screenshot.zsh -w` captures the
window including its title bar, so a pixel measured on that image is a frame
coordinate. Using `client` would mean subtracting a title bar height that
nothing here knows.

**Divide by the display scale — which is 1 today, so today you do not.** A
screenshot is in physical pixels and this format is in logical points, and
`Win32Synthesiser` multiplies back by `GetDpiForWindow`'s scale on the way out.
At 100% those are the same number, so every file here now carries the pixels
exactly as they were read off the capture. Verified 2026-08-27 on P0 before
anything else was measured: a click written at the raw capture coordinate
(238,184) pressed the button under it, and the app's counter moved.

That used to be a rule to follow. It was really a symptom, and as of 2026-08-27
it is fixed: `GtkBackend` now hands the synthesiser GTK's own scale factor
rather than letting it ask `GetDpiForWindow`, so a file here means the same
thing whatever the display is set to. The history below is kept because it is
the evidence, not because it is still a chore.

Between 2026-08-26 and 2026-08-27 this machine went from 125% to 100%, and every
file in this folder had to be **re-measured from fresh captures** — and all 13 y
coordinates changed by exactly 1.25, without one exception. That is the proof
that nothing had moved: GTK 4 on Windows does not scale itself, its scale factor
is an integer, 125% rounds to 1, and one GTK layout unit is one physical pixel
at both settings. The synthesiser multiplied by 1.25 anyway, and the files
absorbed it. Multiplying the old numbers by 1.25 was deliberately *not* how the
new ones were produced: a factor is easy to apply twice or to the wrong axis,
and the result looks exactly like a miss caused by anything else.

**What is verified, and what is not.** The no-change case is verified here:
P21's file drives its three enabled clicks and the counter reads 3, at 100%,
with GTK reporting scale 1.0. The *differing* case — where the toolkit's scale
and the platform's disagree — could not be reproduced on Windows at all. This
machine is at 100%, and `GDK_SCALE`, the obvious way to manufacture a
disagreement without touching the display setting, is **ignored by GTK 4 on
Windows**: measured 2026-08-27, `GDK_SCALE=2` produced a pixel-identical window,
and GTK went on reporting 1.0. So the differing case was verified on Linux,
where `GDK_SCALE` is honoured — under `GDK_SCALE=2` GTK reports 2.0, lays out
820x720 → 1640x1080, and the same one-line file lands 410,400 further into the
window than at scale 1, which is the definition of the format working.

The WinUI file is a separate matter and still carries the old risk: nothing has
ever been driven against WinUIBackend at a scale other than 100%, and it is left
on `GetDpiForWindow` on the reasoning that a DIP framework does scale
fractionally. Reasoning, not a measurement.

**So check the scale before trusting any of this.** Settings → System → Display
→ Scale, or `reg query "HKCU\Control Panel\Desktop\PerMonitorSettings" /s` —
`DpiValue` there is a step offset from the panel's recommended scale, not a
percentage, so `0xffffffff` is one step below recommended rather than 100%.

## 每個檔案都必須做對的兩件事

兩者都是以一次失敗的執行、而非一則錯誤訊息換來的。

**使用 `frame` 原點，而非 `client`。** `testapp/screenshot.zsh -w` 擷取的視窗包含標題列，因此在該
影像上量到的像素就是 frame 座標。若改用 `client`，就必須減去一個此處無人知曉的標題列高度。

**要除以顯示縮放比例——而今天的比例是 1，所以今天不必除。** 截圖以實體像素為單位，本格式以邏輯點
為單位，而 `Win32Synthesiser` 在送出時會再乘回 `GetDpiForWindow` 的縮放比例。在 100% 之下兩者是同一
個數字，因此本資料夾中每個檔案現在都直接照截圖上量到的像素寫入。於 2026-08-27 在量測任何其他東西
之前先以 P0 驗證：以截圖原始座標 (238,184) 寫下的點擊，按到了該座標下方的按鈕，app 的計數器也隨之
變動。

上面這件事過去是一條「必須遵守的規則」。它其實是一個症狀，而自 2026-08-27 起已經修好：`GtkBackend`
現在會把 GTK 自己的 scale factor 交給 synthesiser，而不再讓它去問 `GetDpiForWindow`，因此無論顯示縮放
設定為何，此處的檔案都代表同一件事。以下的歷史之所以保留，是因為它是證據，而不是因為它仍是一件待辦
的雜務。

2026-08-26 至 2026-08-27 之間，本機從 125% 改為 100%，此處每個檔案都必須**重新從新的截圖量測**——而
13 個 y 座標**無一例外**恰好變動 1.25 倍。這正是「什麼都沒有移動」的證明：Windows 上的 GTK 4 並不自行
縮放，它的 scale factor 是整數，125% 會取整為 1，兩種設定下一個 GTK 版面單位都等於一個實體像素。而
synthesiser 仍然照乘 1.25，誤差便由這些檔案吸收了。新的數字刻意**不是**用「把舊數字乘以 1.25」得到的：
乘法係數很容易乘兩次、或乘錯軸，而結果看起來與任何其他原因造成的落空一模一樣。

**哪些已驗證、哪些沒有。** 「不變」的情況已在此驗證：P21 的檔案在 100% 之下打完三次 enabled 點擊，
計數器讀到 3，而 GTK 回報的 scale 為 1.0。但「有落差」的情況——toolkit 的比例與平台的比例不一致——
在 Windows 上根本無法重現。本機為 100%，而 `GDK_SCALE`（在不動顯示設定的前提下製造落差最直接的辦法）
在 **Windows 的 GTK 4 上完全無效**：2026-08-27 實測，`GDK_SCALE=2` 產生的視窗與原本逐像素相同，GTK
也依然回報 1.0。因此「有落差」的情況是在 Linux 上驗證的——`GDK_SCALE` 在那裡確實生效：`GDK_SCALE=2`
時 GTK 回報 2.0，版面由 820x720 變為 1640x1080，而同一個只有一行的檔案，落點比 scale 1 時**恰好**多深
入視窗 410,400——這正是「此格式有在運作」的定義。

WinUI 的檔案是另一回事，且仍帶有舊的風險：從來沒有人在 100% 以外的縮放下驅動過 WinUIBackend，而它
之所以維持使用 `GetDpiForWindow`，依據的是「DIP 框架確實會以小數比例縮放」這個推論。是推論，不是量測。

**因此，在相信這裡的任何內容之前，請先確認縮放比例。** 設定 → 系統 → 顯示器 → 縮放，或
`reg query "HKCU\Control Panel\Desktop\PerMonitorSettings" /s`——其中的 `DpiValue` 是相對於面板建議
比例的「級距偏移量」，不是百分比，因此 `0xffffffff` 代表「比建議值低一級」，而非 100%。
