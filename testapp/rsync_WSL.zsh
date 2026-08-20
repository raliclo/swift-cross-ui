#!/usr/bin/env zsh
set -euo pipefail

# Sync all Swift sources and testapp zsh helper scripts into the WSL copy.
# This intentionally does not delete files on the WSL side: output, build
# caches, and local WSL edits should be left alone.
#
# The consequence is that deletions do not propagate. Removing a file here
# leaves it in place over there, and SwiftPM ignores source directories that
# Package.swift no longer declares, so the WSL build keeps succeeding on a tree
# that no longer matches this one. Measured: dropping GTK3 removed 193 files
# locally and every one of them was still in WSL afterwards, with all targets
# still building. Delete them in WSL by hand after removing anything here.
# 由此產生的後果是：刪除不會傳播。在此處移除檔案，對面仍會留著，而 SwiftPM 會忽略
# Package.swift 不再宣告的原始碼目錄，因此 WSL 端會在一棵已經與此處不一致的樹上持續
# 建置成功。實測：移除 GTK3 在本機刪掉 193 個檔案，事後那些檔案全部仍在 WSL，且所有
# target 依然建置通過。在此處刪除任何東西之後，請手動清除 WSL 端的對應檔案。

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
    `# C sources and headers. Swift is not the whole of this package: GtkCHelpers` \
    `# and CGtk are C, and without these lines the WSL copy kept whatever C files` \
    `# were there when the directory was created. Found when a new shim in` \
    `# gtk_helpers.c failed as "cannot find ... in scope" on WSL while compiling` \
    `# on Windows -- which reads as a Swift visibility problem, not a missing file.` \
    `# C 原始碼與標頭檔。本套件並非全由 Swift 構成：GtkCHelpers 與 CGtk 都是 C，若缺少這幾行，` \
    `# WSL 端的副本會停留在該目錄建立當時的 C 檔案。此問題是在 gtk_helpers.c 新增 shim 後被發現的` \
    `# ——它在 Windows 上編譯正常，在 WSL 上卻報 "cannot find ... in scope"，而該訊息看起來像是` \
    `# Swift 的可見性問題，而非檔案缺失。` \
    --include='*.c' \
    --include='*.h' \
    --include='*.modulemap' \
    --include='testapp/*.zsh' \
    --include='testapp/**/*.zsh' \
    `# The one .sh worth copying: it is the bootstrap that installs zsh, so it` \
    `# has to reach a machine that cannot yet run the .zsh files above. Without` \
    `# this line the WSL copy stayed at whatever version was there when the` \
    `# directory was first created -- found still on an August 16 build.` \
    `# 唯一值得複製的 .sh：它是安裝 zsh 的引導程式，因此必須送達一台尚無法執行上述` \
    `# .zsh 檔案的機器。少了這一行，WSL 端的副本會停留在該目錄初次建立時的版本——` \
    `# 實際發現它仍是 8 月 16 日的版本。` \
    --include='testapp/install_tool_wsl.sh' \
    `# Action files for -actionfile. Not covered by the patterns above, and the` \
    `# failure is quiet in the wrong way: the app launches, renders, and reports` \
    `# only that a file it was told to replay does not exist -- while the same` \
    `# file sits in the Windows checkout, edited a moment earlier.` \
    `# 供 -actionfile 使用的動作檔。上述樣式並未涵蓋，而其失敗方式的安靜之處正在於：app 會啟動、` \
    `# 繪製，只回報「被指定重放的檔案不存在」——而同一個檔案就在 Windows 端的 checkout 裡，` \
    `# 且是片刻之前才編輯過的。` \
    --include='testapp/actions/*.csv' \
    --exclude='*' \
    '$source_root/' \
    '$wsl_project_root/'
find '$wsl_project_root/testapp' -type f -name '*.zsh' -exec chmod +x {} +
"

printf 'Synced *.swift, testapp/**/*.zsh and install_tool_wsl.sh to %s\n' "$wsl_project_root"
