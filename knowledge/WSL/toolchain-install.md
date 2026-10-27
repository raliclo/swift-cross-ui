# WSL toolchain: install_tool_wsl.sh / .zsh

Written 2026-10-24 from `testapp/install_tool_wsl.sh`,
`testapp/install_tool_wsl.zsh`, 0836e0cf and testapp/UI-test-plan-en.md
("Linux plan: GtkBackend through WSL").

## Run it

```sh
wsl -d Ubuntu -u root -- bash testapp/install_tool_wsl.sh          # from the WSL checkout
wsl -d Ubuntu -u root -- bash testapp/install_tool_wsl.sh --help
```

The `.sh` is the only non-zsh script in `testapp/`: it installs zsh on a stock
Ubuntu and hands over to the `.zsh`. Root because `sudo` in a default WSL
Ubuntu asks for a password. Every step is idempotent.

## What it installs, and why each matters

- **Swift 6.4.1** (since 2026-10-23; 6.4.0 from 2026-10-12, 6.3.3 before), the
  same version as Windows. swift.org has no Ubuntu 26.04 build, so the 24.04
  tarball goes to `/usr/local/swift` (`SWIFT_VERSION`, `SWIFT_PLATFORM`,
  `SWIFT_PREFIX` override). PATH comes from `/etc/profile.d/swift.sh`, not
  symlinks.
- **Compat libraries**: 26.04 ships `libxml2.so.16` and ICU 78; the 24.04
  toolchain wants `libxml2.so.2` and ICU 74. Both are extracted from 24.04
  `.deb`s into `/usr/local/lib/swift-compat` (via `ld.so.conf.d`); nothing the
  distribution owns is replaced.
- GTK 4 (`libgtk-4-dev`, 4.22.4 as of the plan), WebKitGTK 6.0 runtime
  (`libwebkitgtk-6.0-4`, loaded with `dlopen` by `gtk_webkit.c`), fonts
  (`fonts-noto-cjk`, `fonts-noto-color-emoji`), `pulseaudio-utils`
  (`pactl info`), `xdotool x11-utils x11-apps netpbm` (`xwd` and `xclock` are
  in x11-apps), Orca with speech-dispatcher, `linux-perf`,
  `vulkan-tools mesa-utils` (`vulkaninfo`, `eglinfo`).
- WSLg GPU settings ([gpu-and-renderer.md](gpu-and-renderer.md)) and the
  fstrim timer ([host-disk-and-memory.md](host-disk-and-memory.md)).

## Rules the script follows, each from a failure

- **Never delete another toolchain.** On 2026-10-23 a run meant only to add
  Orca found 6.4.1 at the prefix, compared it with its 6.4.0 default and
  `rm -rf`'d the toolchain other work was using. A different toolchain is now
  moved to `<prefix>-<its release tag>` with a warning.
- **Match the release tag with a trailing `.0` dropped.** 6.4.0 reports
  `swift-6.4-RELEASE`; grepping for 6.4.0 never matched and every run
  re-downloaded 1.1 GB.
- **A broken third-party apt repository warns, not aborts.** An NVIDIA CUDA
  repo with no keyring (`NO_PUBKEY A4B469963BF863CC`) stopped the whole setup
  under `set -e`. If that repo exists, `cuda-keyring` is installed and the
  unsigned duplicate is renamed, not deleted.
- In zsh, do not assign to `path` (it is tied to `PATH`) and do not name a
  function `log` (autoloaded builtin).

## Building in WSL

- `swift build --target GtkBackend`, not a plain `swift build` or
  `--product SwiftCrossUI`: the default set includes the `WinUIInterop` C
  target, which fails on Linux with `'Windows.h' file not found`.
- `testapp/compile.zsh Pn` builds a test app (GTK-only apps too, since
  fe5cc2af); 5-15 s once warm, 61.7 s from clean for `--target GtkBackend`
  (plan measurement).

## Limits

- The 24.04 toolchain on 26.04 libraries is not a combination swift.org tests.
  A failure that looks like a Swift or Foundation bug should be checked
  against this first.
- WSLg's PulseAudio server can stop listening while its socket stays;
  `pactl info` says "Connection refused" and only `wsl --shutdown` restores it.
  ALSA "cannot find card '0'" lines are a symptom of that, not the cause.

---

# WSL 工具鏈:install_tool_wsl.sh / .zsh

2026-10-24 依 `testapp/install_tool_wsl.sh`、`testapp/install_tool_wsl.zsh`、0836e0cf 與 testapp/UI-test-plan-en.md
(「Linux plan: GtkBackend through WSL」)寫成。

## 執行

指令見上方英文段落。`.sh` 是 `testapp/` 裡唯一不是 zsh 的腳本：它在原始 Ubuntu 上安裝 zsh,然後交棒給 `.zsh`。用
root 是因為預設 WSL Ubuntu 的 `sudo` 會要密碼。每一步都是冪等的。

## 安裝什麼，以及各自的理由

- **Swift 6.4.1**(2026-10-23 起;2026-10-12 起為 6.4.0,之前為 6.3.3),與 Windows 同版。swift.org 沒有 Ubuntu 26.04
  的版本，因此把 24.04 的 tarball 裝到 `/usr/local/swift`(可用 `SWIFT_VERSION`、`SWIFT_PLATFORM`、`SWIFT_PREFIX` 覆寫)。
  PATH 來自 `/etc/profile.d/swift.sh`,不用符號連結。
- **相容函式庫**:26.04 帶的是 `libxml2.so.16` 與 ICU 78;24.04 的工具鏈要 `libxml2.so.2` 與 ICU 74。兩者都從 24.04 的
  `.deb` 解出，放進 `/usr/local/lib/swift-compat`(經 `ld.so.conf.d`);發行版的任何東西都不被替換。
- GTK 4(`libgtk-4-dev`,計畫記錄時為 4.22.4)、WebKitGTK 6.0 runtime(`libwebkitgtk-6.0-4`,由 `gtk_webkit.c` 以
  `dlopen` 載入)、字型(`fonts-noto-cjk`、`fonts-noto-color-emoji`)、`pulseaudio-utils`(`pactl info`)、
  `xdotool x11-utils x11-apps netpbm`(`xwd` 與 `xclock` 在 x11-apps 裡)、Orca 與 speech-dispatcher、`linux-perf`、
  `vulkan-tools mesa-utils`(`vulkaninfo`、`eglinfo`)。
- WSLg 的 GPU 設定([gpu-and-renderer.md](gpu-and-renderer.md))與 fstrim 計時器
  ([host-disk-and-memory.md](host-disk-and-memory.md))。

## 腳本遵守的規則，每一條都來自一次失敗

- **絕不刪除其他工具鏈。**2026-10-23 一次只為了加裝 Orca 的執行，在前綴位置看到 6.4.1,與預設的 6.4.0 比對不符，就
  `rm -rf` 掉了其他工作正在用的工具鏈。現在不同的工具鏈會被移到 `<前綴>-<其 release 標籤>` 並發出警告。
- **比對 release 標籤時去掉結尾的 `.0`。**6.4.0 回報的是 `swift-6.4-RELEASE`;grep 6.4.0 永遠不命中，每次執行都重新
  下載 1.1 GB。
- **損壞的第三方 apt 套件庫只警告、不中止。**一個沒有 keyring 的 NVIDIA CUDA repo(`NO_PUBKEY A4B469963BF863CC`)
  曾在 `set -e` 下讓整個安裝停止。若該 repo 存在，會安裝 `cuda-keyring`,未簽署的重複項目改名而非刪除。
- zsh 中不要對 `path` 賦值(它與 `PATH` 綁定),也不要把函式命名為 `log`(自動載入的 builtin)。

## 在 WSL 中建置

- 用 `swift build --target GtkBackend`,不要用單純的 `swift build` 或 `--product SwiftCrossUI`:預設集合含 `WinUIInterop`
  這個 C target,在 Linux 上會以 `'Windows.h' file not found` 失敗。
- `testapp/compile.zsh Pn` 建置測試 app(自 fe5cc2af 起也包含只有 GTK 的 app);暖機後 5–15 秒,`--target GtkBackend`
  從乾淨狀態 61.7 秒(計畫中的量測)。

## 限制

- 24.04 工具鏈配 26.04 函式庫不是 swift.org 測試過的組合。看起來像 Swift 或 Foundation 的錯誤，要先懷疑是這個。
- WSLg 的 PulseAudio 伺服器可能在 socket 還在時停止監聽;`pactl info` 回報「Connection refused」,只有 `wsl --shutdown`
  能恢復。ALSA「cannot find card '0'」的行是它的症狀，不是病因。
