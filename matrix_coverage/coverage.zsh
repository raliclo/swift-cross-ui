#!/usr/bin/env zsh
# Renders the Pn-versus-platform matrix from the run history in results.csv2.
#
#   zsh matrix_coverage/coverage.zsh          write coverage.md
#   zsh matrix_coverage/coverage.zsh --help
#
# `results.csv2` is the history: one row per app per run, appended by
# `testapp/sweep-test/sweep_drive.zsh`, never rewritten. This script pivots it
# into a matrix -- apps down, platform/backend across -- showing the LATEST
# result for each pair together with the date it was measured.
#
# The date is not decoration. A cell means "this is what happened on that day
# with the code as it was", and this project has spent real time on claims that
# were true when written and silently stopped being true. A pair with no row at
# all shows as `-`, which means untested, not passing.
#
# WHY A HISTORY FILE RATHER THAN A HAND-EDITED TABLE. A table someone updates by
# hand drifts from reality without anything failing. A table generated from rows
# that each carry their own date cannot: the worst it can do is go stale
# visibly, which is the failure mode to want.
#
# TO RECORD A RUN: run the sweep. It appends. Do not edit results.csv2 to make
# the matrix look better -- add a run.
#
# 由 results.csv2 中的執行歷史，算繪出 Pn × 平台的矩陣。
#
# `results.csv2` 是歷史：每次執行、每個 app 一列，由 `testapp/sweep-test/sweep_drive.zsh` 追加，
# 從不覆寫。本腳本將其樞紐為矩陣——app 為列、平台/backend 為欄——顯示每一組的「最新」結果，以及
# 該結果是哪一天量到的。
#
# 日期不是裝飾。每一格的意義是「在那一天、以當時的程式碼，發生了什麼」；本專案已在「寫下時為真、
# 之後安靜地不再為真」的斷言上花掉不少時間。完全沒有資料列的組合顯示為 `-`，代表「未測試」，
# 而非「通過」。
#
# 為何用歷史檔而非手動維護的表格：手動更新的表格會在沒有任何東西失敗的情況下與現實脫節；而由
# 「每列自帶日期」所生成的表格做不到這件事——它最糟只能「明顯地過期」，而那正是我們要的失敗方式。
#
# 要記錄一次執行：去跑掃描，它會自行追加。不要為了讓矩陣好看而編輯 results.csv2——請新增一次執行。

set -uo pipefail

script_path="${0:A}"
here="${script_path:h}"
csv="$here/results.csv2"
md="$here/coverage.md"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    sed -n '2,40p' "$script_path" | sed 's/^# \{0,1\}//'
    exit 0
fi

if ! command -v csv2 >/dev/null 2>&1; then
    printf 'coverage.zsh: csv2 is not on PATH\n' >&2
    exit 1
fi

# No `|| printf 0` fallback here. `grep -c` already prints 0 when it matches
# nothing -- and it *also* exits 1, so the fallback fired as well and the count
# came out as the two characters "0\n0". That then failed `-eq 0`, the
# empty-state branch never ran, and the file was written with an empty table
# under a broken heading. Measured on this script's first run.
#
# 此處不加 `|| printf 0` 這道退路。`grep -c` 在毫無匹配時本來就會印出 0——而它**同時**以 1 結束，
# 於是那道退路也跟著執行，計數變成 "0\n0" 這兩個字元。接著 `-eq 0` 比較失敗、空狀態分支從未執行，
# 檔案便在一個壞掉的標題底下寫出了一張空表。此為本腳本首次執行時實測。
rows="$(csv2 -r -i "$csv" 2>/dev/null | grep -c .)"

# A .csv2 path, not a bare mktemp name: csv2 takes the header count from the
# extension, and refuses a file it cannot classify.
# 使用 .csv2 的路徑，而非 mktemp 的無副檔名檔案：csv2 由副檔名決定標頭列數，無法分類的檔案會被拒絕。
pivot="${TMPDIR:-/tmp}/coverage-pivot-$$.csv2"
trap 'rm -f "$pivot"' EXIT

# Read through `csv2 --json` and match named fields, rather than splitting
# anything on commas.
#
# `csv2 -r` emits CSV, quoting and all -- checked, not assumed, because the
# first version of this script assumed tab-separated output and would have
# mis-parsed every row. The `--json` form gives `"name":"value"` pairs, so a
# comma inside `note` cannot shift a field, which is the whole reason this
# project has csv2 in the first place.
#
# 透過 `csv2 --json` 讀取並比對具名欄位，而不是對任何東西以逗號切割。
#
# `csv2 -r` 輸出的是 CSV，連引號一併保留——這是實測而非假設，因為本腳本的第一版假設它是 tab 分隔，
# 那會把每一列都解析錯。`--json` 形式給出的是 `"name":"value"` 配對，因此 `note` 中的逗號無法把
# 欄位推移——而這正是本專案一開始就採用 csv2 的全部理由。
{
    printf 'app,windows_gtk4,windows_winui,wsl,note\n'
    printf 'app,Windows·gtk4,Windows·WinUI,WSL,備註\n'

    csv2 -r -i "$csv" --json 2>/dev/null | awk '
        function field(name,   pattern, start, rest, end) {
            pattern = "\"" name "\":\""
            start = index($0, pattern)
            if (start == 0) return ""
            rest = substr($0, start + length(pattern))
            end = index(rest, "\"")
            return end ? substr(rest, 1, end - 1) : ""
        }
        # Only records; the first line is the meta object and has no "record".
        # 只取紀錄列；第一行是 meta 物件，不含 "record"。
        /"record"/ {
            date = field("date"); platform = field("platform")
            backend = field("backend"); app = field("app")
            launch = field("launch"); replay = field("replay")

            key = platform "/" backend
            verdict = (launch == "ok") ? (replay == "ok" || replay == "-" ? "pass" : replay) : launch

            # Latest wins, and rows are appended in time order.
            # 以最新者為準；資料列是依時間順序追加的。
            cell[app, key] = verdict " " date
            seen[app] = 1
        }
        END {
            n = 0
            for (a in seen) { order[n++] = a }
            # Numeric order by the digits after P, so P9 comes before P10.
            # 依 P 之後的數字排序，讓 P9 排在 P10 之前。
            for (i = 0; i < n; i++)
                for (j = i + 1; j < n; j++) {
                    ai = order[i]; aj = order[j]
                    sub(/^P/, "", ai); sub(/^P/, "", aj)
                    if (ai + 0 > aj + 0) { t = order[i]; order[i] = order[j]; order[j] = t }
                }
            for (i = 0; i < n; i++) {
                a = order[i]
                g = (a SUBSEP "windows/gtk4")  in cell ? cell[a, "windows/gtk4"]  : "-"
                w = (a SUBSEP "windows/winui") in cell ? cell[a, "windows/winui"] : "-"
                l = (a SUBSEP "wsl/gtk4")      in cell ? cell[a, "wsl/gtk4"]      : "-"
                printf "%s,%s,%s,%s,\n", a, g, w, l
            }
        }
    '
} > "$pivot"

{
    printf '# coverage\n\n'
    printf 'Which test apps have been run on which platform, and when.\n\n'
    printf '`-` means no run has ever been recorded for that pair. It does **not**\n'
    printf 'mean passing.\n\n'
    printf 'Generated from `results.csv2` — do not edit this file:\n\n'
    printf '```sh\nzsh matrix_coverage/coverage.zsh\n```\n\n'
    printf '哪些測試 app 曾在哪個平台上跑過，以及是什麼時候。\n\n'
    printf '`-` 代表該組合從未有任何一次執行被記錄下來，**不**代表通過。\n\n'
    printf '由 `results.csv2` 產生——請勿編輯本檔。\n\n'
    printf '**Runs recorded / 已記錄的執行筆數: %s**\n\n' "$rows"

    if [ "$rows" -eq 0 ]; then
        printf '_No runs recorded yet. Run a sweep and this table fills itself._\n\n'
        printf '_尚無任何執行紀錄。跑一次掃描，本表格便會自行填滿。_\n'
    else
        csv2 -r -i "$pivot" -t -md --pretty
    fi
} > "$md"

printf 'wrote %s (%s runs recorded)\n' "$md" "$rows"
exit 0
