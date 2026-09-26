#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P49"
# **This script did not exist until 2026-09-27**, though P49 had three macOS
# action files; the first macOS sweep found `test.zsh P49` stopping at "Missing
# test script". Title copied from P49.swift's WindowGroup. No marker, for the
# reason test_P45.zsh gives: P49 prints RENDER COMPLETE to stdout, not to the
# debug-events log the marker wait reads.
#
# **這支腳本在 2026-09-27 之前不存在**,雖然 P49 有三份 macOS 動作檔;第一次 macOS sweep 發現
# `test.zsh P49` 停在「Missing test script」。標題照抄自 P49.swift 的 WindowGroup。不設 marker,
# 理由見 test_P45.zsh:P49 把 RENDER COMPLETE 印到 stdout,而不是 marker 等待所讀的 debug-events log。
export TEST_TITLE="P49 presentations"
export TEST_TARGET="mac"
exec zsh "$support_dir/test_common.zsh" "$@"
