# AppKitBackend — open defects

Measured on macOS unless a line says otherwise. Everything here came from a run.

Defects in the backend, not errors in what I said about it. A claim of mine that
turned out to be false goes in `mistakes/mistakes.csv2`, whose subject is me;
this file's subject is the backend. See `flow.md` section 3h.

本檔收的是 backend 的缺陷，不是「我對它說錯的話」。我說過而後來被證明為假的主張，屬於
`mistakes/mistakes.csv2`——那一份的主詞是我，本檔的主詞是這個 backend。見 `flow.md` 第 3h 節。

## Open: a child larger than its frame does not spill on macOS

P44 draws a 200 x 100 point child inside a 120 x 60 frame, three times: once
never clipped, once always clipped, once following a button. On macOS all three
measure 240 x 120 pixels -- 120 x 60 points, the frame -- and no blue appears
anywhere in the window.

The child carries a 40 x 40 blue square at its top-left, and the frame centres
its child, so clipping keeps the middle and throws the marker away. Orange only
means the child was cut down; a blue corner means it was not.

**This is macOS and not the app.** The same source spills on both other
platforms:

| platform | cell 1 | blue in cell 1 | cell 2 |
|---|---|---:|---|
| iOS, scale 3 | 605 x 303 px = 202 x 101 pt | 3721 samples | 361 x 182 px = 120 x 61 pt, none |
| Android, density 2.625 | 461 x 262 px = 176 x 100 pt | 1113 samples | 315 x 157 px = 120 x 60 pt, none |
| macOS, scale 2 | 240 x 120 px = 120 x 60 pt | **0** | 240 x 120 px, none |

Android's cell 1 reads 176 points wide rather than 200 because the phone window
is 411 points and the cell is clipped by the screen edge, not by anything the
app did.

**Two explanations remain and P44 cannot separate them.** Either AppKitBackend
clips a container it was never asked to clip -- `createClippedContainer` is the
only place that sets `clipsToBounds`, and it is correct, so it would be
somewhere else -- or the layout gave the child the frame's size and the marker's
row was compressed until the marker had no width. Both produce a 120 x 60 orange
rectangle with no blue. Separating them needs a marker that survives
compression, which P44 does not have yet.

**Not diagnosed further, and not guessed at.** The measurement is recorded in
`testapp/actions/mac/P44-clip-the-third-cell.csv` alongside the iOS and Android
numbers that make it a macOS result rather than an app result.

## 未修：macOS 上，比 frame 大的子元件不會溢出

P44 在一個 120 x 60 的 frame 中畫一個 200 x 100 點的子元件，共三次：一次永不裁切、一次永遠裁切、
一次跟隨按鈕。在 macOS 上三格全部量得 240 x 120 像素——即 120 x 60 點，也就是 frame——且整個視窗中
沒有出現任何藍色。

該子元件的左上角帶有一個 40 x 40 的藍色方塊，而 frame 會把子元件置中，因此裁切會保留中間、丟掉
那個標記。只有橘色代表子元件被切小了；有藍色角落則代表沒有。

**這是 macOS 的問題，不是這支 app 的問題。** 同一份原始碼在另外兩個平台上都會溢出：

| 平台 | 第 1 格 | 第 1 格的藍色 | 第 2 格 |
|---|---|---:|---|
| iOS，比例 3 | 605 x 303 px = 202 x 101 pt | 3721 個樣本 | 361 x 182 px = 120 x 61 pt，無 |
| Android，density 2.625 | 461 x 262 px = 176 x 100 pt | 1113 個樣本 | 315 x 157 px = 120 x 60 pt，無 |
| macOS，比例 2 | 240 x 120 px = 120 x 60 pt | **0** | 240 x 120 px，無 |

Android 第 1 格讀到 176 點寬而非 200，是因為手機視窗只有 411 點、該格被螢幕邊緣裁掉，而不是這支
app 做了什麼。

**仍有兩種解釋，而 P44 分不開它們。** 可能是 AppKitBackend 裁切了一個它從未被要求裁切的容器
——`createClippedContainer` 是唯一設定 `clipsToBounds` 的地方，而它是正確的，因此問題會在別處
——也可能是版面把子元件給成 frame 的尺寸、而標記所在的那一列被壓縮到標記沒有寬度。兩者都會產生
一個沒有藍色的 120 x 60 橘色矩形。要分開它們，需要一個能在壓縮下存活的標記，而 P44 目前沒有。

**未進一步診斷，也不作猜測。** 該量測記錄於
`testapp/actions/mac/P44-clip-the-third-cell.csv`，並與 iOS 及 Android 的數字並列——正是那些數字
使它成為一項 macOS 的結果，而非一項 app 的結果。
