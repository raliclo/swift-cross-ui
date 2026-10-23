# plan: the shape of a focus protocol (#122), and where accessibility (#123) differs

**狀態:已實作。** 這份形狀於 2026-09-16 在五個 backend 落地(`ef1c4c02`、`38394d14`、`ab2d1d51`),
協定是 `BackendFeatures.FocusableViews`。以下保留實作前的草案。

**Status: implemented.** This shape landed on all five backends on 2026-09-16
(`ef1c4c02`, `38394d14`, `ab2d1d51`) as `BackendFeatures.FocusableViews`. The
draft below is kept as written before implementation.

#122 的協議是「先定形狀、再寫任何 backend」,AppKit/UIKit/Android 三份由 Mac 負責、GTK 與 WinUI 由 Windows 負責。
這份文件是那個形狀,連同**在 Mac 上查得到的部分已經查過**——因為同一週已經有兩次「寫在無法編譯
該檔的機器上」的實作,用到了並不存在的 API。

#122 was agreed as shape first, backends after, with the Mac owning AppKit, UIKit
and Android and Windows owning GTK and WinUI. This is that shape, with the parts
that could be checked on the Mac already checked -- twice that week an
implementation written on a machine that cannot compile the file used an API
that does not exist.

---

## 一、先查證,再設計 / What was verified first

以「列出綁定自身的方法」而非憑記憶:

| 平台 | 需要的東西 | 綁定中是否存在 |
| --- | --- | --- |
| Android | `requestFocus()` / `clearFocus()` / `hasFocus()` | ✅ `AndroidKit/Sources/AndroidView/View.swift:661,205,208` |
| Android | `setFocusable(_:)` / `setFocusableInTouchMode(_:)` | ✅ 同檔 484、490 |
| AppKit | `makeFirstResponder(_:)`、`acceptsFirstResponder` | ✅ 平台 API |
| UIKit | `becomeFirstResponder()` / `resignFirstResponder()` / `canBecomeFirstResponder` | ✅ 平台 API |
| **GTK** | `gtk_widget_grab_focus` | ⚠️ 產生出來的 Swift 沒有它,**但 C 符號可直接呼叫**——見下方更正 |

~~**GTK 那一格是這份草案裡最重要的一行。** 在寫任何 GTK 實作之前,`grabFocus` 必須先被產生出來~~
——**這句話是錯的,2026-09-10 更正。**

「產生出來的 Swift 沒有它」是真的,但它推不出「不能用」。**`Sources/Gtk` 本來就直接呼叫 C 符號**,
而且到處都是:`gtk_widget_set_parent`(8 次)、`gtk_widget_measure`(6)、`gtk_widget_compute_point`
(3)、`gtk_widget_add_tick_callback`(3,見 `Widgets/NV12GLView.swift:248`)。該模組 `import CGtk`,
因此 `gtk_widget_grab_focus(pointer)` 今天就能寫。

程式碼產生器是為了「要一個 Swift 類別」時用的(#32 的三個 `Gesture*` 是類別,所以那次確實需要);
要的若只是一個函式,直接呼叫它。**原先的草案把「binding 缺席」讀成了「能力缺席」,那兩者不是同一回事**
——而這正是本檔開頭所警告的那種錯誤的鏡像版本。

~~The GTK row is the most important line here.~~ **Corrected 2026-09-10.** The
generated Swift not having `grabFocus` is true and does not imply it cannot be
used: `Sources/Gtk` calls C symbols directly throughout -- `gtk_widget_measure`,
`gtk_widget_compute_point`, `gtk_widget_add_tick_callback` -- and imports CGtk.
The generator is for when a Swift CLASS is wanted, which is why #32's three
`Gesture*` types did need it. A function can just be called. The first draft
read "the binding is absent" as "the capability is absent", and those are not the same thing.

---

## 二、五個模型真的不同,而差異落在三個問題上 / Where the five models actually differ

不是「名字不同」,是**語意不同**。三個問題就能把差異分完:

| 問題 | AppKit | UIKit | GTK | WinUI | Android |
| --- | --- | --- | --- | --- | --- |
| 焦點屬於誰? | 視窗的 first responder **鏈**,每個視窗一個 | responder 鏈,每個 **scene** 一個 | 每個 `GtkWindow` 一個 | `FocusManager`,可跨 XAML 島 | view 樹,每個視窗一個 |
| 要求焦點會被拒絕嗎? | 會(`acceptsFirstResponder` 為 false) | 會(`canBecomeFirstResponder` 為 false) | 會(不可 focus 的 widget) | 會 | **會,而且理由是別處沒有的:touch mode** |
| 焦點會自己移動嗎? | 會(Tab、點擊、VoiceOver) | 會(Tab、觸控、VoiceOver) | 會(Tab、點擊) | 會 | 會(方向鍵、無障礙服務) |

**Android 的 touch mode 是唯一一個「別的平台沒有對應物」的東西。** 在觸控模式下,view 預設**不可**取得
焦點,`requestFocus()` 會失敗;要讓它成功,必須先 `setFocusableInTouchMode(true)`。這不是實作細節:
它意味著「要求焦點」在 Android 上是一個**可能失敗且理由正當**的操作,而其餘四個平台上的失敗多半代表
呼叫者搞錯了。

Android's touch mode has no counterpart elsewhere: in touch mode a view is not
focusable by default and `requestFocus()` fails. So "ask for focus" is an
operation that legitimately fails there, while on the other four a failure
usually means the caller was wrong.

---

## 三、提議的形狀 / The proposed shape

```swift
extension BackendFeatures {
    public protocol FocusableViews: Core {
        /// Gives this widget the focus within its window.
        ///
        /// Returns whether it took it. A widget can legitimately refuse --
        /// Android in touch mode, a disabled control, a view that does not
        /// accept first responder -- and a `Void` return would make every
        /// refusal silent.
        func focus(_ widget: Widget) -> Bool

        /// Takes focus away from this widget, if it has it.
        ///
        /// Does nothing when it does not: "unfocus something that is not
        /// focused" is not an error, and treating it as one would make every
        /// caller check first.
        func unfocus(_ widget: Widget)

        /// Whether this widget currently holds the focus.
        func isFocused(_ widget: Widget) -> Bool

        /// Called when focus arrives at or leaves this widget, for any reason.
        ///
        /// Required, not optional, and this is the half that cannot be
        /// simulated: focus moves for reasons the app did not cause -- Tab, a
        /// click, a screen reader, Android's directional pad. Without this a
        /// `@FocusState` would be correct only until the user touched anything.
        func setFocusChangeHandler(
            ofWidget widget: Widget,
            to handler: @escaping (Bool) -> Void
        )
    }
}
```

### 為什麼是這四個,而不是更少

**`focus` 回傳 `Bool`,不回傳 `Void`。** Android 的 `requestFocus()` 本來就回傳 `Bool`,而在 touch mode
下它會**正當地**失敗。一個回傳 `Void` 的版本會讓「這個 widget 拒絕了焦點」與「焦點成功移過去了」在
呼叫端讀起來一模一樣——那正是這棵樹一再抓到的形狀。

**`setFocusChangeHandler` 是必要的,不是加分項。** 理由與 `Slider.onEditingChanged`(#126)完全相同:
焦點會因為 app 沒有造成的原因而移動。少了它,`@FocusState` 只在「使用者什麼都沒碰」時是對的。

**不放 `focusNext()` / `focusPrevious()`。** 五個平台對「下一個」的定義不同(AppKit 的 key view loop、
GTK 的 focus chain、Android 的 `focusSearch(int)` 方向式),而把它們硬塞進一個方法,等於讓一方的模型
冒充通用模型。若日後需要,它應該是一個獨立的 requirement,並帶著自己的量測。

### 框架這一側

`@FocusState` 綁定一個值;framework 把它映射成 `focus`/`unfocus`,並用 handler 把使用者造成的改變寫
回那個 binding。那一層不屬於本 protocol,但形狀必須先對,否則它無處可接。

---

## 四、#123 accessibility 為何**不是**同一個 protocol / Why accessibility is separate

focus 與 accessibility 常被放在一起,但它們的**形狀不同**:

- focus 是一個**動作加一個事件**(去要、被拒絕、被通知)。
- accessibility label/hint/value 是**屬性**——設下去就在那裡,不會有人在別處改動它,也不需要回報。

因此 #123 應該是一組單向的 setter,與 `TapGestures` 現在的形狀一樣:

```swift
func setAccessibilityLabel(ofWidget widget: Widget, to label: String?)
func setAccessibilityHint(ofWidget widget: Widget, to hint: String?)
func setAccessibilityValue(ofWidget widget: Widget, to value: String?)
func setAccessibilityHidden(ofWidget widget: Widget, to hidden: Bool)
```
把兩者合成一個 protocol,會讓「只想加標籤」的 backend 被迫實作焦點回報。分開之後,#123 可以先落地。
而 #122 等 GTK 的 `grabFocus` 產生出來。

Focus is an action plus an event; accessibility labels are properties nobody
else changes. One protocol for both would force a backend that only wants labels
to implement focus reporting, so they are separate -- and #123 can land first,
to implement focus reporting, so they are separate, and #123 can land first.

---

## 五、需要 Windows 同意的事(已定)/ What needed agreement (settled)

1. **這個四方法的形狀**,特別是 `focus` 回傳 `Bool`。已照此實作(2026-09-16:`ef1c4c02` AppKit/UIKit/Android、`38394d14` GTK、`ab2d1d51` WinUI)。
2. ~~**`grabFocus` 要先產生**~~ ——**取消,原判斷有誤。** 直接呼叫 `gtk_widget_grab_focus`,與本模組既有的十幾處 C 呼叫相同。
3. **#123 與 #122 分開**,而 #123 可以先做。
4. WinUI 那一格:草案時唯一無法在 Mac 上查證的衝突是 `FocusManager.TryFocusAsync` 為非同步、本 protocol 的
   `focus` 為同步。結果不需要改形狀:WinUIBackend 用的是一直都在 `UIElement` 上、同步並回傳 `Bool` 的
   `focus(_:)`(見 `WinUIBackend+Focus.swift`)。

The one item that could not be checked on the Mac was WinUI:
`FocusManager.TryFocusAsync` is asynchronous while `focus` here is synchronous.
The shape did not have to change: WinUIBackend uses `UIElement.focus(_:)`, which
is synchronous and returns `Bool` (see `WinUIBackend+Focus.swift`).
