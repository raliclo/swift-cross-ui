# A `body` written with an explicit `return` renders nothing

Found 2026-09-08 while adding a readout to P48. **Not yet fixed** -- this
records the reproduction and what was ruled out, so that whoever fixes it does
not start from the symptom.

發現於 2026-09-08，當時正在為 P48 加上一行讀數。**尚未修復**——本文件記錄的是重現方式與已被排除的
可能,好讓動手修的人不必從症狀開始。

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

## The likely mechanism, unverified

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

## Workaround in the tree today

`testapp/P48.swift`'s `ColorPickerReadout` computes inline in a single
expression. It is uglier and it repeats `resolve(in:)` three times; that is the
cost of the workaround and it should go away when this is fixed.

本樹目前的替代寫法：`testapp/P48.swift` 的 `ColorPickerReadout` 以單一運算式就地計算。它比較醜、而且
把 `resolve(in:)` 重複了三次;那就是這個替代寫法的代價,而它應在本問題修復後移除。
