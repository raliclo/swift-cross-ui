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

**Divide by the display scale.** A screenshot is in physical pixels and this
format is in logical points, and `Win32Synthesiser` multiplies back by
`GetDpiForWindow`'s scale on the way out. On a 125% display, coordinates taken
straight off a capture land 25% too far from the window's top-left — a miss that
grows with distance from the origin, so a target near the title bar looks nearly
right and one near the bottom of the window is nowhere near.

GtkBackend is where this bites, because GTK 4 on Windows does not scale itself:
its scale factor is an integer, 125% rounds to 1, and one GTK layout unit is one
physical pixel. So `physical / 1.25` is what a file has to carry, and a file
written here is correct for this machine's scale rather than for all of them.

## 每個檔案都必須做對的兩件事

兩者都是以一次失敗的執行、而非一則錯誤訊息換來的。

**使用 `frame` 原點，而非 `client`。** `testapp/screenshot.zsh -w` 擷取的視窗包含標題列，因此在該
影像上量到的像素就是 frame 座標。若改用 `client`，就必須減去一個此處無人知曉的標題列高度。

**要除以顯示縮放比例。** 截圖以實體像素為單位，本格式以邏輯點為單位，而 `Win32Synthesiser` 在送出
時會再乘回 `GetDpiForWindow` 的縮放比例。在 125% 的顯示器上，直接從截圖取得的座標會落在距離視窗
左上角遠 25% 之處——偏差隨著離原點的距離而放大，因此靠近標題列的目標看起來幾乎正確，而靠近視窗
底部的目標則差得離譜。

會被這件事咬到的是 GtkBackend，因為 Windows 上的 GTK 4 並不自行縮放：它的 scale factor 是整數，
125% 會取整為 1，一個 GTK 版面單位就等於一個實體像素。因此檔案裡要寫的是 `實體像素 / 1.25`，而
在此處寫成的檔案，只對本機的縮放比例正確，並非對所有機器都正確。
