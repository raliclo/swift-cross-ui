#!/usr/bin/env zsh
set -euo pipefail

# Sync all Swift sources and testapp zsh helper scripts into the WSL copy.
# This intentionally does not delete files on the WSL side: output, build
# caches, and local WSL edits should be left alone.

script_dir="${0:a:h}"
repo_root="${script_dir:h}"
wsl_project_root="${WSL_PROJECT_ROOT:-/home/lowei/proj/swift-cross-ui}"
wsl_exe="${WSL_EXE:-wsl.exe}"

usage() {
    printf '%s\n' \
        "Usage: zsh testapp/rsync_WSL.zsh [--target <wsl-project-root>]" \
        "用法：zsh testapp/rsync_WSL.zsh [--target <WSL 專案根目錄>]" \
        "" \
        "Only syncs:" \
        "  **/*.swift" \
        "  testapp/**/*.zsh"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --target)
            [ "$#" -ge 2 ] || { usage >&2; exit 64; }
            wsl_project_root="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 64
            ;;
    esac
done

to_wsl_path() {
    case "$1" in
        /?/*)
            drive="$(printf '%s' "$1" | cut -c 2 | tr '[:upper:]' '[:lower:]')"
            rest="$(printf '%s' "$1" | cut -c 4-)"
            printf '/mnt/%s/%s\n' "$drive" "$rest"
            ;;
        [A-Za-z]:/*)
            drive="$(printf '%s' "$1" | cut -c 1 | tr '[:upper:]' '[:lower:]')"
            rest="$(printf '%s' "$1" | cut -c 4-)"
            printf '/mnt/%s/%s\n' "$drive" "$rest"
            ;;
        *)
            printf '%s\n' "$1"
            ;;
    esac
}

source_root="$(to_wsl_path "$repo_root")"

# The include/exclude order below is rsync's, and it is not intuitive: the
# first matching rule wins, so the `--include='*/'` that lets rsync walk into
# directories has to come before the file patterns, and the closing
# `--exclude='*'` has to come last or it would swallow everything.
#
# Only sources are copied, never build output. The WSL checkout keeps its own
# .build and .compile-work; overwriting them from Windows would mean shipping
# object files built for the wrong platform. `output/` is excluded for the same
# reason -- the two sides produce P7 and P7.exe from the same source and both
# must survive.
# 下方 include/exclude 的順序是 rsync 的規則，並不直觀：先命中者勝，因此讓 rsync
# 能進入目錄的 `--include='*/'` 必須排在檔案樣式之前，而收尾的 `--exclude='*'`
# 必須放最後，否則會把所有東西一併排除。
#
# 只複製原始碼、不複製建置產物。WSL 端有自己的 .build 與 .compile-work，從 Windows
# 覆蓋過去等於送進為錯誤平台編譯的目的檔；`output/` 同理——兩邊由同一份原始碼分別
# 產出 P7 與 P7.exe，兩者都必須保留。
"$wsl_exe" -e zsh -lc "
set -euo pipefail
command -v rsync >/dev/null || { echo 'rsync is required in WSL.' >&2; exit 127; }
mkdir -p '$wsl_project_root'
rsync -a \
    --exclude='.git/' \
    --exclude='.build/' \
    --exclude='.swiftpm/' \
    --exclude='.compile-work/' \
    --exclude='.tmp/' \
    --exclude='output/' \
    --include='*/' \
    --include='*.swift' \
    --include='testapp/*.zsh' \
    --include='testapp/**/*.zsh' \
    --exclude='*' \
    '$source_root/' \
    '$wsl_project_root/'
chmod +x '$wsl_project_root/testapp/'*.zsh
"

printf 'Synced all *.swift and testapp/*.zsh to %s\n' "$wsl_project_root"
