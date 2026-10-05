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

## Edit every file through csv2

The user's rule (2026-10-05): csv2 is the editor for every file in this tree --
`.md`, `.zsh`, `.swift` as well as CSVs -- not Python string replacement, which
matches an invisible span and has changed the wrong line here. Line mode is
`--headers 0`: each line is one record of one field, the record number is the
line number, and bytes are kept as they are (LF and the trailing newline too).

- Find: `csv2 --headers 0 -contains 'text' -i FILE` (reports line numbers).
- One line: `-update-where 'old line' 'new line' -i FILE --in-place`. It refuses
  unless exactly one line matches, so it is the safe default.
- A block: `-update N:1 --value-file F -i FILE --in-place`. F must not end in a
  newline, or a blank line appears. One `-update` per call with `--value-file`.
- Separate calls shift line numbers, so edit bottom-up. Several `-insert N` at the
  same N keep their order.
- A `.csv`/`.csv2` suffix forces CSV parsing even with `--headers 0`, and action
  files (`#` lines) are refused that way: read them from stdin,
  `csv2 -si --headers 0 -get N:1 < file.csv`.
- A new or rewritten file: `print -rl -- "${lines[@]}" | csv2 -si --headers 0 -r -o FILE`.
  `-append` fails on an empty file.
- Real CSVs: `testapp/test_support/csv2_rows.zsh` (`csv2_new`, `csv2_append`,
  `csv2_has`). Every CSV is LF.
- Afterwards: `git diff`, and `zsh -n` for scripts.

If csv2 cannot express an edit, say so and name the tool used instead.

## 每個檔案都透過 csv2 編輯

使用者的規則(2026-10-05):csv2 是本樹每個檔案的編輯器——`.md`、`.zsh`、`.swift` 與 CSV 皆然——
而不是 Python 字串替換；後者會比對到一段看不見的文字，在這裡曾經改錯行。逐行模式是 `--headers 0`:
每一行是一筆只有一個欄位的紀錄，紀錄編號就是行號，位元組原樣保留(LF 與結尾換行亦然)。

- 找：`csv2 --headers 0 -contains '文字' -i FILE`(回報行號)。
- 改一行：`-update-where '舊行' '新行' -i FILE --in-place`。恰好一行相符才會執行，所以是安全的預設。
- 改一段：`-update N:1 --value-file F -i FILE --in-place`。F 不可以換行結尾，否則會多出一行空行。
  配合 `--value-file` 時一次只能一個 `-update`。
- 分開呼叫會讓行號位移，所以由下往上改。同一個 N 的多個 `-insert N` 會保持順序。
- `.csv`/`.csv2` 副檔名即使加了 `--headers 0` 也會強制以 CSV 解析，動作檔(`#` 開頭的行)因此被拒：
  改從 stdin 讀，`csv2 -si --headers 0 -get N:1 < file.csv`。
- 新建或整份重寫：`print -rl -- "${lines[@]}" | csv2 -si --headers 0 -r -o FILE`。
  空檔案上 `-append` 會失敗。
- 真正的 CSV:`testapp/test_support/csv2_rows.zsh`(`csv2_new`、`csv2_append`、`csv2_has`)。所有 CSV 都是 LF。
- 改完之後：`git diff`,腳本再加 `zsh -n`。

csv2 表達不了某個修改時，要明講，並說出改用了哪個工具。
