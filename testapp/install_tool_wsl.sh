#!/bin/bash
# Bootstrap only. Installs zsh, then hands the whole job to install_tool_wsl.zsh.
#
#   wsl -d Ubuntu -u root -- bash testapp/install_tool_wsl.sh
#   wsl -d Ubuntu -u root -- bash testapp/install_tool_wsl.sh --help
#
# 僅負責引導：安裝 zsh，然後把整個工作交給 install_tool_wsl.zsh。
#
# This is the one file in testapp/ that is not zsh, and it stays that way for a
# reason that cannot be worked around: it runs against a stock Ubuntu where zsh
# is not installed, and installing zsh is its job. A zsh shebang would make the
# script fail to start on precisely the machine it exists to prepare -- not with
# a useful message, but with the kernel refusing to find an interpreter.
#
# So it does nothing except get zsh onto the machine and step aside, the same
# shape as a self-elevating .ps1 launcher that hands off immediately. Every line
# of real logic lives in the .zsh, where it can be read and changed in one
# place. Arguments are forwarded, so --help reaches the zsh script.
# 這是 testapp/ 中唯一不是 zsh 的檔案，而且有一個繞不過去的理由：它面對的是尚未安裝
# zsh 的原生 Ubuntu，而安裝 zsh 正是它的工作。若使用 zsh shebang，這支腳本會在「它
# 存在的目的所指向的那台機器」上根本無法啟動——而且不是給出有用的訊息，是核心找不到
# 直譯器。
#
# 因此它只做兩件事：把 zsh 裝上去，然後讓開；形狀與「自我提權後立刻交棒」的 .ps1
# launcher 相同。所有實際邏輯都在 .zsh 裡，可在單一位置閱讀與修改。引數會原樣轉交，
# 因此 --help 會傳到 zsh 腳本。

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
handoff="$script_dir/install_tool_wsl.zsh"

if [ ! -f "$handoff" ]; then
    echo "Missing $handoff -- this bootstrap has nothing to hand off to." >&2
    exit 1
fi

# --help must not install anything. Checked here rather than only in the zsh
# script, because reaching that check would otherwise mean running apt first.
# --help 不應安裝任何東西。此處先行檢查，而非只在 zsh 腳本中處理，否則要走到那個檢查
# 就得先執行 apt。
for arg in "$@"; do
    case "$arg" in
        -h|--help)
            if command -v zsh >/dev/null 2>&1; then
                exec zsh "$handoff" --help
            fi
            sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
            echo
            echo "zsh is not installed yet, so the full help lives in:"
            echo "  $handoff"
            exit 0
            ;;
    esac
done

if [ "$(id -u)" -ne 0 ]; then
    echo "This script installs system packages; run it as root:" >&2
    echo "  wsl -d <distro> -u root -- bash $0" >&2
    exit 1
fi

if ! command -v zsh >/dev/null 2>&1; then
    echo "==> Installing zsh so the rest of the setup can run"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y --no-install-recommends zsh
fi

exec zsh "$handoff" "$@"
