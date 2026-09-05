#!/usr/bin/env zsh
# Did the action file change anything, or did it only report that it ran?
#
#   zsh verify_effect_android.zsh            every action file
#   zsh verify_effect_android.zsh P10 P23    only those apps'
#
# Launches each app twice from the same APK -- once plain, once with
# `-actionfile` -- waits the same time for both, and compares the two
# screenshots. A difference is the action file's effect. Nothing else in the run
# differs.
#
# **This exists because the two cheaper checks were both inert.**
#
# `verify_replay_android.zsh` proves `-actionfile: replayed <name>` reached
# logcat for all 46. FAQ.md records a run where that line appeared and the app
# still showed `last action -> nothing yet`, so it is necessary and not
# sufficient. The first attempt at the sufficiency half grepped logcat for
# `last action ->` and found it for zero apps -- that text is drawn on screen,
# not logged, so the check could never have fired.
#
# The second attempt compared each app's `-1s-` and `-final-` screenshots from
# the sweep. Forty of forty-five differed by exactly zero pixels, which is not a
# small number: under `--no-showtime` test_android.zsh takes the two captures
# back to back, so they carry the same timestamp and the same md5. It was one
# photograph compared with itself.
#
# Both failures have the same shape as the release-plain probe in
# test_rootscroll_android.zsh: a check that cannot produce a positive is not a
# check. So this one waits long enough for a replay to finish and varies exactly
# one thing.
#
# 動作檔究竟改變了什麼,還是只是回報了它自己執行過?
#
# 本腳本以同一個 APK 啟動每支 app 兩次——一次不帶引數、一次帶 `-actionfile`——兩次等待相同時間,
# 然後比對兩張截圖。差異即是動作檔的效果。該次執行中沒有任何其他變因。
#
# **它之所以存在,是因為兩個較便宜的檢查都是空的。**
#
# `verify_replay_android.zsh` 證明了 46 支的 `-actionfile: replayed <名稱>` 都抵達了 logcat。而
# FAQ.md 記錄過一次執行:該行出現了,app 卻仍顯示 `last action -> nothing yet`,因此它是必要而
# 非充分條件。充分性那一半的第一次嘗試,是在 logcat 中 grep `last action ->`,結果零支命中——那段
# 文字是畫在畫面上的,不是記錄下來的,所以該檢查根本不可能觸發。
#
# 第二次嘗試改為比對 sweep 產生的 `-1s-` 與 `-final-` 兩張截圖。四十五支中有四十支的差異是恰好
# 零像素,而那不是一個小數字:在 `--no-showtime` 之下,test_android.zsh 是連續拍下這兩張的,因此
# 它們帶有相同的時間戳與相同的 md5。那是拿一張照片跟它自己比。
#
# 這兩次失敗與 test_rootscroll_android.zsh 裡那個 release-plain 探測器是同一種形狀:一個產生不出
# 正面結果的檢查,不是檢查。因此本腳本會等到重放足以完成,並且只變動一個變因。

set -uo pipefail

script_path="${0:a}"
script_dir="${script_path:h}"

serial="${ANDROID_SERIAL:-emulator-5554}"
android_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/Volumes/Windows/proj_Win/.android-sdk}}"
adb="$android_root/platform-tools/adb"
out_csv="$script_dir/output/android-effect${SCUI_RWD:+-rwd}.csv2"
settle="${SCUI_SETTLE_SECONDS:-16}"

if [ ! -x "$adb" ]; then
    print -u2 "adb not found at $adb; set ANDROID_HOME"
    exit 69
fi

# `${serial}`, not `$serial`; zsh reads `[...]` after a name as a subscript.
# 使用 `${serial}` 而非 `$serial`;zsh 會把緊接名稱的 `[...]` 讀作下標。
device_ready() {
    "$adb" devices 2>/dev/null | grep -qE "^${serial}[[:space:]]+device$"
}
device_ready || { print -u2 "no device at $serial"; exit 70; }

mkdir -p "$script_dir/output" "$script_dir/output/effect"

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
    w = csv.writer(handle)
    w.writerow(["app", "scenario", "changed_px", "max_delta", "bbox", "replayed", "verdict"])
    w.writerow(["應用程式", "情境", "相異像素", "最大差", "範圍", "已重放", "判定"])
PY

append_row() {
    python3 - "$out_csv" "$@" <<'PY'
import csv, sys
with open(sys.argv[1], "a", newline="") as handle:
    csv.writer(handle).writerow(sys.argv[2:])
PY
}

# `SCUI_RWD=1` photographs the whole page instead of the visible part of it.
#
# Without it this compares the default scroll position, and 27 of the 46
# scenarios have content outside the viewport -- up to 2.65 times its width on
# P6. A change the action file makes off-screen then reads as "no effect", which
# is a statement about the camera and not about the app. P3 is the case that
# showed it: its test image reported zero coloured pixels in the visible frame
# and 4,735 once the page was scaled in. The image had rendered the whole time.
#
# rwdView is reached by tapping the control, whose position is fixed at
# `[21,147][252,273]` -- below the status bar, see RootScrollHost.kt -- so the
# tap needs no lookup. It is only available when
# `DebugFeatures.allowsRootScrollControl` is true, which a SCUI_DEBUG build is.
#
# `SCUI_RWD=1` 拍的是整頁,而不是它可見的那一部分。
#
# 若不啟用,本檢查比對的是預設捲動位置,而 46 個情境中有 27 個的內容位於視口之外——P6 甚至達到視口
# 寬度的 2.65 倍。動作檔在畫面外造成的改變,於是被讀成「無效果」,而那是一句關於相機的陳述,不是關於
# app 的。P3 就是揭露此事的案例:它的測試圖在可見畫面中回報零個彩色像素,把整頁縮放進來之後則是
# 4,735 個。那張圖自始至終都算繪出來了。
#
# rwdView 是靠點擊該控制項進入的,而它的位置固定在 `[21,147][252,273]`——位於狀態列之下,見
# RootScrollHost.kt——因此這次點擊不需要任何查找。它僅在
# `DebugFeatures.allowsRootScrollControl` 為真時存在,而 SCUI_DEBUG 建置正是如此。
shoot() {
    local package="$1" args="$2" dest="$3"
    "$adb" -s "$serial" shell am force-stop "$package" >/dev/null 2>&1
    "$adb" -s "$serial" logcat -c >/dev/null 2>&1
    if [ -n "$args" ]; then
        "$adb" -s "$serial" shell am start -W -n "$package/.MainActivity" \
            --es scui_args "'$args'" >/dev/null 2>&1
    else
        "$adb" -s "$serial" shell am start -W -n "$package/.MainActivity" >/dev/null 2>&1
    fi
    sleep "$settle"
    if [ "${SCUI_RWD:-0}" = "1" ]; then
        "$adb" -s "$serial" shell input tap 136 210 >/dev/null 2>&1
        sleep 3
    fi
    "$adb" -s "$serial" exec-out screencap -p > "$dest"
}

changed=0
inert=0
failed=0

printf "%-6s %-34s %-12s %-9s %s\n" app scenario "changed px" "max d" verdict
print -- "--------------------------------------------------------------------------------"

for action in $action_files; do
    base="${action:t:r}"
    app="${base%%-*}"
    scenario="${base#*-}"
    package="dev.swiftcrossui.testapp.${app:l}"
    apk="$script_dir/.androidApk/$app.apk"

    [ -f "$apk" ] || { failed=$((failed+1)); continue }

    "$adb" -s "$serial" install -r -d "$apk" >/dev/null 2>&1
    "$adb" -s "$serial" push "$action" "/data/local/tmp/$app-actions.csv" >/dev/null 2>&1

    plain="$script_dir/output/effect/$base${SCUI_RWD:+-rwd}-plain.png"
    driven="$script_dir/output/effect/$base${SCUI_RWD:+-rwd}-driven.png"

    shoot "$package" "" "$plain"
    shoot "$package" "--debug -actionfile /data/local/tmp/$app-actions.csv" "$driven"
    replay_lines=$("$adb" -s "$serial" logcat -d 2>/dev/null | grep -c "actionfile: replayed") \
        || replay_lines=0

    read -r px maxd bbox <<< "$(python3 - "$plain" "$driven" <<'PY'
import sys
from PIL import Image, ImageChops
try:
    a = Image.open(sys.argv[1]).convert("RGB")
    b = Image.open(sys.argv[2]).convert("RGB")
except Exception:
    print("-1 -1 unreadable"); raise SystemExit
if a.size != b.size:
    print("-1 -1 size-differs"); raise SystemExit
d = ImageChops.difference(a, b)
# The status-bar clock changes between two launches whatever the app does.
# 狀態列的時鐘在兩次啟動之間本來就會變,與 app 做了什麼無關。
d.paste((0, 0, 0), (0, 0, a.size[0], 130))
px = sum(1 for p in d.get_flattened_data() if p != (0, 0, 0))
print(px, max(x[1] for x in d.getextrema()), d.getbbox() or "none")
PY
)"

    if [ "${px:-0}" -gt 2000 ]; then
        verdict="action file changed the screen"; changed=$((changed+1))
    elif [ "${px:-0}" -lt 0 ]; then
        verdict="could not compare"; failed=$((failed+1))
    else
        verdict="NO EFFECT"; inert=$((inert+1))
    fi

    append_row "$app" "$scenario" "$px" "$maxd" "$bbox" "$replay_lines" "$verdict"
    printf "%-6s %-34s %-12s %-9s %s\n" "$app" "${scenario:0:33}" "$px" "$maxd" "$verdict"

    "$adb" -s "$serial" shell am force-stop "$package" >/dev/null 2>&1
    "$adb" -s "$serial" uninstall "$package" >/dev/null 2>&1
done

print
print "$changed changed the screen, $inert had no effect, $failed could not be compared"
print "Screenshots: $script_dir/output/effect/"
print "CSV: $out_csv"
print "EFFECT VERIFY COMPLETE"
