# DebugFeatures

One switch that decides whether a binary can be debugged and driven at all.

`SCUI_DEBUG=1` at build time compiles in the `--debug` flag, the diagnostic
messages, and action-file replay. Without it none of those exist in the
binary — not disabled at runtime, **absent**.

一個開關，決定某個執行檔究竟能否被除錯與驅動。

建置時的 `SCUI_DEBUG=1` 會將 `--debug` 旗標、診斷訊息，以及動作檔重放編入執行檔。若未設定，這些
東西在該執行檔中都不存在——不是執行期被停用，而是**根本不存在**。

## Why absent rather than disabled

Two reasons, and the second is the one that matters.

**Size.** A release build stops carrying the flag parsing, the message
formatting, and — because the manifest drops the dependency, not just the
code — the whole `InputEvent` module.

**A shipped application should not be able to drive its own interface.** Action
files exist to make a test reproducible. In a release binary the same machinery
is a way to synthesise clicks and keystrokes into whatever window happens to be
in front. Leaving it in and hoping nobody passes `-actionfile` is not the same
as it not being there.

## 為何是「不存在」而非「已停用」

兩個理由，而第二個才是關鍵。

**體積。** release 建置不再攜帶旗標解析、訊息格式化，以及——因為 manifest 連依賴本身都一併移除，
而不只是移除程式碼——整個 `InputEvent` 模組。

**已出貨的應用程式不應該有能力驅動自己的介面。** 動作檔存在的目的是讓測試可重現；但在 release
執行檔中，同一套機制就是「向當下位於前方的任何視窗合成點擊與按鍵」的手段。把它留著、然後指望沒有
人去傳 `-actionfile`，與「它根本不在那裡」並不是同一回事。

## Building

```zsh
SCUI_DEBUG=1 swift build        # the flags exist
swift build                     # they do not
```

`testapp/compile.zsh` passes it through, so:

```zsh
SCUI_DEBUG=1 zsh testapp/compile.zsh P26    # -debug and -actionfile work
zsh testapp/compile.zsh P26                 # neither is recognised
```

## API

```swift
import DebugFeatures

DebugFeatures.isCompiledIn        // was this binary built with SCUI_DEBUG
DebugFeatures.isEnabled           // ...and was --debug passed to this run
DebugFeatures.supportsActionFiles // can this binary replay input at all

DebugFeatures.log("frame \(index) took \(duration)ms")
DebugFeatures.value(after: "-url")
DebugFeatures.flagSummary         // for a --help listing
```

`isCompiledIn` and `isEnabled` answer different questions and are easy to
confuse. `isCompiledIn` is about the **binary**: can it debug at all.
`isEnabled` is about **this run**: was `--debug` passed. A release binary
returns `false` from both, and `isEnabled` never looks at the command line
because there is nothing for the flag to switch on.

`log` takes its message as an `@autoclosure`, so a release build does not pay
to build a string nothing will print. That matters in a loop, where a
diagnostic interpolating a description costs the description on every
iteration even when the output is discarded.

`isCompiledIn` 與 `isEnabled` 回答的是不同問題，且容易混淆。`isCompiledIn` 關乎**執行檔**：它究竟
能否除錯。`isEnabled` 關乎**這一次執行**：是否傳入了 `--debug`。release 執行檔兩者皆回傳 `false`，
而 `isEnabled` 根本不會去查看命令列，因為該旗標沒有任何東西可以開啟。

`log` 以 `@autoclosure` 接收訊息，因此 release 建置不會為了一個不會被印出的字串付出建構成本。這在
迴圈中尤其重要——一則會插值物件描述的診斷訊息，即使輸出被丟棄，每次迭代仍會付出建構描述的代價。

## What is gated on it

| | with `SCUI_DEBUG` | without |
|---|---|---|
| `--debug` | recognised | not recognised |
| `-actionfile <path>` | replays the file | not recognised |
| `DebugFeatures.log` | writes to stderr | compiled out |
| `InputEvent` module | linked | not a dependency |

The last row is the reason this lives in the package manifest rather than
being a plain `#if`. SwiftPM cannot make a *target* conditional, but the
manifest is Swift: the dependency list is built from the environment, so
`InputEvent` is not merely unused in a release build, it is not there.

最後一列正是「此機制必須位於 package manifest 中、而非只是一個 `#if`」的理由。SwiftPM 無法讓
*target* 帶條件，但 manifest 本身就是 Swift：依賴清單由環境變數建構而成，因此在 release 建置中，
`InputEvent` 不只是未被使用，而是根本不存在。

## Forcing a backend

`SCUI_FORCE_BACKEND` does not exist, and does not need to:
**`SCUI_DEFAULT_BACKEND` already forces one, on any platform.**

```swift
// Package.swift
if let backend = env["SCUI_DEFAULT_BACKEND"] {
    defaultBackendDependencies = [.target(name: backend)]   // no platform condition
}
```

There is no `.when(platforms:)` on that line, so naming a backend overrides the
per-platform defaults entirely. That is how `testapp/compile.zsh -gtk4` runs
GtkBackend on Windows today:

```zsh
SCUI_DEFAULT_BACKEND=GtkBackend swift build     # Gtk, wherever you are
SCUI_DEFAULT_BACKEND=WinUIBackend swift build
```

A second variable meaning the same thing was considered and not added. Two
names for one switch is a maintenance trap: they drift, and the one someone
reads is not always the one the build honoured.

**`DebugFeatures.summary` does not report the backend**, and cannot.
`SCUI_DEFAULT_BACKEND` is read when the *manifest* is evaluated, and nothing
carries the name into the compiled code. An application knows its own backend —
print `String(describing: DefaultBackend.self)` beside the summary.

`SCUI_FORCE_BACKEND` 並不存在，也不需要存在：**`SCUI_DEFAULT_BACKEND` 本身就是強制的，且適用於
任何平台。**

該行（如上）沒有 `.when(platforms:)`，因此指名一個 backend 會完全覆寫各平台的預設值。
`testapp/compile.zsh -gtk4` 今天讓 GtkBackend 跑在 Windows 上，用的正是這個機制。

曾考慮新增一個意義相同的第二個變數，最後未採用。同一個開關有兩個名字是維護上的陷阱：它們會逐漸
分歧，而某人讀到的那一個，未必就是建置實際採用的那一個。

**`DebugFeatures.summary` 不會回報 backend**，而且也無從回報。`SCUI_DEFAULT_BACKEND` 是在評估
*manifest* 時讀取的，沒有任何東西把該名稱帶進編譯後的程式碼。應用程式知道自己的 backend——請在
summary 旁自行印出 `String(describing: DefaultBackend.self)`。

## Related

- `Sources/InputEvent/README.md` — the action file format
- `Sources/GtkBackend/ActionFileReplay.swift` — where `-actionfile` is handled
