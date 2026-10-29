#!/usr/bin/env zsh
# P114 on Android, from outside the app: the back gesture pops the NavigationStack, and Back
# at the root still leaves the app as it did before NavigationStack took Back.
#
# actions/android/P114-native-back.actions covers the Back key (`key back`) inside the app. This
# covers what an action file cannot: the back gesture, as an edge swipe through `adb shell input
# swipe` (the same swipe p113_back_android.zsh uses), and Back once every stack is at its root,
# after which P114's activity -- the launcher activity, which Android 12 and later move to the
# back rather than finish -- must no longer be the top resumed activity.
#
# Needs P114 installed (zsh testapp/test.zsh P114 --android) and the emulator running.
# Pass: every line PASS, exit 0.
#
# P114 在 Android 上，從 app 外部檢查：返回手勢彈出 NavigationStack,而所有堆疊都在根層時的返回仍像 NavigationStack
# 接手返回之前那樣離開 app。actions/android/P114-native-back.actions 涵蓋 app 內的返回鍵(`key back`);本腳本涵蓋動作檔
# 做不到的：以 `adb shell input swipe` 做出的邊緣滑動返回手勢(與 p113_back_android.zsh 相同),以及根層的返回——之後
# P114 的 activity(launcher activity,Android 12 以後會被移到背景而非結束)不可再是最上層的 resumed activity。
# 需要已安裝 P114(zsh testapp/test.zsh P114 --android)且 emulator 正在執行。通過條件：每一行都是 PASS,結束碼 0。

set -uo pipefail

adb="${ANDROID_HOME:-/Volumes/Windows/proj_Win/.android-sdk}/platform-tools/adb"
pkg=dev.swiftcrossui.testapp.p114
actions="${0:A:h}/../actions/android/P114-push-and-wait.actions"
failures=0

top() { "$adb" shell dumpsys activity activities | sed -n 's/.*topResumedActivity=ActivityRecord{[0-9a-f]* u0 \([^ ]*\) .*/\1/p' | head -n 1; }
depths() { "$adb" logcat -d -s Swift:I | grep -a -o 'path -> depth [0-9]*' | grep -a -o '[0-9]*$' | tr '\n' ' '; }
pass() { print "PASS $1"; }
fail() { print "FAIL $1"; failures=$((failures + 1)); }
gesture() { "$adb" shell input swipe 2 1200 500 1200 250; sleep 1.5; }

"$adb" shell am force-stop "$pkg"
"$adb" push "$actions" /data/local/tmp/P114-wait.actions >/dev/null
"$adb" logcat -c
"$adb" shell am start -W -n "$pkg/dev.swiftcrossui.testapp.MainActivity" \
    --es scui_args "'--debug -actionfile /data/local/tmp/P114-wait.actions'" >/dev/null

# Wait for the two pushes. 等兩次推入完成。
for i in {1..30}; do
    [[ "$(depths)" == "1 2 " ]] && break
    sleep 1
done
[[ "$(depths)" == "1 2 " ]] && pass "pushed to depth 2 (depths: $(depths))" || fail "pushes (depths: $(depths))"

gesture
[[ "$(depths)" == "1 2 1 " ]] && pass "back gesture popped to depth 1 (depths: $(depths))" || fail "first back gesture (depths: $(depths))"
gesture
[[ "$(depths)" == "1 2 1 0 " ]] && pass "back gesture popped to depth 0 (depths: $(depths))" || fail "second back gesture (depths: $(depths))"

now="$(top)"
[[ "$now" == "$pkg/"* ]] && pass "still in front at the root (top: $now)" || fail "in front at the root (top: $now)"
"$adb" shell input keyevent KEYCODE_BACK; sleep 2
now="$(top)"
[[ "$now" != "$pkg/"* ]] && pass "Back at the root left the app (top: $now)" || fail "Back at the root (top: $now)"
[[ "$(depths)" == "1 2 1 0 " ]] && pass "no pop logged for Back at the root (depths: $(depths))" || fail "depths after Back at the root: $(depths)"

"$adb" logcat -d -s SCUI-BackNavigation:I | grep -a SCUI-BackNavigation
print "failures: $failures"
exit $(( failures > 0 ))
