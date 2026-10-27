# The Windows test machine (Win11) and reaching it from the Mac

Written 2026-10-24 from testapp/gpu_select.zsh, testapp/sweep-test/sweep_drive.zsh,
heartbeats/heartbeat.zsh, mistakes.md (multissh, 2026-09-09), commits 1d27b43d,
3015e005, 57dc3a69, and results.csv2 (windows rows of 2026-10-19 to 2026-10-23).

## The machine

- Recorded as **Win11** in the results `device` column. The sweep drivers write
  Win11 or Win10 from the Windows build number, never the computer name, which
  carries the owner's name (1d27b43d, 3015e005).
- ASUS TUF A15 (FA507NV): AMD Radeon iGPU plus NVIDIA GeForce RTX 4060 Laptop
  GPU (Optimus), a 144 Hz 1920x1080 panel, display scale **125%** in the
  October runs (earlier passes used 100%).
- An exe with no GPU preference runs on the AMD iGPU. With the AMD adapter
  disabled in Device Manager, DXGI listed WARP first and WGL fell back to GDI
  Generic OpenGL 1.1 (2026-10-07). `gpu_select.zsh` (with `gpu_select.ps1` for
  elevation) sets per-app preferences and enables or disables the AMD adapter.
- ASUS utilities (`AsMonitorControl.exe`, `AsHotplugCtrl.exe`, `AsusUpdater.exe`)
  and `GameInputSvc.exe` block injected input; see
  [harness-input-injection.md](harness-input-injection.md).
- The workstation locks itself. Judge it by a desktop capture taken at the same
  moment as the result; `LogonUI.exe` in `tasklist` did not track the lock.
- Paths: checkout `C:\Users\<user>\proj\swift-cross-ui`; GTK in `C:/gtk4` and
  `C:/gtk4-accesskit`; Windows SDK 10.0.22621.0; WinDbg (cdb) is installed via
  winget. A WSL Ubuntu copy of the checkout lives on the same machine (see the
  WSL notes).

## Reaching it from the Mac

- `multissh -F ~/.multissh/generated/config2Win winnode "<command>"` runs a
  command there (exec channel). **The config file is required** (`-F` or `-f`,
  the same option; the file says `Host *`, so any host name works); without it the
  name does not resolve (2026-09-09).
- Example: the GTK three-way deck captured P12 and P14 on Win11 from the Mac
  with `capture_gtk.zsh --win --build P12 P14` over multissh (57dc3a69,
  2026-10-23).
- Neither tmux nor screen exists on the Windows side, so a live Claude session
  there cannot be typed into; the Windows side runs its own session and records
  its results.
- Code moves between the machines through git: both push `develop` to `origin`
  (rebase, no merge commits); `sync_all.zsh` pulls with rebase and autostash.
- `/Volumes/Windows/proj_Win` on the Mac is a local disk, not a mount of Win11.

## How to apply

- Before a timing result: note the GPU (`TEST_GPU=default` or the dGPU), the
  display scale, and whether the display was on and unlocked.
- After any session that ran injected input, check that a desktop capture shows
  the app in front; otherwise treat negatives as unproven.

---

# Windows 測試機(Win11)以及從 Mac 連過去

2026-10-24 依 testapp/gpu_select.zsh、testapp/sweep-test/sweep_drive.zsh、heartbeats/heartbeat.zsh、mistakes.md
(multissh,2026-09-09)、1d27b43d、3015e005、57dc3a69,以及 results.csv2(2026-10-19 至 2026-10-23 的 windows 列)
寫成。

## 機器

- 在結果的 `device` 欄記為 **Win11**。sweep 腳本依 Windows build 號寫入 Win11 或 Win10,從不寫電腦名稱，因為電腦
  名稱帶有擁有者的名字(1d27b43d、3015e005)。
- ASUS TUF A15(FA507NV):AMD Radeon 內顯加 NVIDIA GeForce RTX 4060 Laptop GPU(Optimus),144 Hz 1920x1080 面板，
  十月的執行中顯示縮放為 **125%**(較早幾輪用 100%)。
- 沒有 GPU 偏好的 exe 跑在 AMD 內顯上。在裝置管理員停用 AMD 顯示卡時,DXGI 把 WARP 列在第一個,WGL 退回 GDI Generic
  OpenGL 1.1(2026-10-07)。`gpu_select.zsh`(提權時配合 `gpu_select.ps1`)設定逐 app 偏好，並啟用或停用 AMD
  顯示卡。
- ASUS 工具程式(`AsMonitorControl.exe`、`AsHotplugCtrl.exe`、`AsusUpdater.exe`)與 `GameInputSvc.exe` 會擋住注入
  的輸入；見 [harness-input-injection.md](harness-input-injection.md)。
- 工作站會自行鎖定。要以與結果同一時刻的桌面擷取判斷;`tasklist` 中的 `LogonUI.exe` 並不反映鎖定狀態。
- 路徑:checkout 在 `C:\Users\<user>\proj\swift-cross-ui`;GTK 在 `C:/gtk4` 與 `C:/gtk4-accesskit`;Windows SDK
  10.0.22621.0;WinDbg(cdb)已透過 winget 安裝。同一台機器上的 WSL Ubuntu 另有一份 checkout(見 WSL 筆記)。

## 從 Mac 連過去

- `multissh -F ~/.multissh/generated/config2Win winnode "<命令>"` 在那裡執行命令(exec 通道)。**設定檔是必要
  的**(`-F` 與 `-f` 是同一個選項；該檔寫的是 `Host *`,主機名稱任意);少了它名稱無法解析(2026-09-09)。
- 例子:GTK 三方對照簡報在 Mac 上經 multissh 以 `capture_gtk.zsh --win --build P12 P14` 擷取了 Win11 上的 P12 與
  P14(57dc3a69,2026-10-23)。
- Windows 端沒有 tmux 也沒有 screen,所以無法把文字打進那裡執行中的 Claude 工作階段;Windows 端自己跑一個工作階段
  並記錄結果。
- 程式碼經 git 在兩台機器間移動：兩邊都把 `develop` 推到 `origin`(rebase,不產生 merge commit);`sync_all.zsh`
  以 rebase 與 autostash 拉取。
- Mac 上的 `/Volumes/Windows/proj_Win` 是本機磁碟，不是 Win11 的掛載。

## 如何運用

- 記錄計時結果前：註明 GPU(`TEST_GPU=default` 或獨顯)、顯示縮放，以及螢幕是否開啟且未鎖定。
- 任何跑過注入輸入的工作階段之後，確認桌面擷取顯示 app 在最前面；否則把否定的結果視為未證實。
