#!/usr/bin/env zsh
# Captures to testapp/output/screenshots/<label>-<timestamp>.png, in two
# priorities.
#
#   priority 1  with -w, gdigrab reads that window directly, whatever is in
#               front of it
#   priority 2  gdigrab reads the composited desktop
#
# Priority 2 is used when no -w is given, and as the fallback when the named
# window cannot be captured. Which one produced the file is printed, because it
# changes what the image proves.
#
# Window capture goes through BitBlt, which returns black for D3D and
# DirectComposition content, and that is why the desktop path exists and stays
# the fallback. It is not a reason to avoid window capture generally: GTK 4 on
# Windows draws through OpenGL/WGL and captures perfectly, while its windows do
# not respond to AppActivate at all, so for those the desktop path is the one
# that fails -- silently, by photographing whatever was in front instead.
#
# 擷取結果輸出至 testapp/output/screenshots/<label>-<timestamp>.png，分為兩個優先序。
#
#   優先序 1  指定 -w 時，gdigrab 直接讀取該視窗，不受前方遮擋影響
#   優先序 2  gdigrab 讀取合成後的桌面
#
# 未指定 -w 時使用優先序 2；當指定的視窗無法擷取時，亦以其作為回退。實際由哪一級產生檔案
# 會被印出，因為這會改變該圖所能證明的內容。
#
# 視窗擷取走 BitBlt，對 D3D 與 DirectComposition 內容會回傳全黑，這正是桌面路徑存在並作為
# 回退的理由。但它不構成「普遍避免視窗擷取」的理由：Windows 上的 GTK 4 透過 OpenGL/WGL
# 繪製，擷取完全正常，而其視窗根本不回應 AppActivate——對這類視窗而言，失敗的反而是桌面
# 路徑，且是靜默失敗：它會改拍下當時位於前方的任何內容。
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
        "  -w  Capture this window directly (priority 1), whatever is in front" \
        "      of it. Falls back to the whole desktop (priority 2) if that" \
        "      window cannot be captured. Which one was used is printed." \
        "  -w  直接擷取此視窗（優先序 1），不受前方遮擋影響。若無法擷取該視窗，" \
        "      則回退為擷取整個桌面（優先序 2）。實際使用哪一級會被印出。" \
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

# Raising the window is only needed by priority 2, which photographs the screen
# and therefore needs the window to be on top of it. Priority 1 reads the window
# directly and does not care what is in front, so this whole block is deferred
# into the fallback rather than run first.
#
# Running it first was worse than redundant: with -w it printed "could not bring
# the window to the front" on the exact runs where priority 1 then captured that
# window perfectly, which is a warning that contradicts the result beneath it.
#
# 把視窗帶到前景只有優先序 2 需要——它拍的是螢幕，因此該視窗必須位於最上層。優先序 1 直接
# 讀取視窗本身，不在意前方有什麼，所以整段延後至回退分支才執行，而非一開始就跑。
#
# 一開始就跑不只是多餘：指定 -w 時，它會在「優先序 1 隨後完美擷取到該視窗」的那些執行中，
# 印出「無法將視窗帶到前景」——一則與其下方結果自相矛盾的警告。
raise_window() {
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
    # Bounded, because cscript can block indefinitely. Measured: asked to
    # activate a window that does not exist, it never returned, and since this
    # runs under `set -e` inside a function whose output is not checked, the whole
    # capture hung with the last thing printed being an unrelated warning. Ten
    # seconds is far longer than AppActivate needs when it is going to answer.
    # 加上時間上限，因為 cscript 可能無限期阻塞。實測：要求它啟動一個不存在的視窗時，它從未
    # 返回；而本段在 `set -e` 下、位於一個輸出未被檢查的函式中執行，導致整個擷取流程掛住，
    # 最後印出的卻是一則不相干的警告。十秒遠長於 AppActivate 會回應時所需的時間。
    activated="$(timeout 10 cscript.exe //nologo "$(windows_path "$activate_script")" 2>/dev/null | tr -d '\r\n ' || true)"
    rm -f "$activate_script"
    if [ "$activated" != "ACTIVATED" ]; then
        printf '!! screenshot.zsh: could not bring "%s" to the front either.\n' "$window" >&2
        printf '!! The capture below is of whatever was on screen instead --\n' >&2
        printf '!! a locked session, another window, or nothing at all.\n' >&2
        printf '!! 亦無法將「%s」帶到前景；以下截圖拍到的是當時螢幕上的其他內容。\n' "$window" >&2
    fi
    # Deliberately no discard-frame grab here.
    #
    # This used to run `grab -frames:v 1 -f null -` to give the window a second
    # to come forward, which put two gdigrab desktop sessions back to back with
    # the real capture. That pair hangs: a single desktop capture returns in
    # about a second, while the -w path had to be killed by hand on four separate
    # runs today, each time leaving an ffmpeg holding the device. A plain capture
    # with no -w, which runs one gdigrab, never did.
    #
    # AppActivate has already returned by this point, so the window is raised or
    # it never will be; the wait was insurance against a race that costs a
    # screenshot, paid for with a hang that costs the run.
    #
    # 此處刻意不做丟棄影格的擷取。
    #
    # 先前這裡會執行 `grab -frames:v 1 -f null -`，讓視窗有一秒時間浮到最前面，結果是把兩個
    # gdigrab 桌面工作階段與真正的擷取連續排在一起。這個組合會卡住：單次桌面擷取約一秒即返回，
    # 而 -w 路徑今天有四次執行必須手動終止，每次都留下一個佔住裝置的 ffmpeg；未指定 -w、
    # 只執行一次 gdigrab 的一般擷取則從未發生此情況。
    #
    # 執行到此處時 AppActivate 已經返回，視窗要嘛已被喚起、要嘛永遠不會；那段等待是為了防範
    # 一個「頂多損失一張截圖」的競態，代價卻是「整次執行卡死」。
}

timestamp="$(date +%Y%m%d-%H%M%S)"
target="$output_dir/$label-$timestamp.png"

# Priority 1: the window itself, by title. Priority 2: the composited desktop.
#
# The desktop capture used to be the only path, and it fails in a way that looks
# like success. GTK 4 windows on Windows do not respond to AppActivate -- measured
# with the title resolved exactly, `P6-v2 GTK playback`, three times -- so the
# window stayed behind a terminal and three consecutive captures photographed the
# terminal. Each produced a valid PNG and a zero exit code. Capturing the window
# directly returned the player, its controls, its statistics and the video frame,
# from the same run.
#
# The file header long said window capture goes through BitBlt and comes back
# black for D3D and DirectComposition content. That is true and is why the
# desktop path exists, but it was over-generalised into "never capture a window":
# GTK draws through OpenGL/WGL here and captures perfectly. So the rule is a
# preference with a fallback, not a prohibition.
#
# The fallback triggers on a missing or suspiciously small file rather than on
# ffmpeg's exit code, which is 0 when gdigrab finds no window with that title.
#
# 優先序 1：依標題擷取視窗本身。優先序 2：擷取合成後的桌面。
#
# 桌面擷取原本是唯一路徑，而它失敗的方式看起來就像成功。Windows 上的 GTK 4 視窗不回應
# AppActivate——在標題完全正確（`P6-v2 GTK playback`）的情況下實測三次皆然——因此視窗一直
# 留在終端機後方，連續三次擷取拍到的都是終端機。每一次都產生了有效的 PNG 與 0 的結束碼。
# 而直接擷取該視窗，在同一次執行中就取得了播放器、其控制項、統計數據與影片畫面。
#
# 本檔開頭長期寫著：單一視窗擷取走 BitBlt，對 D3D 與 DirectComposition 內容會回傳全黑。
# 那是事實，也是桌面路徑存在的理由，但它被過度推廣成「永遠不要擷取視窗」：此處 GTK 透過
# OpenGL/WGL 繪製，擷取結果完全正常。因此這條規則是「有回退的偏好」，而非禁令。
#
# 回退的判斷依據是檔案不存在或小得可疑，而非 ffmpeg 的結束碼——當 gdigrab 找不到該標題的
# 視窗時，結束碼仍是 0。
captured_from=""
if [ -n "$window" ]; then
    # Resolve to the real title before priority 1, not only before the raise.
    # gdigrab matches a title exactly, and WSLg renames windows -- an app asking
    # for "P6 stream player" is presented as "P6 stream player (Ubuntu)". Looking
    # up the true title first is what makes priority 1 work on WSL at all;
    # resolving it only inside the fallback, as an earlier version did, left the
    # direct capture failing on every WSLg window for a reason that has nothing
    # to do with the window.
    # 在優先序 1 之前就解析出真實標題，而不只是在喚起視窗前才解析。gdigrab 進行的是標題的
    # 精確比對，而 WSLg 會替視窗改名——app 要求的「P6 stream player」會被呈現為
    # 「P6 stream player (Ubuntu)」。先查出真實標題，正是讓優先序 1 在 WSL 上得以運作的關鍵；
    # 若如先前版本那樣僅在回退分支中解析，直接擷取會在每個 WSLg 視窗上失敗，而原因與該視窗
    # 本身毫無關係。
    # The lookup also decides whether priority 1 is attempted at all. gdigrab
    # asked for a title that does not exist behaves badly from a script: run by
    # hand it prints `Can't find window` and exits, but inside this file it did
    # not return, and with output buffered to a redirect the script died at its
    # timeout having printed nothing -- no warning, no path, no clue which line.
    # Asking tasklist first costs one call and removes that case entirely.
    # 這次查詢同時決定是否要嘗試優先序 1。以不存在的標題呼叫 gdigrab 在腳本中的表現很糟：
    # 手動執行時它會印出 `Can't find window` 並結束，但在本檔內它並未返回；而當輸出被重導向
    # 而遭緩衝時，腳本會在逾時後死去且什麼都沒印出——沒有警告、沒有路徑、也沒有任何線索指出
    # 是哪一行。先問 tasklist 只需一次呼叫，即可完全消除這種情況。
    resolved_title="$(resolve_window_title "$window" || true)"
    if [ -z "$resolved_title" ]; then
        printf '!! screenshot.zsh: priority 1 skipped -- no window whose title\n' >&2
        printf '!! contains "%s" is open. Using priority 2, the whole desktop,\n' "$window" >&2
        printf '!! which shows that window only if it is in front.\n' >&2
        printf '!! 優先序 1 略過：沒有任何標題包含「%s」的視窗開啟中。改用優先序 2\n' "$window" >&2
        printf '!!（整個桌面），該圖僅在此視窗位於最上層時才會包含它。\n' >&2
        window_missing=1
    elif [ "$resolved_title" != "$window" ]; then
        printf 'resolved window title to "%s"\n' "$resolved_title" >&2
        window="$resolved_title"
    fi

    # `|| true` because this file runs under `set -e` and gdigrab can still exit
    # non-zero even for a window that tasklist just reported -- it can close
    # between the two calls. Without it the script aborts here having printed
    # nothing: no warning, no file, and exit 127, which reads like a missing
    # interpreter rather than a missing window.
    # `|| true`：本檔在 `set -e` 下執行，而即使是 tasklist 剛回報過的視窗，gdigrab 仍可能以
    # 非零狀態結束——該視窗可能在兩次呼叫之間關閉。少了它，腳本會在此中止且什麼都沒印出：
    # 沒有警告、沒有檔案，只有 exit 127，看起來像是直譯器缺失而非視窗缺失。
    if [ "${window_missing:-0}" -eq 0 ]; then
        ffmpeg -hide_banner -loglevel error -f gdigrab -framerate 1 \
            -i "title=$window" -frames:v 1 -y "$target" </dev/null 2>/dev/null || true
    fi
    if [ -f "$target" ] && [ "$(stat -c%s "$target" 2>/dev/null || echo 0)" -gt 5000 ]; then
        captured_from="priority 1: window \"$window\""
    else
        rm -f "$target"
        # Said out loud, because the fallback changes what the image means. A
        # priority 1 capture shows the requested window whatever is in front of
        # it; a priority 2 capture shows the screen, which contains the window
        # only if it happened to be raised. Reading the second as the first is
        # how three captures of a terminal were taken for captures of a player.
        # 明確說出，因為回退會改變這張圖的意義。優先序 1 的擷取無論前方有什麼，呈現的都是
        # 所指定的視窗；優先序 2 呈現的是整個螢幕，只有在該視窗剛好位於最上層時才會包含它。
        # 把後者當成前者，正是三張終端機截圖被誤認為播放器截圖的原因。
        #
        # Not repeated when the window was already reported missing above; two
        # warnings for one cause reads as two problems.
        # 若上方已回報該視窗不存在，則不重複輸出；同一個成因印出兩則警告，會被讀成兩個問題。
        if [ "${window_missing:-0}" -eq 0 ]; then
            printf '!! screenshot.zsh: priority 1 failed -- the window titled\n' >&2
            printf '!! "%s" could not be captured. Falling back to priority 2,\n' "$window" >&2
            printf '!! the whole desktop, which shows it only if it is in front.\n' >&2
            printf '!! 優先序 1 失敗：無法擷取標題為「%s」的視窗。改用優先序 2（整個桌面），\n' "$window" >&2
            printf '!! 該圖僅在此視窗位於最上層時才會包含它。\n' >&2
        fi
    fi
fi

if [ -z "$captured_from" ]; then
    [ -n "$window" ] && raise_window
    grab -frames:v 1 -y "$target" </dev/null
    if [ -n "$window" ]; then
        captured_from="priority 2: desktop (window capture failed)"
    else
        # No -w was given, so the desktop is what was asked for rather than a
        # fallback, and calling it one would be misleading.
        # 未指定 -w，因此桌面正是所要求的目標而非回退；把它稱為回退會造成誤導。
        captured_from="desktop"
    fi
fi

printf '%s\n' "$target"
printf 'captured from %s\n' "$captured_from"
