#!/usr/bin/env zsh
# Prepares a WSL (or plain Linux) environment for building and testing
# swift-cross-ui's GtkBackend.
#
#   wsl -d Ubuntu -u root -- bash testapp/install_tool_wsl.sh
#   zsh testapp/install_tool_wsl.zsh --help
#
# 為 swift-cross-ui 的 GtkBackend 準備 WSL（或一般 Linux）的建置與測試環境。
#
# Reached through install_tool_wsl.sh, which installs zsh and hands over. Run
# that rather than this file directly on a machine that has no zsh yet. It needs
# root for the apt packages and for /usr/local; `sudo` in a default WSL Ubuntu
# asks for a password, and `-u root` avoids having to handle one.
# 由 install_tool_wsl.sh 進入，該腳本負責安裝 zsh 後交棒。在尚未安裝 zsh 的機器上請
# 執行那一支，而非直接執行本檔。本腳本需要 root 權限以安裝 apt 套件並寫入 /usr/local；
# 預設的 WSL Ubuntu 使用 `sudo` 會要求密碼，改用 `-u root` 可免去處理密碼。
#
# Everything here is idempotent, so re-running it is safe.
# 此處所有步驟皆為幂等，重複執行是安全的。
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

# $0 inside a zsh function is the function's name, not the script, so the path
# is captured here at top level while it still means the file.
# zsh 中函式內的 $0 是函式名稱而非腳本本身，因此在頂層先捕捉路徑，此時它仍代表檔案。
script_path="${0:A}"

SWIFT_VERSION="${SWIFT_VERSION:-6.3.3}"
SWIFT_PLATFORM="${SWIFT_PLATFORM:-ubuntu24.04}"
SWIFT_PREFIX="${SWIFT_PREFIX:-/usr/local/swift}"
COMPAT_DIR="/usr/local/lib/swift-compat"

usage() {
    sed -n '2,20p' "$script_path" | sed 's/^# \{0,1\}//'
}

# Answered before any work, so a wrong flag costs a page of text rather than an
# apt run and a toolchain download.
# 在任何工作之前先回答，讓打錯的旗標只花費一頁文字，而不是一次 apt 執行與工具鏈下載。
while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 64 ;;
    esac
done

# No log() helper. A function whose name is an autoloadable zsh builtin runs the
# builtin when called before its definition, and this project has already been
# bitten by exactly that with `log` and zsh/watch.
# 不定義 log() 輔助函式。若函式名稱恰為可自動載入的 zsh builtin，在定義之前呼叫會執行
# 該 builtin；本專案已在 `log` 與 zsh/watch 上吃過這個虧。
section() { printf '\n== %s\n' "$1"; }

if [ "$(id -u)" -ne 0 ]; then
    printf 'This script installs system packages; run it as root:\n' >&2
    printf '  wsl -d <distro> -u root -- bash testapp/install_tool_wsl.sh\n' >&2
    exit 1
fi

. /etc/os-release
section "Distribution: ${PRETTY_NAME:-unknown}"

section "Installing GTK 4 and build dependencies"
export DEBIAN_FRONTEND=noninteractive

# A broken third-party repository must not abort the whole setup. Under
# `set -e` it did: this machine had an NVIDIA CUDA repo added during a GPU
# investigation with no keyring alongside it, so `apt-get update` failed with
# `NO_PUBKEY A4B469963BF863CC` and the installer stopped before installing
# anything, on a machine where every package it wanted was available.
#
# The failure is reported rather than hidden, and the installs below are left to
# fail on their own if a package really cannot be found -- which is the accurate
# signal. Warning and continuing is right here because the repositories this
# script depends on are the distribution's own.
# 損壞的第三方套件庫不應中止整個安裝流程。在 `set -e` 下它確實會：本機在一次 GPU 調查
# 期間加入了 NVIDIA CUDA repo 卻沒有一併安裝 keyring，於是 `apt-get update` 以
# `NO_PUBKEY A4B469963BF863CC` 失敗，安裝程式在裝任何東西之前就停止——而該機器上它需要
# 的每一個套件其實都取得得到。
#
# 此處選擇回報而非隱藏失敗，並讓下方的安裝指令在套件真的找不到時自行失敗，那才是準確的
# 訊號。在這裡「警告後繼續」是正確的，因為本腳本真正依賴的是發行版自己的套件庫。
if ! apt-get update -qq; then
    printf '\n  apt-get update reported errors (often a third-party repo without\n' >&2
    printf '  its key). Continuing: the installs below will fail on their own if a\n' >&2
    printf '  package is genuinely unavailable. Check with:\n' >&2
    printf '    ls /etc/apt/sources.list.d/\n' >&2
fi
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
# WSLg 以 PulseAudio server 形式提供音訊並經 RDP 橋接至 Windows，socket 位置即
# PULSE_SERVER 所指（/mnt/wslg/PulseServer）。它可能在 socket 檔案仍留在原處的情況下
# 停止監聽，於是一切看起來設定正確卻沒有聲音。此時 `pactl info` 會回報
# "Connection refused"——這是唯一能把此情況與 client 端設定錯誤區分開來的指令。重啟
# WSLg（於 Windows 執行 `wsl --shutdown` 後重新開啟）可讓伺服器恢復，本機已實聽驗證。
#
# 與之同時出現的 32 行 `ALSA lib confmisc.c:855:(parse_card) cannot find card '0'`
# 是症狀而非病因：SDL 只有在連不上 pulse 時才會退回 ALSA，而 WSL 沒有音效卡可供 ALSA
# 尋找。伺服器健康時 SDL 會自行選擇 pulse，且不會印出任何訊息。追著那些行跑，導致在 P6
# 中加入了一個什麼也沒修好的 SDL_AUDIODRIVER 覆寫，該改動已撤除。
apt-get install -y --no-install-recommends pulseaudio-utils

# GUI automation and window capture, for driving the Pn test apps without a
# person at the keyboard.
#
# These only work against XWayland, reached with GDK_BACKEND=x11. WSLg's default
# is Wayland, where a client cannot be driven by another process by design, so
# xdotool sees nothing. That makes the two backends genuinely different test
# targets rather than an implementation detail: a bug reproduced under one is
# not evidence about the other. A GTK file chooser that would not close was
# reported on the Wayland path and did not reproduce under XWayland at all.
#
# xwd lives in x11-apps, not x11-utils -- installing the latter alone leaves
# `xwd: command not found`. netpbm converts its output, since a capture nobody
# can open is not evidence.
# GUI 自動化與視窗擷取，用於在無人操作鍵盤的情況下驅動 Pn 測試 app。
#
# 這些工具僅在 XWayland 下有效（以 GDK_BACKEND=x11 進入）。WSLg 預設使用 Wayland，
# 而 Wayland 依設計不允許一個行程驅動另一個 client，因此 xdotool 什麼也看不到。這使得
# 兩個 backend 是真正不同的測試目標，而非實作細節：在其中一邊重現的錯誤，並不能作為
# 另一邊的證據。曾有一個「GTK 檔案選擇器不會關閉」的回報發生在 Wayland 路徑上，而在
# XWayland 下完全無法重現。
#
# xwd 位於 x11-apps 而非 x11-utils——只裝後者會得到 `xwd: command not found`。
# netpbm 用於轉換其輸出，因為沒人打得開的擷取檔算不上證據。
apt-get install -y --no-install-recommends xdotool x11-utils x11-apps netpbm

# The NVIDIA CUDA repository, if present, must be signed or apt stops working.
#
# This machine had one added by hand with no keyring, so every `apt-get update`
# failed with `NO_PUBKEY A4B469963BF863CC`. cuda-keyring installs the key and
# its own signed sources entry; the unsigned duplicate then has to go, or apt
# keeps reporting the same error against the same repository twice over. It is
# renamed rather than deleted, and apt reads only *.list and *.sources, so the
# original is still there to restore.
#
# Nothing here adds the repository. It is only repaired when someone else has
# already added it.
# 若系統中存在 NVIDIA CUDA 套件庫，它必須經過簽署，否則 apt 會停止運作。
#
# 本機曾以手動方式加入該套件庫卻未安裝 keyring，導致每次 `apt-get update` 都以
# `NO_PUBKEY A4B469963BF863CC` 失敗。cuda-keyring 會安裝金鑰及其自身已簽署的來源項目；
# 此時未簽署的重複項目必須移除，否則 apt 會對同一個套件庫重複回報相同錯誤。此處採用
# 改名而非刪除，且 apt 只讀取 *.list 與 *.sources，因此原檔仍在、隨時可還原。
#
# 本腳本不會新增該套件庫，只有在他人已經加入時才進行修復。
# `u` deduplicates. Both patterns match the name apt generates for a manually
# added CUDA repo, so without it the same file appears twice and the second
# pass fails on the file the first pass has already renamed.
# `u` 用於去重。手動加入 CUDA 套件庫時 apt 產生的檔名會同時符合兩個樣式，少了它同一個
# 檔案會出現兩次，第二輪便會對第一輪已改名的檔案操作而失敗。
cuda_unsigned=(/etc/apt/sources.list.d/*nvidia*cuda*.list(N) /etc/apt/sources.list.d/*cuda*repos*.list(N))
cuda_unsigned=(${(u)cuda_unsigned})
if [ ${#cuda_unsigned} -gt 0 ]; then
    section "Repairing the unsigned NVIDIA CUDA repository"
    cuda_base=https://developer.download.nvidia.com/compute/cuda/repos/wsl-ubuntu/x86_64
    if [ ! -f /usr/share/keyrings/cuda-archive-keyring.gpg ]; then
        tmp_keyring="$(mktemp -d)"
        if curl -fsSL -o "$tmp_keyring/cuda-keyring.deb" "$cuda_base/cuda-keyring_1.1-1_all.deb"; then
            dpkg -i "$tmp_keyring/cuda-keyring.deb" >/dev/null 2>&1 || true
            printf '  installed cuda-keyring\n'
        else
            printf '  could not download cuda-keyring; leaving the repo alone\n' >&2
        fi
        rm -rf "$tmp_keyring"
    fi
    # Only disable an entry that lacks signed-by, and only once the signed
    # replacement exists, so a working setup is never broken by this.
    # 只停用缺少 signed-by 的項目，且必須在已簽署的替代項目存在之後，
    # 以免破壞原本正常的設定。
    if [ -f /etc/apt/sources.list.d/cuda-wsl-ubuntu-x86_64.list ]; then
        for entry in "${cuda_unsigned[@]}"; do
            [ "${entry:t}" = "cuda-wsl-ubuntu-x86_64.list" ] && continue
            if ! grep -q 'signed-by=' "$entry"; then
                mv "$entry" "$entry.bak"
                printf '  disabled unsigned duplicate: %s\n' "${entry:t}"
            fi
        done
    fi
    apt-get update -qq || printf '  apt-get update still reports errors\n' >&2
fi

# Ubuntu 26.04 renamed the sonames the 24.04 toolchain was linked against. The
# replacements are taken from 24.04's own packages and kept in their own
# directory, ahead of nothing else on the search path, so the distribution's
# newer libxml2 and ICU stay in place for everything else.
# Ubuntu 26.04 更改了 24.04 工具鏈所連結的 soname。替代品取自 24.04 自身的套件，放在
# 獨立目錄中且不排在其他任何項目之前，因此發行版較新的 libxml2 與 ICU 對其餘一切保持
# 不變。
if [ "${VERSION_ID:-}" = "26.04" ]; then
    section "Adding Ubuntu 24.04 compatibility libraries for the toolchain"
    mkdir -p "$COMPAT_DIR"
    work="$(mktemp -d)"
    trap 'rm -rf "$work"' EXIT

    fetch_lib() {
        local pool="$1" pattern="$2" description="$3" glob="$4"
        local deb
        deb="$(curl -fsSL "$pool" | grep -oE "$pattern" | sort -u | tail -1)"
        if [ -z "$deb" ]; then
            printf 'Could not find %s in %s\n' "$description" "$pool" >&2
            exit 1
        fi
        printf '  %s\n' "$deb"
        curl -fsSL -o "$work/$deb" "$pool$deb"
        rm -rf "$work/x"
        mkdir -p "$work/x"
        dpkg-deb -x "$work/$deb" "$work/x"
        # Unquoted on purpose: $glob is a pattern that has to expand here.
        # 刻意不加引號：$glob 是必須在此展開的樣式。
        cp -a "$work"/x/usr/lib/x86_64-linux-gnu/${~glob} "$COMPAT_DIR/"
    }

    fetch_lib "http://archive.ubuntu.com/ubuntu/pool/main/libx/libxml2/" \
        'libxml2_2\.9\.14[^"]*_amd64\.deb' "libxml2 2.9.14" 'libxml2.so.2*'
    fetch_lib "http://archive.ubuntu.com/ubuntu/pool/main/i/icu/" \
        'libicu74_[^"]*_amd64\.deb' "ICU 74" 'libicu*.so.74*'

    printf '%s\n' "$COMPAT_DIR" > /etc/ld.so.conf.d/swift-compat.conf
    ldconfig
fi

section "Installing Swift $SWIFT_VERSION ($SWIFT_PLATFORM build)"
if [ -x "$SWIFT_PREFIX/usr/bin/swift" ] \
    && "$SWIFT_PREFIX/usr/bin/swift" --version 2>/dev/null | grep -q "$SWIFT_VERSION"; then
    printf '  already installed at %s\n' "$SWIFT_PREFIX"
else
    # `platform_path`, not `path`: assigning to `path` in zsh rewrites PATH,
    # because the two are tied as array and scalar. It fails silently and the
    # symptom surfaces far away, as commands no longer being found.
    # 使用 `platform_path` 而非 `path`：在 zsh 中對 `path` 賦值會改寫 PATH，因為兩者以
    # 陣列與純量的形式綁定。它不會報錯，症狀會在很遠的地方以「找不到指令」浮現。
    platform_path="${SWIFT_PLATFORM//./}"
    archive="swift-$SWIFT_VERSION-RELEASE-$SWIFT_PLATFORM.tar.gz"
    url="https://download.swift.org/swift-$SWIFT_VERSION-release/$platform_path/swift-$SWIFT_VERSION-RELEASE/$archive"

    printf '  %s\n' "$url"
    tmp="$(mktemp -d)"
    curl -fsSL -o "$tmp/$archive" "$url"
    rm -rf "$SWIFT_PREFIX"
    mkdir -p "$SWIFT_PREFIX"
    tar -xzf "$tmp/$archive" -C "$SWIFT_PREFIX" --strip-components=1
    rm -rf "$tmp"
fi

# A profile entry rather than symlinks into /usr/local/bin, so the toolchain can
# be replaced by pointing SWIFT_PREFIX somewhere else.
# 使用 profile 項目而非在 /usr/local/bin 建立符號連結，如此只要將 SWIFT_PREFIX 指向他處
# 即可替換工具鏈。
printf 'export PATH="%s/usr/bin:$PATH"\n' "$SWIFT_PREFIX" > /etc/profile.d/swift.sh
chmod 0644 /etc/profile.d/swift.sh

section "Verifying"
export PATH="$SWIFT_PREFIX/usr/bin:$PATH"
swift --version
printf 'gtk4: %s\n' "$(pkg-config --modversion gtk4)"

# WSLg exports these; without them a GTK window has nowhere to appear and every
# UI test result would be meaningless.
# WSLg 會匯出這些變數；少了它們，GTK 視窗無處可顯示，所有 UI 測試結果都毫無意義。
if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    printf 'display: %s / wayland: %s\n' "${DISPLAY:-unset}" "${WAYLAND_DISPLAY:-unset}"
else
    printf 'display: none found -- GUI tests cannot run in this session\n' >&2
fi

# Audio, reported rather than fixed, for the same reason as the GPU below: the
# server lives in WSLg and nothing installed here can restart it.
# 音訊只回報不修復，理由與下方 GPU 相同：伺服器位於 WSLg，此處安裝的任何東西都無法
# 重啟它。
section "Checking audio"
if timeout 5 pactl info >/dev/null 2>&1; then
    printf '  PulseAudio reachable; default sink: %s\n' \
        "$(timeout 5 pactl info 2>/dev/null | sed -n 's/^Default Sink: //p')"
else
    printf '  PulseAudio not reachable. The socket file existing proves nothing --\n' >&2
    printf '  the server can stop serving with it still in place.\n' >&2
    printf '  Fix: run `wsl --shutdown` on Windows, then reopen WSL.\n' >&2
fi

# GPU diagnostic tools. Small, and they turn the section below from inference
# into an answer.
#
# Without them the GPU check can only read files and infer an answer. That gave
# the wrong answer here: /dev/dri is absent, yet Mesa's D3D12 Gallium driver
# reaches the GPU directly through /dev/dxg. `vulkaninfo` and `eglinfo` measure
# the renderer instead of treating one proxy as a verdict.
#
#   deviceType = PHYSICAL_DEVICE_TYPE_CPU
#   deviceName = llvmpipe (LLVM 21.1.8, 256 bits)
#
# Vulkan remains software on this distro, while Wayland EGL can independently
# report a hardware D3D12 renderer; GTK tries the two APIs separately.
#
# GPU 診斷工具。體積很小，而它們讓下方那一段從「推論」變成「答案」。
#
# 沒有它們時只能從檔案推論，而本機曾因此得到錯誤答案：/dev/dri 不存在，Mesa D3D12
# Gallium driver 卻仍能直接經 /dev/dxg 使用 GPU。`vulkaninfo` 與 `eglinfo` 直接量 renderer，
# 不把單一代理條件當成結論。此發行版的 Vulkan 仍是軟體，但 Wayland EGL 可獨立使用硬體
# D3D12；GTK 會分別嘗試這兩個 API。
apt-get install -y --no-install-recommends vulkan-tools mesa-utils

# WSLg OpenGL acceleration uses Mesa's D3D12 Gallium driver over /dev/dxg.
# A DRM render node is not required for this path: this machine has no
# /dev/dri, yet Wayland EGL and GTK both render on its RTX 4060 when d3d12 is
# selected. Vulkan is separate; Ubuntu's package has no dzn ICD, so GSK may
# reject CPU Vulkan and then successfully use hardware GL.
#
# WSLg 的 OpenGL 加速是 Mesa D3D12 Gallium driver 經 /dev/dxg 完成。這條路徑不要求
# DRM render node：本機沒有 /dev/dri，但選用 d3d12 後，Wayland EGL 與 GTK 都能在
# RTX 4060 上算繪。Vulkan 是另一條路；Ubuntu 套件沒有 dzn ICD，因此 GSK 可能先拒絕
# CPU Vulkan，再成功使用硬體 GL。
section "Configuring WSLg GPU acceleration"
wslg_gpu_profile=/etc/profile.d/swift-cross-ui-wslg-gpu.sh
wslg_zshenv=/etc/zsh/zshenv
wslg_zsh_loader='[ ! -r /etc/profile.d/swift-cross-ui-wslg-gpu.sh ] || . /etc/profile.d/swift-cross-ui-wslg-gpu.sh'

wayland_gl_renderer() {
    local adapter="${1:-}"
    local output
    if [ -n "$adapter" ]; then
        output="$(GALLIUM_DRIVER=d3d12 MESA_D3D12_DEFAULT_ADAPTER_NAME="$adapter" \
            timeout 15 eglinfo -p wayland -B 2>/dev/null || true)"
    else
        output="$(GALLIUM_DRIVER=d3d12 timeout 15 eglinfo -p wayland -B 2>/dev/null || true)"
    fi
    printf '%s\n' "$output" | sed -n 's/^OpenGL core profile renderer: //p' | head -1
}

gpu_ok=0
gpu_adapter=""
gpu_renderer="$(timeout 15 eglinfo -p wayland -B 2>/dev/null \
    | sed -n 's/^OpenGL core profile renderer: //p' | head -1 || true)"

if [ -z "${WAYLAND_DISPLAY:-}" ]; then
    printf '  no Wayland display in this session; leaving GPU settings unchanged\n' >&2
elif [ ! -e /dev/dxg ]; then
    printf '  /dev/dxg missing; WSL GPU support is unavailable\n' >&2
elif [ ! -e /usr/lib/x86_64-linux-gnu/dri/d3d12_dri.so ] \
    || [ ! -e /usr/lib/wsl/lib/libd3d12.so ] \
    || [ ! -e /usr/lib/wsl/lib/libdxcore.so ]; then
    printf '  Mesa d3d12 or the WSL D3D12/DXCore bridge is missing\n' >&2
elif [[ "$gpu_renderer" == D3D12\ * ]]; then
    gpu_ok=1
    printf '  already accelerated: %s\n' "$gpu_renderer"
else
    # First try Mesa's normal adapter selection, then the common hybrid-GPU
    # vendors. The adapter name is a case-insensitive substring match. NVIDIA
    # comes first because test machines should prefer throughput over battery;
    # nothing is written until EGL proves that the candidate actually works.
    # 先試 Mesa 預設選卡，再試常見的混合顯卡廠牌。adapter 名稱採不分大小寫的子字串比對。
    # NVIDIA 優先，因測試機以效能為主；EGL 實測成功之前不會寫入任何設定。
    for candidate in "" NVIDIA AMD Intel; do
        candidate_renderer="$(wayland_gl_renderer "$candidate")"
        if [[ "$candidate_renderer" == D3D12\ * ]]; then
            gpu_adapter="$candidate"
            gpu_renderer="$candidate_renderer"
            gpu_ok=1
            break
        fi
    done

    if [ "$gpu_ok" -eq 1 ]; then
        {
            printf '%s\n' '# Generated by testapp/install_tool_wsl.zsh.'
            printf '%s\n' 'export GALLIUM_DRIVER=d3d12'
            if [ -n "$gpu_adapter" ]; then
                printf 'export MESA_D3D12_DEFAULT_ADAPTER_NAME=%q\n' "$gpu_adapter"
            fi
        } > "$wslg_gpu_profile"
        chmod 0644 "$wslg_gpu_profile"

        # Ubuntu's zsh does not source /etc/profile or /etc/profile.d. Add one
        # exact, idempotent loader so non-interactive commands such as
        # `zsh testapp/run.zsh` inherit the measured settings too.
        # Ubuntu 的 zsh 不會讀取 /etc/profile.d；加入一行冪等 loader，讓
        # `zsh testapp/run.zsh` 這類非互動命令也會繼承實測設定。
        if ! grep -Fqx "$wslg_zsh_loader" "$wslg_zshenv"; then
            printf '\n%s\n' "$wslg_zsh_loader" >> "$wslg_zshenv"
        fi

        export GALLIUM_DRIVER=d3d12
        if [ -n "$gpu_adapter" ]; then
            export MESA_D3D12_DEFAULT_ADAPTER_NAME="$gpu_adapter"
        fi
        printf '  configured: %s\n' "$gpu_renderer"
        printf '  profile: %s\n' "$wslg_gpu_profile"
        printf '  zsh loader: %s\n' "$wslg_zshenv"
    else
        printf '  no working D3D12 adapter found; renderer remains: %s\n' \
            "${gpu_renderer:-unknown}" >&2
    fi
fi

if [ "$gpu_ok" -eq 1 ]; then
    printf '  GTK may reject CPU Vulkan; hardware GL remains available.\n'
    printf '  verify: eglinfo -p wayland -B | grep "core profile renderer"\n'
else
    printf '  GTK will use llvmpipe unless a later driver/WSL update fixes D3D12.\n' >&2
fi

# Native Windows, for contrast. GTK built for Windows uses native WGL; WSLg
# uses Mesa D3D12 and has its own independent adapter preference.
#
# Which GPU it gets is a Windows setting, not a GTK one. On a hybrid-graphics
# laptop an app with no recorded preference is given the integrated GPU, and
# nothing announces this -- the first measurement here reported
# `AMD Radeon(TM) Graphics`, the Ryzen APU, on a machine whose discrete GPU is an
# RTX 4060. The name has no model number, which is the only hint that it is the
# integrated one.
#
#   HKCU\SOFTWARE\Microsoft\DirectX\UserGpuPreferences
#     <full path to the .exe>  REG_SZ  GpuPreference=1;   power saving  / integrated
#     <full path to the .exe>  REG_SZ  GpuPreference=2;   high performance / discrete
#
# Setting 2 for P0.exe switched the reported renderer to
# `NVIDIA GeForce RTX 4060 Laptop GPU/PCIe/SSE2`. The alternative is exporting
# NvOptimusEnablement from the executable, which needs a C shim; the registry
# route needs no code.
#
# The entry is keyed by full executable path, so every Pn.exe needs its own. That
# is the part worth remembering: without it a comparison silently runs two
# binaries on two different GPUs and the numbers look reasonable either way.
#
# WSL uses MESA_D3D12_DEFAULT_ADAPTER_NAME instead of this registry key. The
# configuration above discovers and records a working WSL adapter separately.
#
# 原生 Windows 使用 WGL；WSLg 則使用 Mesa D3D12，兩邊的介面卡偏好彼此獨立。
#
# 取得哪一顆 GPU 是 Windows 的設定，而非 GTK 的設定。在混合顯示卡筆電上，未登記偏好的程式
# 會被指派內顯，且沒有任何提示——此處第一次量測回報 `AMD Radeon(TM) Graphics`，即 Ryzen
# APU，而該機器的獨顯是 RTX 4060。該名稱不含型號，是判斷它為內顯的唯一線索。
#
# 將 P0.exe 設為 2 之後，回報的 renderer 變為
# `NVIDIA GeForce RTX 4060 Laptop GPU/PCIe/SSE2`。另一種做法是從執行檔匯出
# NvOptimusEnablement，但那需要 C shim；註冊表這條路則完全不需改動程式碼。
#
# 該設定以執行檔完整路徑為鍵，因此每支 Pn.exe 都需各自登記。這正是最值得記住的一點：少了它，
# 一次比較會在兩顆不同的 GPU 上靜默執行兩個二進位檔，而兩邊的數字看起來都很合理。
#
# WSL 不使用上述 registry key，而是透過 MESA_D3D12_DEFAULT_ADAPTER_NAME 選卡；前面的
# 探測會另外找出可用的 WSL adapter 並寫入設定。

section "Done"
printf 'Open a new login shell, or run:\n'
printf '  export PATH="%s/usr/bin:$PATH"\n' "$SWIFT_PREFIX"
if [ -f "$wslg_gpu_profile" ]; then
    printf '  . %s\n' "$wslg_gpu_profile"
fi
