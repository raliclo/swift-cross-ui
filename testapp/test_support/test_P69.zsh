#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P69"
export TEST_TITLE="P69 accessibility modifiers"
export TEST_LOG_NAME="p69-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
# `/h.`, not `/h'`: the pattern goes into a single-quoted `zsh -lc` for WSL, and a bare quote
# there left it unbalanced -- every WSL run printed `zsh:1: unmatched '` and no summary (2026-10-20).
# The dot still matches the quote that opens each hint in P69's log.
# 用 `/h.` 而非 `/h'`:這個樣式會被放進送往 WSL 的單引號 `zsh -lc`,裸露的引號會讓它不成對——每次 WSL 執行都印出
# `zsh:1: unmatched '` 而沒有摘要(2026-10-20)。點號仍比對得到 P69 紀錄中每個提示開頭的引號。
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|ACCESSIBILITY READ|HIDDEN|/h.|backend"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
