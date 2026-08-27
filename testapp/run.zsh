#!/usr/bin/env zsh
# Launch a -gtk4 Pn on Windows with GTK's DLLs findable.
#
#   zsh testapp/run.zsh P9                 launch P9.exe
#   zsh testapp/run.zsh P9 --debug         pass flags straight through
#   zsh testapp/run.zsh P19 --debug -actionfile actions/win/P19-open-and-select.csv
#
# An -actionfile path is tried as given, then under testapp/, so both
# `actions/win/P19-...csv` and `testapp/actions/win/P19-...csv` work from
# anywhere. Why bother: the app resolves that path itself, with
# `URL(fileURLWithPath:)` in Sources/InputEvent/ActionFileReplay.swift, and a
# relative path there is relative to the *process's* working directory --
# whichever directory you ran this from, since nothing in this script cd's. The
# example above was in this header before the resolution existed, and from the
# repo root it named a directory that is not there. Nothing says so usefully:
# the window comes up, the replay reports `failed:` for a file it could not
# open, and the app looks like it ignored its input. Accepting both spellings
# costs less than being right about which directory the reader is standing in.
#
# 在 Windows 上啟動 -gtk4 的 Pn，並讓 GTK 的 DLL 找得到。
#
# -actionfile 的路徑會先照原樣嘗試，再嘗試 testapp/ 之下，因此
# `actions/win/P19-...csv` 與 `testapp/actions/win/P19-...csv` 在任何目錄下都可用。
# 為何要這麼做：該路徑是由 app 自行解析的（Sources/InputEvent/ActionFileReplay.swift 中的
# `URL(fileURLWithPath:)`），而其中的相對路徑是相對於**行程**的工作目錄——也就是你執行本腳本時
# 所在的目錄，因為本腳本不做任何 cd。上方的範例在此解析機制存在之前就寫在標頭中，而從 repo 根目錄
# 看，它指的是一個不存在的目錄。而且沒有任何訊息能有效指出此事：視窗照常出現，重放對一個打不開的
# 檔案回報 `failed:`，於是 app 看起來就像忽略了輸入。接受兩種寫法，比「猜對讀者站在哪個目錄」便宜。
#
# Why this exists: compile.zsh puts C:/gtk4/bin on PATH for the build shell, and
# that directory holds both the GTK DLLs and the UCRT (api-ms-win-crt-*). A
# separate shell launching the exe has neither, so it dies before main with
#   api-ms-win-crt-locale-l1-1-0.dll: cannot open shared object file
# The named library is the UCRT, which sends the reader looking for a broken
# Visual C++ install; what is actually missing is the whole C:/gtk4/bin.
#
# 存在理由：compile.zsh 只為建置的 shell 把 C:/gtk4/bin 加進 PATH，而該目錄同時存放 GTK 的 DLL
# 與 UCRT（api-ms-win-crt-*）。另一個 shell 啟動該 exe 時兩者皆無，因此會在進入 main 之前就以
#   api-ms-win-crt-locale-l1-1-0.dll: cannot open shared object file
# 死掉。訊息指名的函式庫是 UCRT，會把讀者引向「Visual C++ 安裝損壞」；但真正缺少的，是整個
# C:/gtk4/bin。
#
# Only for direct launches. `zsh testapp/test.zsh <Pn> --windows` already sets
# the same PATH itself; this is for running an exe by hand.
# 僅供直接啟動使用。`zsh testapp/test.zsh <Pn> --windows` 本身已設定相同的 PATH；此腳本是供
# 手動執行某個 exe 之用。

set -uo pipefail
setopt no_nomatch

script_path="${0:A}"
script_dir="${script_path:h}"

if [ "${1:-}" = --help ] || [ "${1:-}" = -h ] || [ "$#" -eq 0 ]; then
    # Everything from line 2 up to the first line that is not a comment, rather
    # than a fixed range. A range has to be corrected in the same edit that adds
    # a paragraph, and this one was not: it stopped at line 20, mid-sentence and
    # mid-language, once the header above grew.
    # 從第 2 行印到第一個非註解行，而不是寫死行號範圍。寫死的範圍必須在「新增段落」的同一次編輯中
    # 一併修正，而它並沒有：標頭一長，它就停在第 20 行——句子中間，語言中間。
    sed -n '2,${/^#/!q; s/^# \{0,1\}//p;}' "$script_path"
    exit 0
fi

app="$1"
shift
case "$app" in
    *.exe) app="${app%.exe}" ;;
esac

exe="$script_dir/output/$app.exe"
if [ ! -x "$exe" ]; then
    printf 'No such executable: %s\n' "$exe" >&2
    printf 'Build it first: SCUI_DEBUG=1 zsh testapp/compile.zsh -gtk4 %s\n' "$app" >&2
    exit 1
fi

# POSIX form before it touches PATH. `:` is the separator here, so C:/gtk4/bin
# is not one entry but two -- `C` and `/gtk4/bin`, neither of which exists.
# 在接觸 PATH 之前先轉為 POSIX 形式。此處的 `:` 是分隔符，因此 C:/gtk4/bin 並非單一項目——而是
# `C` 與 `/gtk4/bin` 兩項，兩者皆不存在。
gtk_prefix="${GTK4_PREFIX:-C:/gtk4}"
gtk_bin="$(cygpath -u "$gtk_prefix/bin" 2>/dev/null || printf '%s' "$gtk_prefix/bin")"
if [ ! -d "$gtk_bin" ]; then
    printf 'GTK 4 not found at %s\n' "$gtk_prefix" >&2
    printf 'Run: zsh testapp/install_gtk4_windows.zsh\n' >&2
    exit 1
fi
export PATH="$gtk_bin:$PATH"

# The path after `-actionfile`, resolved here rather than left to the app.
#
# Tried as given first, so a path that already works keeps working; then under
# testapp/, which is what makes the short form in the header true from the repo
# root. The header says why the app itself cannot do this.
#
# `exit` from inside the function, and the result handed back in a variable
# rather than through `$(...)`. An `exit` inside a command substitution ends
# only the subshell: the complaint would be printed and the app launched anyway,
# with an empty path where the file should be -- a replay that reports `failed:`
# for a file nobody named, which is a worse place to start than the missing file
# it came from.
#
# `cygpath -m` because the exe is a Windows binary and cannot open an MSYS path
# such as /c/Users/... . Nothing reports that either: Foundation returns nil and
# the window sits there looking like the replay did nothing. Same reason as the
# note beside `args=` in testapp/test_support/test_common.zsh.
#
# `-actionfile` 之後的路徑在此解析，而非交給 app。
#
# 先照原樣嘗試，讓原本可用的路徑繼續可用；再嘗試 testapp/ 之下，這正是讓標頭中的短寫法在 repo
# 根目錄下也成立的原因。app 為何無法自行處理，見標頭。
#
# 在函式內 `exit`，並以變數而非 `$(...)` 回傳結果。命令替換中的 `exit` 只會結束子 shell：訊息會印出，
# app 仍照樣啟動，而檔案位置換成一個空字串——於是重放會為「沒有人指名的檔案」回報 `failed:`，
# 那比原本的「檔案不存在」更難查。
#
# 使用 `cygpath -m`：該 exe 是 Windows 原生執行檔，無法開啟 /c/Users/... 這類 MSYS 路徑。此事同樣
# 無人回報：Foundation 回傳 nil，視窗就停在那裡，看起來像重放什麼都沒做。與
# testapp/test_support/test_common.zsh 中 `args=` 旁的註解同一個理由。
resolved_action_file=""
resolve_action_file() {
    local given="$1"
    local found=""
    if [ -f "$given" ]; then
        found="$given"
    elif [ -f "$script_dir/$given" ]; then
        found="$script_dir/$given"
    else
        printf 'No such action file: %s\n' "$given" >&2
        printf 'Tried it as given, and as %s\n' "$script_dir/$given" >&2
        exit 1
    fi
    resolved_action_file="$(cygpath -m "${found:A}" 2>/dev/null || printf '%s' "${found:A}")"
}

args=()
next_is_action_file=0
for arg in "$@"; do
    if [ "$next_is_action_file" -eq 1 ]; then
        resolve_action_file "$arg"
        args+=("$resolved_action_file")
        next_is_action_file=0
        continue
    fi
    args+=("$arg")
    if [ "$arg" = "-actionfile" ]; then
        next_is_action_file=1
    fi
done

exec "$exe" "${args[@]}"
