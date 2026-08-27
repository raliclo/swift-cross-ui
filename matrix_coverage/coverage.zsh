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
# The columns are Windows/gtk4, Windows/WinUI, WSL, macOS/AppKit, iOS/UIKit and
# Android. To add another, add one line to the `key`/`en`/`zh` arrays in the awk
# BEGIN block and raise `ncol`; the headers and the body are both built from
# that one list, so they cannot disagree.
#
# A run whose `platform/backend` pair matches no column is REPORTED on stderr
# rather than dropped in silence. That is not hypothetical: it caught two rows
# in this project's own history recorded as `windows/liststyle` and
# `windows/control` -- ad-hoc backend labels that were quietly missing from the
# table, where they read as "never tested".
#
# 目前的欄位為 Windows/gtk4、Windows/WinUI、WSL、macOS/AppKit、iOS/UIKit 與 Android。若要新增，
# 只需在 awk BEGIN 區塊的 `key`／`en`／`zh` 陣列各加一行並調高 `ncol`；標頭與內容都由這份清單產生，
# 因此兩者不可能不一致。
#
# 若某筆執行的 `platform/backend` 配對不符合任何欄位，會在 stderr 上「回報」而非靜默捨棄。這並非
# 假想情境：它抓到了本專案自身歷史中兩筆記為 `windows/liststyle` 與 `windows/control` 的資料——
# 那是臨時起意的 backend 標籤，原本會悄悄從表格中消失，讀起來就成了「從未測試過」。
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
    csv2 -r -i "$csv" --json 2>/dev/null | awk '
        # The columns, defined once and used for both the headers and the body.
        #
        # They used to be written out twice -- a printf for the two header rows
        # and a hand-rolled line per column in END -- which is two places to
        # edit and no way for them to disagree loudly. Adding macOS, iOS and
        # Android is what made that expensive enough to fix.
        #
        # A platform is a `platform/backend` pair from results.csv2, so a run
        # recorded with any other pair belongs in no column. Those used to
        # vanish; `dropped` below counts them and the script reports it, because
        # a run silently missing from a coverage matrix reads as "never tested"
        # and is exactly the wrong thing to be quiet about.
        #
        # 這些欄位只定義一次，同時供標頭與內容使用。
        #
        # 先前它們被寫了兩遍——兩列標頭各一個 printf，加上 END 之中每欄一行的手寫程式碼——那是兩處
        # 要維護、且無法在不一致時大聲失敗。加入 macOS、iOS 與 Android 使得這個代價高到值得修正。
        #
        # 一個平台是 results.csv2 中的 `platform/backend` 配對，因此以其他配對記錄的執行不屬於任何
        # 欄位。這些紀錄過去會直接消失；下方的 `dropped` 會計數，腳本並予以回報——因為一筆在覆蓋率
        # 矩陣中悄悄消失的執行，讀起來就是「從未測試過」，而那正是最不該保持安靜的事。
        BEGIN {
            ncol = 6
            key[1] = "windows/gtk4";     en[1] = "windows_gtk4";  zh[1] = "Windows·gtk4"
            key[2] = "windows/winui";    en[2] = "windows_winui"; zh[2] = "Windows·WinUI"
            key[3] = "wsl/gtk4";         en[3] = "wsl";           zh[3] = "WSL"
            key[4] = "mac/appkit";       en[4] = "macos_appkit";  zh[4] = "macOS·AppKit"
            key[5] = "ios/uikit";        en[5] = "ios_uikit";     zh[5] = "iOS·UIKit"
            key[6] = "android/android";  en[6] = "android";       zh[6] = "Android"

            line = "app"; for (c = 1; c <= ncol; c++) line = line "," en[c]
            print line ",note"
            line = "app"; for (c = 1; c <= ncol; c++) line = line "," zh[c]
            print line ",備註"

            for (c = 1; c <= ncol; c++) known[key[c]] = 1
        }
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

            pair = platform "/" backend
            # "n/a" counts as "no replay was expected", alongside "-". An app
            # with no action file launches and is captured and is a perfectly
            # good run; reporting the verdict as "n/a" made those look like
            # something had gone wrong. Both spellings are in the file because
            # the capture column already uses "n/a", so writing it in the replay
            # column is the natural thing to do.
            # 「n/a」與「-」同樣代表「本就不預期有重放」。沒有動作檔的 app，能啟動、能擷取，就是一次
            # 完全合格的執行；把結論報成「n/a」會讓它看起來像出了什麼問題。兩種寫法都存在於檔案中，
            # 因為 capture 欄本來就使用「n/a」，於是在 replay 欄照樣寫下它是很自然的事。
            noReplayExpected = (replay == "-" || replay == "n/a" || replay == "")
            verdict = (launch == "ok") ? (replay == "ok" || noReplayExpected ? "pass" : replay) : launch

            if (!(pair in known)) { dropped[pair]++; next }

            # Latest wins, and rows are appended in time order.
            # 以最新者為準；資料列是依時間順序追加的。
            cell[app, pair] = verdict " " date
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
                line = a
                for (c = 1; c <= ncol; c++)
                    line = line "," ((a SUBSEP key[c]) in cell ? cell[a, key[c]] : "-")
                print line ","
            }

            # To stderr, so it reaches the operator without landing in the
            # pivot. Named pairs rather than a bare count: "3 rows dropped" does
            # not tell you whether a platform is missing from the table above or
            # whether someone mistyped a backend.
            # 輸出至 stderr，如此可傳達給操作者而不會混入 pivot。此處列出具體配對而非僅給總數：
            # 「捨棄 3 列」無法告訴你究竟是上表少了一個平台，還是有人把 backend 名稱打錯了。
            for (p in dropped)
                printf "coverage.zsh: %d run(s) recorded as %s match no column\n", \
                    dropped[p], p > "/dev/stderr"
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
