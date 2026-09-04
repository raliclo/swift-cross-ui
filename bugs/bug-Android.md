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

## Open: a replayed press on a `.wheel` date picker is lost about a third of the time

P41's action file presses one row of the month wheel. Counted 2026-09-04: **3 of
5** with the file as it stands. The claim itself is right -- when the press
lands, the wheel advances to Sep and the readout goes 2025-08-24 to 2025-09-24 --
and nothing else in the file is unreliable.

**Two hypotheses, both tested and both wrong.** They are written down because
each cost a build and neither is worth repeating.

- **Layout timing.** Dumps at 2, 4, 6 and 9 seconds after launch: the wheel's
  selected band is absent at 2 and present at y 954-1080 from 4 onwards. The
  file's settling sleep was raised from 1.8 to 3.5 seconds accordingly, which
  puts the press at about 4.5 seconds counting the replay's own 1 second. Going
  further, to 6, gave 4 of 5 -- inside the same spread. Waiting longer is not
  the fix.
- **Press duration.** A synthesised click posts ACTION_DOWN and ACTION_UP with
  no gap, and `dispatch` stamps both with `SystemClock.uptimeMillis()`, so they
  can share a millisecond -- a touch of zero length. `NumberPicker`, which is
  what a Holo spinner is, tells a tap from a fling by measuring the gesture, so
  this looked like the answer. Holding for 50ms gave **0 of 5**: strictly worse
  than no gap at all. Reverted.

**What is not yet ruled out**: the emulator dropping input under load, something
in `NumberPicker`'s own press-state handling, or the replay thread's hop to the
main thread reordering the two events. None of those has been measured.

The affected row is one press in one file. Every other Android action file
replays consistently.

## 未修：對 `.wheel` 日期選擇器的重放按壓，約有三分之一會遺失

P41 的動作檔會按下月份滾輪的其中一列。2026-09-04 計數：以檔案現狀為 **5 次中 3 次**。該主張本身是
正確的——當按壓落下時，滾輪會前進到 Sep，讀數由 2025-08-24 變為 2025-09-24——而該檔案中其餘部分
都沒有不穩定的情況。

**兩個假設，都測過，也都是錯的。** 之所以寫下來，是因為每一個都花了一次建置，而兩者都不值得重來。

- **版面時序。** 於啟動後 2、4、6、9 秒各取一次 dump：滾輪被選中的那一帶在 2 秒時不存在，自 4 秒起
  存在且穩定於 y 954-1080。該檔案的等待因此由 1.8 秒提高到 3.5 秒，加上重放本身的 1 秒，使按壓落在
  約 4.5 秒。再往上加到 6 秒得到 5 次中 4 次——落在同一個散布範圍內。等更久並不是解法。
- **按壓時長。** 一次合成的點擊會投遞 ACTION_DOWN 與 ACTION_UP 且中間沒有間隔，而 `dispatch` 以
  `SystemClock.uptimeMillis()` 為兩者蓋時戳，因此它們可能共用同一毫秒——一次長度為零的觸控。而
  `NumberPicker`（Holo 滾輪的本體）正是以量測手勢來區分點擊與快滑，所以這看起來像是答案。改為持續
  50 毫秒的結果是 **5 次中 0 次**：嚴格地比完全沒有間隔更差。已撤回。

**尚未排除的**：emulator 在負載下丟棄輸入、`NumberPicker` 自身按下狀態處理中的某些行為，或重放
執行緒跳往主執行緒時使那兩個事件次序顛倒。以上皆未經量測。

受影響的是一份檔案中的一次按壓。其餘每一份 Android 動作檔的重放都是穩定的。

## Fixed 2026-09-05: an app's `print` did not reach logcat, and it was buffering

Recorded on 2026-09-03 as a platform limitation -- "an Android app's `print` does
not reach logcat" -- and used to justify writing several action files against
uiautomator attributes and pixels instead of the diagnostics the apps already
had. It was four lines of buffering.

`AndroidBackend.entrypoint` pipes **both** stdout and stderr and `dup2`s both, so
nothing was missing. C stdio picks its buffering from what the descriptor is: a
terminal gets line buffering, anything else gets a full 4 KB buffer. After the
`dup2` stdout is a pipe, so `print` wrote into a buffer flushed when it filled,
when the process exited, or never -- and an app ended with `am force-stop`, which
is how every test here ends, never flushes. stderr is unbuffered by the C
standard, which is exactly why `InputEvent`'s `-actionfile:` lines always
appeared while the apps' own output never did.

That asymmetry was the whole clue and it was in front of me: two streams, same
plumbing, only one arriving.

`setvbuf(stdout, nil, _IOLBF, 0)` after the dup2. Verified: P44 now logs
`[P44] RENDER COMPLETE -- P44 ready for clipping checks` and
`[P44] third cell clipped: true`.

## 已修 2026-09-05：app 的 `print` 到不了 logcat，而成因是緩衝

2026-09-03 曾把它記為平台限制——「Android app 的 `print` 到不了 logcat」——並以此為由，讓好幾份動作
檔改用 uiautomator 屬性與像素判讀，而不是那些 app 本來就有的診斷輸出。它其實是四行緩衝設定。

`AndroidBackend.entrypoint` 對 stdout 與 stderr **兩者**都接了 pipe、也都做了 `dup2`，因此並沒有
少接什麼。C stdio 是依「該描述子是什麼」決定緩衝方式的：終端機得到行緩衝，其他一切得到完整的 4 KB
緩衝區。`dup2` 之後 stdout 是一條 pipe，於是 `print` 寫進一個「滿了才沖、行程結束才沖，或永遠不沖」
的緩衝區——而一個以 `am force-stop` 終結的 app（此處每次測試都是如此）永遠不會沖。stderr 依 C 標準
無緩衝，這正是為什麼 `InputEvent` 的 `-actionfile:` 各行一直都看得到，而 app 自身的輸出從來沒有。

那個不對稱就是全部的線索，而它一直擺在眼前：兩條串流、同一套管線，只有一條抵達。

修法是在 dup2 之後加上 `setvbuf(stdout, nil, _IOLBF, 0)`。已驗證：P44 現在會記錄
`[P44] RENDER COMPLETE -- P44 ready for clipping checks` 與
`[P44] third cell clipped: true`。

## Fixed 2026-09-04: `windowLevel(.floating)`, after four experiments

AndroidBackend now conforms to `BackendFeatures.WindowLevels` and reports
`[.automatic, .normal]`. It does not offer `.floating`, and this section is the
evidence for that rather than an assertion, because "the platform has no API for
this" is a claim this repository requires to be demonstrated.

Both attempts were on the API 36 emulator with SYSTEM_ALERT_WINDOW granted
through `adb shell appops set ... allow`, which the permission needs -- it is
granted by the user in Settings, not by a manifest line.

**1. `Window.setType(TYPE_APPLICATION_OVERLAY)` on the activity's own window.**
Compiles, runs, returns nothing, does nothing. Settings launched over P37
covered it completely and `dumpsys window` reported
`mCurrentFocus=...SettingsHomepageActivity`. An activity's window type is
assigned by the window manager when the activity is attached; it is not a
property the activity can change afterwards.

**2. Detaching the content view into a `WindowManager` overlay window.** This
does produce a real overlay, and the dump proves it: `dumpsys window windows`
listed `Sys2038:dev.swiftcrossui.testapp.p37/...` at #6 with Settings at #9 --
2038 is TYPE_APPLICATION_OVERLAY and #6 is above #9 -- with
`mAttrs={(0,0)(fillxfill) ty=APPLICATION_OVERLAY fmt=TRANSLUCENT`,
`mViewVisibility=0x0` and `appop=SYSTEM_ALERT_WINDOW`. And it draws nothing.
Re-assigning MATCH_PARENT layout params and calling `requestLayout()` and
`invalidate()` after `addView` changed nothing. The window is in front, visible,
full screen, and empty.

**3. The same through `applicationContext`'s WindowManager**, in case the
window was following the activity's token. Identical. So it follows the
*process* state, not the token.

**4. A foreground service owning the window.** This is the one. A foreground
service keeps the process out of the cached state, which is what the surface
needed. `OverlayService.kt` holds the view; `swift-bundler`'s manifest generator
gained a `<service>` element to declare it.

**"Draws nothing" was wrong, and so was the diagnosis built on it.** Experiment
2 was recorded here as producing a blank overlay. It did not: with the view
instrumented it laid out at 1080x2209, attached, and drew P37's text over
everything. The blank screenshots came from testing against **Settings**, whose
window carries `HIDE_NON_SYSTEM_OVERLAY_WINDOWS` -- read off `dumpsys window
windows` on 2026-09-04. That flag hides every non-system overlay while such a
screen is in front, for every app on the platform, and cannot be opted out of.
Three runs were read as failures because of the app I happened to test against.

Verified against an ordinary app instead: with P44 in front, P37's text draws
over P44's orange tiles and the overlay sits at window #7 above it.

**What it costs**, and both are Android's price rather than a choice made here:
SYSTEM_ALERT_WINDOW, which the user grants in Settings and which
`supportedWindowLevels` is computed from rather than assumed; and a foreground
service, which means an app that floats shows a notification.

## 已修 2026-09-04：`windowLevel(.floating)`,歷經四次實驗

AndroidBackend 現已實作 `BackendFeatures.WindowLevels`，並回報 `[.automatic, .normal]`。它不提供
`.floating`，而本節是那件事的證據，而非一項斷言——因為「這個平台沒有對應的 API」是本倉庫要求必須
被證明的主張。

兩次嘗試都是在 API 36 emulator 上、並以 `adb shell appops set ... allow` 授予 SYSTEM_ALERT_WINDOW
的情況下進行的；該權限需要這樣做，因為它是由使用者在「設定」中授予的，不是靠 manifest 的一行取得的。

**1. 在 activity 自己的視窗上呼叫 `Window.setType(TYPE_APPLICATION_OVERLAY)`。** 能編譯、能執行、
不回傳任何東西，也什麼都不做。啟動於 P37 之上的「設定」把它完全覆蓋，而 `dumpsys window` 回報
`mCurrentFocus=...SettingsHomepageActivity`。activity 的視窗型別是在 activity 被 attach 時由 window
manager 指派的；那不是 activity 事後可以更改的屬性。

**2. 把內容 view 分離、移入一個 `WindowManager` 的 overlay 視窗。** 這確實產生了一個真正的 overlay，
而 dump 可以證明：`dumpsys window windows` 把 `Sys2038:dev.swiftcrossui.testapp.p37/...` 列在 #6，
而「設定」在 #9——2038 即 TYPE_APPLICATION_OVERLAY，而 #6 位於 #9 之上——其
`mAttrs={(0,0)(fillxfill) ty=APPLICATION_OVERLAY fmt=TRANSLUCENT`、`mViewVisibility=0x0`、
appop 為 SYSTEM_ALERT_WINDOW。而它什麼都不畫。在 `addView` 之後重新指派 MATCH_PARENT 的 layout
params 並呼叫 `requestLayout()` 與 `invalidate()`，也沒有改變任何事。該視窗在最前面、可見、滿版，
而且是空的。

**3. 同樣的做法，但改用 `applicationContext` 的 WindowManager**，以防該視窗在跟隨 activity 的
token。結果完全相同。因此它跟隨的是**行程**狀態，不是 token。

**4. 由一個 foreground service 持有該視窗。** 這一個成了。foreground service 會讓行程不進入 cached
狀態，而那正是該 surface 所需要的。`OverlayService.kt` 持有那個 view；`swift-bundler` 的 manifest
產生器則新增了一個 `<service>` 元素來宣告它。

**「什麼都不畫」是錯的，而建立在它之上的診斷也是錯的。** 此處原本記載第 2 次實驗產生了一個空白的
overlay。它並沒有：為該 view 加上量測之後，它以 1080x2209 完成佈局、已 attach，並把 P37 的文字畫在
一切之上。那些空白的截圖來自以**「設定」**作為測試對象——而它的視窗帶有
`HIDE_NON_SYSTEM_OVERLAY_WINDOWS`，此事於 2026-09-04 自 `dumpsys window windows` 讀出。該旗標會在
這類畫面位於前景時，隱藏平台上每一支 app 的所有非系統 overlay，且無法選擇退出。三次執行之所以被
讀成失敗，原因只是我恰好拿來測試的那支 app。

改以一支普通 app 驗證：P44 在前景時，P37 的文字畫在 P44 的橘色磚之上，而該 overlay 位於其上的
視窗 #7。

**它的代價**，而兩者都是 Android 的定價、不是此處所做的選擇：SYSTEM_ALERT_WINDOW——由使用者在
「設定」中授予，而 `supportedWindowLevels` 是依它計算而非假定；以及一個 foreground service——
這意味著一支會浮動的 app 會顯示一則通知。

## Fixed 2026-09-04: three defects P7, P40 and P43 recorded as failures

Each of these had an action file that stated a claim and then recorded that the
claim was false. All three now hold, and the files keep both recordings.

**A List selection made from code was never drawn.** P7's five rows measured
pure white after "Select Cherry", while a tapped row on a neighbouring list
measured 237. The binding worked -- the label read "Selection: Cherry" -- and so
did `setItemChecked`. `AbsListView` calls `setActivated(true)` on a checked row
whose view is not `Checkable`, and these views are plain containers with no
drawable that answers `state_activated`, so the flag arrived and nothing painted
it. Each row now carries a foreground `StateListDrawable` in the ListView's own
selector colour, so a row selected from code and a row under a finger look the
same. Foreground rather than background, because a row's background belongs to
whatever `.background()` the app put there.

**Geometric effects were cut at the cell edge.** P40's offset tile was
translated to exactly the right place and then lost 106 pixels of width and 53
of height; the rotated and sheared tiles stopped at the right edge of their
pre-transform frames. Nothing was wrong with the transform. Android is the only
backend here whose parent clips a child by default: `ViewGroup.clipChildren` is
true, `UIView.clipsToBounds` is false, an `NSView` does not clip, and GTK draws
outside an allocation. `CustomContainer` and `GeometricEffectContainer` no
longer clip, which nothing depended on -- `BackendFeatures.Clipping` is not
implemented on Android at all, and `CornerRadiusContainer` clips with
`canvas.clipPath` inside its own draw.

**`Shape.fill(gradient)` was a flat colour.** AndroidBackend did not implement
the gradient overload of `renderPath`, so `BackendFeatures.Paths` supplied its
default, which flattens and warns. Two things made that worse than it sounds:
the flattened colour is the *first stop* rather than a midpoint, because
`ResolvedFillStyle.midpoint(of:)` picks the stop nearest 0.5 with `min(by:)` and
a two-stop gradient ties at 0.5, and the warning it logs never appears, because
an Android app's `print` does not reach logcat. The overload is implemented with
Android's own `LinearGradient` and `RadialGradient`. `RadialGradient` has no
start radius; that is expressed by remapping the stop positions rather than
dropped.

**Still open, found on the way:** AndroidBackend does not implement
`BackendFeatures.Clipping`, so `.clipped()` would take the `@CastBackend` path.
No test app in this tree exercises it on Android yet.

## 已修 2026-09-04：P7、P40 與 P43 記錄為失敗的三個缺陷

這三者各自都有一份動作檔，其中陳述了一項主張，然後記下該主張為假。三者現在都成立，而那些檔案同時
保留了兩次記錄。

**以程式做出的 List 選取從未被繪製。** 按下「Select Cherry」之後，P7 的五列量得純白，而鄰近清單中
一列被點擊時量得 237。繫結是正常的——標籤讀作「Selection: Cherry」——`setItemChecked` 也是。當某列
的 view 並非 `Checkable` 時，`AbsListView` 會對它呼叫 `setActivated(true)`，而這些 view 是普通容器，
沒有任何回應 `state_activated` 的 drawable，因此那個旗標抵達了、卻沒有東西把它畫出來。現在每一列都
帶有一個 foreground `StateListDrawable`，顏色即 ListView 自己的 selector 色，使「以程式選取的列」
與「手指底下的列」看起來相同。採用 foreground 而非 background，因為一列的 background 屬於 app 以
`.background()` 放在那裡的東西。

**幾何效果在格位邊緣被切斷。** P40 的 offset 磚被平移到完全正確的位置，然後失去 106 像素的寬與 53
像素的高；旋轉與傾斜的磚都止於它們變換前方框的右緣。變換本身沒有任何問題。Android 是此處唯一
「父元件預設會裁切子元件」的 backend：`ViewGroup.clipChildren` 為 true，而 `UIView.clipsToBounds`
為 false、`NSView` 不裁切、GTK 會畫到 allocation 之外。`CustomContainer` 與
`GeometricEffectContainer` 不再裁切，而這一點沒有任何東西依賴——`BackendFeatures.Clipping` 在
Android 上根本沒有實作，而 `CornerRadiusContainer` 是在它自己的 draw 中以 `canvas.clipPath` 裁切的。

**`Shape.fill(gradient)` 是一個平面色。** AndroidBackend 未實作 `renderPath` 的漸層 overload，
因此 `BackendFeatures.Paths` 提供了它的預設實作——壓平並發出警告。有兩件事使情況比聽起來更糟：
壓平後得到的是**第一個 stop** 而非中點，因為 `ResolvedFillStyle.midpoint(of:)` 以 `min(by:)` 取
「最接近 0.5」的 stop，而雙 stop 漸層在 0.5 處打平；而它所記錄的那則警告從未出現，因為 Android
app 的 `print` 不會抵達 logcat。該 overload 現已使用 Android 自己的 `LinearGradient` 與
`RadialGradient` 實作。`RadialGradient` 沒有起始半徑；那是以重新映射 stop 位置來表達的，而不是
被丟棄。

**沿路發現、仍未修：** AndroidBackend 未實作 `BackendFeatures.Clipping`，因此 `.clipped()` 會走
`@CastBackend` 路徑。本樹中目前沒有任何測試 app 在 Android 上用到它。

## Fixed 2026-09-03: a ZStack's later child did not cover an earlier Button

P10 puts a `Button` and then an opaque `Color.orange` in a `ZStack`. On iOS and
macOS the button is invisible -- P10's own comment calls it "invisible on
purpose", because that is what makes a press reaching it a statement about
`allowsHitTesting(false)`. On Android the button was drawn on top of the orange.

**Not the insertion order.** That was the first suspicion and it was wrong. A
tree dump taken after layout shows the ZStack container holding `Button` at
index 0 and the orange's container at index 1, which is the declared order.
What differed was Z: the platform button style gives a `Button`
`elevation=5.25` -- 2dp at density 2.625 -- against the orange's 0, and
**Android orders siblings by Z first and by child index second**. A
`uiautomator` dump could not tell the two candidates apart, because it lists
drawing order, which is what Z has already decided.

`CustomContainer` now makes the declaration order win where the two disagree.
Only where they disagree: a container whose Z values already rise with the index
is untouched, which is nearly all of them, so a button alone in its wrapper
keeps the shadow that is a real part of how Android looks.

Two things had to be got right, and each was measured wrong first:

- **When.** The first version ran in `onLayout`, saw every child at z=0, found
  nothing to correct, and left the button on top. A button's elevation comes
  from its state-list animator, which runs after layout and before the first
  draw. The check belongs in `dispatchDraw`.
- **What.** Cancelling `translationZ` alone did nothing: the animator owns that
  property and put its own value back, so the tree still read `Button z=5.25`
  after a pass that had just zeroed it. The animator has to be cleared first.

**Scope.** Any `ZStack` with a native control below something else. P10's
action file was written while this was open and said its overlay claim was
weaker on Android than elsewhere; it now makes the same claim as the other
platforms, and records that it once could not.

## 已修 2026-09-03：ZStack 中較晚宣告的子元件無法覆蓋較早的 Button

P10 在一個 `ZStack` 中依序放入一個 `Button` 與一個不透明的 `Color.orange`。在 iOS 與 macOS 上
那顆按鈕是看不見的——P10 自己的註解稱它是「刻意看不見的」，正因如此，「按壓抵達了它」才成為一項
關於 `allowsHitTesting(false)` 的陳述。而在 Android 上，按鈕被畫在橘色之上。

**不是插入順序。** 那是最初的懷疑，而它是錯的。版面完成後所取的樹狀 dump 顯示，ZStack 容器持有的
是索引 0 的 `Button` 與索引 1 的橘色容器，那正是宣告的順序。真正不同的是 Z：平台的按鈕樣式給了
`Button` `elevation=5.25`——density 2.625 下的 2dp——而橘色是 0，且 **Android 先依 Z、再依子元件
索引排序同層元件**。`uiautomator` 的 dump 無法分辨那兩個候選成因，因為它列出的是繪製順序，而那
早已由 Z 決定。

`CustomContainer` 現在會在兩種排序衝突時使宣告順序勝出。而且僅在衝突時：Z 值本來就隨索引遞增的
容器完全不受影響，而那幾乎是全部——因此一顆獨自位於其外層中的按鈕，仍保有那道屬於 Android 外觀
真實一部分的陰影。

有兩件事必須做對，而每一件都先量錯過一次：

- **時機。** 第一版在 `onLayout` 中執行，它看到的每個子元件都是 z=0，因而認定沒有東西需要修正，
  於是按鈕依然在上面。按鈕的 elevation 來自它的 state-list animator，而該 animator 在版面之後、
  首次繪製之前才執行。這項檢查該放在 `dispatchDraw`。
- **內容。** 只取消 `translationZ` 什麼也做不到：那個屬性是由該 animator 所擁有的，它會把自己的值
  放回去，因此在一次剛把它歸零的處理之後，樹狀結構讀到的仍是 `Button z=5.25`。必須先清除該
  animator。

**影響範圍。** 任何「原生控制項位於其他東西之下」的 `ZStack`。P10 的動作檔是在此問題尚未修正時
撰寫的，當時寫明其覆蓋層主張在 Android 上比別處弱；它現在提出的是與其他平台相同的主張，並記下
它曾經無法如此。

## Fixed 2026-09-03: a list row lit up under the press and changed nothing else

P16's sidebar is a `List(selection:)`. Pressing a row highlighted it and left
the detail pane reading "Select an area" whichever row was pressed.

`createSelectableListView` registered only
`AdapterView.OnItemSelectedListener`. That callback is about the *focused*
item -- the one a D-pad or trackball moved to. A `ListView` on a touchscreen is
in touch mode, where there is no focused item at all, so a tap fires
`onItemClick` and never `onItemSelected`. The binding was accepted and did
nothing, and the highlight came from the row's own pressed state, which is what
made it look like it had worked.

`setSelectedItem` had the matching half of the same misreading: it called
`setSelection`, which in touch mode also does nothing. The list is in
`CHOICE_MODE_SINGLE`, so `setItemChecked` is the state it actually carries.

Fixed by having `ListItemSelectedListener` implement both interfaces and
registering it as both. Verified: P16's detail pane reads "Science" after the
row is pressed.

## 已修 2026-09-03：清單的列在按壓下亮起，其餘毫無變化

P16 的側欄是一個 `List(selection:)`。按下任何一列都會讓它亮起，而 detail 窗格無論如何都讀作
「Select an area」。

`createSelectableListView` 只註冊了 `AdapterView.OnItemSelectedListener`。該 callback 講的是
**取得焦點**的項目——也就是 D-pad 或軌跡球移動到的那一個。觸控螢幕上的 `ListView` 處於 touch mode，
而該模式下根本沒有取得焦點的項目，因此點擊觸發的是 `onItemClick`，永遠不會是 `onItemSelected`。
該繫結被接受了，卻什麼都沒做；而那個高亮來自該列自身的按下狀態——正是它讓整件事看起來像是成功了。

`setSelectedItem` 犯的是同一個誤讀的另一半：它呼叫 `setSelection`，而該方法在 touch mode 下同樣
什麼都不做。此清單處於 `CHOICE_MODE_SINGLE`，因此 `setItemChecked` 才是它真正持有的狀態。

修法是讓 `ListItemSelectedListener` 同時實作兩個介面，並以兩者的身分註冊它。已驗證：按下該列之後，
P16 的 detail 窗格讀作「Science」。

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
