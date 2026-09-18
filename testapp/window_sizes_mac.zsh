#!/usr/bin/env zsh
# Reports the window each built macOS test app opens at, and the numbers behind it.
#
#   zsh testapp/window_sizes_mac.zsh                    every built P*
#   zsh testapp/window_sizes_mac.zsh P5 P36 P50         only these
#   zsh testapp/window_sizes_mac.zsh --csv out.csv2     also write a csv2 table
#
# The AppKit counterpart to `window_sizes.zsh`, which does this on Windows with
# wincap. Same reason for existing -- every action file's coordinates are
# measured off one app's window, so an app whose size changes between builds
# silently invalidates the file measured against it -- and one addition: it
# prints the three numbers that DECIDE the size, not only the size.
#
# `WindowReference` opens a window at `max(minimumWindowSize, proposedWindowSize)`,
# clamped by a maximum when the scene asks for one. `SCUI_DEBUG_WINDOW_SIZE=1`
# makes every window update print those, so a window that came out an odd size
# can be read rather than guessed at: a window sitting exactly on its minimum is
# a window whose content asked for less than it needs, which is what P50 turned
# out to be on 2026-09-17.
#
# TWO THINGS THAT WILL OTHERWISE MISLEAD YOU:
#
#   1. **AppKit restores a saved window frame over `.defaultSize`.**
#      `createWindow` calls `setFrameAutosaveName`, so the size in user defaults
#      wins over the code. Every launch here runs `defaults delete <app>` first;
#      without it you measure the last run rather than this build.
#   2. **The instrument only exists in binaries built after 2026-09-17.** An
#      older binary prints nothing and this script reports its size with
#      `minimum -` rather than pretending it knows.
#
# 回報每一支已建置的 macOS 測試 app 開在什麼視窗尺寸,以及決定那個尺寸的數字。
#
# 這是 `window_sizes.zsh` 的 AppKit 對應版本(那一支在 Windows 上以 wincap 做同一件事)。存在的理由相同
# ——每一份動作檔的座標都是量自某一支 app 的視窗,因此一支「尺寸在兩次建置之間改變」的 app,會靜默地
# 作廢那份依它量出來的檔案——並多做一件事:它印出**決定**尺寸的那三個數字,而不只是尺寸。
#
# `WindowReference` 以 `max(minimumWindowSize, proposedWindowSize)` 開啟視窗(若 scene 要求上限則再夾住)。
# `SCUI_DEBUG_WINDOW_SIZE=1` 會讓每次視窗更新印出那些值,於是一個尺寸古怪的視窗可以被**讀出來**而不是
# 猜出來:一個正好坐在自己最小尺寸上的視窗,就是「內容要求的比它需要的少」——2026-09-17 的 P50 正是如此。
#
# 有兩件事若不說會誤導你:
#
#   1. **AppKit 會用儲存的視窗框蓋過 `.defaultSize`。** `createWindow` 呼叫了
#      `setFrameAutosaveName`,因此 user defaults 裡的尺寸會贏過程式碼。此處每次啟動前都會先
#      `defaults delete <app>`;少了那一步,你量到的是上一次執行,而不是這次建置。
#   2. **那支儀器只存在於 2026-09-17 之後建置的二進位裡。** 較舊的二進位什麼都不會印,而本腳本會以
#      `minimum -` 回報,而不是假裝它知道。

set -u

script_dir=${0:A:h}
output_dir="$script_dir/output"
csv_path=""
apps=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        --csv)
            if [ "$#" -lt 2 ]; then
                print -u2 -r -- "--csv needs a path"
                exit 64
            fi
            csv_path="$2"
            shift 2
            ;;
        --csv=*) csv_path="${1#*=}"; shift ;;
        -h|--help)
            sed -n '2,12p' "$0"
            exit 0
            ;;
        *) apps+=("$1"); shift ;;
    esac
done

if [ "${#apps}" -eq 0 ]; then
    apps=(${(f)"$(ls "$output_dir" | grep -E '^P[0-9]+$' | sort -V)"})
fi

# A window that is exactly its own minimum is the case worth seeing, so it is
# flagged rather than left for the reader to spot in a column of numbers.
# 一個「正好等於自己最小尺寸」的視窗,才是值得被看見的情況,因此它會被標記出來,而不是留給讀者自己
# 從一整欄數字裡找。
printf '%-6s %-12s %-12s %-12s %s\n' app window proposed minimum note
rows=()

for app in "${apps[@]}"; do
    binary="$output_dir/$app"
    [ -x "$binary" ] || continue

    defaults delete "$app" >/dev/null 2>&1
    log=$(mktemp)
    (SCUI_DEBUG_WINDOW_SIZE=1 "$binary" 2>"$log" >/dev/null &)
    sleep 5

    size=$(osascript -e "tell application \"System Events\" to tell (first process whose name contains \"$app\") to get size of window 1" 2>/dev/null | tr -d ' ')
    line=$(grep -m1 '^-window:' "$log" 2>/dev/null)
    pkill -f "$output_dir/$app" >/dev/null 2>&1
    rm -f "$log"

    if [ -z "$line" ]; then
        proposed="-"; minimum="-"; note="no instrument in this binary; rebuild it"
    else
        proposed=$(print -r -- "$line" | sed -n 's/.*proposed SIMD2<Int>(\([0-9]*\), \([0-9]*\)).*/\1x\2/p')
        minimum=$(print -r -- "$line" | sed -n 's/.*minimum SIMD2<Int>(\([0-9]*\), \([0-9]*\)).*/\1x\2/p')
        note=""
        if [ -n "$proposed" ] && [ -n "$minimum" ]; then
            pw=${proposed%x*}; ph=${proposed#*x}
            mw=${minimum%x*}; mh=${minimum#*x}
            [ "$mw" -ge "$pw" ] && note="width set by the minimum"
            if [ "$mh" -ge "$ph" ]; then
                [ -n "$note" ] && note="$note; height set by the minimum" \
                    || note="height set by the minimum"
            fi
        fi
    fi

    [ -z "$size" ] && size="(no window)"
    printf '%-6s %-12s %-12s %-12s %s\n' "$app" "${size/,/x}" "${proposed:--}" "${minimum:--}" "$note"
    rows+=("$app,${size/,/x},${proposed:--},${minimum:--},\"$note\"")
done

if [ -n "$csv_path" ]; then
    {
        print -r -- "app,window,proposed,minimum,note"
        print -r -- "app,視窗,提議,最小,備註"
        for row in "${rows[@]}"; do print -r -- "$row"; done
    } > "$csv_path"
    print -r -- "wrote $csv_path"
fi
