#!/usr/bin/env zsh
# Did the iOS action file change anything, or did it only report that it ran?
#
#   zsh verify_effect_ios.zsh            every iOS action file
#   zsh verify_effect_ios.zsh P10 P23    only those apps'
#
# Runs each app twice through the XCUITest runner -- once with
# `actions/ios/_control-no-actions.csv`, which presses nothing, and once with the
# real file -- and compares the two final captures.
#
# **The control is a no-op action file, not a plain launch.** On iOS a run with
# an action file is started by XCUITest and a run without one by `simctl
# launch`, so comparing those two would vary the launch path and the elapsed
# time as well as the actions. Any difference could then be attributed to any of
# the three. Both runs here take the same route and differ only in whether there
# are rows to press.
#
# This is the third layer of evidence and the other two do not imply it:
#
#   the runner logs `replaying <file> with <n> actions`   the file was read
#   XCUITest reports EXECUTE SUCCEEDED, 0 failures        the actions ran
#   this script                                            the app looks different
#
# The 2026-09-07 sweep established the first two for all 48 files -- 190 actions,
# no failures. It could not establish the third, because with an action file
# `test_ios.zsh` skips its one-second capture and only a final one exists, so
# there was nothing to compare a final against.
#
# iOS 的動作檔究竟改變了什麼,還是只是回報了它自己執行過?
#
# 本腳本讓每支 app 各經由 XCUITest runner 執行兩次——一次使用
# `actions/ios/_control-no-actions.csv`(不按任何東西),一次使用真正的檔案——然後比對兩張最終擷取。
#
# **對照組是一份空的動作檔,而不是一次普通啟動。** 在 iOS 上,帶動作檔的執行由 XCUITest 啟動,不帶的
# 則由 `simctl launch` 啟動;若拿那兩者比對,變動的就不只是動作,還包括啟動路徑與經過時間,而任何
# 差異都可以被歸給這三者中的任何一個。此處兩次執行走的是同一條路徑,唯一的差別是有沒有可按的列。
#
# 這是第三層證據,而前兩層並不蘊涵它:
#
#   runner 記錄 `replaying <檔案> with <n> actions`   檔案被讀取了
#   XCUITest 回報 EXECUTE SUCCEEDED、0 failures        那些動作執行了
#   本腳本                                             該 app 看起來不同了
#
# 2026-09-07 的全掃為全部 48 份檔案確立了前兩層——190 個動作、零失敗。它無法確立第三層,因為在帶
# 動作檔時 `test_ios.zsh` 會跳過它的一秒擷取、只留下一張最終擷取,於是沒有東西可以與那張最終擷取比對。

set -uo pipefail

script_path="${0:a}"
script_dir="${script_path:h}"

control="$script_dir/actions/ios/_control-no-actions.csv"
out_csv="$script_dir/output/ios-effect.csv2"
shots="$script_dir/output/screenshots"
keep="$script_dir/output/effect-ios"

if [ ! -f "$control" ]; then
    print -u2 "missing control file: $control"
    exit 66
fi

mkdir -p "$keep" "$script_dir/output"

if [ "$#" -gt 0 ]; then
    action_files=()
    for wanted in "$@"; do
        action_files+=(${(f)"$(ls "$script_dir"/actions/ios/${wanted}-*.csv 2>/dev/null)"})
    done
else
    action_files=(${(f)"$(ls "$script_dir"/actions/ios/P*.csv \
        | sed 's|.*/||' | sort -t P -k2 -n | sed "s|^|$script_dir/actions/ios/|")"})
fi

# Only rewritten for a full pass; naming apps appends.
#
# The Android verifier truncated its own CSV on every invocation, and three
# re-runs of one app to chase an intermittent left the file holding one row of
# forty-six. See mistakes.csv2, entry 89.
#
# 只有完整執行才會重寫;指名個別 app 時改為追加。
#
# Android 的驗證器在每次呼叫時都會截斷自己的 CSV,而為了追查一個偶發問題而重跑三次某支 app,
# 就讓那個檔案從四十六列只剩一列。見 mistakes.csv2 第 89 條。
if [ "$#" -eq 0 ] || [ ! -f "$out_csv" ]; then
    python3 - "$out_csv" <<'PY'
import csv, sys
with open(sys.argv[1], "w", newline="") as handle:
    w = csv.writer(handle)
    w.writerow(["app", "scenario", "changed_px", "max_delta", "bbox", "actions", "verdict"])
    w.writerow(["應用程式", "情境", "相異像素", "最大差", "範圍", "動作數", "判定"])
PY
fi

append_row() {
    python3 - "$out_csv" "$@" <<'PY'
import csv, sys
with open(sys.argv[1], "a", newline="") as handle:
    csv.writer(handle).writerow(sys.argv[2:])
PY
}

newest_final() {
    ls -t "$shots"/${1:l}-ios-final-*.png 2>/dev/null | head -1
}

run_with() {
    local app="$1" file="$2" dest="$3" log="$4"
    SCUI_DEBUG=1 zsh "$script_dir/test_ios.zsh" "$app" \
        --actionfile "$file" --no-showtime > "$log" 2>&1
    local shot
    shot="$(newest_final "$app")"
    [ -n "$shot" ] && cp "$shot" "$dest"
    grep -oE "replaying \S+ with [0-9]+ actions" "$log" | grep -oE "^[0-9]+" >/dev/null 2>&1
}

changed=0
inert=0
failed=0

printf "%-6s %-34s %-12s %-8s %s\n" app scenario "changed px" actions verdict
print -- "--------------------------------------------------------------------------------"

for action in $action_files; do
    base="${action:t:r}"
    app="${base%%-*}"
    scenario="${base#*-}"
    [ -f "$script_dir/$app.swift" ] || { failed=$((failed + 1)); continue }

    plain="$keep/$base-control.png"
    driven="$keep/$base-driven.png"

    run_with "$app" "$control" "$plain" "/tmp/ios-effect-$base-control.log"
    run_with "$app" "$action" "$driven" "/tmp/ios-effect-$base-driven.log"

    acts=$(grep -oE "with [0-9]+ actions" "/tmp/ios-effect-$base-driven.log" 2>/dev/null \
        | grep -oE "[0-9]+" | head -1)
    [ -n "$acts" ] || acts=0

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
# The status bar carries a clock, and the two runs are a minute apart.
# 狀態列帶有時鐘,而兩次執行相隔約一分鐘。
d.paste((0, 0, 0), (0, 0, a.size[0], 100))
px = sum(1 for p in d.get_flattened_data() if p != (0, 0, 0))
print(px, max(x[1] for x in d.getextrema()), d.getbbox() or "none")
PY
)"

    # 100, from the Android distribution: scenarios that change nothing report
    # exactly 0, and the smallest real change measured there was 517 pixels,
    # because a digit is small. 2000 was tried and called two passes failures.
    # 門檻 100,取自 Android 的分佈:不改變任何東西的情境回報恰好 0,而在該處量到的最小真實改變是
    # 517 像素——因為一個數字就是這麼小。曾用過 2000,結果把兩次通過判成了失敗。
    if [ "${px:-0}" -gt 100 ]; then
        verdict="the action file changed the screen"; changed=$((changed + 1))
    elif [ "${px:-0}" -lt 0 ]; then
        verdict="could not compare"; failed=$((failed + 1))
    else
        verdict="NO VISIBLE CHANGE"; inert=$((inert + 1))
    fi

    append_row "$app" "$scenario" "$px" "$maxd" "$bbox" "$acts" "$verdict"
    printf "%-6s %-34s %-12s %-8s %s\n" "$app" "${scenario:0:33}" "$px" "$acts" "$verdict"
done

print
print "$changed changed the screen, $inert did not, $failed could not be compared"
print "Captures: $keep"
print "CSV: $out_csv"
print "IOS EFFECT COMPLETE"
