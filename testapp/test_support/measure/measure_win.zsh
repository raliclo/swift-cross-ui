#!/usr/bin/env zsh
# measure_win.zsh -- launch a built Windows Pn and list every UIA element's
# centre relative to the window frame: the numbers an `origin=frame` action file
# row wants. The app is closed again afterwards unless MEASURE_KEEP=1.
#
#   zsh testapp/test_support/measure/measure_win.zsh P83            WinUI build
#   zsh testapp/test_support/measure/measure_win.zsh P83 gtk4       GTK build
#   MEASURE_WAIT=8 zsh .../measure_win.zsh P72                      slower start
#   zsh testapp/test_support/measure/measure_win.zsh --help
#
# measure_win.zsh -- 啟動一個已建置的 Windows 版 Pn,列出每個 UIA 元素相對於視窗框的中心點：也就是
# `origin=frame` 動作檔列要的數字。除非 MEASURE_KEEP=1,結束後會關閉 app。
#
# It does not build the app (compile.zsh does that) and sends no input. The
# window is found by the app name in its title, which every Pn starts with.
# A GTK build exposes nothing to UIA on Windows -- gvsbuild's GTK has no
# AccessKit -- so for gtk4 only the window line comes back; measure under WSLg
# with AT-SPI instead.
# 本腳本不建置 app(那是 compile.zsh 的事),也不送任何輸入。以標題中的 app 名稱找視窗，每個 Pn 的標題
# 都以它開頭。Windows 上的 GTK 建置不提供任何東西給 UIA——gvsbuild 的 GTK 沒有 AccessKit——所以 gtk4
# 只會得到視窗那一行；請改在 WSLg 下以 AT-SPI 量測。
set -uo pipefail
script_path="${0:A}"
if [[ "${1:-}" == --help || -z "${1:-}" ]]; then
    sed -n '2,22p' "$script_path" | sed 's/^# \{0,1\}//'
    exit 0
fi
app="$1"
backend="${2:-WinUI}"
measure_dir="${script_path:h}"
testapp_dir="${measure_dir:h:h}"
exe="$testapp_dir/output/$app-$backend.exe"
tool="$testapp_dir/helper/bin/uia_rects.exe"
if [ ! -x "$tool" ] || [ "$measure_dir/uia_rects.c" -nt "$tool" ]; then
    mkdir -p "${tool:h}"
    clang -O1 -municode "$measure_dir/uia_rects.c" -o "$tool" \
        -lole32 -loleaut32 -luser32 -luuid || { printf 'uia_rects build failed\n' >&2; exit 1; }
fi
if [ ! -x "$exe" ]; then
    printf 'no %s -- build it first: zsh testapp/compile.zsh %s%s\n' "${exe:t}" \
        "$( [ "$backend" = gtk4 ] && printf -- '-gtk4 ' )" "$app" >&2
    exit 1
fi
taskkill -f -im "${exe:t}" >/dev/null 2>&1 || true
( cd "${exe:h}" && "./${exe:t}" >/dev/null 2>&1 & )
sleep "${MEASURE_WAIT:-6}"
"$tool" "${MEASURE_TITLE:-$app}" | grep -a -v -E "pane '|Non Client|title bar|'System'|Minimize|Maximize|size=0x0|menu bar ''"
rc=${pipestatus[1]}
if [ "${MEASURE_KEEP:-0}" != 1 ]; then
    taskkill -f -im "${exe:t}" >/dev/null 2>&1 || true
fi
exit "$rc"
