#!/usr/bin/env zsh
# Scans this project's zsh and sh files for names and idioms that fail quietly.
#
#   zsh lint.zsh                 every tracked .zsh
#   zsh lint.zsh a.zsh b.zsh     just these
#   zsh lint.zsh --quiet         findings only, no banner
#   zsh lint.zsh --help
#
# Exit 1 if anything at FATAL is found, 0 otherwise. WARN does not fail the run.
#
# WHY THIS EXISTS RATHER THAN A COMMENT SOMEWHERE. On 2026-08-27
# `print_actionfile_report` in test_common.zsh was found to begin with
# `local path="$1"`. In zsh `path` is the array tied to `PATH`, so for the length
# of that function PATH went from 49 entries to one -- the name of a log file --
# and `command -v` answered NONE for `grep`, `sed` and `zsh` alike. The `grep`
# inside had never once executed, and under `set -e` it aborted the script
# with 127.
#
# The part worth acting on is not the bug. It is that **two other files in this
# same repo already carried a comment warning against exactly this**, in
# `test_android.zsh` and `test_ios.zsh`, and a third file had it anyway. Written
# knowledge did not prevent it. A check that fails does.
#
# WHAT IT CANNOT CATCH. Literal assignments and `for` bindings only. `eval`,
# `read path`, `getopts` into one of these names, and any indirect assignment
# get past it. It is a tripwire, not a proof, and a clean run is not a
# guarantee.
#
# 掃描本專案的 zsh 與 sh 檔案，找出會「安靜地出錯」的名稱與寫法。
#
# 發現任何 FATAL 即以 1 結束，否則為 0。WARN 不會使本次執行失敗。
#
# 為何需要它，而非在某處寫一句註解。2026-08-27 發現 test_common.zsh 的
# `print_actionfile_report` 第一行是 `local path="$1"`。在 zsh 中 `path` 是與 `PATH` 綁定的陣列，
# 因此在該函式執行期間，PATH 由 49 個項目變成 1 個——一個 log 檔名——而 `command -v` 對 `grep`、
# `sed`、`zsh` 一律回答 NONE。其中的 `grep` 從來沒有執行成功過，且在 `set -e` 下以 127 中止腳本。
#
# 值得據以行動的並不是這個 bug 本身，而是：**本 repo 中已有另外兩個檔案帶著針對此事的警告註解**
# （test_android.zsh 與 test_ios.zsh），第三個檔案照樣中招。寫下來的知識沒能阻止它，會失敗的檢查
# 才能。
#
# 它抓不到什麼：只抓字面上的指派與 `for` 綁定。`eval`、`read path`、把 getopts 讀進這些名稱，
# 以及任何間接指派，都逃得掉。這是一條絆索，不是一份證明；乾淨通過並不等於保證。

set -uo pipefail

script_path="${0:A}"
repo="${script_path:h}"

quiet=0
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    sed -n '2,40p' "$script_path" | sed 's/^# \{0,1\}//'
    exit 0
fi
if [ "${1:-}" = "--quiet" ]; then
    quiet=1
    shift
fi

if [ "$#" -gt 0 ]; then
    files=("$@")
else
    # Tracked files only. The vendored trees are full of these -- libpng's
    # ltmain.sh under .build assigns `path=` in five places, and GTK's own
    # testsuite under testapp/gtk4-source uses `status=` -- and none of it is
    # ours to fix. `git ls-files` excludes them for free.
    # 只檢查納入版控的檔案。vendored 的目錄樹滿是這些寫法——.build 底下 libpng 的 ltmain.sh 有五處
    # `path=`，testapp/gtk4-source 底下 GTK 自己的 testsuite 使用 `status=`——而那些都不是我們該修
    # 的。用 `git ls-files` 即可免費排除。
    files=(${(f)"$(cd "$repo" && git ls-files '*.zsh')"})
fi

fatal_count=0
warn_count=0

# ─────────────────────────────────────────────────────────────────────────────
# The rules
# ─────────────────────────────────────────────────────────────────────────────
#
# Ordered by how quietly each one fails, worst first. That ordering is the whole
# design: a name that errors at the point of assignment needs no linter, and a
# name that empties PATH and lets the script carry on does.
#
# 依「失敗得多安靜」排序，最糟的在前。這個排序就是全部的設計：一個在指派當下就報錯的名稱不需要
# linter，而一個把 PATH 清空、還讓腳本繼續跑下去的名稱才需要。

# Tied to a real parameter. Assigning empties or replaces the thing the shell
# runs on, and nothing says so.
# 與真實參數綁定。指派會清空或取代 shell 賴以運作的東西，而且沒有任何東西會說。
tied_names=(path fpath cdpath manpath fignore)

# Autoloads a module on assignment. Works where module_path is right and fails
# with `failed to load module zsh/watch` where it is not -- so it passes on the
# machine it was written on.
# 指派時會 autoload 模組。在 module_path 正確之處可運作，不正確之處則以
# `failed to load module zsh/watch` 失敗——因此它在「寫它的那台機器上」總是通過。
module_names=(watch)

# Read-only or special. These error at the assignment, which is loud, but a
# `local status=$?` still aborts a run and the message does not name the cause.
# 唯讀或特殊參數。它們在指派當下就報錯（夠大聲），但 `local status=$?` 仍會中止整場執行，而其訊息
# 並不會指出真正的原因。
special_names=(status options argv)

report() {
    local severity="$1" file="$2" rule="$3" hits="$4"
    printf '\n  %s  %s\n' "$severity" "$file"
    printf '        %s\n' "$rule"
    printf '%s\n' "$hits" | sed 's/^/        /'
}

for file in $files; do
    full="$repo/$file"
    [ -f "$full" ] || full="$file"
    [ -f "$full" ] || continue

    # Comment lines are dropped first. Three files in this repo mention `path=`
    # only to warn about it, and a linter that flags its own documentation is a
    # linter people switch off.
    # 先剔除註解行。本 repo 有三個檔案提到 `path=` 純粹是為了警告它，而一個會對自己的文件報警的
    # linter，是一個大家會關掉的 linter。
    body="$(grep -vE '^[[:space:]]*#' "$full" 2>/dev/null)"

    for name in $tied_names $module_names $special_names; do
        hits="$(printf '%s\n' "$body" \
            | grep -nE "(^|[^A-Za-z0-9_])(local |typeset |declare )?${name}=|(^|[^A-Za-z0-9_])for +${name} +in" \
            2>/dev/null)"
        [ -z "$hits" ] && continue

        case " ${tied_names[*]} " in
            *" $name "*)
                report FATAL "$file" \
                    "assigns to \`$name\`, the array zsh ties to \$${name:u} -- the real one is replaced for the rest of the scope" \
                    "$hits"
                fatal_count=$((fatal_count + 1))
                continue
                ;;
        esac
        case " ${module_names[*]} " in
            *" $name "*)
                report FATAL "$file" \
                    "assigns to \`$name\`, which autoloads zsh/$name -- it works only where module_path happens to be right" \
                    "$hits"
                fatal_count=$((fatal_count + 1))
                continue
                ;;
        esac
        report FATAL "$file" \
            "assigns to \`$name\`, a special parameter -- the assignment errors and takes the run with it" \
            "$hits"
        fatal_count=$((fatal_count + 1))
    done

    # `print` is a zsh builtin only. In bash it falls through to PATH and on
    # Windows hits C:\Windows\System32\print.exe -- the printer -- which writes
    # `Unable to initialize device PRN` to stdout and exits 0. Redirect that into
    # a file and an error message has been silently written as content.
    #
    # `print -P` inside a .zsh file is exempt: -P does prompt expansion for
    # colour and printf has no equivalent.
    #
    # `print` 只是 zsh 的 builtin。在 bash 中它會落到 PATH 查找，在 Windows 上打到
    # C:\Windows\System32\print.exe——那台印表機——它會把 `Unable to initialize device PRN` 寫到
    # stdout 並以 0 結束。把它導進檔案，等於安靜地把一則錯誤訊息寫成了內容。
    #
    # .zsh 檔案中的 `print -P` 屬例外：-P 會做 prompt 展開以輸出顏色，而 printf 沒有對應功能。
    # Single-quoted regions are skipped, tracked across lines. `print` inside
    # them is not a zsh command -- it is almost always awk's `print`, and this
    # repo embeds multi-line awk programs in several scripts.
    #
    # Measured on this linter's first run: `{ print $9 }` inside screenshot.zsh's
    # tasklist parser was reported three times, along with two more in
    # testapp/rebase.zsh. A linter with obvious false positives is one people
    # switch off, so this is worth the state machine rather than a `grep -v awk`
    # that would also hide a real hit on a line that happens to mention awk.
    #
    # 會跨行追蹤並跳過單引號區段。其中的 `print` 並非 zsh 指令——它幾乎總是 awk 的 `print`，而本
    # repo 有數個腳本內嵌了多行的 awk 程式。
    #
    # 於本 linter 首次執行時實測：screenshot.zsh 中 tasklist 解析器裡的 `{ print $9 }` 被報了三次，
    # testapp/rebase.zsh 另有兩次。一個有明顯誤報的 linter 是大家會關掉的 linter，因此這個狀態機
    # 值得寫——而不是用 `grep -v awk` 了事，那會連「碰巧提到 awk 的那一行上的真實命中」也一併藏起來。
    print_hits="$(printf '%s\n' "$body" | awk '
        {
            line = $0
            out = ""
            i = 1
            n = length(line)
            while (i <= n) {
                c = substr(line, i, 1)
                if (inq) {
                    if (c == "'"'"'") inq = 0
                } else if (c == "'"'"'") {
                    inq = 1
                } else {
                    out = out c
                }
                i++
            }
            # NR here is the line number within `body`, which is what the other
            # rules report too.
            # 此處的 NR 是 body 內的行號，與其他規則所回報的一致。
            if (out ~ /(^|[;&|{][ \t]*|[ \t])print[ \t]/ && out !~ /print[ \t]+-P/ && out !~ /printf/)
                printf "%d:%s\n", NR, line
        }
    ')"
    if [ -n "$print_hits" ]; then
        case "$file" in
            *.sh)
                report FATAL "$file" \
                    'uses `print` in an sh file -- not a builtin there; on Windows it runs System32\print.exe and writes "Unable to initialize device PRN" to stdout, exit 0' \
                    "$print_hits"
                fatal_count=$((fatal_count + 1))
                ;;
            *)
                report WARN "$file" \
                    'uses `print` without -P -- portable only while the file stays zsh; printf is a builtin in both shells' \
                    "$print_hits"
                warn_count=$((warn_count + 1))
                ;;
        esac
    fi

    # `echo -n` and `echo -e` are not portable: the flag handling differs
    # between shells and builds, so the flag is sometimes printed as text.
    # `echo -n` 與 `echo -e` 不具可攜性：不同 shell 與不同建置對旗標的處理各異，因此該旗標有時會
    # 被當成文字印出來。
    echo_hits="$(printf '%s\n' "$body" | grep -nE '(^|[;&|][[:space:]]*|[[:space:]])echo[[:space:]]+-[neE]')"
    if [ -n "$echo_hits" ]; then
        report WARN "$file" \
            'uses `echo` with a flag -- -n/-e handling varies; use printf' \
            "$echo_hits"
        warn_count=$((warn_count + 1))
    fi
done

if [ "$quiet" -eq 0 ]; then
    printf '\n'
    printf '─────────────────────────────────────────────────────────────\n'
    printf ' lint.zsh   %s files scanned\n' "${#files}"
    printf '            %s FATAL   %s WARN\n' "$fatal_count" "$warn_count"
    printf '─────────────────────────────────────────────────────────────\n'
fi

if [ "$fatal_count" -gt 0 ]; then
    printf '\n'
    printf '!! %s FATAL finding(s). These do not announce themselves at runtime:\n' "$fatal_count"
    printf '!! a name tied to a real parameter empties it for the rest of the scope,\n'
    printf '!! and the failure surfaces later as a command that is suddenly missing.\n'
    printf '!! Rename the variable. There is no case where the tied name is wanted.\n'
    printf '\n'
    printf '!! %s 項 FATAL。它們在執行期不會自己出聲：綁定至真實參數的名稱會在其作用域內把該參數\n' "$fatal_count"
    printf '!! 清空，而失敗會延後浮現，表現為「某個指令突然找不到」。請改名——沒有任何情況會需要\n'
    printf '!! 使用這些被綁定的名稱。\n'
    exit 1
fi

if [ "$warn_count" -gt 0 ]; then
    printf '\n%s warning(s), none fatal. / %s 項警告，皆非致命。\n' "$warn_count" "$warn_count"
fi

exit 0
