#!/usr/bin/env zsh
# Installs a portable, silent NVDA for reading what a screen reader says (Windows only).
#
#   zsh testapp/install_nvda_windows.zsh            unpack into $LOCALAPPDATA/nvda-portable
#   zsh testapp/install_nvda_windows.zsh --help
#   NVDA_PORTABLE=<dir> zsh testapp/install_nvda_windows.zsh
#
# For #123 (queue.md row 8): Narrator cannot be scripted or logged, but NVDA reads
# the same UIA tree and logs every utterance at log level 12 (input/output), so an
# NVDA transcript of P69 is the mechanical stand-in for listening. The copy is
# portable -- nothing goes into Program Files or the registry -- and its synth is
# `silence`, so a run says nothing aloud. Idempotent: an existing copy is kept.
# 安裝一份可攜、靜音的 NVDA,用來讀出螢幕報讀器實際說了什麼(僅限 Windows)。供 #123(queue.md 第 8 列)使用:
# Narrator 無法以程式控制或記錄，但 NVDA 讀的是同一棵 UIA 樹，並在記錄等級 12(input/output)記下每句話，因此 P69 的
# NVDA 逐字稿就是「用耳朵聽」的機械替代。這是可攜版——不寫入 Program Files 或登錄檔——語音合成器設為 `silence`,
# 執行時不會發出聲音。冪等：已存在的副本會保留。
set -euo pipefail
script_path="${0:A}"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    sed -n '2,17p' "$script_path" | sed 's/^# \{0,1\}//'
    exit 0
fi

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) ;;
    *) printf 'install_nvda_windows.zsh: Windows only (uname -s = %s)\n' "$(uname -s)" >&2; exit 2 ;;
esac

target="${NVDA_PORTABLE:-$(cygpath -u "$LOCALAPPDATA")/nvda-portable}"
if [[ -x "$target/nvda.exe" ]]; then
    printf '==> NVDA already at %s\n' "$target"
else
    download="$target.download"
    mkdir -p "$download"
    printf '==> Downloading NVDA with winget into %s\n' "$download"
    # winget, not a pinned URL: it verifies the installer hash.
    # 用 winget 而非寫死的網址：它會核對安裝檔的雜湊值。
    MSYS2_ARG_CONV_EXCL='*' winget.exe download --id NVAccess.NVDA --exact \
        --accept-source-agreements --accept-package-agreements \
        -d "$(cygpath -w "$download")" | tr -d '\r' | tail -3
    launcher=$(ls "$download"/*.exe | head -1)
    printf '==> Creating the portable copy at %s\n' "$target"
    # --create-portable-silent makes the copy without starting it.
    # --create-portable-silent 只建立副本，不啟動它。
    MSYS2_ARG_CONV_EXCL='*' "$launcher" --create-portable-silent \
        "--portable-path=$(cygpath -w "$target")"
    for _ in {1..120}; do
        [[ -x "$target/nvda.exe" ]] && break
        sleep 1
    done
    [[ -x "$target/nvda.exe" ]] || { printf '!! no nvda.exe in %s after 120 s\n' "$target" >&2; exit 1; }
fi

# Silent, no welcome dialog, no update check. A portable copy reads userConfig/
# beside it.
# 靜音、不顯示歡迎對話框、不檢查更新。可攜版讀取它旁邊的 userConfig/。
mkdir -p "$target/userConfig"
printf '%s\n' '[general]' '	showWelcomeDialogAtStartup = False' '[speech]' '	synth = silence' \
    '[update]' '	autoCheck = False' > "$target/userConfig/nvda.ini"
printf '==> NVDA ready: %s/nvda.exe (synth silence)\n' "$target"
printf '    run: "%s/nvda.exe" --log-level=12 --log-file=<file>, and "nvda.exe -q" to quit\n' "$target"
