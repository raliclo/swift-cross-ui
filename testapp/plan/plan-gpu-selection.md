# GPU selection: `-GPU N` as a protocol-level concept

An application should be able to say which graphics adapter it wants, in one
vocabulary, on every platform — including an external GPU where the platform
has one.

應用程式應能以**一套詞彙**、在**每個平台**上表達它想要哪一張繪圖介面卡——在平台具備外接
GPU 的情況下，也包含外接 GPU。

## Status

Design. **Only the Windows half is measured**; everything about macOS, Linux,
iOS, Android and eGPU behaviour below is reasoning from documentation, not
observation. This machine has two internal adapters and no eGPU, and no Mac.
Treat any unmarked claim here as unverified.

設計文件。**只有 Windows 那一半是實測的**；以下關於 macOS、Linux、iOS、Android 與 eGPU 的
一切都是依文件推論，而非觀察所得。這台機器有兩張內建介面卡、沒有 eGPU，也沒有 Mac。此處
未標記的宣稱一律視為未經驗證。

## What is already built

`-GPU N` exists and works on GtkBackend/Windows, committed 2026-08-29:

- `DebugFeatures.gpuSelection` parses `-GPU N`, default `1`
- `0` skips Direct Composition, so GTK falls back to `GskCairoRenderer`
  (software); `1` and above request it and GTK gets `GskGLRenderer`
- `N >= 2` detects the current `UserGpuPreferences` value, prints the change and
  the adapter list, asks in the terminal, writes the registry and relaunches
- `-y` does not skip the prompt; it decides which way a **blank** answer falls,
  which is what a run with nothing on stdin gets, so `-y` is what makes it
  scriptable

Measured: prompt cancels cleanly and leaves the registry untouched; with `-y` it
writes `GpuPreference=2;` and the relaunched process reports *NVIDIA GeForce RTX
4060 Laptop GPU/PCIe/SSE2* where it previously reported *AMD Radeon(TM)
Graphics*.

## The numbering

    0   no GPU — software rendering
    1   the platform's own default        ← the default, and the fallback
    2   the first external GPU, else the highest-performance adapter
    3   the second external GPU
    n   the nth external GPU

`0` and `1` are **policies**. `2` and above are an **ordinal within a category**
— "the nth external GPU" — not an index into a raw device list.

That distinction is the whole point and is worth defending. A raw index
renumbers when hardware is plugged in or a display wakes, so `-GPU 2` would
quietly mean a different card tomorrow with nothing to notice. An ordinal
within "external GPUs" is stable while the set of external GPUs is stable, and
`0`/`1` never move at all.

`0` 與 `1` 是**政策**。`2` 以上是**某個類別內的序數**——「第 n 張外接 GPU」——而不是原始
裝置清單的索引。

這個區別正是重點所在，值得堅持。原始索引會在插拔硬體或顯示器喚醒時重新編號，於是 `-GPU 2`
明天就會悄悄指向另一張卡，而且沒有任何東西會提醒你。「外接 GPU 中的第 n 張」這個序數，在
外接 GPU 的集合不變時就保持穩定，而 `0`／`1` 則永遠不動。

### Fallback

If the requested adapter is not available, fall back to `1`. If `1` has no GPU
either, fall back to `0`. This chain is defined **once**, at protocol level, not
per backend.

若所要求的介面卡不可用，退回 `1`。若 `1` 同樣沒有 GPU，退回 `0`。這條退路只在**協定層定義
一次**，不由各 backend 各自實作。

### Reporting

When `-GPU N` is passed, print every adapter the platform can see to stdout,
with which one was selected and why. A selection that silently resolved to
something other than what was asked for is the failure mode this whole document
exists to avoid.

## Per-platform

| platform | external GPU | how a specific adapter is chosen |
|---|---|---|
| Windows / **GtkBackend** | yes, Thunderbolt, NVIDIA and AMD | **policy only** — OpenGL, see below |
| Windows / **WinUIBackend** | same hardware | **by index** — DXGI, see below |
| Linux | yes, Thunderbolt | `DRI_PRIME=n`, or `__NV_PRIME_RENDER_OFFLOAD=1` plus `__GLX_VENDOR_LIBRARY_NAME=nvidia` |
| macOS Intel | yes, AMD only | `MTLCopyAllDevices()`, filter `isRemovable == true` |
| macOS Apple Silicon | **no — Apple does not support it** | single unified GPU; every policy resolves to it |
| iOS / Android | no today | single GPU; see the note below |

### The conflict is GTK's, not Windows'

**Corrected 2026-08-29.** This section first said "Windows cannot express the
nth external GPU". That is too broad and was wrong: it is true of GtkBackend and
false of WinUIBackend, on the same machine and the same cards. The original
wording is kept here because a limitation attributed to the wrong layer is
exactly the kind of claim that gets designed around unnecessarily.

**GtkBackend — policy only, and this part stands.** GTK renders through OpenGL,
and Windows selects an OpenGL adapter by policy: `UserGpuPreferences` takes
exactly three values (0 unspecified, 1 power saving, 2 high performance), and a
WGL context has no per-adapter selection. So `-GPU 2` maps to *high
performance*, which is what an attached eGPU resolves to, and **`-GPU 3` and
above cannot be honoured** — they clamp to 2. Implemented, and it says so in a
banner on stderr rather than quietly doing something else.

**WinUIBackend — by index, and this is why the limit is not Windows'.** WinUI
renders through DirectX, where `IDXGIFactory1::EnumAdapters1` gives a real index
and `D3D11CreateDevice` takes an explicit adapter as its first argument. Both
are already called in this repo, in
`Sources/WinUIBackend/D3D11VideoInterop.swift` — `EnumAdapters1` around line 789
to build adapter descriptions, and `D3D11CreateDevice` around line 281 passing
`nil` for the adapter today, which is "let the system choose". Passing a chosen
adapter there is the whole change.

So the two Windows backends do **not** work the same way, and the numbering fits
WinUI better than it fits GTK. Neither needs a different `-GPU` vocabulary; they
need different implementations behind it, which is the argument for the protocol
in the first place.

**此限制屬於 GTK，而非 Windows。2026-08-29 修正。** 本節原本寫「Windows 無法表達第 n 張外接
GPU」——**寫得太寬，而且是錯的**：這對 GtkBackend 成立，對 WinUIBackend 不成立，而且是在同一台
機器、同一批介面卡上。原文保留於此，因為「把限制歸咎到錯誤的層級」正是那種會讓人繞著它做出
不必要設計的宣稱。

**GtkBackend——僅限政策，這部分依然成立。** GTK 透過 OpenGL 繪製，而 Windows 是以政策選擇
OpenGL 介面卡：`UserGpuPreferences` 只接受三個值，WGL context 也沒有逐一介面卡的選擇機制。
因此 `-GPU 3` 以上**無法被遵從**，會夾到 2，並以 stderr 橫幅明說，而不是安靜地做別的事。

**WinUIBackend——可依索引選取，這正是「限制不屬於 Windows」的證據。** WinUI 透過 DirectX
繪製，其中 `IDXGIFactory1::EnumAdapters1` 提供真正的索引，而 `D3D11CreateDevice` 的第一個參數
可接受明確指定的 adapter。這兩者在本 repo 中**都已經被呼叫**，位於
`Sources/WinUIBackend/D3D11VideoInterop.swift`：`EnumAdapters1` 在約 789 行用來建立介面卡描述，
`D3D11CreateDevice` 在約 281 行、目前 adapter 傳入 `nil`，亦即「交給系統決定」。把選定的
adapter 傳進去，就是全部的改動。

### macOS

`1` means the default Metal device. `2` means the first `isRemovable` device,
`3` the second, and so on — which is exactly the ordinal above, and macOS is the
platform where it maps most cleanly, because Metal enumerates devices at
runtime.

macOS is also **easier** than Windows and the design must not copy the Windows
shape: device selection is a runtime choice made when the renderer is created.
No registry, no confirmation, no relaunch. The detect/confirm/write/restart
sequence in `GtkBackend` is a workaround for a Windows constraint — the adapter
is fixed at process creation — and belongs to that platform only.

### iOS and Android, for later

Neither supports an external GPU today. USB4 Version 2.0 (there is no "USB5")
and Thunderbolt 4/5 on newer devices make it conceivable rather than possible.
If it ever arrives, the numbering above already covers it without change: the
external GPUs are enumerated and `2` is the first of them.

Worth stating plainly: this is not a reason to build anything for those
platforms now. They conform and decline, and the ordinal is reserved.

## Shape: what belongs at protocol level

The point of lifting this is that the **rules** are shared and only the
**lookup** is not.

    SwiftCrossUI  (protocol level — one implementation, shared by everyone)
        GraphicsAdapter          name, isRemovable, isLowPower, identifier
        GraphicsAdapterSelection the number and what it means
        resolution + fallback    N -> adapter, with the 1 then 0 chain
        reporting                printing the list and the choice

    BackendFeatures.GraphicsAdapters  (what a backend must actually provide)
        var availableAdapters: [GraphicsAdapter]
        func apply(_ adapter: GraphicsAdapter) -> Outcome
             // .applied / .needsRestart(reason) / .unavailable(reason)
        var adapterRemoved: (() -> Void)?

`needsRestart` exists so that "Windows must relaunch, macOS must not" is a
difference the **protocol can express**, rather than logic buried in one
backend. It gets a second witness as soon as WinUIBackend conforms, which uses
the identical registry mechanism.

`adapterRemoved` is the one thing an external GPU adds that nothing else does:
it can be unplugged mid-run. All three desktop platforms have this and each
signals it differently — macOS device-removal notifications and
`Info.plist GPUEjectPolicy`, Windows `WM_DEVICECHANGE` and
`DXGI_ERROR_DEVICE_REMOVED`, Linux udev/DRM hotplug.

**This is the reason not to defer the protocol.** Selection can be retrofitted;
removal cannot, because a renderer written to assume a permanent device has to
be rewritten rather than extended.

`adapterRemoved` 是外接 GPU 帶進來、其他情況都沒有的唯一新問題：它可能在執行途中被拔掉。
三個桌面平台都有這件事，而各自的訊號不同。**這正是不該延後定義協定的理由**：選擇機制可以
事後補上，移除機制不行——一個假設裝置永久存在的 renderer，之後只能重寫，不能擴充。

## Order of work

1. Move the policy type out of `DebugFeatures` into `SwiftCrossUI`.
   `DebugFeatures` keeps only the argv parsing of `-GPU N` and `-y`, which is
   its job and which must vanish in a release build.
2. Define `BackendFeatures.GraphicsAdapters`, including `adapterRemoved`.
3. `GtkBackend` conforms — move the existing Windows code behind it. Every other
   backend conforms and declines, which is the safe shape here because
   `@CastBackend` turns a *missing* conformance into `fatalError`.
4. `WinUIBackend` conforms, using the same registry mechanism. This is what
   gives `needsRestart` its second witness and pays for the abstraction.
5. Sweep P6-v2 across every available adapter and record dropped frames at
   4K/60, on GTK, Windows and WSL. That is the first real workload behind this
   API, and the first evidence that the choice changes anything measurable.

## Blocker to clear first

**A new `.swift` file under `Sources/` is not picked up by
`testapp/compile.zsh`.** Measured 2026-08-29: a file containing nothing but
`#error` was added to `Sources/GtkBackend/`, the build completed in 5.25s
without recompiling anything and without reporting the error. Touching
`Package.swift` to force a re-plan did not help. The identical code compiled
first time once it was moved into an existing file.

Cause unknown, and recorded as unknown. Since steps 1–3 above all want new
files, this has to be understood before starting, or the work has to be written
into existing files. The cheap check for anyone hitting it: put a temporary
`#error` in the new file **while the rest of the tree compiles cleanly**, and
see whether it fires.

**`Sources/` 下新增的 `.swift` 檔不會被 `testapp/compile.zsh` 納入建置。** 2026-08-29 實測：
在 `Sources/GtkBackend/` 放入一個只含 `#error` 的檔案，建置在 5.25 秒內完成、未重新編譯任何
東西、也未回報該錯誤。`touch Package.swift` 強制重新規劃亦無效。同樣的程式碼搬進既有檔案後
一次就編譯成功。

成因未知，且照實記為未知。由於上述步驟 1–3 都需要新檔案，開工前必須先弄清楚這件事，否則就得
把程式碼寫進既有檔案。給遇到此問題者的便宜檢查法：**在整棵樹都能乾淨編譯的前提下**，在新檔案
中放一個暫時的 `#error`，看它會不會觸發。
