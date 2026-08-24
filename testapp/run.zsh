#!/usr/bin/env zsh
# Launch a -gtk4 Pn on Windows with GTK's DLLs findable.
#
#   zsh testapp/run.zsh P9                 launch P9.exe
#   zsh testapp/run.zsh P9 --debug         pass flags straight through
#   zsh testapp/run.zsh P19 --debug -actionfile actions/win/P19-open-and-select.csv
#
# 在 Windows 上啟動 -gtk4 的 Pn，並讓 GTK 的 DLL 找得到。
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
    sed -n '2,20p' "$script_path" | sed 's/^# \{0,1\}//'
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

exec "$exe" "$@"
