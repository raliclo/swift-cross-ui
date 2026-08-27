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

At any other scale a file here is wrong, and wrong in a way that reads as the
app ignoring input. Between 2026-08-26 and 2026-08-27 this machine went from
125% to 100%, and every file in this folder had to be **re-measured from fresh
captures**. Multiplying the old numbers by 1.25 was deliberately not done: a
factor is easy to apply twice or to the wrong axis, and the result looks exactly
like a miss caused by anything else.

GtkBackend is where the scale bites, because GTK 4 on Windows does not scale
itself: its scale factor is an integer, 125% rounded to 1, and one GTK layout
unit is one physical pixel. That is why the 125% files carried `physical / 1.25`
and these carry `physical`.

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

在任何其他縮放比例下，本資料夾的檔案都是錯的，而且錯的樣子看起來就像 app 忽略了輸入。2026-08-26
至 2026-08-27 之間，本機從 125% 改為 100%，此處每個檔案都必須**重新從新的截圖量測**。刻意不採用
「把舊數字乘以 1.25」的做法：乘法係數很容易乘兩次、或乘錯軸，而結果看起來與任何其他原因造成的落空
一模一樣。

會被縮放咬到的是 GtkBackend，因為 Windows 上的 GTK 4 並不自行縮放：它的 scale factor 是整數，
125% 會取整為 1，一個 GTK 版面單位就等於一個實體像素。這正是 125% 時期的檔案寫 `實體像素 / 1.25`、
而現在的檔案寫 `實體像素` 的原因。

**因此，在相信這裡的任何內容之前，請先確認縮放比例。** 設定 → 系統 → 顯示器 → 縮放，或
`reg query "HKCU\Control Panel\Desktop\PerMonitorSettings" /s`——其中的 `DpiValue` 是相對於面板建議
比例的「級距偏移量」，不是百分比，因此 `0xffffffff` 代表「比建議值低一級」，而非 100%。
