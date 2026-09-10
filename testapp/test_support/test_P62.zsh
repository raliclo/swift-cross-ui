#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P62"
# The window title comes from the DOCUMENT, not from the scene, so it is
# "Untitled" for a new document rather than anything naming P62. Matching on
# that is what lets the harness capture the window rather than the whole screen.
# 視窗標題來自**文件**、而非 scene，因此新文件的標題是「Untitled」，不是任何含有 P62 的字串。
# 以它比對，才能讓 harness 擷取到那個視窗，而不是整個螢幕。
export TEST_TITLE="Untitled"
export TEST_LOG_NAME="p62-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|backend|window |text is now"
export TEST_TARGET="mac"
exec zsh "$support_dir/test_common.zsh" "$@"
