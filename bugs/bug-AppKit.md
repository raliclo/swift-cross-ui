# AppKitBackend — open defects

Measured on macOS unless a line says otherwise. Everything here came from a run.

Defects in the backend, not errors in what I said about it. A claim of mine that
turned out to be false goes in `mistakes/mistakes.csv2`, whose subject is me;
this file's subject is the backend. See `flow.md` section 3h.

本檔收的是 backend 的缺陷，不是「我對它說錯的話」。我說過而後來被證明為假的主張，屬於
`mistakes/mistakes.csv2`——那一份的主詞是我，本檔的主詞是這個 backend。見 `flow.md` 第 3h 節。

## Fixed 2026-09-04: a child larger than its frame did not spill on macOS

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

**The cause was neither of the two candidates first written here**, and both
were wrong in the same way: they assumed the clipping had to come from something
this code does. It came from something it stopped doing.

`NSView.clipsToBounds` defaulted to **false** when this backend was written --
`createClippedContainer`'s comment still says so, and says that setting it to
true is "the whole difference between the clipped container and the plain one".
On a modern macOS SDK it defaults to **true**. So every container the backend
made was a clipped container, and the two functions returned the same thing.

Settled by dumping the view tree of a running app: **199 of 199
`AppKitHitTestingContainer`s reported `clipsToBounds == true`**, and
`createContainer` never sets it. Zero reported false. That is not a value this
code chose.

`createContainer` now sets `clipsToBounds` and `masksToBounds` to false
explicitly, and both functions carry a note saying why the plain one has to
state a default it used to be able to assume. Re-measured: cell 1 is 176 x 100
points with 680 blue samples, cell 2 is 119 x 60 with none.

**What this was worth beyond P44.** Every `clipped()`-free container in every
macOS app built from this backend was clipping. P44 is the only app in the tree
whose subject is overflow, which is why nothing else caught it -- and it existed
for four hours before it did.

## 已修 2026-09-04：macOS 上，比 frame 大的子元件不會溢出

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

**成因不是此處最初所寫的那兩個候選**，而它們錯在同一個地方：兩者都假設那個裁切必然來自「這段
程式碼所做的某件事」。它其實來自「這段程式碼不再做的某件事」。

`NSView.clipsToBounds` 在這個 backend 撰寫時預設為 **false**——`createClippedContainer` 的註解
至今仍這麼寫，並說把它設為 true 就是「已裁切的容器與一般容器之間的全部差異」。而在現代的 macOS
SDK 上，它預設為 **true**。因此這個 backend 所建立的每一個容器都是「已裁切的容器」，兩個函式回傳
的是同一種東西。

以傾印執行中 app 的 view tree 定案：**199 個 `AppKitHitTestingContainer` 中有 199 個回報
`clipsToBounds == true`**，而 `createContainer` 從來沒有設定過它。回報 false 的有零個。那不是這段
程式碼所選擇的值。

`createContainer` 現在會明確地把 `clipsToBounds` 與 `masksToBounds` 設為 false，而兩個函式都寫下
了說明：為何「一般容器」現在必須明說一個它過去可以假設的預設值。重新量測：第 1 格為 176 x 100 點、
680 個藍色樣本，第 2 格為 119 x 60 點、無藍色。

**這件事在 P44 之外的價值。** 由這個 backend 建置出來的每一支 macOS app 中，每一個未使用
`clipped()` 的容器都在裁切。P44 是本樹中唯一以「溢出」為主題的 app，那正是其他東西都沒抓到它的
原因——而它從存在到抓到這件事，只隔了四個小時。
