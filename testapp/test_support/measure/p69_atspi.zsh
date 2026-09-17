#!/usr/bin/env zsh
# Reads P69's accessibility tree through the EXTERNAL AT-SPI bus (Linux/WSLg),
# which is what a screen reader sees -- not P69's own in-process readback.
#
#   cd ~/proj/swift-cross-ui/testapp/output
#   dbus-run-session -- zsh ../test_support/measure/p69_atspi.zsh "$PWD/P69"
#   zsh testapp/test_support/measure/p69_atspi.zsh --help
#
# Needs python3-pyatspi. Launches the app, waits 30 s for its tree to settle,
# then runs p69_atspi.py against that process ID. The ID and not the window
# title, because an AT-SPI desktop lists every accessible app and titles repeat.
# Exit 0 only if every check in p69_atspi.py passes; the JSON tree is printed
# either way, so a failure can be read rather than re-run.
#
# 透過**外部** AT-SPI bus(Linux/WSLg)讀取 P69 的無障礙樹——也就是螢幕閱讀器看到的東西——而非 P69
# 自己在行程內的讀回。需要 python3-pyatspi。啟動 app、等 30 秒讓樹穩定,再以該行程 ID 執行
# p69_atspi.py。用行程 ID 而非視窗標題,因為 AT-SPI desktop 會列出每一支無障礙 app,標題會重複。
# 只有 p69_atspi.py 的每項檢查都通過才以 0 結束;JSON 樹無論成敗都會印出,失敗時讀得到原因、不必重跑。
set -euo pipefail

script_path="${0:A}"

# Before anything runs: this used to launch its first argument unconditionally,
# so `--help` was executed as the app path.
# 在執行任何東西之前:本腳本原本會無條件啟動第一個參數,於是 `--help` 被當成 app 路徑執行。
if [[ $# -eq 0 || "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    sed -n '2,18p' "$script_path" | sed 's/^# \{0,1\}//'
    exit 0
fi

app="$1"
probe="${script_path:h}/p69_atspi.py"
export GTK_A11Y=atspi
"$app" --debug &
app_pid=$!
trap 'kill "$app_pid" 2>/dev/null || true; wait "$app_pid" 2>/dev/null || true' EXIT
sleep 30
kill -0 "$app_pid"
python3 "$probe" "$app_pid"
