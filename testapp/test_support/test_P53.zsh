#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P53"
# **This script did not exist until 2026-09-27**, though P53 had a macOS action
# file; the first macOS sweep found `test.zsh P53` stopping at "Missing test
# script". Title copied from P53.swift's WindowGroup. No marker, for the reason
# test_P45.zsh gives.
#
# **這支腳本在 2026-09-27 之前不存在**,雖然 P53 有一份 macOS 動作檔;第一次 macOS sweep 發現
# `test.zsh P53` 停在「Missing test script」。標題照抄自 P53.swift 的 WindowGroup。不設 marker,
# 理由見 test_P45.zsh。
export TEST_TITLE="P53 toolbar"
export TEST_TARGET="mac"
exec zsh "$support_dir/test_common.zsh" "$@"
