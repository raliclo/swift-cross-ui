#!/bin/zsh
# Capture test apps at rest on the iPhone simulator (UIKitBackend) and the Android emulator
# (AndroidBackend), for the iOS / Android pairs deck (build_ios_android_deck.zsh).
#
#   zsh testapp/test_support/pairs_deck/capture_mobile.zsh P113 P114   # only those
#   zsh testapp/test_support/pairs_deck/capture_mobile.zsh             # every testapp/P*.swift
#
# Runs `test.zsh Pn --ios --showtime 3` and `test.zsh Pn --android --showtime 3` with no action
# file, and appends one record per run to testapp/output/ios-android-pairs.csv2
# (utc,app,platform,exit,image). A run that leaves no -final- screenshot is recorded with an
# empty image. Logs go to testapp/output/ios-android-pairs-logs/. ANDROID_NO_BUILD=1 reuses
# .androidApk/Pn.apk and IOS_NO_BUILD=1 reuses output/Pn-ios.app instead of building. Each run
# takes the platform lock that test_ios.zsh and test_android.zsh take, so SoftPCB can use the
# simulator or the emulator between two runs.
#
# 在 iPhone 模擬器(UIKitBackend)與 Android 模擬器(AndroidBackend)上擷取測試 app 靜止時的畫面，給 iOS / Android
# 對照簡報(build_ios_android_deck.zsh)使用。以 `test.zsh Pn --ios --showtime 3` 與 `test.zsh Pn --android
# --showtime 3` 執行，不帶動作檔，每次執行在 testapp/output/ios-android-pairs.csv2 加一筆(utc,app,platform,exit,image)。
# 沒有留下 -final- 截圖的執行，影像欄留空。log 在 testapp/output/ios-android-pairs-logs/。ANDROID_NO_BUILD=1 沿用
# .androidApk/Pn.apk,IOS_NO_BUILD=1 沿用 output/Pn-ios.app,不重新建置。每次執行都取用 test_ios.zsh 與 test_android.zsh
# 取用的平台鎖，所以兩次執行之間 SoftPCB 可以使用模擬器。

emulate -L zsh
setopt pipe_fail
repo=${0:A:h:h:h:h}
source $repo/testapp/test_support/csv2_rows.zsh
out=$repo/testapp/output/ios-android-pairs.csv2
logs=$repo/testapp/output/ios-android-pairs-logs
mkdir -p $logs
[[ -s $out ]] || csv2_new $out 'utc,app,platform,exit,image' 'UTC 時間,app,平台,結束狀態,影像'
apps=("$@")
if (( ! $#apps )); then
    apps=(${${(f)"$(ls $repo/testapp/P*.swift)"}:t:r})
    apps=(${(on)apps})
fi
for app in $apps; do
    for platform in ios android; do
        log=$logs/$app-$platform.log
        flags=(--$platform --showtime 3)
        [[ $platform == ios && ${IOS_NO_BUILD:-0} == 1 ]] && flags+=(--no-build)
        [[ $platform == android && ${ANDROID_NO_BUILD:-0} == 1 ]] && flags+=(--no-build)
        zsh $repo/testapp/test.zsh $app $flags > $log 2>&1
        rc=$?
        # test_ios.zsh and test_android.zsh print the file name only: "==> Screenshot: pN-ios-final-STAMP.png".
        # test_ios.zsh 與 test_android.zsh 只印檔名:「==> Screenshot: pN-ios-final-STAMP.png」。
        shot=$(grep -a -o 'Screenshot: [^ ]*-final-[0-9-]*\.png' $log | tail -1)
        image=${shot:+testapp/output/screenshots/${shot#Screenshot: }}
        csv2_append $out "$(date -u +%Y-%m-%dT%H:%M:%SZ)" $app $platform $rc "$image"
        print -r -- "$app $platform exit $rc ${image:t}"
    done
done
