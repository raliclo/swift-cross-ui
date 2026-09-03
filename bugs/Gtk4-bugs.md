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
    ( cd testapp/output && SCUI_PROBE_GTK_TRANSFORM=1 ./P40-gtk4.exe & )
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

    $ GSK_RENDERER=help ./P40-gtk4.exe
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

**The time of day is implemented, and the limits above are the reason it had to
be separate.** The calendar grid carries the date, a separate row carries the
time, and the bound `Date` is rebuilt from both.

`TimeRow` at `GtkBackend.swift:4864` is that row, written in Swift on GTK
primitives. It takes a `Precision` of `.hourMinute` or `.hourMinuteSecond`,
reports through `onChange` on a 24-hour clock whatever the locale draws, and
decides 12-versus-24-hour with `DateFormatter.dateFormat(fromTemplate: "j")`
rather than `Locale.hourCycle`, which would need macOS 13. `updateDatePicker`
derives the precision from the requested components — testing
`hourMinuteAndSecond` first, because SwiftUI's bitfield makes it include
`hourAndMinute` — constructs the row, and `applyDate` writes the hour, minute
and second back into it. Exercised by P41 and verified by capture on
2026-09-01.

The incomplete `TimePicker` class from upstream's
`425ff888 Implement DatePicker (#244)` is still in the file, unused, with its
author's note that the spin buttons could not be made to work and four TODOs.
Left in place deliberately: it is upstream's code, and deleting it in a fork
buys a merge conflict rather than a fix. **It is superseded, not pending** —
`TimeRow` is what carries the time, and reading `TimePicker` as the unfinished
state of this feature is wrong.

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

**時刻功能是已實作的，而上述限制正是它必須獨立出來的原因**：日曆網格承載日期，另一列承載時間，
繫結的 `Date` 由兩者共同重建。

`GtkBackend.swift:4864` 的 `TimeRow` 就是那一列，以 Swift 寫在 GTK 原生元件之上。它接受
`.hourMinute` 或 `.hourMinuteSecond` 兩種 `Precision`，無論 locale 如何呈現都以 24 小時制透過
`onChange` 回報，並以 `DateFormatter.dateFormat(fromTemplate: "j")` 判斷 12 或 24 小時制——而非
使用需要 macOS 13 的 `Locale.hourCycle`。`updateDatePicker` 由所要求的 components 推導出精度
（先測 `hourMinuteAndSecond`，因為 SwiftUI 的 bitfield 使它包含 `hourAndMinute`），建構該 row，
而 `applyDate` 會把時、分、秒寫回其中。由 P41 驅動，並於 2026-09-01 以截圖驗證。

上游 `425ff888 Implement DatePicker (#244)` 帶來的那個 incomplete `TimePicker` 類別仍在檔案中、
未被使用，並附有作者「spin buttons 無法運作」的註記與四項 TODO。刻意保留：那是上游的程式碼，在
fork 中刪除它換來的是 merge 衝突而非修正。**它是已被取代，而非尚待完成**——承載時間的是 `TimeRow`，
把 `TimePicker` 讀成「這個功能的未完成狀態」是錯的。

---

## 5. Not GTK: `gtk_window_set_default_size` sizes the whole window, and we treat it as content

**Measured 2026-09-01 on WSLg with P16, GTK 4.22.4, and again 2026-09-03 on GTK
for Windows (gvsbuild).** Filed here rather than as a GTK defect because GTK
behaves as documented; the mistake is on our side.

> **Was scoped to WSLg, and that was wrong.** Until 2026-09-03 everything below
> was written up as a WSLg observation, with the WinUI comparison read as
> "Windows is fine". **The shortfall is a property of `GtkBackend`, not of
> WSLg.** GTK on Windows loses the same **39px**, for the same reason: with
> client-side decorations the header bar is inside the window on both. Only the
> decoration thickness *around* the window differs between them, and that is not
> the number that matters. The WSLg text is kept below rather than replaced,
> because "measured on WSLg" reads as a platform finding, and that reading is
> exactly what needs distrusting.

P16 asks for `.defaultSize(width: 900, height: 600)`. `GtkBackend.createWindow`
passes that straight to `window.defaultSize` (`GtkBackend.swift:994-997`), which
is `gtk_window_set_default_size` (`Sources/Gtk/Widgets/Window.swift:63`). In
GTK4 that call sizes the **window**, and with client-side decorations the header
bar is inside the window. So the app is given less than it asked for.

A wincap capture of the WSLg window, measured pixel by pixel:

| | |
|---|---|
| window surface | exactly **900x600** — the request was honoured |
| header bar inside it | **39px** |
| content left for the app | **900x561** |

The consequence is visible in the layout system's own diagnostic, which reports
`leadingContent` height **485** on the first commit and **446** on the second
and third, differing by exactly 39. Reproducible byte-for-byte across three
runs. **The first pass is the one that honours the request**; the second is the
layout system correctly re-laying out for a window that turned out smaller. No
part of the layout code is wrong.

**GTK on Windows does the same thing, measured 2026-09-03**, which is what takes
this off WSLg. P16 logs three passes there: `leadingContent=200.0x480.0` twice,
then `200.0x441.0` — a drop of **39**, the identical number, and a later pass
correcting an earlier one exactly as under WSLg. The absolute heights differ
(480/441 against 485/446) because the two window systems put different amounts
of decoration around the surface; the shortfall does not differ at all.

| backend / platform | `leadingContent` height | passes | shortfall |
|---|---|---|---|
| GTK / Windows (gvsbuild) | 480, 480, then **441** | 3, with a correction | **39** |
| GTK / WSLg | 485, then **446** | 2, with a correction | **39** |
| WinUI / Windows | **486** | 1, no correction | **0** |

Regenerate any row with `SCUI_DEBUG_SPLIT=1 zsh testapp/run.zsh P16`, then read
`splitview-debug.log` **in the repo root** — `SplitView.swift:215` builds its
path from `currentDirectoryPath`, so the file lands where you invoked the script
and not in `testapp/output/` next to the executable.

WinUIBackend does not have this: on Windows the title bar is non-client area, so
the same app measures a 916x639 frame around a 900x600 client and reports a
steady 486 with no second pass. Widths are unaffected anywhere — the header bar
takes height only, and every case reports `total=880` = 900 - 2x10 of padding.

**The frame sizes say the same thing from outside the app, and the deltas are
constant per backend.** Measured 2026-09-03 on two apps asking for different
sizes:

| app | `.defaultSize` | gtk4 frame | WinUI frame |
|---|---|---|---|
| P31 | 780x560 | 808x589 (**+28/+29**) | 796x599 (**+16/+39**) |
| P16 | 900x600 | 928x629 (**+28/+29**) | 916x639 (**+16/+39**) |

Neither delta moves with the requested size, so each is a fixed decoration cost
rather than anything proportional. WinUI's **+16/+39** is Windows non-client area
drawn *around* a client of exactly the requested size — **WinUI honours the
request**, and the frame being larger than the request is not a shortfall. What
gtk4's +28/+29 is made of was not broken down; only that it is constant, and
that it is a different constant from WinUI's, which is why comparing frame sizes
between the two backends says nothing about which one honoured the request.

**Why it cannot be fixed by adding a constant.** GTK4 has no set-content-size
call, and the header height is not knowable before the window is realized: it
depends on theme, scale and whether the compositor gives server-side decorations
at all. The correction has to happen once after the window is mapped — compare
the content widget's allocation against the request and grow the window by the
shortfall. Tracked in `todo.md`.

Unverified and needing a Mac: whether AppKit's `.defaultSize` maps to the
content rect, which would make GTK the only one of the three that is short.

---

**5. 非 GTK 的問題：`gtk_window_set_default_size` 設定的是整個視窗，而我們把它當成內容**

**2026-09-01 於 WSLg 以 P16 量測，GTK 4.22.4；2026-09-03 再於 Windows 版 GTK（gvsbuild）上量測一次。**
歸在此處而非列為 GTK 缺陷，因為 GTK 的行為與其文件一致；錯在我們這邊。

> **原本被界定為 WSLg 的現象，而那個界定是錯的。** 2026-09-03 之前，以下內容都被寫成「WSLg 上的
> 觀察」，並把 WinUI 的對照讀成「Windows 沒事」。**這個短少是 `GtkBackend` 的性質，不是 WSLg 的。**
> Windows 上的 GTK 少掉的是同樣的 **39px**，理由也相同：在 client-side decoration 之下，標題列在兩
> 邊都位於視窗之內。兩者之間不同的只有視窗**外側**的裝飾厚度，而那並不是關鍵的那個數字。以下保留
> 原本的 WSLg 敘述而非刪除，因為「於 WSLg 量測」讀起來像是一項平台結論，而那正是該被懷疑的讀法。

P16 要求 `.defaultSize(width: 900, height: 600)`。`GtkBackend.createWindow` 把它直接交給
`window.defaultSize`（`GtkBackend.swift:994-997`），亦即 `gtk_window_set_default_size`
（`Sources/Gtk/Widgets/Window.swift:63`）。在 GTK4 中該呼叫設定的是**視窗**，而在 client-side
decoration 之下，標題列位於視窗之內。於是 app 拿到的比它要求的少。

一張 WSLg 視窗的 wincap 截圖，逐像素量測：

| | |
|---|---|
| 視窗表面 | 恰為 **900x600**——要求本身有被遵守 |
| 其內的標題列 | **39px** |
| app 實際可用的內容 | **900x561** |

後果可在版面系統自身的診斷中看到：`leadingContent` 高度第一次 commit 為 **485**，第二、三次為
**446**，相差正好 39，三次執行逐位元組可重現。**第一輪才是遵守要求的那一次**；第二輪是版面系統
正確地為「實際較小的視窗」重新排版。版面程式碼沒有任何一處是錯的。

**Windows 上的 GTK 做的是同一件事，2026-09-03 實測**——這正是把本條移出 WSLg 的依據。P16 在該處
記錄了三輪：`leadingContent=200.0x480.0` 兩次，接著 `200.0x441.0`，落差 **39**，與 WSLg 完全相同的
數字，且同樣有一輪修正前一輪。絕對高度不同（480/441 對 485/446），是因為兩個視窗系統在表面外圍
加上的裝飾厚度不同；短少的量則毫無差異。

| backend / 平台 | `leadingContent` 高度 | 輪數 | 短少 |
|---|---|---|---|
| GTK / Windows（gvsbuild） | 480、480，接著 **441** | 3 輪，含一次修正 | **39** |
| GTK / WSLg | 485，接著 **446** | 2 輪，含一次修正 | **39** |
| WinUI / Windows | **486** | 1 輪，無修正 | **0** |

任何一列都可用 `SCUI_DEBUG_SPLIT=1 zsh testapp/run.zsh P16` 重新產生，再讀取**repo 根目錄下**的
`splitview-debug.log`——`SplitView.swift:215` 以 `currentDirectoryPath` 組出路徑，因此該檔會落在
「你執行腳本的位置」，而不是執行檔旁的 `testapp/output/`。

WinUIBackend 沒有這個問題：Windows 上標題列屬 non-client 區域，因此同一支 app 量得 916x639 的
外框包著 900x600 的 client，回報穩定的 486 且沒有第二輪。三種情況的寬度都不受影響——標題列只吃
高度，每一個都回報 `total=880` = 900 − 2×10 的 padding。

**視窗外框尺寸從 app 之外說的是同一件事，而其差額對每個 backend 而言是固定的。** 2026-09-03 於兩支
要求不同尺寸的 app 上量測：

| app | `.defaultSize` | gtk4 外框 | WinUI 外框 |
|---|---|---|---|
| P31 | 780x560 | 808x589（**+28/+29**） | 796x599（**+16/+39**） |
| P16 | 900x600 | 928x629（**+28/+29**） | 916x639（**+16/+39**） |

兩組差額都不隨要求的尺寸變動，因此各自是固定的裝飾成本，而非任何比例性的東西。WinUI 的
**+16/+39** 是 Windows 畫在「尺寸恰為所求」的 client **外圍**的 non-client 區域——**WinUI 遵守了
要求**，外框大於要求並不是短少。gtk4 的 +28/+29 由什麼組成並未拆解，只確認它是固定值，且與 WinUI
的是不同的固定值——這也正是為何「比較兩個 backend 的外框尺寸」完全說不出誰遵守了要求。

**為何不能靠加一個常數修好。** GTK4 沒有「設定內容尺寸」的呼叫，而標題列高度在視窗 realize 之前
無從得知：它取決於主題、縮放，以及 compositor 是否根本提供 server-side decorations。修正必須在
視窗 map 之後做一次——比對內容 widget 的配置與原始要求，再依差額放大視窗。追蹤於 `todo.md`。

尚未驗證、需要 Mac：AppKit 的 `.defaultSize` 是否對應 content rect；若是，GTK 就是三者中唯一
少給的那一個。

---

## 6. Not GTK: the Win32 synthesiser cannot address a modal dialog, and steals focus from it

**Measured 2026-09-03 on Windows / GtkBackend, driving P31 with
`testapp/actions/win/P31-tab-and-escape.csv`.**

Escape does not dismiss a `.alert`. The alert stays open, the main window's
controls grey out behind it, and the replay reports nothing wrong.

**It is not GTK ignoring the key.** The same run proves the keyboard path works:
`key tab` then `key space` activated the button, and `p31-debug-events.log`
records `button clicked count=1`. Keys arrive. Escape did not fail to be sent.

**The synthesiser sent it to the wrong window.** `Win32Synthesiser.ownWindow()`
(Win32Synthesiser.swift:365-400) enumerates this process's visible top-level
windows and returns **the one with the largest area**. A `Gtk.MessageDialog` is
a separate top-level window and is smaller than the window that owns it, so the
heuristic can never select it. Worse, the synthesiser then calls
`SetForegroundWindow` on that main window before sending, which **takes focus
away from the modal** and delivers Escape to the window that was not asking for
it.

The file's own comment already describes this failure shape on another platform:
"a window presented at startup was not focused a second later, and a replay
reported success while driving something else." This is the same thing, one
window deeper.

**Corroboration that this is not new.** `testapp/actions/win/P5-stacked-alerts.csv`
deliberately contains no OK-button coordinate, and says why: an alert is a
separate top-level window whose position GTK chooses. That file worked around
the wall; it did not identify it. No action file in this tree has ever dismissed
a GTK alert.

**What a fix has to do**, and why "pick the smallest" is not it: the right window
is the one that is *modal for* the app's window, not the smallest or the newest.
`GetWindow(hwnd, GW_ENABLEDPOPUP)` names it directly — Windows already tracks
which popup of a window is enabled and taking input — and returns NULL when
there is none, which is the ordinary case. Until then, no action file can test
anything that appears in a dialog: not an alert's buttons, not Escape, not a
file dialog's contents.

**Verify any fix by capture, not by log.** P31 logs `alert opened` and has no
line for a dismissal, so the log looks identical whether Escape worked or not.
A desktop capture — not `screenshot.zsh -w`, which matches by title and finds
only the main window — shows the alert plainly.

---

**6. 非 GTK 的問題：Win32 合成器無法定址 modal dialog，並且會從它手上搶走焦點**

**2026-09-03 於 Windows / GtkBackend 實測**，以
`testapp/actions/win/P31-tab-and-escape.csv` 驅動 P31。

Escape 無法關閉 `.alert`。alert 持續開啟，主視窗的控制項在它後方變灰，而重放不回報任何異常。

**這不是 GTK 忽略了該按鍵。** 同一次執行即證明鍵盤路徑暢通：`key tab` 之後的 `key space`
啟動了按鈕，`p31-debug-events.log` 記錄了 `button clicked count=1`。按鍵確實送達。

**是合成器送給了錯的視窗。** `Win32Synthesiser.ownWindow()`（Win32Synthesiser.swift:365-400）
列舉本行程可見的 top-level 視窗，回傳**面積最大**的那一個。`Gtk.MessageDialog` 是獨立的
top-level 視窗，且小於擁有它的視窗，因此該啟發式永遠選不到它。更糟的是，合成器接著對那個主視窗
呼叫 `SetForegroundWindow`，**等於把焦點從 modal 手上搶走**，再把 Escape 投遞給一個並未在等待它
的視窗。

該檔案自己的註解早已描述過這個失敗形態在另一個平台上的樣子：「啟動時 present 的視窗一秒後並未
取得焦點，而重放回報成功，實際驅動的卻是別的程式。」這是同一件事，只是深了一層視窗。

**修正必須做到什麼**，以及為何「挑最小的」不是答案：正確的視窗是「對 app 視窗而言為 modal」的
那一個，而非最小或最新的。`GetWindow(hwnd, GW_ENABLEDPOPUP)` 直接指名它——Windows 本就追蹤某個
視窗的哪一個 popup 已啟用並正在接收輸入——且在沒有時回傳 NULL，那是常態。在此之前，任何動作檔都
無法測試出現在對話框中的東西：alert 的按鈕、Escape、檔案對話框的內容，都不行。

**驗證修正時請用擷圖，不要用 log。** P31 會記錄 `alert opened`，卻沒有任何一行對應關閉，因此無論
Escape 是否生效，log 看起來完全一樣。

### Resolved 2026-09-04, and two claims above were wrong

The wall is down. What removed it was a **dump before a fix**: a candidate list
printed from inside `Win32Synthesiser.ownWindow()` itself, behind `-actionfile`
plus `--debug`, so it reports the real decision at the real moment rather than an
approximation from another process. Driving P1 once produced this, with the sheet
up:

```
window 0x…0065a 648x549@234,234 class=gdkSurfaceToplevel enabled=true  owner=none      enabledPopup=0x…50d4c
window 0x…50d4c 428x174@344,421 class=gdkSurfaceToplevel enabled=true  owner=0x…0065a  enabledPopup=none
```

Two things written above as findings are refuted by it, and both are left in
place rather than edited away, because a plausible wrong diagnosis is worth more
on the page than a silent correction:

- **"the main window's controls grey out behind it" / focus is stolen from a
  disabled owner.** The owner measures `enabled=true`. GTK4 does modality with
  its own grab and never calls `EnableWindow` on Win32. The greying is GTK's
  styling, not a Windows window state, and code that tested `IsWindowEnabled`
  would have found nothing wrong.
- **`GW_ENABLEDPOPUP` "was tried and was ineffective"** — the reason it was
  removed. It is not ineffective: the owner reports the sheet by handle,
  exactly as documented. It was removed without any dump to say whether the call
  had answered, so an unrelated failure was attributed to it.

**Why the first attempt genuinely did nothing, which is the part worth keeping.**
The defect was in *two* places, and fixing either alone is invisible:

1. `ownWindow()` returned the largest-area window, and a dialog is smaller than
   its owner — 428x174 against 648x549 — so the owner always won.
2. `ActionFileReplay` reads geometry **once** (`ActionFileReplay.swift:116`) and
   `Synthesiser.replay(_:in:)` reuses it for every action. So fixing (1) only
   changes which window `SetForegroundWindow` targets; every coordinate stays
   resolved against the owner's frame origin.

Fixed by following `GW_ENABLEDPOPUP` transitively (dialogs nest — P1's sheet
opens another) and by re-measuring geometry **when the target window changes and
only then**. Per action would break the case the code documents: a file that
drags a window by its title bar and then clicks would measure that click against
the new position. A window that merely moved keeps its `HWND`, so those files are
untouched.

Proven by arithmetic on measured numbers, not by "it looked right". With the
sheet at `428x174@318,395`, a second click written as `frame=(324,330)` resolved
to screen `(642,725)` — 318+324 and 395+330. Before the change the same row
resolved against the owner.

### A second defect, which this uncovered and which was a suspicion since 2026-09-03

`prepareForReplay` pins its window `HWND_TOPMOST`. **A dialog opened afterwards is
not pinned, so the app's own main window covers its own modal.** Measured
2026-09-04: P1's sheet existed at `428x174@162,239` — Win32 reported it and
`GW_ENABLEDPOPUP` named it — and a desktop capture taken while it was up shows no
sheet at all, only the main window's buttons occupying that rectangle.

`testapp/actions/win/P5-stacked-alerts.csv` has carried this as a stated risk
since 2026-09-03: *"If the capture shows no alert, that is the first thing to
suspect rather than a click that missed."* It was right. Fixed by re-running
`prepareForReplay` when the target window changes, which pins the new target.

### The symptom this section opens with was not a bug either

The first paragraph reports *"Escape does not dismiss a `.alert`. The alert stays
open … and the replay reports nothing wrong."* That is the behaviour GtkBackend
is written to have, in **two** independent places:

- `createAlert` installs a shortcut controller whose entire purpose is to
  *"disable the default Escape-to-close action"* (`GtkBackend.swift:3287`).
- `present` drops response id `-4` with *"Ignore escape key for now"*
  (`GtkBackend.swift:3339`).

Both give the same reason: until an alert knows which of its buttons is the
cancel action, Escape has nothing correct to do. So an alert still standing after
Escape is a **pass**, and "the replay reports nothing wrong" was accurate — there
was nothing wrong to report. The diagnosis that followed happened to be right
about the synthesiser, but it was reached from a symptom that was never a defect,
and `testapp/actions/win/P31-tab-and-escape.csv` then asserted the opposite of
the backend's stated behaviour for a day.

What P31 can now assert instead, and could not before 2026-09-04: pressing the
alert's **OK** button. Measured, running that file:

```
P31 … alert opened
P31 … alert OK
```

The app writes `alert OK` from the button's own handler, so nothing but a press
on that button produces it. That is the first time any file in this tree has
pressed a control inside a dialog.

### Retracted the same day: "P1's first synthesised click is consumed"

**There is no such defect.** This section carried one for about two hours on
2026-09-04, with a table of measurements behind it, and every number in it was
real. The conclusion was still false, and the way it went wrong is worth more
than the claim was.

What was written, and what it rested on — interleaved, three rounds each:

| file | sheet observed |
|---|---|
| one click on "Open root sheet" | **0/3** |
| the same click twice, 600 ms apart | **3/3** |
| a `move` to the button, then one click | **0/3** |

Read as: only a preceding *click* helps, so the first press is being swallowed.
It even survived a control — `P35`'s single click gives `count=1` **3/3** — which
made it look app-specific rather than like a mistake.

**The instrument had stopped, and the column head says "sheet observed" for a
reason.** Identity is checked *before* each action, so a file whose last action
is the sleep that waits for the dialog never observes it: the check ran while it
was still mapping. The one thing that used to look afterwards was
`finishReplay`, which called `ownWindow()` and dumped as a side effect — and the
fix two sections up replaced that call with a `visibleWindows()` loop. Correct in
itself, and a real fix. It also silently deleted the only observation point after
the last action.

So the two-click file was not proving that two clicks are needed. It was proving
that a *second action* gives the checker a second chance to look.

Re-measured with one extra `sleep` row, so a check runs after the sheet has
mapped: **one click, 3/3.** The click had worked every time.

`WindowFromPoint` at the moment of the press returns our own window and equals
`GetForegroundWindow()`, so the press was never misdirected either — a fact that
would have refuted the claim on its own, and was only gathered afterwards.

`finishReplay` now dumps again, deliberately and with the reason written beside
it. `GetActiveWindow()` is printed too but says nothing here: it is per
*thread*, and the replay runs on a background queue, so `active=none` is expected
and is not evidence of anything.

**The general shape, which this file has now recorded three times in one day:** a
negative that came from a check that was no longer running. `-tail 45` on a
47-row file, a `grep` for a string that appears either way, and now a diagnostic
removed by an unrelated fix. None of them errored. All three produced a plausible
number. The guard is the same each time — *establish that the check can still
fail before believing that it passed* — and it is cheap: one extra action row was
the whole cost here.

---

### 2026-09-04 已解決，且上文有兩項主張是錯的

這道牆倒了。讓它倒下的是**先傾印、後修正**：在 `Win32Synthesiser.ownWindow()` 內部印出候選清單，
置於 `-actionfile` 加 `--debug` 之後，因此它回報的是**真正的決策、在真正的時刻**，而不是從另一個
行程做出的近似。驅動 P1 一次，在 sheet 開啟時得到：

```
window 0x…0065a 648x549@234,234 class=gdkSurfaceToplevel enabled=true  owner=none      enabledPopup=0x…50d4c
window 0x…50d4c 428x174@344,421 class=gdkSurfaceToplevel enabled=true  owner=0x…0065a  enabledPopup=none
```

上文有兩項被當成「發現」寫下的東西被它推翻，而兩者都**原文保留**而非改寫，因為一個看似合理的錯誤
診斷留在頁面上，比一次無聲的更正更有價值：

- **「主視窗的控制項在它後方變灰」／焦點被從一個已停用的擁有者手上搶走。** 擁有者實測為
  `enabled=true`。GTK4 以自己的 grab 處理 modality，在 Win32 上從不呼叫 `EnableWindow`。變灰是
  GTK 的樣式，不是 Windows 的視窗狀態；一段去檢查 `IsWindowEnabled` 的程式碼，什麼異常都找不到。
- **`GW_ENABLEDPOPUP`「試過且無效」** ——那正是它被移除的理由。它並非無效：擁有者確實以 handle
  指名了該 sheet，與文件所述完全一致。它是在**沒有任何傾印可以判斷「該呼叫是否回答了」**的情況下
  被移除的，於是一項無關的失敗被歸咎到它頭上。

**第一次嘗試之所以真的毫無作用，這才是值得留下的部分。** 缺陷位於**兩個**地方，只修其中之一是
看不見的：

1. `ownWindow()` 回傳面積最大的視窗，而對話框比其擁有者更小——428x174 對 648x549——因此擁有者
   永遠勝出。
2. `ActionFileReplay` 只讀取幾何**一次**（`ActionFileReplay.swift:116`），而
   `Synthesiser.replay(_:in:)` 對每一個動作重複使用它。因此只修 (1)，改變的僅是
   `SetForegroundWindow` 指向哪個視窗；每一個座標仍以擁有者的框架原點來解析。

修法是遞移地追隨 `GW_ENABLEDPOPUP`（對話框會巢狀——P1 的 sheet 會再開一個），並且**只在目標視窗
改變時**重新量測幾何。逐動作重量會破壞程式碼所載明的情境：一份「以標題列拖曳視窗後再點擊」的檔案，
會把該次點擊對到新位置。而僅僅移動過的視窗其 `HWND` 不變，因此那些檔案完全不受影響。

以實測數字的**算術**證明，而非「看起來對」。sheet 位於 `428x174@318,395` 時，一列寫成
`frame=(324,330)` 的第二次點擊解析為螢幕 `(642,725)`——即 318+324 與 395+330。改動之前，同一列
是對著擁有者解析的。

### 第二個缺陷，由此順帶揭出，且自 2026-09-03 起就是一項懷疑

`prepareForReplay` 會把它的視窗釘為 `HWND_TOPMOST`。**其後才開啟的對話框不會被釘，於是 app 自己的
主視窗蓋住了自己的 modal。** 2026-09-04 實測：P1 的 sheet 確實存在於 `428x174@162,239`——Win32
如此回報，`GW_ENABLEDPOPUP` 也指名了它——而在它開啟期間所取的桌面擷圖中，完全看不到任何 sheet，
那個矩形裡只有主視窗的按鈕。

`testapp/actions/win/P5-stacked-alerts.csv` 自 2026-09-03 起就把這件事寫成明列的風險：
「**若擷圖看不到 alert，這是第一個該懷疑的東西，而不是懷疑點擊沒中。**」它是對的。修法是在目標
視窗改變時重新執行 `prepareForReplay`，以釘住新的目標。

### 本節開頭的那個症狀，也不是缺陷

第一段回報：「**Escape 無法關閉 `.alert`。alert 持續開啟……而重放不回報任何異常。**」那正是
GtkBackend 被寫成要有的行為，而且出現在**兩個**獨立的地方：

- `createAlert` 安裝了一個 shortcut controller，其存在的全部目的就是「**停用預設的
  Escape 關閉行為**」（`GtkBackend.swift:3287`）。
- `present` 會丟棄 response id `-4`，註明「**Ignore escape key for now**」
  （`GtkBackend.swift:3339`）。

兩者給的理由相同：在 alert 尚不知道自己哪一顆按鈕是取消動作之前，Escape 沒有正確的事可做。
因此**按下 Escape 後 alert 仍然站著是通過**，而「重放不回報任何異常」也是準確的——本來就沒有
異常可報。其後的診斷雖然在「合成器」這件事上碰巧是對的，但它是從一個**從來就不是缺陷**的症狀
出發的；而 `testapp/actions/win/P31-tab-and-escape.csv` 因此有整整一天在主張與 backend 明文
行為相反的事。

P31 現在能改為主張、而在 2026-09-04 之前寫不出來的東西：按下 alert 的 **OK** 按鈕。實測，
以該檔案執行：

```
P31 … alert opened
P31 … alert OK
```

`alert OK` 是 app 從該按鈕自己的 handler 寫出的，因此除了「按到那一顆」之外，沒有任何東西能
產生它。這是本樹中第一次有檔案按下了對話框**內部**的控制項。

### 同日撤回：「P1 的第一次合成點擊被吞掉」

**不存在這個缺陷。** 2026-09-04 當天，本節帶著這樣一個缺陷約兩個小時，背後還附有一張量測表，
而表中每一個數字都是真的。結論依然是**假的**；而它出錯的方式，比那個主張本身更有價值。

當初寫下的內容，以及它所依據的東西——交錯量測，各三輪：

| 檔案 | 是否**觀察到** sheet |
|---|---|
| 對「Open root sheet」點一次 | **0/3** |
| 同一個點擊做兩次，相隔 600 毫秒 | **3/3** |
| 先 `move` 到按鈕，再點一次 | **0/3** |

當時的解讀是：只有先來一次「點擊」才有用，所以第一次按壓被吞掉了。它甚至通過了一個對照組
——`P35` 的單次點擊給出 `count=1`，**3/3**——這讓它看起來像是「該 app 專有」，而非一個錯誤。

**是儀器停了；而那一欄的標題寫「是否**觀察到**」正是原因。** identity 是在每個動作**之前**
檢查的，因此一份「最後一個動作是等待對話框的 sleep」的檔案，永遠不會觀察到它：檢查發生在它
還在 map 的時候。唯一會在其後再看一眼的東西是 `finishReplay`——它呼叫 `ownWindow()`，而後者
會順帶輸出傾印——而上面兩節的那個修正，把該呼叫換成了 `visibleWindows()` 迴圈。那本身是正確
的，也是一項真正的修正。它同時**靜默地**刪掉了最後一個動作之後唯一的觀測點。

所以雙擊版檔案證明的並不是「需要點兩次」，而是「**多一個動作**，就讓檢查器多一次觀察的機會」。

加一列 `sleep`，讓檢查在 sheet map 之後才執行，重新量測：**單擊，3/3。** 那個點擊一直都有效。

按壓當下的 `WindowFromPoint` 回傳的是我們自己的視窗，且等於 `GetForegroundWindow()`，因此那次
按壓也從來沒有被送錯——這項事實單獨就足以推翻該主張，只是它是事後才被收集的。

`finishReplay` 現在會重新輸出傾印，是刻意的，理由就寫在旁邊。`GetActiveWindow()` 也一併印出，
但它在此什麼也說不了：它是**逐執行緒**的，而重放跑在背景佇列上，因此 `active=none` 是預期結果，
不構成任何證據。

**共通的形狀，本檔一天之內已記錄三次：** 一個來自「已不再執行的檢查」的否定結果。47 列的檔案上
用 `-tail 45`、grep 一個兩種情況下都會出現的字串，以及現在這個「被一項無關修正移除的診斷」。
三者都沒有報錯，三者都產出了合理的數字。防範方式每次都相同——**在相信一項檢查通過之前，先確認
它仍然「有可能失敗」**——而且很便宜：這一次的全部代價，就是多一列動作。
