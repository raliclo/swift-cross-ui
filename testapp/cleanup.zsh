#!/usr/bin/env zsh
# Free disk space left behind by the test harnesses -- emulator, simulators,
# build caches -- without touching anything a test needs to start.
#
#   zsh testapp/cleanup.zsh                 report only: what would go, and how much
#   zsh testapp/cleanup.zsh --apply         remove the regenerable items below
#   zsh testapp/cleanup.zsh --apply --erase-sims
#                                           also erase every iOS simulator (all its
#                                           apps and settings) -- see below
#   zsh testapp/cleanup.zsh --apply --wipe-avd
#                                           also reset the Android AVD's user data
#   zsh testapp/cleanup.zsh --apply --deep  also SwiftPM / Gradle / Homebrew caches
#
# **Report first, by default.** Nothing is removed without --apply, and every
# line says the size it measured before it says what it did, so a run that
# freed less than expected shows which item it was.
#
# **Why the system disk.** On 2026-10-02 the system disk filled mid-sweep
# (ENOSPC) because the AVD's qcow2 overlay grows with every APK install; the
# AVD moved to /Volumes/Windows. On 2026-10-04 the disk was again down to
# 8.9 GB free, and what had grown was not the emulator but the two iOS
# simulators the sweeps use: 13 GB between them, of which ~3.9 GB was the
# simulators' own unified logs (data/var/db/diagnostics). Those logs are what
# the default run removes; the rest of a simulator's size (downloaded
# MobileAssets, wallpaper poster data) only goes with --erase-sims.
#
# **What it never removes:** anything under testapp/output (captures are the
# evidence of past runs), an AVD that is not this harness's, or a simulator
# that is booted -- deleting a running simulator's log store under its logd is
# a different kind of problem from a full disk. A booted one is listed and
# skipped; shut it down (`xcrun simctl shutdown all`) and run again.
#
# 釋放測試工具留下的磁碟空間——模擬器、建置快取——而不碰任何測試啟動所需的東西。預設只回報，不加 --apply
# 不刪任何東西。2026-10-04 系統碟只剩 8.9 GB,變大的不是 Android 模擬器而是 sweep 用的兩台 iOS 模擬器:
# 共 13 GB,其中約 3.9 GB 是模擬器自己的 unified log。預設清的就是那些 log;模擬器其餘的大小(下載的
# MobileAsset、桌布資料)只有 --erase-sims 才會清。永遠不清:testapp/output 底下的東西、不屬於本工具的
# AVD、以及正在開機中的模擬器。

set -euo pipefail

apply=0 erase_sims=0 wipe_avd=0 deep=0
for arg in "$@"; do
    case "$arg" in
        --apply) apply=1 ;;
        --erase-sims) erase_sims=1 ;;
        --wipe-avd) wipe_avd=1 ;;
        --deep) deep=1 ;;
        -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) print -u2 "unknown option: $arg"; exit 64 ;;
    esac
done

repo_root="${0:A:h:h}"
android_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-${repo_root:h}/.android-sdk}}"
adb="$android_root/platform-tools/adb"
sim_root="$HOME/Library/Developer/CoreSimulator/Devices"
user_cache="$(getconf DARWIN_USER_CACHE_DIR)"

freed_kb=0

kb() { [ -e "$1" ] && du -xsk "$1" 2>/dev/null | cut -f1 || print 0; }
human() { awk -v k="$1" 'BEGIN { if (k >= 1048576) printf "%.1f GB", k/1048576; else printf "%.0f MB", k/1024 }'; }

# Remove one path, after checking it is absolute, non-trivial and inside one of
# the roots this script is allowed to clean.
# 移除一個路徑，先確認它是絕對路徑、不是根目錄這類東西，且位於本腳本允許清理的範圍內。
remove() {
    local target="$1" label="$2" size
    case "$target" in
        "$sim_root"/?*|"$HOME"/Library/Developer/Xcode/DerivedData/?*|"$user_cache"?*|\
        "$HOME"/Library/Caches/org.swift.swiftpm/?*|"$HOME"/.gradle/caches/?*|/tmp/android-"$USER"/?*) ;;
        *) print -u2 "refusing to remove $target: outside the cleanable roots"; return 1 ;;
    esac
    [ -e "$target" ] || return 0
    size="$(kb "$target")"
    (( size >= 1024 )) || return 0
    if (( apply )); then
        rm -rf -- "$target"
        print "  removed  $(human $size)  $label"
        freed_kb=$(( freed_kb + size ))
    else
        print "  would remove  $(human $size)  $label"
        freed_kb=$(( freed_kb + size ))
    fi
}

print "==> Disk before"
df -h /System/Volumes/Data | tail -1
[ -d /Volumes/Windows ] && df -h /Volumes/Windows | tail -1

# ---------------------------------------------------------------- Android
print "\n==> Android emulator"
emulator_running=0
pgrep -f 'qemu-system.*-avd' >/dev/null && emulator_running=1

# The emulator leaves crashpad_handler and netsimd behind when it dies -- seen
# 2026-10-04 after /Volumes/Windows was unmounted under it. They hold nothing,
# but they keep the SDK volume busy.
# 模擬器死掉時會留下 crashpad_handler 與 netsimd——2026-10-04 /Volumes/Windows 在它底下被卸載後見過。
helpers=($(pgrep -f "$android_root/emulator/(crashpad_handler|netsimd)" || true))
if (( ! emulator_running && ${#helpers} )); then
    if (( apply )); then
        # TERM first; they ignored it on 2026-10-04 and the first version of
        # this line reported them stopped anyway. KILL what is left, then say
        # what is actually still running.
        # 先送 TERM;2026-10-04 它們忽略了 TERM,而這一行的第一版照樣回報「已停止」。剩下的送 KILL,
        # 再說出實際還在執行的東西。
        kill ${helpers[@]} 2>/dev/null || true
        sleep 2
        left=($(pgrep -f "$android_root/emulator/(crashpad_handler|netsimd)" || true))
        (( ${#left} )) && kill -9 ${left[@]} 2>/dev/null || true
        sleep 1
        left=($(pgrep -f "$android_root/emulator/(crashpad_handler|netsimd)" || true))
        if (( ${#left} )); then
            print "  could not stop ${#left} emulator helper process(es): ${left[*]}"
        else
            print "  stopped ${#helpers} helper process(es) left by an emulator that is gone"
        fi
    else
        print "  would stop ${#helpers} helper process(es) left by an emulator that is gone"
    fi
fi

# A crash database here makes every later boot wait on a consent dialog
# (sweep_android.zsh explains); it is never wanted.
for f in /tmp/android-"$USER"/emu-crash-*.db(N); do
    remove "$f" "emulator crash database ${f:t}"
done

avd_name="${ANDROID_AVD:-$("$android_root/emulator/emulator" -list-avds 2>/dev/null | head -n 1 || true)}"
if [ -n "$avd_name" ]; then
    avd_path="$(sed -n 's/^path=//p' "$HOME/.android/avd/$avd_name.ini" 2>/dev/null || true)"
    if [ -n "$avd_path" ] && [ -d "$avd_path" ]; then
        print "  AVD $avd_name: $(du -sh "$avd_path" | cut -f1) at $avd_path"
        if (( wipe_avd )); then
            if (( emulator_running )); then
                print "  --wipe-avd skipped: the emulator is running; stop it first"
            elif (( apply )); then
                size="$(kb "$avd_path")"
                # The emulator's own reset: userdata and cache go back to the
                # system image's, and test_android.zsh reinstalls each APK.
                "$android_root/emulator/emulator" -avd "$avd_name" -wipe-data -no-window \
                    -no-snapshot -no-boot-anim -no-metrics -gpu host >/dev/null 2>&1 &
                "$adb" wait-for-device
                for _ in {1..90}; do
                    [ "$("$adb" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && break
                    sleep 2
                done
                "$adb" emu kill >/dev/null 2>&1 || true
                sleep 5
                after="$(kb "$avd_path")"
                print "  wiped AVD user data: $(human $size) -> $(human $after)"
            else
                print "  would wipe the AVD's user data (-wipe-data)"
            fi
        fi
    fi
fi

# AVDs on the SDK volume that the emulator does not list are not this
# harness's to delete; say they are there and how big, and leave them.
# SDK 磁碟上、模擬器沒有列出的 AVD 不是本工具可以刪的；說出它們在哪、多大，然後留著。
avd_home="${repo_root:h}/.android-avd"
if [ -d "$avd_home" ]; then
    for d in "$avd_home"/*.avd(N/); do
        n="${d:t:r}"
        [ "$n" = "$avd_name" ] && continue
        [ -e "$HOME/.android/avd/$n.ini" ] && state="registered" || state="not registered in ~/.android/avd"
        print "  note: AVD $n ($state), $(du -sh "$d" | cut -f1) at $d -- not removed"
    done
fi

# ---------------------------------------------------------------- iOS simulators
print "\n==> iOS simulators"
if (( apply )); then
    xcrun simctl delete unavailable 2>/dev/null && print "  deleted unavailable simulators (if any)"
else
    n="$(xcrun simctl list devices unavailable 2>/dev/null | grep -c '(' || true)"
    print "  would delete $n unavailable simulator(s)"
fi

booted=($(xcrun simctl list devices booted 2>/dev/null | grep -oE '[0-9A-F-]{36}' || true))
for dev in "$sim_root"/*(N/); do
    id="${dev:t}"
    name="$(xcrun simctl list devices 2>/dev/null | grep -F "$id" | sed -E 's/^ *//; s/ \(.*//' | head -n 1)"
    print "  ${name:-unknown} ($id): $(du -xsh "$dev" | cut -f1)"
    if (( ${booted[(Ie)$id]} )); then
        print "    booted -- skipped; \`xcrun simctl shutdown all\` and run again"
        continue
    fi
    if (( erase_sims )); then
        size="$(kb "$dev")"
        if (( apply )); then
            xcrun simctl erase "$id"
            after="$(kb "$dev")"
            print "    erased: $(human $size) -> $(human $after)"
            freed_kb=$(( freed_kb + size - after ))
        else
            print "    would erase (all apps and settings)"
        fi
    else
        remove "$dev/data/var/db/diagnostics" "unified log of ${name:-$id}"
        remove "$dev/data/var/db/uuidtext" "log symbol table of ${name:-$id}"
        remove "$dev/data/Library/Logs/CrashReporter" "crash reports of ${name:-$id}"
        remove "$dev/data/tmp" "tmp of ${name:-$id}"
    fi
done

# ---------------------------------------------------------------- build caches
print "\n==> Build caches (rebuilt on the next build)"
# test_ios.zsh leaves one iOSActionFileRunner-<hash> here per run (hundreds by
# 2026-10-04), so they are summed into one line rather than listed.
# test_ios.zsh 每跑一次就在這裡留下一個 iOSActionFileRunner-<hash>(2026-10-04 時已有數百個),
# 因此合計成一行而不逐一列出。
derived=("$HOME"/Library/Developer/Xcode/DerivedData/*(N/))
if (( ${#derived} )); then
    size="$(du -xsk "${derived[@]}" 2>/dev/null | awk '{ s += $1 } END { print s + 0 }')"
    if (( apply )); then
        for d in "${derived[@]}"; do
            case "$d" in "$HOME"/Library/Developer/Xcode/DerivedData/?*) rm -rf -- "$d" ;; esac
        done
        print "  removed  $(human $size)  DerivedData (${#derived} folders)"
    else
        print "  would remove  $(human $size)  DerivedData (${#derived} folders)"
    fi
    freed_kb=$(( freed_kb + size ))
fi
remove "${user_cache}clang/ModuleCache" "clang module cache"
remove "${user_cache}com.apple.dt.InstrumentsCLI" "Instruments CLI cache"

if (( deep )); then
    print "\n==> Deep (downloaded again on the next build)"
    remove "$HOME/Library/Caches/org.swift.swiftpm/repositories" "SwiftPM repository cache"
    for d in "$HOME"/.gradle/caches/{build-cache-1,transforms-*,jars-*}(N/); do
        remove "$d" "Gradle ${d:t}"
    done
    if command -v brew >/dev/null; then
        if (( apply )); then
            brew cleanup -s >/dev/null 2>&1 && print "  brew cleanup -s done"
        else
            print "  would run brew cleanup -s ($(du -sh "$(brew --cache)" 2>/dev/null | cut -f1) cache)"
        fi
    fi
fi

print "\n==> $( (( apply )) && print Freed || print 'Would free' ) about $(human $freed_kb) (measured before removal)"
print "==> Disk after"
df -h /System/Volumes/Data | tail -1
(( apply )) || print "Report only. Run again with --apply to remove."
