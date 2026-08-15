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
        "Usage: zsh testapp/rsync_WSL.sh [--target <wsl-project-root>]" \
        "用法：zsh testapp/rsync_WSL.sh [--target <WSL 專案根目錄>]" \
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
