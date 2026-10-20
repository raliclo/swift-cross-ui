#!/usr/bin/env zsh
# p78_send_urls_android.zsh -- P78's pass condition on Android: launch it with one URL, send a second
# while it is in front, and check logcat for "received 2", launch then running.
#
#   zsh testapp/test_support/p78_send_urls_android.zsh            the one device adb sees
#   zsh testapp/test_support/p78_send_urls_android.zsh SERIAL     a given device
#   zsh testapp/test_support/p78_send_urls_android.zsh --help
#
# Needs P78 installed (test_android.zsh P78). The two URLs come from different places on Android --
# the launch intent, and onNewIntent -- which is why both are sent. An action file has no action that
# opens a URL, so actions/android/P78-received-twice.actions only holds the window and points here.
# Exit 0 on a pass.
#
# P78 在 Android 上的通過條件：以一個 URL 啟動，app 在前景時再送第二個，檢查 logcat 有「received 2」,先 launch
# 後 running。需要已安裝 P78。兩個 URL 在 Android 上來自不同地方(啟動 intent 與 onNewIntent),所以兩個都送。
# action 檔沒有開啟 URL 的動作，因此 actions/android/P78-received-twice.actions 只讓視窗停留並指向這裡。通過時以 0 結束。
script_path="${0:A}"
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    sed -n '2,12p' "$script_path" | sed 's/^# \{0,1\}//'
    exit 0
fi
# The SDK test_android.zsh uses. / 與 test_android.zsh 相同的 SDK。
adb=("${ANDROID_HOME:-${ANDROID_SDK_ROOT:-${script_path:h:h:h:h}/.android-sdk}}/platform-tools/adb")
[[ -n "${1:-}" ]] && adb+=(-s "$1")
pkg=dev.swiftcrossui.testapp.p78
"${adb[@]}" shell am force-stop $pkg
"${adb[@]}" logcat -c
"${adb[@]}" shell am start -a android.intent.action.VIEW -d scui-testapp://launch --es scui_args --debug $pkg >/dev/null
perl -e 'select(undef,undef,undef,6)'
"${adb[@]}" shell am start -a android.intent.action.VIEW -d scui-testapp://running --es scui_args --debug $pkg >/dev/null
perl -e 'select(undef,undef,undef,3)'
got="$("${adb[@]}" logcat -d | grep -a '\[P78\] received ' | sed 's/.*received /received /' | tr -d '\r' | tr '\n' ';')"
if [[ "$got" == "received 1: scui-testapp://launch;received 2: scui-testapp://running;" ]]; then
    print -r -- "android: PASS -- $got"
    exit 0
fi
print -r -- "android: FAIL -- got \"${got:-nothing}\""
exit 1
