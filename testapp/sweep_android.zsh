#!/usr/bin/env zsh
# Build, install, drive and photograph every test app on Android, one at a time.
#
#   zsh sweep_android.zsh              every action file under actions/android/
#   zsh sweep_android.zsh P10 P23      only those apps' action files
#
# Writes output/android-sweep.csv2 and prints a table. One row per **action
# file**, not per app, because they are not the same number: 45 apps and 46
# files, since P12 carries both `android-smoke` and `increment-the-counter`.
# Iterating apps and taking the first file each -- which the first version of
# this script did -- quietly drops a scenario, and a sweep that reports 45 of 45
# while never running one of them is exactly the shape of pass this tree keeps
# paying for.
#
# **One app on the device at a time.** The emulator was wedged three separate
# ways during the 2026-09-05 work -- `Failure calling service package: Broken
# pipe`, `Can't find service: activity`, and a "Pixel Launcher isn't responding"
# dialog that dimmed a screenshot and turned a clean comparison into 2.5 million
# differing pixels. All three followed long runs with a dozen 110 MB APKs
# installed and as many processes left alive. So each app is force-stopped and
# uninstalled when its turn ends, and `logcat -c` runs before each launch so the
# box measurement belongs to the app that is running rather than to whichever
# one logged last. That mistake was made too: a per-app table read P13 as
# fitting the screen exactly, and a clean device gave it as
# (-609,-162)-(1690,2625).
#
# **A failure here is not the same as a broken app.** The emulator failures
# above are retried once, and the retry is recorded, because a run that silently
# swallows them reports a defect in the toolkit that is really a defect in the
# device.
#
# 逐一建置、安裝、驅動並拍攝每一支 Android 測試 app。
#
# 會寫出 output/android-sweep.csv2 並印出一張表。每一列對應一份**動作檔**而非一支 app，因為兩者數目
# 不同：45 支 app、46 份檔案，P12 同時帶有 `android-smoke` 與 `increment-the-counter`。若逐 app 迭代
# 並各取第一份檔案——本腳本的第一版正是如此——就會默默丟掉一個情境；而一次「回報 45 之 45 通過、卻
# 從未執行其中之一」的 sweep，正是本樹一再付出代價的那種通過形狀。
#
# **裝置上一次只放一支 app。** 2026-09-05 的工作期間，模擬器以三種不同方式被弄僵——
# `Failure calling service package: Broken pipe`、`Can't find service: activity`，以及一個
# 「Pixel Launcher isn't responding」對話框；後者讓一張截圖整片變暗，把一次乾淨的比對變成 250 萬個
# 相異像素。三者都發生在「裝了十幾個 110 MB 的 APK、留下同樣多行程」的長時間執行之後。因此每支 app
# 結束時都會被 force-stop 並解除安裝，而每次啟動前都會執行 `logcat -c`，好讓量到的內容框屬於正在執行
# 的那支 app，而不是最後一個寫日誌的那支。後面這個錯也犯過：一張逐 app 的表把 P13 讀成「恰好塞得下」，
# 而乾淨裝置給出的是 (-609,-162)-(1690,2625)。
#
# **此處的失敗不等於 app 壞掉。** 上述的模擬器失敗會重試一次，而且重試會被記錄下來；一次默默吞掉它們
# 的執行，會把裝置的缺陷回報成工具組的缺陷。

set -uo pipefail

script_path="${0:a}"
script_dir="${script_path:h}"

serial="${ANDROID_SERIAL:-emulator-5554}"
android_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/Volumes/Windows/proj_Win/.android-sdk}}"
adb="$android_root/platform-tools/adb"
out_csv="$script_dir/output/android-sweep.csv2"

if [ ! -x "$adb" ]; then
    print -u2 "adb not found at $adb; set ANDROID_HOME"
    exit 69
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

# Resumes by default; `--fresh` starts the CSV over.
#
# A full pass is 46 builds and something over two hours, and it was interrupted
# once with 14 rows already good. Re-running those costs 35 minutes and answers
# nothing, so an app/scenario pair already in the CSV is skipped unless asked
# for. The pairs are read back with a real CSV parser, never by splitting on
# commas: the note column holds error text with commas in it, and cutting on `,`
# would shift every field after it without failing.
#
# 預設為續跑；`--fresh` 會把 CSV 重新開始。
#
# 一次完整的執行是 46 次建置、兩個多小時，而它曾在已有 14 列良好結果時被中斷。重跑那些要花 35 分鐘
# 且回答不了任何問題，因此已存在於 CSV 中的「app/情境」組合會被略過，除非明確要求。這些組合是以真正的
# CSV 解析器讀回的，絕不以逗號切割：note 欄位存放的錯誤文字本身含有逗號，而以 `,` 切割會讓其右每一欄
# 靜默左移，且不會失敗。
fresh=0
if [ "${1:-}" = "--fresh" ]; then
    fresh=1
    shift
fi

if [ "$fresh" -eq 1 ] || [ ! -f "$out_csv" ]; then
    python3 - "$out_csv" <<'PY'
import csv, sys
with open(sys.argv[1], "w", newline="") as handle:
    writer = csv.writer(handle)
    writer.writerow(["app", "scenario", "build", "launched", "screenshots", "content_box", "overflow", "note"])
    writer.writerow(["應用程式", "情境", "建置", "已啟動", "截圖數", "內容框", "溢出", "備註"])
PY
fi

already_done() {
    python3 - "$out_csv" "$1" "$2" <<'PY'
import csv, sys
path, app, scenario = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(path, newline="") as handle:
        rows = list(csv.reader(handle))
except FileNotFoundError:
    sys.exit(1)
for row in rows[2:]:
    if len(row) >= 2 and row[0] == app and row[1] == scenario:
        sys.exit(0)
sys.exit(1)
PY
}

append_row() {
    python3 - "$out_csv" "$@" <<'PY'
import csv, sys
with open(sys.argv[1], "a", newline="") as handle:
    csv.writer(handle).writerow(sys.argv[2:])
PY
}

# True only when the device is listed and ready.
#
# Every `adb` call below names a serial, and `adb -s <serial> <command>` **waits
# for that device** rather than failing when it is absent. The first version of
# this script cleared logcat before the first build, having just killed the
# emulator to start clean, and sat on that one command for forty-eight minutes:
# no output, no error, a gradle daemon still alive from an earlier run to make
# it look busy. `adb devices` was empty the whole time.
#
# So nothing here talks to the device by serial without asking first.
# test_android.zsh boots the AVD when it needs one, which is why the check can
# simply skip the clear on the first pass -- a freshly booted emulator has no
# log to clear.
#
# 只有在裝置已列出且就緒時才為真。
#
# 下方每一個 `adb` 呼叫都指名了 serial，而 `adb -s <serial> <command>` 在該裝置不存在時是**等待**它，
# 不是失敗。本腳本的第一版在第一次建置之前清除 logcat——而它才剛把模擬器砍掉以求乾淨的起點——結果就
# 卡在那一個指令上四十八分鐘：沒有輸出、沒有錯誤，還有一個先前留下的 gradle daemon 讓它看起來很忙。
# 那段期間 `adb devices` 一直是空的。
#
# 因此此處不會在未先詢問的情況下以 serial 與裝置對話。test_android.zsh 需要時會自行啟動 AVD，這也是
# 為什麼第一輪可以直接略過清除——剛啟動的模擬器本來就沒有日誌可清。
device_ready() {
    # `${serial}`, not `$serial`. zsh reads `[...]` after a parameter name as a
    # subscript even inside double quotes, so `"$serial[[:space:]]"` is parsed
    # as a subscript of `serial` and dies with
    # `device_ready:1: bad output format specification` -- a message about
    # neither adb nor grep. `zsh -n` passes it: subscripting is a run-time
    # error. The enclosing function died before its `print "$?"`, so the caller
    # saw an empty exit status and recorded P0 as FAILED with no log at all.
    #
    # 使用 `${serial}` 而非 `$serial`。zsh 即使在雙引號內，也會把緊接在參數名之後的 `[...]` 讀作
    # 下標，因此 `"$serial[[:space:]]"` 會被解析成對 `serial` 取下標，並以
    # `device_ready:1: bad output format specification` 中止——那個訊息既不關 adb 的事，也不關
    # grep 的事。`zsh -n` 檢查不出來：下標是執行期的錯誤。外層函式在執行到它的 `print "$?"` 之前就
    # 已死亡，於是呼叫端收到一個空的結束狀態，把 P0 記成 FAILED，而且連日誌檔都沒有。
    "$adb" devices 2>/dev/null | grep -qE "^${serial}[[:space:]]+device\$"
}

adb_if_ready() {
    device_ready || return 0
    "$adb" -s "$serial" "$@" 2>/dev/null
}

run_one() {
    local app="$1" action="$2" log="$3"
    adb_if_ready logcat -c >/dev/null 2>&1
    SCUI_DEBUG=1 zsh "$script_dir/test_android.zsh" "$app" \
        --actionfile "$action" --no-showtime > "$log" 2>&1
    print "$?"
}

count_in() {
    local file="$1" pattern="$2" n
    [ -f "$file" ] || { print 0; return 0; }
    n=$(grep -c -- "$pattern" "$file") || n=0
    print "${n:-0}"
}

emulator_wedged() {
    grep -qE "Failure calling service package|Can't find service|INSTALL_FAILED|device offline" "$1"
}

# Booted here, not left to the first app.
#
# test_android.zsh boots the AVD when it needs one and waits sixty seconds for
# it to appear. That is enough for a warm start and not for a cold one: the
# first attempt at this sweep followed an `emu kill`, and P0 built for 107
# seconds, booted the AVD, and died with "Android emulator did not appear in adb
# devices" -- one wasted build, and every app after it would have wasted one too.
#
# 在此處啟動，而不是留給第一支 app。
#
# test_android.zsh 需要時會自行啟動 AVD，並等待六十秒讓它出現。那對熱啟動夠用，對冷啟動不夠：本
# sweep 的第一次嘗試發生在一次 `emu kill` 之後，P0 建置了 107 秒、啟動了 AVD，然後以「Android
# emulator did not appear in adb devices」死去——白費一次建置，而它之後的每一支也都會白費一次。
if ! device_ready; then
    print "==> booting the emulator"
    # The crash database first, and it is the part that actually mattered.
    #
    # A crash left `/tmp/android-$USER/emu-crash-*.db` behind on 2026-09-04, and
    # every emulator start after that logged "Showing crashdialog to get
    # consent." and waited for a click. `-no-metrics` does not cover it: metrics
    # and crash-report consent are separate, and the run with the flag still
    # logged the dialog and still never appeared in `adb devices`. Three boot
    # attempts were spent on the wrong explanation -- too slow, then two
    # emulators on one AVD, then adb -- before the log line was read. With the
    # database gone the same command was ready in 35 seconds.
    #
    # 先處理當機資料庫，而那才是真正關鍵的部分。
    #
    # 2026-09-04 的一次當機在 `/tmp/android-$USER/emu-crash-*.db` 留下了紀錄，此後每一次啟動模擬器
    # 都會記錄「Showing crashdialog to get consent.」並等待一次點擊。`-no-metrics` 涵蓋不到它：metrics
    # 與當機回報同意是兩件事，加了旗標的那次執行照樣記錄了該對話框、也照樣沒有出現在 `adb devices`
    # 中。在讀到那一行日誌之前，已經有三次啟動嘗試耗在錯誤的解釋上——先是「太慢」，接著是「兩個模擬器
    # 共用一個 AVD」，然後是 adb。把該資料庫移除之後，同一道指令在 35 秒內就緒。
    rm -rf "/tmp/android-${USER}/emu-crash-"*.db 2>/dev/null
    "$android_root/emulator/emulator" -avd "${ANDROID_AVD:-swift-cross-ui-api36}" \
        -no-snapshot -no-boot-anim -no-metrics >/dev/null 2>&1 &
    for _ in {1..180}; do
        device_ready && break
        sleep 2
    done
    if ! device_ready; then
        print -u2 "emulator did not become ready"
        exit 70
    fi
    "$adb" -s "$serial" wait-for-device >/dev/null 2>&1
    for _ in {1..90}; do
        [ "$("$adb" -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] \
            && break
        sleep 2
    done
    print "==> emulator ready"
fi

pass=0
fail=0
row=0
skipped=0

print "==> ${#action_files[@]} action files across $(print -l ${action_files:t} | sed 's/-.*//' | sort -u | wc -l | tr -d ' ') apps"
printf "%-6s %-34s %-7s %-9s %-6s %-28s %s\n" app scenario build launched shots "content box" note

for action in $action_files; do
    row=$((row + 1))
    base="${action:t:r}"
    app="${base%%-*}"
    scenario="${base#*-}"
    log="$script_dir/output/sweep-$base.log"

    if already_done "$app" "$scenario"; then
        skipped=$((skipped + 1))
        printf "%-6s %-34s %s\n" "$app" "${scenario:0:33}" "already recorded -- skipped"
        continue
    fi

    rc=$(run_one "$app" "$action" "$log")
    # An empty status means `run_one` died before its own `print`, which is what
    # a run-time zsh error inside it looks like from here. Treated as a failure
    # rather than fed to `[ -ne ]`, which would abort the sweep on the first one.
    # 空的狀態代表 `run_one` 在自己的 `print` 之前就死了，而那正是「其內部發生 zsh 執行期錯誤」在
    # 此處的樣子。將它視為失敗，而不是餵給 `[ -ne ]`——那會讓整個 sweep 在第一次發生時就中止。
    rc="${rc:-1}"

    if [ "$rc" -ne 0 ] && [ -f "$log" ] && emulator_wedged "$log"; then
        note_prefix="retried after an emulator failure: "
        adb_if_ready shell am force-stop "dev.swiftcrossui.testapp.${app:l}" >/dev/null 2>&1
        rc=$(run_one "$app" "$action" "$log")
    else
        note_prefix=""
    fi

    # `count_in`, not `grep -c ... || print 0`.
    #
    # `grep -c` prints `0` and *also* exits 1 when it matches nothing, so the
    # `||` branch runs too and the substitution yields "0\n0" -- which then
    # lands in the CSV and in `[ -gt ]` as a two-line string. This exact shape is
    # in mistakes_prevention as a known trap and it was written here anyway.
    # Assigning first and defaulting the status keeps the count single-valued.
    #
    # 使用 `count_in`，而非 `grep -c ... || print 0`。
    #
    # `grep -c` 在零命中時會印出 `0`，**同時**以 1 結束，於是 `||` 分支也會執行，該替換產生的是
    # 「0\n0」——接著它會以一個兩行的字串進入 CSV 與 `[ -gt ]`。這個確切的形狀就記在
    # mistakes_prevention 裡，是一條已知的陷阱，而它仍然在此處被寫了出來。先指派、再為狀態設定預設值，
    # 才能讓計數保持單一值。
    launched=$(count_in "$log" "==> Launched")
    shots=$(count_in "$log" "==> Screenshot")
    built=$(count_in "$log" "==> Bundling")

    box=$(adb_if_ready logcat -d \
        | grep -o "box=([-0-9]*,[-0-9]*)-([-0-9]*,[-0-9]*)" | tail -1 | sed 's/^box=//')
    [ -n "$box" ] || box="(not reported)"

    overflow=$(python3 - "$box" <<'PY'
import re, sys
m = re.match(r"\((-?\d+),(-?\d+)\)-\((-?\d+),(-?\d+)\)", sys.argv[1])
if not m:
    print("")
    raise SystemExit
l, t, r, b = map(int, m.groups())
bits = []
if l < 0: bits.append(f"{-l}L")
if r > 1080: bits.append(f"{r - 1080}R")
if t < 0: bits.append(f"{-t}T")
if b > 2400: bits.append(f"{b - 2400}B")
print(" ".join(bits) if bits else "fits")
PY
)

    if [ "$rc" -eq 0 ] && [ "$launched" -gt 0 ]; then
        pass=$((pass + 1))
        note="$note_prefix"
    else
        fail=$((fail + 1))
        note="$note_prefix$([ -f "$log" ] && grep -m1 -E "error:|^e: |Failure|not found" "$log" | head -c 160)"
        [ -n "$note" ] || note="${note_prefix}exit $rc"
    fi

    build_state=$([ "$built" -gt 0 ] && print ok || print FAILED)
    append_row "$app" "$scenario" "$build_state" "$launched" "$shots" "$box" "$overflow" "$note"
    printf "%-6s %-34s %-7s %-9s %-6s %-28s %s\n" \
        "$app" "${scenario:0:33}" "$build_state" "$launched" "$shots" "$box" "$note"

    adb_if_ready shell am force-stop "dev.swiftcrossui.testapp.${app:l}" >/dev/null 2>&1
    adb_if_ready uninstall "dev.swiftcrossui.testapp.${app:l}" >/dev/null 2>&1
done

print
print "$pass launched, $fail did not, $skipped already recorded, of ${#action_files[@]} action files"
print "CSV: $out_csv"
print "Logs: $script_dir/output/sweep-<app>-<scenario>.log"
print "SWEEP COMPLETE"
