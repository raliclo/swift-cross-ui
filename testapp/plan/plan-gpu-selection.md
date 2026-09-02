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
- **Corrected 2026-09-02.** The next two lines used to read: "`0` skips Direct
  Composition, so GTK falls back to `GskCairoRenderer` (software); `1` and above
  request it and GTK gets `GskGLRenderer`." That describes a threshold the code
  has not used for some time. `GtkBackend.swift` reads `gpuSelection >= 2`, so
  the DEFAULT of `1` does **not** request Direct Composition -- it is off unless
  asked for. A reader following this plan would have expected a hardware
  renderer out of the box and found Cairo.
- **2026-09-02 更正。** 下面兩行原本寫著：「`0` 會跳過 Direct Composition，因此 GTK 退回
  `GskCairoRenderer`（軟體）；`1` 以上會要求它，GTK 便得到 `GskGLRenderer`。」那描述的是程式碼
  已有一段時間不再使用的門檻。`GtkBackend.swift` 讀的是 `gpuSelection >= 2`，因此預設值 `1`
  **不會**要求 Direct Composition——除非明確要求，否則它是關閉的。依此計畫閱讀的人，會預期開箱
  即得硬體 renderer，實際拿到的卻是 Cairo。
- `0` and `1` both skip Direct Composition, so GTK falls back to `GskCairoRenderer`
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

**As built, abf49d12** — three differences from the sketch, all deliberate:

    SwiftCrossUI  (the rules — one implementation, shared by everyone)
        GraphicsAdapter            name, isRemovable, isLowPower
        GraphicsAdapterSelection   .software / .systemDefault
                                   / .external(ordinal:) + init(number:)
        resolve(among:)            the fallback chain, defined once
        GraphicsAdapterResolution  requested, resolved, adapter, fellBackBecause

    BackendFeatures.GraphicsAdapters  (only what a backend alone can answer)
        var availableAdapters: [GraphicsAdapter]
        func applyAdapter(_ resolution: GraphicsAdapterResolution) -> AdapterOutcome
        var adapterRemoved: (() -> Void)?

    AdapterOutcome
        .applied / .alreadyActive / .needsRestart(reason:) / .unavailable(reason:)

1. **`applyAdapter` takes the resolution, not the adapter.** The backend sees
   what was *asked for* beside what it resolved to, so it can report a
   substitution instead of only acting on the result.
2. **`GraphicsAdapterResolution` was not in the sketch and carries
   `fellBackBecause`.** A caller cannot print the answer without also having the
   reason it is not what was requested — which is the failure this whole feature
   exists to prevent, made structurally hard rather than merely discouraged.
3. **No `identifier`.** The sketch had one; nothing needed it, and an unused
   field invites someone to key selection off it — which is the index-based
   numbering this design rejects. Add it when something actually requires it.

**依實作，abf49d12** —— 與草圖有三處差異，皆為刻意：

1. **`applyAdapter` 收的是 resolution，而非 adapter。** backend 能同時看到「使用者要求什麼」與
   「解析成什麼」，因此它能回報一次替換，而不只是對結果採取行動。
2. **`GraphicsAdapterResolution` 不在草圖中，且帶有 `fellBackBecause`。** 呼叫端不可能在「印出
   答案」的同時、手上卻沒有「這不是使用者所要求的」之理由——而那正是整個功能所要防止的失敗，
   此處讓它在結構上難以發生，而不只是「不鼓勵」。
3. **沒有 `identifier`。** 草圖裡有，但沒有任何東西需要它；而一個沒人用的欄位會誘使人以它為鍵
   來做選擇——那正是本設計所拒絕的「索引式編號」。等到真的有東西需要它時再加。

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

**Read the status honestly: 2 is done, 1 and 3 are half done, and the half that
is missing is the half that matters.** The protocol is defined, `GtkBackend`
conforms, and it all compiles — but **nothing calls it**. `applyAdapter` and
`availableAdapters` have no callers, and the `-GPU` flow still reads
`DebugFeatures.gpuSelection` as a raw `Int` in two places
(`GtkBackend.swift:329` and `:695`). So the flag works, the protocol works, and
they are not connected to each other.

That is exactly the shape of defect this project keeps finding — something that
compiles, conforms and looks finished while the wire is missing — so it is
written here rather than reported as complete.

**狀態請照實讀：第 2 項完成，第 1 與第 3 項只做了一半，而缺的那一半正是關鍵的那一半。**
協定已定義、`GtkBackend` 已 conform、全部編譯通過——但**沒有任何東西呼叫它**。`applyAdapter`
與 `availableAdapters` 沒有呼叫端，而 `-GPU` 的流程仍在兩處直接讀取原始的
`DebugFeatures.gpuSelection`（`GtkBackend.swift:329` 與 `:695`）。也就是說：旗標能用、協定能用，
而兩者尚未接在一起。

這正是本專案一再發現的那種缺陷形狀——編得過、conform 了、看起來完成了，但線沒接上——因此在此
寫明，而非回報為已完成。

1. **PARTIAL.** `GraphicsAdapterSelection` exists in `SwiftCrossUI` with
   `init(number:)`. `DebugFeatures.gpuSelection` still returns a raw `Int` and
   is still what the backend reads. Parsing `-GPU N` and `-y` from argv belongs
   in `DebugFeatures` and should stay there; *interpreting* the number should
   not.
2. **DONE.** `BackendFeatures.GraphicsAdapters`, with `adapterRemoved`.
3. **PARTIAL.** `GtkBackend` conforms and reports its adapters and outcomes
   correctly, but `ensureGpuPreference` still does the work directly instead of
   going through `applyAdapter`. Other backends do not conform yet, which will
   `fatalError` under `@CastBackend` the moment anything does call it — so the
   wiring in 3b must land together with their conformances.
3b. **Wire it up.** `-GPU N` → `GraphicsAdapterSelection(number:)` →
   `resolve(among: backend.availableAdapters)` → `backend.applyAdapter(_:)`,
   and let the shared reporting print `requested` beside `resolved`. This is
   what makes the protocol load-bearing rather than decorative, and it is the
   step that will show whether the shape is right.
4. `WinUIBackend` conforms, using the same registry mechanism. This is what
   gives `needsRestart` its second witness and pays for the abstraction.
5. Sweep P6-v2 across every available adapter and record dropped frames at
   4K/60, on GTK, Windows and WSL. That is the first real workload behind this
   API, and the first evidence that the choice changes anything measurable.

## Blocker — CLEARED 2026-08-29

A new `.swift` file under `Sources/` was not picked up by
`testapp/compile.zsh`. **Fixed**; steps 1–3 are unblocked.

**Cause.** llbuild bakes the source file list into `.build/debug.yaml` when it
plans a build. A later build whose inputs are all unchanged reuses that plan, so
an added file belongs to no compile command and is skipped — no error, no
warning, and a build finishing in seconds looking successful. Editing an
existing file works fine, which is why it went unnoticed.

**Fix.** `compile.zsh` now hashes the *list* of source paths (not their
contents — content changes are what llbuild already tracks) and drops
`debug.yaml` when the list differs. Costs nothing on ordinary builds: measured
31.94s when the list changed and 4.17s / 4.48s when it did not.

**Two of the diagnostics along the way were wrong, and both are worth keeping.**
"Deleting debug.yaml did not help" was false — it deleted the one in
`testapp/.compile-work`, while `-gtk4` builds in `testapp/.compile-work-gtk4`.
There are three work directories, one per backend, and `.gitignore` says so.
The first `#error` probe was also invalid, because another compile error was
already present and may have stopped type-checking before reaching it.

**阻擋已於 2026-08-29 排除。**

**成因。** llbuild 在規劃建置時把原始檔清單烘焙進 `.build/debug.yaml`；之後只要輸入皆未改變就
重複使用該計畫，於是新增的檔案不屬於任何編譯指令而被略過——沒有錯誤、沒有警告，建置數秒完成
且看似成功。修改既有檔案則一切正常，這正是它長期未被察覺的原因。

**修法。** `compile.zsh` 現在會雜湊原始檔路徑「清單」（而非內容——內容變更本來就由 llbuild
正確追蹤），清單一有差異就刪除 `debug.yaml`。對一般建置零成本：清單變更時實測 31.94 秒，
未變更時為 4.17 / 4.48 秒。

**過程中有兩項診斷是錯的，而且都值得留著。**「刪掉 debug.yaml 沒有用」是假的——當時刪的是
`testapp/.compile-work` 裡的那一個，而 `-gtk4` 建置實際使用的是 `testapp/.compile-work-gtk4`。
工作目錄一共有三個、每個 backend 各一，而 `.gitignore` 裡就寫著這件事。第一次的 `#error` 探針
同樣無效，因為當時樹上已有另一個編譯錯誤，可能在到達該檔案之前就停止了型別檢查。

## Review 2026-08-29

Two harness defects were found while reviewing the uncommitted GPU work:

1. `gpu_flag_test.zsh` claimed to prove that `-GPU 5` did not write
   `GpuPreference=5`, but it used an empty expected string with the shared
   "contains" helper. That assertion always passed. The test now has a separate
   negative assertion helper and fails if the forbidden text appears.
2. The same script hardcoded the registry value name to this checkout's
   `P40.exe` path. The test now derives the Windows path from `testapp/output`,
   so it checks the executable it actually launched.

These are harness fixes, not backend fixes. The backend-side policy change
remains: `-GPU 1` means the platform default, while `-GPU 2` is the explicit
request for Direct Composition / hardware rendering on Windows GTK.

`testapp/wincap.swift` is now wired into `screenshot.zsh` as the only
Windows/WSLg `-w` window-capture path. With `-w`, the flow is wincap /
`PrintWindow(PW_RENDERFULLCONTENT)` only, and the command fails closed if that
capture fails. Desktop capture remains available only by omitting `-w`. The
helper is built on demand into `testapp/helper/bin/wincap.exe`, checks for a
non-black BMP, and the script converts that BMP to the same PNG output format
as the rest of the screenshot flow.

P40 is a rendering-geometric-effects test, not a layout-geometry test. It can
settle whether transformed samples render as real content or hotpink fallback;
it does not settle P7/#556 split-view pane ratios.

Measured 2026-08-29 with PIL before calling the P40 capture passed:

- `p40-wincap-20260829-181107.png`: 928x743; hotpink exact 0, hotpink near 0.
  Seven blue tile bodies were detected, each 90x58; seven orange anchors were
  detected, each 14x80.
- `p40-wincap-default-20260829-181425.png`: same size and same component
  geometry; hotpink exact 0, hotpink near 0.

Capture timing on the same default P40 window:

- `screenshot.zsh -w` through wincap: 1000 ms.
- The old direct `ffmpeg -f gdigrab -i title=...` method: 3215 ms.

On the DComp run, wincap captured the `WS_EX_NOREDIRECTIONBITMAP` window
directly with 93.0% non-black pixels. A desktop capture took similar wall time
in that one run, but photographed a foreground terminal over the app, so it was
not valid evidence for the named window.

## Review 2026-08-29（中文）

Review 未提交 GPU 工作時發現兩個測試 harness 缺陷：

1. `gpu_flag_test.zsh` 宣稱能證明 `-GPU 5` 沒有寫入 `GpuPreference=5`，
   但它把空字串交給共用的「contains」檢查函式。任何字串都包含空字串，因此該斷言永遠通過。
   現在已改成獨立的 negative assertion helper；只要 forbidden text 出現就會失敗。
2. 同一支腳本把 registry value name 寫死為此 checkout 的 `P40.exe` 路徑。
   現在改由 `testapp/output` 動態產生 Windows path，因此會檢查實際啟動的那支 executable。

這些是 harness 修正，不是 backend 修正。Backend 端政策仍維持目前結論：`-GPU 1` 代表平台預設，
`-GPU 2` 才是 Windows GTK 上明確要求 Direct Composition / hardware rendering。

`testapp/wincap.swift` 現已接進 `screenshot.zsh`，作為 Windows/WSLg 唯一的 `-w` 視窗擷取路徑。
指定 `-w` 時只會走 wincap / `PrintWindow(PW_RENDERFULLCONTENT)`，若擷取失敗則 fail closed。
桌面擷取只在明確省略 `-w` 時使用。helper 會按需建置到 `testapp/helper/bin/wincap.exe`，檢查 BMP
不是全黑，並由腳本轉成與既有截圖流程相同的 PNG 輸出格式。

P40 是 rendering geometric effects 測試，不是 layout geometry 測試。它能判定 transformed samples
是畫成真實內容還是 hotpink fallback；它不能判定 P7/#556 的 split-view pane ratio。

2026-08-29 以 PIL 量測後，才將 P40 capture 視為通過：

- `p40-wincap-20260829-181107.png`：928x743；hotpink exact 0、hotpink near 0。
  偵測到七個藍色 tile body，每個 90x58；七個橘色 anchor，每個 14x80。
- `p40-wincap-default-20260829-181425.png`：尺寸與 component geometry 相同；hotpink exact 0、
  hotpink near 0。

同一個 default P40 視窗的擷取時間：

- `screenshot.zsh -w` 透過 wincap：1000 ms。
- 舊的 direct `ffmpeg -f gdigrab -i title=...` 方法：3215 ms。

DComp 那輪中，wincap 直接擷取 `WS_EX_NOREDIRECTIONBITMAP` 視窗，非黑像素 93.0%。同輪 desktop
capture 的 wall time 接近，但它拍到前景終端機覆蓋 app，因此不是指定視窗的有效證據。
