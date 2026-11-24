#!/usr/bin/env zsh
# P119 on a phone, for CI: zsh testapp/test_support/ci_p119_mobile.zsh --ios|--android
#
# P119 has no action file, so the sweeps never start it. It runs its own steps when
# launched with --sequence, and then has to do three things, all checked here: print
# the PASS verdict after all 20 cycles, end by itself, and end without a crash.
# Neither phone hands back an exit status worth reading, so the log is the evidence.
# The crash check is the one that matters: on Android P119 printed its verdict and
# then died of SIGABRT inside exit(), and test_android.zsh still returned 0 (2026-11-19).
# Set P119_CI_DEADLINE to change the 300 s limit on one run.
#
# 在手機上跑 P119，給 CI 用：zsh testapp/test_support/ci_p119_mobile.zsh --ios|--android
#
# P119 沒有動作檔，所以 sweep 不會啟動它。以 --sequence 啟動時它會自己跑完步驟，接著必須做到三件事，這裡全部檢查：
# 跑完 20 個循環後印出 SKIP 判定、自己結束、結束時沒有當掉。兩種手機都拿不到值得採信的結束碼，所以證據是記錄。
# 當機檢查最重要：P119 在 Android 上印出判定後，於 exit() 裡因 SIGABRT 而死，test_android.zsh 卻仍回傳 0
# (2026-11-19)。設 P119_CI_DEADLINE 可更改單次執行 300 秒的上限。
set -uo pipefail

testapp="${0:A:h:h}"
output="$testapp/output"
shots="$output/screenshots"
deadline="${P119_CI_DEADLINE:-300}"
verdict="P119 PASS: [0-9]+ backend containers recorded, 0 still alive off screen, 0 probes still attached, cycles 20"
mkdir -p "$shots"

fail() {
    print -u2 -r -- "!! P119 on $platform: $*"
    exit 1
}

check_ios() {
    local device="${IOS_SIM_DEVICE:-swift-cross-ui}"
    local bundle="dev.swiftcrossui.testapp.debugTarget"
    local log="$output/p119-ios-sequence.log"
    local marker="$output/p119-ios-sequence.marker"

    zsh "$testapp/test_ios.zsh" P119 --no-showtime || fail "build or install failed"
    touch "$marker"

    # simctl stays until the app ends, so its leaving is the app's leaving.
    # simctl 會留到 app 結束，所以它離開就代表 app 結束。
    xcrun simctl launch --console-pty --terminate-running-process \
        "$device" "$bundle" --sequence > "$log" 2>&1 < /dev/null &
    local launcher=$!
    sleep 4
    xcrun simctl io "$device" screenshot "$shots/p119-ios-sequence.png" || fail "no screenshot"

    SECONDS=0
    while kill -0 "$launcher" 2>/dev/null; do
        if [ "$SECONDS" -ge "$deadline" ]; then
            kill "$launcher" 2>/dev/null
            fail "still running after $deadline s"
        fi
        sleep 1
    done

    grep -aqE -- "$verdict" "$log" || fail "no verdict line in ${log:t}"
    if xcrun simctl spawn "$device" launchctl list | grep -qE "^[0-9]+[[:space:]].*UIKitApplication:$bundle"; then
        fail "the app did not end by itself"
    fi
    # The crash report appears seconds after the process dies, and simctl returns 0 after
    # a crash too, so an abort() passed until this waited for it (2026-11-19).
    # 當機報告在行程死後數秒才出現，而 simctl 在當機後同樣回傳 0，所以在加上這段等待之前，abort() 會判通過(2026-11-19)。
    local reports=()
    SECONDS=0
    while [ "$SECONDS" -lt 30 ]; do
        reports=(${(f)"$(find "$HOME/Library/Logs/DiagnosticReports" -name 'debugTarget*' -newer "$marker" 2>/dev/null)"})
        [ "${#reports}" -eq 0 ] || fail "crash report: ${reports[1]}"
        sleep 2
    done
}

check_android() {
    local android_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-${testapp:h:h}/.android-sdk}}"
    local adb="$android_root/platform-tools/adb"
    local serial="${ANDROID_SERIAL:-emulator-5554}"
    local package="dev.swiftcrossui.testapp.p119"
    # The kernel keeps the last 15 characters, and that is the name a native crash logs.
    # 核心只保留最後 15 個字元，原生當機記錄的就是這個名字。
    local process="${package[-15,-1]}"
    local log="$output/p119-android-sequence.log"
    [ -x "$adb" ] || fail "adb not found at $adb"

    zsh "$testapp/test_android.zsh" P119 --no-showtime || fail "build or install failed"
    "$adb" -s "$serial" shell am force-stop "$package"
    "$adb" -s "$serial" logcat -b all -c
    "$adb" -s "$serial" shell am start -W -n "$package/dev.swiftcrossui.testapp.MainActivity" \
        --es scui_args "'--sequence'" > /dev/null || fail "am start failed"
    sleep 4
    "$adb" -s "$serial" exec-out screencap -p > "$shots/p119-android-sequence.png" || fail "no screenshot"

    SECONDS=0
    # No -q: grep leaving early would SIGPIPE adb, and under pipefail the verdict would read as
    # missing (see check_expectation in test_common.zsh). / 不加 -q:grep 提早離開會讓 adb 收到 SIGPIPE,在 pipefail
    # 之下判定行就讀成不存在(見 test_common.zsh 的 check_expectation)。
    until "$adb" -s "$serial" logcat -d -s Swift:I | grep -aE -- "$verdict" > /dev/null; do
        [ "$SECONDS" -lt "$deadline" ] || fail "no verdict line after $deadline s"
        sleep 1
    done
    SECONDS=0
    while [ -n "$("$adb" -s "$serial" shell pidof "$package" | tr -d '\r')" ]; do
        [ "$SECONDS" -lt 30 ] || fail "the app did not end by itself"
        sleep 1
    done

    "$adb" -s "$serial" logcat -d -b main,system,crash > "$log"
    local crashes="$(grep -aE "Fatal signal [0-9]+.*\($process\)|Process: $package, PID|>>> $package <<<" "$log")"
    [ -z "$crashes" ] || fail "crashed while ending: $crashes"
    "$adb" -s "$serial" uninstall "$package" > /dev/null
}

case "${1:-}" in
    --ios) platform=iOS; check_ios ;;
    --android) platform=Android; check_android ;;
    *) print -u2 "usage: ci_p119_mobile.zsh --ios|--android"; exit 64 ;;
esac
print -r -- "P119 on $platform: PASS, every removed container released; ended by itself, no crash"
