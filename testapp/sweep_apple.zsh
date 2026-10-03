#!/usr/bin/env zsh
# Drive and photograph every macOS or iOS action file, one at a time.
#
#   zsh testapp/sweep_apple.zsh --macos            every file under actions/mac/
#   zsh testapp/sweep_apple.zsh --ios              every file under actions/ios/
#   zsh testapp/sweep_apple.zsh --ios P57 P72      only those apps' files
#
# Writes output/<platform>-sweep.csv2, one row per ACTION FILE -- not per app,
# for the reason sweep_android.zsh gives: several apps carry more than one file,
# and a sweep that takes the first file per app quietly drops scenarios.
#
# **What a `pass` here means, and what it does not.** Three things, each read
# from something the run produced rather than inferred:
#
#   replay    the replay's own `-actionfile: replayed <file>` line -- on macOS
#             from the app's actionfile log, on iOS from the XCUITest runner's
#             output. A `failed:` line, or no line at all, is not a replay.
#   capture   a `<app>-<platform>-final-*.png` written DURING this run, found by
#             comparing against a marker touched before it started. An older
#             capture of the same app is exactly what a run that never reached
#             the screenshot leaves behind.
#   exit      test.zsh's own status.
#
# It does NOT mean each file's assertions held. An XCUITest tap on empty space
# is not an error and neither is a click that lands on the wrong control; the
# assertion lives in the file's header and a person or a later check reads it
# off the capture. This is the same standard the Android column was filled by,
# and it is said here so a green row is not read as more than it is.
#
# **One run at a time, and a watchdog on each.** An app that hangs would
# otherwise stop the whole sweep; after `--timeout` seconds (default 600) the
# run is killed and recorded as `timeout`.
#
# macOS runs move the REAL pointer and bring windows to the front. Do not use
# the Mac while a macOS sweep runs, and do not run the two platforms at once:
# the Simulator window can end up over a macOS test app.
#
# 逐一驅動並拍攝每一份 macOS 或 iOS 動作檔。
#
# 寫出 output/<平台>-sweep.csv2,每一列對應一份**動作檔**而不是一支 app——理由與 sweep_android.zsh
# 相同:有幾支 app 帶著不只一份檔案,而「每支 app 取第一份」的 sweep 會默默丟掉情境。
#
# **此處的 `pass` 代表什麼、不代表什麼。**三件事,每一件都讀自那次執行產出的東西,而不是推測:
#
#   replay    重放自己的 `-actionfile: replayed <檔名>` 那一行——macOS 讀自 app 的 actionfile log,
#             iOS 讀自 XCUITest runner 的輸出。一行 `failed:`、或者根本沒有那一行,都不算重放。
#   capture   一張在**本次執行期間**寫出的 `<app>-<平台>-final-*.png`,以「執行開始前 touch 的標記檔」
#             比對找出。同一支 app 較舊的擷圖,正是一次「沒走到截圖那一步」的執行會留下的東西。
#   exit      test.zsh 自己的結束狀態。
#
# 它**不**代表每一份檔案的斷言都成立。XCUITest 在空白處的一次點擊不算錯誤,點到錯的控制項也不算;
# 斷言寫在檔頭,要由人或之後的檢查從擷圖上讀出來。這與 Android 那一欄當初被填入的標準相同,而在此明說,
# 以免一列綠色被讀成比它實際更多的意思。
#
# **一次一個,而且每一個都有看門狗。**一支卡住的 app 否則會讓整輪停住;超過 `--timeout` 秒(預設 600)
# 就結束它,並記為 `timeout`。
#
# macOS 的執行會移動**真實**指標並把視窗帶到最前面。macOS sweep 執行期間不要使用這台 Mac,也不要兩個平台
# 同時跑:Simulator 的視窗可能會蓋到 macOS 的測試 app 上。

set -u
script_dir="${0:A:h}"
repo_root="${script_dir:h}"

platform=""
timeout_s=600
apps=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --macos) platform=macos; shift ;;
        --ios) platform=ios; shift ;;
        --timeout) timeout_s="$2"; shift 2 ;;
        -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
        P[0-9]*) apps+=("$1"); shift ;;
        *) echo "unknown argument: $1" >&2; exit 64 ;;
    esac
done
if [ -z "$platform" ]; then
    echo "usage: sweep_apple.zsh --macos|--ios [--timeout seconds] [Pn ...]" >&2
    exit 64
fi

case "$platform" in
    macos) action_dir="$script_dir/actions/mac"; backend=appkit ;;
    ios) action_dir="$script_dir/actions/ios"; backend=uikit ;;
esac

output_dir="$script_dir/output"
shots_dir="$output_dir/screenshots"
run_dir="$output_dir/sweep-$platform"
out_csv="$output_dir/$platform-sweep.csv2"
mkdir -p "$run_dir" "$shots_dir"

# **The app a file belongs to is the LONGEST prefix that names an app, not the
# text before the first dash.** P15-DARK and P17-DOE are apps of their own
# (testapp/P15-DARK.swift, testapp/P17-DOE.swift), and cutting at the first dash
# turned `P15-DARK-...csv` into P15: the first two sweeps of 2026-09-27 replayed
# those files against the wrong app and counted them as passes, because a tap
# that lands on some other app's empty space is not an error either.
# **一份檔案所屬的 app,是「能對應到某支 app 的最長前綴」,不是第一個破折號之前的文字。**P15-DARK 與
# P17-DOE 是各自獨立的 app,而在第一個破折號處切開,會把 `P15-DARK-...csv` 變成 P15:2026-09-27 的前兩輪
# sweep 就是拿這兩份檔案去重放錯的 app,還把它們算成通過。
app_of() {
    local stem="${1%.csv}" candidate="" best=""
    local -a parts=("${(@s:-:)stem}")
    local i
    for i in {1..${#parts}}; do
        candidate="${(j:-:)parts[1,$i]}"
        [ -f "$script_dir/$candidate.swift" ] && best="$candidate"
    done
    print -r -- "$best"
}

files=()
for f in "$action_dir"/P*.csv(N); do
    app="$(app_of "${f:t}")"
    if [ -z "$app" ]; then
        echo "no testapp/<app>.swift matches ${f:t}; skipped and said so" >&2
        continue
    fi
    if [ "${#apps[@]}" -gt 0 ] && (( ! ${apps[(Ie)$app]} )); then
        continue
    fi
    # `-ipad` files open several windows and the sweep runs on the iPhone
    # Simulator, where there is one: P59-two-windows-ipad failed there on
    # 2026-10-03. They are run on an iPad by hand (testapp/README.md > iPad).
    # `-ipad` 檔會開多個視窗，而 sweep 跑在只有一個視窗的 iPhone 模擬器上:2026-10-03
    # P59-two-windows-ipad 在那裡失敗。它們在 iPad 上手動執行(見 testapp/README.md > iPad)。
    if [[ "${f:t}" == *-ipad.csv ]]; then
        echo "${f:t}: an iPad file, skipped on the iPhone sweep" >&2
        continue
    fi
    files+=("$f")
done
if [ "${#files[@]}" -eq 0 ]; then
    echo "no action files matched under $action_dir" >&2
    exit 1
fi
print "==> $platform sweep: ${#files[@]} action files"

rows_file="$run_dir/rows.tsv"
: > "$rows_file"

for f in "${files[@]}"; do
    name="${f:t}"
    app="$(app_of "$name")"
    stem="${name%.csv}"
    log="$run_dir/$stem.log"
    marker="$run_dir/.started-$stem"
    touch "$marker"
    started=$(date +%s)

    # **Launch arguments a file needs, read from the file itself.** P34's files say
    # in prose that they need `-rows 500` -- at the default of 100 both of its buttons
    # are no-ops by design -- and a sweep that cannot read prose launched them
    # without it, so they replayed, captured, and could not have passed. A file that
    # needs arguments now states them on one line, `# launch-args: -rows 500`, and
    # they reach the app on both platforms through TEST_APP_ARGS, keeping the
    # harness's own `--debug`.
    # **一份檔案需要的啟動參數,從檔案本身讀出來。**P34 的檔案以散文寫著需要 `-rows 500`——在預設的
    # 100 之下它的兩顆按鈕依設計都是 no-op——而讀不懂散文的 sweep 就不帶參數啟動它們,於是它們有重放、
    # 有擷圖、卻不可能通過。需要參數的檔案現在用一行 `# launch-args: -rows 500` 寫明,參數在兩個平台上
    # 都經由 TEST_APP_ARGS 送達 app,並保留 harness 自己的 `--debug`。
    launch_args="$(grep -m1 -E '^# *launch-args:' "$f" | sed -E 's/^# *launch-args: *//')"
    if [ "$platform" = macos ]; then
        rm -f "$output_dir/${app:l}-actionfile.log"
        TEST_APP_ARGS="--debug${launch_args:+ $launch_args}" \
            zsh "$script_dir/test.zsh" "$app" --macos --showtime 2 --actionfile "$f" > "$log" 2>&1 &
    else
        # Through TEST_APP_ARGS, not `--`: test.zsh hands its options to test_common,
        # which rejects `--`, and test_common forwards TEST_APP_ARGS to test_ios.zsh.
        # 經由 TEST_APP_ARGS 而不是 `--`:test.zsh 把選項交給 test_common,而它拒絕 `--`;
        # test_common 會把 TEST_APP_ARGS 轉給 test_ios.zsh。
        # `--debug` always, as on macOS: without it an app prints none of its `[Pn]`
        # lines, and output/<app>-ios-stdout.log is how a tap that landed is told from
        # one that missed.
        # 一律帶 `--debug`,與 macOS 相同:少了它 app 不會印出任何 `[Pn]` 行,而
        # output/<app>-ios-stdout.log 正是分辨「點到了」與「沒點到」的依據。
        TEST_APP_ARGS="--debug${launch_args:+ $launch_args}" \
            zsh "$script_dir/test.zsh" "$app" --ios --showtime 2 --actionfile "$f" > "$log" 2>&1 &
    fi
    pid=$!
    state=""
    while kill -0 "$pid" 2>/dev/null; do
        if (( $(date +%s) - started > timeout_s )); then
            kill "$pid" 2>/dev/null
            pkill -f "debugTarget" 2>/dev/null
            state=timeout
            break
        fi
        sleep 2
    done
    wait "$pid" 2>/dev/null
    rc=$?
    [ "$state" = timeout ] && rc=124
    elapsed=$(( $(date +%s) - started ))

    if [ "$platform" = macos ]; then
        replay_source="$output_dir/${app:l}-actionfile.log"
        [ -f "$replay_source" ] && cp "$replay_source" "$run_dir/$stem-actionfile.log"
    else
        replay_source="$log"
    fi
    replay=fail
    replay_note=""
    if [ -f "$replay_source" ] && grep -aq -- "-actionfile: replayed $name" "$replay_source"; then
        replay=ok
    elif [ -f "$replay_source" ]; then
        replay_note=$(grep -a -m1 -- "-actionfile: failed" "$replay_source" | cut -c1-160)
    fi

    capture=fail
    shot=""
    for s in "$shots_dir"/${app:l}-$platform-final-*.png(N.om); do
        if [ "$s" -nt "$marker" ]; then
            capture=ok
            shot="${s:t}"
        fi
        break
    done

    # **A crash report written during the run overrides everything above.** On iOS
    # the replay runs in the XCUITest process, so it reports `replayed` and exits 0
    # whether or not the app survived, and the final capture is then the home
    # screen. Measured 2026-09-27 with P73 before its fix: `replayed`, exit 0, a
    # capture -- and debugTarget-2026-09-27-222247.ips, EXC_BREAKPOINT. Both
    # platforms install the app as `debugTarget`, so one check covers both.
    # **執行期間寫出的崩潰報告,凌駕上面的一切。**iOS 上重放在 XCUITest 行程裡執行,因此不論 app 有沒有
    # 活下來,它都會回報 `replayed` 並以 0 結束,而最終擷圖就成了主畫面。2026-09-27 以修正前的 P73 實測:
    # `replayed`、結束碼 0、有擷圖——以及 debugTarget-2026-09-27-222247.ips,EXC_BREAKPOINT。兩個平台
    # 都把 app 裝成 `debugTarget`,因此一個檢查涵蓋兩者。
    crash=""
    for c in "$HOME"/Library/Logs/DiagnosticReports/debugTarget-*.ips(N.om); do
        [ "$c" -nt "$marker" ] && crash="${c:t}"
        break
    done

    result=fail
    [ "$rc" -eq 0 ] && [ "$replay" = ok ] && [ "$capture" = ok ] && result=pass
    [ "$state" = timeout ] && result=timeout
    if [ -n "$crash" ]; then
        result=crash
        replay_note="crash report $crash${replay_note:+; $replay_note}"
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$app" "$name" "$result" "$rc" "$replay" "$capture" "$elapsed" "$shot" "$replay_note" >> "$rows_file"
    printf '    %-6s %-44s %-7s rc=%-3s replay=%-4s capture=%-4s %4ss\n' \
        "$app" "$name" "$result" "$rc" "$replay" "$capture" "$elapsed"
    rm -f "$marker"
done

# Written with a real CSV writer: the note column carries error text with
# commas in it, and this tree has paid for splitting on commas twice.
# 以真正的 CSV writer 寫出:note 欄帶著含逗號的錯誤訊息,而這棵樹已經為「以逗號切割」付過兩次代價。
python3 - "$rows_file" "$out_csv" "$platform" "$backend" <<'PY'
import csv, sys, datetime
rows_path, out_path, platform, backend = sys.argv[1:5]
today = datetime.date.today().isoformat()
with open(rows_path, newline="", encoding="utf-8") as handle:
    rows = [line.rstrip("\n").split("\t") for line in handle if line.strip()]
with open(out_path, "w", newline="", encoding="utf-8") as handle:
    writer = csv.writer(handle)
    writer.writerow(["date", "platform", "backend", "app", "action_file", "result",
                     "exit", "replay", "capture", "seconds", "screenshot", "note"])
    writer.writerow(["日期", "平台", "backend", "app", "動作檔", "結果",
                     "結束碼", "重放", "擷取", "秒數", "擷圖", "備註"])
    for app, name, result, rc, replay, capture, secs, shot, note in rows:
        writer.writerow([today, platform, backend, app, name, result,
                         rc, replay, capture, secs, shot, note])
total = len(rows)
passed = sum(1 for r in rows if r[2] == "pass")
print(f"==> {platform}: {passed} of {total} action files pass; written to {out_path}")
PY
