# CLAUDE.md — swift-cross-ui

Rules for this repository. The user's global `~/.claude/CLAUDE.md` still applies;
nothing here contradicts it.

---

## No feature may be left "not supported" on a shipped backend

**Android, iOS, Linux, macOS, Windows and WSL must all implement every feature.
Windows carries two backends — GtkBackend and WinUIBackend — and both count.**

That is six platforms and, counting Windows twice, five backends:
`GtkBackend`, `WinUIBackend`, `AppKitBackend`, `UIKitBackend`, `AndroidBackend`.

### What this rules out

A missing `BackendFeatures` conformance has three possible responses. Only one
of them is acceptable here.

| Response | Acceptable |
| --- | --- |
| `fatalError` — the process dies | No. It takes the whole app down for one modifier. |
| Degrade — warn once, render unmodified | No, not on these five. |
| Implement it | Yes. |

Degradation is a safety net for backends outside that set — `CursesBackend`,
`LVGLBackend`, `QtBackend`, `DummyBackend`. It is not a way to close a gap on a
shipped target.

### Why the rule is stated this strongly

The pattern it exists to stop is one I followed on 2026-09-02. `AppKitBackend`
implemented neither `VisualEffects` nor `GeometricEffects`, and the modifiers
went through `@CastBackend`, which expands to `fatalError`. Three of the
forty-two test apps had no window on macOS at all as a result.

Making them degrade instead — warn once, show the view unmodified — was a real
improvement over aborting, and it was still the wrong answer. The instruction
was: *"This is wrong, I need your help to implement it in swift"*, and
*"It shall work for all backends"*. What actually closed the gap was
implementing the feature: a `CIFilter` chain for AppKit, a `CATransform3D` for
AppKit and UIKit, a `RenderEffect` and an animation matrix for Android.

**A truthful report of a missing feature is not the same as a working feature.**
Degrading produces the first and looks like the second.

### "The platform has no API for this" is a claim to verify, not a conclusion

I have used that sentence once to decline implementing `VisualEffects` for
UIKitBackend, on the grounds that `CALayer.filters` does not composite on iOS.
The decline was rejected. If a platform genuinely cannot express a feature, that
has to be demonstrated — the specific API tried, and what it did — not asserted
from memory, and the answer is still to find the way the platform *does* do it.

---

## 沒有任何功能可以在已發布的 backend 上維持「不支援」

**Android、iOS、Linux、macOS、Windows 與 WSL 全部都必須實作每一項功能。Windows 帶有兩個
backend——GtkBackend 與 WinUIBackend——兩者都算。**

也就是六個平台、五個 backend：`GtkBackend`、`WinUIBackend`、`AppKitBackend`、
`UIKitBackend`、`AndroidBackend`。

### 這條規則排除了什麼

面對缺失的 `BackendFeatures` conformance，有三種可能的回應，而此處只接受其中一種。

| 回應 | 可接受 |
| --- | --- |
| `fatalError`——行程直接終止 | 否。為了一個 modifier 而拖垮整個 app。 |
| 降級——警告一次、顯示未修飾的 view | 否，在這五個 backend 上不行。 |
| 實作它 | 是。 |

降級是給該集合以外的 backend 兜底用的——`CursesBackend`、`LVGLBackend`、`QtBackend`、
`DummyBackend`。它不是用來填補已發布目標之缺口的手段。

### 為何這條規則寫得如此強硬

它要阻止的，正是我在 2026-09-02 所採取的做法。`AppKitBackend` 既未實作 `VisualEffects` 也未實作
`GeometricEffects`，而相關 modifier 走的是 `@CastBackend`，該 macro 會展開為 `fatalError`。
其結果是四十二支測試 app 中有三支在 macOS 上根本開不出視窗。

把它們改為降級——警告一次、顯示未修飾的 view——相對於中止行程確實是真正的改善，但那依然是錯的答案。
當時得到的指示是：*「這是錯的，我要你用 Swift 實作出來」*，以及*「它必須對所有 backend 有效」*。
真正填補缺口的是實作本身：AppKit 的 `CIFilter` 鏈、AppKit 與 UIKit 的 `CATransform3D`、
Android 的 `RenderEffect` 與 animation matrix。

**如實回報一項缺失的功能，與擁有一項可運作的功能，是兩回事。** 降級產出的是前者，看起來卻像後者。

### 「這個平台沒有對應的 API」是一項待查證的主張，不是結論

我曾以這句話拒絕為 UIKitBackend 實作 `VisualEffects`，理由是 `CALayer.filters` 在 iOS 上不參與
合成。該拒絕未被接受。若某個平台確實無法表達某項功能，那必須被證明——列出所嘗試的具體 API 及其
結果——而不是憑印象斷言；而且答案仍然是去找出該平台**做得到**的方式。
