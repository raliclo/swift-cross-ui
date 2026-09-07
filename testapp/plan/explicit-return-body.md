# A `body` written with an explicit `return` renders nothing

Found 2026-09-08 while adding a readout to P48. **Fixed the same day**, in
`Sources/SwiftCrossUI/Views/View.swift`. The reproduction is kept because the
symptom is unrecognisable from the cause, and because P48 now carries the
explicit-return shape on purpose as the regression test.

發現於 2026-09-08,當時正在為 P48 加上一行讀數。**同日已修復**,位於
`Sources/SwiftCrossUI/Views/View.swift`。此處保留重現方式,因為由症狀完全認不出成因;也因為 P48 現在
刻意保留了「顯式 return」那個形狀,作為回歸測試。

## The reproduction

Both of these are `View` conformances in an application module. The first draws
nothing at all. The second draws.

```swift
struct A: View {
    var body: some View {
        let n = 7
        return Text("MINIMAL n=\(n)")     // nothing appears
    }
}

struct B: View {
    var body: some View {
        Text("READOUT MARKER")            // appears
    }
}
```

Verified by screenshot, at the same position in the same parent `VStack`, in
consecutive builds of `testapp/P48.swift`.

## What it is not

- **Not the environment.** The first version of this had
  `@Environment(\.self)` and called `Color.resolve(in:)`. Removing both and
  reducing to `let n = 7` keeps the failure.
- **Not a body that never runs.** Instrumented with a write to stderr: the body
  is entered 28 times over one launch and the values it computes are correct.
  `resolved 0.85 0.45 0.2` was printed while the screen showed nothing.
- **Not a layout collapse further up.** `B` renders at exactly the position
  where `A` renders nothing, in the same parent, one build apart.
- **Not a compile error, a warning, or a runtime message.** Nothing is reported
  anywhere.

## The cause

`View`'s default implementations disagreed with each other about what
`children` is.

`defaultChildren(backend:snapshots:environment:)` asks `body` for its children.
`defaultAsWidget`, `defaultComputeLayout` and `defaultCommit` then wrapped `body`
in a `VStack` and handed it those same children. That works when the builder ran,
because `Content` is then a `TupleViewN` and the children are
`TupleViewChildren`, which is what a `VStack` expects.

With an explicit `return`, `Content` is the returned view itself. `Text` is an
`ElementaryView`, whose `Content` is `EmptyView`, so the children are
`EmptyViewChildren` -- and the `VStack` wrapping them found no layoutable
children at all. It laid out zero children, reported zero size, and drew
nothing.

The fix is to route through `VStack` only when the children are
`TupleViewChildren`, and to delegate straight to `body` otherwise.

**`EmptyViewChildren` had to be on the delegating side, and getting that wrong
was the first attempt.** Treating it as builder-produced looks right -- an empty
builder body does produce it -- and changed nothing, because it is exactly the
case that breaks. Delegating is correct for a genuinely empty body too: an
`EmptyView` draws nothing either way.

## 成因

`View` 的各個預設實作彼此對「`children` 是什麼」沒有共識。

`defaultChildren(backend:snapshots:environment:)` 是向 `body` 索取其 children 的。而
`defaultAsWidget`、`defaultComputeLayout` 與 `defaultCommit` 接著把 `body` 包進一個 `VStack`,再把
同一份 children 交給它。當 builder 執行過時這是可行的,因為此時 `Content` 是某個 `TupleViewN`、
children 是 `TupleViewChildren`,而那正是 `VStack` 所預期的。

一旦使用顯式 `return`,`Content` 就是所回傳的 view 本身。`Text` 是 `ElementaryView`、其 `Content` 為
`EmptyView`,因此 children 是 `EmptyViewChildren`——而包住它們的那個 `VStack` 一個可佈局的子節點都
找不到。它排列了零個子節點、回報零尺寸、什麼都沒畫。

修法是:只有在 children 為 `TupleViewChildren` 時才繞道 `VStack`,其餘一律直接委派給 `body`。

**`EmptyViewChildren` 必須被歸在「委派」那一側,而把它弄反正是第一次嘗試的錯誤。** 把它當成
builder 產生的看起來很合理——一個空白的 builder body 確實會產生它——而那次改動什麼都沒有改變,因為
那恰恰就是會壞掉的那一種。對於真正空白的 body,委派同樣是對的:`EmptyView` 無論走哪一條路都不會畫
出任何東西。

## The hypothesis this replaced, kept because it was close but not actionable

`View` declares `@ViewBuilder var body: Body { get }`. An explicit `return`
opts out of the builder, so `Body` becomes the returned type itself -- `Text` --
rather than the `TupleView1<Text>` the builder would have produced. A custom
view whose `Body` is a leaf view directly is the case that differs, and it is
the case that fails.

That is a hypothesis from the shapes of the two, not a diagnosis. The next step
is to check whether `return VStack { Text("x") }` renders, which would put the
boundary at "leaf `Body`" rather than at "explicit `return`".

`View` 宣告的是 `@ViewBuilder var body: Body { get }`。顯式的 `return` 會跳出 builder，於是 `Body`
成為回傳型別本身——`Text`——而不是 builder 原本會產生的 `TupleView1<Text>`。「`Body` 直接是一個 leaf
view」的自訂 view 正是兩者相異之處，也正是失敗的那一個。

這是從兩者的形狀推出的假設，不是診斷。下一步是檢查 `return VStack { Text("x") }` 會不會畫出來——
若會，界線就在「leaf 的 `Body`」而不是在「顯式 `return`」。

## Why it matters more than its size suggests

An explicit `return` in a `body` is ordinary Swift and is what anyone writes the
moment a body needs a local. It compiles, it runs, and the view is absent, so
the author's next move is to look at the layout, the parent, or the data -- none
of which is wrong. Four rounds went into this one before the shape of it was
clear, and the last two were spent ruling out an environment that had nothing to
do with it.

在 `body` 中使用顯式 `return` 是再普通不過的 Swift，也是任何人「body 需要一個區域變數」時的第一個
寫法。它編得過、跑得動，而 view 不見了——於是作者的下一步會是去看版面、看父層、看資料，而那三者
都沒有錯。這一個花了四輪才看清形狀，其中最後兩輪是在排除一個與它毫無關係的 environment。

## The regression test

`testapp/P48.swift`'s `ColorPickerReadout` is written with an explicit `return`
on purpose. If the fix is ever undone, that one line disappears from P48 and
nothing else changes -- which is why the comment there says so.

Checked for collateral damage by capturing P46 and P47 before and after the
change: both are pixel-identical. That covers the case where `Content` IS a
`TupleView`, which is every view in the tree that was already working; it does
not amount to having run all forty-eight apps.

## 回歸測試

`testapp/P48.swift` 的 `ColorPickerReadout` **刻意**以顯式 `return` 撰寫。若該修正日後被還原,P48 中
就只有那一行會消失,其他一切都不會改變——這也是那裡的註解如此寫明的原因。

附帶損害的檢查方式是:在改動前後各擷取 P46 與 P47,兩者皆逐像素相同。那涵蓋了「`Content` 確實是
`TupleView`」的情況——也就是本樹中原本就能運作的每一個 view——但這並不等於把四十八支 app 全部跑過。
