#!/usr/bin/env zsh
# Did the action file actually replay, or was it only pushed?
#
#   zsh verify_replay_android.zsh            every action file
#   zsh verify_replay_android.zsh P10 P23    only those apps'
#
# sweep_android.zsh records that an app built, launched and produced
# screenshots. None of those answer this question. Its log shows
# `==> Pushing .../P17-....csv -> /data/local/tmp/P17-actions.csv` and then the
# launch, which proves the file reached the device and the extra was sent -- not
# that a single event was replayed. The confirmation is a line on stderr,
# `-actionfile: replayed <name>`, and stderr goes to logcat, which the sweep
# cleared for each app and never read for this.
#
# **`replayed` is necessary and not sufficient.** FAQ.md records a run that
# logged `action file replayed` while the screenshot still read
# `last action -> nothing yet`: the replay completed and the events landed
# nowhere. So this reports the count of replayed lines and, when the app prints
# one, its own last-action line, and it does not call the pair a pass.
#
# No rebuilds. The APKs in .androidApk/ are the ones the sweep just produced, so
# this installs, drives and uninstalls -- about half a minute an app instead of
# two and a half.
#
# 動作檔究竟有沒有真的重放，還是只是被推送過去而已？
#
# sweep_android.zsh 記錄的是「app 建置了、啟動了、產出了截圖」。這三件事沒有一件回答得了這個問題。
# 它的日誌顯示 `==> Pushing .../P17-....csv -> /data/local/tmp/P17-actions.csv` 以及隨後的啟動，那
# 證明了檔案抵達裝置、extra 被送出——而不是任何一個事件真的被重放。確認訊息是 stderr 上的
# `-actionfile: replayed <名稱>`，而 stderr 進入 logcat，那正是 sweep 為每支 app 清掉、且從未為此
# 讀取過的東西。
#
# **`replayed` 是必要條件，不是充分條件。** FAQ.md 記錄過一次執行：它記錄了
# `action file replayed`，而截圖仍顯示 `last action -> nothing yet`——重放完成了，事件卻沒有落到
# 任何地方。因此本腳本回報的是 replayed 行的數量，以及（當 app 有印時）它自己的 last-action 行，
# 並且不把這兩者合稱為通過。
#
# 不重新建置。`.androidApk/` 中的 APK 正是 sweep 剛剛產出的那些，因此此處只做安裝、驅動、解除安裝
# ——每支約半分鐘，而不是兩分半。

set -uo pipefail

script_path="${0:a}"
script_dir="${script_path:h}"

serial="${ANDROID_SERIAL:-emulator-5554}"
android_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/Volumes/Windows/proj_Win/.android-sdk}}"
adb="$android_root/platform-tools/adb"
out_csv="$script_dir/output/android-replay.csv2"

if [ ! -x "$adb" ]; then
    print -u2 "adb not found at $adb; set ANDROID_HOME"
    exit 69
fi

# `${serial}`, not `$serial`. zsh reads `[...]` after a parameter name as a
# subscript even inside double quotes; see sweep_android.zsh.
# 使用 `${serial}` 而非 `$serial`。zsh 即使在雙引號內也會把緊接參數名的 `[...]` 讀作下標；
# 見 sweep_android.zsh。
device_ready() {
    "$adb" devices 2>/dev/null | grep -qE "^${serial}[[:space:]]+device$"
}

if ! device_ready; then
    print -u2 "no device at $serial"
    exit 70
fi

mkdir -p "$script_dir/output"

if [ "$#" -gt 0 ]; then
    action_files=()
    for wanted in "$@"; do
        action_files+=(${(f)"$(ls "$script_dir"/actions/android/${wanted}-*.csv 2>/dev/null)"})
    done
else
    action_files=(${(f)"$(ls "$script_dir"/actions/android/*.csv \
        | sed 's|.*/||' | sort -t P -k2 -n | sed "s|^|$script_dir/actions/android/|")"})
fi

python3 - "$out_csv" <<'PY'
import csv, sys
with open(sys.argv[1], "w", newline="") as handle:
    writer = csv.writer(handle)
    writer.writerow(["app", "scenario", "installed", "replayed_lines", "replayed_what", "app_report", "verdict"])
    writer.writerow(["應用程式", "情境", "已安裝", "replayed 行數", "重放了什麼", "app 自述", "判定"])
PY

append_row() {
    python3 - "$out_csv" "$@" <<'PY'
import csv, sys
with open(sys.argv[1], "a", newline="") as handle:
    csv.writer(handle).writerow(sys.argv[2:])
PY
}

count_in_text() {
    local n
    n=$(print -r -- "$1" | grep -c -- "$2") || n=0
    print "${n:-0}"
}

# Close the system UI a previous run may have left on top.
#
# `am force-stop <the test app>` stops the test app and nothing else, and the
# file dialog P18 opens is not the test app: it is
# `com.google.android.documentsui/PickActivity`, a separate package. It survives
# the force-stop, stays the resumed activity, and swallows the next launch --
# the app starts behind it, never resumes, and the Swift entrypoint never
# reaches the replay.
#
# Demonstrated 2026-09-06: with the picker on top, P18 logged zero
# `actionfile: replayed` lines; `am force-stop com.google.android.documentsui`
# and the identical command logged one. That is the whole of the "P18 fails in a
# batch and passes alone" behaviour, which was first written down as an emulator
# intermittent on the strength of one failure and three passes.
#
# 關掉先前執行可能留在最上層的系統介面。
#
# `am force-stop <測試 app>` 只會停止該測試 app,而 P18 所開啟的檔案對話框並不是測試 app:它是
# `com.google.android.documentsui/PickActivity`,屬於另一個套件。它會在 force-stop 之後存活、
# 維持為 resumed activity,並吞掉下一次啟動——app 會在它後面啟動、永遠不會 resume,而 Swift 的
# 進入點也就從未走到重放。
#
# 2026-09-06 實證:選擇器在最上層時,P18 記錄了零行 `actionfile: replayed`;執行
# `am force-stop com.google.android.documentsui` 之後,完全相同的指令記錄了一行。這就是
# 「P18 在批次中失敗、單獨執行則通過」的全部成因——而它最初依據「一次失敗與三次通過」被寫成了
# 模擬器偶發。
close_leftover_system_ui() {
    for leftover in com.google.android.documentsui com.android.documentsui; do
        "$adb" -s "$serial" shell am force-stop "$leftover" >/dev/null 2>&1
    done
}

replayed=0
silent=0
missing=0

printf "%-6s %-34s %-10s %-8s %s\n" app scenario installed lines "replayed / why not"
print -- "----------------------------------------------------------------------------------"

for action in $action_files; do
    base="${action:t:r}"
    # The longest prefix that names a real app, not the first segment. See the
    # note in verify_effect_ios.zsh: `${base%%-*}` launched P15 for
    # P15-DARK-the-override-survives-a-tap, and both apps exist.
    # 取「能對應到真實 app 的最長前綴」,而不是第一段。見 verify_effect_ios.zsh 中的說明:
    # `${base%%-*}` 會為 P15-DARK-the-override-survives-a-tap 啟動 P15,而兩支 app 都是存在的。
    app=""
    candidate="$base"
    while [ -n "$candidate" ]; do
        if [ -f "$script_dir/$candidate.swift" ]; then app="$candidate"; break; fi
        [[ "$candidate" == *-* ]] || break
        candidate="${candidate%-*}"
    done
    [ -n "$app" ] || app="${base%%-*}"
    scenario="${base#*-}"
    package="dev.swiftcrossui.testapp.${app:l}"
    apk="$script_dir/.androidApk/$app.apk"

    if [ ! -f "$apk" ]; then
        missing=$((missing + 1))
        append_row "$app" "$scenario" "no apk" 0 "" "" "not run"
        printf "%-6s %-34s %-10s %-8s %s\n" "$app" "${scenario:0:33}" "no apk" 0 "never built"
        continue
    fi

    "$adb" -s "$serial" shell am force-stop "$package" >/dev/null 2>&1
    close_leftover_system_ui
    "$adb" -s "$serial" install -r -d "$apk" >/dev/null 2>&1
    installed=$?

    "$adb" -s "$serial" push "$action" "/data/local/tmp/$app-actions.csv" >/dev/null 2>&1
    "$adb" -s "$serial" logcat -c >/dev/null 2>&1

    # The inner quotes are for the shell **on the device**: `adb shell` joins its
    # arguments into one command line that the device's shell re-splits. Without
    # them `am` reads `-actionfile` as `-a ctionfile`. Same reasoning as
    # test_android.zsh, and the same failure if it is dropped.
    # 內層引號是給**裝置上的** shell 的：`adb shell` 會把它的引數併成一行命令，再由裝置端的 shell
    # 重新斷詞。少了它們，`am` 會把 `-actionfile` 讀成 `-a ctionfile`。理由與 test_android.zsh 相同，
    # 少了它也會以相同的方式失敗。
    "$adb" -s "$serial" shell am start -W -n "$package/.MainActivity" \
        --es scui_args "'--debug -actionfile /data/local/tmp/$app-actions.csv'" >/dev/null 2>&1

    sleep 12

    log=$("$adb" -s "$serial" logcat -d 2>/dev/null)
    lines=$(count_in_text "$log" "actionfile: replayed")
    what=$(print -r -- "$log" | grep -o "actionfile: replayed [^ ]*" | tail -1 | sed 's/.*replayed //')
    report=$(print -r -- "$log" | grep -oE "last action -> [^\"]*" | tail -1 | head -c 60)

    if [ "${lines:-0}" -ge 1 ]; then
        verdict="replayed"
        replayed=$((replayed + 1))
    else
        verdict="no replay line"
        silent=$((silent + 1))
    fi

    append_row "$app" "$scenario" "$([ "$installed" -eq 0 ] && print yes || print FAILED)" \
        "$lines" "$what" "$report" "$verdict"
    printf "%-6s %-34s %-10s %-8s %s\n" "$app" "${scenario:0:33}" \
        "$([ "$installed" -eq 0 ] && print yes || print FAILED)" "$lines" "$what$report"

    "$adb" -s "$serial" shell am force-stop "$package" >/dev/null 2>&1
    "$adb" -s "$serial" uninstall "$package" >/dev/null 2>&1
done

print
print "$replayed replayed, $silent with no replay line, $missing never built, of ${#action_files[@]}"
print "CSV: $out_csv"
print "REPLAY VERIFY COMPLETE"
