# WSLg: the GPU path, -render hw|sw, and the adapter list

Written 2026-10-24 from `testapp/install_tool_wsl.zsh`, `test_common.zsh`
(`wsl_renderer_preflight`), 8de98ab5, 752c9d9a and queue.md (2026-10-07 entry).

## What

- OpenGL under WSLg is Mesa's d3d12 Gallium driver over `/dev/dxg` and
  `libdxcore.so`/`libd3d12.so` in `/usr/lib/wsl/lib`. No DRM render node is
  needed: GTK and Wayland EGL render on the RTX 4060 with no `/dev/dri`.
  Checking `/dev/dri` gave the wrong answer once; `eglinfo -p wayland -B`
  measures the renderer instead.
- Vulkan stays software (llvmpipe): Ubuntu's Mesa has no dzn ICD. GSK may
  reject CPU Vulkan and then use hardware GL; that is the normal path.
- GTK gets an OpenGL ES context there (queue.md records ES 3.0; P72 reports
  "D3D12 (NVIDIA GeForce RTX 4060 Laptop GPU) / OpenGL ES 3.1"). A
  `#version 330 core` shader is rejected and the view goes blank with nothing
  reported; the 3D view now picks `330 core` or `300 es` per context and
  reports a shader failure once on stderr (P72, P76, P77, 2026-10-07).

## Selecting the GPU

- WSL ignores Windows' per-exe `UserGpuPreferences`; the adapter is chosen with
  `MESA_D3D12_DEFAULT_ADAPTER_NAME` (case-insensitive substring).
- `install_tool_wsl.zsh` tries Mesa's default, then NVIDIA, AMD, Intel, keeps
  the first that `eglinfo` proves is `D3D12 ...`, and writes it to
  `/etc/profile.d/swift-cross-ui-wslg-gpu.sh`, plus a loader line in
  `/etc/zsh/zshenv` (Ubuntu's zsh does not read `/etc/profile.d`).
- GtkBackend lists adapters through DXCore (`gtk_dxcore.c`, loaded at run
  time). WSL has no DRM cards for its GPUs; the only card seen was `vgem`, the
  kernel's virtual GEM device, which `drmCards` now skips with `vkms`. P68
  under WSL: "NVIDIA GeForce RTX 4060 Laptop GPU" and "AMD Radeon(TM)
  Graphics [low power]" (8de98ab5).

## -render hw|sw

`test.zsh --wsl` (and `sweep_drive_wsl.zsh`) take `-render hw` (default) or
`-render sw`:

| mode | environment | preflight expects |
|---|---|---|
| hw | `GALLIUM_DRIVER=d3d12 MESA_D3D12_DEFAULT_ADAPTER_NAME=NVIDIA GSK_DEBUG=renderer` | `D3D12 ...` |
| sw | `LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe GSK_DEBUG=renderer` | `llvmpipe ...` |

`wsl_renderer_preflight` runs `eglinfo -p wayland -B` with that environment
before the build and fails the run if the renderer does not match.
`TEST_RENDER_ENV` replaces the environment. `-render` with a non-WSL target is
refused. After the run, `print_renderer_wsl` prints GSK's "Not using" /
"renderer is" lines from the app's stderr.

## WebKitGTK

WebKit's sandboxed web process aborts with "Could not create surfaceless EGL
display" on hardware EGL under WSL. WSL kernel 6.18 added `/dev/dri` render
nodes (root:video/render, 660) that this user cannot open, so a probe that
only saw `/dev/dxg` succeed chose hardware and P27/P38 drew an empty grey
frame. `gtk_webkit.c` keeps hardware GL for WebKit only when the user can open
a render node, otherwise llvmpipe (752c9d9a, 2026-10-20).

## Measured rates

P96 (results.csv2 / queue.md row 27): WSLg refreshes at 60 Hz; dots alone
59.7 fps; the driven panel 48-49 fps in the first 3 s after the CSS and
warm-up fixes, 59 fps after the first-frame wait
([d3d12-shader-stall.md](d3d12-shader-stall.md)).

## Limits

- Older notes saying "WSL has no GPU path, GTK is on llvmpipe"
  (testapp/UI-test-plan-en.md, P6 section) predate the d3d12 setup and are
  superseded.
- Measured with Mesa 26.0.8 on Ubuntu 26.04; the render-node permissions
  depend on the WSL kernel version.

---

# WSLg:GPU 路徑、-render hw|sw 與介面卡清單

2026-10-24 依 `testapp/install_tool_wsl.zsh`、`test_common.zsh`(`wsl_renderer_preflight`)、8de98ab5、752c9d9a 與
queue.md(2026-10-07 的項目)寫成。

## 是什麼

- WSLg 下的 OpenGL 是 Mesa 的 d3d12 Gallium 驅動，經由 `/dev/dxg` 與 `/usr/lib/wsl/lib` 中的
  `libdxcore.so`/`libd3d12.so`。不需要 DRM render node:沒有 `/dev/dri` 時,GTK 與 Wayland EGL 照樣在 RTX 4060 上
  算繪。檢查 `/dev/dri` 曾得出錯誤答案;`eglinfo -p wayland -B` 才是直接量 renderer。
- Vulkan 仍是軟體(llvmpipe):Ubuntu 的 Mesa 沒有 dzn ICD。GSK 可能先拒絕 CPU Vulkan,再使用硬體 GL;這是正常路徑。
- GTK 在那裡拿到的是 OpenGL ES context(queue.md 記為 ES 3.0;P72 回報「D3D12 (NVIDIA GeForce RTX 4060 Laptop GPU) /
  OpenGL ES 3.1」)。`#version 330 core` 的 shader 會被拒絕，畫面空白且什麼都不回報;3D view 現在依 context 選
  `330 core` 或 `300 es`,shader 失敗時在 stderr 回報一次(P72、P76、P77,2026-10-07)。

## 選擇 GPU

- WSL 不理會 Windows 依執行檔設定的 `UserGpuPreferences`;介面卡由 `MESA_D3D12_DEFAULT_ADAPTER_NAME` 選定(不分大小
  寫的子字串比對)。
- `install_tool_wsl.zsh` 依序試 Mesa 預設、NVIDIA、AMD、Intel,保留第一個經 `eglinfo` 證實為 `D3D12 ...` 的，寫入
  `/etc/profile.d/swift-cross-ui-wslg-gpu.sh`,並在 `/etc/zsh/zshenv` 加一行 loader(Ubuntu 的 zsh 不讀
  `/etc/profile.d`)。
- GtkBackend 經 DXCore 列出介面卡(`gtk_dxcore.c`,執行時載入)。WSL 的 GPU 沒有 DRM card;唯一看到的是 `vgem`,
  即核心的虛擬 GEM 裝置,`drmCards` 現在會連同 `vkms` 一起略過。WSL 下的 P68:「NVIDIA GeForce RTX 4060 Laptop GPU」
  與「AMD Radeon(TM) Graphics [low power]」(8de98ab5)。

## -render hw|sw

`test.zsh --wsl`(以及 `sweep_drive_wsl.zsh`)接受 `-render hw`(預設)或 `-render sw`,環境變數與預檢期望值見上表。
`wsl_renderer_preflight` 在建置前以該環境執行 `eglinfo -p wayland -B`,renderer 不符就讓這次執行失敗。
`TEST_RENDER_ENV` 可取代整組環境。目標不是 WSL 時給 `-render` 會被拒絕。執行後,`print_renderer_wsl` 從 app 的
stderr 印出 GSK 的「Not using」/「renderer is」行。

## WebKitGTK

在 WSL 的硬體 EGL 上,WebKit 沙箱中的 web 行程會以「Could not create surfaceless EGL display」abort。WSL 核心 6.18
新增了 `/dev/dri` render node(root:video/render,660),這個使用者打不開；只看到 `/dev/dxg` 探測成功的檢查選了硬體，
P27/P38 於是只畫出空的灰框。`gtk_webkit.c` 只在使用者打得開 render node 時才讓 WebKit 用硬體 GL,否則用 llvmpipe
(752c9d9a,2026-10-20)。

## 量到的數字

P96(results.csv2 / queue.md 第 27 列):WSLg 更新率 60 Hz;只有圓點時 59.7 fps;CSS 與預熱修正後,driven 面板前
3 秒 48–49 fps,第一幀等待之後 59 fps(見 [d3d12-shader-stall.md](d3d12-shader-stall.md))。

## 限制

- 較舊的筆記寫著「WSL 完全沒有 GPU 路徑,GTK 跑在 llvmpipe」(testapp/UI-test-plan-en.md 的 P6 段落),早於 d3d12
  設定，已被取代。
- 量測於 Ubuntu 26.04 上的 Mesa 26.0.8;render node 的權限取決於 WSL 核心版本。
