#!/usr/bin/env zsh
# Build, bundle, install, and launch one SwiftCrossUI test app on an Android
# emulator. The APK cache is deliberately separate from source and build trees.
#
#   zsh testapp/test_android.zsh P12
#   zsh testapp/test_android.zsh P12 --no-build
#   zsh testapp/test_android.zsh P12 --actionfile actions/android/P12-android-smoke.csv
#
# Usually reached as `zsh testapp/test.zsh P12 --android`, which is the same
# command and the same flags as every other platform.
# 通常經由 `zsh testapp/test.zsh P12 --android` 抵達，該指令與旗標和其他平台完全相同。
#
# 在 Android emulator 上建置、打包、安裝並啟動一支 SwiftCrossUI 測試 app。APK 快取與原始碼及
# build tree 分開；預設會重新建置 APK，`-noApk` 才重用既有 APK。

set -euo pipefail

script_path="${0:a}"
script_dir="${script_path:h}"
repo_root="${script_dir:h}"
output_dir="$script_dir/output"
apk_dir="$script_dir/.androidApk"
app=""
do_apk=1
action_file=""
device_name="${ANDROID_AVD_NAME:-}"
showtime_seconds="${ANDROID_SHOWTIME_SECONDS:-0}"

usage() {
    cat <<EOF_USAGE
Usage: ${script_path:t} <Pn> [--no-build] [--actionfile [path]] [--showtime seconds|--no-showtime] [--device name|serial]

Usually reached as: zsh testapp/test.zsh <Pn> --android
That uses the same flags as every other platform.

Default: compile and bundle a fresh Android APK in RELEASE, then install and
launch it. `--debug-build` uses debug instead.

Release is the default because Android was the only platform here that was not:
compile.zsh has used release everywhere else all along, and the debug default
cost 28 MB per APK -- 154 against 126, measured on P43 2026-09-05 -- for an
optimisation setting nothing was reading. `SCUI_DEBUG` is a separate thing and
still works: it is a compilation condition, not a build configuration, so
action-file replay and `--debug` diagnostics are available in both. Verified in
release on P43: the gradients measure what they did in debug and the replay
still reports `replayed P43-actions.csv`.
--no-build: reuse testapp/.androidApk/<Pn>.apk and skip compile/bundle.
            Aliases: -noApk, --no-apk.
--actionfile: replay an Android action file after launch; without a path, use
         testapp/actions/android/<Pn>-*.csv when exactly one file exists.
         Aliases: -replay, --replay.
--no-showtime: return as soon as the app is up.
--device: use an existing adb serial; otherwise boot the selected AVD.
EOF_USAGE
}

die() { print -u2 -r -- "[error] $1"; exit 1; }

[ "$#" -gt 0 ] || { usage >&2; exit 64; }
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    usage
    exit 0
fi
app="${1:u}"
app_id="${app:l}"
shift
[[ "$app" == P<-> ]] || die "Invalid test target: $app"

while [ "$#" -gt 0 ]; do
    case "$1" in
        # `--no-build` and `--actionfile` are the spellings test.zsh uses for
        # every other platform, and they are what test_common.zsh hands over.
        # The original `-noApk` and `-replay` stay as aliases so anything that
        # calls this script directly keeps working.
        # `--no-build` 與 `--actionfile` 是 test.zsh 在其他所有平台上使用的寫法，也是
        # test_common.zsh 交付過來的形式。原本的 `-noApk` 與 `-replay` 保留為別名，讓任何直接
        # 呼叫本腳本的既有做法仍然可用。
        -n|--no-build|-noApk|--no-apk) do_apk=0; shift ;;
        # Release is the default here, as it is for every other platform in
        # compile.zsh, and this is the way back to a debug build.
        # 此處預設為 release，與 compile.zsh 中其他所有平台相同；本旗標是回到 debug 建置的方式。
        --debug-build) BUILD_CONFIG=debug; shift ;;
        --actionfile|-replay|--replay)
            if [ "$#" -gt 1 ] && [[ "$2" != -* ]]; then
                action_file="$2"
                shift 2
            else
                candidates=("$script_dir/actions/android/$app"-*.csv(N))
                [ "${#candidates}" -eq 1 ] || die "Provide one Android action file for $app"
                action_file="${candidates[1]}"
                shift
            fi
            ;;
        --showtime)
            [ "$#" -gt 1 ] || die "--showtime requires seconds"
            showtime_seconds="$2"
            shift 2
            ;;
        --no-showtime) showtime_seconds=0; shift ;;
        --device)
            [ "$#" -gt 1 ] || die "--device requires an AVD name or adb serial"
            device_name="$2"
            shift 2
            ;;
        -h|--help) usage; exit 0 ;;
        *) die "Unknown option: $1" ;;
    esac
done

[ "$(uname -s)" = Darwin ] || die "test_android.zsh requires macOS"

android_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-${repo_root:h}/.android-sdk}}"
# macOS 27 can block the legacy IOKit USB backend while adb starts its server.
# libusb keeps emulator-only testing responsive and can still be overridden by
# callers that need the legacy backend.
# macOS 27 可能讓 adb 啟動 server 時卡在舊版 IOKit USB backend。libusb 可讓僅使用
# emulator 的測試正常啟動；若有需要，呼叫端仍可覆寫此設定。
export ADB_LIBUSB="${ADB_LIBUSB:-1}"
if [ -n "${SWIFT_BUNDLER:-}" ]; then
    bundler_bin="$SWIFT_BUNDLER"
elif [ -x "$repo_root/Vendor/swift-bundler/.build/out/Products/Debug/swift-bundler" ]; then
    # Use the build-tree executable because ErrorKit's resource bundle is kept
    # beside it. The copied root binary may fail before parsing arguments when
    # that resource bundle is absent.
    # 使用 build tree 的執行檔，因為 ErrorKit resource bundle 會與它放在一起；若缺少該
    # resource bundle，複製到 repository root 的 binary 可能在解析引數前就失敗。
    bundler_bin="$repo_root/Vendor/swift-bundler/.build/out/Products/Debug/swift-bundler"
else
    bundler_bin="$repo_root/swift-bundler"
fi

# The strip is default, and this is what makes "default" mean something.
#
# `.swift_ast` is removed from the packaged library by a patch this tree keeps
# against Vendor/swift-bundler -- 43 MB off every APK, 212 down to 169. A
# bundler built without that patch produces a correct APK that is simply larger,
# so nothing fails and nobody notices until the download doubles. That is the
# shape of failure this project spends the most effort refusing.
#
# The marker is the flag's own name, which only exists in a patched build. If it
# is missing, say so once and carry on: a fat APK is still a testable APK, and
# stopping the run would make a size optimisation into a blocker.
#
# 剝除是預設行為，而這一段正是讓「預設」這個詞有意義的東西。
#
# `.swift_ast` 是由本樹針對 Vendor/swift-bundler 所保存的一份 patch，從打包的 library 中移除的
# ——每支 APK 少 43 MB，由 212 降到 169。一個未套用該 patch 的 bundler 會產生完全正確、只是比較大的
# APK，因此不會有任何東西失敗，也不會有人發現，直到下載量翻倍為止。那正是本專案最不遺餘力拒絕的
# 那種失敗形狀。
#
# 此處的標記是那個旗標自己的名稱，它只存在於已套用 patch 的建置中。若它不存在，就說一次然後繼續：
# 一個肥大的 APK 仍然是可測試的 APK，而中止執行會把一項體積最佳化變成一道阻礙。
# `grep -c` into a variable, not `grep -q` in a condition. Under this script's
# `set -o pipefail`, `grep -q` exits as soon as it matches, `strings` takes
# SIGPIPE, the pipeline reports failure, and the `!` turns that into the warning
# it was meant to suppress. The first version of this check fired on a bundler
# that did carry the marker -- the test manufactured the fault it was looking
# for.
#
# 使用 `grep -c` 並存進變數，而不是在條件式中使用 `grep -q`。在本腳本的 `set -o pipefail` 之下，
# `grep -q` 一旦命中就會結束，`strings` 收到 SIGPIPE，整條管線回報失敗，而 `!` 又把它轉成了它本該
# 抑制的那則警告。這項檢查的第一版，正是在一個確實帶有該標記的 bundler 上觸發的——那個測試自己
# 製造了它所要尋找的故障。
strip_marker=$(strings "$bundler_bin" 2>/dev/null | grep -c "SCUI_KEEP_SWIFT_AST") || strip_marker=0
if [ "${strip_marker:-0}" -eq 0 ]; then
    printf '%s\n' \
        "==> WARNING: this swift-bundler does not strip .swift_ast." \
        "    Every APK it builds will be about 43 MB larger than it needs to be." \
        "    Fix with: bash Scripts/build-android-bundler.sh" \
        "==> 警告：這個 swift-bundler 不會剝除 .swift_ast。" \
        "    它所建置的每一支 APK 都會比必要大小多出約 43 MB。" \
        "    修正方式：bash Scripts/build-android-bundler.sh" >&2
fi
# 31, matching compile.zsh and androidContainer/Bundler.android.toml.
#
# This said 28 while the other two said 31, which is worse than all three
# saying 28: `compile.zsh -android` would build for API 31 and then this script
# would rebuild the same app for 28 in its own tree, so the APK under test was
# not the thing that had just been checked. The three are one decision and have
# to move together.
#
# 31，與 compile.zsh 及 androidContainer/Bundler.android.toml 一致。
#
# 此處原本寫 28，而另外兩處寫 31——那比三處都寫 28 更糟：`compile.zsh -android` 會以 API 31 建置，
# 而本腳本接著會在自己的建置樹中以 28 重建同一支 app，於是受測的 APK 並不是剛才檢查過的那一個。
# 這三處是同一個決定，必須一起移動。
android_triple="${ANDROID_TRIPLE:-aarch64-unknown-linux-android31}"
android_ndk_version="${ANDROID_NDK_VERSION:-27.0.12077973}"
android_ndk_home="${ANDROID_NDK_HOME:-$android_root/ndk/$android_ndk_version}"
# A toolchain matching the Android SDK, and explicitly not Xcode's.
#
# `swift` on a Mac is Xcode's -- 6.4 as of 2026-09-02 -- while the newest
# Android SDK swift.org publishes is 6.3.3. Building with the host default
# fails on every module that imports Foundation:
#
#     error: module compiled with Swift 6.3.3 cannot be imported by the
#     Swift 6.4 compiler
#
# The default was a dated snapshot name, `swift-6.3-DEVELOPMENT-SNAPSHOT-
# 2026-06-07-a`. That toolchain still exists here, but the name rots: the
# matching Android SDK was replaced with 6.3.3-RELEASE on 2026-09-02 and a
# hard-coded snapshot date has no way to follow. `swift-latest` is the same
# 6.3.3-dev compiler today and at least tracks whatever was installed last.
#
# If this ever fails with the version error above, the fix is to install a
# toolchain matching the SDK -- not to raise the SDK, which cannot be raised
# past what swift.org has published. See testapp/build_time_android.md.
#
# 需要與 Android SDK 相符的 toolchain，且明確不是 Xcode 的那個。
#
# Mac 上的 `swift` 是 Xcode 的——2026-09-02 為 6.4——而 swift.org 所發布最新的 Android SDK 是
# 6.3.3。使用主機預設值建置，會使每一個 import Foundation 的 module 都以上方英文所示的錯誤失敗。
#
# 原本的預設值是一個帶日期的 snapshot 名稱 `swift-6.3-DEVELOPMENT-SNAPSHOT-2026-06-07-a`。
# 該 toolchain 目前仍存在，但這個名稱會腐爛：對應的 Android SDK 已於 2026-09-02 換成
# 6.3.3-RELEASE，而寫死的 snapshot 日期無從跟上。`swift-latest` 今日即是同一個 6.3.3-dev 編譯器，
# 且至少會跟隨「最後安裝的是哪一個」。
#
# 若日後出現上述版本錯誤，正確的修法是安裝一個與 SDK 相符的 toolchain——而不是調高 SDK，
# 因為它無法高過 swift.org 已發布的版本。詳見 testapp/build_time_android.md。
swift_toolchain="${SWIFT_ANDROID_TOOLCHAIN:-swift-latest}"
swift_bin="${SWIFT_BIN:-$HOME/Library/Developer/Toolchains/${swift_toolchain}.xctoolchain/usr/bin/swift}"
package_dir="$script_dir/.compile-work-android/TestApps"
apk_path="$apk_dir/$app.apk"
# Lowercased. The APK's application id is lowercase, so `adb shell am start`
# against "dev.swiftcrossui.testapp.P12" finds no such package while the install
# reports success -- the failure looks like the app refusing to launch.
# 轉為小寫。APK 的 application id 是小寫的，因此以 "dev.swiftcrossui.testapp.P12" 執行
# `adb shell am start` 會找不到該套件，而安裝本身卻回報成功——該失敗看起來會像是 app 拒絕啟動。
package_id="dev.swiftcrossui.testapp.$app_id"
adb="$android_root/platform-tools/adb"
emulator="$android_root/emulator/emulator"

zsh "$script_dir/install_tools_android.zsh" --check >/dev/null
[ -x "$adb" ] || die "Missing adb: $adb"

if [ "$do_apk" -eq 1 ]; then
    [ -x "$swift_bin" ] || die "Missing Swift Android toolchain: $swift_bin; run Scripts/build-tool-install-android-on-Mac.sh"
    [ -x "$bundler_bin" ] || die "Missing Swift Bundler: $bundler_bin; run Scripts/build-tool-install-android-on-Mac.sh"

    print "==> Building $app for Android"
    ANDROID_HOME="$android_root" ANDROID_SDK_ROOT="$android_root" \
        ANDROID_NDK_HOME="$android_ndk_home" ANDROID_NDK_ROOT="$android_ndk_home" \
        ANDROID_TRIPLE="$android_triple" SWIFT_BIN="$swift_bin" \
        SCUI_ANDROID=1 zsh "$script_dir/compile.zsh" -android "$app"

    print "==> Bundling $app APK"
    mkdir -p "$apk_dir"
    # Both overrides have to be handed to the bundler explicitly.
    #
    # Swift Bundler runs its own `swift build`, and it inherits neither
    # of the two things an Android build here needs. Measured
    # 2026-09-02, its invocation was
    #
    #   /usr/bin/env swift build -c debug --product P12 --arch aarch64
    #     --swift-sdks-path ~/Library/Caches/.../sdk-silos/...
    #     --swift-sdk aarch64-unknown-linux-android31 ...
    #
    # -- Xcode's swift, and the default swiftbuild build system. So it
    # reproduced the six SwiftJava static-linkage errors that
    # compile.zsh already works around, after compile.zsh had just
    # built the same product successfully.
    #
    # `--toolchain` fixes the compiler, `--Xswiftpm` passes the build
    # system through. See testapp/build_time_android.md for why each is
    # needed.
    #
    # 兩個覆寫都必須明確交給 bundler。
    #
    # Swift Bundler 會執行它自己的 `swift build`，而此處 Android 建置所需的那兩件事，它一件
    # 也不繼承。2026-09-02 實測其呼叫如上方英文所示——用的是 Xcode 的 swift，以及預設的
    # swiftbuild 建置系統。於是它重現了 compile.zsh 早已繞過的那六條 SwiftJava 靜態連結錯誤，
    # 而 compile.zsh 才剛剛成功建出同一個 product。
    #
    # `--toolchain` 修正編譯器，`--Xswiftpm` 把建置系統傳遞下去。各自的理由見
    # testapp/build_time_android.md。
    #
    # The comment above used to sit between the environment assignments and the
    # command, after a line continuation. zsh ends the continuation at the
    # comment, so SCUI_ANDROID and the four ANDROID_* variables applied to
    # nothing and the build failed with "Unknown backend selected" from
    # DefaultBackend -- an error about backend selection caused by a misplaced
    # comment.
    #
    # 上方的註解原本位於環境變數指派與指令之間、且緊接在續行符號之後。zsh 會在註解處結束續行，
    # 因此 SCUI_ANDROID 與那四個 ANDROID_* 變數等於沒有套用到任何東西，建置以 DefaultBackend 的
    # 「Unknown backend selected」失敗——一個關於 backend 選擇的錯誤，成因卻是一個位置放錯的註解。
    #
    # A scratch path of its own, so the two entry points stop erasing each
    # other.
    #
    # Both defaulted to `<package>/.build`, but Swift Bundler builds against a
    # Swift SDK *silo* -- a symlink farm under its cache that exists to
    # disambiguate SDKs sharing a target triple -- and passes that path as
    # `--swift-sdks-path`. compile.zsh uses the SDK's real location. Same
    # scratch directory, different SDK path, so SwiftPM saw different inputs and
    # rebuilt everything; then the next `compile.zsh -android` rebuilt
    # everything back. Ten minutes each way, for a tree that was already warm.
    #
    # Two trees cost disk. One tree cost ten minutes every time anyone switched.
    #
    # 給它自己的 scratch path，讓兩個入口不再互相清除對方的成果。
    #
    # 兩者原本都預設為 `<package>/.build`，但 Swift Bundler 是針對 Swift SDK 的 *silo* 建置的
    # ——那是位於其快取下的一片符號連結，存在目的是為共用 target triple 的多個 SDK 消歧義——並把該
    # 路徑以 `--swift-sdks-path` 傳入。compile.zsh 用的則是 SDK 的實際位置。相同的 scratch 目錄、
    # 不同的 SDK 路徑，於是 SwiftPM 認定輸入不同而全部重建；接著下一次 `compile.zsh -android`
    # 又全部重建回去。來回各十分鐘，而那棵樹本來是熱的。
    #
    # 兩棵樹的代價是磁碟。一棵樹的代價是每次有人切換就十分鐘。
    bundler_scratch="$package_dir/.build-bundler"
    (
        cd "$package_dir"
        SCUI_ANDROID=1 ANDROID_HOME="$android_root" ANDROID_SDK_ROOT="$android_root" \
            ANDROID_NDK_HOME="$android_ndk_home" ANDROID_NDK_ROOT="$android_ndk_home" \
            "$bundler_bin" bundle "$app" --platform Android -c "${BUILD_CONFIG:-release}" \
                --toolchain "${swift_bin:h:h:h}" \
                --scratch-path "$bundler_scratch" \
                --Xswiftpm --build-system --Xswiftpm "${ANDROID_BUILD_SYSTEM:-native}"
    )
    # Read back out of the same scratch path it was written into.
    #
    # These were two separate literals and they disagreed: the bundle went to
    # `.build-bundler/...` and this looked in `.build/...`. Every app died with
    # "Bundler succeeded but APK was not found" after a four-minute build --
    # every app except P12, because a stale P12 APK from an earlier run was
    # still sitting at the old path. So P12 alone appeared to pass, and what it
    # installed was not what had just been built. A survey of 23 apps was run
    # against that.
    #
    # One variable now, used in both places, so they cannot drift again.
    #
    # 從寫入時所用的同一個 scratch path 讀回來。
    #
    # 這裡原本是兩個各自獨立的字面值，而它們並不一致：bundle 產到 `.build-bundler/...`，此處卻去
    # `.build/...` 找。每一支 app 都在四分鐘的建置之後死於「Bundler succeeded but APK was not
    # found」——除了 P12，因為舊路徑上還躺著先前某次執行留下的 P12 APK。於是只有 P12 看起來通過，
    # 而它所安裝的並不是剛剛建出來的那一支。一份涵蓋 23 支 app 的普查就是在那個狀態下跑的。
    #
    # 現在只有一個變數、兩處共用，因此它們不可能再各自漂移。
    generated_apk="$bundler_scratch/bundler/apps/$app/$app.apk"
    [ -f "$generated_apk" ] || die "Bundler succeeded but APK was not found: $generated_apk"
    cp "$generated_apk" "$apk_path"
    print "    -> $apk_path"
else
    [ -f "$apk_path" ] || die "Missing cached APK: $apk_path; omit -noApk to build it"
    print "==> Reusing $apk_path"
fi

if [ -z "$device_name" ]; then
    device_name="$($emulator -list-avds 2>/dev/null | head -n 1 || true)"
    [ -n "$device_name" ] || die "No Android AVD exists; create one before delivery"
fi

if [[ "$device_name" == emulator-* ]]; then
    serial="$device_name"
else
    print "==> Booting Android AVD: $device_name"
    # `-no-metrics`, or the emulator can block before it ever boots.
    #
    # Measured 2026-09-05: `emulator -avd ... -no-snapshot -no-boot-anim` logged
    # "Showing crashdialog to get consent." and then sat there. `adb devices`
    # stayed empty, the sixty-second wait below expired, and the failure read
    # "Android emulator did not appear in adb devices" -- which sounds like a
    # boot that was too slow rather than a modal dialog waiting for a click that
    # a headless run will never give it.
    #
    # 加上 `-no-metrics`，否則模擬器可能在啟動之前就卡住。
    #
    # 2026-09-05 實測：`emulator -avd ... -no-snapshot -no-boot-anim` 記錄了
    # 「Showing crashdialog to get consent.」然後就停在那裡。`adb devices` 一直是空的，下方的六十秒
    # 等待逾時，而失敗訊息是「Android emulator did not appear in adb devices」——那聽起來像是啟動太慢，
    # 而不是「一個模態對話框正在等一次點擊，而無人值守的執行永遠不會給它」。
    "$emulator" -avd "$device_name" -no-snapshot -no-boot-anim -no-metrics \
        >/dev/null 2>&1 &
    serial=""
    for _ in {1..60}; do
        serial="$($adb devices | awk '/^emulator-[0-9]+[[:space:]]+/{print $1; exit}')"
        [ -n "$serial" ] && break
        sleep 1
    done
    [ -n "$serial" ] || die "Android emulator did not appear in adb devices"
fi

print "==> Waiting for Android device"
ANDROID_SERIAL="$serial" "$adb" wait-for-device
ANDROID_SERIAL="$serial" "$adb" shell getprop sys.boot_completed | grep -q 1 || {
    for _ in {1..60}; do
        sleep 1
        ANDROID_SERIAL="$serial" "$adb" shell getprop sys.boot_completed 2>/dev/null | grep -q 1 && break
    done
}
ANDROID_SERIAL="$serial" "$adb" shell getprop sys.boot_completed | grep -q 1 || die "Android device did not finish booting"


# Screenshots, into the same place and with the same naming every other platform
# uses -- testapp/output/screenshots/<label>-<timestamp>.png -- so a run's
# evidence lands together whichever target produced it.
#
# Not through screenshot.zsh. That captures a display, and a display is the
# wrong thing here: what matters is the device's own framebuffer, which is a
# different image from "the emulator window as composited on this Mac" and is
# available without Screen Recording permission.
#
# The file is checked for content, not just the exit code. `adb exec-out` writes
# through a shell redirect, so the file exists whether or not a single byte
# arrived -- an empty PNG would otherwise be reported as a successful capture.
#
# Failure is reported and counted, never swallowed, and never aborts the run: a
# screenshot is evidence, not the assertion.
#
# 截圖輸出至與其他所有平台相同的位置與命名方式——testapp/output/screenshots/<label>-<時間戳>.png
# ——如此一來，無論由哪個 target 產生，一次執行的證據都會落在一起。
#
# 不經由 screenshot.zsh。該腳本擷取的是「顯示器」，而在此處那是錯的對象：真正重要的是裝置自身的
# framebuffer，它與「emulator 視窗在這台 Mac 上合成後的樣子」是不同的影像，且不需要螢幕錄製權限。
#
# 此處檢查的是檔案是否有內容，而不僅是結束碼。`adb exec-out` 是透過 shell 重導向寫出的，因此無論
# 是否真的收到任何位元組，該檔都會存在——否則一個空的 PNG 會被回報為擷取成功。
#
# 失敗會被回報並計數，不會被吞掉，也絕不中止執行：截圖是證據，而非斷言。
screenshot_failures=0
capture() {
    local label="$1"
    local dir="$script_dir/output/screenshots"
    mkdir -p "$dir"
    # Not `path`. It is the zsh array tied to $PATH, so `local path=...` empties
    # the command search path for the rest of the function: xcrun is not found,
    # the capture "fails", and then `rm` is not found either -- the observed
    # symptom was "capture:12: command not found: rm". Same family as `status`,
    # which bit two commits ago, and this file's own notes name `path` first.
    # 不用 `path`。它是 zsh 中與 $PATH 綁定的陣列，因此 `local path=...` 會清空該函式其餘部分的
    # 命令搜尋路徑：找不到 xcrun，擷取遂「失敗」，接著連 `rm` 也找不到——實際觀察到的症狀是
    # 「capture:12: command not found: rm」。與兩個 commit 前咬過人的 `status` 同一族，而本檔自身
    # 的註解正是把 `path` 列在第一個。
    local shot="$dir/${label}-$(date +%Y%m%d-%H%M%S).png"

    if ANDROID_SERIAL="$serial" "$adb" exec-out screencap -p > "$shot" 2>/dev/null \
        && [ -s "$shot" ]; then
        print "==> Screenshot: ${shot:t}"
        return 0
    fi

    rm -f "$shot"
    screenshot_failures=$(( screenshot_failures + 1 ))
    print -u2 -r -- "!! no screenshot from $serial"
    return 0
}

print "==> Installing $apk_path"
ANDROID_SERIAL="$serial" "$adb" install -r "$apk_path" >/dev/null
ANDROID_SERIAL="$serial" "$adb" shell am force-stop "$package_id" || true
# Start the declared launcher activity directly. `monkey` can return a non-zero
# status for emulator input limitations even when it does not provide a useful
# readiness check for action-file replay.
# 直接啟動 manifest 宣告的 launcher activity。`monkey` 可能因 emulator 輸入限制回傳
# 非零狀態，無法作為 action file replay 的可靠 readiness check。
# The action file goes to the device and its path goes in an intent extra.
#
# An Android app has no argv, so `AndroidBackend.entrypoint` used to call
# `main(0, nil)` and nothing downstream could see a flag. `--actionfile` was
# parsed by this script and then dropped -- an option that was accepted and did
# nothing. `AndroidBackend+Arguments.swift` now reads the `scui_args` extra and
# builds argv from it before `main` runs, so `--debug` and `-actionfile` mean
# here what they mean everywhere else.
#
# `/data/local/tmp` rather than the app's own directory: adb can write there
# without root and the app can read it, and no path in it contains a space --
# which matters, because the extra is split on spaces.
#
# 動作檔送到裝置上，而它的路徑放進 intent 的 extra。
#
# Android app 沒有 argv，因此 `AndroidBackend.entrypoint` 原本呼叫 `main(0, nil)`，下游看不到任何
# 旗標。`--actionfile` 由本腳本解析之後就被丟掉——一個被接受卻什麼都不做的選項。現在
# `AndroidBackend+Arguments.swift` 會讀取 `scui_args` 這個 extra，並在 `main` 執行前據以建構 argv，
# 使 `--debug` 與 `-actionfile` 在此處的意義與在其他每個平台相同。
#
# 使用 `/data/local/tmp` 而非 app 自己的目錄：adb 不需 root 即可寫入該處，而 app 讀得到；且其中
# 沒有任何路徑含有空白——這一點很重要，因為該 extra 是以空白切分的。
app_args=()
if [ -n "$action_file" ]; then
    [ -f "$action_file" ] || die "No such action file: $action_file"
    device_action_file="/data/local/tmp/$app-actions.csv"
    print "==> Pushing $action_file -> $device_action_file"
    ANDROID_SERIAL="$serial" "$adb" push "$action_file" "$device_action_file" >/dev/null \
        || die "Could not push the action file to the device"
    app_args=(--debug -actionfile "$device_action_file")
fi

if [ "${#app_args}" -gt 0 ]; then
    # Quoted for the shell ON THE DEVICE, which is a second round of word
    # splitting `adb shell` does not protect against: it joins its arguments
    # into one command line and the device's shell re-parses it. Without the
    # inner quotes, `--es scui_args "--debug -actionfile /data/local/tmp/x.csv"`
    # arrives as three words, and `am` reads `-actionfile` as `-a ctionfile` --
    # it sets the intent's ACTION to "ctionfile" and takes the path as the
    # component:
    #
    #   Starting: Intent { act=ctionfile cmp=/data/local/tmp/P12-actions.csv }
    #   Error: Activity class {/data/local/tmp/P12-actions.csv} does not exist.
    #
    # Measured on the emulator. The app never launched, and the script stopped
    # with no line saying why.
    #
    # 這裡的引號是給**裝置上的** shell 的——那是 `adb shell` 並不會替你擋掉的第二輪斷詞：它把自己的
    # 引數併成一行命令，再由裝置端的 shell 重新解析。少了內層引號，
    # `--es scui_args "--debug -actionfile /data/local/tmp/x.csv"` 抵達時會是三個詞，而 `am` 會把
    # `-actionfile` 讀成 `-a ctionfile`——它把 intent 的 ACTION 設為「ctionfile」，並把該路徑當成
    # component（輸出見上方英文）。此事於 emulator 上實測：app 根本沒有啟動，而腳本停下時沒有任何
    # 一行說明原因。
    ANDROID_SERIAL="$serial" "$adb" shell am start -W -n "$package_id/.MainActivity" \
        --es scui_args "'${app_args[*]}'" >/dev/null
else
    ANDROID_SERIAL="$serial" "$adb" shell am start -W -n "$package_id/.MainActivity" >/dev/null
fi

print "==> Launched $package_id on $serial"

# Five seconds before the first capture, not one.
#
# One second is the number the other platforms use, and on Android it
# photographs the wrong thing. A cold start here has to bring up the JVM, load
# libswiftCore, Foundation and ICU, run `AndroidBackend_entrypoint` through JNI
# and then lay out; the apps log RENDER COMPLETE at around six seconds. A
# one-second capture can therefore photograph the launch splash instead of the
# app: `p13-android-1s-20260905-113746.png` is 97.6% white with a green Android
# robot and nothing else. One of 174 captures on 2026-09-05, so it is rare on a
# warm emulator and not rare enough to leave to chance.
#
# It also broke a check built on top of it. Comparing the `-1s-` and `-final-`
# captures was meant to show what the action file changed, and under
# `--no-showtime` the two are taken back to back: forty of forty-five apps
# differed by exactly zero pixels, same timestamp, same md5. One photograph
# compared with itself. The gap has to be real for the pair to mean anything.
#
# The name stays `-1s-`. It is in every existing filename and in the comparisons
# written against them, and renaming it would silently split the history in two.
# 是 5 秒,不是 1 秒。
#
# 1 秒是其他平台使用的數字,而在 Android 上它拍到的是錯的東西。此處的冷啟動必須先起 JVM、載入
# libswiftCore、Foundation 與 ICU、透過 JNI 執行 `AndroidBackend_entrypoint`,然後才排版;這些 app
# 大約在六秒左右記錄 RENDER COMPLETE。因此 1 秒的擷取有可能拍到啟動畫面而不是 app:
# `p13-android-1s-20260905-113746.png` 有 97.6% 是白色,畫面上只有一個綠色的 Android 機器人。
# 2026-09-05 的 174 張擷取中出現一次——在熱的模擬器上算罕見,但沒有罕見到可以交給運氣。
#
# 它同時也弄壞了一個建立在其上的檢查。比對 `-1s-` 與 `-final-` 兩張擷取,原意是顯示動作檔改變了
# 什麼;而在 `--no-showtime` 之下,這兩張是連續拍下的:四十五支中有四十支的差異恰好是零像素、
# 時間戳相同、md5 相同。那是拿一張照片跟它自己比。這一對要有意義,中間的間隔就必須是真的。
#
# 名稱維持 `-1s-`。它出現在每一個既有檔名、以及依據那些檔名所寫的比對之中,重新命名會靜默地把
# 歷史一分為二。
first_capture_seconds="${ANDROID_FIRST_CAPTURE_SECONDS:-5}"
sleep "$first_capture_seconds"
capture "${app_id}-android-1s"

if [ "$showtime_seconds" -gt 0 ]; then
    sleep "$showtime_seconds"
fi

capture "${app_id}-android-final"
if [ "$screenshot_failures" -gt 0 ]; then
    print -u2 -r -- "!! $screenshot_failures screenshot(s) could not be taken"
fi
