#!/usr/bin/env zsh
# Package one test app, already compiled by `compile.zsh -android`, as an APK --
# without Swift Bundler.
#
#   zsh testapp/package_android.zsh <Pn> <output.apk>
#
# test_android.zsh calls this after compile.zsh. The environment it expects is
# the one test_android.zsh already sets: ANDROID_HOME, ANDROID_NDK_HOME,
# ANDROID_TRIPLE, SWIFT_BIN, BUILD_CONFIG.
#
# **What it replaces, and why.** Swift Bundler ran a second `swift build` of
# every app in its own scratch tree (.build-bundler, 24 GB of release objects
# beside compile.zsh's .build), then generated a Gradle project for the app,
# deleted it on the next bundle and generated it again. This script takes the
# product compile.zsh has just linked, relinks it as a shared library, and
# builds one Gradle project that stays (testapp/androidContainer/gradleProject,
# copied to .compile-work-android/gradleProject). The steps are the bundler's,
# in the bundler's order (Vendor/swift-bundler/.../APKBundler.swift), so the APK
# carries the same things:
#
#   1. relink the executable as lib<Pn>.so, with an soname, from SwiftPM's own
#      link command in .build/<config>.yaml
#   2. lib<Pn>.so into jniLibs, with .swift_ast removed (SCUI_KEEP_SWIFT_AST=1
#      keeps it, as the bundler patch did)
#   3. every shared library it needs, found with llvm-readelf, copied unless
#      the device ships it
#   4. libshim.so: MainActivity.setup() -> AndroidBackend_entrypoint
#   5. AndroidBackend's Kotlin into the project
#   6. AndroidManifest.xml with the permissions from Bundler.android.toml
#   7. gradlew assembleDebug, with the app passed in as -P properties
#
# 打包一支已由 `compile.zsh -android` 編好的測試 app 成 APK,不經 Swift Bundler。Swift Bundler 會在自己的
# scratch 樹(.build-bundler,在 compile.zsh 的 .build 旁邊另有 24 GB 的 release 物件)把每支 app 再
# `swift build` 一次，接著為該 app 產生 Gradle 專案，下一次打包時刪掉再重新產生。本腳本取用 compile.zsh 剛
# 連結好的 product,重新連結成共享函式庫，並建置一個會留著的 Gradle 專案。步驟與 bundler 相同、順序相同，
# 因此 APK 帶有相同的內容。

set -euo pipefail

app="${1:?usage: package_android.zsh <Pn> <output.apk>}"
output_apk="${2:?usage: package_android.zsh <Pn> <output.apk>}"

script_dir="${0:A:h}"
repo_root="${script_dir:h}"
container="$script_dir/androidContainer"
template="$container/gradleProject"
settings_toml="$container/Bundler.android.toml"
package_dir="$script_dir/.compile-work-android/TestApps"
project="$script_dir/.compile-work-android/gradleProject"

die() { print -u2 -r -- "[error] $1"; exit 1; }

: "${ANDROID_HOME:?ANDROID_HOME is not set}"
: "${ANDROID_NDK_HOME:?ANDROID_NDK_HOME is not set}"
triple="${ANDROID_TRIPLE:-aarch64-unknown-linux-android31}"
config="${BUILD_CONFIG:-release}"
api="${triple##*android}"
products="$package_dir/.build/$triple/$config"
executable="$products/$app"
library="$products/lib$app.so"
build_plan="$package_dir/.build/$config.yaml"

[ -f "$executable" ] || die "$executable is missing; run compile.zsh -android $app first"
[ -f "$build_plan" ] || die "$build_plan is missing; it is written by the same swift build"

ndk_bin="$(print -r -- "$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/*/bin(N[1]))"
[ -d "$ndk_bin" ] || die "no LLVM toolchain under $ANDROID_NDK_HOME/toolchains/llvm/prebuilt"
readelf="$ndk_bin/llvm-readelf"
objcopy="$ndk_bin/llvm-objcopy"
clang="$ndk_bin/clang"

# The Swift SDK the build used: the one artifact bundle, as compile.zsh insists
# (SwiftPM 6.4 refuses to build with two installed).
# 建置所用的 Swift SDK:唯一的那個 artifact bundle,與 compile.zsh 的要求相同(裝了兩個時 SwiftPM 6.4 拒絕建置)。
sdk_bundles=("$HOME"/Library/org.swift.swiftpm/swift-sdks/*android.artifactbundle(N/))
(( ${#sdk_bundles} == 1 )) || die "expected one Swift Android SDK, found ${#sdk_bundles}"
swift_sdk="${sdk_bundles[1]}/swift-android"
abi_dir="aarch64-linux-android"

# ---------------------------------------------------------------- 1. relink
# SwiftPM's link command for the executable, from the build plan it just ran,
# turned into a shared library: -emit-executable out, -emit-library and an
# soname in. Without the soname the shim records the host path of the library
# and the device's loader cannot find it (the bundler's own note on this).
# Taken from the plan rather than written out, so the flags -- the SDK, the
# resource dir, `main=Pn_main` -- are always the ones the build used.
# SwiftPM 剛執行過的 build plan 裡該執行檔的連結指令，改成共享函式庫:拿掉 -emit-executable,加上
# -emit-library 與 soname。少了 soname,shim 會記下該函式庫在主機上的路徑，裝置的載入器就找不到它。
# 從 plan 取用而非自己寫，因此旗標永遠是建置時所用的那些。
print "==> Linking lib$app.so"
#
# Read by scanning for the one command, not by loading the YAML: the plan is
# 111 MB, and yaml.safe_load took 17.5 s of every app's build (2026-10-05)
# against 0.04 s for this. SwiftPM writes each `args:` as a single JSON-style
# flow list, which json.loads reads as is.
# 以掃描找出那一條指令來讀，而不是載入整份 YAML:plan 有 111 MB,yaml.safe_load 佔掉每支 app 建置的
# 17.5 秒(2026-10-05),這裡只要 0.04 秒。SwiftPM 把每個 `args:` 寫成單行 JSON 風格的 flow list,
# json.loads 可以直接讀。
link_args=("${(@f)$(python3 - "$build_plan" "$app" "$triple" "$config" "$library" <<'EOF'
import sys, json
plan, app, triple, config, out = sys.argv[1:]
wanted = {f'  "C.{app}-{triple}-{config}.exe":\n', f'  "C.{app}-{config}.exe":\n'}
args = None
with open(plan) as f:
    for line in f:
        if line in wanted:
            break
    for line in f:
        if not line.startswith("    "):
            break
        if line.lstrip().startswith("args: "):
            args = json.loads(line.lstrip()[len("args: "):])
            break
if args is None:
    sys.exit(f"no link command for {app} in {plan}")
i = args.index("-o")
del args[i:i + 2]
args = [a for a in args if a != "-emit-executable"]
args += ["-emit-library", "-o", out, "-Xlinker", "-soname", "-Xlinker", f"lib{app}.so"]
print("\n".join(args))
EOF
)}")
(( ${#link_args} > 1 )) || die "could not read the link command for $app"
(cd "$package_dir" && "${link_args[@]}")
[ -f "$library" ] || die "linking did not produce $library"

# ---------------------------------------------------------------- project
# The template over the working copy, keeping Gradle's build/ and .gradle/ so
# the next app reuses them. local.properties is per machine.
# 範本覆蓋到工作副本上，保留 Gradle 的 build/ 與 .gradle/,讓下一支 app 重用它們。local.properties 依機器而定。
mkdir -p "$project"
rsync -a --exclude build --exclude .gradle --exclude .kotlin \
    --exclude src/main/kotlin --exclude src/main/jniLibs --exclude src/main/AndroidManifest.xml \
    "$template/" "$project/"
print -r -- "sdk.dir=$ANDROID_HOME" > "$project/local.properties"

# ---------------------------------------------------------------- 2-4. jniLibs
# Emptied first: the previous app's lib<Pn>.so must not ride along.
# 先清空：上一支 app 的 lib<Pn>.so 不能跟著打包進去。
jni="$project/src/main/jniLibs/arm64-v8a"
[[ "$jni" == */.compile-work-android/gradleProject/src/main/jniLibs/arm64-v8a ]] || die "unexpected jniLibs path $jni"
rm -rf -- "$jni"
mkdir -p "$jni"
cp "$library" "$jni/"

if [[ "${SCUI_KEEP_SWIFT_AST:-0}" == (1|true) ]]; then
    print "==> SCUI_KEEP_SWIFT_AST is set; leaving .swift_ast in lib$app.so"
else
    "$objcopy" --remove-section=.swift_ast "$jni/lib$app.so"
fi

# Dependencies, breadth first, searched where the bundler searched: the build's
# products, the SDK's Swift runtime, the sysroot (copied) and the sysroot's
# per-API directory (shipped by the device, not copied).
# 相依函式庫，逐層找，搜尋位置與 bundler 相同：建置產物、SDK 的 Swift runtime、sysroot(複製),以及
# sysroot 依 API 分的目錄(裝置自帶，不複製)。
search_copy=("$products" "$swift_sdk/swift-resources/usr/lib/swift-aarch64/android"
    "$swift_sdk/ndk-sysroot/usr/lib/$abi_dir")
search_system=("$swift_sdk/ndk-sysroot/usr/lib/$abi_dir/$api")
typeset -A seen
queue=("$library")
copied=0
while (( ${#queue} )); do
    current="${queue[1]}"; queue=("${(@)queue[2,-1]}")
    for needed in ${(f)"$("$readelf" -d "$current" | sed -n 's/.*(NEEDED).*\[\(.*\)\].*/\1/p')"}; do
        [[ -n "${seen[$needed]:-}" ]] && continue
        seen[$needed]=1
        found=""
        for d in $search_copy; do
            if [ -f "$d/$needed" ]; then found="$d/$needed"; break; fi
        done
        if [ -n "$found" ]; then
            cp "$found" "$jni/$needed"
            copied=$((copied + 1))
            queue+=("$found")
            continue
        fi
        for d in $search_system; do
            [ -f "$d/$needed" ] && { found=system; break; }
        done
        [ -n "$found" ] || die "lib$app.so needs $needed and it is in none of: $search_copy $search_system"
    done
done
print "==> $copied shared libraries copied beside lib$app.so"

"$clang" --target="$triple" -shared -fPIC -o "$jni/libshim.so" \
    "$project/shim/shim.c" -L"$jni" -l"$app"

# ---------------------------------------------------------------- 5. Kotlin
# Mirrored, so a file deleted from Sources is deleted here too.
# 以鏡像同步，Sources 裡刪掉的檔案這裡也會刪掉。
mkdir -p "$project/src/main/kotlin"
rsync -a --delete --include '*/' --include '*.kt' --exclude '*' \
    "$repo_root/Sources/AndroidBackend/Kotlin/" "$project/src/main/kotlin/"

# ---------------------------------------------------------------- 6-7. Gradle
# SDK levels and permissions from Bundler.android.toml, the file that already
# decides them; the manifest is written only when it changes, so Gradle sees an
# unchanged input across apps.
# SDK level 與權限取自 Bundler.android.toml,即本來就決定它們的那個檔案；manifest 只在內容改變時才寫，
# 因此換 app 時 Gradle 看到的輸入不變。
gradle_props=("${(@f)$(python3 - "$settings_toml" "$project/src/main/AndroidManifest.xml" <<'EOF'
import sys, tomllib, pathlib
settings = tomllib.load(open(sys.argv[1], "rb"))
manifest = pathlib.Path(sys.argv[2])
permissions = "".join(
    f'    <uses-permission android:name="{p if "." in p else "android.permission." + p}" />\n'
    for p in settings.get("permissions", []))
# One VIEW filter per URL scheme, so a link reaches the app (BackendFeatures.IncomingURLs).
# singleTop on the activity, so a link while the app is in front arrives as onNewIntent
# rather than as a second activity on top of the first.
# 每個 URL scheme 一個 VIEW filter,讓連結能到達 app;activity 設 singleTop,app 在前景時的連結會以
# onNewIntent 送達，而不是在第一個 activity 上再疊一個。
url_filters = "".join(
    "            <intent-filter>\n"
    "                <action android:name=\"android.intent.action.VIEW\" />\n"
    "                <category android:name=\"android.intent.category.DEFAULT\" />\n"
    "                <category android:name=\"android.intent.category.BROWSABLE\" />\n"
    f"                <data android:scheme=\"{scheme}\" />\n"
    "            </intent-filter>\n"
    for scheme in settings.get("url_schemes", []))
text = f'''<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">
{permissions}    <application
        android:allowBackup="true"
        android:icon="@mipmap/icon"
        android:label="@string/app_name"
        android:theme="@style/Theme.AppTheme"
        tools:targetApi="{settings["target_sdk"]}">
        <activity android:name=".MainActivity" android:exported="true"
            android:launchMode="singleTop">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
{url_filters}        </activity>
        <service
            android:name="dev.swiftcrossui.androidbackend.OverlayService"
            android:exported="false"
            android:foregroundServiceType="specialUse" />
    </application>
</manifest>
'''
if not manifest.exists() or manifest.read_text() != text:
    manifest.write_text(text)
print(f"-PscuiMinSdk={settings['min_sdk']}")
print(f"-PscuiTargetSdk={settings['target_sdk']}")
print(f"-PscuiCompileSdk={settings['compile_sdk']}")
EOF
)}")

application_id="dev.swiftcrossui.testapp.${${app//-/}:l}"
version_code="$(git -C "$repo_root" rev-list --count HEAD)"

print "==> Gradle: $application_id"
(
    cd "$project"
    # stdin closed: with it open gradlew can hang after the build has finished,
    # which the bundler worked around the same way.
    # 關閉 stdin:開著時 gradlew 可能在建置完成後仍掛住,bundler 也是這樣繞過的。
    ./gradlew assembleDebug --console=plain \
        "${gradle_props[@]}" \
        -PscuiApplicationId="$application_id" \
        -PscuiAppName="$app" \
        -PscuiVersionCode="$version_code" </dev/null
)

built="$project/build/outputs/apk/debug/TestApps-debug.apk"
[ -f "$built" ] || die "Gradle finished but $built is missing"
mkdir -p "${output_apk:h}"
cp "$built" "$output_apk"
print "    -> $output_apk"
