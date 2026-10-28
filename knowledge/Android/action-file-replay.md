# Action-file replay on Android

Sources/AndroidBackend/AndroidSynthesiser.swift and Kotlin/FrontWindows.kt,
checked 2026-10-24. Files live in `testapp/actions/android/` (147 files,
2026-10-24); a file is kept there only after it has run on Android.

## How it works

- **In process.** Events are posted into the app's own activity
  (`Activity.dispatchTouchEvent` / `dispatchKeyEvent`). Nothing can drive
  another app, and nothing outside the app's windows is reachable.
- **Points to pixels at the last moment**, with the activity's density (what
  the backend laid out against), not the display's.
- **Origin**: an activity fills the screen, so frame and client origin are 0.
  The client origin then follows the root scroll host's displacement, so files
  measured before an oversized root started at its top-left (2026-10-09) still
  press the same views. The first geometry read waits until the root host is at
  rest **and** no layout is pending: the push that clears the mode button
  lands a pass later, and the same file put P35's point at y 793 on one run and
  887 on the next (2026-10-13).
- **Off-screen points**: the replay scrolls the root host to bring them on
  screen, says so in the log, and subtracts that scroll from later points.

## Verb semantics that differ from the desktop

- `move` outside a press posts nothing (a touch screen has no hover); it only
  records where a coordinate-less `click` lands. Between `mousedown` and
  `mouseup` it is the finger moving (ACTION_MOVE); that is how P88 drags after
  a long press. A drag is therefore down, move rows, up.
- A press and its release share one `downTime`; a release with a fresh one ends
  nothing.
- **Long press is real elapsed time.** `View.onTouchEvent` posts a long-press
  runnable on ACTION_DOWN and cancels it on ACTION_UP, so the hold sleeps on the
  replay thread while the main thread runs the runnable. Timestamps 500 ms
  apart posted back to back are a tap. No moves are sent during the hold.
- `scroll` is wheel notches turned into a drag: 40 pt per notch, sign inverted
  (as the iOS runner), with intermediate points, and the finger rests before
  lifting; lifted straight off the last move it is a fling (P34's two notches
  ran its list to the end, 2026-10-13). A screenful is 15-22 notches; a row
  like `scroll,0,300` asks for a drag far off the screen and moves nothing
  without an error.
- `taplabel` finds the view by its text (focused sheet first) and presses its
  centre via `getLocationInWindow`. It survives layout changes and AVD
  changes, so it is preferred over coordinates.
- `focus "<title>"` switches later rows to that window's activity and
  re-measures geometry; an unknown or not-yet-started window is an error, not
  a silent fallback to the first window (since 2026-10-20).
- `orient` asks the activity for an orientation; the configuration change that
  follows is the same as a rotation.
- The cursor verb asks `onResolvePointerIcon` on the decor with a
  `SOURCE_MOUSE` hover event: it proves which icon Android resolves at a point,
  not that a cursor is drawn (the AVD has no pointer device).
- F13-F20 have no Android keycode and are refused by name.
- `key back` posts `KEYCODE_BACK`, which reaches the `OnBackPressedDispatcher`
  through the activity's `onKeyUp`, with the same result as `adb shell input
  keyevent KEYCODE_BACK` (P113-back.actions, 2026-10-28). The back gesture is
  not covered.

## Front windows

`dispatchTouchEvent` reaches the activity's own window only. Sheets (Dialog)
and popovers (PopupWindow) register their root in `FrontWindows` while shown,
and events go to the focused one with coordinates translated into it. Since
2026-10-21 `FrontWindows.focused(activity)` also uses
`WindowInspector.getGlobalWindowViews` (API 29, no permission) to reach
platform-built windows: PopupMenu, Spinner dropdowns, alerts, and other
activities such as P60's settings window. It leaves out **only the target
activity's decor, by identity** (7c1fe16e): walking each root's context to an
Activity never matched and sent every key to the decor (P94 "changes: 0"), and
leaving out all `TYPE_BASE_APPLICATION` windows lost P60's settings activity.

## Checking a replay

`-actionfile: replayed` proves the file ran, not that it did anything. Read
the app's own log lines or the final capture; see harness-run.md for
verify_replay_android.zsh and verify_effect_android.zsh. Twelve apps that run
their own steps (P85, P86, P89, P95-P101, P104, P112) have sleep-only files
with no coordinates, valid on any AVD (db561114).

## Stale statements

The P80 row of results.csv2 (2026-10-20) says the replay cannot press into a
platform PopupMenu; that was true until the WindowInspector change the next day.

---

# Android 上的動作檔重播

Sources/AndroidBackend/AndroidSynthesiser.swift 與 Kotlin/FrontWindows.kt,2026-10-24 查過。檔案放在
`testapp/actions/android/`(2026-10-24 共 147 個);只有在 Android 上實際跑過的檔案才會留在那裡。

## 運作方式

- **在程序內。** 事件送進 app 自己的 activity(`Activity.dispatchTouchEvent` / `dispatchKeyEvent`)。無法驅動其他 app,
  app 視窗以外的東西也碰不到。
- **最後一刻才把 point 換成 pixel**,用的是 activity 的密度(backend 排版所依據的那個),不是螢幕的。
- **原點**:activity 佔滿螢幕，所以 frame 與 client 原點都是 0。client 原點接著加上根 scroll host 的位移，因此在「過大的根
  從左上角開始」(2026-10-09)之前量的檔案仍會按到同樣的 view。第一次讀取幾何資訊要等根 host 靜止**而且**沒有待處理的排版：
  讓開模式按鈕的那次推移會晚一個 pass 才到，同一個檔案曾讓 P35 的點一次落在 y 793、一次落在 887(2026-10-13)。
- **螢幕外的點**:重播會捲動根 host 把它帶進螢幕，在紀錄裡說明，並從之後的點扣掉這段捲動。

## 與桌面不同的動詞語意

- 按下之外的 `move` 不送任何事件(觸控螢幕沒有 hover),只記錄沒有座標的 `click` 要落在哪裡。在 `mousedown` 與 `mouseup`
  之間則是手指移動(ACTION_MOVE);P88 就是這樣在長按後拖曳。因此拖曳是：按下、數列 move、放開。
- 一次按下與其放開共用同一個 `downTime`;帶著新 `downTime` 的放開什麼都不會結束。
- **長按是真實經過的時間。** `View.onTouchEvent` 在 ACTION_DOWN 時排入一個長按 runnable,在 ACTION_UP 時取消，所以按住期間
  是在重播執行緒上 sleep,讓主執行緒去跑那個 runnable。時間戳相差 500 ms 卻接連送出的兩個事件只是一次點擊。按住期間不送 move。
- `scroll` 是把滾輪格數換成拖曳：每格 40 pt、方向相反(與 iOS runner 相同),中間有過渡點，放開前手指先停住；直接從最後一個
  move 放開就成了 fling(P34 的兩格讓清單直接捲到底,2026-10-13)。一個螢幕高約 15–22 格；像 `scroll,0,300` 這樣的列要求
  拖到螢幕外很遠的地方，什麼都不會動，也不會報錯。
- `taplabel` 依文字找到 view(先找有焦點的 sheet),以 `getLocationInWindow` 按它的中心。它不受版面與 AVD 變動影響，所以比
  座標優先。
- `focus "<標題>"` 讓之後的列改送到該視窗的 activity,並重新量測幾何；不存在或尚未啟動的視窗會報錯，不會默默退回第一個視窗
  (自 2026-10-20)。
- `orient` 向 activity 要求某個方向，隨後的設定變更與實際旋轉相同。
- 游標動詞以 `SOURCE_MOUSE` 的 hover 事件在 decor 上呼叫 `onResolvePointerIcon`:它證明的是 Android 在該點會選哪個圖示，
  不是游標有被畫出來(這個 AVD 沒有指標裝置)。
- F13–F20 在 Android 沒有 keycode,會依名稱拒絕。
- `key back` 投遞 `KEYCODE_BACK`,經 activity 的 `onKeyUp` 到達 `OnBackPressedDispatcher`,與 `adb shell input keyevent
  KEYCODE_BACK` 結果相同(P113-back.actions,2026-10-28)。返回手勢不在其內。

## 前景視窗

`dispatchTouchEvent` 只送到 activity 自己的視窗。sheet(Dialog)與 popover(PopupWindow)顯示期間會把根 view 登記在
`FrontWindows`,事件交給有焦點的那一個，並換算成它的座標。自 2026-10-21 起,`FrontWindows.focused(activity)` 也用
`WindowInspector.getGlobalWindowViews`(API 29,不需權限)找到平台建立的視窗:PopupMenu、Spinner 下拉、alert,以及其他 activity,
例如 P60 的設定視窗。它**只排除目標 activity 的 decor,以同一物件比較**(7c1fe16e):沿每個根的 context 找 Activity 的做法從未
比對成功，讓所有按鍵都送進 decor(P94「changes: 0」);排除所有 `TYPE_BASE_APPLICATION` 視窗則失去了 P60 的設定 activity。

## 檢查重播

`-actionfile: replayed` 證明檔案跑過，不證明它有作用。請讀 app 自己的紀錄行或最後的擷圖；verify_replay_android.zsh 與
verify_effect_android.zsh 見 harness-run.md。十二支自己執行步驟的 app(P85、P86、P89、P95–P101、P104、P112)的檔案只有等待、
沒有座標，在任何 AVD 上都有效(db561114)。

## 過期的敘述

results.csv2 的 P80 列(2026-10-20)說重播無法按進平台的 PopupMenu;那只在隔天改用 WindowInspector 之前成立。
