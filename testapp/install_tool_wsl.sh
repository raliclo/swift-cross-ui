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

# Where to look next when the render node is missing, and what it means.
#
# WSL mounts the Windows DriverStore read-only at /usr/lib/wsl/drivers, and the
# GPU's user-mode D3D12 driver has to be among those entries. If it is not,
# dxgkrnl has no adapter to describe, and `dmesg | grep dxgk` fills with
# `dxgkio_query_adapter_info: Ioctl failed: -22`. That message is the one to
# search for; it appears within the first few seconds of boot and is the
# earliest point in the chain that says anything at all.
#
# Deliberately not checked programmatically. Matching driver directories by
# vendor prefix looked easy and was wrong on the first real run: `^nv` matches
# `nvami.inf` and `nvdimm.inf`, which are NVDIMM storage drivers, so the check
# reported a graphics driver on a machine that plainly had none. The two device
# node tests above are direct evidence and do not need a heuristic behind them.
#
# The fix is on the Windows side -- reinstall the GPU driver so the DriverStore
# entry is restored, and reboot. Nothing inside the distribution can supply it.
# render node 缺席時該往哪裡看，以及那代表什麼。
#
# WSL 會把 Windows 的 DriverStore 唯讀掛載於 /usr/lib/wsl/drivers，GPU 的 D3D12
# 使用者模式驅動必須在其中。若不在，dxgkrnl 就沒有介面卡可描述，`dmesg | grep dxgk`
# 會出現 `dxgkio_query_adapter_info: Ioctl failed: -22`。那行訊息就是該搜尋的目標，
# 它在開機後數秒內出現，是整條鏈上最早會發聲的位置。
#
# 刻意不做程式化判斷。以廠商前綴比對驅動目錄看似容易，卻在第一次真實執行就出錯：
# `^nv` 會匹配到 `nvami.inf` 與 `nvdimm.inf`——那是 NVDIMM 儲存驅動，於是檢查在一台
# 明顯沒有顯示卡驅動的機器上回報「找到了」。上方兩項裝置節點檢查是直接證據，不需要
# 這種啟發式。
#
# 修復屬於 Windows 端：重新安裝顯示卡驅動讓 DriverStore 項目回來，然後重開機。
# 發行版內部無法提供它。
if [ "$gpu_ok" -eq 1 ]; then
    echo "  device nodes present; confirm with: GSK_DEBUG=renderer <app>"
else
    echo "  GTK will fall back to llvmpipe (CPU). UI tests still work;" >&2
    echo "  anything measuring GPU presentation does not." >&2
fi

log "Done. Open a new shell, or run: export PATH=\"$SWIFT_PREFIX/usr/bin:\$PATH\""
