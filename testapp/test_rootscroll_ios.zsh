#!/usr/bin/env zsh
# Check that the root view-mode control obeys the build and the flag.
#
# UIKitBackend hosts every window's content in a RootScrollHost and offers a
# floating actualView/rwdView button. That button is a test affordance, so:
#
#   debug build (SCUI_DEBUG=1)   shown by default
#   release build                hidden by default
#   release build + the flag     shown
#
# The flag is `-allow-rootscroll`, and it is read in release builds on purpose:
# a release build is exactly where rebuilding to see the control is not an
# option. See DebugFeatures.allowsRootScrollControl.
#
# This script builds the app twice -- the two builds differ only in SCUI_DEBUG
# -- and looks at the top-left corner of three screenshots. The corner is the
# button's default position, and the check is whether anything is drawn there:
# on a white page a bordered button is a large run of non-white pixels, and the
# apps this runs against have nothing else in that corner.
#
# 檢查根視圖的模式控制項是否遵守「建置」與「旗標」。
#
# UIKitBackend 把每個視窗的內容都放進 RootScrollHost，並提供一個浮動的 actualView/rwdView 按鈕。
# 該按鈕是測試用的輔助功能，因此：
#
#   debug 建置（SCUI_DEBUG=1）  預設顯示
#   release 建置                預設隱藏
#   release 建置 + 旗標          顯示
#
# 旗標為 `-allow-rootscroll`，而它在 release 建置中會被讀取乃是刻意的：release 建置恰恰是
# 「重新建置以看見該控制項」這條路走不通的那種建置。詳見 DebugFeatures.allowsRootScrollControl。
#
# 本腳本建置該 app 兩次——兩次建置的唯一差異是 SCUI_DEBUG——並檢視三張螢幕截圖的左上角。該角落是
# 按鈕的預設位置，而檢查的是「那裡有沒有畫東西」：在白色頁面上，一個有邊框的按鈕就是一大片非白色
# 像素，而本腳本所針對的 app 在該角落沒有其他東西。

set -euo pipefail

script_path="${0:a}"
script_dir="${script_path:h}"
target="${1:-P12}"
device_name="${IOS_SIM_DEVICE:-swift-cross-ui}"
bundle_id="dev.swiftcrossui.testapp.$target"
shots="$script_dir/output/screenshots"
scratch="${TMPDIR:-/tmp}/rootscroll-$target"

if [ ! -f "$script_dir/$target.swift" ]; then
    print -u2 "No such test app: $target (expected $script_dir/$target.swift)"
    exit 64
fi

mkdir -p "$shots" "$scratch"

# The corner the button is installed into: safe-area origin + 8pt, 92 x 28pt.
# In pixels on a 3x capture that is a box comfortably inside x 24..300,
# y 170..300. The margins are generous because the safe-area inset differs
# between devices and the check only needs to know whether anything is there.
# 按鈕被安裝到的那個角落：安全區域原點 + 8pt，尺寸 92 x 28pt。在 3x 擷取的像素座標下，
# 那是一個舒適地落在 x 24..300、y 170..300 之內的方框。邊界取得寬鬆，因為安全區域的內縮量
# 因裝置而異，而本檢查只需要知道「那裡有沒有東西」。
button_probe() {
    python3 - "$1" <<'PY'
import sys
from PIL import Image

image = Image.open(sys.argv[1]).convert("RGB")
corner = image.crop((24, 170, 300, 300))
# Anything meaningfully darker than the page. The button has a 1pt separator
# border and a label; the page behind it in these apps is white.
# 任何明顯比頁面暗的東西。該按鈕有 1pt 的分隔線邊框與一個標籤；在這些 app 中，其後方的頁面是白色。
dark = sum(1 for r, g, b in corner.getdata() if r < 200 and g < 200 and b < 200)
print(dark)
PY
}

report() {
    local label="$1" count="$2" expected="$3"
    if [ "$expected" = present ]; then
        if [ "$count" -gt 200 ]; then
            print "  PASS  $label -- button present ($count dark pixels)"
            return 0
        fi
        print "  FAIL  $label -- button missing ($count dark pixels, wanted > 200)"
        return 1
    else
        if [ "$count" -lt 200 ]; then
            print "  PASS  $label -- button absent ($count dark pixels)"
            return 0
        fi
        print "  FAIL  $label -- button present when it should not be ($count dark pixels)"
        return 1
    fi
}

capture() {
    local name="$1"
    shift
    xcrun simctl terminate "$device_name" "$bundle_id" >/dev/null 2>&1 || true
    xcrun simctl launch "$device_name" "$bundle_id" "$@" >/dev/null
    sleep 3
    # Written to the scratch directory first. `simctl io screenshot` cannot
    # write into this repository -- the volume refuses it with "Operation not
    # permitted" -- so the file is captured elsewhere and copied in.
    # 先寫進 scratch 目錄。`simctl io screenshot` 無法寫入本 repository——該磁碟區會以
    # 「Operation not permitted」拒絕——因此先擷取到別處，再複製進來。
    xcrun simctl io "$device_name" screenshot "$scratch/$name.png" >/dev/null 2>&1
    cp "$scratch/$name.png" "$shots/$target-rootscroll-$name.png"
    button_probe "$scratch/$name.png"
}

failures=0

print "==> release build (no SCUI_DEBUG)"
zsh "$script_dir/compile.zsh" -ios "$target" >/dev/null
xcrun simctl install "$device_name" "$script_dir/output/$target-ios.app" >/dev/null

report "release, no flag" "$(capture release-plain)" absent || failures=$((failures + 1))
report "release, -allow-rootscroll" "$(capture release-flag -allow-rootscroll)" present \
    || failures=$((failures + 1))

print "==> debug build (SCUI_DEBUG=1)"
SCUI_DEBUG=1 zsh "$script_dir/compile.zsh" -ios "$target" >/dev/null
xcrun simctl install "$device_name" "$script_dir/output/$target-ios.app" >/dev/null

report "debug, no flag" "$(capture debug-plain)" present || failures=$((failures + 1))

xcrun simctl terminate "$device_name" "$bundle_id" >/dev/null 2>&1 || true

print
print "Screenshots: $shots/$target-rootscroll-*.png"
if [ "$failures" -eq 0 ]; then
    print "All 3 checks passed."
else
    print "$failures of 3 checks failed."
fi
exit "$failures"
