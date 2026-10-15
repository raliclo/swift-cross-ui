#!/bin/zsh
# Capture frames WHILE a test runs, from outside it: the iOS Simulator through
# `simctl io screenshot`, or the whole Mac screen through `screencapture`.
#
#   zsh testapp/test_support/measure/frames_during.zsh OUTDIR COUNT WAIT_FOR LOG SOURCE -- COMMAND...
#
#   OUTDIR    where f01.png, f02.png, ... go (emptied first)
#   COUNT     how many frames
#   WAIT_FOR  a fixed string; capturing starts once LOG contains it
#   LOG       the file COMMAND's output goes to
#   SOURCE    a simulator UDID, or "mac" for the whole screen (0.4 s apart)
#
# Written 2026-10-15 for P88: a test runner captures only at the end, so a
# state that lasts only while a finger is held -- the panel orange during a
# long-press hover -- never reached a capture. On the iPhone 17 simulator, 30
# simctl frames during a 3 s XCUITest press showed the panel orange in frames
# 10-18 and blue before and after; on GtkBackend on macOS, 30 screen frames
# showed it orange in 21-28. Measure the frames with colour_bbox.swift.
#
# 在測試執行「期間」由外部擷取畫面:iOS 模擬器用 `simctl io screenshot`,整個 Mac 螢幕用 `screencapture`。
# 2026-10-15 為 P88 而寫：測試執行器只在最後擷圖，所以只在手指按住時才存在的狀態——長按 hover 時面板變橘色——
# 從來拍不到。在 iPhone 17 模擬器上，XCUITest 按住 3 秒期間的 30 張 simctl 畫面中，第 10–18 張面板是橘色，
# 前後都是藍色;macOS 上的 GtkBackend,30 張螢幕畫面中第 21–28 張是橘色。畫面用 colour_bbox.swift 量。

emulate -L zsh
setopt pipe_fail
(( $# >= 7 )) && [[ $6 == -- ]] || { print -u2 "usage: ${0:t} OUTDIR COUNT WAIT_FOR LOG SOURCE -- COMMAND..."; exit 2 }
out=$1 count=$2 wait_for=$3 log=$4 source=$5
shift 6
rm -rf $out && mkdir -p $out
: > $log
"$@" > $log 2>&1 &
runner=$!
# Wait for the marker, at most two minutes. / 等標記出現，最多兩分鐘。
for i in {1..600}; do
    grep -a -q -F -- "$wait_for" $log && break
    kill -0 $runner 2>/dev/null || break
    sleep 0.2
done
for i in {1..$count}; do
    frame=$out/f${(l:2::0:)i}.png
    if [[ $source == mac ]]; then
        screencapture -x $frame
        sleep 0.4
    else
        xcrun simctl io $source screenshot $frame >/dev/null 2>&1
    fi
done
wait $runner
print -r -- "$out: $count frames; the command exited $?"
