#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P114"
# The window title follows .navigationTitle on both Windows backends, as on macOS:
# "Home" at the root, "Fruits" after a push, and so on. The scene title
# "P114 back button label" never appears, so every capture by it failed and the
# run exited 7 (2026-11-07). The 1 s capture is taken at the root; the final one
# is of the desktop, because each action file ends on a different screen.
# 兩個 Windows backend 的視窗標題都跟著 .navigationTitle 走，與 macOS 相同：根畫面是「Home」，
# push 之後是「Fruits」，依此類推。場景標題「P114 back button label」從不出現，因此依它擷取的每張
# 截圖都失敗，執行以 7 結束(2026-11-07)。1 秒截圖拍的是根畫面；最後一張拍桌面，因為每個動作檔
# 結束時停在不同的畫面。
export TEST_TITLE="Home"
export TEST_FINAL_CAPTURE=desktop
export TEST_LOG_NAME="p114-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|path ->"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
