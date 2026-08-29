#!/usr/bin/env zsh
# Captures to testapp/output/screenshots/<label>-<timestamp>.png, in two
# priorities.
#
#   priority 1  with -w, wincap asks DWM to render that window through
#               PrintWindow(PW_RENDERFULLCONTENT)
#   desktop     without -w, gdigrab reads the composited desktop
#
# Desktop capture is used only when no -w is given. A named-window capture that
# wincap cannot complete fails instead of substituting a desktop screenshot.
#
# The old gdigrab window path went through BitBlt, which returns black for some
# top-level window styles and can hang when called from this script. Windows
# `-w` therefore uses `wincap.swift` only: PrintWindow(PW_RENDERFULLCONTENT),
# a non-black bitmap check, and BMP-to-PNG conversion. Desktop capture remains
# available only when explicitly requested by omitting -w.
#
# 擷取結果輸出至 testapp/output/screenshots/<label>-<timestamp>.png，分為兩個優先序。
#
#   優先序 1  指定 -w 時，wincap 透過 PrintWindow(PW_RENDERFULLCONTENT) 要求 DWM
#             算繪該視窗
#   desktop     未指定 -w 時，gdigrab 讀取合成後的桌面
#
# 只有未指定 -w 時才使用 desktop capture。指定視窗但 wincap 無法擷取時會失敗，不再以
# desktop screenshot 替代。
#
# 舊的 gdigrab 視窗路徑走 BitBlt，對若干 top-level window styles 會回傳全黑，且在此腳本
# 中可能卡住。因此 Windows `-w` 只使用 `wincap.swift`：PrintWindow(PW_RENDERFULLCONTENT)、
# 非黑 bitmap 檢查，以及 BMP-to-PNG 轉換。只有明確省略 -w 時才使用 desktop capture。
#
# The wait differs by path. Window capture sleeps, then asks wincap for one
# rendered image. Desktop capture still waits by grabbing one frame per second
# and overwriting the same file, so the file always holds the most recent frame.
# 等待方式依路徑不同。視窗擷取會先 sleep，再請 wincap 取得一張已算繪影像。桌面擷取仍靠每秒
# 抓一張並覆寫同一個檔案，因此檔案內容永遠是最新的一張。

set -euo pipefail

script_dir="${0:a:h}"
output_dir="$script_dir/output/screenshots"
wincap_source="$script_dir/wincap.swift"
wincap_exe="$script_dir/helper/bin/wincap.exe"

# ─────────────────────────────────────────────────────────────────────────────
# 平台 / Platform
# ─────────────────────────────────────────────────────────────────────────────
#
# 偵測一次、存成一個名字，之後每個分支都問這個名字。
#
# 先前這個檔案沒有偵測，它**假設**自己在 Windows 上：整支腳本建立在 gdigrab 與 cygpath 之上。
# 那個假設在 macOS 上以最糟的方式破掉——ffmpeg 印出 `Unknown input format: 'gdigrab'`，然後
# **以 0 結束**。實測：`zsh testapp/screenshot.zsh -d 1 -w "P28 hit testing" probe-macos` 印出
# 那三行錯誤、回報成功、沒有產生任何檔案，而 test_common.zsh 的六個呼叫點都帶著 `|| true`，
# 於是 `test.zsh P28 --macos` 跑完後 output/screenshots 是空的，終端機上卻寫著
# 「final screenshot follows」。
#
# 所以未知平台在這裡**硬性失敗**，而不是往下掉進 Windows 路徑。少了這一段，一台沒有 gdigrab
# 的機器得到的是「成功但沒有圖」，而那要靠人去看目錄才會發現。
#
# Detected once, given a name, and asked by name from then on.
#
# This file previously did no detection and **assumed** Windows: the whole script is built on
# gdigrab and cygpath. On macOS that assumption broke in the worst available way -- ffmpeg printed
# `Unknown input format: 'gdigrab'` and then **exited 0**. Measured: the command above printed
# three error lines, reported success, and produced no file; all six call sites in
# test_common.zsh pass `|| true`, so after `test.zsh P28 --macos` the screenshots directory was
# empty while the terminal said "final screenshot follows".
#
# So an unknown platform **fails hard** here rather than falling through into the Windows path.
# Without this, a machine without gdigrab gets "succeeded, no picture", which is found only by a
# person looking in a directory.
case "$(uname -s)" in
    Darwin)
        platform="macos"
        ;;
    MINGW*|MSYS*|CYGWIN*|Windows_NT)
        platform="windows"
        ;;
    Linux)
        # WSL 走的是 Windows 路徑：gdigrab 與 tasklist.exe 都是透過 interop 呼叫到 Windows 那側，
        # 拍的也是 Windows 的桌面。沒有 interop 的一般 Linux 兩者都沒有。
        # WSL takes the Windows path: gdigrab and tasklist.exe both reach the Windows side through
        # interop, and what is photographed is the Windows desktop. Plain Linux has neither.
        if grep -qi microsoft /proc/version 2>/dev/null; then
            platform="windows"
        else
            platform="linux"
        fi
        ;;
    *)
        platform="unknown"
        ;;
esac

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
        "  -w  Capture this window directly with wincap (priority 1)," \
        "      whatever is in front of it. If wincap cannot capture it," \
        "      this command fails instead of substituting the desktop." \
        "  -w  直接擷取此視窗（優先序 1），不受前方遮擋影響。若無法擷取該視窗，" \
        "      指令會失敗，不會用桌面截圖替代。" \
        "" \
        "macOS: -w matches a window title, and falls back to the name of the" \
        "       program that owns it, because macOS returns an empty title to" \
        "       any process without Screen Recording permission. Which one" \
        "       matched is printed. Capture needs that permission; without it" \
        "       nothing is written and the exit code is 1. A sleeping display defeats" \
        "       window capture entirely, so a fallback to the whole screen is a signal." \
        "macOS：-w 先比對視窗標題，比不到時改以擁有該視窗的程式名稱比對——未取得" \
        "       「螢幕錄製」權限的行程讀到的標題一律為空。實際以哪一種比中會被印出。" \
        "       擷取本身需要該權限；沒有時不會產生檔案，結束碼為 1。" \
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

# ─────────────────────────────────────────────────────────────────────────────
# macOS
# ─────────────────────────────────────────────────────────────────────────────
#
# 為什麼 macOS 自成一段，而不是與下方共用流程
#
# 兩邊唯一相同的只有輸出檔名。列出視窗、把視窗帶到前景、擷取本身、以及失敗時的表現，四件事
# 都不一樣，其中最後一件差最多：gdigrab 找不到視窗時結束碼是 **0**，而 screencapture 失敗時
# 結束碼是 **1 且不留下任何檔案**（兩者皆實測）。把它們折進同一組條件式，會讓下方關於 BitBlt、
# AppActivate 與 WSLg 的註解看起來像是也適用於此，而它們一條都不適用。
#
# Why macOS is a self-contained section rather than sharing the flow below.
#
# The only thing the two share is the name of the output file. Listing windows, raising one, the
# capture itself, and how failure presents all differ -- the last most of all: gdigrab exits **0**
# when it cannot find the window, while screencapture exits **1 and leaves no file** (both
# measured). Folding them into one branch would make the notes below about BitBlt, AppActivate
# and WSLg read as though they applied here, and not one of them does.
if [ "$platform" = "macos" ]; then
    timestamp="$(date +%Y%m%d-%H%M%S)"
    target="$output_dir/$label-$timestamp.png"

    # screencapture 自己會等，因此既不需要 sleep，也不需要 Windows 路徑那種丟棄影格的做法。
    # screencapture waits by itself, so neither a sleep nor the Windows path's discarded frames
    # are needed here.
    #
    # 用陣列而不是字串：zsh 不對 `$var` 做字語分割，`-T 5` 會以**一個**參數送進去，而
    # screencapture 對此的反應是把整串當成檔名。
    # An array rather than a string: zsh does not word-split `$var`, so `-T 5` would arrive as a
    # single argument, which screencapture treats as a file name.
    wait_args=()
    if [ "$delay" -gt 0 ]; then
        wait_args=(-T "$delay")
    fi

    # 視窗清單來自 CGWindowListCopyWindowInfo，經 osascript 的 ObjC 橋接呼叫——不必編譯任何
    # 東西、不必安裝額外工具、也不需要輔助使用權限。
    #
    # 但**視窗標題是否讀得到，取決於呼叫端行程的「螢幕錄製」權限**（macOS 10.15 起）。這一點
    # 在同一台機器上量到兩種相反的結果：在未取得權限的終端機裡，列出的 28 個視窗 kCGWindowName
    # 全部是空字串；在另一個已取得權限的終端機裡，26 個視窗有 22 個標題讀得到。kCGWindowOwnerName
    # 兩邊都有值。
    #
    # 因此 -w 先比標題、比不到再比擁有該視窗的程式名稱，而**用哪一種比中會被印出**——程式名稱
    # 只能指認「哪個 app」，不能指認「它的哪一個視窗」，兩者能證明的事情不同。
    #
    # The window list comes from CGWindowListCopyWindowInfo through osascript's ObjC bridge:
    # nothing to compile, nothing to install, and no accessibility permission needed.
    #
    # But **whether a window title is readable depends on the calling process's Screen Recording
    # permission** (macOS 10.15 onwards), and the two possible answers were both measured on this
    # machine: from a terminal without the permission, all 28 listed windows had an empty
    # kCGWindowName; from another terminal that had it, 22 of 26 titles were readable.
    # kCGWindowOwnerName was present in both.
    #
    # So -w matches the title first and the owning program's name second, and **which one matched
    # is printed** -- a program name identifies which app, not which of its windows, and the two
    # support different conclusions.
    mac_windows() {
        osascript -l JavaScript <<'JXA'
ObjC.import('CoreGraphics');
// castRefToObject 是必要的：CGWindowListCopyWindowInfo 回傳 CFArrayRef，JXA 不會自動橋接它，
// 直接 deepUnwrap 得到的是 undefined——而 undefined 傳到 shell 端，看起來與「一個視窗都沒開」
// 完全一樣。實測過：少了這個轉換，輸出是空的而結束碼是 0。
// The cast is required: the CFArrayRef is not bridged automatically and deepUnwrap returns
// undefined, which reaches the shell looking exactly like "no windows are open". Measured:
// without the cast the output is empty and the exit code is 0.
var list = ObjC.deepUnwrap(ObjC.castRefToObject($.CGWindowListCopyWindowInfo(1, 0)));
// 分隔字元寫成 fromCharCode 而不是字面值：US 是控制字元，貼在原始碼裡看不見，而看不見的
// 分隔字元被誰不小心刪掉時，沒有任何東西會報錯。
// The separator is written as fromCharCode rather than a literal: US is a control character,
// invisible in source, and nothing reports it when an invisible separator is deleted by accident.
var SEP = String.fromCharCode(31);
var out = [];
for (var i = 0; i < list.length; i++) {
    var w = list[i], b = w.kCGWindowBounds || {};
    // layer 0 才是一般視窗。選單列、Dock 與各種浮層在別的 layer，而它們一樣有名字、有大小，
    // 因此不濾掉的話會比中它們——那會得到一張拍到 Dock 的圖，而不是一次失敗。
    // Layer 0 is an ordinary window. The menu bar, the Dock and assorted overlays sit on other
    // layers and have names and sizes too, so without this filter they match -- yielding a
    // photograph of the Dock rather than a failure.
    if (w.kCGWindowLayer !== 0) continue;
    if (b.Width < 100 || b.Height < 100) continue;
    out.push([w.kCGWindowNumber, w.kCGWindowOwnerName || '', w.kCGWindowName || '',
              Math.round(b.X), Math.round(b.Y), Math.round(b.Width), Math.round(b.Height),
              w.kCGWindowOwnerPID].join(SEP));
}
out.join('\n');
JXA
    }

    # 欄位以 US（八進位 \037）分隔，不是 tab 也不是逗號：視窗標題是任意字串，裡面可以有 tab、
    # 逗號與引號，而這三個字元在任何一種「自己切欄位」的做法裡都會安靜地把欄位切錯位。
    # Fields separated by US (octal \037) rather than tab or comma: a window title is an arbitrary
    # string and may contain tabs, commas and quotes, each of which silently shifts fields in any
    # hand-rolled split.
    #
    # 標題的比對優先於程式名稱，而且是看完整份清單才決定——單趟即決無法「偏好標題」，因為
    # 標題可能出現在比較後面的一列。
    # Titles are preferred over program names across the whole list rather than decided in one
    # pass, because a title match may appear on a later row than a name match.
    mac_resolve() {
        mac_windows | awk -F'\037' -v want="$1" '
            NF >= 8 {
                if ($3 != "" && index($3, want) && by_title == "") { by_title = $0 }
                else if (index($2, want) && by_owner == "") { by_owner = $0 }
            }
            END {
                if (by_title != "") print by_title "\037title"
                else if (by_owner != "") print by_owner "\037owner"
            }
        '
    }

    mac_field() { printf '%s' "$1" | awk -F'\037' -v n="$2" '{ print $n }'; }

    # macOS 的 stat 沒有 -c。下方 Windows 路徑用的是 `stat -c%s ... || echo 0`，在這裡會走進
    # `|| echo 0`——於是每一張成功的截圖都會被判定為「太小」而觸發回退。
    # macOS's stat has no -c. The Windows path below uses `stat -c%s ... || echo 0`, which here
    # takes the `|| echo 0` branch, so every successful capture would be judged too small and
    # fall back.
    mac_size() { stat -f%z "$1" 2>/dev/null || echo 0; }

    # 螢幕錄製權限缺席時**兩級都會失敗**，因為兩級都要讀畫面。所以這段只印一次，而且講的是
    # 怎麼修，不是重複「擷取失敗」。
    # Without Screen Recording permission **both priorities fail**, since both read the screen.
    # So this is printed once and says what to do, rather than repeating "capture failed".
    mac_no_image_hint() {
        printf '!! screenshot.zsh: screencapture 沒有產生任何影像。\n' >&2
        printf '!! 在 macOS 上這通常是「螢幕錄製」權限：系統設定 > 隱私權與安全性 >\n' >&2
        printf '!! 螢幕與系統音訊錄製，勾選實際執行本腳本的那個程式（終端機、iTerm 或編輯器）。\n' >&2
        printf '!! 勾選後通常立刻生效，不需要重開終端機——screencapture 每次都是新的子行程，\n' >&2
        printf '!! 讀的是當下的權限狀態（實測：授權後未重啟即可擷取）。仍然失敗時才重開它。\n' >&2
        printf '!! 另外兩種會得到同一則訊息的情況：螢幕被鎖定，以及**顯示器休眠**——後者連整個\n' >&2
        printf '!! 螢幕都拍得到，只是拍回來一張全黑的圖，而視窗擷取則是直接失敗。\n' >&2
        printf '!! screencapture produced no image at all.\n' >&2
        printf '!! On macOS this is usually Screen Recording permission: System Settings >\n' >&2
        printf '!! Privacy & Security > Screen & System Audio Recording, tick the program that\n' >&2
        printf '!! actually runs this script (Terminal, iTerm, or the editor).\n' >&2
        printf '!! That usually takes effect at once and needs no restart -- screencapture is a\n' >&2
        printf '!! fresh subprocess each time and reads the current permission state (measured:\n' >&2
        printf '!! captures worked after the grant with nothing restarted). Restart it only if\n' >&2
        printf '!! this persists.\n' >&2
        printf '!! Two other conditions give the same message: a locked screen, and a **sleeping\n' >&2
        printf '!! display** -- the latter still photographs the whole screen, returning a black\n' >&2
        printf '!! frame, while window capture fails outright.\n' >&2
    }

    captured_from=""
    resolved=""
    if [ -n "$window" ]; then
        resolved="$(mac_resolve "$window" || true)"
        if [ -z "$resolved" ]; then
            printf '!! screenshot.zsh: 優先序 1 略過——沒有任何視窗的標題或程式名稱包含\n' >&2
            printf '!!「%s」。改用優先序 2（整個螢幕），該圖僅在此視窗位於最上層時才會包含它。\n' "$window" >&2
            printf '!! priority 1 skipped -- no window whose title or owning program name\n' >&2
            printf '!! contains "%s" is open. Using priority 2, the whole screen, which shows\n' "$window" >&2
            printf '!! that window only if it is in front.\n' >&2
        else
            window_id="$(mac_field "$resolved" 1)"
            window_owner="$(mac_field "$resolved" 2)"
            window_title="$(mac_field "$resolved" 3)"
            matched_by="$(mac_field "$resolved" 9)"
            if [ "$matched_by" = "owner" ]; then
                printf 'matched the owning program "%s", not a window title\n' "$window_owner" >&2
                printf '（比中的是程式名稱「%s」而非視窗標題；未取得螢幕錄製權限時標題為空）\n' "$window_owner" >&2
            else
                printf 'resolved window title to "%s"\n' "$window_title" >&2
            fi
            # -l 直接讀該視窗本身，被別的視窗蓋住也照樣拍得到——這與 Windows 的優先序 1 語意
            # 相同，而在 macOS 上它不需要先把視窗帶到前景。
            #
            # 但它不是完全不受畫面狀態影響：**顯示器休眠時，-l 對每一個視窗都失敗**，包含當下
            # 最前景的那一個。實測：整螢幕擷取仍以 0 結束並回來一張全黑的圖，而同一時刻對本行程
            # 與對終端機自己的視窗各試一次 -l，兩次都是 could not create image from window。
            # 因此「回退成整個螢幕」在呼叫端應視為訊號，而不只是次好結果。
            #
            # -l reads the window itself and captures it even when other windows cover it -- the
            # same meaning as the Windows priority 1, and here it needs no raise.
            #
            # It is not indifferent to the state of the display, though: **while the display
            # sleeps, -l fails for every window**, the frontmost included. Measured: a whole-screen
            # capture still exited 0 and returned a black frame while, at the same moment, -l on
            # this process's window and on the terminal's own both answered could not create image
            # from window. So a caller should read a fallback to the whole screen as a signal
            # rather than merely a lesser result.
            #
            # -o 去掉視窗陰影：陰影是一圈半透明邊框，留著會讓兩張圖的像素邊界對不齊。
            # -o drops the window shadow, a translucent border that otherwise misaligns the pixel
            # edges between two captures.
            screencapture -x -o -l "$window_id" "${wait_args[@]}" "$target" 2>/dev/null || true
            if [ -f "$target" ] && [ "$(mac_size "$target")" -gt 5000 ]; then
                captured_from="priority 1: window $window_id (\"${window_title:-$window_owner}\")"
            else
                rm -f "$target"
                printf '!! screenshot.zsh: 優先序 1 失敗——無法擷取視窗 %s。改用優先序 2\n' "$window_id" >&2
                printf '!!（整個螢幕），該圖僅在此視窗位於最上層時才會包含它。\n' >&2
                printf '!! priority 1 failed -- window %s could not be captured. Falling back to\n' "$window_id" >&2
                printf '!! priority 2, the whole screen, which shows it only if it is in front.\n' >&2
            fi
        fi
    fi

    if [ -z "$captured_from" ]; then
        if [ -n "$resolved" ]; then
            # 帶到前景只有優先序 2 需要：它拍的是螢幕，視窗不在最上層就等於拍到別的東西，而
            # 那張圖一樣是有效的 PNG、結束碼一樣是 0。這正是本檔開頭記載的那個「拍到鎖定畫面
            # 卻回報成功」的形狀。
            # Raising is needed only by priority 2: it photographs the screen, so a window that is
            # not on top means photographing something else -- still a valid PNG, still a zero
            # exit code. That is the shape this file's header records as a capture of the lock
            # screen reported as a success.
            #
            # System Events 需要「輔助使用」權限，它與「螢幕錄製」是兩個不同的權限，可能只給了
            # 其中一個。因此這裡不假設它會成功，失敗就說出來。
            # System Events needs Accessibility permission, a different permission from Screen
            # Recording that may be granted alone. So success is not assumed, and failure is said
            # out loud.
            window_pid="$(mac_field "$resolved" 8)"
            if ! osascript -e "tell application \"System Events\" to set frontmost of (first application process whose unix id is $window_pid) to true" >/dev/null 2>&1; then
                printf '!! screenshot.zsh: 亦無法將該視窗帶到前景（需要「輔助使用」權限）。\n' >&2
                printf '!! 以下截圖拍到的是當時螢幕上的其他內容。\n' >&2
                printf '!! could not bring the window to the front either (needs Accessibility\n' >&2
                printf '!! permission). The capture below is of whatever was on screen instead.\n' >&2
            fi
        fi
        screencapture -x "${wait_args[@]}" "$target" 2>/dev/null || true
        if [ -n "$window" ]; then
            captured_from="priority 2: screen (window capture failed)"
        else
            # 未指定 -w，因此整個螢幕正是所要求的目標而非回退。
            # No -w was given, so the whole screen is what was asked for rather than a fallback.
            captured_from="screen"
        fi
    fi

    # 沒有檔案就不要印出檔名。印一個不存在的路徑再以 0 結束，正是本檔通篇在防的那種「看起來
    # 成功」——而在 macOS 上它特別容易發生，因為權限被拒時 screencapture 什麼都不留下。
    # No file, no file name. Printing a path that does not exist and exiting 0 is exactly the
    # looks-like-success this file guards against throughout, and on macOS it is especially easy
    # to hit, because a denied permission leaves screencapture with nothing to leave behind.
    if [ ! -f "$target" ]; then
        mac_no_image_hint
        exit 1
    fi

    printf '%s\n' "$target"
    printf 'captured from %s\n' "$captured_from"
    exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# 既不是 macOS 也不是 Windows / Neither macOS nor Windows
# ─────────────────────────────────────────────────────────────────────────────
#
# 以下全部依賴 Windows capture 工具：指定 -w 時使用 wincap/PrintWindow，未指定 -w 時使用
# gdigrab 桌面擷取。一般 Linux 沒有這兩條路徑，因此直接停住並說明原因。
# Everything below depends on Windows capture tooling: wincap/PrintWindow for -w,
# and gdigrab desktop capture when -w is omitted. Plain Linux has neither path,
# so this stops here and says why.
if [ "$platform" != "windows" ]; then
    printf '!! screenshot.zsh: 本平台（uname -s = %s）沒有擷取路徑。\n' "$(uname -s)" >&2
    printf '!! 目前支援 macOS（screencapture）與 Windows／WSL（ffmpeg gdigrab）。\n' >&2
    printf '!! 沒有產生任何檔案。\n' >&2
    printf '!! no capture path on this platform (uname -s = %s).\n' "$(uname -s)" >&2
    printf '!! Supported: macOS via screencapture, Windows and WSL via wincap/gdigrab.\n' >&2
    printf '!! No file was produced.\n' >&2
    exit 3
fi

grab() {
    ffmpeg -hide_banner -loglevel error -f gdigrab -framerate 1 -i desktop "$@"
}

ensure_wincap() {
    if [ ! -f "$wincap_source" ]; then
        printf '!! screenshot.zsh: wincap source is missing: %s\n' "$wincap_source" >&2
        return 1
    fi

    if [ ! -x "$wincap_exe" ] || [ "$wincap_source" -nt "$wincap_exe" ]; then
        mkdir -p "$script_dir/helper/bin"
        printf 'building wincap helper: %s\n' "$wincap_exe" >&2
        if ! swiftc "$wincap_source" -o "$wincap_exe"; then
            printf '!! screenshot.zsh: failed to build wincap helper\n' >&2
            return 1
        fi
    fi
}

capture_with_wincap() {
    local title="$1"
    local bmp="${target:r}-wincap.bmp"
    local log="${target:r}-wincap.log"
    local rc=0

    ensure_wincap || return 1

    if "$wincap_exe" "$title" "$(windows_path "$bmp")" > "$log" 2>&1; then
        rc=0
    else
        rc=$?
    fi

    if [ -s "$log" ]; then
        sed 's/^/wincap: /' "$log" >&2
    fi

    if [ "$rc" -ne 0 ]; then
        [ -f "$bmp" ] && rm -- "$bmp"
        [ -f "$log" ] && rm -- "$log"
        return 1
    fi

    if [ ! -f "$bmp" ] || [ "$(stat -c%s "$bmp" 2>/dev/null || echo 0)" -le 54 ]; then
        printf '!! screenshot.zsh: wincap returned success but produced no usable BMP\n' >&2
        [ -f "$bmp" ] && rm -- "$bmp"
        [ -f "$log" ] && rm -- "$log"
        return 1
    fi

    if ! ffmpeg -hide_banner -loglevel error -y -i "$bmp" "$target" </dev/null; then
        printf '!! screenshot.zsh: failed to convert wincap BMP to PNG\n' >&2
        [ -f "$bmp" ] && rm -- "$bmp"
        [ -f "$log" ] && rm -- "$log"
        return 1
    fi

    [ -f "$bmp" ] && rm -- "$bmp"
    [ -f "$log" ] && rm -- "$log"
    [ -f "$target" ] && [ "$(stat -c%s "$target" 2>/dev/null || echo 0)" -gt 5000 ]
}

# In window mode the wait is a plain sleep, because Windows `-w` intentionally
# uses only wincap. In desktop mode, discarded gdigrab frames are the wait: one
# per second, decoded and thrown away.
# 視窗模式下等待就是 sleep，因為 Windows `-w` 刻意只使用 wincap。桌面模式下，丟棄的
# gdigrab 影格就是等待：每秒一張，解碼後直接丟掉。
if [ "$delay" -gt 0 ]; then
    if [ -n "$window" ]; then
        sleep "$delay"
    else
        grab -frames:v "$delay" -f null - </dev/null
    fi
fi

timestamp="$(date +%Y%m%d-%H%M%S)"
target="$output_dir/$label-$timestamp.png"

# With -w: the window itself through wincap/PrintWindow, with no desktop
# fallback. Without -w: the composited desktop.
#
# The old Windows priority-1 path used gdigrab with `title=...`, which meant
# exact-title matching, BitBlt, and occasional hangs from this script. wincap is
# now the only window path on Windows/WSLg: it matches by substring, asks DWM to
# render the window, and rejects an all-black bitmap before this script converts
# the BMP to PNG.
#
# 指定 -w：透過 wincap/PrintWindow 擷取視窗本身，不做 desktop fallback。未指定 -w：
# 擷取合成後的桌面。
#
# 舊的 Windows 優先序 1 使用 gdigrab 的 `title=...`，意味著 exact-title matching、BitBlt，
# 且從本腳本呼叫時偶爾會卡住。現在 Windows/WSLg 的唯一視窗路徑是 wincap：它以子字串比對、
# 要求 DWM 算繪視窗，並在本腳本將 BMP 轉成 PNG 前拒絕全黑 bitmap。
captured_from=""
if [ -n "$window" ]; then
    if capture_with_wincap "$window"; then
        captured_from="priority 1: wincap window \"$window\""
    else
        # Fail closed. A desktop capture is not evidence about the named window,
        # and silently substituting one caused false findings before.
        # 採 fail closed。桌面截圖不是指定視窗的證據，先前靜默替換成桌面截圖曾造成錯誤 finding。
        printf '!! screenshot.zsh: priority 1 failed -- no matching window could be captured by wincap.\n' >&2
        printf '!! No desktop fallback was used; retry with the correct window title or omit -w explicitly.\n' >&2
        printf '!! 優先序 1 失敗：wincap 無法擷取符合的視窗。未使用 desktop fallback；請修正視窗標題，或明確省略 -w。\n' >&2
        exit 1
    fi
fi

if [ -z "$captured_from" ]; then
    grab -frames:v 1 -y "$target" </dev/null
    captured_from="desktop"
fi

printf '%s\n' "$target"
printf 'captured from %s\n' "$captured_from"
