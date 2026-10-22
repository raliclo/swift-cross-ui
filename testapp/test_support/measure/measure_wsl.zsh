#!/usr/bin/env zsh
# measure_wsl.zsh -- launch a WSL-built Pn under WSLg and list its accessible
# elements with their centres in window coordinates, which ARE the numbers a
# WSL action file row takes (no origin column, xdotool's default).
#
#   zsh testapp/test_support/measure/measure_wsl.zsh P80
#   MEASURE_WAIT=12 zsh testapp/test_support/measure/measure_wsl.zsh P72
#   zsh testapp/test_support/measure/measure_wsl.zsh --help
#
# measure_wsl.zsh -- 在 WSLg 下啟動 WSL 建置的 Pn,列出其無障礙元素及視窗座標中心點，這些數字**就是**
# WSL 動作檔列要的數字(不填 origin 欄，即 xdotool 的預設)。
#
# The app is launched as test.zsh launched it for a replay before 2026-10-22 -- GDK_BACKEND=x11 --
# plus GTK_A11Y=atspi, and read with atspi_rects.py beside this script.
# Calibrated 2026-10-19 against actions/wsl/P80-cursor.actions, whose rows were
# verified by replay: hand 152,196 / cross 200,196 / text 244,196 measured, file
# says 152,196 / 199,196 / 244,196. It does not build: run
# `zsh testapp/compile.zsh Pn` inside WSL first (test.zsh --wsl does).
# app 的啟動方式與 test.zsh 重放時相同(GDK_BACKEND=x11),再加上 GTK_A11Y=atspi,並以同目錄的 atspi_rects.py
# 讀取。2026-10-19 以經重放驗證的 actions/wsl/P80-cursor.actions 校準：量到 hand 152,196 / cross 200,196 /
# text 244,196,檔案寫的是 152,196 / 199,196 / 244,196。本腳本不建置：請先在 WSL 內執行
# `zsh testapp/compile.zsh Pn`(test.zsh --wsl 會做)。
#
# Deliberately without GTK_CSD=1, which test.zsh adds since 2026-10-22. Under it GTK draws
# its title bar inside the window and every centre here would come out about 39 points
# lower; the replay adds that offset itself (ActionFileReplay.clientContentOffset), so the
# numbers a row takes are the ones measured without it.
# 刻意不加 GTK_CSD=1(test.zsh 自 2026-10-22 起會加)。加了之後 GTK 把標題列畫在視窗內，這裡的每個中心點都會低約 39 點；
# 重放會自己加上那個位移(ActionFileReplay.clientContentOffset),所以列要填的數字就是不加它時量到的。
set -uo pipefail
script_path="${0:A}"
if [[ "${1:-}" == --help || -z "${1:-}" ]]; then
    sed -n '2,24p' "$script_path" | sed 's/^# \{0,1\}//'
    exit 0
fi
app="$1"
wait_s="${MEASURE_WAIT:-8}"
# /mnt/c path of the probe: the WSL copy is synced without .py files.
# 探針用 /mnt/c 路徑：WSL 的複本同步時不含 .py 檔。
probe="/mnt/c${${script_path:h}#/c}/atspi_rects.py"
# Literal command text, no variables crossing wsl.exe except through \$ (see
# the user's CLAUDE.md: `$var` is eaten crossing Windows -> WSL).
# 跨越 wsl.exe 的指令內容除了以 \$ 寫出的之外不含變數(見使用者的 CLAUDE.md:`$var` 跨越 Windows -> WSL 會被吃掉)。
MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu --cd /home/lowei/proj/swift-cross-ui/testapp/output -- \
    bash -lc "test -x ./$app || { echo 'no ./$app in the WSL output -- build it in WSL first'; exit 1; }; pkill -x $app; sleep 0.5; GDK_BACKEND=x11 GTK_A11Y=atspi setsid ./$app >/dev/null 2>&1 & p=\\\$!; sleep $wait_s; python3 '$probe' \\\$p | grep -v 'no extents'; rc=\\\${PIPESTATUS[0]}; kill \\\$p; exit \\\$rc" \
    | tr -d '\r' | grep -v -E "^ *(panel|filler) '' "
