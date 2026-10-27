# WSL: GtkBackend under WSLg

GtkBackend as Linux GTK 4 inside WSL2 (Ubuntu 26.04) on the Windows machine,
shown on the Windows desktop through WSLg. Runs are driven from the Windows
checkout with `zsh testapp/test.zsh Pn --wsl`. Written 2026-10-24.

## Rendering and GPU

- [d3d12-shader-stall.md](WSL/d3d12-shader-stall.md) -- the first frame with new draw state waits 560-870 ms because Mesa's d3d12 driver caches nothing across processes; the renderer warm-up and its limits.
- [mesa-d3d12-issue.md](WSL/mesa-d3d12-issue.md) -- the Mesa issue draft (not filed): source reading, perf numbers, suggested fixes.
- [first-frame-stall.c](WSL/first-frame-stall.c) -- standalone GTK 4 reproduction of that stall.
- [gpu-and-renderer.md](WSL/gpu-and-renderer.md) -- d3d12 over `/dev/dxg`, GLES contexts, adapter choice and the DXCore list, `-render hw|sw`, WebKit on llvmpipe.

## Display server and desktop

- [copy-mode.md](WSL/copy-mode.md) -- after WSLg restarts itself every capture is black and `test.zsh` exits 7; the keeper window prevents it, only `wsl --shutdown` cures it.
- [x11-and-wayland.md](WSL/x11-and-wayland.md) -- every run uses `GDK_BACKEND=x11 GTK_CSD=1`; what WSLg's window manager lacks and how `.floating`, Super, menus and xdotool work around it.
- [file-dialog-portal.md](WSL/file-dialog-portal.md) -- `GtkFileDialog` goes to xdg-desktop-portal-gtk, which needs the display variables imported before each run.
- [theme-and-fonts.md](WSL/theme-and-fonts.md) -- dark mode read from Windows' registry, Segoe UI from `/mnt/c`, forced dark in tests, the CJK and emoji fonts a stock image lacks.

## Harness

- [harness.md](WSL/harness.md) -- what one `test.zsh --wsl` run does, the rules for crossing `wsl.exe`, exit codes 1/6/7/64, the sweep and measuring tools.
- [wsl-checkout.md](WSL/wsl-checkout.md) -- `/home/lowei/proj/swift-cross-ui` is a non-git copy fed by `rsync_WSL.zsh`; deletions do not propagate.

## Setup and host

- [toolchain-install.md](WSL/toolchain-install.md) -- `install_tool_wsl.sh`: Swift 6.4.1 (24.04 build plus compat libraries on 26.04), packages, and the rules learned from its failures.
- [host-disk-and-memory.md](WSL/host-disk-and-memory.md) -- fstrim that actually runs under systemd, the sparse vhdx, C: free space and `.wslconfig` memory settings.

## Open as of 2026-10-24

- The remaining first-frame wait under d3d12 (about 560 ms): needs a persistent d3d12 cache in Mesa.
- Whether WSLg forwards touch to X11 clients: unverified.
- Whether the installed portal makes live colour-scheme changes visible to GTK under WSLg: unmeasured.
- Orca speech for #123 (P69 transcript): tools installed 2026-10-23, transcript not taken.

---

# WSL:WSLg 下的 GtkBackend

GtkBackend 以 Linux GTK 4 的形式執行於 Windows 機器上的 WSL2(Ubuntu 26.04),經由 WSLg 顯示在 Windows 桌面上。
測試由 Windows checkout 以 `zsh testapp/test.zsh Pn --wsl` 驅動。2026-10-24 寫成。

## 算繪與 GPU

- [d3d12-shader-stall.md](WSL/d3d12-shader-stall.md)——帶有新繪圖狀態的第一幀要等 560–870 毫秒，因為 Mesa 的 d3d12 驅動不跨行程快取任何東西；算繪預熱及其限制。
- [mesa-d3d12-issue.md](WSL/mesa-d3d12-issue.md)——Mesa issue 草稿(尚未提交):原始碼解讀、perf 數字、建議修法。
- [first-frame-stall.c](WSL/first-frame-stall.c)——重現該卡頓的獨立 GTK 4 程式。
- [gpu-and-renderer.md](WSL/gpu-and-renderer.md)——經 `/dev/dxg` 的 d3d12、GLES context、介面卡選擇與 DXCore 清單、`-render hw|sw`、WebKit 改用 llvmpipe。

## 顯示伺服器與桌面

- [copy-mode.md](WSL/copy-mode.md)——WSLg 自行重啟後每張擷取都是黑的,`test.zsh` 以 7 結束;keeper 視窗可預防，只有 `wsl --shutdown` 能恢復。
- [x11-and-wayland.md](WSL/x11-and-wayland.md)——每次執行都用 `GDK_BACKEND=x11 GTK_CSD=1`;WSLg 視窗管理員缺少什麼，以及 `.floating`、Super、選單與 xdotool 如何繞過。
- [file-dialog-portal.md](WSL/file-dialog-portal.md)——`GtkFileDialog` 會交給 xdg-desktop-portal-gtk,每次執行前要先匯入顯示變數。
- [theme-and-fonts.md](WSL/theme-and-fonts.md)——深色模式讀自 Windows 登錄、Segoe UI 取自 `/mnt/c`、測試強制深色、原始映像缺少的 CJK 與 emoji 字型。

## Harness

- [harness.md](WSL/harness.md)——一次 `test.zsh --wsl` 做了什麼、穿越 `wsl.exe` 的規則、結束碼 1/6/7/64、sweep 與量測工具。
- [wsl-checkout.md](WSL/wsl-checkout.md)——`/home/lowei/proj/swift-cross-ui` 是由 `rsync_WSL.zsh` 餵送的非 git 複本；刪除不會傳播。

## 安裝與主機

- [toolchain-install.md](WSL/toolchain-install.md)——`install_tool_wsl.sh`:Swift 6.4.1(26.04 上的 24.04 版本加相容函式庫)、套件，以及從失敗中學到的規則。
- [host-disk-and-memory.md](WSL/host-disk-and-memory.md)——在 systemd 下真正會執行的 fstrim、稀疏 vhdx、C: 剩餘空間與 `.wslconfig` 記憶體設定。

## 至 2026-10-24 仍未解決

- d3d12 下剩下的第一幀等待(約 560 毫秒):需要 Mesa 為 d3d12 提供持久快取。
- WSLg 是否把觸控轉給 X11 client:未驗證。
- 已安裝的 portal 是否讓 GTK 在 WSLg 下看得到即時的配色變更：未量測。
- #123 的 Orca 語音(P69 逐字稿):工具已於 2026-10-23 安裝，逐字稿尚未取得。
