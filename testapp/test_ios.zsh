#!/usr/bin/env zsh
# Build, package, install, and launch one SwiftCrossUI test app on iOS Simulator.
#
# The copied executable is deliberately renamed to `debugTarget`. Keeping the
# executable and bundle identifier stable makes repeated Pn runs comparable and
# avoids leaving one installed app per test target on the simulator.
#
# 建置、封裝、安裝並啟動一支 SwiftCrossUI iOS Simulator 測試 app。
#
# 複製進去的執行檔固定重新命名為 `debugTarget`。固定執行檔與 Bundle identifier
# 可讓多次 Pn 測試保持可比較，也避免 Simulator 中每支測試各留一個已安裝 app。

set -euo pipefail

script_path="${0:a}"
script_dir="${script_path:h}"
repo_root="${script_dir:h}"
output_dir="$script_dir/output"
template_dir="$script_dir/iosContainer/appTemplate.app"
bundle_root="$script_dir/.bundledApp"
xctest_template="$script_dir/iosContainer/xcodeTestRunner"
xctest_project="$script_dir/iosContainer/xcodeTestRunnerProject"
app_name="debugTarget"
bundle_id="dev.swiftcrossui.testapp.debugTarget"
device_name="${IOS_SIM_DEVICE:-swift-cross-ui}"
showtime_seconds=30
do_build=1
action_file=""
app_args=()

usage() {
    cat <<EOF_USAGE
Usage: ${script_path:t} <P0..Pn> [options] [-- app arguments]

Builds the selected Pn for the iOS Simulator, copies its executable into
testapp/iosContainer/appTemplate.app as debugTarget, installs it, and launches it.

Options:
  -n, --no-build             Reuse output/<Pn>-ios.app/<Pn> already built for iOS.
  --showtime <seconds>       Keep the app running for this long; default: 30.
  --no-showtime              Return immediately after launch.
  --device <name|UDID>       Simulator device; default: $device_name.
  --actionfile <path>        Replay CSV through XCUITest after launch.
  --debug                    Pass --debug to the Pn app.
  -h, --help                 Show this help.

Examples:
  zsh testapp/test_ios.zsh P14
  zsh testapp/test_ios.zsh P14 --no-build --showtime 10
  zsh testapp/test_ios.zsh P14 -- --debug
EOF_USAGE
}

if [ "$#" -eq 0 ]; then
    usage >&2
    exit 64
fi

if [ "$1" = -h ] || [ "$1" = --help ]; then
    usage
    exit 0
fi

target="$1"
shift
case "$target" in
    p*) target="${target:u}" ;;
esac
if [[ "$target" != P<-> ]]; then
    printf 'Invalid test target: %s\n' "$target" >&2
    usage >&2
    exit 64
fi

while [ "$#" -gt 0 ]; do
    case "$1" in
        -n|--no-build) do_build=0; shift ;;
        --showtime)
            if [ "$#" -lt 2 ] || ! [[ "$2" == <-> ]]; then
                printf 'Invalid --showtime value\n' >&2
                exit 64
            fi
            showtime_seconds="$2"
            shift 2
            ;;
        --no-showtime) showtime_seconds=0; shift ;;
        --device)
            if [ "$#" -lt 2 ] || [ -z "$2" ]; then
                printf '%s\n' '--device requires a name or UDID' >&2
                exit 64
            fi
            device_name="$2"
            shift 2
            ;;
        --actionfile)
            if [ "$#" -lt 2 ] || [[ "$2" == -* ]]; then
                candidates=("$script_dir/actions/ios/$target"-*.csv(N))
                if [ "${#candidates}" -ne 1 ]; then
                    printf 'Provide an iOS action file; no unique default exists for %s.\n' "$target" >&2
                    exit 64
                fi
                action_file="${candidates[1]}"
                shift
            else
                action_file="$2"
                shift 2
            fi
            ;;
        --actionfile=*) action_file="${1#*=}"; shift ;;
        --debug) app_args+=(--debug); shift ;;
        --)
            shift
            app_args+=("$@")
            break
            ;;
        -h|--help) usage; exit 0 ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            usage >&2
            exit 64
            ;;
    esac
done

if [ "$(uname -s)" != Darwin ]; then
    printf '%s\n' 'test_ios.zsh requires macOS.' >&2
    exit 1
fi

if [ ! -d "$template_dir" ]; then
    printf 'Missing iOS app template: %s\n' "$template_dir" >&2
    exit 1
fi

if [ -n "$action_file" ] && [ ! -f "$action_file" ]; then
    printf 'Missing iOS action file: %s\n' "$action_file" >&2
    exit 1
fi
if [ -n "$action_file" ]; then
    action_file="${action_file:A}"
fi

if [ "$do_build" -eq 1 ]; then
    printf '==> Building %s for the iOS Simulator\n' "$target"
    zsh "$script_dir/compile.zsh" -ios "$target"
fi

source_app="$output_dir/${target}-ios.app/$target"
if [ ! -f "$source_app" ]; then
    printf 'Missing iOS executable: %s\n' "$source_app" >&2
    printf 'Build it first with: zsh testapp/compile.zsh -ios %s\n' "$target" >&2
    exit 1
fi

# Keep one reusable assembled bundle in the checkout. This avoids copying a
# large temporary tree on every run; only the selected Pn executable is replaced.
# 在 checkout 中保留一份可重複使用的 assembled Bundle，避免每次執行都複製大型暫存樹；
# 每次只替換所選 Pn 的執行檔。
bundle_dir="$bundle_root/$app_name.app"
mkdir -p "$bundle_dir"
cp "$template_dir/Info.plist" "$bundle_dir/Info.plist"
cp "$template_dir/PkgInfo" "$bundle_dir/PkgInfo"
rm -f "$bundle_dir/$app_name"
cp "$source_app" "$bundle_dir/$app_name"
chmod +x "$bundle_dir/$app_name"

# The executable is replaced after the template was copied. Ad-hoc signing is
# sufficient for an iOS Simulator app and makes the generated bundle installable
# even when the source Pn bundle was signed under a different identity.
# 複製 template 後才替換執行檔。iOS Simulator 使用 ad-hoc signing 即可；即使來源 Pn
# 以不同 identity 簽署，重新簽署仍可讓產生的 Bundle 正常安裝。
codesign --force --deep --sign - "$bundle_dir" >/dev/null

printf '==> Booting Simulator: %s\n' "$device_name"
xcrun simctl boot "$device_name" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$device_name" -b

if printf '%s' "$device_name" | grep -Eq '^[0-9A-Fa-f-]{36}$'; then
    destination="platform=iOS Simulator,id=$device_name"
else
    destination="platform=iOS Simulator,name=$device_name"
fi

log_dir="$output_dir"
log_file="$log_dir/ios-$target-debugTarget.log"
: > "$log_file"

# `log stream` reads the unified log from the simulator. It is kept separate
# from launch output so the runner can return while the app remains interactive.
# `--style compact` keeps the recorded lines readable in a source checkout.
# `log stream` 讀取 Simulator 的 unified log。它獨立於 launch 輸出執行，因此 runner
# 結束後 app 仍可互動；`--style compact` 讓記錄檔在 source checkout 中保持易讀。
(
    xcrun simctl spawn "$device_name" log stream --style compact \
        --predicate "process == \"$app_name\"" >> "$log_file" 2>&1
) &
log_pid=$!
sleep 1

printf '==> Installing %s as %s\n' "$target" "$bundle_id"
xcrun simctl install "$device_name" "$bundle_dir"
if [ -z "$action_file" ]; then
    printf '==> Launching %s\n' "$bundle_id"
    xcrun simctl launch "$device_name" "$bundle_id" "${app_args[@]}"
fi

if [ -n "$action_file" ]; then
    xctest_root="$bundle_root/xcodeTestRunnerProject"
    mkdir -p "$xctest_root"
    cp -R "$xctest_project/iOSActionFileRunner.xcodeproj" "$xctest_root/"
    cp -R "$xctest_project/Host" "$xctest_root/"
    mkdir -p "$bundle_root/xcodeTestRunner"
    cp -R "$xctest_template/Tests" "$bundle_root/xcodeTestRunner/"
    xctest_build="$bundle_root/xcodeTestRunnerProject.build"
    printf '==> Replaying iOS action file: %s\n' "${action_file:t}"
    xcodebuild \
        -project "$xctest_root/iOSActionFileRunner.xcodeproj" \
        -scheme iOSActionFileRunner \
        -destination "$destination" \
        -derivedDataPath "$xctest_build" \
        build-for-testing

    xctestrun_path="$(find "$xctest_build/Build/Products" -name '*.xctestrun' -print -quit)"
    if [ -z "$xctestrun_path" ]; then
        printf '%s\n' 'XCUITest build succeeded but no .xctestrun file was produced.' >&2
        exit 1
    fi

    # Keep Xcode's generated host as the UI-test target. The test method then
    # launches debugTarget by its fixed bundle identifier.
    # 保留 Xcode 產生的 host 作為 UI-test target；測試方法再依固定 Bundle identifier
    # 啟動 debugTarget。
    xcrun simctl install "$device_name" "$bundle_dir"
    xcrun simctl launch "$device_name" "$bundle_id" "${app_args[@]}"
    /usr/libexec/PlistBuddy -c "Add :iOSActionFileRunner:TestingEnvironmentVariables:IOS_ACTION_FILE string $action_file" "$xctestrun_path" 2>/dev/null \
        || /usr/libexec/PlistBuddy -c "Set :iOSActionFileRunner:TestingEnvironmentVariables:IOS_ACTION_FILE $action_file" "$xctestrun_path"

    xcodebuild test-without-building \
        -xctestrun "$xctestrun_path" \
        -destination "$destination" \
        -only-testing:iOSActionFileRunner/ActionFileUITests/testActionFile
fi

if [ "$showtime_seconds" -gt 0 ]; then
    printf '==> Showing %s for %ss; press Ctrl-C to stop\n' "$target" "$showtime_seconds"
    trap 'kill "$log_pid" 2>/dev/null || true; wait "$log_pid" 2>/dev/null || true; exit 130' INT TERM
    sleep "$showtime_seconds"
fi

kill "$log_pid" 2>/dev/null || true
wait "$log_pid" 2>/dev/null || true
printf '==> Simulator log: %s\n' "$log_file"
