#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P73"
# Title copied from P73.swift's WindowGroup. No marker: P73 prints to stdout, which
# the marker wait does not read (see test_P45.zsh); with an action file, test_common
# waits for the replay to finish instead.
# 標題照抄自 P73.swift 的 WindowGroup。不設 marker:P73 印到 stdout,而 marker 等待不讀它
# (見 test_P45.zsh);有動作檔時,test_common 改為等重放結束。
export TEST_TITLE="P73 publish during build"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
