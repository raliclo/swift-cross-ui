#!/usr/bin/env zsh
# Captures the desktop to testapp/output/screenshots/<label>-<timestamp>.png.
#
# Uses ffmpeg's gdigrab, which reads the already-composited screen. Capturing a
# single window instead goes through BitBlt, which comes back black for
# D3D/DirectComposition content -- exactly the content this is used to check.
# 使用 ffmpeg 的 gdigrab 擷取「已合成」的螢幕畫面。若改為擷取單一視窗會走
# BitBlt，對 D3D/DirectComposition 內容只會得到全黑，而那正是本工具要檢查的
# 內容。
#
# The wait before capturing is done by grabbing one frame per second and
# overwriting the same file, so no sleep is needed and the file always holds
# the most recent frame.
# 等待是靠每秒抓一張並覆寫同一個檔案達成，因此不需要 sleep，檔案內容永遠是最新
# 的一張。

set -euo pipefail

script_dir="${0:a:h}"
output_dir="$script_dir/output/screenshots"

windows_path() {
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -w "$1"
        return
    fi

    case "$1" in
        /?/*)
            local drive rest
            drive="$(printf '%s' "$1" | cut -c 2 | tr '[:lower:]' '[:upper:]')"
            rest="$(printf '%s' "$1" | cut -c 4- | tr '/' '\\')"
            printf '%s:\\%s\n' "$drive" "$rest"
            ;;
        *)
            printf '%s\n' "$1"
            ;;
    esac
}

usage() {
    printf '%s\n' \
        "Usage: screenshot.zsh [-d <seconds>] [-w <window title>] [<label>]" \
        "用法：screenshot.zsh [-d <秒數>] [-w <視窗標題>] [<標籤>]" \
        "" \
        "  -d  Wait this many seconds before capturing (default 0)." \
        "  -d  擷取前先等待的秒數（預設 0）。" \
        "  -w  Raise this window to the front just before capturing." \
        "  -w  擷取前先把這個視窗帶到最前面。" \
        "" \
        "Example 範例:" \
        "  zsh testapp/screenshot.zsh -d 15 -w 'P6 stream player' p6-960x540"
}

delay=0
label="screen"
window=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        -d)
            if [ "$#" -lt 2 ]; then
                usage >&2
                exit 64
            fi
            delay="$2"
            shift 2
            ;;
        -w)
            if [ "$#" -lt 2 ]; then
                usage >&2
                exit 64
            fi
            window="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            label="$1"
            shift
            ;;
    esac
done

mkdir -p "$output_dir"

grab() {
    ffmpeg -hide_banner -loglevel error -f gdigrab -framerate 1 -i desktop "$@"
}

# Discarded frames are the wait: one per second, decoded and thrown away.
# 丟棄的影格就是等待：每秒一張，解碼後直接丟掉。
if [ "$delay" -gt 0 ]; then
    grab -frames:v "$delay" -f null - </dev/null
fi

# Windows has no built-in command that activates a window, so drive WSH's
# AppActivate, which does. cscript is a stock Windows tool, called the same way
# this repo calls other native tools from the shell.
# Windows 沒有內建可啟動視窗的命令，因此改用 WSH 的 AppActivate；cscript 是系統
# 內建工具，呼叫方式與本專案從 shell 呼叫其他原生工具一致。
# WSLg does not present a Linux window to Windows under the title the app set.
# It appends the distribution -- "P6 stream player (Ubuntu)" -- and prefixes a
# warning when its own rendering path has degraded:
#
#   [WARN:COPY MODE] P6 stream player (Ubuntu)
#
# AppActivate matches the beginning or the end of a title, so that prefix breaks
# a search for "P6 stream player" while the suffix alone does not. Measured: a
# WSL self-update from 2.7.11 to 2.7.12 left the running WSLg in COPY MODE, and
# from then on every capture reported "could not bring the window to the front"
# and photographed whatever else was on screen. The window was there the whole
# time, under a name nobody was looking for.
#
# So the requested name is treated as a substring, resolved against the real
# titles, and COPY MODE is called out rather than left to be discovered.
# WSLg 不會以 app 自己設定的標題把 Linux 視窗呈現給 Windows。它會附加發行版名稱——
# 「P6 stream player (Ubuntu)」——並在自身的算繪路徑降級時加上前綴：
#
#   [WARN:COPY MODE] P6 stream player (Ubuntu)
#
# AppActivate 比對的是標題的開頭或結尾，因此該前綴會使「P6 stream player」的搜尋失敗，
# 而僅有後綴時則不會。實測：WSL 從 2.7.11 自我更新至 2.7.12 後，執行中的 WSLg 陷入
# COPY MODE，自此每次擷取都回報「無法將視窗帶到前景」並拍下當時螢幕上的其他內容。
# 視窗自始至終都在，只是名字不是任何人在找的那個。
#
# 因此把傳入的名稱視為子字串、對照真實標題解析，並主動點出 COPY MODE，而不是留給人去發現。
resolve_window_title() {
    local wanted="$1"
    MSYS2_ARG_CONV_EXCL='*' tasklist.exe /v /fo csv 2>/dev/null \
        | tr -d '\0\r' \
        | sed 's/^"//; s/"$//' \
        | awk -F'","' -v want="$wanted" \
            'NR>1 && $9 != "N/A" && index($9, want) { print $9; exit }'
}

if [ -n "$window" ]; then
    resolved="$(resolve_window_title "$window")"
    if [ -n "$resolved" ] && [ "$resolved" != "$window" ]; then
        case "$resolved" in
            *"COPY MODE"*)
                printf '!! screenshot.zsh: WSLg is in COPY MODE -- its rendering path has\n' >&2
                printf '!! degraded and the window will not come to the front. Run\n' >&2
                printf '!! `wsl --shutdown` on Windows and reopen WSL, then retry.\n' >&2
                # Printed for a person to act on, never run from here. A
                # shutdown kills everything in the distribution, including
                # long-running services that have nothing to do with this
                # project -- multisshd was killed twice that way. Whoever is at
                # the keyboard decides when that is acceptable.
                # 此訊息供人判斷後自行執行，絕不由腳本代為執行。關閉 WSL 會終止該發行版中
                # 的一切，包含與本專案無關的長時間執行服務——multisshd 就曾因此被殺掉兩次。
                # 何時可以接受，由當下操作的人決定。
                printf '!! WSLg 目前處於 COPY MODE，算繪路徑已降級，視窗無法帶到前景。\n' >&2
                printf '!! 請於 Windows 執行 `wsl --shutdown` 後重開 WSL，再重試。\n' >&2
                ;;
        esac
        window="$resolved"
    fi

    activate_script="$output_dir/activate-$$.vbs"
    # AppActivate returns whether it found and raised the window. That answer
    # used to be discarded, which made the one failure mode that matters
    # invisible: a locked session, or a window that never opened, still
    # produced a screenshot file and a run that looked entirely successful.
    # One such capture in this repo was of the Windows lock screen, and only a
    # human looking at the image noticed.
    #
    # A false is not proof the session is locked -- a wrong title or an app
    # that died gives the same answer. All three mean the same thing for the
    # caller: the picture does not show what was asked for.
    # AppActivate 會回報是否找到並喚起了視窗。先前這個答案被丟棄，使得唯一真正要緊
    # 的失敗模式變得不可見：工作階段被鎖定、或視窗根本沒開，仍然會產生截圖檔，執行
    # 結果也看起來完全成功。本專案就發生過一次，拍到的是 Windows 鎖定畫面，而且是靠
    # 人看圖才發現。
    #
    # 回傳 false 並不足以證明是鎖定：標題打錯或 app 已結束也會得到同樣結果。但對呼叫
    # 端而言三者意義相同——這張圖並未呈現所要求的內容。
    # The script emits a word rather than the boolean itself. `WScript.Echo`
    # given a Boolean prints `-1`, not `True` -- a first version compared
    # against "True" and so reported failure on every capture, including the
    # ones that worked. A warning that fires every time teaches the reader to
    # ignore it, which is worse than having none.
    # 這段腳本輸出的是字串而非布林值本身。`WScript.Echo` 印布林時會印出 `-1` 而非
    # `True`——第一版拿 "True" 比對，於是每次擷取都回報失敗，包含成功的那些。每次
    # 都響的警告只會訓練讀者忽略它，比沒有更糟。
    printf 'If CreateObject("WScript.Shell").AppActivate("%s") Then\n  WScript.Echo "ACTIVATED"\nElse\n  WScript.Echo "NOTFOUND"\nEnd If\n' \
        "$window" > "$activate_script"
    activated="$(cscript.exe //nologo "$(windows_path "$activate_script")" 2>/dev/null | tr -d '\r\n ')"
    rm -f "$activate_script"
    if [ "$activated" != "ACTIVATED" ]; then
        printf '!! screenshot.zsh: could not bring "%s" to the front.\n' "$window" >&2
        printf '!! The capture below is of whatever was on screen instead --\n' >&2
        printf '!! a locked session, another window, or nothing at all.\n' >&2
        printf '!! 無法將「%s」帶到前景；以下截圖拍到的是當時螢幕上的其他內容。\n' "$window" >&2
    fi
    # One discarded frame gives the window a second to come forward.
    # 丟棄一張影格，讓視窗有一秒的時間浮到最前面。
    grab -frames:v 1 -f null - </dev/null
fi

timestamp="$(date +%Y%m%d-%H%M%S)"
target="$output_dir/$label-$timestamp.png"

grab -frames:v 1 -y "$target" </dev/null

printf '%s\n' "$target"
