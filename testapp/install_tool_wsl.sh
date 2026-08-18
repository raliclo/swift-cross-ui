#!/bin/bash
# The one script here that is deliberately not zsh.
#
# It is the bootstrap: it runs against a stock Ubuntu where zsh is not
# installed yet, and installing zsh is one of the things it does. A zsh
# shebang would make it unable to run on exactly the machine it exists to set
# up. Everything it starts afterwards can be, and is, zsh.
# 本目錄唯一刻意不用 zsh 的腳本。
#
# 它是 bootstrap：執行時面對的是尚未安裝 zsh 的原生 Ubuntu，而安裝 zsh 正是它的
# 工作之一。若用 zsh shebang，它就無法在它存在的目的所指向的那台機器上執行。
# Prepares a WSL (or plain Linux) environment for building and testing
# swift-cross-ui's GtkBackend.
#
# Run it inside the distribution, not from Windows:
#
#   wsl -d Ubuntu -- bash testapp/install_tool_wsl.sh
#
# It needs root for the apt packages and for /usr/local. `sudo` in a default
# WSL Ubuntu asks for a password; `wsl -d Ubuntu -u root` avoids handling one:
#
#   wsl -d Ubuntu -u root -- bash testapp/install_tool_wsl.sh
#
# Everything here is idempotent, so re-running it is safe.
#
# What it deals with, learned the hard way on Ubuntu 26.04:
#
# - swift.org publishes no toolchain for 26.04. The 24.04 build runs there, so
#   that is what gets installed.
# - That toolchain then fails to start, because 26.04 dropped the library
#   versions it was linked against: libxml2.so.2 (26.04 ships .so.16) and ICU 74
#   (26.04 ships 78). Both are extracted from the 24.04 packages into a separate
#   directory rather than installed, so nothing the distribution owns is
#   touched or downgraded.

set -euo pipefail

SWIFT_VERSION="${SWIFT_VERSION:-6.3.3}"
SWIFT_PLATFORM="${SWIFT_PLATFORM:-ubuntu24.04}"
SWIFT_PREFIX="${SWIFT_PREFIX:-/usr/local/swift}"
COMPAT_DIR="/usr/local/lib/swift-compat"

log() { printf '\n== %s\n' "$1"; }

if [ "$(id -u)" -ne 0 ]; then
    echo "This script installs system packages; run it as root:" >&2
    echo "  wsl -d <distro> -u root -- bash ${0}" >&2
    exit 1
fi

. /etc/os-release
log "Distribution: ${PRETTY_NAME:-unknown}"

log "Installing GTK 4 and build dependencies"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends \
    zsh libgtk-4-dev pkg-config curl ca-certificates git \
    binutils libcurl4-openssl-dev libedit2 libncurses-dev \
    libpython3-dev libsqlite3-0 libz3-dev tzdata unzip

# CJK fonts, needed because this project's UI text and test media names are in
# Traditional Chinese. A stock WSL image has none: measured here, fontconfig saw
# 89 fonts and 0 for zh-TW, and fc-match for zh-TW answered "DejaVu Sans", which
# has no Han glyphs. GTK then draws every Chinese character as a tofu box while
# the app itself is working perfectly -- P6 showed its media filename as boxes
# in the same screenshot where the video's own burned-in Chinese subtitles were
# sharp, because those are pixels rather than text. Nothing errors, so this
# reads as a rendering bug in the backend rather than a missing package.
# The Windows side is unaffected: it uses the system fonts, which include CJK.
# CJK 字型。本專案的 UI 文字與測試媒體檔名皆為繁體中文，而原始的 WSL 映像完全沒有
# 中文字型：實測 fontconfig 只看到 89 個字型、zh-TW 為 0，且 zh-TW 的 fc-match 回答
# 「DejaVu Sans」——該字型不含漢字。於是 GTK 會把每個中文字畫成豆腐框，即使 app 本身
# 運作完全正常——P6 就曾在同一張截圖中把媒體檔名顯示為方框，而影片本身壓製的中文字幕
# 卻清晰可辨，因為後者是像素而非文字。整個過程不會有任何錯誤訊息，因此這會被誤讀成
# backend 的算繪缺陷，而非缺少套件。Windows 端不受影響，因為它使用含 CJK 的系統字型。
apt-get install -y --no-install-recommends fonts-noto-cjk

# PulseAudio client tools. Not needed to play audio -- libpulse is already
# pulled in by ffmpeg -- but without them there is no way to ask whether the
# audio server is even reachable, and that is the question that matters here.
#
# WSLg supplies audio as a PulseAudio server bridged to Windows over RDP, at the
# socket PULSE_SERVER points to (/mnt/wslg/PulseServer). It can stop listening
# while the socket file stays in place, so everything looks configured and
# nothing plays. `pactl info` answers "Connection refused" -- the one command
# that distinguishes this from a client-side misconfiguration. Restarting WSLg
# (`wsl --shutdown` from Windows, then reopen) brings the server back, verified
# by ear on this machine.
#
# The 32 lines of `ALSA lib confmisc.c:855:(parse_card) cannot find card '0'`
# that appear alongside this are a symptom, not the cause: SDL only falls back
# to ALSA when it cannot reach pulse, and WSL has no sound card for ALSA to
# find. With a healthy server SDL picks pulse on its own and prints nothing.
# Chasing those lines led to an SDL_AUDIODRIVER override in P6 that fixed
# nothing and has since been reverted.
# PulseAudio client 工具。播放音訊本身不需要它（libpulse 已由 ffmpeg 帶入），但少了
# 它就無從得知音訊伺服器是否真的連得上，而那正是此處的關鍵問題。
#
# WSLg 以 PulseAudio server 形式提供音訊，並經 RDP 橋接至 Windows，socket 位置即
# PULSE_SERVER 所指（/mnt/wslg/PulseServer）。有兩件事會出錯：
#
#   1. ffplay 透過 SDL 播放，而 SDL 會先嘗試 ALSA 再嘗試 PulseAudio。WSL 沒有音效卡，
#      因此 ALSA 失敗並輸出 32 行
#      `ALSA lib confmisc.c:855:(parse_card) cannot find card '0'`。P6 在
#      PULSE_SERVER 存在時，會為其 ffplay 子行程設定 SDL_AUDIODRIVER=pulse。
#   2. WSLg 的 PulseAudio server 可能停止監聽，但 socket 檔案仍留在原處，於是一切看
#      起來設定正確卻沒有聲音。此時 `pactl info` 會回報 "Connection refused"——這是唯一
#      能把此情況與 client 端設定錯誤區分開來的指令。重啟 WSLg（於 Windows 執行
#      `wsl --shutdown` 後重新開啟）可讓伺服器恢復。
apt-get install -y --no-install-recommends pulseaudio-utils

# Ubuntu 26.04 renamed the sonames the 24.04 toolchain was linked against. The
# replacements are taken from 24.04's own packages and kept in their own
# directory, ahead of nothing else on the search path, so the distribution's
# newer libxml2 and ICU stay in place for everything else.
if [ "${VERSION_ID:-}" = "26.04" ]; then
    log "Adding Ubuntu 24.04 compatibility libraries for the toolchain"
    mkdir -p "$COMPAT_DIR"
    work="$(mktemp -d)"
    trap 'rm -rf "$work"' EXIT

    fetch_lib() {
        local pool="$1" pattern="$2" description="$3"
        local deb
        deb="$(curl -fsSL "$pool" | grep -oE "$pattern" | sort -u | tail -1)"
        if [ -z "$deb" ]; then
            echo "Could not find $description in $pool" >&2
            exit 1
        fi
        echo "  $deb"
        curl -fsSL -o "$work/$deb" "$pool$deb"
        rm -rf "$work/x"
        mkdir -p "$work/x"
        dpkg-deb -x "$work/$deb" "$work/x"
        cp -a "$work"/x/usr/lib/x86_64-linux-gnu/$4 "$COMPAT_DIR/"
    }

    fetch_lib "http://archive.ubuntu.com/ubuntu/pool/main/libx/libxml2/" \
        'libxml2_2\.9\.14[^"]*_amd64\.deb' "libxml2 2.9.14" 'libxml2.so.2*'
    fetch_lib "http://archive.ubuntu.com/ubuntu/pool/main/i/icu/" \
        'libicu74_[^"]*_amd64\.deb' "ICU 74" 'libicu*.so.74*'

    echo "$COMPAT_DIR" > /etc/ld.so.conf.d/swift-compat.conf
    ldconfig
fi

log "Installing Swift $SWIFT_VERSION ($SWIFT_PLATFORM build)"
if [ -x "$SWIFT_PREFIX/usr/bin/swift" ] \
    && "$SWIFT_PREFIX/usr/bin/swift" --version 2>/dev/null | grep -q "$SWIFT_VERSION"; then
    echo "  already installed at $SWIFT_PREFIX"
else
    platform_path="${SWIFT_PLATFORM//./}"
    archive="swift-$SWIFT_VERSION-RELEASE-$SWIFT_PLATFORM.tar.gz"
    url="https://download.swift.org/swift-$SWIFT_VERSION-release/$platform_path/swift-$SWIFT_VERSION-RELEASE/$archive"

    echo "  $url"
    tmp="$(mktemp -d)"
    curl -fsSL -o "$tmp/$archive" "$url"
    rm -rf "$SWIFT_PREFIX"
    mkdir -p "$SWIFT_PREFIX"
    tar -xzf "$tmp/$archive" -C "$SWIFT_PREFIX" --strip-components=1
    rm -rf "$tmp"
fi

# A profile entry rather than symlinks into /usr/local/bin, so the toolchain can
# be replaced by pointing SWIFT_PREFIX somewhere else.
printf 'export PATH="%s/usr/bin:$PATH"\n' "$SWIFT_PREFIX" > /etc/profile.d/swift.sh
chmod 0644 /etc/profile.d/swift.sh

log "Verifying"
export PATH="$SWIFT_PREFIX/usr/bin:$PATH"
swift --version
echo "gtk4: $(pkg-config --modversion gtk4)"

# WSLg exports these; without them a GTK window has nowhere to appear and every
# UI test result would be meaningless.
if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    echo "display: ${DISPLAY:-unset} / wayland: ${WAYLAND_DISPLAY:-unset}"
else
    echo "display: none found -- GUI tests cannot run in this session" >&2
fi

# GPU acceleration: reported, not fixed. Nothing here can install it.
#
# GTK renders through GSK, which tries Vulkan, then GL, then falls back to
# llvmpipe -- a CPU rasteriser. The fallback is silent: windows appear, tests
# pass, screenshots look right, and every frame was drawn on the CPU. Anything
# measuring GPU presentation is then measuring nothing, which is why this
# prints the answer rather than leaving it to be discovered.
#
# The chain that has to hold, in order:
#
#   /dev/dxg          WSL's GPU device. Present whenever GPU support is on.
#   /dev/dri/renderD* The DRM render node. EGL opens this and nothing else;
#                     without it eglInitialize fails with "failed to get
#                     driver name for fd -1" no matter which Mesa driver is
#                     selected. /dev/dxg alone is not enough.
#   a non-CPU Vulkan  Otherwise GSK reports "device is CPU" and gives up. On
#     device          WSL that means the dzn (D3D12 -> Vulkan) ICD; the stock
#                     mesa-vulkan-drivers package here ships lavapipe, which
#                     is software.
#
# Measured on this machine, 2026-08-18: /dev/dxg present, /dev/dri absent,
# only lavapipe, so GTK ran on llvmpipe. Overriding GALLIUM_DRIVER,
# MESA_LOADER_DRIVER_OVERRIDE or GSK_RENDERER changes nothing, because the
# missing piece is the render node rather than the driver choice. Fixing it is
# a WSL-side concern -- kernel with the dxgkrnl DRM shim, GPU support enabled
# in .wslconfig -- not an apt install.
# GPU 加速：只回報、不修復，這裡沒有任何 apt 套件能補上。
#
# GTK 透過 GSK 繪製，依序嘗試 Vulkan、GL，最後退回 llvmpipe（CPU 光柵化器）。這個
# 退回是「靜默」的：視窗照常出現、測試照常通過、截圖看起來正確，而每一格都是 CPU
# 畫的。任何量測 GPU 呈現的工作到那時都在量空氣，因此這裡直接把答案印出來。
#
# 必須依序成立的條件：/dev/dxg（WSL 的 GPU 裝置）、/dev/dri/renderD*（DRM render
# node，EGL 只認這個，缺了它無論選哪個 Mesa 驅動都會失敗）、以及非 CPU 的 Vulkan
# 裝置（WSL 上需要 dzn ICD；本機 mesa-vulkan-drivers 只提供軟體的 lavapipe）。
#
# 2026-08-18 於本機實測：/dev/dxg 有、/dev/dri 無、只有 lavapipe，因此 GTK 跑在
# llvmpipe 上。覆寫 GALLIUM_DRIVER、MESA_LOADER_DRIVER_OVERRIDE 或 GSK_RENDERER
# 都無效，因為缺的是 render node 而非驅動選擇。要修屬於 WSL 端的事——具備 dxgkrnl
# DRM shim 的核心、以及 .wslconfig 中啟用 GPU 支援——不是安裝套件能解決的。
log "Checking GPU acceleration"
gpu_ok=1
[ -e /dev/dxg ] || { echo "  /dev/dxg missing: GPU support is off for this distribution" >&2; gpu_ok=0; }
ls /dev/dri/renderD* >/dev/null 2>&1 \
    || { echo "  /dev/dri render node missing: EGL cannot initialise, GTK will use llvmpipe" >&2; gpu_ok=0; }

# Where to look next when the render node is missing.
#
# `dmesg | grep dxgk` is the earliest thing in the chain that speaks. On the
# machine this was diagnosed on it reported
# `dxgkio_query_adapter_info: Ioctl failed: -22` within three seconds of boot,
# and every symptom above it -- no /dev/dri, "device is CPU", llvmpipe --
# follows from that without naming it.
#
# What it is NOT, established by getting it wrong three times in one sitting:
#
#   It is not a missing or outdated GPU driver. `pnputil /enum-drivers` showed
#   the NVIDIA display driver installed and current, published as oem109.inf
#   from nvami.inf, and its WSL mount at
#   /usr/lib/wsl/drivers/nvami.inf_amd64_*/ held 165 files including
#   libcuda.so. The payload is there.
#
#   `nvami.inf` is NVIDIA's display driver, whatever the name suggests. A
#   check that dismissed it as NVDIMM storage was written, committed, and
#   pushed before `pnputil` was consulted.
#
#   Reinstalling the driver, `wsl --shutdown` and `wsl --update` were all
#   tried and changed nothing; WSL 2.7.11 with WSLg 1.0.73.2 is current.
#
# So the cause is still open. Ask dxgk what it could not enumerate before
# assuming anything about drivers -- three guesses were spent on the driver
# because it was the plausible answer, and each one was checked against a
# proxy that happened to agree.
# render node 缺席時該往哪裡看。
#
# `dmesg | grep dxgk` 是整條鏈上最早發聲的地方。在診斷這台機器時，它於開機三秒內
# 報出 `dxgkio_query_adapter_info: Ioctl failed: -22`，而其上的所有症狀（沒有
# /dev/dri、「device is CPU」、llvmpipe）都源自於此，卻都不會提到它。
#
# 以下是「不是」什麼，代價是同一次作業中連錯三次：
#
#   不是驅動缺失或過舊。`pnputil /enum-drivers` 顯示 NVIDIA 顯示驅動已安裝且為新版
#   （oem109.inf，源自 nvami.inf），其 WSL 掛載
#   /usr/lib/wsl/drivers/nvami.inf_amd64_*/ 內有 165 個檔案，包含 libcuda.so。
#
#   `nvami.inf` 就是 NVIDIA 的顯示驅動，名稱容易誤導。曾有一個把它當成 NVDIMM 儲存
#   驅動而排除的檢查被寫下、提交並推送——在查 `pnputil` 之前。
#
#   重裝驅動、`wsl --shutdown`、`wsl --update` 都試過且無效；WSL 2.7.11 與
#   WSLg 1.0.73.2 皆為最新。
#
# 因此成因仍未確定。在對驅動做出任何假設之前，先問 dxgk 它究竟列舉不到什麼——
# 前三次猜測都押在驅動上，因為那是看似合理的答案，而每次驗證用的代理指標又剛好同意。
if [ "$gpu_ok" -eq 1 ]; then
    echo "  device nodes present; confirm with: GSK_DEBUG=renderer <app>"
else
    echo "  GTK will fall back to llvmpipe (CPU). UI tests still work;" >&2
    echo "  anything measuring GPU presentation does not." >&2
fi

log "Done. Open a new shell, or run: export PATH=\"$SWIFT_PREFIX/usr/bin:\$PATH\""
