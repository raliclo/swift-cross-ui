# Keys and menu shortcuts on Android

Fixed 2026-09-25 (0e320730); P71 passes since. Later additions 2026-10-14
(P94) and 2026-10-22 (7c1fe16e).

## What

- A key event follows the **focus chain**. `ViewGroup.dispatchKeyEvent`
  dispatches to `mFocused` or to itself and otherwise returns false; it does
  not walk its children. With nothing focused (P71's normal state) no view
  under the decor sees the key at all.
- App-menu shortcuts used to be an `OnUnhandledKeyEventListener` on the decor,
  which `ViewRootImpl` runs after the hierarchy declines a key, above anything
  an app can post to. A replay posts through `Activity.dispatchKeyEvent`,
  below that, so an action file could not reach them, while
  `adb shell input keycombination -t 120 113 47` could.
- **`ShortcutHostLayout` is now the window's content view** and handles both:
  it looks the key up in the shortcut table after `super.dispatchKeyEvent`
  declines (so a text field still gets its own keys first), and it takes focus
  with `FOCUS_AFTER_DESCENDANTS`, holding it only when nothing else wants it.
  Returning true stops `ViewRootImpl` before the unhandled-key manager, so a
  shortcut never fires twice.
- `setApplicationMenu` can run before the content view exists, so the listener
  is stored and attached from both sides.

## Replay rules (AndroidSynthesiser)

- Modifier state is carried by the synthesiser: a synthesised `KeyEvent` has
  its own `metaState` and nothing infers it. The bit is cleared **before** the
  release event is built; a release that still carries shift reads as a stuck
  modifier (AppKitSynthesiser had the same defect on 2026-09-19).
- Write shortcuts with Control, not Command. A Command row presses
  `KEYCODE_META_LEFT`, whose `META_META_ON` the comparison mask drops, and the
  counters read 0 as if nothing were registered.
- An unhandled key with Control held is offered as a shortcut to the focused
  view, as `ViewRootImpl` would: that is how a focused text view gets
  Control-A/X/C/V/Z and Shift-Z (P94 "changes: 0" before, 2026-10-14).
- An unhandled Tab moves focus, as the view root does for real input.
- Keys go to a focused sheet first; Escape there cancels it (P49).

## What does not work, and was tried

An app cannot inject at system level. `Instrumentation.sendKeySync` would enter
at `ViewRootImpl`, and `InputDispatcher` exempts an injector owning the focused
window, but the permission check comes first: refused 7 of 7 on 2026-09-23 with
"Injecting input events requires ... the INJECT_EVENTS permission". The code was
removed.

## Contradiction in the source

The long comment above the key path in AndroidSynthesiser.swift still says an
app-menu shortcut is out of reach of an action file. That describes
2026-09-23. `actions/android/P71-shortcuts.actions` and 0e320730 record PLAIN 1,
SHIFTED 1, DISABLED 0 from the file since 2026-09-25 through
ShortcutHostLayout; trust those.

---

# Android 上的按鍵與選單快捷鍵

2026-09-25 修正(0e320730),P71 自此通過。之後的補充:2026-10-14(P94)與 2026-10-22(7c1fe16e)。

## 內容

- 按鍵事件跟著**焦點鏈**走。`ViewGroup.dispatchKeyEvent` 只派給 `mFocused` 或自己，否則回傳 false,不會走訪子節點。沒有任何
  東西持有焦點時(P71 的正常狀態),decor 底下沒有任何 view 看得到按鍵。
- app 選單快捷鍵原本是 decor 上的 `OnUnhandledKeyEventListener`,由 `ViewRootImpl` 在整個階層都不處理該鍵之後才執行，位於 app
  能送事件的層級之上。重播經由 `Activity.dispatchKeyEvent` 送出，在那之下，所以動作檔碰不到它們，而
  `adb shell input keycombination -t 120 113 47` 碰得到。
- **`ShortcutHostLayout` 現在是視窗的 content view**,兩件事都由它處理：在 `super.dispatchKeyEvent` 不處理之後查快捷鍵表
  (所以文字欄位仍先拿到自己的按鍵),並以 `FOCUS_AFTER_DESCENDANTS` 取得焦點，只在沒有別人要焦點時才持有。回傳 true 會讓
  `ViewRootImpl` 在 unhandled-key manager 之前停下，所以快捷鍵不會觸發兩次。
- `setApplicationMenu` 可能在 content view 存在之前執行，所以 listener 先存起來，兩邊都會掛上。

## 重播規則(AndroidSynthesiser)

- 修飾鍵狀態由 synthesiser 自己保存：合成的 `KeyEvent` 帶著自己的 `metaState`,沒有東西會推斷它。放開事件建立**之前**就要清掉
  該位元；仍帶著 shift 的放開事件看起來像修飾鍵卡住(AppKitSynthesiser 在 2026-09-19 有同樣的缺陷)。
- 快捷鍵用 Control 寫，不要用 Command。Command 列按的是 `KEYCODE_META_LEFT`,其 `META_META_ON` 會被比對遮罩丟掉，計數器讀到 0,
  看起來就像什麼都沒登記。
- 按住 Control 而未被處理的按鍵，會像 `ViewRootImpl` 那樣以快捷鍵的形式交給有焦點的 view:有焦點的文字 view 就是這樣拿到
  Control-A/X/C/V/Z 與 Shift-Z(之前 P94 是「changes: 0」,2026-10-14)。
- 未被處理的 Tab 會移動焦點，與 view root 對真實輸入的處理相同。
- 按鍵先送到有焦點的 sheet;在那裡按 Escape 會取消它(P49)。

## 試過而行不通的

app 無法在系統層注入。`Instrumentation.sendKeySync` 會從 `ViewRootImpl` 進入，而且 `InputDispatcher` 會豁免擁有焦點視窗的注入者，
但權限檢查在前面:2026-09-23 七次中七次被拒，訊息為「Injecting input events requires ... the INJECT_EVENTS permission」。
該程式碼已移除。

## 原始碼中的矛盾

AndroidSynthesiser.swift 按鍵路徑上方的長註解仍說動作檔碰不到 app 選單快捷鍵。那描述的是 2026-09-23。
`actions/android/P71-shortcuts.actions` 與 0e320730 記錄自 2026-09-25 起經由 ShortcutHostLayout,從動作檔得到 PLAIN 1、
SHIFTED 1、DISABLED 0;以它們為準。
