#!/bin/zsh
# Writes ipad-<mode>.txt: the menu bar a real SwiftUI app (refios.swift) builds on an iPad.
#
#   zsh testapp/reference/swiftui-commands/ipad/dump.zsh [mode ...]     default: base after replacing
#
# How, and why it is this roundabout (2026-10-14):
#   - The system does not build an iPad's menu bar until a key or the pointer arrives. Launched
#     alone, the reference app prints nothing, and UIMenuSystem.main.setNeedsRebuild() does not
#     change that.
#   - The action-file runner (XCUITest) can send both, but it launches the app it was built to
#     launch: dev.swiftcrossui.testapp.debugTarget. So the reference is installed under that
#     identifier, and the runner replays P92-build-the-menu-bar-ipad.actions on it.
#   - The runner launches the app itself and passes no environment, so the mode is compiled in.
#   - The reference is uninstalled at the end. Left installed, the next P92 run on the iPad
#     finds the wrong app under its identifier and fails with "No matches found ... Window".
#
# 寫出 ipad-<mode>.txt:真正的 SwiftUI app(refios.swift)在 iPad 上建出的選單列。系統要等到有按鍵或指標事件才建 iPad 的
# 選單列，單獨啟動時參考 app 什麼都不印。動作檔 runner 能送出這兩種事件，但它只啟動 debugTarget 這個識別碼的 app,所以把參考
# app 裝在該識別碼底下，由 runner 對它重放 P92-build-the-menu-bar-ipad.actions。runner 不傳環境變數，所以模式是編譯進去的。
# 結束時解除安裝參考 app:留著的話，下一次 iPad 上的 P92 會在自己的識別碼底下找到別的 app 而失敗。
set -euo pipefail
here="${0:a:h}"
testapp="${here:h:h:h}"
device="${IOS_DEVICE:-iPad Pro 11-inch (M5)}"
target_id="dev.swiftcrossui.testapp.debugTarget"
modes=("$@")
[ "${#modes}" -gt 0 ] || modes=(base after replacing)

# One P92 run first: it builds the runner and leaves its .xctestrun pointing at the action file.
# 先跑一次 P92:它會建好 runner,並讓 .xctestrun 指向那個動作檔。
print -r -- "==> P92 once, to build the runner and aim it at the action file"
zsh "$testapp/test_ios.zsh" P92 --device "$device" --debug --no-showtime \
    --actionfile "$testapp/actions/ios/P92-build-the-menu-bar-ipad.actions" > /dev/null
xctestrun="$(find "$testapp/.bundledApp/xcodeTestRunnerProject.build/Build/Products" -name '*.xctestrun' -print -quit)"
[ -n "$xctestrun" ] || { print -ru2 -- "no .xctestrun under testapp/.bundledApp"; exit 1; }

work="$(mktemp -d)"
bundle="$work/RefAsTarget.app"
mkdir -p "$bundle"
plist="$bundle/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $target_id" \
    -c "Add :CFBundleExecutable string RefIOS" -c "Add :CFBundleName string RefIOS" \
    -c "Add :CFBundlePackageType string APPL" -c "Add :CFBundleVersion string 1" \
    -c "Add :CFBundleShortVersionString string 1.0" -c "Add :UILaunchScreen dict" \
    -c "Add :UIApplicationSceneManifest dict" \
    -c "Add :UIApplicationSceneManifest:UIApplicationSupportsMultipleScenes bool true" \
    -c "Add :UIDeviceFamily array" -c "Add :UIDeviceFamily:0 integer 1" \
    -c "Add :UIDeviceFamily:1 integer 2" -c "Add :MinimumOSVersion string 17.0" "$plist" > /dev/null

restore() {
    xcrun simctl terminate "$device" "$target_id" 2>/dev/null || true
    xcrun simctl uninstall "$device" "$target_id" 2>/dev/null || true
}
trap restore EXIT

mode_line='let mode = ProcessInfo.processInfo.environment["REF_MODE"] ?? "base"'
failed=0
for mode in $modes; do
    cp "$here/refios.swift" "$work/refios-$mode.swift"
    csv2 --headers 0 -update-where "$mode_line" "let mode = \"$mode\"" \
        -i "$work/refios-$mode.swift" --in-place
    xcrun -sdk iphonesimulator swiftc -parse-as-library -O \
        -target arm64-apple-ios17.0-simulator "$work/refios-$mode.swift" -o "$bundle/RefIOS"
    restore
    xcrun simctl install "$device" "$bundle"
    out="$work/ipad-$mode.txt"
    xcrun simctl launch --console-pty --terminate-running-process "$device" "$target_id" > "$out" 2>&1 &
    launcher=$!
    xcodebuild test-without-building -xctestrun "$xctestrun" \
        -destination "platform=iOS Simulator,name=$device" \
        -only-testing:iOSActionFileRunner/ActionFileUITests/testActionFile > "$work/runner-$mode.log" 2>&1 || true
    xcrun simctl terminate "$device" "$target_id" 2>/dev/null || true
    wait $launcher 2>/dev/null || true
    # No dump is a failure, not an empty reference. / 沒有傾印是失敗，不是一份空的基準。
    if grep -q '^=== end' "$out"; then
        cp "$out" "$here/ipad-$mode.txt"
        print -r -- "==> ipad-$mode.txt: $(grep -c '' "$out") lines"
    else
        print -ru2 -- "!! $mode: the reference app printed no menu bar; see $work/runner-$mode.log"
        failed=1
    fi
done
exit $failed
