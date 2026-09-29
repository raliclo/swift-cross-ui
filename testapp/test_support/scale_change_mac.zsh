#!/bin/zsh
# Drives P42 on macOS through a real display-scale change: 1x -> 2x -> 1x.
#
# No synthesised input changes a display's scale, and this Mac's screen has one
# 1x mode, so the change comes from vdisplay.m: a HiDPI CGVirtualDisplay (the
# mechanism DeskPad and BetterDisplay use). On this machine -- whose screen is
# itself a headless virtual display -- creating it makes it the ONLY active
# display, so every window moves to 2x, and back when the tool exits. That is
# what a person sees moving a window to a Retina display and back.
#
# It changes the WHOLE screen, so it runs only while the harness holds
# testapp/.ui-lock (test-p42).
#
# Pass (measured 2026-09-30): "scale factor -> 1.0 (change 1)", "-> 2.0 (change
# 2)", "-> 1.0 (change 3)". The control run with no switch logs change 1 only.
#
# 讓 P42 在 macOS 上經歷一次真正的顯示器縮放變更:1x -> 2x -> 1x。沒有任何合成輸入能改變顯示器縮放,
# 本機螢幕也只有一個 1x 模式,所以改變來自 vdisplay.m:一個 HiDPI 的 CGVirtualDisplay。在本機——其螢幕
# 本身就是無頭的虛擬顯示器——建立它會使它成為**唯一**的作用中顯示器,所有視窗移到 2x,工具結束時再移回。
# 它會改變**整個**螢幕,因此只在 harness 持有 testapp/.ui-lock(test-p42)期間執行。
set -euo pipefail
here="${0:a:h}"
testapp="${here:h}"
work="${TMPDIR:-/tmp}/scui-vdisplay"
mkdir -p "$work"
clang -fobjc-arc -framework Foundation -framework CoreGraphics \
    -o "$work/vdisplay" "$here/vdisplay.m"
log="$testapp/output/p42-scale-change.log"
zsh "$testapp/test.zsh" P42 --macos --showtime 30 > "$log" 2>&1 &
harness=$!
for _ in {1..240}; do
    grep -q "RENDER COMPLETE" "$log" && break
    sleep 0.5
done
sleep 2
print "==> screen to 2x for 8 s"
"$work/vdisplay" 8
print "==> screen back to 1x"
wait $harness
# In change order: the lines arrive interleaved, and the counter is the order.
grep "scale factor ->" "$log" | sed -E 's/.*\(change ([0-9]+)\).*/\1 &/' | sort -n | cut -d' ' -f2-
