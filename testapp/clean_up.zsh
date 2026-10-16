#!/bin/zsh
# clean_up.zsh -- remove built test apps that are cheap to build again: Android APKs by
# default, iOS app bundles on request, and optionally the copies installed in the emulator
# or simulators. testapp/cleanup.zsh is the other half (simulator logs, the AVD, caches);
# this one only touches what a test run builds per app.
#
#   zsh testapp/clean_up.zsh                    Android APKs not used for a day
#   zsh testapp/clean_up.zsh --all              every Android APK
#   zsh testapp/clean_up.zsh P62 P75            those apps' APKs, however recent
#   zsh testapp/clean_up.zsh --platform ios     iOS app bundles (testapp/output/Pn-ios.app)
#   zsh testapp/clean_up.zsh --platform all     both
#   zsh testapp/clean_up.zsh --days 3           "unused" means not used for 3 days
#   zsh testapp/clean_up.zsh --uninstall        also uninstall them from the emulator /
#                                               booted simulators
#   zsh testapp/clean_up.zsh --dry-run          list what would go and how much
#
# **Only what rebuilds in under a minute.** A platform is cleaned only if rebuilding one app
# was measured below 60 s; a later run that finds it slower should raise the number here,
# and the platform is then refused until --force. Measured 2026-10-16 with the compile cache
# warm (the cache is .build, which this never touches):
#   android  23 s  P62: compile 17 s, package 4 s, then install as usual
#   ios       9 s  P96: build and bundle, then install as usual
# A missing APK or bundle is rebuilt by test_android.zsh / test_ios.zsh on the next run of
# that app, so nothing needs rebuilding up front. A cold cache (after a toolchain change)
# takes about eleven minutes for the first app (testapp/build_time_android.md) whether or
# not this ran.
#
# "Unused" is the file's modification time: an app built or rebuilt within --days is kept.
#
# clean_up.zsh——移除重建成本低的測試 app:預設是 Android APK,指定時也清 iOS app bundle,並可選擇一併移除模擬器裡已
# 安裝的副本。testapp/cleanup.zsh 是另一半(模擬器 log、AVD、快取);本腳本只碰每次測試為各 app 建置的產物。
# **只清不到一分鐘就能重建的東西。** 只有實測重建一支 app 低於 60 秒的平台才會清;之後若量到更慢，要在這裡改數字，
# 該平台就會被拒絕，除非加 --force。2026-10-16 在編譯快取(.build,本腳本從不碰)有效時量得:android 23 秒(P62)、
# ios 9 秒(P96)。缺少的 APK 或 bundle 會在下次測該 app 時由 test_android.zsh / test_ios.zsh 自動重建，不需要事先
# 全部重建。「未使用」以檔案修改時間判斷：在 --days 天內建置過的 app 會保留。

emulate -L zsh
setopt err_exit pipe_fail no_unset

here=${0:A:h}
typeset -A REBUILD_SECONDS=(android 23 ios 9)
LIMIT=60

platform=android all=0 days=1 dry=0 uninstall=0 force=0
apps=()
while (( $# )); do
    case $1 in
        --platform) platform=${2:?--platform needs android, ios or all}; shift 2 ;;
        --all) all=1; shift ;;
        --days) days=${2:?--days needs a number}; shift 2 ;;
        --dry-run|-n) dry=1; shift ;;
        --uninstall) uninstall=1; shift ;;
        --force) force=1; shift ;;
        -h|--help) sed -n '2,15p' $0 | sed 's/^# \{0,1\}//'; exit 0 ;;
        P*) apps+=($1); shift ;;
        *) print -u2 -r -- "unknown option: $1 (see --help)"; exit 64 ;;
    esac
done
case $platform in
    android|ios) platforms=($platform) ;;
    all) platforms=(android ios) ;;
    *) print -u2 -r -- "--platform must be android, ios or all"; exit 64 ;;
esac

sdk=${ANDROID_HOME:-${here:h:h}/.android-sdk}
adb=$sdk/platform-tools/adb
freed=0

# The files to remove for one platform: chosen apps, or every app (--all), or those whose
# file is older than --days.
# 某個平台要刪的檔案：指定的 app、全部(--all),或檔案早於 --days 的那些。
candidates() {
    local kind=$1 file name
    local -a files
    case $kind in
        android) files=($here/.androidApk/*.apk(N)) ;;
        ios) files=($here/output/*-ios.app(N/)) ;;
    esac
    for file in $files; do
        name=${file:t}
        name=${name%.apk}
        name=${name%-ios.app}
        if (( $#apps )); then
            (( ${apps[(Ie)$name]} )) && print -r -- $file
        elif (( all )); then
            print -r -- $file
        elif [[ -n $(find $file -maxdepth 0 -mtime +$((days - 1)) 2>/dev/null) ]]; then
            print -r -- $file
        fi
    done
}

uninstall_app() {
    local kind=$1 name=$2
    case $kind in
        android)
            [[ -x $adb ]] || return 0
            local package="dev.swiftcrossui.testapp.${(L)name//-/_}"
            if $adb shell pm list packages 2>/dev/null | grep -qx "package:$package"; then
                (( dry )) && { print -r -- "   would uninstall $package"; return 0 }
                $adb uninstall $package >/dev/null 2>&1 && print -r -- "   uninstalled $package"
            fi
            ;;
        ios)
            # Every iOS test app is installed as the one debugTarget bundle; removed once.
            # 每支 iOS 測試 app 都以同一個 debugTarget bundle 安裝;只移除一次。
            [[ -n ${ios_uninstalled:-} ]] && return 0
            ios_uninstalled=1
            (( dry )) && { print -r -- "   would uninstall dev.swiftcrossui.testapp.debugTarget from booted simulators"; return 0 }
            xcrun simctl uninstall booted dev.swiftcrossui.testapp.debugTarget 2>/dev/null \
                && print -r -- "   uninstalled dev.swiftcrossui.testapp.debugTarget"
            ;;
    esac
}

for kind in $platforms; do
    seconds=${REBUILD_SECONDS[$kind]:-}
    if [[ -z $seconds ]] || (( seconds >= LIMIT )); then
        if (( ! force )); then
            print -u2 -r -- "!! $kind: rebuilding an app takes ${seconds:-an unmeasured time} s, not under $LIMIT s; skipped (--force to clean anyway)"
            continue
        fi
    fi
    files=(${(f)"$(candidates $kind)"})
    files=(${files:#})
    print -r -- "==> $kind: ${#files} to remove (rebuild about $seconds s each, on that app's next run)"
    for file in $files; do
        kb=$(du -sk $file | cut -f1)
        freed=$(( freed + kb ))
        name=${file:t}
        name=${name%.apk}
        name=${name%-ios.app}
        if (( dry )); then
            print -r -- "   would remove ${file#$here/} ($(( kb / 1024 )) MB)"
        else
            rm -rf $file
            print -r -- "   removed ${file#$here/} ($(( kb / 1024 )) MB)"
        fi
        (( uninstall )) && uninstall_app $kind $name
    done
done
print -r -- "==> $( (( dry )) && print would free || print freed ) $(( freed / 1024 )) MB"
