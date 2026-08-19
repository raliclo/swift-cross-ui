#!/usr/bin/env zsh
# P6-v2 under the standard test flow.
#
#   zsh testapp/test.zsh P6-v2
#
# P6-v2 是 P6 的 GTK 對照組：同樣的速度／幀率／解析度語彙與掉幀計算方式，但不含 D3D11。
# 它存在的目的是讓兩個 backend 的數字可以並排比較。
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P6-v2"
export TEST_TITLE="P6-v2 GTK playback"
export TEST_LOG_NAME="p6-v2-debug-events.log"

# P6-v2 writes RENDER COMPLETE from onAppear, unlike P6, which predates that
# convention and needs an alternation over two platform-specific lines. Writing
# the marker was the cheaper choice for a new app: the framework then waits for a
# statement the app makes about itself rather than for a side effect that has to
# be re-derived whenever the rendering path changes.
# P6-v2 於 onAppear 寫出 RENDER COMPLETE，這點與 P6 不同——P6 早於此慣例，必須以
# alternation 比對兩行平台專屬訊息。對一支新 app 而言，直接寫出 marker 是較省事的選擇：
# 框架等待的是 app 對自身狀態的陳述，而非某個每當繪製路徑變動就得重新推導的副作用。
export TEST_MARKER="RENDER COMPLETE"

# -seconds bounds the run, which matters more here than in other Pn apps: this
# one is a measurement and an unbounded sample length makes two runs
# incomparable. -autoplay removes the click, so the framework does not have to
# drive the UI to get a number.
#
# No -cpu or -gpu, so the default auto path runs and the summary records which
# decoder it actually got. Pinning a mode here would hide a fallback.
#
# -i is not passed. P6-v2 reports "Pass -i <file>" and renders its window, so
# the marker still appears and the framework's launch check stays valid on a
# machine with no media file. A run that measures anything needs -i, which is
# what measure_p6v2 does; this wrapper checks that the app comes up.
#
# -seconds 限定執行長度，這在此比其他 Pn app 更重要：本 app 是一項量測，而未設限的取樣
# 長度會使兩次執行無從比較。-autoplay 省去點擊，使框架無需驅動 UI 即可取得數字。
#
# 不傳 -cpu 或 -gpu，因此會走預設的 auto 路徑，並由摘要記錄實際取得的解碼器。在此釘死某個
# 模式會掩蓋回退行為。
#
# 不傳 -i。P6-v2 會顯示「Pass -i <file>」並繪製視窗，因此 marker 仍會出現，框架的啟動檢查
# 在沒有媒體檔的機器上依然有效。真正要量測的執行需要 -i，那由 measure_p6v2 負責；本 wrapper
# 檢查的是 app 能否正常啟動。
export TEST_APP_ARGS="-autoplay -seconds 12 --debug"

# `SUMMARY` carries the whole measurement in one line; `hwaccels reported` and
# `fell back` explain a decode path that is not the expected one, which is the
# question asked most often when two runs disagree.
# `SUMMARY` 以單行承載整份量測結果；`hwaccels reported` 與 `fell back` 則說明解碼路徑為何
# 不是預期的那一個——當兩次執行結果不一致時，這正是最常被問到的問題。
export TEST_SUMMARY_PATTERN="SUMMARY|hwaccels reported|fell back|start speed|backend "

export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
