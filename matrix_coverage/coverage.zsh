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
# THE DATE IS NOT THE ONLY CONDITION THAT MATTERS. Since 2026-09-07 every row
# also carries the `renderer` it ran under, and that value is part of the cell
# key, so two runs of one app on one day under different renderers combine
# rather than one silently replacing the other. It was added because a renderer
# decided a verdict: P11 captured 0.0% non-black under `-render hw` and 92.1%
# under `-render sw`, minutes apart. Rows predating the column read
# `unrecorded`, which means nobody wrote it down -- not the same as `default`,
# which means a run that chose nothing and took the platform default.
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
# 日期不是唯一重要的條件。自 2026-09-07 起，每一列同時帶著它所執行的 `renderer`，而該值是格子鍵的
# 一部分，因此同一支 app 在同一天、不同 renderer 下的兩次執行會「合併」，而不是其中一次靜默取代
# 另一次。加入它的原因是 renderer 會決定判決：P11 在 `-render hw` 下擷取到的非黑比例為 0.0%，
# 在 `-render sw` 下為 92.1%，兩者相隔數分鐘。早於本欄位的資料列讀作 `unrecorded`，意思是沒有人
# 寫下來過——這與 `default` 不同，後者意為「該次執行未做選擇，採用平台預設」。
#
# 要記錄一次執行：去跑掃描，它會自行追加。不要為了讓矩陣好看而編輯 results.csv2——請新增一次執行。

set -uo pipefail

script_path="${0:A}"
here="${script_path:h}"
csv="$here/results.csv2"
md="$here/coverage.md"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    # Line 2 through line 51: the whole English half. Widen it in the same edit
    # that grows the header, or the synopsis is truncated the moment anything is
    # added above the cut.
    #
    # It was `2,40p` and the English half already ran to line 42, so `TO RECORD A
    # RUN: run the sweep. It appends.` -- the one instruction a reader of this
    # `--help` is most likely to have come for -- was being cut off. That is the
    # drift this comment now exists to make visible; the same range in
    # sweep_drive.zsh had drifted the same way.
    #
    # 第 2 行至第 51 行：整個英文半邊。請在使檔頭變長的同一次編輯中一併加寬，否則只要在切點之上
    # 新增任何內容，說明就會被截斷。
    #
    # 它原本是 `2,40p`，而英文半邊當時已經寫到第 42 行，於是 `TO RECORD A RUN: run the sweep.
    # It appends.`——讀者查看這份 `--help` 最可能是為了它而來的那一句指示——一直被切掉。這正是本註解
    # 現在存在的用意：讓這種漂移看得見；sweep_drive.zsh 中的同一種範圍也以同樣方式漂移過。
    sed -n '2,51p' "$script_path" | sed 's/^# \{0,1\}//'
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

            # LATEST DATE WINS, AND WITHIN THAT DATE THE ROWS COMBINE.
            #
            # This was `cell[app, pair] = verdict " " date`, i.e. the last row
            # read simply replaced whatever was there. That was right while
            # sweep_drive.zsh emitted one row per app; it started losing results
            # the moment that script began driving EVERY action file, because a
            # second file for the same app on the same day silently overwrote
            # the first. P46 has three, and P24, P20, P19, P13 and P10 have two
            # each -- 5 of the 38 files -- so a pass could hide a failure that
            # ran an hour earlier and nothing would say so.
            #
            # A NEWER DATE still discards the older one, deliberately: a cell
            # means "this is what happened on that day", and mixing two days
            # would answer a question nobody asked. Rows within the same date
            # are the same run, so they combine instead.
            #
            # The combination is not an average. If every file passed the cell
            # is `pass`; if any did not, the cell shows the FIRST failing
            # verdict, because a run with one failure is a failing run and the
            # detail belongs in results.csv2 where each row names its file.
            #
            # 以**最新日期**為準，而同一日期之內的資料列則合併。
            #
            # 此處原本是 `cell[app, pair] = verdict " " date`，也就是「最後讀到的那一列直接取代原
            # 有內容」。在 sweep_drive.zsh 每支 app 只輸出一列時，那是正確的；但當該腳本開始驅動
            # **每一個**動作檔的那一刻起，它就開始遺失結果——因為同一天、同一支 app 的第二個檔案會
            # 靜默覆蓋第一個。P46 有三個，P24、P20、P19、P13 與 P10 各有兩個，合計 38 個檔案中的
            # 5 個；於是一次通過可能蓋掉一小時前的一次失敗，而不會有任何東西說出來。
            #
            # **較新的日期**仍然捨棄較舊者，這是刻意的：一格的意思是「那一天發生了什麼」，把兩天
            # 混在一起等於回答一個沒有人問的問題。同一日期內的資料列屬於同一次執行，因此改為合併。
            #
            # 合併不是取平均。若每個檔案都通過，該格為 `pass`；只要有任何一個沒通過，該格顯示
            # **第一個失敗的判決**——因為「有一項失敗的執行」就是失敗的執行，而細節屬於
            # results.csv2，那裡的每一列都標明了自己的檔案。
            # KEYED BY ACTION FILE, latest per file wins, then combined.
            #
            # Rows appended by sweep_drive.zsh carry their action file at the
            # front of the note, `P10-ctrl-q.csv: ...`, because the `app` column
            # cannot hold it. Rows written before that share one key, which
            # makes them behave exactly as they always did.
            #
            # WHY NOT "any failure that day poisons the cell", which is what this
            # was for one commit: because several rows for one app on one date
            # are usually a DAY OF DEBUGGING, not several files, and the last one
            # is the conclusion. P1 on mac 2026-09-01 has two rows -- `no marker,
            # launched but the render marker never appeared`, then `ok, no marker
            # configured; capture is timed`. The second retracts the first. P26
            # has seven, four of them `never launched` while the loader was being
            # fixed, ending `ok ok window`. Combining those reported eighteen
            # cells as failing that were nothing of the kind, and the claim was
            # made and withdrawn within the hour.
            #
            # Superseding still works, because latest-per-file still wins. What
            # is fixed is only the case the file key distinguishes: two DIFFERENT
            # files for one app, where the second used to overwrite the first.
            #
            # 以**動作檔**為鍵，每個檔案取最新者，再行合併。
            #
            # sweep_drive.zsh 追加的資料列會把動作檔名放在 note 的最前面，形如
            # `P10-ctrl-q.csv: ...`，因為 `app` 欄放不下它。在那之前寫入的資料列共用同一個鍵，
            # 因此其行為與過去完全一致。
            #
            # 為何不採「當天只要有一項失敗就毒化該格」——那正是本處曾有一個 commit 的做法：因為
            # 「同一天、同一支 app 的數列」通常是**一天的除錯過程**，而不是數個檔案，且最後一列才是
            # 結論。P1 在 mac 2026-09-01 有兩列——`no marker, launched but the render marker never
            # appeared`，接著是 `ok, no marker configured; capture is timed`；第二列在**撤回**第一列。
            # P26 有七列，其中四列是 loader 被修好之前的 `never launched`，最後結束於 `ok ok window`。
            # 把它們合併，會把十八格根本不是失敗的格子報成失敗；那個主張在一小時之內就被提出又收回。
            #
            # 「後者取代前者」依然有效，因為每個檔案仍是最新者勝出。真正被修好的，只有「檔案鍵」所能
            # 區分的那一種情況：同一支 app 的**兩個不同檔案**，過去第二個會覆蓋第一個。
            note = field("note")
            fileKey = "-"
            if (match(note, /^[^ :]+\.csv: /))
                fileKey = substr(note, 1, RLENGTH - 2)

            # THE RENDERER IS PART OF THE KEY, added 2026-09-07 with the
            # `renderer` column itself.
            #
            # The key answers "is this the same run, superseded, or a different
            # run that also happened that day". A renderer makes it a different
            # run. Measured that day on WSL: P11 at 788x649, minutes apart,
            # captured 0.0% non-black under `-render hw` (GSK chose
            # GskGLRenderer) and 92.1% under `-render sw` (GskVulkanRenderer on
            # llvmpipe). Without the renderer in the key those two share one
            # key, so the second one read silently REPLACES the first and the
            # matrix reports whichever was appended last -- one condition
            # standing in for both, with no sign that the other ever ran.
            #
            # This is the same shape as the action-file key above and is fixed
            # the same way. With both in the key the pair combines instead: a
            # cell showing `fail 1/2` says one of the two conditions failed,
            # and results.csv2 names which. The ratio therefore counts distinct
            # (renderer, action file) runs, not action files alone.
            #
            # It changes nothing for the existing history, where every row reads
            # `unrecorded` and so every key is unchanged -- verified: the
            # generated coverage.md is byte-identical across the migration. The
            # 44 WSL rows of 2026-09-07 stay merged, because the thing that
            # would separate them was never written down. That is the cost of
            # the omission and it is not recoverable here.
            #
            # renderer 也是鍵的一部分，於 2026-09-07 隨 `renderer` 欄一併加入。
            #
            # 這個鍵回答的是「這是同一次執行、是被取代、還是當天另一次不同的執行」。renderer 不同，
            # 就是不同的執行。當天在 WSL 上實測：P11 於 788x649，前後相隔數分鐘，`-render hw`
            # （GSK 選用 GskGLRenderer）擷取到的非黑比例為 0.0%，`-render sw`（llvmpipe 上的
            # GskVulkanRenderer）則為 92.1%。若鍵中不含 renderer，這兩者共用同一個鍵，於是後讀到
            # 的那一列會靜默**取代**前一列，矩陣呈現的是最後被追加的那一個——由一種條件代表兩種，
            # 且沒有任何跡象顯示另一種曾經跑過。
            #
            # 這與上方動作檔鍵是同一種形狀，也以同一種方式修正。兩者都入鍵之後，該對資料改為合併：
            # 一格顯示 `fail 1/2` 即表示兩種條件中有一種失敗了，而 results.csv2 會指出是哪一種。
            # 因此該比例計數的是不同的 (renderer, 動作檔) 執行，而不只是動作檔。
            #
            # 對既有歷史毫無影響：那裡每一列都讀作 `unrecorded`，因此每一個鍵都不變——已驗證：
            # 產生出來的 coverage.md 在遷移前後位元組完全相同。2026-09-07 的那 44 列 WSL 紀錄依然
            # 合併在一起，因為能區分它們的那樣東西從來沒有被寫下來。那是這次遺漏的代價，且在此處
            # 已無從挽回。
            renderer = field("renderer")
            if (renderer != "") fileKey = renderer "/" fileKey

            # The accumulator is ONE STRING PER CELL, `file=verdict|` repeated,
            # rather than a shared array keyed by app and file.
            #
            # A shared array needs clearing when a newer date arrives, and
            # `delete arr` in awk clears the WHOLE array -- every other app and
            # its verdicts with it. (No apostrophes in here: this program is
            # inside a single-quoted argument, and one in a COMMENT ends the
            # quote. It did, and zsh reported a parse error two hundred lines
            # away at the first bare parenthesis it then met.)
            # Rows arrive interleaved across apps and platforms, so
            # that would empty cells at random depending on the order results
            # were appended in, which is a bug that would have looked like data
            # loss rather than like a bug.
            #
            # 累積器是**每格一個字串**，內容為重複的 `file=verdict|`，而非一個以 app 與檔案為鍵的
            # 共用陣列。
            #
            # 共用陣列在較新日期出現時需要清空，而 awk 的 `delete arr` 會清掉**整個**陣列——連同其他
            # 每一支 app 的判決。資料列在各 app 與各平台之間是交錯抵達的，因此那會依「結果被追加的
            # 順序」隨機清空某些格子;那種 bug 看起來會像資料遺失，而不像 bug。
            if (date > cellDate[app, pair]) {
                cellDate[app, pair] = date
                acc[app, pair] = ""
            }
            if (date == cellDate[app, pair]) {
                # Rebuilt rather than appended, because a later row REPLACES an
                # earlier one for the same file and a running total cannot take
                # a verdict back.
                # 採重建而非追加：因為同一個檔案的較新資料列會**取代**較舊者，而累加式的計數收不回
                # 一個已經計入的判決。
                n = split(acc[app, pair], parts, "|")
                out = ""; replaced = 0
                for (i = 1; i <= n; i++) {
                    if (parts[i] == "") continue
                    eq = index(parts[i], "=")
                    f = substr(parts[i], 1, eq - 1)
                    v = substr(parts[i], eq + 1)
                    if (f == fileKey) { v = verdict; replaced = 1 }
                    out = out f "=" v "|"
                }
                if (!replaced) out = out fileKey "=" verdict "|"
                acc[app, pair] = out

                n = split(out, parts, "|")
                passes = 0; failed = ""; files = 0
                for (i = 1; i <= n; i++) {
                    if (parts[i] == "") continue
                    files++
                    v = substr(parts[i], index(parts[i], "=") + 1)
                    if (v == "pass") passes++
                    else if (failed == "") failed = v
                }
                fileCount[app, pair] = files
                shown = (failed == "") ? "pass" : failed
                # The ratio only when more than one file ran, so every
                # single-file cell reads exactly as it did before.
                # 只有在跑了超過一個檔案時才附上比例，如此每一個單檔的格子讀起來與從前完全相同。
                if (fileCount[app, pair] > 1)
                    shown = shown " " passes "/" fileCount[app, pair]
                cell[app, pair] = shown " " date
            }
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
