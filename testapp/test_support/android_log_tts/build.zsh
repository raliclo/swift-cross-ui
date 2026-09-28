#!/bin/zsh
# Builds SCUI log TTS -- a text-to-speech engine that logs every utterance and
# speaks none -- and, with --install, installs it and makes it the default engine
# on the connected device.
#
#   zsh testapp/test_support/android_log_tts/build.zsh [--install]
#
# Why it exists: a screen reader's speech used to be "someone has to listen".
# TalkBack speaks through the default engine, so with this one in place
# `adb logcat -s SCUI-TTS` is a transcript of what it said. No Gradle: javac, d8,
# aapt2 and apksigner from the SDK beside the repo, a throwaway debug key.
#
# 建置 SCUI log TTS——一個記下每一段朗讀、什麼都不唸的 TTS 引擎——加上 --install 時,安裝它並設為已連線裝置的預設
# 引擎。它存在的理由:螢幕閱讀器的朗讀以前只能「要有人聽」。TalkBack 經由預設引擎發聲,所以有了它,
# `adb logcat -s SCUI-TTS` 就是它唸了什麼的逐字稿。不用 Gradle:用 repo 旁 SDK 的 javac、d8、aapt2、apksigner,
# 以及一把用完即丟的 debug key。
set -euo pipefail

here="${0:a:h}"
repo="${here:h:h:h}"
sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-${repo:h}/.android-sdk}}"
tools="$sdk/build-tools/$(ls "$sdk/build-tools" | sort -V | tail -1)"
platform="$sdk/platforms/$(ls "$sdk/platforms" | sort -V | tail -1)/android.jar"
out="$repo/testapp/output/android_log_tts"
rm -rf "$out"
mkdir -p "$out/classes" "$out/dex"

javac --release 11 -classpath "$platform" -d "$out/classes" \
    "$here"/src/dev/swiftcrossui/logtts/*.java
"$tools/d8" --lib "$platform" --output "$out/dex" "$out"/classes/dev/swiftcrossui/logtts/*.class
"$tools/aapt2" compile --dir "$here/res" -o "$out/res.zip"
"$tools/aapt2" link -I "$platform" --manifest "$here/AndroidManifest.xml" \
    -o "$out/unsigned.apk" "$out/res.zip"
(cd "$out/dex" && zip -q "$out/unsigned.apk" classes.dex)
"$tools/zipalign" -f 4 "$out/unsigned.apk" "$out/aligned.apk"

key="$out/debug.keystore"
keytool -genkeypair -keystore "$key" -storepass android -keypass android \
    -alias logtts -keyalg RSA -keysize 2048 -validity 3650 \
    -dname "CN=SCUI log TTS" >/dev/null 2>&1
"$tools/apksigner" sign --ks "$key" --ks-pass pass:android --key-pass pass:android \
    --out "$out/scui-log-tts.apk" "$out/aligned.apk"
printf 'built %s\n' "$out/scui-log-tts.apk"

if [ "${1:-}" = "--install" ]; then
    adb="$sdk/platform-tools/adb"
    "$adb" install -r "$out/scui-log-tts.apk"
    "$adb" shell settings put secure tts_default_synth dev.swiftcrossui.logtts
    printf 'default TTS engine: %s\n' "$("$adb" shell settings get secure tts_default_synth)"
fi
