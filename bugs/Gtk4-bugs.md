# GTK 4 bugs and limitations / GTK 4 的缺陷與限制

Defects that live in GTK 4 itself, not in this project. Kept apart from
`testapp/gtk-silent-noops.md`, which catalogues things **GtkBackend** does
wrong and could fix; everything here is upstream, and the only decisions
available to us are how to detect it and how to degrade.

Each entry records the version it was measured on, because a GTK bug is a
moving target and a fixed one should be found by re-running the reproduction
rather than by someone remembering. **Re-check any entry older than a GTK minor
release before relying on it.**

本檔記錄的是存在於 GTK 4 自身、而非本專案的缺陷。與 `testapp/gtk-silent-noops.md` 分開存放——後者
編錄的是 **GtkBackend** 自己做錯、且有能力修正的事；此處的一切都屬於上游，我們能做的決定只有
「如何偵測」與「如何降級」。

每一條都記下實測所在的版本，因為 GTK 的缺陷是會移動的目標；某條已被修好，應該是靠重跑重現步驟被
發現，而不是靠某人記得。**任何超過一個 GTK 次版本的條目，在依賴它之前請重新查證。**

---

## 1. A transformed widget renders as flat hotpink, losing its content

**Measured 2026-08-27 on GTK 4.22.4** (the current stable release at the time).
Windows and the WSL install were both on 4.22.4.

**Symptom.** Apply any non-identity transform to a widget and the entire
transformed subtree is painted as one flat rectangle of hotpink,
`rgb(255, 105, 180)` — sampled from the capture, not judged by eye. The geometry
is applied: tiles measurably move and change size. What is lost is the content.
Text, colours, child widgets: all replaced by the pink block.

Nothing is logged. No CSS parse error, no warning, no `Gtk-CRITICAL`.

**Why pink.** This is not arbitrary. GTK's own documentation states that a node
the renderer cannot handle is drawn pink, so the colour *is* GSK reporting the
failure in the only channel it has. Reading it as a mystery wastes the one clear
signal available.

**What was ruled out**, before concluding it is GTK rather than us:

| ruled out | how |
|---|---|
| the mechanism | CSS `transform: matrix(...)` and `gtk_fixed_set_child_transform` with a `GskTransform` fail identically, and they are unrelated code paths |
| the renderer | ~~`GSK_RENDERER=cairo` and the default GL renderer produce the same hotpink~~ **WRONG, and it was the whole answer — see below** |
| our own code | a no-op control that built the container and skipped **only** the transform call rendered every tile perfectly, so the container, the modifier and the layout are all innocent |
| the content | a bare `Text`, with no nested containers and no `Color` views inside the transformed subtree, goes hotpink too |
| the version | 4.22.4 is current stable; there is no newer release to move to |

### Correction, 2026-08-29: this is not a GTK transform bug

The renderer row above is false, and everything built on it was wrong. There is
no GL renderer on this machine to compare cairo against:

    Failed to realize renderer 'GskGLRenderer' for surface 'GdkWin32Toplevel':
        OpenGL requires Direct Composition
    Using renderer 'GskCairoRenderer' for surface 'GdkWin32Toplevel'

GTK falls back to the **software** cairo renderer for every window, so "cairo
and the default GL renderer agree" was cairo agreeing with itself. What cannot
draw a transform node is `GskCairoRenderer`; GSK's hotpink is that renderer
reporting it, exactly as documented — the reading of the colour was right, the
attribution was not.

The tell was there in the numbers and went unexamined: `GSK_RENDERER` set to
`(default)`, `cairo`, `gl`, `ngl` and `vulkan` all produced **47 873** hotpink
pixels — not similar, *identical*. Five renderers cannot agree to the pixel.
They were one renderer, five times. (`vulkan` is not even a recognised name in
this build, and `gl`/`ngl` both fail to realize.)

GDK has a switch for the missing piece, listed under `GDK_DEBUG=help` as
`dcomp — Enable Direct Composition (Windows)`. With it, GTK uses
`GskGLRenderer` and **every transform renders correctly**: offset, both scales,
both rotations, the shear and rotated text, with zero hotpink and no content
lost.

| | renderer | hotpink |
|---|---|---|
| default | `GskCairoRenderer` | 47 873 |
| `GDK_DEBUG=dcomp` | `GskGLRenderer` | 0 |

`GtkBackend` can ask for this itself, and does when `SCUI_GTK_DCOMP=1` is set —
four lines calling `g_setenv("GDK_DEBUG", "dcomp", 1)` before GDK initialises.
It is opt-in rather than the default because it changes how every window is
composited, not only transformed ones; P2 and P21 were checked and render
correctly under it, but that is two apps, not a decision.

**So `setGeometricEffect` declining is now a workaround for a machine
configuration, not for a platform defect.** Whether to enable dcomp by default
on Windows, and then implement the transform properly, is an open decision.

**Reproduce.**

    SCUI_DEBUG=1 zsh testapp/compile.zsh -gtk4 P40
    ( cd testapp/output && SCUI_PROBE_GTK_TRANSFORM=1 ./P40.exe & )
    zsh testapp/screenshot.zsh -w P40

Then count hotpink pixels in the capture; zero means the bug is gone.

**`SCUI_PROBE_GTK_TRANSFORM=1` is not optional, and this is the whole point.**
Without it `setGeometricEffect` applies nothing — see below — so the capture
contains zero hotpink pixels whether GTK is broken or fixed, and the count
reports "the bug is gone" having measured nothing. That is what these steps did
until 2026-08-29: they were written when the backend still applied the
transform, and were left unchanged when it stopped.

Measured 2026-08-29 on GTK 4.22.4, both ways, so the test is known to
discriminate rather than assumed to:

| | hotpink pixels | tiles |
|---|---|---|
| probe off | 0 | all seven exactly 90×57, untransformed |
| probe on | 47 873 | six of seven flat hotpink, content gone |

Check the tiles too, not only the count. A probe that silently fails to apply
also gives zero, and looks identical to a fix. On the first attempt the probe
emitted `matrix(…, 40px, 20px)`; CSS `matrix()` takes `<number>`, so the `px`
made the declaration invalid, GTK dropped it without a word, and the run
reported zero hotpink with every tile still 90×57.

**How this project degrades.** `GtkBackend.setGeometricEffect` conforms to
`BackendFeatures.GeometricEffects` and deliberately applies nothing, logging
once through `debugLogOnce`. Declining beats applying it: an untransformed view
is still legible and still clickable, whereas a hotpink rectangle has lost
everything. This is the one case so far where "apply what you can and say so"
loses to "apply nothing and say so".

Conforming-but-declining rather than not conforming is also deliberate:
`@CastBackend` turns a *missing* conformance into `fatalError`, so refusing the
protocol would abort every app that calls `.offset(_:_:)` instead of drawing it
in the wrong place.

**Not GTK-wide.** WinUIBackend implements the same protocol and renders
rotation, scale and offset correctly, so the protocol shape is sound and this is
a GTK-side gap.

> **Was: "Still untested: whether Linux GTK behaves the same. Same version, so
> probably, but nobody has run it — the WSL box has no screenshot tool installed
> and the WSLg window was not reachable from the Windows capture path."**
>
> **Tested 2026-08-29, and the guess was wrong in both halves.** Linux GTK does
> *not* behave the same: P40 under WSLg renders every transform correctly —
> offset, both scales, both rotations and the shear — with zero hotpink pixels.
> It realizes `GskVulkanRenderer`, and Vulkan draws transform nodes, so the
> defect is specific to the renderer Windows is left with rather than to the
> version. And the WSLg window *is* reachable from the Windows capture path: a
> desktop capture shows it, and `PrintWindow(PW_RENDERFULLCONTENT)` captures the
> window itself at 92.6% non-black. "Probably, but nobody has run it" is the
> shape to distrust — it reads as a conclusion and carries no evidence at all.

---

**1. 被變換過的 widget 會被畫成一整片 hotpink，其內容完全消失**

**2026-08-27 於 GTK 4.22.4 實測**（當時的最新穩定版）。Windows 與 WSL 兩邊安裝的都是 4.22.4。

**症狀。** 對任何 widget 套用非 identity 的變換，整個被變換的子樹就會被畫成一整塊純色的 hotpink，
`rgb(255, 105, 180)`——此數值取樣自截圖，而非目測判斷。幾何變換確實被套用了：方塊有可量測的位移
與尺寸變化。消失的是內容：文字、顏色、子 widget，全部被那塊粉紅色取代。

過程中沒有任何紀錄。沒有 CSS 解析錯誤、沒有警告、沒有 `Gtk-CRITICAL`。

**為何是粉紅色。** 這並非隨意選色。GTK 官方文件載明「繪製器無法處理的節點會被畫成粉紅色」，因此
這個顏色**就是** GSK 以它僅有的管道回報失敗。把它當成謎團看待，等於浪費了現場唯一明確的訊號。

**在判定為 GTK 而非我方問題之前，已排除的項目**（對應上表）：機制（CSS `transform: matrix(...)`
與搭配 `GskTransform` 的 `gtk_fixed_set_child_transform` 失敗方式完全相同，而兩者是互不相干的程式
路徑）、繪製器（`GSK_RENDERER=cairo` 與預設的 GL 繪製器結果同為 hotpink）、我方程式碼（一組「建立
容器但**只**略過變換呼叫」的對照組，每個方塊都正常繪製，故容器、modifier 與版面皆無涉）、內容
（被變換的子樹中僅有一段純 `Text`、無巢狀容器亦無 `Color` view，同樣變成 hotpink）、版本
（4.22.4 已是最新穩定版，無更新版本可換）。

**重現方式**：指令同上；接著計算截圖中 hotpink 像素的數量，為零即代表此缺陷已消失。

**本專案的降級方式。** `GtkBackend.setGeometricEffect` 會宣告 conformance 但刻意不做任何事，並透過
`debugLogOnce` 記錄一次。拒絕執行優於強行套用：未經變換的 view 仍然可讀、仍然可點擊，而一塊
hotpink 矩形已經失去一切。這是目前唯一一個「盡力套用並明白告知」輸給「什麼都不做但明白告知」的
情況。

選擇「宣告 conformance 但拒絕執行」而非「不宣告」，同樣是刻意的：`@CastBackend` 會把**缺少的**
conformance 轉為 `fatalError`，因此若拒絕實作該 protocol，任何呼叫 `.offset(_:_:)` 的 app 都會直接
中止，而不是把它畫在錯誤的位置。

**這並非 GTK 以外皆然。** WinUIBackend 實作了同一個 protocol，且能正確繪製旋轉、縮放與位移，因此
protocol 本身是健全的，這是 GTK 這一側的缺口。

> **原文為：「仍未測試：Linux 的 GTK 是否有相同行為。版本相同，結果很可能一致，但確實無人實測
> 過——WSL 環境未安裝任何截圖工具，而 WSLg 的視窗也無法從 Windows 的擷取路徑取得。」**
>
> **2026-08-29 已測，而且這個猜測兩半都錯。** Linux 的 GTK **並非**相同行為：WSLg 下的 P40 把
> 每一個變換都正確繪製出來——位移、兩種縮放、兩種旋轉與 shear——hotpink 像素為 0。它實現的是
> `GskVulkanRenderer`，而 Vulkan 畫得出 transform node，因此該缺陷專屬於「Windows 上只剩下的
> 那個繪製器」，而非該版本。另外，WSLg 的視窗**確實**能由 Windows 的擷取路徑取得：桌面擷取拍
> 得到它，而 `PrintWindow(PW_RENDERFULLCONTENT)` 更能直接擷取該視窗本身，非黑像素達 92.6%。
> 「很可能一致，但無人實測過」正是該被懷疑的句型——它讀起來像結論，卻完全不帶證據。

---

## 2. Not GTK: WSL has no hardware Vulkan, so GSK silently draws on the CPU

**Filed here despite not being a GTK defect**, because it is upstream of us in
exactly the sense this file is for: we cannot fix it, and the only decisions
available are how to detect it and how to degrade. Measured 2026-08-29 on
Ubuntu 26.04, Mesa 26.0.3, WSL 2.7.12, WSLg 1.0.73.2, Direct3D 1.611.1.

**Symptom.** GTK reports `GskVulkanRenderer`, which reads like hardware, and
every frame is drawn by lavapipe on the CPU:

    libEGL warning: MESA-LOADER: failed to retrieve device information
    MESA: error: ZINK: failed to choose pdev
    Not using GL: renderer is llvmpipe
    Using renderer 'GskVulkanRenderer' for surface 'GdkWaylandToplevel'

**Cause, and it is two absences rather than a misconfiguration.**

1. **Eight Vulkan ICD manifests look plentiful and every one is for hardware
   that is not present** — asahi, gfxstream, intel, intel_hasvk, nouveau,
   radeon, virtio, and `lvp`. Only lavapipe can answer, and lavapipe is
   software. `dzn`, Mesa's Vulkan-on-D3D12 driver and the only one that could
   reach a GPU through `/dev/dxg`, **is not built into Ubuntu's
   `mesa-vulkan-drivers` at all**: `/usr/lib/x86_64-linux-gnu/libvulkan_dzn.so`
   does not exist. So this is not a manifest to add or a variable to set.
2. **The Windows driver publishes no GL or Vulkan userspace into WSL.**
   `/usr/lib/wsl/lib` holds CUDA, NVENC/NVDEC and OptiX — `libcuda.so`,
   `libnvcuvid.so`, `libnvidia-encode.so`, `libnvoptix.so` — and nothing
   matching GLX, Vulkan or ICD.

The hardware plumbing is otherwise intact: `/dev/dxg` exists, `libdxcore.so`
and `libd3d12core.so` are in the loader cache via `/etc/ld.so.conf.d/ld.wsl.conf`,
and `d3d12_dri.so` is installed. `/dev/dri` does not exist.

**Everything reachable without installing anything was tried and none of it
helped**: `GALLIUM_DRIVER=d3d12`, `MESA_LOADER_DRIVER_OVERRIDE=d3d12`, and an
explicit `LD_LIBRARY_PATH=/usr/lib/wsl/lib`. All still ended at llvmpipe.

**What this invalidates.** UI tests stay valid — the pixels are correct, they
were simply drawn by the CPU. Anything measuring GPU presentation, frame time
or renderer performance on WSL is measuring lavapipe. In particular, "Vulkan is
the hardware path so it must be faster than Cairo" is false here: both run on
the CPU, and lavapipe additionally emulates a GPU pipeline.

**Detection**: `zsh testapp/diagnose_wsl_gpu.zsh` prints the ICD manifests, the
`libvulkan_*.so` that Mesa was actually built with, and what the Windows driver
exposes. The distinction between those first two matters — the manifests say
what is configured, the libraries say what exists to configure.

### Building `dzn` was tried, and it narrows the cause to one place

**2026-08-29.** Rather than leave "a Mesa built with `dzn`" as a suggestion, it
was done. `mesa-vulkan-drivers` was upgraded to 26.0.8 first — still no `dzn`,
confirming Ubuntu does not build it at any available version — then Mesa 26.0.8
was configured with `-Dvulkan-drivers=microsoft-experimental` and built into a
**separate prefix**, `/opt/mesa-dzn`, so the working system Mesa is untouched
and the two can be A/B'd with `VK_DRIVER_FILES`.

It builds and loads. It still finds no GPU:

    MESA: error: ID3D12DeviceFactory::CreateDevice failed
    Failed to detect any valid GPUs in the current config

**That is a more useful failure than the one it replaced**, because it moves the
blocker off Linux entirely. `dzn` reaches D3D12 through `libd3d12.so`'s
`D3D12GetInterface` and enumerates adapters through `libdxcore.so`; both load
successfully, and reaching `CreateDevice` at all means **an adapter was
enumerated**. What fails is D3D12 creating a device on it, and that needs a
user-mode D3D12 driver the Windows side must publish into `/usr/lib/wsl/lib` —
where, as above, only CUDA, NVENC/NVDEC and OptiX appear.

So the Linux side is now complete and the remaining lever is a **Windows NVIDIA
driver that installs WSL graphics support**, not anything installable inside the
distribution. `/opt/mesa-dzn` is left in place: it costs nothing, it is not on
any default path, and it means the next attempt starts from a measurement rather
than from this paragraph.

**Fixes, neither of which is a code change**: a Windows NVIDIA driver that
publishes GL/Vulkan/D3D12 userspace to WSL, or — already done, and not
sufficient by itself — a Mesa built with `dzn`.

**曾實際建置 `dzn`，而這把成因收斂到單一位置。2026-08-29。** 與其把「換一份編入 dzn 的 Mesa」
留為建議，直接做了。先將 `mesa-vulkan-drivers` 升級至 26.0.8——仍然沒有 `dzn`，確認 Ubuntu 在
任何可取得的版本都不編它——再以 `-Dvulkan-drivers=microsoft-experimental` 設定並建置 Mesa 26.0.8，
裝入**獨立 prefix** `/opt/mesa-dzn`，因此可運作的系統 Mesa 未被動到，兩者可用 `VK_DRIVER_FILES`
進行 A/B。

它建得起來也載入得了，卻依然找不到 GPU（訊息見上）。**這個失敗比它所取代的那個更有用**，因為它
把阻礙完全移出 Linux：`dzn` 透過 `libd3d12.so` 的 `D3D12GetInterface` 進入 D3D12，並透過
`libdxcore.so` 列舉介面卡；兩者都成功載入，而**能走到 `CreateDevice` 就代表介面卡確實被列舉到了**。
失敗的是 D3D12 在該介面卡上建立裝置，而那需要一份由 Windows 端發布進 `/usr/lib/wsl/lib` 的
user-mode D3D12 驅動——如前所述，那裡只有 CUDA、NVENC/NVDEC 與 OptiX。

因此 Linux 這一側已經做完，剩下的槓桿是**一份會安裝 WSL 圖形支援的 Windows NVIDIA 驅動**，而非
發行版內可安裝的任何東西。`/opt/mesa-dzn` 予以保留：它不佔用任何預設路徑、成本為零，並且讓下一次
嘗試從一個量測結果出發，而不是從這段文字出發。

---

**2. 這不是 GTK：WSL 沒有硬體 Vulkan，因此 GSK 靜默地改用 CPU 繪製**

**雖非 GTK 的缺陷仍歸檔於此**，因為它正是本檔所針對的那種「位於我們上游」：我們修不了，能做的
決定只有「如何偵測」與「如何降級」。2026-08-29 於 Ubuntu 26.04、Mesa 26.0.3、WSL 2.7.12、
WSLg 1.0.73.2、Direct3D 1.611.1 實測。

**症狀。** GTK 回報 `GskVulkanRenderer`，讀起來像硬體，而每一格其實都由 CPU 上的 lavapipe 繪製
（訊息見上）。

**成因是兩項「缺席」，而非設定錯誤。**

1. **八個 Vulkan ICD manifest 看起來很豐富，但每一個都對應到不存在的硬體**——asahi、gfxstream、
   intel、intel_hasvk、nouveau、radeon、virtio 與 `lvp`。只有 lavapipe 能回應，而 lavapipe 是軟體。
   `dzn`（Mesa 的 Vulkan-on-D3D12 驅動，也是唯一能透過 `/dev/dxg` 觸及 GPU 的那個）**根本未被
   Ubuntu 的 `mesa-vulkan-drivers` 編入**：`/usr/lib/x86_64-linux-gnu/libvulkan_dzn.so` 並不存在。
   因此這不是「補一個 manifest」或「設一個環境變數」能解決的。
2. **Windows 驅動未向 WSL 發布任何 GL 或 Vulkan userspace。** `/usr/lib/wsl/lib` 內有 CUDA、
   NVENC/NVDEC 與 OptiX——`libcuda.so`、`libnvcuvid.so`、`libnvidia-encode.so`、`libnvoptix.so`
   ——而沒有任何名稱含 GLX、Vulkan 或 ICD 的檔案。

其餘硬體管線是完整的：`/dev/dxg` 存在，`libdxcore.so` 與 `libd3d12core.so` 透過
`/etc/ld.so.conf.d/ld.wsl.conf` 位於 loader cache 中，`d3d12_dri.so` 也已安裝。`/dev/dri` 不存在。

**所有「不必安裝任何東西」的途徑都試過，全部無效**：`GALLIUM_DRIVER=d3d12`、
`MESA_LOADER_DRIVER_OVERRIDE=d3d12`，以及顯式指定 `LD_LIBRARY_PATH=/usr/lib/wsl/lib`。
結果一律止於 llvmpipe。

**這會使哪些結論失效。** UI 測試仍然有效——像素是正確的，只是由 CPU 畫的。但任何在 WSL 上量測
GPU 呈現、frame time 或繪製器效能的工作，量到的都是 lavapipe。尤其「Vulkan 是硬體路徑，所以一定
比 Cairo 快」在此為假：兩者都跑在 CPU 上，而 lavapipe 還額外模擬了一整條 GPU pipeline。

**偵測方式**：`zsh testapp/diagnose_wsl_gpu.zsh` 會列出 ICD manifest、Mesa 實際編入的
`libvulkan_*.so`，以及 Windows 驅動所暴露的內容。前兩者的區別很重要——manifest 說的是「設定了
什麼」，函式庫說的是「有什麼可供設定」。

**修法有兩條，皆非程式碼變更**：換一份會向 WSL 發布 GL/Vulkan userspace 的 Windows NVIDIA 驅動，
或換一份編入 `dzn` 的 Mesa。

---

## 3. The two GTK 4 builds for Windows are each missing the half the other has

**Measured 2026-08-29. Both builds are GTK 4.22.4** — the same upstream release,
so nothing here is a version difference.

| | Vulkan renderer built in | `dcomp` in `GDK_DEBUG` |
|---|---|---|
| gvsbuild (`/c/gtk4`, MSVC, `gtk-4-1.dll`) | **no** — `-Dvulkan=disabled` | **yes** |
| MSYS2 ucrt64 (MinGW, `libgtk-4-1.dll`) | **yes** — imports `vulkan-1.dll` | **no** |

**Why that combination is fatal rather than merely awkward.** GTK's Win32
backend demands Direct Composition for Vulkan exactly as it does for OpenGL:

    Failed to realize renderer 'GskVulkanRenderer' for surface 'GdkWin32Toplevel':
        Vulkan requires Direct Composition

So the MSYS2 build ships a renderer it cannot reach, and drops the switch that
reaches the one gvsbuild *can* — `dcomp` is what `SCUI_GTK_DCOMP=1` and `-GPU 2`
turn on, and the only route to a hardware renderer on Windows. **Switching to
MSYS2 would trade a renderer we cannot use for a switch we need.** gvsbuild
stays; `testapp/install_gtk4_windows.zsh` records this so the swap is not
attempted as an upgrade.

On gvsbuild, GTK says so itself, which is the only source that settles it:

    $ GSK_RENDERER=help ./P40.exe
      cairo  - Use the Cairo fallback renderer
      opengl - Use the OpenGL renderer
      vulkan - Disabled during GTK build

**Verified by running MSYS2's own `gtk4-demo.exe`**, downloaded and extracted
without installing MSYS2 — no repackaging, no import libraries, no rebuild. The
`GDK_DEBUG=help` output was checked to be non-empty before concluding `dcomp`
was absent from it: 28 flags listed, including `opengl` and `vulkan`. Without
that control, "no dcomp line" is indistinguishable from "no output".

That control exists because the first attempt at this comparison reached the
right verdict for an entirely false reason — `strings` and `objdump` were aimed
at `libgtk-4-1.dll` while the gvsbuild file is `gtk-4-1.dll`, and both tools
printed nothing for a file that does not exist. See `mistakes/mistakes.csv2`
entry 43.

**Nothing here is fixable from this repository.** It is two packaging decisions
upstream, and the only choice available is which build to depend on.

---

**3. Windows 上的兩份 GTK 4 build，各自缺少對方擁有的那一半**

**2026-08-29 實測。兩份都是 GTK 4.22.4**——同一個上游版本，因此以上差異都不是版本差異（表見上）。

**為何這個組合是致命的、而非只是不便。** GTK 的 Win32 backend 對 Vulkan 的要求，與它對 OpenGL 的
要求完全相同：`Vulkan requires Direct Composition`。

因此 MSYS2 那份帶著一個它**構不到**的繪製器，同時又拿掉了那個能構到 gvsbuild 唯一可用繪製器的
開關——`dcomp` 正是 `SCUI_GTK_DCOMP=1` 與 `-GPU 2` 所開啟的東西，也是 Windows 上通往硬體繪製器
的唯一途徑。**換到 MSYS2 等於用一個我們用不到的繪製器，換掉一個我們需要的開關。** 因此維持
gvsbuild；`testapp/install_gtk4_windows.zsh` 已記下此事，以免日後有人把這個交換當成升級。

**此結論是實際執行 MSYS2 自帶的 `gtk4-demo.exe` 得出的**——套件下載後直接解壓，未安裝 MSYS2、
未重新打包、未產生 import library、未重新建置。在斷定「`dcomp` 不在其中」之前，先確認過
`GDK_DEBUG=help` 的輸出並非空的：共列出 28 個 flag，其中包含 `opengl` 與 `vulkan`。少了這道對照，
「沒有 dcomp 那一行」與「根本沒有輸出」是無法區分的。

這道對照之所以存在，是因為本比較的第一次嘗試「結論正確、理由卻全錯」——`strings` 與 `objdump`
被指向了 `libgtk-4-1.dll`，而 gvsbuild 的檔名是 `gtk-4-1.dll`，兩個工具都對一個不存在的檔案印出了
「沒有」。詳見 `mistakes/mistakes.csv2` 第 43 條。

**此處沒有任何一項能從本 repository 修正。** 那是上游的兩個打包決策，我們唯一能做的選擇是「要依賴
哪一份 build」。

---

## 4. A GtkCalendar cannot carry a time of day, a time zone, a calendar system or a range

**Measured on GTK 4.22.4 and then confirmed in `gtk/gtkcalendar.c`**, which is
why these are stated rather than suspected. The obvious implementation -- hand
GTK a `GDateTime` and read one back -- is wrong in three separate ways.

- **`gtk_calendar_select_day` returns early unless the year, month or day
  differs** (`calendar_select_day_internal`). Setting the same day at a
  different time of day, or in a different time zone, silently does nothing. So
  the widget cannot be used to carry a time of day at all.
- **Clicking a day discards the time and forces the machine's time zone.**
  `calendar_select_and_focus_day` rebuilds the value as
  `g_date_time_new_local(year, month, day, 0, 0, 0)`, whatever zone was set.
- **`day-selected` fires for a programmatic set exactly as for a click.** A
  handler that does not tell the two apart reports the application's own writes
  back into its binding.

Two further limits are model gaps rather than defects:

- **No calendar system.** A `GtkCalendar` is Gregorian, and has no
  calendar-system property among its 43. Its month names come from the C locale
  rather than from anything the caller passes, so `environment.calendar` cannot
  reach the grid.
- **No minimum or maximum date**, so out-of-range days stay clickable.

**How this project degrades.** `GtkBackend` treats a `GtkCalendar` as storing a
year, month and day and nothing else: it keeps the bound `Date` itself and
rebuilds it from the widget's day plus its own time of day, resolved in
`environment.timeZone`. Nothing reads an instant back out of GTK. The compact
style's label goes through a `DateFormatter` and does honour
`environment.calendar`; the grid cannot. `range` is clamped afterwards, which is
what the protocol asks for anyway since it calls `range` a hint.

> **Was, written earlier the same day: "Still open, and it is upstream's
> unfinished work rather than ours. GTK has no time-of-day widget in play
> here."**
>
> **False, and corrected within the hour.** `TimeRow` at
> `GtkBackend.swift:4864` is a working time-of-day widget written in Swift on
> GTK primitives. It takes a `Precision` of `.hourMinute` or
> `.hourMinuteSecond`, reports through `onChange` on a 24-hour clock whatever
> the locale draws, and decides 12-versus-24-hour with
> `DateFormatter.dateFormat(fromTemplate: "j")` rather than `Locale.hourCycle`,
> which would need macOS 13. It is wired: `updateDatePicker` derives the
> precision from the requested components — testing `hourMinuteAndSecond` first,
> because SwiftUI's bitfield makes it include `hourAndMinute` — constructs the
> row, and `applyDate` writes the hour, minute and second back into it.
>
> **How the wrong claim was reached is the part worth keeping.** Two stale
> markers agreed with each other: the abandoned `TimePicker` class, and
> `gtk-silent-noops.md` entry 12 saying time components are dropped. Neither was
> checked against a grep for a *working* implementation, and two stale sources
> pointing the same way read as corroboration. The same file already carried
> three entries whose line numbers no longer existed.

**So the time of day is implemented**, and the `GtkCalendar` limits above are
the reason it had to be: the calendar grid carries the date, a separate row
carries the time, and the bound `Date` is rebuilt from both.

The incomplete `TimePicker` class from upstream's
`425ff888 Implement DatePicker (#244)` is still in the file, unused, with its
author's note that the spin buttons could not be made to work and four TODOs.
Left in place deliberately: it is upstream's code, and deleting it in a fork
buys a merge conflict rather than a fix. It is also what made the claim above
look true, so it is worth knowing it is superseded rather than pending.

---

**4. GtkCalendar 無法承載時間、時區、曆法系統或範圍**

**於 GTK 4.22.4 實測，並在 `gtk/gtkcalendar.c` 中確認**，因此以下是陳述而非臆測。最直覺的實作
——把 `GDateTime` 交給 GTK、再讀一個回來——在三個彼此獨立的地方是錯的。

- **`gtk_calendar_select_day` 在年、月、日皆未改變時會提早返回**（`calendar_select_day_internal`）。
  以「同一天但不同時刻」或「同一天但不同時區」去設定，會**無聲地什麼也不做**。因此該 widget 根本
  無法用來承載一天中的時間。
- **點選某一天會丟棄時間，並強制使用機器的時區。** `calendar_select_and_focus_day` 以
  `g_date_time_new_local(year, month, day, 0, 0, 0)` 重建該值，無論先前設定的是哪個時區。
- **`day-selected` 對「程式設定」與「使用者點選」一視同仁地觸發。** 未區分兩者的處理常式，會把
  應用程式自己的寫入回報進它自己的 binding。

另有兩項是模型上的缺口而非缺陷：**沒有曆法系統**（`GtkCalendar` 是格里曆，其 43 個屬性中沒有任何
曆法系統屬性，月份名稱取自 C locale 而非呼叫端傳入之物，因此 `environment.calendar` 到不了那個
網格）；以及**沒有最小／最大日期**，超出範圍的日子仍可點選。

**本專案如何降級。** `GtkBackend` 把 `GtkCalendar` 當成「只儲存年、月、日」：它自己保有繫結的
`Date`，再由 widget 的日期加上它自己的時刻、於 `environment.timeZone` 中解析並重建。**不從 GTK
讀回任何時間點。** compact 樣式的標籤走 `DateFormatter`，確實會遵從 `environment.calendar`；網格
則不能。`range` 於事後夾制，而那本來就是 protocol 所要求的——它把 `range` 稱為提示。

> **原文（同日稍早所寫）：「仍未解決，而且那是上游未完成的工作，不是我們的。此處沒有可用的
> GTK 時刻 widget。」**
>
> **這是假的，並於一小時內更正。** `GtkBackend.swift:4864` 的 `TimeRow` 就是一個能運作的時刻
> widget，以 Swift 寫在 GTK 原生元件之上。它接受 `.hourMinute` 或 `.hourMinuteSecond` 兩種
> `Precision`，無論 locale 如何呈現都以 24 小時制透過 `onChange` 回報，並以
> `DateFormatter.dateFormat(fromTemplate: "j")` 判斷 12 或 24 小時制——而非使用需要 macOS 13 的
> `Locale.hourCycle`。它也確實被接上：`updateDatePicker` 由所要求的 components 推導出精度
> （先測 `hourMinuteAndSecond`，因為 SwiftUI 的 bitfield 使它包含 `hourAndMinute`），建構該 row，
> 而 `applyDate` 會把時、分、秒寫回其中。
>
> **這個錯誤結論是怎麼得出的，才是值得留下的部分。** 兩個過時的標記彼此吻合：被放棄的 `TimePicker`
> 類別，以及 `gtk-silent-noops.md` 第 12 條「時間元件被丟棄」。兩者都沒有被拿去對照「是否存在**可
> 運作的**實作」的 grep，而**兩個指向同一方向的過時來源，讀起來就像互相佐證**。同一份檔案裡本就已
> 經有三條所引行號早已不存在的條目。

**因此時刻功能是已實作的**，而上述 `GtkCalendar` 的限制正是它必須如此的原因：日曆網格承載日期，
另一列承載時間，繫結的 `Date` 由兩者共同重建。

上游 `425ff888 Implement DatePicker (#244)` 帶來的那個 incomplete `TimePicker` 類別仍在檔案中、
未被使用，並附有作者「spin buttons 無法運作」的註記與四項 TODO。刻意保留：那是上游的程式碼，在
fork 中刪除它換來的是 merge 衝突而非修正。它同時也正是讓上述錯誤主張看起來為真的東西，因此值得
知道它是**已被取代**，而非**尚待完成**。
