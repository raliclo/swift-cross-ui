#!/usr/bin/env zsh
# Check that the root view-mode control obeys the build and the flag on Android.
#
# The Android counterpart of test_rootscroll_ios.zsh, and the same three states:
#
#   debug build (SCUI_DEBUG=1)   shown by default
#   release build                hidden by default
#   release build + the flag     shown
#
# The flag is `-allow-rootscroll`, read in release builds on purpose: a release
# build is exactly where rebuilding to see the control is not an option. See
# DebugFeatures.allowsRootScrollControl.
#
# Two things differ from the iOS script, and both are the platform rather than a
# choice.
#
# **The flag travels in an intent extra.** An Android activity has no command
# line, so `AndroidLaunchArguments` reads `--es scui_args` and assigns
# `CommandLine.arguments` before `main`. That is the only route a flag has here,
# and it is why this script passes the flag with `am start --es` rather than
# after the binary's name.
#
# **The probe looks below the status bar, and for the button's fill.** The
# control is offset by the safe-area inset, because before it was the status bar
# took its touches -- `statusBars frame=[0,0][1080,128]` on the emulator this was
# written against, against a button 126 pixels tall. So the corner this samples
# starts under that.
#
# The iOS script counts dark pixels there, on the stated grounds that "the apps
# this runs against have nothing else in that corner". That is true of the iOS
# layout and false here: Android draws edge to edge, so the content starts higher
# and P23's own title sits in the same rectangle. Counting dark pixels reported
# 3455 for a release build with no button at all and called it present -- a
# failure invented entirely by the probe. Counting the button's own fill instead
# separates the two states by two orders of magnitude: 19,614 pixels of
# (214,215,215) with the button, 211 without.
#
# 檢查根視圖的模式控制項在 Android 上是否遵守「建置」與「旗標」。
#
# 這是 test_rootscroll_ios.zsh 的 Android 對應版本，檢查同樣的三個狀態：
#
#   debug 建置（SCUI_DEBUG=1）   預設顯示
#   release 建置                預設隱藏
#   release 建置 + 該旗標        顯示
#
# 旗標為 `-allow-rootscroll`，它在 release 建置中會被讀取，而這是刻意的：release 建置恰恰是「無法
# 靠重新建置來看見該控制項」的那種建置。見 DebugFeatures.allowsRootScrollControl。
#
# 有兩點與 iOS 的腳本不同，而兩者都是平台造成的，不是選擇。
#
# **旗標是以 intent extra 傳遞的。** Android 的 activity 沒有命令列，因此 `AndroidLaunchArguments`
# 會讀取 `--es scui_args`，並在 `main` 之前指派 `CommandLine.arguments`。那是旗標在此處唯一的路徑，
# 這也是本腳本以 `am start --es` 傳遞旗標、而非附在執行檔名稱之後的原因。
#
# **探測區域位於狀態列之下，且判準是按鈕本身的填色。** 該控制項會依安全區域的 inset 偏移，因為在此
# 之前，狀態列會接走它的觸控——撰寫本腳本時所依據的模擬器上，`statusBars frame=[0,0][1080,128]`，而
# 按鈕高 126 像素。因此本腳本取樣的角落是從狀態列之下開始。
#
# iOS 的腳本在那裡計算深色像素，其理由明載為「這些 app 在那個角落不會放任何其他東西」。那句話對 iOS
# 的版面成立，在此處則不成立：Android 是 edge-to-edge 繪製的，內容起點更高，P23 自己的標題就落在同一個
# 矩形內。以深色像素計數，會對「一個根本沒有按鈕的 release 建置」回報 3455 並判定為存在——那是一個
# 完全由探測器自己製造出來的失敗。改為計算按鈕自身的填色，兩個狀態相差兩個數量級：有按鈕時
# (214,215,215) 有 19,614 個像素，沒有時 211 個。

set -euo pipefail

script_path="${0:a}"
script_dir="${script_path:h}"

target="${1:-P12}"
serial="${ANDROID_SERIAL:-emulator-5554}"
package="dev.swiftcrossui.testapp.${target:l}"
shots="$script_dir/output/screenshots"
scratch="${TMPDIR:-/tmp}/rootscroll-android-$target"

if [ ! -f "$script_dir/$target.swift" ]; then
    print -u2 "No such test app: $target (expected $script_dir/$target.swift)"
    exit 64
fi

android_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/Volumes/Windows/proj_Win/.android-sdk}}"
adb="$android_root/platform-tools/adb"
if [ ! -x "$adb" ]; then
    print -u2 "adb not found at $adb; set ANDROID_HOME"
    exit 69
fi

mkdir -p "$shots" "$scratch"

# The button's default corner, in device pixels, below the status bar.
#
# Sampled rather than read out of a UI dump on purpose: a dump reports a node
# whether or not anything was drawn, and the question here is whether the
# control is on the screen. On a white page a bordered button is a large run of
# non-white pixels and these apps put nothing else in that corner.
#
# 按鈕的預設角落，以裝置像素表示，位於狀態列之下。
#
# 刻意採用取樣而非讀取 UI dump：dump 無論實際上有沒有畫出東西都會回報一個節點，而此處要問的是「該
# 控制項是否出現在畫面上」。在白色頁面上，一個帶框的按鈕就是一大片非白像素，而這些 app 在那個角落
# 不會放任何其他東西。
button_probe() {
    python3 - "$1" <<'PY'
import sys
from PIL import Image
image = Image.open(sys.argv[1]).convert("RGB")
corner = image.crop((21, 147, 252, 273))
fill = sum(
    1
    for r, g, b in corner.get_flattened_data()
    if 195 <= r <= 240 and abs(r - g) < 12 and abs(g - b) < 14
)
print(fill)
PY
}

report() {
    local label="$1" count="$2" expected="$3"
    if [ "$expected" = present ]; then
        if [ "$count" -gt 5000 ]; then
            print "  PASS  $label -- button present ($count fill pixels)"
            return 0
        fi
        print "  FAIL  $label -- button missing ($count fill pixels, wanted > 5000)"
        return 1
    else
        if [ "$count" -lt 5000 ]; then
            print "  PASS  $label -- button absent ($count fill pixels)"
            return 0
        fi
        print "  FAIL  $label -- button present when it should not be ($count fill pixels)"
        return 1
    fi
}

capture() {
    local name="$1"
    local args="${2:-}"
    "$adb" -s "$serial" shell am force-stop "$package" >/dev/null 2>&1 || true
    if [ -n "$args" ]; then
        "$adb" -s "$serial" shell am start -n "$package/.MainActivity" \
            --es scui_args "$args" >/dev/null 2>&1
    else
        "$adb" -s "$serial" shell am start -n "$package/.MainActivity" >/dev/null 2>&1
    fi
    # Long enough for the Swift runtime, the JNI entrypoint and the first layout
    # pass. Three seconds was enough on iOS and is not here: a cold Android
    # start of these apps reaches RENDER COMPLETE at around six.
    # 足以涵蓋 Swift runtime、JNI 進入點與第一次版面計算。三秒在 iOS 上夠用，在此處不夠：這些 app
    # 的 Android 冷啟動大約在六秒左右才抵達 RENDER COMPLETE。
    sleep 8
    "$adb" -s "$serial" exec-out screencap -p > "$scratch/$name.png"
    cp "$scratch/$name.png" "$shots/$target-rootscroll-android-$name.png"
    button_probe "$scratch/$name.png"
}

install_current() {
    "$adb" -s "$serial" install -r -d "$script_dir/.androidApk/$target.apk" >/dev/null 2>&1
}

failures=0

print "==> release build (no SCUI_DEBUG)"
# test_android.zsh builds, installs and launches. The launch is not wanted here
# -- each check launches the app itself, with the arguments under test -- but it
# is harmless: `capture` force-stops before every launch. Reusing the script is
# better than reproducing its build invocation, which is where the bundler
# overrides, the scratch path and the strip guard live.
# test_android.zsh 會建置、安裝並啟動。此處並不需要那次啟動——每一項檢查都會自行以「受測的引數」
# 啟動 app——但它無害：`capture` 在每次啟動前都會 force-stop。沿用該腳本，優於複製它的建置呼叫，
# 因為 bundler 的各項覆寫、scratch path 與剝除守衛都在那裡。
zsh "$script_dir/test_android.zsh" "$target" --no-showtime >/dev/null 2>&1
install_current

report "release, no flag" "$(capture release-plain)" absent || failures=$((failures + 1))
report "release, -allow-rootscroll" "$(capture release-flag -allow-rootscroll)" present \
    || failures=$((failures + 1))

print "==> debug build (SCUI_DEBUG=1)"
SCUI_DEBUG=1 zsh "$script_dir/test_android.zsh" "$target" --no-showtime >/dev/null 2>&1
install_current

report "debug, no flag" "$(capture debug-plain)" present || failures=$((failures + 1))

"$adb" -s "$serial" shell am force-stop "$package" >/dev/null 2>&1 || true

print
print "Screenshots: $shots/$target-rootscroll-android-*.png"
if [ "$failures" -eq 0 ]; then
    print "All 3 checks passed."
else
    print "$failures of 3 checks failed."
fi
exit "$failures"
