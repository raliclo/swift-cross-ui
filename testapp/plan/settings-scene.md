# A `Settings` scene cannot be built on `Window`

Task #35's last item. **Attempted 2026-09-08 and withdrawn before shipping**,
because the obvious construction is silently inert on two of the five backends.
This records why, so the next attempt starts from the finding rather than from
the same design.

任務 #35 的最後一項。**2026-09-08 嘗試過,並在出貨之前撤回**,因為那個顯而易見的做法在五個 backend
中的兩個上是靜默失效的。此處記錄其原因,好讓下一次嘗試從這項發現開始,而不是從同一個設計開始。

## What was built, and why it looked right

`Settings<Content>` wrapping a `Window` with a reserved id
(`dev.swiftcrossui.settings`), a `SettingsNode` delegating to `WindowNode`, and
an `openSettings` action on the environment. It needs nothing from any backend,
it compiles, and on macOS, GTK and WinUI it does exactly what SwiftUI's does
minus the menu item.

## Why it was withdrawn

`OpenWindowAction.callAsFunction(id:)` opens with:

```swift
guard environment.backend.supportsMultipleWindows else {
    logger.warning("openWindow(id:) called but the backend doesn't support multi-window, ignoring")
    return
}
```

and:

| backend | `supportsMultipleWindows` |
| --- | --- |
| AppKitBackend | true |
| GtkBackend | true |
| WinUIBackend | true |
| **UIKitBackend** | **false** |
| **AndroidBackend** | **false** |

So on iOS and Android `openSettings` logs a line and returns. The settings
window never appears, the caller is not told, and the application looks like it
ignored the button. That is "supported everywhere except X", which this
repository's rules do not allow on these five, and it is the exact shape the
symbol work spent the day avoiding.

因此在 iOS 與 Android 上,`openSettings` 只會記下一行然後返回。設定視窗不會出現、呼叫端不會被告知,
而應用程式看起來就像忽略了那個按鈕。那就是「除了 X 之外都支援」,本 repo 的規則不允許它出現在這五個
backend 上,而它正是符號那批工作花了一整天在避免的形狀。

## What it actually needs

A presentation, not a window. Where the platform has windows, a window; where
it does not, whatever that platform uses instead -- which on iOS and Android is
a modal presentation over the root, not a second window.

That is the same machinery `.popover` and `.fullScreenCover` need, and those are
task #36. **So #35's last item is blocked behind #36 rather than being a small
job of its own**, and doing #36 first makes this one a thin wrapper over it.

它需要的是一種**呈現**,而不是一個視窗。平台有視窗的地方就用視窗;沒有的地方就用該平台實際使用的
東西——在 iOS 與 Android 上那是覆蓋在根視圖之上的 modal 呈現,不是第二個視窗。

那與 `.popover` 及 `.fullScreenCover` 所需的機制相同,而那些屬於任務 #36。**因此 #35 的最後一項是卡在
#36 之後,而不是一件自己的小工作**;先做 #36 會讓這一項變成它之上的一層薄包裝。

## What is worth keeping from the attempt

The reserved id and the `openSettings` shape are right and cost nothing to
rebuild. What was wrong was the assumption that a scene is a window on every
platform, and that assumption is checkable in one grep --
`grep -rn supportsMultipleWindows Sources/*/` answers it in a second and would
have answered it before the code was written.

這次嘗試中值得保留的,是那個保留的 id 與 `openSettings` 的形狀——兩者都是對的,重建的成本也是零。
錯的是「scene 在每個平台上都是一個視窗」這個假設,而該假設一個 grep 就能查證:
`grep -rn supportsMultipleWindows Sources/*/` 一秒內就會回答它,而它本可以在程式碼寫下之前就回答。
