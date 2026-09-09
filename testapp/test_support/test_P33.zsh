#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P33"
# ~~"P33 missing views"~~ -- renamed 2026-09-09 in the same edit as P33.swift's
# WindowGroup, because screenshot.zsh -w finds the window by this string.
#
# ~~"a mismatch does not fail, it makes wincap find nothing and the script fall
# back to a DESKTOP capture, which succeeds while photographing whatever is in
# front of the window"~~ -- THAT WAS WRITTEN IN THIS SAME EDIT AND IT IS FALSE.
# It was a plausible claim about a tool's behaviour, asserted without reading
# the tool, inside a change whose entire subject was claims that outlived what
# they described. screenshot.zsh line 722 is explicit: with -w it captures the
# window and does NOT fall back. MEASURED 2026-09-09, app confirmed running
# first (PID in tasklist) so the test was not vacuous:
#
#   -w "P33 hand-built approximations"  -> captured from priority 1: wincap
#   -w "P33 missing views"              -> "!! No desktop fallback was used"
#
# So a mismatch fails LOUDLY and exits non-zero. Keeping both strings in step is
# still required -- a loud failure in a sweep is still a stopped sweep -- but
# the reason is not the one written above.
#
# ~~「P33 missing views」~~——2026-09-09 與 P33.swift 的 WindowGroup 在同一次編輯中改名，因為
# screenshot.zsh -w 是靠這個字串找到視窗的。
#
# ~~「兩者不一致不會失敗，只會讓 wincap 找不到東西，於是腳本退回**桌面**擷取——那會成功，卻拍下當時
# 擋在視窗前面的任何東西。」~~——**那句話就寫在這同一次編輯裡，而它是假的。** 它是一項關於某個工具行為
# 的合理臆測，在沒有讀那個工具的情況下被斷言，而它所身處的那次改動，主題正是「活得比事實更久的主張」。
# screenshot.zsh 第 722 行寫得很明白：指定 -w 時它擷取視窗本身，**不做** fallback。
# **2026-09-09 實測**，且先確認 app 確實在跑（tasklist 中有 PID），以免測試落空：
# 以新標題擷取 → `captured from priority 1: wincap`；以舊標題擷取 → `!! No desktop fallback was used`。
#
# 因此不一致會**大聲**失敗並以非零結束。兩個字串仍必須同步——在一次 sweep 中，大聲的失敗依然是一次被
# 中斷的 sweep——但理由不是上面那一個。
export TEST_TITLE="P33 hand-built approximations"
export TEST_LOG_NAME="p33-debug-events.log"
# TEST_MARKER is unaffected: the render line still begins "RENDER COMPLETE", it
# is only its tail that changed.
# TEST_MARKER 不受影響：那一行仍以「RENDER COMPLETE」開頭，改動的只是它的結尾。
export TEST_MARKER="RENDER COMPLETE"
# ~~`missing`~~ -> `approximations`. That alternative matched a log line the app
# stopped writing on 2026-09-04 and a render marker that stopped saying it on
# 2026-09-09. A dead alternative in an alternation is invisible: the other four
# still match, so the summary looks right and one of its five probes has simply
# stopped testing anything.
# ~~`missing`~~ 改為 `approximations`。該選項所比對的 log 行，app 早在 2026-09-04 就不再寫出，而
# render marker 也在 2026-09-09 不再那樣說。**一個交替式中失效的選項是看不見的**：其餘四個仍會命中，
# 於是摘要看起來完全正確，而它五個探針中的一個已經不再測試任何東西。
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|backend|approximations|Stepper|DisclosureGroup"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
