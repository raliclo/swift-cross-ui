# testapp FAQ

Answers to things that have actually been asked, kept here because each one cost
time to work out and would otherwise be worked out again.

此處收錄實際被問過的問題。每一則都曾耗費時間才弄清楚，若不記錄下來便會被重新推導一次。

## How does xdotool turn a coordinate into a click?

There are two mechanisms in this repo and they are not the same. Knowing which
one you are using decides whether a number read off a screenshot is correct.

本 repo 中存在兩套機制，而兩者並不相同。你正在使用哪一套，決定了「從截圖上量到的數字」是否正確。

### `drive_xdotool.zsh` — xdotool does the translation

```zsh
xdotool mousemove --window "$wid" X Y
```

`--window` makes xdotool ask the X server where that window is and convert for
you. The script never does coordinate arithmetic.

This is why the driver started working: an earlier version computed absolute
screen positions from `getwindowgeometry` and clicked on nothing.

**`getwindowgeometry` does not report a screen position.** Under a reparenting
window manager it double-counts the frame offset. Measured on one P19 window:

| source | X | Y |
|---|---|---|
| `xdotool getwindowgeometry --shell` | 1021 | 348 |
| `xwininfo` Absolute upper-left | 983 | 289 |
| `xwininfo` Relative upper-left (offset inside the frame) | 38 | 59 |

`983 + 38 = 1021`. The number xdotool prints is the true position plus the frame
offset that position already includes, so it is neither the client origin nor
the frame origin, and a click computed from it misses by exactly the decoration.

`--window` 會讓 xdotool 向 X server 詢問該視窗的位置並代為換算，腳本本身不做任何座標運算。

這正是該驅動器後來能運作的原因：早先的版本依 `getwindowgeometry` 自行計算螢幕絕對座標，結果
什麼都點不到。

**`getwindowgeometry` 回報的不是螢幕位置。** 在 reparenting 視窗管理員之下，它把框架偏移重複
計算了一次。對某個 P19 視窗實測，結果如上表：`983 + 38 = 1021`。xdotool 印出的數字，是「真正的
位置」再加上「該位置已經包含的框架偏移」，因此它既不是 client origin 也不是 frame origin，由它
算出的點擊會恰好偏離裝飾的大小。

### Why a coordinate read off a screenshot works directly

Because the capture is of the window, not of the desktop:

```zsh
xwd -id "$wid" | xwdtopnm | pnmtopng
```

The image's `0,0` **is** the window's `0,0`, so a pixel measured on it can be
typed straight into `--click X,Y` with no conversion.

This is load-bearing and implicit. Capture the desktop instead and every number
you measure is wrong by wherever the window happened to be.

因為擷取的是視窗而非桌面（如上）。影像的 `0,0` **就是**視窗的 `0,0`，因此在圖上量到的像素可以
直接填入 `--click X,Y`，無需任何換算。

這一點承載了整套流程，而且是隱含的。若改為擷取桌面，你量到的每一個數字都會偏掉——偏差量即為
該視窗當時所在的位置。

### `-actionfile` — the app converts, because it has two origins to serve

The `InputEvent` module cannot use `--window`, because an action file can name
either the client area or the window frame as its origin and `--window` offers
only one of them. It finds its own window and converts:

```
xdotool search --onlyvisible --pid <our pid>    ->  pick the largest by area
xdotool windowactivate --sync <id>
xdotool mousemove --window <id> 0 0             ->  client origin, read back
xdotool getmouselocation --shell                    from getmouselocation
xprop -id <id> _NET_FRAME_EXTENTS               ->  left, right, top, bottom
frame origin = client origin - (left, top)
screen position = (origin + the file's coordinate) * scale
```

The client origin is obtained by moving the pointer to the window's own `0,0`
and reading where it landed, rather than by asking for the geometry. That is
definitional rather than derived: it measures the exact transform `--window`
applies, so the arithmetic cannot disagree with the mechanism it feeds — which
is precisely how `getwindowgeometry` went wrong above.

By pid, not `getactivewindow`: XTEST posts to whatever the X server has focused,
and a window presented at startup is not reliably focused a second later.
Largest by area because a GTK app owns several X windows and the first match can
be a 1×1 helper.

`InputEvent` 模組無法使用 `--window`，因為動作檔可以指定「客戶區」或「視窗框架」作為原點，而
`--window` 只提供其中一種。它會自行找出自己的視窗並換算（如上）。

client origin 的取得方式是「把指標移到該視窗自身的 `0,0`，再讀回落點」，而非查詢幾何。這是定義性
而非推導性的：它量測的正是 `--window` 所套用的那個轉換，因此運算不可能與其所服務的機制相牴觸
——而上文中 `getwindowgeometry` 出錯的原因正在於此。

依 pid 而非 `getactivewindow`：XTEST 會投遞至 X server 當前聚焦的視窗，而啟動時 present 過的視窗
並不保證一秒後仍具焦點。取面積最大者，是因為一個 GTK app 擁有數個 X 視窗，第一個匹配可能是 1×1
的輔助視窗。

### Are the client and frame origins the same on Linux?

Not necessarily, and assuming so was wrong. This page previously claimed they
coincide because GTK draws its own title bar. Measured under WSLg's window
manager:

```
_NET_FRAME_EXTENTS(CARDINAL) = 38, 38, 59, 38
_GTK_FRAME_EXTENTS: not found.
```

The window manager decorates server-side — a 38 px border and a 59 px title bar
— and there are no client-side decorations at all. The two origins differ by
`38,59` here, so `_NET_FRAME_EXTENTS` is read rather than assumed. A missing
property does mean a zero inset, which is the genuine client-side-decoration
case.

Windows needs none of this. `GetWindowRect` gives the frame and `ClientToScreen`
gives the client, separately.

不一定，而且假設它們相同是錯的。本頁先前宣稱兩者重合，理由是 GTK 自行繪製標題列。在 WSLg 的
視窗管理員下實測，結果如上：該視窗管理員採用 server-side 裝飾（38 px 邊框、59 px 標題列），
而且完全沒有 client-side decorations。此處兩種原點相差 `38,59`，因此改為讀取
`_NET_FRAME_EXTENTS` 而非假設。屬性不存在確實代表偏移為零——那才是真正的 client-side
decoration 情形。

Windows 完全不需要這些：`GetWindowRect` 給出框架，`ClientToScreen` 給出客戶區，兩者分別取得。

## Why must a replay run off the main thread?

Because on the main thread it starves the application it is driving.

A replay spends nearly all its wall time asleep — waiting for an `xdotool`
subprocess, waiting out a `sleep` row. On the main thread that sleep is the UI's
sleep too, so posted events queue up unprocessed.

Measured: `P19-open-and-select.csv` opens a menu, waits 800 ms, then presses an
item. Run from the main thread it completed without error and logged
`action file replayed`, and the screenshot still read `last action -> nothing
yet` — the application never got to process the first click and map the popover,
so the second click landed on the empty window behind where the popover should
have been. Moving the replay to a background queue produced
`last action -> button item` with no other change.

This is why `Synthesiser` is deliberately **not** `@MainActor`.

因為在主執行緒上，它會餓死自己正在驅動的那個應用程式。

重放的絕大部分實際時間都在睡眠——等待 `xdotool` 子行程、等待某個 `sleep` 列。在主執行緒上，那份
睡眠同時也是 UI 的睡眠，於是已投遞的事件只能排隊而無法被處理。

實測：`P19-open-and-select.csv` 會開啟選單、等待 800 ms、再按下項目。由主執行緒執行時，它毫無
錯誤地完成並記錄了 `action file replayed`，而截圖仍顯示 `last action -> nothing yet`——應用程式
根本來不及處理第一次點擊並將 popover map 出來，因此第二次點擊落在「popover 本應出現之處」後方的
空白視窗上。僅把重放移到背景 queue，其餘一律不動，結果即為 `last action -> button item`。

這正是 `Synthesiser` 刻意**不**標記 `@MainActor` 的原因。

## Can xdotool drive a Windows app if I install an X server?

No, and this was measured rather than reasoned.

`xdotool` is an X11 client speaking XTEST. A SwiftCrossUI app on Windows is a
Win32 HWND and is not an X client, and installing an X server does not make it
one. The gvsbuild GTK 4 for Windows has no x11 backend compiled in either:

```
$ GDK_BACKEND=x11 ./P18.exe
Gdk-WARNING: No such backend: x11
Gtk-WARNING: Failed to open display
```

Windows input synthesis goes through `SendInput`, which is a Win32 function in
`user32.dll` -- not a package to obtain. That is what `Win32Synthesiser` uses.

不行，而這是實測而非推論得出的結論。

`xdotool` 是使用 XTEST 的 X11 client。Windows 上的 SwiftCrossUI app 是 Win32 HWND，並非 X client；
安裝 X server 也不會使它變成 X client。gvsbuild 的 Windows 版 GTK 4 同樣未編入 x11 backend（如上）。

Windows 端的輸入合成透過 `SendInput`——那是 `user32.dll` 中的 Win32 函式，並非需要取得的套件。
`Win32Synthesiser` 使用的正是它。

## Why does `swift test` not run?

It does not run on either platform here, for four separate pre-existing reasons,
each of which surfaces only after the previous one is fixed:

| platform | stops at |
|---|---|
| Linux | `WinUIInterop` included `Windows.h` unconditionally — now guarded |
| Linux | `swift-winui`'s `CWinAppSDK` needs `wtypesbase.h` |
| Windows | the layout benchmark imported `SwiftCrossUI` without `@_spi(Backends)` — now fixed |
| Windows | `UIKitBackend` needs `UIKit` |

The cause is structural: `swift test` compiles every target in the package, and
SwiftPM cannot make a target conditional -- only a dependency on one. Adding
platform conditions to `WinUIBackend`'s product dependencies was tried and does
not help.

Until that is sorted out, a module can be verified by compiling its sources
directly with `swiftc`, which is how `InputEvent`'s parser is checked.

`swift test` 在此處的兩個平台上皆無法執行，成因是四項各自獨立的既有問題，且每一項都要在前一項
修正之後才會浮現（如上表）。

根本原因是結構性的：`swift test` 會編譯 package 中的每一個 target，而 SwiftPM 無法讓 target 本身
帶條件——只能讓「對某個 target 的依賴」帶條件。曾嘗試為 `WinUIBackend` 的 product 依賴加上平台
條件，並無幫助。

在此問題解決之前，可以直接以 `swiftc` 編譯模組原始碼來驗證；`InputEvent` 的解析器即以此方式檢查。

## Why must apps be launched one at a time?

Because launching twelve at once produced a sweep in which every app looked
dead, and every one of them was fine. That was one of three false failures in a
single session, all caused by how runs were driven rather than by what was run.

The others: a script launched through `cmd /c start /b zsh` received a
Windows-form `PATH`, so prepending POSIX entries gave MSYS a mixture it could not
convert and the children could not resolve the GTK DLLs; and an `awk` filter on
`tasklist` CSV output missed every row because the first field carries a leading
quote.

See `verified-test-process.md` for the full list.

因為一次啟動十二支，曾產生一份「每支 app 看起來都死了」的結果，而實際上它們全都正常。那是同一個
工作階段中三次假失敗之一，三次的成因都在於「執行方式」，而非「被執行的對象」。

另外兩次：透過 `cmd /c start /b zsh` 啟動的腳本收到的是 Windows 格式的 `PATH`，因此在前方接上
POSIX 項目後，MSYS 得到一個無法轉換的混合格式，子行程也就無法解析 GTK 的 DLL；以及對 `tasklist`
的 CSV 輸出所做的 `awk` 過濾漏掉了每一列，因為第一個欄位帶有前導引號。

完整清單見 `verified-test-process.md`。

## Why is a debug trace in `body` dangerous?

`body` is a result-builder property. Adding a statement before an explicit
`return` changes how it is built.

Doing exactly that to P7 blanked its window: no list, no split view, no buttons,
not even its title text — just a single small box. It was reported as a severe
backend defect and three bisections went past the real cause before it was
traced to the trace. `init` is safe; `body` is not.

`body` 是 result-builder 屬性，在明確的 `return` 之前加入陳述式會改變它的建構方式。

對 P7 做了這件事之後，它的視窗變成一片空白：沒有清單、沒有 split view、沒有按鈕，連標題文字都
沒有——只剩一個小方塊。它一度被回報為嚴重的 backend 缺陷，而在追溯到「追蹤本身」之前，有三次
二分都走過了頭。`init` 是安全的；`body` 不是。

## How do I read an iOS Simulator app log?

The iOS runner is `test.zsh <Pn> --ios`, which delegates to `test_ios.zsh`. It installs the selected Pn into the
reusable `testapp/.bundledApp/appTemplate.app` bundle. Its executable and
bundle identifier are always `debugTarget`. The runner starts a Simulator
unified-log stream filtered to that process and writes it to:

```text
testapp/output/ios-P14-debugTarget.log
```

The Pn name changes with the target. To run a test and keep the app open for
ten seconds:

```sh
zsh testapp/test.zsh P14 --ios --showtime 10
```

To replay an iOS action file through XCUITest:

```sh
zsh testapp/test.zsh P14 --ios --actionfile testapp/actions/ios/P14-basic.csv
```

For a live view of the same Simulator log, use the fixed executable name:

```sh
xcrun simctl spawn swift-cross-ui log stream --style compact \
  --predicate 'process == "debugTarget"'
```

XCUITest action replay uses the standard Xcode UI-test runner generated from
`testapp/iosContainer/xcodeTestRunnerProject`. It does not use the Linux or
Windows input synthesiser. Run it with an explicit CSV path:

```sh
zsh testapp/test.zsh P14 --ios --actionfile testapp/actions/ios/P14-smoke.csv
```

The supported rows are `click`, `doubleclick`, `move`, `sleep`, and a
`mousedown`/`mouseup` drag pair. `keydown`, `keyup`, `key`, `scroll`, and
`frame` coordinates are rejected instead of being silently misinterpreted.

XCUITest action replay 使用由
`testapp/iosContainer/xcodeTestRunnerProject` 產生的標準 Xcode UI-test runner，
不使用 Linux 或 Windows 的 input synthesiser。請指定 CSV 路徑執行：

```sh
zsh testapp/test.zsh P14 --ios --actionfile testapp/actions/ios/P14-smoke.csv
```

目前支援的列為 `click`、`doubleclick`、`move`、`sleep`，以及
`mousedown`／`mouseup` 拖曳配對。`keydown`、`keyup`、`key`、`scroll` 與
`frame` 座標會直接拒絕，不會靜默地以錯誤語意執行。

如何讀取 iOS Simulator app 的 log？

iOS runner 是 `test.zsh <Pn> --ios`，實際工作委派給 `test_ios.zsh`。它會把指定的 Pn 安裝到可重複使用的
`testapp/.bundledApp/appTemplate.app` Bundle。其執行檔與 Bundle identifier
固定使用 `debugTarget`。runner 會啟動只篩選該 process 的 Simulator unified-log
串流，並寫入：

```text
testapp/output/ios-P14-debugTarget.log
```

檔名中的 Pn 會隨測試目標改變。執行測試並讓 app 保持開啟 10 秒：

```sh
zsh testapp/test.zsh P14 --ios --showtime 10
```

透過 XCUITest 重放 iOS action file：

```sh
zsh testapp/test.zsh P14 --ios --actionfile testapp/actions/ios/P14-basic.csv
```

若要即時查看同一份 Simulator log，請使用固定的執行檔名稱：

```sh
xcrun simctl spawn swift-cross-ui log stream --style compact \
  --predicate 'process == "debugTarget"'
```
