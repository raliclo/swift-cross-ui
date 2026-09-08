#!/usr/bin/env zsh
# =====================================================================
# wsl_run.zsh — run a shell script inside WSL without Windows eating its
#               `$` expansions. Reads the script from a file or stdin.
# wsl_run.zsh — 在 WSL 內執行一段 shell 腳本，而不讓 Windows 側先吃掉它的 `$` 展開。
#               腳本由檔案或 stdin 讀入。
#
#   zsh testapp/test_support/wsl_run.zsh script.sh
#   printf '%s\n' 'echo "files: $(ls | wc -l)"' | zsh testapp/test_support/wsl_run.zsh
#   zsh testapp/test_support/wsl_run.zsh --help
#
# WHY THIS EXISTS. `wsl.exe -- sh -c '...'` loses every `$` in the string,
# even inside single quotes: Git Bash consumes the quotes (they are its own
# syntax), expands `$var`, `$(...)` and `$?` against ITS OWN environment,
# and only then does wsl.exe reassemble a command line for the Linux shell.
# The Linux side never sees what was written.
#
# It cost four wrong measurements in one session on 2026-09-08, and each
# one looked like a result rather than an error:
#
#   `ls X | wc -l` per file      three files reported ABSENT after an rsync
#                                that had in fact delivered 104
#   `command -v $t` in a loop    all six capture tools reported MISSING;
#                                the loop variable had been emptied, so
#                                `command -v` ran with no argument at all
#   `echo "$?"` after a build    rc=0 for a build that had FAILED on a
#                                hardcoded swiftc path
#   `wc -c < log` in a poll      "0" for eight consecutive polls of a build
#                                that finished in 58 seconds
#
# None of them errored. Every one produced a plausible number.
#
# THE FIX IS THE PIPE, NOT ESCAPING. `\$` works for a bare variable but not
# reliably for `$(...)`, and it has to be got right at every site forever.
# Sending the script on STDIN means it never enters argv, so there is
# nothing for Git Bash to expand. `sh -s` reads the program from stdin.
#
# `MSYS2_ARG_CONV_EXCL='*'` is still set here for a DIFFERENT trap: MSYS
# rewrites POSIX-looking paths in argv, so `/tmp/x` would arrive as
# `C:/Users/.../Temp/x`. That one is about paths, not `$`, and both are
# needed.
#
# 為何存在。`wsl.exe -- sh -c '...'` 會弄丟字串中的每一個 `$`，即使包在單引號裡：Git Bash 先消費掉
# 那些引號（那是它自己的語法），以**它自己的**環境展開 `$var`、`$(...)` 與 `$?`，然後 wsl.exe 才為
# Linux shell 重組命令列。Linux 那一側從未看見原本寫下的東西。
#
# 2026-09-08 一個 session 內因此產生四次錯誤量測，而每一次看起來都像結果、不像錯誤：rsync 明明送
# 達 104 個檔案卻回報三個檔案不存在；六個擷取工具全數回報 MISSING（迴圈變數被清空，`command -v`
# 根本是在沒有引數的情況下執行）；一個因 swiftc 路徑寫死而失敗的建置回報 rc=0；一個 58 秒就完成
# 的建置，連續八輪輪詢都回報 "0"。沒有任何一次報錯。
#
# 修法是管線，不是跳脫。`\$` 對單純變數有效，對 `$(...)` 並不可靠，而且必須在每一個使用點永遠寫對。
# 以 **stdin** 送入腳本，它就完全不會進入 argv，Git Bash 也就沒有東西可以展開。`sh -s` 會從 stdin
# 讀取程式本體。
#
# 此處仍設定 `MSYS2_ARG_CONV_EXCL='*'`，但那是為了**另一個**陷阱：MSYS 會改寫 argv 中看起來像
# POSIX 的路徑，`/tmp/x` 會變成 `C:/Users/.../Temp/x`。那一條關於路徑、與 `$` 無關，兩者都需要。
# =====================================================================
set -euo pipefail

script_path="${0:A}"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    sed -n '2,20p' "$script_path" | sed 's/^# \{0,1\}//'
    exit 0
fi

# Read the program: a file if one was named, otherwise stdin.
# 讀入程式本體：有指名檔案就讀該檔，否則讀 stdin。
if [ "$#" -gt 0 ]; then
    if [ ! -r "$1" ]; then
        printf 'wsl_run: cannot read %s\n' "$1" >&2
        exit 2
    fi
    program="$(cat -- "$1")"
else
    program="$(cat)"
fi

if [ -z "$program" ]; then
    printf 'wsl_run: empty program; nothing to run\n' >&2
    exit 2
fi

# The exit status is the Linux side's, not this shell's. Reporting the
# wrapper's status would reintroduce exactly the `$?` confusion above.
# 退出狀態取自 Linux 那一側，而非本 shell。回報包裝器自身的狀態，等於把上述 `$?` 的混淆原樣搬回來。
printf '%s\n' "$program" | MSYS2_ARG_CONV_EXCL='*' wsl.exe -- sh -s
