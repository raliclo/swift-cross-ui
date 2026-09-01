#!/usr/bin/env zsh
# Runs every built Pn on macOS, records what happened, appends to the history.
#
#   zsh testapp/sweep-test/sweep_drive_macos.zsh            every built app
#   zsh testapp/sweep-test/sweep_drive_macos.zsh P8 P28     just these
#   zsh testapp/sweep-test/sweep_drive_macos.zsh --dry-run  list, change nothing
#   zsh testapp/sweep-test/sweep_drive_macos.zsh --help
#
# The macOS counterpart of sweep_drive.zsh. That one is the Windows driver and
# says so: it is built on tasklist, taskkill, gdigrab and Pn.exe, and hard-codes
# `platform=windows`. None of that exists here.
#
# This one is not a second copy of it. It drives `test.zsh <Pn> --macos`, which
# already builds, launches, waits for the render marker, screenshots and closes
# on this platform -- so the sweep is a loop, a reader of that output, and an
# appender. Reimplementing the launch and teardown would be a second thing to
# keep correct, and the project's own verified-test-process.md says not to write
# a new harness.
#
# sweep_drive.zsh 的 macOS 對應版本。那一支是 Windows 的驅動器，其檔頭亦如此聲明：它建立在
# tasklist、taskkill、gdigrab 與 Pn.exe 之上，並且寫死 `platform=windows`。這些在此處都不存在。
#
# 本腳本並非它的第二份副本。它驅動的是 `test.zsh <Pn> --macos`——後者在本平台上本就會建置、啟動、
# 等待 render marker、截圖並收尾——因此這支 sweep 只是一個迴圈、一個輸出的讀取者，以及一個追加者。
# 重新實作啟動與收尾等於多出一個必須維持正確的東西，而本專案的 verified-test-process.md 明講
# 「不要另寫測試框架」。

set -euo pipefail

script_path="${0:A}"
sweep_dir="${script_path:h}"
testapp_dir="${sweep_dir:h}"
repo="${testapp_dir:h}"

results="$repo/matrix_coverage/results.csv2"

# `mac`, not `macos`. coverage.zsh's column key is `mac/appkit`, and a row whose
# platform/backend pair matches no column is reported on stderr rather than
# dropped -- so a plausible-looking `macos` would leave every app reading as
# never tested while the sweep reported success.
# 是 `mac` 而非 `macos`。coverage.zsh 的欄位鍵為 `mac/appkit`，而配對不符任何欄位的資料列會被回報
# 於 stderr 而非直接捨棄——因此一個看似合理的 `macos` 會使每支 app 都讀起來像「從未測試」，而 sweep
# 卻回報成功。
platform=mac
backend=appkit
run_date="$(date +%F)"

usage() { sed -n '2,9p' "$script_path" | sed 's/^# \{0,1\}//'; }

dry_run=0
apps=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        -n|--dry-run) dry_run=1; shift ;;
        P<->|P<->-*) apps+=("$1"); shift ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 64 ;;
    esac
done

[ "$(uname -s)" = Darwin ] || { printf 'This is the macOS driver.\n' >&2; exit 3; }
[ -f "$results" ] || { printf '%s is missing; it is the history file\n' "$results" >&2; exit 1; }

# Every app that has both a loader and a built executable.
#
# Both, not either. Without a loader `test.zsh` cannot run it; without a build
# there is nothing to run, and building here would turn a sweep into a
# multi-hour job with a different failure mode. sweep_build.zsh is the pair for
# that, exactly as on the Windows side.
#
# 兩者皆需，而非其一。缺少 loader，`test.zsh` 無從執行；缺少建置產物則無物可執行，而在此處建置會
# 使一次 sweep 變成數小時的工作、且失敗型態完全不同。負責建置的是 sweep_build.zsh，與 Windows 那
# 邊的分工相同。
if [ "${#apps[@]}" -eq 0 ]; then
    for loader in "$testapp_dir/test_support"/test_P*.zsh; do
        name="${loader:t:r}"; name="${name#test_}"
        [ -x "$testapp_dir/output/$name" ] && apps+=("$name")
    done
fi

if [ "${#apps[@]}" -eq 0 ]; then
    printf 'Nothing to sweep: no app has both a loader and a build in testapp/output.\n' >&2
    exit 1
fi

printf '==> %d app(s) on %s/%s, %s\n\n' "${#apps[@]}" "$platform" "$backend" "$run_date"
printf '%-8s %-8s %-8s %-9s %s\n' app launch replay capture note

for app in "${apps[@]}"; do
    # Cleared per app. The staleness check below writes a note before the run,
    # so the reset cannot live where it used to -- and a note that survives into
    # the next iteration attributes one app's finding to another.
    # 每支 app 都重設。下方的過期檢查會在執行前就寫入 note，因此重設不能再留在原處；而一個殘留到
    # 下一輪的 note，會把某支 app 的發現安到另一支頭上。
    note=""

    if [ "$dry_run" -eq 1 ]; then
        printf '%-8s %-8s %-8s %-9s %s\n' "$app" "-" "-" "-" "would run"
        continue
    fi

    # An action file only if one exists for this platform. testapp/actions/mac
    # holds a file only after it has been run here, so its absence is a fact
    # about coverage rather than an error, and the row says n/a.
    # 僅在本平台確實有動作檔時才使用。testapp/actions/mac 中的檔案只有在此處實際執行過之後才會存在，
    # 因此它的缺席是一項關於覆蓋率的事實而非錯誤，該列即記為 n/a。
    #
    # Globbed with zsh's (N) qualifier, not `compgen`. compgen is a bash
    # builtin; zsh does not have it, so the test failed silently and the first
    # pilot run recorded P28 as replay=n/a while its action file sat in
    # actions/mac. A missing-tool check that reads as "no action file" is the
    # exact false negative this column exists to avoid.
    # 使用 zsh 的 (N) glob 修飾詞，而非 `compgen`。compgen 是 bash 的內建指令，zsh 並沒有它，因此
    # 該判斷會靜默失敗——首次試跑就把 P28 記為 replay=n/a，而它的動作檔明明就在 actions/mac 裡。
    # 一個「工具不存在」卻被讀成「沒有動作檔」的檢查，正是本欄位所要避免的那種偽陰性。
    action_args=()
    local -a found
    found=("$testapp_dir/actions/mac/$app"-*.csv(N))
    [ "${#found}" -gt 0 ] && action_args=(--actionfile)

    # Reuse the existing build, except when replaying.
    #
    # `-actionfile` is compiled out unless the binary was built with SCUI_DEBUG,
    # and test_common.zsh only sets that when an action file is asked for. So
    # `-n` plus `--actionfile` produces an app with no replay support and a run
    # that reports nothing -- measured: the first P28 attempt recorded
    # `no line` against a binary built earlier without the flag. Dropping `-n`
    # for those apps costs one build each and makes the column mean something.
    #
    # 重用既有的建置，但重放時例外。
    #
    # 除非執行檔是以 SCUI_DEBUG 建置，否則 `-actionfile` 會被編譯掉；而 test_common.zsh 僅在確實
    # 要求動作檔時才設定該變數。因此「`-n` 加上 `--actionfile`」會產出一個不具重放支援的 app，其
    # 執行結果什麼也不回報——實測：第一次嘗試 P28 時，對著先前未帶該旗標建置的執行檔記下了
    # `no line`。對這些 app 放棄 `-n`，代價是各多一次建置，而該欄位也才具有意義。
    # Rebuild when the binary is older than its source, or when replaying.
    #
    # Reusing a build is the point of a sweep, but reusing a *stale* one records
    # the wrong app. P37 and P38 were logged as "declares a marker that never
    # appeared" for exactly this: their binaries were built on 2026-08-27,
    # before the diagnostics they print, so the marker could not appear. A
    # rebuild produced it on the first run -- "RENDER COMPLETE -- P37 ready for
    # window-level challenge" -- and neither the app nor AppKit was ever at
    # fault.
    #
    # 當執行檔比其原始碼舊、或需要重放時，重新建置。
    #
    # 重用既有建置正是 sweep 的意義所在，但重用**過期的**建置記錄到的是另一個 app。P37 與 P38 之所以
    # 被記為「宣告了 marker 卻從未出現」，原因正是如此：它們的執行檔建於 2026-08-27，早於它們所印出
    # 的診斷訊息，因此該 marker 不可能出現。重新建置後第一次執行就印出了它——「RENDER COMPLETE --
    # P37 ready for window-level challenge」——而 app 與 AppKit 自始至終都沒有問題。
    build_args=(-n)
    source_file="$testapp_dir/$app.swift"
    if [ "${#action_args[@]}" -gt 0 ]; then
        build_args=()
    elif [ -f "$source_file" ] && [ "$source_file" -nt "$testapp_dir/output/$app" ]; then
        build_args=()
        note="rebuilt: the binary was older than $app.swift"
    fi

    zsh "$testapp_dir/ui-lock.zsh" release "test-${app:l}" >/dev/null 2>&1 || true

    # No showtime when there is nothing to replay; enough of one when there is.
    #
    # `--no-showtime` closes the app as soon as it renders, which truncates a
    # replay still in progress. Measured on P26: its action file clicks a tab and
    # then sleeps three seconds for the fetch, and the log held
    # "-actionfile: replaying" with no matching "replayed" -- the app was gone
    # first. The row then read `no line` and blamed SCUI_DEBUG, which was fine.
    #
    # 沒有東西要重放時不留時間；有的時候則留足夠的時間。
    #
    # `--no-showtime` 會在 app 完成繪製後立刻關閉它，而那會截斷仍在進行中的重放。在 P26 上實測：
    # 其動作檔會點擊分頁、接著等待三秒讓抓取完成，而記錄檔中只有「-actionfile: replaying」而沒有
    # 對應的「replayed」——app 先一步被關掉了。該列於是讀成 `no line` 並歸咎於 SCUI_DEBUG，而後者
    # 其實毫無問題。
    show_args=(--no-showtime)
    # Ten seconds, not the eight that first worked. Eight was fitted to the one
    # action file that existed -- a click and a three-second wait -- and a value
    # chosen to just clear the only case in front of you is the value that
    # truncates the next one. Ten is the floor for any replay here.
    # 十秒，而非最初可行的八秒。八秒是依當時唯一存在的那個動作檔（一次點擊加三秒等待）湊出來的，
    # 而「剛好夠用於眼前唯一案例」的數值，正是會截斷下一個案例的數值。十秒是此處任何重放的下限。
    [ "${#action_args[@]}" -gt 0 ] && show_args=(--showtime 10)

    out="$(timeout 900 zsh "$testapp_dir/test.zsh" "$app" --macos "${show_args[@]}" \
        "${build_args[@]}" "${action_args[@]}" 2>&1 || true)"

    # Every column is read out of what happened, never assumed. A sweep that
    # writes `ok` because the command returned 0 records the thing it was
    # supposed to measure.
    # 每一欄都由「實際發生了什麼」讀出，絕不假設。一支因為「指令回傳 0」就寫下 `ok` 的 sweep，
    # 記錄的正是它本應去量測的那件事。
    # Three outcomes, not two, and the middle one is the trap.
    #
    # An app with no TEST_MARKER is not failing when no marker appears -- most
    # of them have none, and test_common.zsh says so in the output and falls
    # back to timed capture. The first sweep read only "did a marker appear",
    # which labelled eleven such apps `no marker` and would have put eleven
    # problems into the matrix that do not exist. Only P37 and P38 declare a
    # marker and do not print it; those two are the real finding, and the
    # distinction has to survive into the table.
    #
    # 三種結果而非兩種，而中間那一種正是陷阱。
    #
    # 沒有設定 TEST_MARKER 的 app，在沒有 marker 出現時並非失敗——多數 app 都沒有設，而
    # test_common.zsh 會在輸出中明講並改用計時截圖。第一次 sweep 只判讀「marker 有沒有出現」，
    # 因而把十一支這樣的 app 標為 `no marker`，等於把十一個並不存在的問題寫進矩陣。真正有設 marker
    # 卻沒印出來的只有 P37 與 P38；那兩支才是實際的發現，而這個區別必須完整地留存到表格裡。
    case "$out" in
        *"rendered after"*)
            launch=ok ;;
        *"No render marker configured"*)
            launch=ok; note="no marker configured; capture is timed" ;;
        *"Launching"*)
            launch='no marker'; note="declares a marker that never appeared" ;;
        *)
            launch=fail; note="never launched" ;;
    esac

    # The replay verdict is read from the app's own log, not from this
    # command's output. run_macos launches the app with `>"$action_log"`, so the
    # `-actionfile:` line never reaches the terminal -- reading `$out` for it
    # recorded `no line` on a run whose log said "replaying" all along, and the
    # note then blamed SCUI_DEBUG for something that was never wrong.
    # 重放的判定讀自 app 自身的記錄檔，而非本指令的輸出。run_macos 以 `>"$action_log"` 啟動該
    # app，因此 `-actionfile:` 那一行從不會抵達終端——去 `$out` 裡找它，會在一次記錄檔明明寫著
    # 「replaying」的執行上記下 `no line`，而該備註還會把責任推給根本沒問題的 SCUI_DEBUG。
    action_log="$testapp_dir/output/${app:l}-actionfile.log"
    replay_out="$([ -f "$action_log" ] && cat "$action_log" || printf '')"

    if [ "${#action_args[@]}" -eq 0 ]; then
        replay=n/a
    else
        case "$replay_out" in
            *"-actionfile: replayed"*) replay=ok ;;
            *"-actionfile: failed"*)   replay=fail
                note="${note:+$note; }$(printf '%s' "$replay_out" | grep -m1 'actionfile: failed' | cut -c1-80)" ;;
            *)                         replay='no line'
                note="${note:+$note; }no -actionfile line -- built without SCUI_DEBUG?" ;;
        esac
    fi

    case "$out" in
        *"priority 1"*) capture=window ;;
        *"priority 2"*) capture=desktop; note="${note:+$note; }window capture fell back to the screen" ;;
        *"no screenshot"*) capture=fail; note="${note:+$note; }screenshot.zsh produced no image" ;;
        *) capture=n/a ;;
    esac

    printf '%-8s %-8s %-8s %-9s %s\n' "$app" "$launch" "$replay" "$capture" "$note"

    # Appended with csv2, not with `printf >>`.
    #
    # sweep_drive.zsh writes the row by hand and quotes it per RFC 4180 itself.
    # That works, but it is the project writing CSV without the tool it keeps
    # for the purpose, and the row it produces is never validated: a malformed
    # note, or a history file whose last record is already truncated, is
    # discovered by whatever reads it next. `csv2 -append` validates the input
    # before writing, reads the existing file to check its final record, and
    # writes only the appended bytes -- measured on a copy, 126 lines unchanged
    # and one added, with a note containing both a comma and doubled quotes
    # parsed back intact.
    #
    # 以 csv2 追加，而非 `printf >>`。
    #
    # sweep_drive.zsh 是自行手寫該列並依 RFC 4180 自行處理引號。那能運作，但那是本專案在不使用其
    # 為此保留的工具的情況下寫 CSV，且所產生的資料列從未經過驗證：一個格式錯誤的 note，或一個最後
    # 一筆記錄已被截斷的歷史檔，要等到下一個讀取者才會發現。`csv2 -append` 會在寫入前驗證輸入、
    # 讀取既有檔案以檢查其最後一筆記錄，並且只寫入所追加的位元組——在副本上實測：126 行未變、新增
    # 一行，且一個同時含有逗號與加倍引號的 note 能被原樣解析回來。
    csv2 -append "$run_date,$platform,$backend,$app,$launch,$replay,$capture,\"${note//\"/\"\"}\"" \
        -i "$results" --in-place
done

if [ "$dry_run" -eq 0 ]; then
    printf '\nAppended to %s\n' "${results#$repo/}"
    printf 'Regenerate the matrix with: zsh matrix_coverage/coverage.zsh\n'
fi
