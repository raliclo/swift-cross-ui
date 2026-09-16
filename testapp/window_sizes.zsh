#!/usr/bin/env zsh
# Captures every built test app on Windows and reports the window size of each.
#
#   zsh testapp/window_sizes.zsh                 every P*-WinUI.exe
#   zsh testapp/window_sizes.zsh -gtk4           every P*-gtk4.exe instead
#   zsh testapp/window_sizes.zsh P23 P50 P57     only these
#   zsh testapp/window_sizes.zsh --csv out.csv2  also write a csv2 table
#
# WHY IT EXISTS: a window size is not a detail here. Every action file's
# coordinates are measured off a capture of one app's window, so two apps that
# open at different sizes cannot share a coordinate, and an app whose size
# CHANGES between builds silently invalidates the file that was measured
# against it. This session re-measured P57's coordinates three times for
# exactly that reason. A list of sizes says which apps agree and which do not.
#
# The size comes from wincap's own `size: WxH` line, not from anything this
# script computes: it is the frame the capture actually covered, which is the
# rectangle the coordinates in an action file are relative to.
#
# EVERY P*.exe IS KILLED BEFORE EACH LAUNCH, and that is not tidiness. GTK apps
# share an application ID, so a second instance exits 0 without drawing
# anything -- a launch that never happened looks exactly like one that did.
#
# 為 Windows 上每一支已建置的測試 app 各截一張圖,並回報各自的視窗尺寸。
#
#   zsh testapp/window_sizes.zsh                 每一支 P*-WinUI.exe
#   zsh testapp/window_sizes.zsh -gtk4           改為每一支 P*-gtk4.exe
#   zsh testapp/window_sizes.zsh P23 P50 P57     只跑這幾支
#   zsh testapp/window_sizes.zsh --csv out.csv2  另外寫出一份 csv2 表格
#
# 為何需要它:視窗尺寸在此處不是細節。**每一個動作檔的座標,都是量自某一支 app 視窗的擷圖**,
# 因此兩支開啟尺寸不同的 app 不可能共用座標;而一支「尺寸在不同建置之間改變」的 app,
# 會**靜默地**讓當初對著它量的那個檔案失效。本次 session 就為了這個理由把 P57 的座標重量了三次。
# 一份尺寸清單,說得出哪些 app 彼此一致、哪些不一致。
#
# 尺寸取自 wincap 自己的 `size: WxH` 那一行,而非本腳本計算:那是擷圖**實際涵蓋的視窗框**,
# 也正是動作檔中座標所相對的那個矩形。
#
# **每次啟動之前都會殺掉所有 P*.exe**,而那不是為了整潔。GTK app 共用同一個 application ID,
# 因此第二個實例會以 0 結束、而且什麼都不畫——**一次從未發生的啟動,看起來與發生過的一模一樣**。
set -euo pipefail

script_path="${0:A}"
script_dir="${script_path:h}"
repo_dir="${script_dir:h}"
output_dir="$repo_dir/testapp/output"
shots_dir="$output_dir/screenshots"

usage() {
    sed -n '2,33p' "$script_path" | sed 's/^# \{0,1\}//'
}

# --help answers before anything is built, launched or captured. A wrong flag
# should cost a page of text, not a seven-minute sweep.
# --help 在任何建置、啟動或擷取之前就回答。一個打錯的旗標應該只花掉一頁文字,而不是一次七分鐘的掃描。
backend_suffix="-WinUI"
csv_path=""
wanted=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        -gtk4) backend_suffix="-gtk4"; shift ;;
        -winui|--winui) backend_suffix="-WinUI"; shift ;;
        --csv)
            if [ "$#" -lt 2 ]; then usage >&2; exit 64; fi
            csv_path="$2"; shift 2 ;;
        --csv=*) csv_path="${1#*=}"; shift ;;
        P[0-9]*) wanted+=("$1"); shift ;;
        *) printf 'unknown argument: %s\n' "$1" >&2; usage >&2; exit 64 ;;
    esac
done

case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*) ;;
    *)
        printf 'window_sizes.zsh measures Windows windows; this host is %s.\n' "$(uname -s)" >&2
        exit 64
        ;;
esac

apps=()
if [ "${#wanted[@]}" -gt 0 ]; then
    for name in "${wanted[@]}"; do
        if [ -f "$output_dir/$name$backend_suffix.exe" ]; then
            apps+=("$name")
        else
            printf 'skipped %s: no %s%s.exe\n' "$name" "$name" "$backend_suffix" >&2
        fi
    done
else
    # `exe_path`, NOT `path`. In zsh `path` is tied to `PATH` as an array, so a
    # loop variable named `path` REPLACES the search path with whatever it last
    # held -- here an .exe file -- and nothing reports it.
    #
    # This script did exactly that, and the way it failed is the reason the
    # rename carries a comment. The three-app form passes explicit names and
    # never enters this loop, so a trial run worked; the full sweep entered it
    # and then died twelve lines later on `command not found: date`, which
    # reads as a missing coreutils rather than as a wiped PATH. The symptom
    # surfaces far from the assignment, in a command that has nothing to do
    # with it.
    #
    # 用 `exe_path`,**不要用 `path`**。在 zsh 中,`path` 與 `PATH` 綁成同一個陣列,因此一個名為
    # `path` 的迴圈變數會**把搜尋路徑換成它最後持有的值**——此處是一個 .exe 檔——而且不會有任何回報。
    #
    # 本腳本正是這樣壞掉的,而那個壞法就是這段註解存在的理由:指定三支 app 的用法會傳入明確名稱、
    # 根本不會進入這個迴圈,所以試跑成功了;整輪掃描進入了它,然後在十二行之後死於
    # `command not found: date`——那看起來像是少了 coreutils,而不像 PATH 被清空。
    # **症狀出現在離指派很遠的地方,而且出現在一個與它毫無關係的指令上。**
    for exe_path in "$output_dir"/P*"$backend_suffix".exe; do
        [ -f "$exe_path" ] || continue
        name="${exe_path:t}"
        apps+=("${name%$backend_suffix.exe}")
    done
fi

if [ "${#apps[@]}" -eq 0 ]; then
    printf 'no %s executables found in %s\n' "$backend_suffix" "$output_dir" >&2
    exit 1
fi

printf '%s apps, backend %s\n' "${#apps[@]}" "$backend_suffix"
printf '%-8s %-12s %s\n' 'app' 'size' 'note'

# GTK needs its runtime on PATH or the process dies before drawing, with an
# error about a UCRT DLL that points at Visual C++ rather than at GTK.
# GTK 需要它的 runtime 在 PATH 上,否則行程會在繪製之前就結束,而其錯誤訊息談的是某個 UCRT DLL
# ——那會把人指向 Visual C++,而不是指向 GTK。
if [ "$backend_suffix" = "-gtk4" ]; then
    gtk_bin="/c/gtk4/bin"
    [ -d "$gtk_bin" ] && export PATH="$gtk_bin:$PATH"
fi

# One directory per sweep, named by the clock, so a failed run's logs are still
# there afterwards and two runs cannot overwrite each other.
# 每次掃描一個目錄,以時間命名,好讓失敗那一輪的 log 事後仍在,且兩次執行不會互相覆蓋。
run_dir="$output_dir/window-sizes/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$run_dir"

rows=()
for app in "${apps[@]}"; do
    MSYS2_ARG_CONV_EXCL='*' taskkill.exe -f -im "P*.exe" >/dev/null 2>&1 || true
    # A named directory rather than `mktemp -d`. The first run of this script
    # used mktemp, worked for a three-app trial, and then failed on the full
    # sweep with `command not found: mktemp` -- the packaged zsh here does not
    # always have it on PATH, and a dependency that is present for a short run
    # and absent for a long one is worse than no dependency at all.
    # 使用具名目錄,而非 `mktemp -d`。本腳本第一次執行時用的是 mktemp:三支 app 的試跑成功了,
    # 接著整輪掃描卻以 `command not found: mktemp` 失敗——此處打包的 zsh 並不總是把它放在 PATH 上,
    # 而**一個「短程執行時在、長程執行時不在」的依賴,比完全沒有依賴更糟**。
    events_dir="$run_dir/$app"
    mkdir -p "$events_dir"
    SCUI_DEBUG_EVENTS_DIR="$events_dir" \
        "$output_dir/$app$backend_suffix.exe" --debug >"$events_dir/stdout.log" 2>&1 &
    app_pid=$!
    sleep 5

    label="winsize-$app"
    if zsh "$script_dir/screenshot.zsh" -w "$app" "$label" >"$events_dir/shot.log" 2>&1; then
        capture_log="$(ls -t "$shots_dir/$label"-*-wincap.log 2>/dev/null | head -1)"
        size="$(grep -oE '^size: [0-9]+x[0-9]+' "$capture_log" 2>/dev/null | head -1 | sed 's/^size: //')"
        note=""
    else
        size=""
        note="capture failed (see $events_dir/shot.log)"
    fi
    [ -n "$size" ] || { size="-"; [ -n "$note" ] || note="no size line in the wincap log"; }

    kill "$app_pid" 2>/dev/null || true
    MSYS2_ARG_CONV_EXCL='*' taskkill.exe -f -im "$app$backend_suffix.exe" >/dev/null 2>&1 || true

    printf '%-8s %-12s %s\n' "$app" "$size" "$note"
    rows+=("$app,$size,$note")
done

# The summary is the point of the sweep: which sizes are shared, and by whom.
# A list of forty numbers is not an answer to "is the window size the same".
# 摘要才是這次掃描的重點:哪些尺寸是共用的、由誰共用。四十個數字的清單,並不是
# 「視窗尺寸是否相同」的答案。
printf '\n=== sizes, most common first ===\n'
printf '%s\n' "${rows[@]}" | awk -F, '$2 != "-" { count[$2]++; apps[$2] = apps[$2] " " $1 }
    END { for (s in count) printf "%-12s %2d  %s\n", s, count[s], apps[s] }' | sort -k2 -rn

if [ -n "$csv_path" ]; then
    {
        printf 'app,size,note\n'
        printf 'app,尺寸,備註\n'
        printf '%s\n' "${rows[@]}"
    } >"$csv_path"
    printf '\nwrote %s\n' "$csv_path"
fi
