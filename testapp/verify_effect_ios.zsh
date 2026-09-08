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

    # The longest prefix that names a real app, not the first segment.
    #
    # `${base%%-*}` truncates at the first hyphen, which is right for
    # P7-select-a-list-row and wrong for P15-DARK-the-override-survives-a-tap:
    # it launched P15 and drove it with P15-DARK's coordinates. Both apps exist
    # -- testapp/P15-DARK.swift and testapp/P17-DOE.swift -- so this was not a
    # missing file, it was the wrong file, and the run reported cleanly.
    #
    # The failure was invisible from the results: the capture is named after the
    # scenario, so `P15-DARK-...-control.png` held a picture of P15, and the
    # taps landed on blank space in an app nobody meant to test. It reads as
    # "the action file changed nothing", which is what it was recorded as.
    #
    # 取「能對應到真實 app 的最長前綴」,而不是第一段。
    #
    # `${base%%-*}` 在第一個連字號截斷,這對 P7-select-a-list-row 是對的,對
    # P15-DARK-the-override-survives-a-tap 則是錯的:它啟動了 P15,卻用 P15-DARK 的座標去驅動它。
    # 兩支 app 都存在——testapp/P15-DARK.swift 與 testapp/P17-DOE.swift——因此這不是「檔案不見了」,
    # 而是「拿錯了檔案」,而該次執行回報得乾乾淨淨。
    #
    # 這個失敗從結果上看不出來:擷取是以情境命名的,於是 `P15-DARK-...-control.png` 裡裝的是 P15 的
    # 畫面,而那些點擊落在一支沒有人打算測試的 app 的空白處。它讀起來就是「這個動作檔什麼都沒改變」,
    # 而它也正是被那樣記錄下來的。
    app=""
    candidate="$base"
    while [ -n "$candidate" ]; do
        if [ -f "$script_dir/$candidate.swift" ]; then app="$candidate"; break; fi
        [[ "$candidate" == *-* ]] || break
        candidate="${candidate%-*}"
    done
    [ -n "$app" ] || { failed=$((failed + 1)); continue }
    scenario="${base#$app-}"

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
#
# 108, measured, not chosen. The clock's glyphs occupy rows 69..107 on this
# device, so a 100-row mask left seven rows of digit showing -- and those seven
# rows were the entire "difference" for ten of the forty-eight apps. It is not
# one row more than 108 either: P1, P18 and P37 have real, full-width changes
# whose topmost row is exactly 108.
#
# 108,是量出來的,不是挑出來的。在本裝置上時鐘字符佔據第 69..107 列,因此 100 列的遮罩留下了
# 七列數字未遮——而那七列正是四十八支 app 中十支的「全部差異」。它也不能比 108 再多一列:
# P1、P18 與 P37 有真實的、跨滿寬度的變化,其最上緣恰好就在第 108 列。
d.paste((0, 0, 0), (0, 0, a.size[0], 108))
px = sum(1 for p in d.get_flattened_data() if p != (0, 0, 0))
print(px, max(x[1] for x in d.getextrema()), d.getbbox() or "none")
PY
)"

    # Zero, because with the mask correct there is nothing to threshold.
    #
    # This was 100, and before that 2000, and both numbers were compensating for
    # the mask above being thirty rows too short: the leaked clock digits scored
    # 56 to 327 pixels, so any threshold had to sit above them and therefore
    # inside the real data. It could not be chosen well because the distribution
    # was continuous -- 56, 87, 138, 189, 206, 218, 241, 241, 244, 296, 327,
    # 1028, 1241, 1634 -- with no gap to put it in.
    #
    # With the status bar actually masked, ten apps report exactly 0 and the
    # smallest real change is 29 pixels, in a bbox at y=1951 that has nothing to
    # do with the clock. The gap is between 0 and 29, so the test is `> 0`, and
    # a scenario that changes nothing is a finding rather than a number below a
    # line someone picked.
    #
    # 門檻為零,因為遮罩正確之後就沒有什麼需要設門檻了。
    #
    # 它曾經是 100、更早是 2000,而這兩個數字都是在替上方那個「短了三十列」的遮罩擦屁股:漏出來的
    # 時鐘數字得分介於 56 到 327 像素之間,因此任何門檻都必須高過它們——也就必然落在真實資料之內。
    # 它無法被好好選定,因為該分佈是連續的——56、87、138、189、206、218、241、241、244、296、327、
    # 1028、1241、1634——沒有任何可供安放的間隙。
    #
    # 狀態列真正被遮住之後,有十支 app 回報恰好 0,而最小的真實變化是 29 像素,其 bbox 位於
    # y=1951,與時鐘毫無關係。間隙落在 0 與 29 之間,因此測試是 `> 0`;而「什麼都沒改變的情境」
    # 是一項發現,不是一個落在某人挑出的線以下的數字。
    if [ "${px:-0}" -gt 0 ]; then
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
