#!/bin/zsh
# P113's pass condition on Android: Back does not close a window that is not
# closable, and does once "closable" is turned on -- for the first window and
# for a second one. Run after `zsh testapp/test.zsh P113 --android` has
# installed the app; it relaunches it.
#
# A second check beside actions/android/P113-back.actions (its `key back`
# rows): this one sends the real system Back key from outside the process,
# `adb shell input keyevent KEYCODE_BACK`, and the back gesture as an edge
# swipe, which the action file does not cover. Both gave the same results
# (2026-10-28). Taps are pixels on the api36b AVD (1080 x 2400, density 2.625),
# read from a uiautomator dump of P113 on 2026-10-27.
#
# P113 在 Android 上的通過條件：不可關閉的視窗按返回不會關閉，打開「closable」後則會——第一個視窗與第二個視窗皆然。
# 在 `zsh testapp/test.zsh P113 --android` 裝好 app 之後執行；它會重新啟動 app。
#
# 這是 actions/android/P113-back.actions(`key back` 列)之外的第二道檢查：它從程序外以 `adb shell input keyevent
# KEYCODE_BACK` 送出真正的系統返回鍵，並以邊緣滑動送出返回手勢——動作檔不涵蓋手勢。兩者實測結果相同(2026-10-28)。
# 點擊座標是 api36b AVD(1080 x 2400,密度 2.625)上的像素，2026-10-27 讀自 P113 的 uiautomator dump。
set -uo pipefail

adb="${ANDROID_HOME:-/Volumes/Windows/proj_Win/.android-sdk}/platform-tools/adb"
pkg=dev.swiftcrossui.testapp.p113
failures=0

top() { "$adb" shell dumpsys activity activities | sed -n 's/.*topResumedActivity=ActivityRecord{[0-9a-f]* u0 \([^ ]*\) .*/\1/p' | head -n 1; }
check() {
    # $1 what, $2 expected substring of the top activity, or !substring for "not".
    local now="$(top)"
    if [[ "$2" == !* ]]; then
        [[ "$now" != *"${2#!}"* ]] && print "PASS $1 (top: $now)" || { print "FAIL $1 (top: $now)"; failures=$((failures + 1)); }
    else
        [[ "$now" == *"$2"* ]] && print "PASS $1 (top: $now)" || { print "FAIL $1 (top: $now)"; failures=$((failures + 1)); }
    fi
}
back() { "$adb" shell input keyevent KEYCODE_BACK; sleep 1.5; }
gesture() { "$adb" shell input swipe 2 1200 500 1200 250; sleep 1.5; }
tap() { "$adb" shell input tap "$1" "$2"; sleep 1.2; }

"$adb" shell am force-stop "$pkg"
"$adb" logcat -c
"$adb" shell am start -W -n "$pkg/dev.swiftcrossui.testapp.MainActivity" >/dev/null
sleep 5

check "launched" "$pkg/dev.swiftcrossui.testapp.MainActivity"
back
check "Back key, main window not closable: still in front" "$pkg/dev.swiftcrossui.testapp.MainActivity"
gesture
check "back gesture, main window not closable: still in front" "$pkg/dev.swiftcrossui.testapp.MainActivity"

# The second window, not closable and not resizable from the start.
# 第二個視窗，一開始就不可關閉、不可縮放。
tap 250 928
sleep 2
check "second window opened as the non-resizable activity" "$pkg/dev.swiftcrossui.androidbackend.ScuiFixedSizeWindowActivity"
back
check "Back key, second window not closable: still in front" "ScuiFixedSizeWindowActivity"
tap 820 385
back
check "Back key, second window closable: closed, main window in front" "$pkg/dev.swiftcrossui.testapp.MainActivity"

tap 820 385
back
check "Back key, main window closable: the app left the front" "!$pkg"

print -r -- "-- SCUI-WindowBehaviors log"
"$adb" logcat -d -s SCUI-WindowBehaviors | grep -v '^-' | sed 's/^/   /'
"$adb" shell am force-stop "$pkg"
print "failures: $failures"
(( failures == 0 ))
