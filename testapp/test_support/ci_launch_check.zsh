#!/usr/bin/env zsh
# CI launch check for a test app on a host with no input injection: start it, let
# it run SECONDS, and fail if it exits before then (a launch crash) or, when a
# MARKER is given, if its output never shows it. Added 2026-11-13, when every
# Android app trapped at launch and the only job that could see it was the
# Android sweep.
#
#   zsh testapp/test_support/ci_launch_check.zsh SECONDS MARKER|- COMMAND [ARGS...]
#
# Linux runs it under xvfb-run; macOS and Windows runners have a desktop.
# CI 用的測試 app 啟動檢查，給無法注入輸入的主機：啟動它、讓它跑 SECONDS 秒；若它在那之前結束(啟動即當)，
# 或給了 MARKER 而輸出中始終沒有出現，就失敗。2026-11-13 加入，當時每支 Android app 都在啟動時當掉，
# 而唯一看得到的只有 Android sweep。Linux 在 xvfb-run 下執行;macOS 與 Windows 的 runner 有桌面。
set -uo pipefail

(( $# >= 3 )) || { print -u2 "usage: ${0:t} SECONDS MARKER|- COMMAND [ARGS...]"; exit 64; }
seconds=$1 marker=$2
shift 2
log="${CI_LAUNCH_LOG:-${TMPDIR:-/tmp}/ci-launch-${1:t}.log}"

"$@" >"$log" 2>&1 &
pid=$!
print "==> ${1:t}: pid $pid, ${seconds}s, marker ${marker}, log $log"

fail() {
    print -u2 "!! ${1:t}: $2"
    print -u2 -r -- "-- last lines of $log:"
    tail -n 40 "$log" >&2
    kill "$pid" 2>/dev/null
    exit 1
}

for (( i = 0; i < seconds; i++ )); do
    perl -e "select(undef, undef, undef, 1)"
    if ! kill -0 "$pid" 2>/dev/null; then
        wait "$pid"
        fail "$1" "exited with status $? after about $(( i + 1 ))s, before ${seconds}s"
    fi
done

if [[ "$marker" != - ]] && ! grep -aqF -- "$marker" "$log"; then
    fail "$1" "still running after ${seconds}s, but its output never showed \"$marker\""
fi

kill "$pid" 2>/dev/null
wait "$pid" 2>/dev/null
if [[ "$marker" == - ]]; then print "==> ${1:t}: ran ${seconds}s"; else print "==> ${1:t}: ran ${seconds}s and showed \"$marker\""; fi
