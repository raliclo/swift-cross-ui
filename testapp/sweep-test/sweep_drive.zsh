#!/usr/bin/env zsh
# Launches every already-built P1-P26 app, replays its action file, captures it.
#
#   zsh testapp/sweep-test/sweep_drive.zsh                 every app
#   zsh testapp/sweep-test/sweep_drive.zsh -l gtk4         label the run
#   zsh testapp/sweep-test/sweep_drive.zsh P8 P19          just these
#   zsh testapp/sweep-test/sweep_drive.zsh --help
#
# The pair to sweep_build.zsh, and it does not build. See that script's header
# for why the two are separate; the short version is that this half needs an
# unlocked desktop and that half does not, and this half keeps the desktop
# unlocked by itself because synthesised input resets the idle timer.
#
# `-l` only names the run: it goes into the capture filenames and the table
# heading. It does **not** choose a backend. The backend is whatever
# `testapp/output/Pn.exe` happens to be, which is whatever was built last.
# Passing `-l gtk4` after a WinUI build produces a table that is wrong in a way
# nothing else will catch, so pass what you actually built.
#
# Reading the columns:
#
#   launch    the process is still alive when the capture is taken
#   replay    the app's own `-actionfile:` line, which needs a SCUI_DEBUG build
#   capture   `window` is a real window capture; `desktop` is the fallback
#
# `desktop` is expected for WinUI and a problem for GTK. WinUI draws through
# DirectComposition, `BitBlt` returns black, and testapp/screenshot.zsh falls
# back -- documented in its own header. GTK draws through OpenGL/WGL and
# captures properly, so a `desktop` there means the window was not found.
#
# 啟動每一個已建置好的 P1-P26 app，重放其動作檔，並擷取畫面。
#
# 與 sweep_build.zsh 成對，且本腳本不做建置。兩者為何分開，見該腳本的檔頭；簡言之，這一半需要
# 解鎖的桌面而那一半不需要，而且這一半會自行維持桌面不被鎖定——因為合成輸入會重置閒置計時器。
#
# `-l` 只是為本次執行命名：它會出現在截圖檔名與表格標題中。它**不會**選擇 backend。實際的 backend
# 取決於 `testapp/output/Pn.exe` 當下是哪一個，也就是最後一次建置的產物。在 WinUI 建置之後傳入
# `-l gtk4`，會產生一份錯誤的表格，而且沒有任何其他東西會抓到——請傳入你實際建置的那一個。
#
# 各欄位的讀法：
#
#   launch    擷取當下該行程仍然存活
#   replay    app 自己輸出的 `-actionfile:` 行，需要 SCUI_DEBUG 建置才會存在
#   capture   `window` 為真正的視窗擷取；`desktop` 為回退
#
# 對 WinUI 而言 `desktop` 是預期的，對 GTK 而言則是問題。WinUI 透過 DirectComposition 繪製，
# `BitBlt` 會回傳全黑，因此 testapp/screenshot.zsh 會回退——這在其自身檔頭已有記載。GTK 透過
# OpenGL/WGL 繪製，擷取完全正常，因此在 GTK 上出現 `desktop`，代表視窗根本沒被找到。

set -uo pipefail

script_path="${0:A}"
repo="${${script_path:h}:h:h}"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    sed -n '2,38p' "$script_path" | sed 's/^# \{0,1\}//'
    exit 0
fi

label=run
if [ "${1:-}" = "-l" ]; then
    if [ "$#" -lt 2 ]; then
        printf 'sweep_drive.zsh: -l needs a label\n' >&2
        exit 64
    fi
    label="$2"
    shift 2
fi

out="$repo/testapp/output"
actions="$repo/testapp/actions/win"
log_dir="/tmp/sweep_drive-$label"
mkdir -p "$log_dir"

# Where each run's rows are appended. The file is the history; coverage.zsh
# renders the current matrix out of it. Rows accumulate -- nothing is ever
# rewritten -- so an old result stays visible with its own date rather than
# being replaced by a newer one that might have tested something different.
#
# `windows` is hard-coded because this script is the Windows driver: it uses
# tasklist, taskkill and gdigrab. A WSL driver would append `wsl` rows to the
# same file.
#
# 每次執行的資料列都追加至此。該檔案即是歷史；coverage.zsh 由它算繪出當前的矩陣。資料列只增不改
# ——從不覆寫——因此舊的結果會連同它自己的日期一併留著，而不會被一個「可能測的是別的東西」的新結果
# 取代。
#
# `windows` 寫死，因為本腳本就是 Windows 的驅動器：它使用 tasklist、taskkill 與 gdigrab。WSL 的
# 驅動器會把 `wsl` 的資料列追加到同一個檔案。
results="$repo/matrix_coverage/results.csv2"
platform=windows
run_date="$(date +%F)"

if [ ! -f "$results" ]; then
    printf 'sweep_drive.zsh: %s is missing; it is the history file and ships with the repo\n' \
        "$results" >&2
    exit 1
fi

export PATH="/c/gtk4/bin:$PATH"

if [ "$#" -gt 0 ]; then
    apps=("$@")
else
    apps=(P1 P2 P3 P4 P5 P7 P8 P9 P10 P11 P12 P13 P14 P15 P16 P17 P18 P19 P20 P21 P22 P23 P24 P25 P26)
fi

printf '=== drive: %s ===\n' "$label"
printf '%-6s %-8s %-9s %-9s %s\n' app launch replay capture note
printf '%s\n' '--------------------------------------------------------------'

for app in $apps; do
    launch=- replay=- capture=- note=

    if [ ! -x "$out/$app.exe" ]; then
        printf '%-6s %-8s %-9s %-9s %s\n' "$app" 'no exe' - - 'never built'
        continue
    fi

    # A leftover process makes the next launch exit 0 with no window, which
    # reads as the app failing rather than the sweep failing.
    # 殘留行程會讓下一次啟動以 0 結束卻沒有視窗，那看起來像是 app 失敗，而非本掃描失敗。
    MSYS2_ARG_CONV_EXCL='*' taskkill /F /IM "$app.exe" >/dev/null 2>&1
    sleep 1

    action_file="$(ls "$actions/$app"-*.csv 2>/dev/null | grep -v -- '-winui' | head -1)"

    if [ -n "$action_file" ]; then
        ( cd "$out" && ./"$app.exe" -actionfile "$(cygpath -m "$action_file")" \
            > "$log_dir/$app.log" 2>&1 & )
    else
        ( cd "$out" && ./"$app.exe" > "$log_dir/$app.log" 2>&1 & )
    fi

    # Derived from the file rather than fixed, because a fixed wait silently
    # truncates the long ones. Measured 2026-08-27: 14 seconds was hard-coded,
    # P20-open-level-1.csv holds 16.8 s of sleeps, the replay starts 1 s after
    # launch -- so P20 needed 17.8 s and was captured and killed at 14. Its log
    # had `replaying` and no `replayed`, and the sweep reported it as though the
    # app were at fault. Every other file is at or under 10.4 s, so P20 was the
    # only one affected, which is exactly why it looked like an app defect.
    #
    # 由檔案本身推導而非固定，因為固定的等待會靜默截斷較長的動作檔。2026-08-27 實測：當時寫死
    # 14 秒，而 P20-open-level-1.csv 的睡眠總長為 16.8 秒，重放又在啟動後 1 秒才開始——因此 P20
    # 需要 17.8 秒，卻在第 14 秒就被擷取並終止。它的 log 有 `replaying`、沒有 `replayed`，而掃描
    # 把它報成了 app 的問題。其餘每個檔案都在 10.4 秒以內，所以只有 P20 受影響——這正是它看起來
    # 像 app 缺陷的原因。
    wait_seconds=14
    if [ -n "$action_file" ]; then
        wait_seconds="$(
            awk -F, '!/^#/ && !/^action,/ {s += $7}
                     END {
                         # the file, plus the replay delay, plus room for the
                         # actions themselves
                         # 檔案本身、加上重放延遲、再加上動作自身所需的餘裕
                         want = (s / 1000000) + 5
                         printf "%d", (want > 14 ? want : 14)
                     }' "$action_file"
        )"
    fi
    sleep "$wait_seconds"

    # No MSYS2_ARG_CONV_EXCL, and a doubled slash. The taskkill above wants the
    # opposite -- the exclusion and a single slash -- and mixing them up fails
    # silently in the worst way: with the exclusion set, `//FI` reaches tasklist
    # literally, it answers "ERROR: Invalid argument/option" on stderr, and
    # every app reads as having failed to launch. Measured 2026-08-27, on this
    # script's first run: P1 and P2 reported "exited before the capture" with
    # their windows plainly on screen.
    #
    # 此處不設 MSYS2_ARG_CONV_EXCL，並使用雙斜線。上方的 taskkill 要的正好相反——要設排除、用單
    # 斜線——而把兩者搞混的失敗方式最糟：設了排除時，`//FI` 會原封不動送達 tasklist，它會在
    # stderr 回覆「ERROR: Invalid argument/option」，於是每個 app 都被判讀為啟動失敗。於
    # 2026-08-27 本腳本首次執行時實測：P1 與 P2 的視窗明明在螢幕上，卻回報「exited before the
    # capture」。
    if tasklist.exe //FI "IMAGENAME eq $app.exe" 2>&1 | grep -q "$app.exe"; then
        launch=ok
    else
        launch=FAIL
        note='exited before the capture'
    fi

    case "$(zsh "$repo/testapp/screenshot.zsh" -w "$app" "$label-$app" 2>&1 | tail -1)" in
        *'priority 1'*) capture=window ;;
        *'priority 2'*|*desktop*) capture=desktop ;;
        *) capture='?' ;;
    esac

    if [ -n "$action_file" ]; then
        if grep -q 'status 5' "$log_dir/$app.log" 2>/dev/null; then
            replay=LOCKED
            note="${note:+$note; }workstation locked -- input result is void"
        elif grep -q 'actionfile: replayed' "$log_dir/$app.log" 2>/dev/null; then
            replay=ok
        elif grep -q 'actionfile: failed' "$log_dir/$app.log" 2>/dev/null; then
            replay=FAIL
            note="${note:+$note; }$(grep -m1 -oE 'failed: .*' "$log_dir/$app.log" | cut -c1-40)"
        elif grep -q 'actionfile: replaying' "$log_dir/$app.log" 2>/dev/null; then
            # Started and never finished. Distinguished from "no output at all"
            # because they have different causes and the old script reported
            # both as "built without SCUI_DEBUG?", which was wrong twice in one
            # afternoon -- once for a WinUI build whose output cannot reach a
            # file at all, and once for a wait that was too short.
            #
            # 開始了但沒跑完。與「完全沒有輸出」分開，因為兩者成因不同；舊版腳本把兩者都報成
            # 「built without SCUI_DEBUG?」，而那在一個下午之內就錯了兩次——一次是 WinUI 建置的
            # 輸出根本到不了檔案，一次是等待時間不足。
            replay='running'
            note="${note:+$note; }still replaying when captured"
        else
            replay='no line'
            note="${note:+$note; }no output at all -- WinUI build, or no SCUI_DEBUG"
        fi
    fi

    MSYS2_ARG_CONV_EXCL='*' taskkill /F /IM "$app.exe" >/dev/null 2>&1

    printf '%-6s %-8s %-9s %-9s %s\n' "$app" "$launch" "$replay" "$capture" "$note"

    # Appended so the matrix has evidence with a date on it. A hand-maintained
    # Pn-versus-platform table drifts from reality silently, which is the exact
    # failure this project spent a day chasing elsewhere; a table generated from
    # rows that each carry the day they were measured cannot.
    #
    # Quoted with `""` doubling, per RFC 4180, because `note` regularly contains
    # commas -- and splitting a CSV on `,` is what `csv2` exists in this project
    # to stop people doing.
    #
    # 追加寫出，好讓矩陣擁有「帶日期的證據」。手動維護的 Pn × 平台表格會靜默地與現實脫節——這正是
    # 本專案在別處花了一整天追查的同一種失敗；而由「每一列都記著自己是哪一天量到的」所生成的表格
    # 不會。
    #
    # 依 RFC 4180 以 `""` 進行跳脫，因為 `note` 經常含有逗號——而「用 `,` 切 CSV」正是 `csv2` 在本
    # 專案中存在的目的所要阻止的事。
    printf '%s,%s,%s,%s,%s,%s,%s,"%s"\n' \
        "$run_date" "$platform" "$label" "$app" \
        "$launch" "$replay" "$capture" "${note//\"/\"\"}" \
        >> "$results"
done

printf '\nlogs in %s ; captures in testapp/output/screenshots/%s-*.png\n' "$log_dir" "$label"
printf 'results appended to %s -- run coverage.zsh to regenerate the matrix\n' "$results"
exit 0
