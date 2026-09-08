# P52: PrimitiveButtonStyle against a custom ButtonStyle

**Verdict, 2026-09-08: no measurable difference, and that refutes what this
session predicted before running it.**

Regenerate everything below with:

```zsh
SCUI_DEBUG=1 zsh testapp/compile.zsh P52 -gtk4
cd testapp/output && PATH=/c/gtk4/bin:$PATH ./P52-gtk4.exe --debug
```

Every number is a minimum of `n` samples with `n` printed beside it. Re-run
rather than quote this file if it is more than a week old.

**2026-09-08 判定：測不出差異，而這推翻了本 session 在執行之前所做的預測。**

上方的指令可重新產生以下每一個數字。每個數字都是 `n` 個樣本的最小值，且 `n` 都印在旁邊。若本檔已超過
一週，請重跑，而不要引用它。

---

## What was predicted, and what was wrong with it

Before P52 existed, this session reasoned from the code that a custom
`ButtonStyle` costs an extra layout pass per press transition, and that
`PrimitiveButtonStyle` therefore wins. **Two of the three premises do not
survive reading `Button.swift`.**

1. **The update chain is not extra.** `installPressHandler` is called from
   `Button.commit` for *every* button (`Button.swift:349`) and its guard passes
   on all five shipped backends. A `.bordered` press writes `isPressed`,
   publishes, and runs `bottomUpUpdate` -> `computeLayout` -> `commit` exactly
   as a custom-styled one does. The only genuinely extra work is inside
   `styledLabel(in:)` (`Button.swift:206-220`): one extra `AnyView` around the
   label, `makeBody` through an existential, `AnyView` of the result, and the
   style body's own layout.
2. **The padding saving is a cached return.** `buttonPadding(in:)` returns
   `SIMD2(0,0)` for `.plain` instead of calling `measureBorderedButtonPadding()`
   -- but that is memoised on both Windows backends. The saving is one cached
   return and two integer subtractions.

The third premise held: `Button.Children` is now `TupleViewChildren1<AnyView>`
unconditionally, so every button gains one container widget. Both arms pay it,
so it cancels in this comparison.

**本 session 原先的預測，以及它錯在哪裡。** 在 P52 存在之前，本 session 從程式碼推論：自訂
`ButtonStyle` 每一次按壓轉換都要多付一輪版面計算，因此 `PrimitiveButtonStyle` 較快。**三項前提中有
兩項讀過 `Button.swift` 之後就站不住。**

第一，那條更新鏈並非額外。`installPressHandler` 是在 `Button.commit` 中對**每一顆**按鈕呼叫的
（`Button.swift:349`），而其守衛在五個已發布的 backend 上都會通過。因此 `.bordered` 被按下時，同樣會
寫入 `isPressed`、發布、並執行 `bottomUpUpdate` → `computeLayout` → `commit`。真正額外的工作只在
`styledLabel(in:)` 之內。

第二，那項 padding 節省是「快取回傳」。`buttonPadding(in:)` 對 `.plain` 回傳 `SIMD2(0,0)` 而不呼叫
`measureBorderedButtonPadding()`——但後者在兩個 Windows backend 上都有記憶化。省下的是一次快取回傳
與兩個整數減法。

第三項成立：`Button.Children` 現在無條件是 `TupleViewChildren1<AnyView>`，因此每顆按鈕都多一層容器
widget。兩臂都付，所以在本比較中相抵。

---

## The measurement

48 buttons per arm, 10 rounds, 5 passes per round, interleaved round-robin with
the starting arm rotated each round. GtkBackend on Windows 11, 100% display
scale, release build.

| arm | n | min | median | max |
| --- | --- | --- | --- | --- |
| control (0 buttons) | 50 | 236 us | 326 us | 710,763 us |
| primitive | 50 | **289,907 us** | 374,199 us | 407,065 us |
| custom | 50 | **311,344 us** | 386,472 us | 466,661 us |

```
RATIO custom/primitive per transition = 1.07x
SEPARATION none: ranges overlap (primitive 289,907...407,065,
                                 custom    311,344...466,661)
```

**The ranges overlap, so the 1.07x is noise and not a result.** P52 prints that
sentence itself rather than leaving a reader to decide, because a ratio with no
separation test reads like a finding.

The control arm exists to size the fixed per-pass overhead: at 236 us against
arms of ~300,000 us it is 0.08%, so the arms genuinely dominate and 48 buttons
was enough. P52 emits `WARNING margin thin` and suggests `--buttons=96` if that
ever stops being true.

**量測。** 每臂 48 顆按鈕、10 輪、每輪 5 趟，採交錯輪替並於每輪旋轉起始臂。Windows 11 上的
GtkBackend、100% 顯示縮放、release 建置。**兩臂範圍重疊，因此 1.07x 是雜訊而非結果。** 控制臂的用途
是量出每趟的固定開銷：236 us 相對於約 300,000 us 的兩臂只佔 0.08%，因此兩臂確實主導了量測，48 顆按鈕
已經足夠。

---

## The number that does matter

About **6 ms per transition per button**, so one click on a 48-button screen
costs roughly **0.3 s** of layout and commit — and that is true of ordinary
`.bordered` buttons, not only styled ones, because every button installs the
press handler.

    PER TRANSITION per button: primitive 6,034.81 us   custom 6,481.41 us
    PER CLICK    per button:   primitive 12,069.62 us  custom 12,962.83 us

That is the finding worth acting on. The primitive-versus-custom question is
settled as "no difference"; the absolute cost is not settled at all and nobody
has looked at it.

**真正要緊的數字。** 每顆按鈕每次轉換約 **6 毫秒**，因此在一個有 48 顆按鈕的畫面上，一次點擊約需
**0.3 秒**的版面與提交——而且這對一般的 `.bordered` 按鈕同樣成立，不只限於套用樣式者，因為每顆按鈕
都會安裝按壓 handler。這才是值得行動的發現。「primitive 對 custom」這個問題已經定案為「沒有差異」；
而絕對成本則完全沒有定案，也還沒有人看過它。

---

## The cost is SUPERLINEAR in child count, measured 2026-09-08

The 6 ms figure above is not a constant. Re-running P52 at three button counts,
**in both ascending and descending order**, taking the minimum of the two orders
per count:

| buttons | ascending | descending | min | per button |
| --- | --- | --- | --- | --- |
| 12 | 35,679 us | 33,516 us | **33,516 us** | 2,793 us |
| 24 | 112,179 us | 92,930 us | **92,930 us** | 3,872 us |
| 48 | 278,768 us | 281,202 us | **278,768 us** | 5,808 us |

```
12 -> 24    buttons x2    time x2.77
24 -> 48    buttons x2    time x3.00
```

**Doubling the buttons roughly triples the time**, consistently across both
doublings and both orders — about `n^1.5`.

Both orders were run because this project's monotonic-drift pattern and a real
superlinearity are indistinguishable from an ascending sweep alone. They are
distinguished here: in descending order the later, smaller runs came out
*faster*, which is the opposite of drift, so drift is not the explanation.

Regenerate:

```zsh
cd testapp/output && PATH=/c/gtk4/bin:$PATH
for n in 12 24 48; do
    taskkill -f -im P52-gtk4.exe >/dev/null 2>&1   # a leftover makes the next run exit 0
    ./P52-gtk4.exe --debug --buttons=$n | grep 'PRESS primitive n='
done
```

**Kill leftovers between runs.** One survived a killed 96-button run here and
the next three invocations produced no output at all — the documented
single-instance behaviour, and it looks exactly like a broken command line.

### What this is NOT, and what the mechanism is NOT known to be

P52's arms are `VStack { ForEach rows { HStack { ForEach buttons } } }` with 8
fixed columns — **plain stacks, no `LazyVGrid`**. Doubling the button count
doubles the ROW count. So this is superlinearity in a `VStack`'s child count,
which would affect every stack in the framework, not something about buttons.

The mechanism is **not established**. `LayoutSystem.swift:288` computes
flexibility with two `computeLayout` calls per child, and nesting multiplies
that by the inner stack's own passes — but that arithmetic stays linear in the
total child count, so it does not by itself explain `n^1.5`. It carries
`environment.with(\.allowLayoutCaching, true)`, so cache behaviour degrading
with size is a candidate, and that is a guess, not a measurement.

**The next experiment is a text-only arm**: N plain `Text` views in the same
stack shape. If it shows the same curve, the cost is the stack layout and
buttons are incidental; if it does not, the cost is in `Button`.

## 成本相對於子節點數量是超線性的，2026-09-08 實測

上面的 6 毫秒不是一個常數。以三種按鈕數量重跑 P52，**升序與降序各跑一次**，每個數量取兩者的最小值：
加倍按鈕，時間大約變三倍，兩次加倍與兩種順序都一致，約為 `n^1.5`。

之所以兩種順序都跑，是因為單就升序而言，本專案的單調漂移形態與真正的超線性長得一模一樣。此處已將兩者
分開：降序時後跑的、較小的那幾次反而**更快**，方向與漂移相反，因此漂移不是解釋。

**每次執行之間要清掉殘留行程。** 此處曾有一個從被砍掉的 96 顆那次存活下來，導致其後三次呼叫完全沒有
輸出——那是有紀錄的單一實例行為，而它看起來就像指令寫錯了。

**這不是什麼，以及機制尚未確立。** P52 的每一臂是
`VStack { ForEach 列 { HStack { ForEach 按鈕 } } }`、固定 8 欄——**是純粹的 stack，沒有 `LazyVGrid`**。
加倍按鈕即加倍列數。因此這是 `VStack` 子節點數量上的超線性，會影響框架中的每一個 stack，而不是按鈕
特有的性質。機制**尚未確立**：`LayoutSystem.swift:288` 對每個子節點做兩次 `computeLayout`，巢狀時再
乘上內層 stack 自己的趟數——但那個算術對總子節點數而言仍是線性，因此它本身解釋不了 `n^1.5`。
它帶著 `allowLayoutCaching`，所以「快取行為隨規模劣化」是一個候選，而那是猜測，不是量測。

**下一個實驗是一條純 `Text` 的臂**：在相同的 stack 形狀中放 N 個純 `Text`。若它呈現相同的曲線，成本
就在 stack 版面上、按鈕只是附帶；若不同，成本就在 `Button` 裡。

---

## Method, and why each part is there

- **Interleaved**, never all-of-one-then-the-other. On this project repeated
  heavy work has made later measurements monotonically worse (1.74 -> 3.08 ->
  5.45 -> 5.99 s), which makes whichever arm ran first look faster. The
  per-round table is printed in the order taken so drift shows as a trend rather
  than being averaged into invisibility — and it IS visible here: primitive
  climbs 289,907 -> 361,138 across the ten rounds.
- **Minimum, not mean.** Single-run variance on this host has exceeded 2x.
- **Ten rounds.** Six has been dominated by an outlier before.
- **A control arm with zero buttons**, so the fixed overhead is measured rather
  than assumed.
- **CPU accumulated per phase, never per sample.** `GetProcessTimes` has a
  ~15.6 ms tick, so a per-sample CPU figure would be quantisation noise.

**方法，以及每一項的理由。** 交錯執行、取最小值而非平均、十輪、設一個零按鈕的控制臂、CPU 時間按階段
累計而非逐樣本取值。每一項都對應本專案上曾經因為缺少它而得出錯誤結論的一次量測。

---

## What this does NOT measure

- **Everything before the state write** — platform event delivery, and the
  backend press handler up to `isPressedState.wrappedValue = pressed`.
- **The toolkit's own redraw of a pressed `.bordered` button**, which happens
  inside GTK and never re-enters Swift. **This exclusion favours the primitive
  arm**, so the real gap can only be smaller than 1.07x, not larger.
- **A real click.** P52 issues the state write directly, because `isPressed` is
  `@State private` and only the backend handler writes it. The write enters the
  same machinery at the same point (`Button.swift:34` says a press is an
  ordinary state change), but a driven click plus a backend-side timestamp is
  what would close the two gaps above.
- **WinUI.** Measured on GtkBackend only.

**本量測不涵蓋的部分。** 狀態寫入之前的一切；GTK 自己對按下之 `.bordered` 按鈕的重繪（**此項排除對
primitive 臂有利**，因此真實差距只可能小於 1.07x，不可能更大）；真實的點擊；以及 WinUI。
