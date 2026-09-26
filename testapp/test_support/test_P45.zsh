#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P45"
# **This script did not exist until 2026-09-27**, though P45 had five macOS
# action files: `test.zsh P45` stopped at "Missing test script", so none of them
# could be run through the standard entry point, and the first macOS sweep
# found it. The title is the app's WindowGroup title, copied from P45.swift --
# a wrong one falls back to the whole screen and still produces a capture.
#
# No marker: P45 prints its RENDER COMPLETE line to stdout, and the marker wait
# reads only the debug-events log, so a marker here would wait for a line that
# never arrives there. With an action file, test_common waits for the replay to
# finish instead.
#
# **這支腳本在 2026-09-27 之前不存在**,雖然 P45 有五份 macOS 動作檔:`test.zsh P45` 會停在
# 「Missing test script」,因此它們沒有一份能透過標準入口執行,而第一次 macOS sweep 發現了這件事。
# 標題是這支 app 的 WindowGroup 標題,照抄自 P45.swift——寫錯的標題會退回整個螢幕,而且照樣產出一張擷圖。
#
# 不設 marker:P45 把它的 RENDER COMPLETE 印到 stdout,而 marker 等待只讀 debug-events log,
# 因此在此設 marker 會等一行永遠不會出現在那裡的字。有動作檔時,test_common 改為等重放結束。
export TEST_TITLE="P45 computed bindings"
export TEST_TARGET="mac"
exec zsh "$support_dir/test_common.zsh" "$@"
