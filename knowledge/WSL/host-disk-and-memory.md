# WSL host: fstrim, a sparse vhdx, C: free space and .wslconfig

Written 2026-10-24 from 46b6d83e, a44f33e8,
`testapp/test_support/check_wsl_host.zsh`, `testapp/install_tool_wsl.zsh`
and `testapp/test_support/host/` (`wslconfig`, `README.md`).

## What

Three Windows-side settings decide whether WSL builds keep running:

- **The distribution's `ext4.vhdx` only grows.** Files deleted inside WSL stay
  allocated on C:: 79 GB in use inside was 82 GB on C: (2026-10-23). Space
  comes back only when both halves are in place: `fstrim` inside WSL marks the
  freed blocks, and the vhdx must be sparse on the Windows side to release
  them.
- **C: under 20 GB free**: the pagefile grows into it. On 2026-10-22 C: filled
  and a background build was killed for low memory.
- **`.wslconfig` without `memory=`**: the VM may take half of the 32 GB RAM and
  Linux fills it with file cache, which Windows counts as committed: vmmemWSL
  held 14.9 GB, 13.6 GB of it cache, while WSL itself used about 1 GB
  (2026-10-22).

## What is in place

- `install_tool_wsl.zsh` enables `fstrim.timer` and runs `fstrim -v /` once.
  Both `fstrim.timer` and `fstrim.service` carry
  `ConditionVirtualization=!container`, and systemd counts WSL as a container,
  so the enabled timer stayed "inactive (dead) ... start condition unmet"
  (2026-10-24). A drop-in `/etc/systemd/system/fstrim.{timer,service}.d/wsl.conf`
  with an empty `ConditionVirtualization=` clears it. Without systemd
  (`[boot] systemd=true` in `/etc/wsl.conf`) the timer cannot run.
- The same script checks through WSL interop (`reg.exe`, `fsutil.exe`) that the
  vhdx is sparse and prints the fix when it is not. Only Windows can set it,
  with WSL stopped, so it is printed, not run:
  `wsl --shutdown; wsl --manage Ubuntu --set-sparse true` (PowerShell).
- `check_wsl_host.zsh` checks from Windows: vhdx sparse (found through
  `HKCU\...\Lxss` and `fsutil sparse queryflag`), C: free under 20 GB,
  `.wslconfig` `memory=` under `[wsl2]` and `autoMemoryReclaim` under
  `[experimental]`. Warnings only, exit 0, each with its fix. `test.zsh` runs it
  with `--quiet` for `--wsl` and `--both`. `TEST_WSL_DISTRO` names another
  distribution.
- `testapp/test_support/host/wslconfig` is a byte copy of this PC's
  `%UserProfile%\.wslconfig`: `networkingMode=mirrored`, `memory=8GB`,
  `[experimental] hostAddressLoopback=true` and `autoMemoryReclaim=DropCache`,
  each with its reason. Restore with `cp` and `wsl --shutdown`; check drift with
  `cmp`.

## How to apply

- `hostAddressLoopback` and `autoMemoryReclaim` belong under `[experimental]`.
  In the wrong section they are ignored with no warning.
- Raise `memory=` if a Swift build inside WSL is OOM-killed.
- Any change to `.wslconfig` needs `wsl --shutdown`, which stops every
  distribution and everything in it (multisshd included).

## Limits

- `autoMemoryReclaim` was confirmed as an `[experimental]` key in WSL 3.0.3
  (`strings wslservice.exe`, 2026-10-22); re-check after a WSL update.

---

# WSL 主機:fstrim、稀疏 vhdx、C: 剩餘空間與 .wslconfig

2026-10-24 依 46b6d83e、a44f33e8、`testapp/test_support/check_wsl_host.zsh`、`testapp/install_tool_wsl.zsh` 與
`testapp/test_support/host/`(`wslconfig`、`README.md`)寫成。

## 是什麼

Windows 這一側有三個設定決定 WSL 建置能否持續:

- **發行版的 `ext4.vhdx` 只會變大。**WSL 內刪掉的檔案在 C: 上照樣佔著：裡面用 79 GB,C: 上是 82 GB(2026-10-23)。
  兩半都到位才會還回空間:WSL 內的 `fstrim` 標出已釋放的區塊，而 vhdx 必須在 Windows 那一側是稀疏的才會交還。
- **C: 剩餘不到 20 GB**:分頁檔會長進去。2026-10-22 C: 滿了，背景建置因記憶體不足被停掉。
- **`.wslconfig` 沒有 `memory=`**:VM 可拿走 32 GB RAM 的一半,Linux 把它塞滿檔案快取，而 Windows 把那些算成已承諾
  記憶體:vmmemWSL 佔 14.9 GB,其中 13.6 GB 是快取,WSL 自己只用約 1 GB(2026-10-22)。

## 目前的做法

- `install_tool_wsl.zsh` 啟用 `fstrim.timer` 並執行一次 `fstrim -v /`。`fstrim.timer` 與 `fstrim.service` 都帶有
  `ConditionVirtualization=!container`,而 systemd 把 WSL 算成容器，所以啟用後的計時器仍是「inactive (dead) ... start
  condition unmet」(2026-10-24)。drop-in `/etc/systemd/system/fstrim.{timer,service}.d/wsl.conf` 以空白的
  `ConditionVirtualization=` 清掉這個條件。沒有 systemd(`/etc/wsl.conf` 的 `[boot] systemd=true`)時計時器無法執行。
- 同一支腳本經 WSL interop(`reg.exe`、`fsutil.exe`)檢查 vhdx 是否稀疏，不是時印出修正指令。只有 Windows 能設定，
  而且 WSL 必須停止，所以只印不執行:`wsl --shutdown; wsl --manage Ubuntu --set-sparse true`(PowerShell)。
- `check_wsl_host.zsh` 從 Windows 檢查:vhdx 是否稀疏(經 `HKCU\...\Lxss` 與 `fsutil sparse queryflag` 找到)、C: 是否
  剩不到 20 GB、`.wslconfig` 的 `[wsl2]` 下有無 `memory=`、`[experimental]` 下有無 `autoMemoryReclaim`。只發警告、以 0
  結束，每則附修正方式。`test.zsh` 在 `--wsl` 與 `--both` 時以 `--quiet` 執行它。`TEST_WSL_DISTRO` 可指定其他發行版。
- `testapp/test_support/host/wslconfig` 是本機 `%UserProfile%\.wslconfig` 的逐位元組拷貝:`networkingMode=mirrored`、
  `memory=8GB`、`[experimental] hostAddressLoopback=true` 與 `autoMemoryReclaim=DropCache`,各附理由。以 `cp` 加
  `wsl --shutdown` 還原；以 `cmp` 檢查是否走樣。

## 怎麼用

- `hostAddressLoopback` 與 `autoMemoryReclaim` 屬於 `[experimental]`。放錯區段會被忽略，沒有任何警告。
- WSL 內的 Swift 建置被 OOM 殺掉時調高 `memory=`。
- 任何 `.wslconfig` 的變更都需要 `wsl --shutdown`,它會停止所有發行版與其中的一切(包括 multisshd)。

## 限制

- `autoMemoryReclaim` 在 WSL 3.0.3 確認為 `[experimental]` 的鍵(`strings wslservice.exe`,2026-10-22);WSL 更新後要重新查證。
