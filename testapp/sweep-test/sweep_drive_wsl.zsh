#!/usr/bin/env zsh
# Runs every built Pn under WSLg, records what happened, appends to the history.
#
#   zsh testapp/sweep-test/sweep_drive_wsl.zsh              every built app
#   zsh testapp/sweep-test/sweep_drive_wsl.zsh P8 P19       just these
#   zsh testapp/sweep-test/sweep_drive_wsl.zsh -render sw   llvmpipe, not D3D12
#   zsh testapp/sweep-test/sweep_drive_wsl.zsh --dry-run    list, change nothing
#   zsh testapp/sweep-test/sweep_drive_wsl.zsh --help
#
# Why this exists: a WSL run could not be recorded at all.
#
# Only two scripts ever appended to matrix_coverage/results.csv2 -- the Windows
# sweep_drive.zsh and the macOS sweep_drive_macos.zsh. The path a WSL run takes,
# testapp/test_support/test_common.zsh, contains no reference to results.csv2,
# so nothing written there could reach the matrix. Measured 2026-09-07: 462
# records, of which exactly ONE says `wsl` (P8, 2026-08-27), against 21 distinct
# apps holding WSLg screenshots in testapp/output/screenshots dated 2026-08-29
# to 2026-09-02. The recorded set and the run set were disjoint, and the matrix
# reported an empty WSL column for work that had actually been done.
#
# Modelled on sweep_drive_macos.zsh, not on sweep_drive.zsh. That one is the
# Windows driver and says so: tasklist, taskkill, gdigrab, Pn.exe, and a
# hard-coded `platform=windows`. None of that applies here.
#
# Like the macOS twin, this is a loop, a reader and an appender. `test.zsh <Pn>
# --wsl` already syncs, builds, launches under WSLg, waits for the render
# marker, screenshots and closes -- wait_for_marker_wsl, print_summary_wsl,
# print_renderer_wsl and run_wsl all live in test_common.zsh. Reimplementing any
# of it would be a second thing to keep correct, and verified-test-process.md
# says not to write a new harness.
#
# There is no `-l` flag. sweep_drive.zsh has one because Windows carries two
# backends and the label picks the executable; under WSLg there is one, so a
# flag offering a choice would be offering a choice that does not exist. The row
# is always `platform=wsl,backend=gtk4`, which is coverage.zsh's `wsl/gtk4`
# column key -- a pair matching no column is reported on stderr rather than
# dropped, so a plausible-looking `linux` or `gtk` would leave every app reading
# as never tested while this script reported success.
#
# `-n` MEANS --dry-run HERE, NOT --no-build. That is sweep_drive_macos.zsh's
# spelling and it is kept rather than improved, because two sweep drivers whose
# flags disagree are worse than one collision. test_common.zsh's `-n` is
# --no-build; this script decides building for itself, per app, and never
# forwards a bare `-n`.
#
# Reading the columns:
#
#   launch   `ok` the app rendered, or declares no marker and was captured on a
#            timer; `no marker` it declares one that never appeared; `fail` it
#            never launched, or the EGL preflight refused the renderer
#   replay   `ok` the app's own `-actionfile: replayed` line was in its WSL log.
#            It means the replay RAN TO COMPLETION. Nothing on this platform
#            reports which window received the clicks, so it is not a claim that
#            they landed on the app. `n/a` means no action file exists in
#            testapp/actions/wsl and NOTHING verified the content -- the row is
#            then a launch and a capture, and the note says so
#   capture  read from the LAST `captured from` line of the run, because a run
#            takes two or three screenshots and only the final one is evidence.
#            `window` is a real window capture, `desktop` the whole-screen
#            fallback, `n/a` no capture line at all
#
# No column is inferred from an exit status. A screenshot proves a launch and a
# capture; it does not prove a pass. `launch=ok,replay=n/a,capture=window` is
# the truthful shape for most apps here and it is written as such.
#
# Two Windows-to-WSL traps are load-bearing in the code below, both silent:
#
#   1. every wsl.exe call needs MSYS2_ARG_CONV_EXCL='*', or Git Bash's MSYS
#      runtime rewrites the POSIX paths in argv before wsl.exe sees them
#   2. `$var` is eaten crossing the boundary even inside single quotes.
#      Measured 2026-09-07 through this very shell:
#        wsl.exe -- zsh -lc 'for n in A B; do printf "got %s\n" $n; done'
#      printed `got` twice with nothing after it; with `\$n` it printed A and B.
#      So NO remote command in this file contains a remote-side `$`. Everything
#      variable is expanded on the Windows side and travels as literal text.
#
# The WSL checkout is a separate, non-git copy, so a build there compiles
# whatever was last rsynced. The staleness probe therefore runs AFTER
# rsync_WSL.zsh, never before: comparing a Windows edit against a WSL binary
# through an unsynced tree reports "fresh" for an app whose source changed, and
# a stale binary records the wrong app. That is not hypothetical -- P37 and P38
# were logged on macOS as "declares a marker that never appeared" purely because
# their binaries predated the diagnostics they print.
#
# 在 WSLg 下執行每一支已建置的 Pn，記錄實際發生了什麼，並追加至歷史檔。
#
# 它為何存在：一次 WSL 執行根本無法被記錄。
#
# 過去只有兩支腳本會追加到 matrix_coverage/results.csv2——Windows 的 sweep_drive.zsh 與 macOS 的
# sweep_drive_macos.zsh。WSL 執行所走的路徑 testapp/test_support/test_common.zsh 完全沒有提及
# results.csv2，因此在那裡發生的事沒有任何管道進入矩陣。2026-09-07 實測：462 筆記錄中，只有一筆
# 寫著 `wsl`（P8，2026-08-27），而 testapp/output/screenshots 中有 21 支不同的 app 留有
# 2026-08-29 至 2026-09-02 的 WSLg 截圖。被記錄的集合與實際執行的集合互不相交，於是矩陣對著確實
# 做過的工作，回報了一個空白的 WSL 欄位。
#
# 以 sweep_drive_macos.zsh 為藍本，而非 sweep_drive.zsh。後者是 Windows 驅動器，其檔頭亦如此
# 聲明：tasklist、taskkill、gdigrab、Pn.exe，以及寫死的 `platform=windows`。這些在此處都不適用。
#
# 與 macOS 對應版一樣，本腳本只是一個迴圈、一個讀取者與一個追加者。`test.zsh <Pn> --wsl` 本就會
# 同步、建置、在 WSLg 下啟動、等待 render marker、截圖並收尾——wait_for_marker_wsl、
# print_summary_wsl、print_renderer_wsl 與 run_wsl 全都位於 test_common.zsh。重新實作其中任何
# 一項，等於多出一個必須維持正確的東西，而 verified-test-process.md 明講「不要另寫測試框架」。
#
# 此處沒有 `-l` 旗標。sweep_drive.zsh 之所以有，是因為 Windows 帶有兩個 backend 而標籤要挑選
# 執行檔；WSLg 下只有一個，因此提供選項等於提供一個並不存在的選擇。資料列一律是
# `platform=wsl,backend=gtk4`，也就是 coverage.zsh 的 `wsl/gtk4` 欄位鍵——配對不符任何欄位的執行
# 會被回報於 stderr 而非直接捨棄，因此一個看似合理的 `linux` 或 `gtk` 會使每支 app 都讀起來像
# 「從未測試」，而本腳本卻回報成功。
#
# `-n` 在此代表 --dry-run，而非 --no-build。那是 sweep_drive_macos.zsh 的寫法，此處予以沿用而非
# 「改良」，因為兩支旗標互相矛盾的 sweep 驅動器，比一個名稱衝突更糟。test_common.zsh 的 `-n` 是
# --no-build；本腳本自行逐支 app 決定是否建置，且從不轉送裸的 `-n`。
#
# 各欄位的讀法：
#
#   launch   `ok` 表示該 app 完成繪製，或它未宣告 marker 而以計時方式截圖；`no marker` 表示它
#            宣告了 marker 卻從未出現；`fail` 表示它從未啟動，或 EGL 預檢拒絕了該 renderer
#   replay   `ok` 表示該 app 自身的 `-actionfile: replayed` 出現在它的 WSL 記錄檔中。它的意思是
#            「重放執行到完成」。本平台沒有任何東西會回報是哪個視窗收到了那些點擊，因此它並不
#            主張點擊落在該 app 上。`n/a` 表示 testapp/actions/wsl 中沒有對應的動作檔，且沒有
#            任何東西驗證過內容——該列於是只代表一次啟動與一次擷取，而 note 會如實說明
#   capture  取自本次執行的「最後一行」`captured from`，因為一次執行會拍兩到三張截圖，而只有
#            最後一張構成證據。`window` 為真正的視窗擷取，`desktop` 為全螢幕回退，`n/a` 為
#            完全沒有擷取行
#
# 沒有任何欄位是由結束狀態推斷而來。一張截圖證明的是「啟動了」與「擷取到了」，它不證明「通過」。
# `launch=ok,replay=n/a,capture=window` 是此處多數 app 的如實樣貌，也就照這樣寫下。
#
# 下方程式碼中有兩個 Windows 到 WSL 的陷阱是關鍵，且兩者都是靜默的：
#
#   1. 每一次 wsl.exe 呼叫都需要 MSYS2_ARG_CONV_EXCL='*'，否則 Git Bash 的 MSYS runtime 會在
#      wsl.exe 看到 argv 之前改寫其中的 POSIX 路徑
#   2. `$var` 即使在單引號內也會在跨越邊界時被吃掉。2026-09-07 於本 shell 實測：
#        wsl.exe -- zsh -lc 'for n in A B; do printf "got %s\n" $n; done'
#      印出兩次 `got` 且其後空無一物；改為 `\$n` 則印出 A 與 B。因此本檔中沒有任何遠端命令含有
#      遠端側的 `$`。所有變數都在 Windows 側展開，並以字面文字傳遞。
#
# WSL 端的 checkout 是一份獨立、非 git 的副本，因此在那裡建置編到的是最後一次 rsync 過去的內容。
# 過期檢查因此在 rsync_WSL.zsh 之「後」執行，絕不在其前：隔著未同步的樹去比較 Windows 端的修改與
# WSL 端的執行檔，會對一支原始碼已變動的 app 回報「未過期」，而過期的執行檔記錄到的是另一個 app。
# 這並非假設——P37 與 P38 在 macOS 上被記為「宣告了 marker 卻從未出現」，原因純粹是它們的執行檔
# 早於它們所印出的診斷訊息。

# No `-e`. One app that fails must not take the sweep down with it; every
# outcome below is read out of the run's own output, and an aborted loop would
# leave the remaining apps unrecorded rather than recorded as failures.
# 不使用 `-e`。一支失敗的 app 不該拖垮整趟 sweep；下方每一項判定都是由該次執行自身的輸出讀出，
# 而中途中止的迴圈會使其餘 app 完全沒有記錄，而非被記為失敗。
set -uo pipefail

script_path="${0:A}"
sweep_dir="${script_path:h}"
testapp_dir="${sweep_dir:h}"
repo="${testapp_dir:h}"

results="$repo/matrix_coverage/results.csv2"

# Hard-coded to match test_common.zsh, which launches from exactly this path.
# If the two disagree, this script probes one tree and test.zsh runs another.
# 寫死以與 test_common.zsh 一致，後者正是自此路徑啟動。若兩者不一致，本腳本探測的是一棵樹，而
# test.zsh 執行的是另一棵。
wsl_distro=Ubuntu
wsl_repo=/home/lowei/proj/swift-cross-ui

platform=wsl
backend=gtk4
run_date="$(date +%F)"

# Line 2 through line 142: the whole header, BOTH halves.
#
# A hard-coded range silently truncates the synopsis the moment anything is
# added above it, and the column section is the part a reader came for. Widen it
# in the same edit that grows the header. sweep_drive.zsh stops at its English
# half and has a Chinese line saying `--help` prints both; the two disagreed for
# hours on 2026-09-07, which is the argument for printing all of it.
#
# 第 2 行至第 142 行：整個檔頭，「兩個半邊都印」。
#
# 寫死的範圍會在其上方新增任何內容的那一刻靜默截斷說明，而「各欄位的讀法」正是讀者前來尋找的
# 部分。檔頭變長時，請在同一次編輯中一併加寬。sweep_drive.zsh 只印到英文半邊為止，卻有一行中文
# 說明宣稱 `--help` 兩半都會印出來；兩者在 2026-09-07 互相矛盾了幾個小時，而那正是「全部印出」
# 的理由。
usage() { sed -n '2,142p' "$script_path" | sed 's/^# \{0,1\}//'; }

# --help answers before any work: before the host check, before wsl.exe, before
# the rsync, before a single build. A `--help` that fell through to a launcher
# once blocked for five minutes on a person who wanted a page of text.
# --help 在任何工作之前作答：在主機檢查之前、在 wsl.exe 之前、在 rsync 之前、在任何一次建置之前。
# 曾有一個落入啟動器的 `--help`，讓一個只想要一頁文字的人等了五分鐘。
dry_run=0
render_mode=hw
apps=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        -n|--dry-run) dry_run=1; shift ;;
        -render|--render)
            [ "$#" -gt 1 ] || { printf -- '%s requires hw or sw\n' "$1" >&2; exit 64; }
            render_mode="$2"; shift 2 ;;
        -render=*|--render=*) render_mode="${1#*=}"; shift ;;
        # Rejected before the Pn patterns, not after. An app name reaches a
        # `zsh -lc` string sent to WSL as literal text, so anything outside
        # [A-Za-z0-9-] would be the remote shell's syntax rather than a name.
        # 在 Pn 樣式之前就先拒絕，而非之後。app 名稱會以字面文字進入送往 WSL 的 `zsh -lc` 字串，
        # 因此 [A-Za-z0-9-] 以外的字元將成為遠端 shell 的語法，而不是一個名稱。
        *[!A-Za-z0-9-]*)
            printf 'Not a usable app name: %s\n' "$1" >&2; exit 64 ;;
        P<->|P<->-*) apps+=("$1"); shift ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 64 ;;
    esac
done

case "$render_mode" in
    hw|sw) ;;
    *) printf -- '-render must be hw or sw, not %s\n' "$render_mode" >&2; exit 64 ;;
esac

case "$(uname -s 2>/dev/null || printf unknown)" in
    MINGW*|MSYS*|CYGWIN*) ;;
    *)
        printf 'This is the WSL driver and it drives WSL through wsl.exe, so it\n' >&2
        printf 'needs a Windows host. Running it from inside WSL is not the same thing.\n' >&2
        exit 3 ;;
esac

[ -f "$results" ] || { printf '%s is missing; it is the history file\n' "$results" >&2; exit 1; }

if ! MSYS2_ARG_CONV_EXCL='*' wsl.exe -d "$wsl_distro" -- true >/dev/null 2>&1; then
    printf 'wsl.exe -d %s did not answer. Start the distro and try again.\n' "$wsl_distro" >&2
    printf 'This script never starts, stops or restarts WSL itself.\n' >&2
    exit 1
fi

# A locked or input-refusing desktop makes every instrument return a plausible
# negative instead of an error: a desktop capture yields the lock screen, and a
# window capture keeps returning the app drawn perfectly because BitBlt reads a
# window that is not on screen. Sweeping into that produces rows that look fine
# and mean nothing, so it is refused rather than warned about.
# 一個被鎖定或拒絕輸入的桌面，會讓每一項儀器回傳貌似合理的否定結果而非錯誤：桌面擷取拍到鎖定畫面，
# 而視窗擷取仍持續回傳畫得好好的 app，因為 BitBlt 讀的是一個並不在螢幕上的視窗。在那種狀態下 sweep
# 會產出看起來正常卻毫無意義的資料列，因此予以拒絕，而不只是警告。
lock_state="$(zsh "$testapp_dir/ui-lock.zsh" status 2>&1 || true)"
case "$lock_state" in
    *"refused our input"*)
        printf '%s\n' "$lock_state" >&2
        printf 'Refusing to sweep: captures taken now would look good and prove nothing.\n' >&2
        exit 4 ;;
esac

# One command, no remote-side `$`, and `find` rather than a glob: a `P*.swift`
# glob under `zsh -lc` aborts with "no matches found" on a tree that has none,
# which reads as a broken probe rather than an empty directory.
# 單一命令、沒有遠端側的 `$`，且使用 `find` 而非 glob：在沒有任何符合檔案的樹上，`zsh -lc` 下的
# `P*.swift` glob 會以「no matches found」中止，那讀起來像是探測壞掉，而不像是目錄是空的。
probe_cmd='cd ~/proj/swift-cross-ui/testapp 2>/dev/null || exit 1; find . -maxdepth 1 -name "P*.swift" -printf "src %T@ %f\n" 2>/dev/null; cd output 2>/dev/null || exit 0; find . -maxdepth 1 -type f -executable -printf "bin %T@ %f\n" 2>/dev/null'

# Sources first, then measure. rsync -a preserves mtimes, so after this the WSL
# copy carries the Windows timestamps and the comparison below is meaningful.
# In --dry-run nothing is written anywhere, WSL included, so the staleness
# reading is against whatever WSL already holds and is labelled as such.
# 先同步原始碼，再量測。rsync -a 會保留 mtime，因此在此之後 WSL 端的副本帶有 Windows 端的時間戳，
# 下方的比較才有意義。在 --dry-run 下不會對任何地方寫入（WSL 亦然），因此過期判讀是針對 WSL 端
# 目前既有的內容，並會如此標示。
if [ "$dry_run" -eq 0 ]; then
    printf '==> Syncing sources to WSL\n'
    zsh "$testapp_dir/rsync_WSL.zsh" >/dev/null || {
        printf 'rsync_WSL.zsh failed; a build here would compile stale sources.\n' >&2
        exit 1
    }
fi

probe="$(MSYS2_ARG_CONV_EXCL='*' wsl.exe -d "$wsl_distro" -- zsh -lc "$probe_cmd" 2>/dev/null \
    | tr -d '\r' || true)"

typeset -A src_mtime bin_mtime
while IFS=' ' read -r kind stamp name; do
    case "$kind" in
        src) src_mtime[${name%.swift}]="${stamp%%.*}" ;;
        bin) bin_mtime[$name]="${stamp%%.*}" ;;
    esac
done <<< "$probe"

# Every app that has both a loader here and a build over there.
#
# Both, not either. Without a loader `test.zsh` cannot run it; without a build
# there is nothing to run, and the build check has to be made in WSL because
# that is where the binary lives -- testapp/output on the Windows side holds
# Pn-gtk4.exe and Pn-WinUI.exe, which are different files for a different
# platform. sweep_build.zsh is the pair for building.
#
# `(nN)` on the glob: numeric sort, so the table reads P0, P1, P2 rather than
# P0, P1, P10. `N` so an empty directory yields an empty list instead of an
# error.
#
# 兩者皆需，而非其一。缺少 loader，`test.zsh` 無從執行；缺少建置產物則無物可執行，而「是否已建置」
# 必須在 WSL 端判斷，因為執行檔在那裡——Windows 端的 testapp/output 放的是 Pn-gtk4.exe 與
# Pn-WinUI.exe，那是屬於另一個平台的另一批檔案。負責建置的是 sweep_build.zsh。
#
# glob 上的 `(nN)`：數值排序，使表格讀起來是 P0、P1、P2 而非 P0、P1、P10。`N` 則讓空目錄產出空
# 清單而非錯誤。
if [ "${#apps[@]}" -eq 0 ]; then
    for loader in "$testapp_dir/test_support"/test_P*.zsh(nN); do
        name="${loader:t:r}"; name="${name#test_}"
        [ -n "${bin_mtime[$name]:-}" ] && apps+=("$name")
    done
else
    # Named apps are checked, not assumed. An app with no loader or no WSL
    # build is dropped with a reason on stderr rather than recorded: a row
    # describes a run, and no run happened.
    # 明確指名的 app 會被檢查而非直接採信。沒有 loader 或沒有 WSL 建置的 app 會在 stderr 上附上
    # 理由後剔除，而不予記錄：一筆資料列描述的是一次執行，而此處並沒有執行發生。
    kept=()
    for name in "${apps[@]}"; do
        if [ ! -f "$testapp_dir/test_support/test_$name.zsh" ]; then
            printf 'Skipping %s: no testapp/test_support/test_%s.zsh\n' "$name" "$name" >&2
        elif [ -z "${bin_mtime[$name]:-}" ]; then
            printf 'Skipping %s: not built in %s/testapp/output\n' "$name" "$wsl_repo" >&2
        else
            kept+=("$name")
        fi
    done
    apps=("${kept[@]}")
fi

if [ "${#apps[@]}" -eq 0 ]; then
    printf 'Nothing to sweep: no app has both a loader here and a build in WSL.\n' >&2
    exit 1
fi

# The action files for one app, with the ones belonging to a longer-named app
# removed. `$app-*.csv` is a prefix glob and some apps are prefixes of others
# -- P15 and P15-DARK, P6 and P6-v2, P17 and P17-DOE -- so asking for P15 also
# matches P15-DARK's file. test_common.zsh's default_action_file carries the
# same filter and reports "Several action files for P15", which reads as two
# files for one app rather than one file each for two apps.
#
# 某支 app 的動作檔，並剔除屬於「名稱更長的另一支 app」的那些。`$app-*.csv` 是前綴 glob，而有些
# app 的名稱正是另一些的前綴——P15 與 P15-DARK、P6 與 P6-v2、P17 與 P17-DOE——因此要求 P15 時會
# 一併匹配到 P15-DARK 的檔案。test_common.zsh 的 default_action_file 帶有相同的篩選，並會回報
# 「Several action files for P15」，那讀起來像是「一支 app 有兩個檔案」，而實際上是「兩支 app 各
# 有一個檔案」。
action_candidates() {
    local app_name="$1"
    local cand other cand_name claimed
    local -a cands others kept
    cands=("$testapp_dir/actions/wsl/$app_name"-*.csv(N))
    if [ "${#cands}" -le 1 ]; then
        [ "${#cands}" -gt 0 ] && printf '%s\n' "${cands[@]}"
        return 0
    fi
    others=("$testapp_dir"/"$app_name"-*.swift(N:t:r))
    for cand in "${cands[@]}"; do
        cand_name="${cand:t}"
        claimed=0
        for other in "${others[@]}"; do
            if [[ "$cand_name" == "$other"-* ]]; then
                claimed=1
                break
            fi
        done
        [ "$claimed" -eq 0 ] && kept+=("$cand")
    done
    [ "${#kept}" -gt 0 ] && cands=("${kept[@]}")
    printf '%s\n' "${cands[@]}"
}

add_note() { note="${note:+$note; }$1"; }

printf '==> %d app(s) on %s/%s, -render %s, %s\n' \
    "${#apps[@]}" "$platform" "$backend" "$render_mode" "$run_date"
if [ "$dry_run" -eq 1 ]; then
    printf '    dry run: nothing was synced, so staleness is against the WSL tree as it stands\n'
fi
printf '\n'

# Leftovers from an EARLIER session, cleared once before the loop.
#
# test_common.zsh's kill_existing already handles the app about to run, and
# run_wsl pkills it again after the captures, so nothing this sweep starts
# survives into the next app. What it cannot see is a different Pn left up by
# something else: screenshot.zsh matches by title, so a stale WSLg window gives
# a capture that looks perfectly good and photographs the wrong process. That
# happened on 2026-09-02 -- a WSLg P43 was still up and the "WinUI" capture was
# really the GTK one, identical down to the title bar.
#
# Built as literal text from names already restricted to [A-Za-z0-9-], and
# never as `pkill -x` over a pattern: the one time a variable was interpolated
# into a destructive command sent through `wsl.exe -lc`, it expanded to
# `rm -rf /*` and emptied a home directory.
#
# 清除「更早的 session」留下的殘骸，於迴圈前執行一次。
#
# test_common.zsh 的 kill_existing 已處理即將執行的那一支，而 run_wsl 在截圖後會再 pkill 一次，
# 因此本 sweep 所啟動的東西不會存活到下一支 app。它看不到的是「別的東西留下的另一支 Pn」：
# screenshot.zsh 依標題比對，因此一個殘留的 WSLg 視窗會給出一張看起來完全正常、卻拍到錯誤 process
# 的截圖。2026-09-02 就發生過——一個 WSLg 的 P43 還開著，那張「WinUI」截圖其實是 GTK 的，連標題列
# 都一模一樣。
#
# 由「已限定為 [A-Za-z0-9-] 的名稱」組成字面文字，而不是對某個樣式下 `pkill -x`：唯一一次把變數
# 插入透過 `wsl.exe -lc` 送出的破壞性命令中，它展開成了 `rm -rf /*`，清空了一個家目錄。
if [ "$dry_run" -eq 0 ]; then
    kill_cmd=""
    for app in "${apps[@]}"; do
        kill_cmd="${kill_cmd}pkill -x ${app} 2>/dev/null; "
    done
    kill_cmd="${kill_cmd}true"
    MSYS2_ARG_CONV_EXCL='*' wsl.exe -d "$wsl_distro" -- zsh -lc "$kill_cmd" >/dev/null 2>&1 || true
fi

printf '%-9s %-9s %-8s %-8s %s\n' app launch replay capture note

appended=0
preflight_failed=0

for app in "${apps[@]}"; do
    # Cleared per app. A note that survives into the next iteration attributes
    # one app's finding to another.
    # 每支 app 都重設。殘留到下一輪的 note，會把某支 app 的發現安到另一支頭上。
    note=""

    action_args=()
    action_files=("${(@f)$(action_candidates "$app")}")
    # `(@f)` on an empty string yields one empty element, so the count is not
    # the test -- the first element being empty is.
    # 對空字串使用 `(@f)` 會產生一個空元素，因此判斷依據不是元素個數，而是第一個元素是否為空。
    if [ -n "${action_files[1]:-}" ]; then
        if [ "${#action_files[@]}" -gt 1 ]; then
            # One is replayed and the row names it. The alternative -- passing
            # a bare --actionfile -- makes test_common.zsh exit 64 with
            # "Several action files", which would record nothing at all for
            # five of the apps that have the most replay coverage.
            # 只重放其中一個，並在資料列中指名。另一種做法——傳裸的 --actionfile——會讓
            # test_common.zsh 以「Several action files」結束並回傳 64，那將使重放覆蓋最完整的
            # 五支 app 完全沒有任何記錄。
            add_note "replayed ${action_files[1]:t} only; ${#action_files[@]} action files exist for $app"
        fi
        action_args=(--actionfile "${action_files[1]}")
    fi

    # Reuse the WSL build, except when it is stale or when replaying.
    #
    # `-actionfile` is compiled out unless the binary was built with
    # SCUI_DEBUG, and test_common.zsh only sets that when an action file is
    # asked for. So `-n` plus `--actionfile` produces an app with no replay
    # support and a run that reports nothing.
    #
    # Staleness is the other half: reusing a build is the point of a sweep, but
    # reusing a stale one records the wrong app. Both timestamps come from the
    # WSL side, post-rsync, so they are the same clock -- comparing a Windows
    # mtime against a WSL one would compare two filesystems.
    #
    # 重用 WSL 端的建置，但在它過期或需要重放時例外。
    #
    # 除非執行檔是以 SCUI_DEBUG 建置，否則 `-actionfile` 會被編譯掉；而 test_common.zsh 僅在確實
    # 要求動作檔時才設定該變數。因此「`-n` 加上 `--actionfile`」會產出一個不具重放支援的 app，
    # 其執行結果什麼也不回報。
    #
    # 過期判斷是另一半：重用既有建置正是 sweep 的意義所在，但重用過期的建置記錄到的是另一個 app。
    # 兩個時間戳都取自 WSL 端、且在 rsync 之後，因此是同一個時鐘——拿 Windows 的 mtime 去比 WSL 的
    # mtime，比的是兩個檔案系統。
    build_args=(-n)
    src_stamp="${src_mtime[$app]:-}"
    bin_stamp="${bin_mtime[$app]:-}"
    if [ "${#action_args[@]}" -gt 0 ]; then
        build_args=()
    elif [ -n "$src_stamp" ] && [ -n "$bin_stamp" ] && [ "$src_stamp" -gt "$bin_stamp" ]; then
        build_args=()
        add_note "rebuilt: the WSL binary was older than $app.swift"
    fi

    if [ "$dry_run" -eq 1 ]; then
        if [ "${#build_args[@]}" -eq 0 ]; then plan=build; else plan=reuse; fi
        if [ "${#action_args[@]}" -gt 0 ]; then plan="$plan+replay"; fi
        # The note is printed here too, not swallowed. It is where the choice
        # of action file appears, and an app with five of them would otherwise
        # look identical to one with a single unambiguous file.
        # 此處也印出 note，而非吞掉它。動作檔的選擇正是顯示在那裡，否則一支有五個動作檔的 app
        # 看起來會與一支只有單一明確檔案的 app 一模一樣。
        printf '%-9s %-9s %-8s %-8s %s\n' "$app" "-" "-" "-" "would $plan${note:+; $note}"
        continue
    fi

    zsh "$testapp_dir/ui-lock.zsh" release "test-${app:l}" >/dev/null 2>&1 || true

    # No showtime when there is nothing to replay; enough of one when there is.
    # `--no-showtime` closes the app as soon as it renders, which truncates a
    # replay still in progress -- measured on macOS P26, whose action file
    # clicks a tab and then sleeps three seconds. Ten seconds, not the eight
    # that first worked: a value chosen to just clear the only case in front of
    # you is the value that truncates the next one.
    # 沒有東西要重放時不留時間；有的時候則留足夠的時間。`--no-showtime` 會在 app 完成繪製後立刻
    # 關閉它，而那會截斷仍在進行中的重放——在 macOS 的 P26 上實測過，其動作檔會點擊分頁再等三秒。
    # 十秒而非最初可行的八秒：「剛好夠用於眼前唯一案例」的數值，正是會截斷下一個案例的數值。
    show_args=(--no-showtime)
    [ "${#action_args[@]}" -gt 0 ] && show_args=(--showtime 10)

    # A WSL build is a Swift compile on the Linux side, which is minutes rather
    # than seconds, so the two ceilings are not the same number. The macOS twin
    # uses one 900s value because its builds are local and incremental.
    # WSL 端的建置是在 Linux 側編譯 Swift，耗時以分鐘計而非秒計，因此兩種上限並非同一個數字。
    # macOS 對應版之所以只用一個 900 秒的值，是因為它的建置在本機且為增量式。
    if [ "${#build_args[@]}" -eq 0 ]; then app_timeout=2400; else app_timeout=900; fi

    if out="$(timeout "$app_timeout" zsh "$testapp_dir/test.zsh" "$app" --wsl \
        -render "$render_mode" "${show_args[@]}" "${build_args[@]}" "${action_args[@]}" 2>&1)"; then
        rc=0
    else
        rc=$?
    fi

    # Every column is read out of what happened, never assumed. A sweep that
    # writes `ok` because the command returned 0 records the thing it was
    # supposed to measure.
    #
    # The preflight case is first and is not redundant. wsl_renderer_preflight
    # runs before the launch and returns non-zero under test_common.zsh's
    # `set -e`, so the run dies with none of the other markers present -- the
    # fallback would then read `never launched`, which blames the app for an
    # EGL setting.
    #
    # 每一欄都由「實際發生了什麼」讀出，絕不假設。一支因為「指令回傳 0」就寫下 `ok` 的 sweep，
    # 記錄的正是它本應去量測的那件事。
    #
    # preflight 的分支排在最前，且並非多餘。wsl_renderer_preflight 在啟動之前執行，並在
    # test_common.zsh 的 `set -e` 下以非零值返回，因此該次執行會在其他標記都尚未出現時就結束
    # ——若落到最後的預設分支，會讀成 `never launched`，把一個 EGL 設定的問題怪到 app 頭上。
    #
    # Three outcomes for the marker, not two, and the middle one is the trap.
    # An app with no TEST_MARKER is not failing when no marker appears; most
    # have none, and test_common.zsh says so in the output and falls back to
    # timed capture. Reading only "did a marker appear" put eleven such apps
    # into the macOS matrix as problems that do not exist.
    # marker 有三種結果而非兩種，而中間那一種正是陷阱。沒有設定 TEST_MARKER 的 app，在沒有 marker
    # 出現時並非失敗；多數 app 都沒有設，而 test_common.zsh 會在輸出中明講並改用計時截圖。只判讀
    # 「marker 有沒有出現」，曾把十一支這樣的 app 當成並不存在的問題寫進 macOS 的矩陣。
    case "$out" in
        *"Renderer preflight failed"*)
            launch=fail
            preflight_failed=1
            add_note "EGL preflight refused -render $render_mode; no app was launched" ;;
        *"rendered after"*)
            launch=ok ;;
        *"No render marker configured"*)
            launch=ok; add_note "no marker configured; capture is timed" ;;
        *"Launching"*)
            launch='no marker'; add_note "declares a marker that never appeared" ;;
        *)
            launch=fail; add_note "never launched" ;;
    esac

    # A build failure does not stop run_wsl -- the grep that reads the build
    # output ends in `|| true` -- so the launch that follows uses whatever
    # binary was already there. Without this the row would describe the old
    # build under today's date.
    # 建置失敗不會中止 run_wsl——讀取建置輸出的那個 grep 以 `|| true` 結尾——因此隨後的啟動用的是
    # 原本就在那裡的執行檔。少了這一項，該列會以今天的日期描述舊的建置。
    if [ "${#build_args[@]}" -eq 0 ]; then
        case "$out" in
            *"error:"*)
                add_note "WSL build reported: $(printf '%s' "$out" | grep -m1 'error:' | cut -c1-80)" ;;
        esac
    fi

    if [ "$rc" -eq 124 ]; then
        add_note "test.zsh was killed after ${app_timeout}s; anything after that point is unknown"
        MSYS2_ARG_CONV_EXCL='*' wsl.exe -d "$wsl_distro" -- zsh -lc \
            "pkill -x ${app} 2>/dev/null; true" >/dev/null 2>&1 || true
    fi

    # The replay verdict is read from the app's own log, and that log is in
    # WSL. run_wsl launches with `2>$actionfile_log` inside the Linux output
    # directory, so the `-actionfile:` line never reaches this terminal and
    # never reaches the Windows checkout either. Reading `$out` for it, or
    # reading the Windows-side file, records `no line` against a run whose log
    # said "replayed" all along.
    # 重放的判定讀自 app 自身的記錄檔，而那個檔案在 WSL。run_wsl 是在 Linux 端的 output 目錄下以
    # `2>$actionfile_log` 啟動，因此 `-actionfile:` 那一行既不會抵達本終端，也不會出現在 Windows
    # 端的 checkout。去 `$out` 裡找它、或去讀 Windows 端的檔案，會在一次記錄檔明明寫著「replayed」
    # 的執行上記下 `no line`。
    if [ "${#action_args[@]}" -eq 0 ]; then
        replay=n/a
        add_note "no action file in testapp/actions/wsl; nothing verified the content"
    else
        replay_out="$(MSYS2_ARG_CONV_EXCL='*' wsl.exe -d "$wsl_distro" -- zsh -lc \
            "cat $wsl_repo/testapp/output/${app:l}-actionfile.log 2>/dev/null; true" 2>/dev/null \
            | tr -d '\r' || true)"
        case "$replay_out" in
            *"-actionfile: replayed"*) replay=ok ;;
            *"-actionfile: failed"*)
                replay=fail
                add_note "$(printf '%s' "$replay_out" | grep -m1 'actionfile: failed' | cut -c1-80)" ;;
            *)
                replay='no line'
                add_note "no -actionfile line in the WSL log -- built without SCUI_DEBUG, or the app died first" ;;
        esac
    fi

    # The LAST capture line, not any of them. A run takes an early screenshot
    # one second in and a final one after the marker; the early one often finds
    # no window yet, and `case "$out" in *"priority 1"*` would let either
    # decide the column. Only the final capture is the evidence.
    # 取「最後一行」擷取記錄，而非任何一行。一次執行會在一秒時拍一張早期截圖、並在 marker 之後拍
    # 一張最終截圖；早期那張常常還找不到視窗，而 `case "$out" in *"priority 1"*` 會讓其中任何一張
    # 決定該欄位。只有最終那張截圖才是證據。
    capture_line="$(printf '%s\n' "$out" | grep 'captured from' | tail -1 || true)"
    case "$capture_line" in
        *"priority 1"*) capture=window ;;
        *"priority 2"*|*desktop*)
            capture=desktop
            add_note "window capture fell back to the screen" ;;
        "")
            case "$out" in
                *"no screenshot"*) capture=fail; add_note "screenshot.zsh produced no image" ;;
                *) capture=n/a; add_note "no capture line in the output; whether an image exists is unknown" ;;
            esac ;;
        *) capture=n/a; add_note "unrecognised capture line: $(printf '%s' "$capture_line" | cut -c1-60)" ;;
    esac

    printf '%-9s %-9s %-8s %-8s %s\n' "$app" "$launch" "$replay" "$capture" "$note"

    # Appended with csv2, not with `printf >>`. It validates the input before
    # writing, reads the existing file to check its final record, and writes
    # only the appended bytes. A note here can hold a comma and a quote -- a
    # compiler diagnostic, an action file name -- and hand-quoting per RFC 4180
    # is how a malformed row reaches whatever reads it next.
    # 以 csv2 追加，而非 `printf >>`。它會在寫入前驗證輸入、讀取既有檔案以檢查其最後一筆記錄，
    # 並且只寫入所追加的位元組。此處的 note 可能含有逗號與引號——編譯器診斷、動作檔名稱——而自行
    # 依 RFC 4180 加引號，正是格式錯誤的資料列被下一個讀取者發現的成因。
    if csv2 -append "$run_date,$platform,$backend,$app,$launch,$replay,$capture,\"${note//\"/\"\"}\"" \
        -i "$results" --in-place; then
        appended=$(( appended + 1 ))
    else
        printf '!! csv2 refused the row for %s; it was NOT recorded\n' "$app" >&2
    fi

    # An EGL failure is a fact about this host, not about this app, so every
    # remaining row would repeat it. The one row above is kept -- it is true --
    # and the sweep stops rather than writing forty-six more copies of it.
    # EGL 失敗是關於這台主機的事實，而非關於這支 app，因此其餘每一列都只會重複同一件事。上方那一
    # 列予以保留——它是真的——而 sweep 就此停止，不再寫下另外四十六份相同的副本。
    if [ "$preflight_failed" -eq 1 ]; then
        printf '\n!! The EGL preflight refused -render %s on this host.\n' "$render_mode" >&2
        printf '!! Nothing was launched. Try: %s -render sw\n' "${script_path:t}" >&2
        break
    fi
done

if [ "$dry_run" -eq 0 ]; then
    printf '\nAppended %d row(s) to %s\n' "$appended" "${results#$repo/}"
    printf 'Regenerate the matrix with: zsh matrix_coverage/coverage.zsh\n'
fi
