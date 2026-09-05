#!/usr/bin/env zsh
# Launches every already-built P1-P26 app, replays its action file, captures it.
#
#   zsh testapp/sweep-test/sweep_drive.zsh                 every app
#   zsh testapp/sweep-test/sweep_drive.zsh -l gtk4         label the run
#   zsh testapp/sweep-test/sweep_drive.zsh P8 P19          just these
#   zsh testapp/sweep-test/sweep_drive.zsh --help
#
# The pair to sweep_build.zsh, and it does not build. See that script's header
# for why the two are separate; the short version is that this half needs an
# unlocked desktop and that half does not, and this half keeps the desktop
# unlocked by itself because synthesised input resets the idle timer.
#
# `-l` NOW CHOOSES THE BACKEND as well as naming the run: `gtk4` drives
# `Pn-gtk4.exe`, `winui` drives `Pn-WinUI.exe`.
#
# It used to be a label only, and the header said so: "it does not choose a
# backend; the backend is whatever testapp/output/Pn.exe happens to be". That
# stopped being true when executables gained their backend suffix -- there is no
# `Pn.exe` any more, so this script reported `never built` for every app while
# forty-three binaries sat in that directory. The old arrangement also had the
# failure the old header warned about, `-l gtk4` after a WinUI build producing a
# silently wrong table; deriving the filename from the label removes both, since
# the label can no longer disagree with what is run.
#
# `-l` **現在同時選擇 backend**，而不只是為本次執行命名：`gtk4` 驅動 `Pn-gtk4.exe`，
# `winui` 驅動 `Pn-WinUI.exe`。
#
# 它過去只是個標籤，檔頭也是這麼寫的：「它不會選擇 backend；實際的 backend 取決於
# testapp/output/Pn.exe 當下是哪一個」。當執行檔加上 backend 後綴之後，那句話就不再成立——
# 已經沒有 `Pn.exe` 了，於是本腳本在那個目錄裡躺著四十三個執行檔的情況下，對每一個 app 都回報
# `never built`。舊做法同時帶有舊檔頭所警告的那種失敗：在 WinUI 建置之後傳 `-l gtk4`，會產生
# 一份靜默錯誤的表格。由標籤推導檔名可同時消除這兩者，因為標籤再也無法與實際執行的對象相左。
#
# Reading the columns:
#
#   launch    the process is still alive when the capture is taken; STALE means
#             the exe predates the window-choice fix and was not run at all
#   replay    the app's own `-actionfile:` line, which needs a SCUI_DEBUG build.
#             `ok` finished AND every click landed on the app; `ASTRAY` finished
#             with clicks on some other window, so it proves nothing; `CHECKER`
#             means this script's own hit test is broken, not the run
#   capture   `window` is a real window capture; `desktop` is the fallback
#
# `desktop` is expected for WinUI and a problem for GTK. WinUI draws through
# DirectComposition, `BitBlt` returns black, and testapp/screenshot.zsh falls
# back -- documented in its own header. GTK draws through OpenGL/WGL and
# captures properly, so a `desktop` there means the window was not found.
#
# 啟動每一個已建置好的 P1-P26 app，重放其動作檔，並擷取畫面。
#
# 與 sweep_build.zsh 成對，且本腳本不做建置。兩者為何分開，見該腳本的檔頭；簡言之，這一半需要
# 解鎖的桌面而那一半不需要，而且這一半會自行維持桌面不被鎖定——因為合成輸入會重置閒置計時器。
#
# `-l` 只是為本次執行命名：它會出現在截圖檔名與表格標題中。它**不會**選擇 backend。實際的 backend
# 取決於 `testapp/output/Pn.exe` 當下是哪一個，也就是最後一次建置的產物。在 WinUI 建置之後傳入
# `-l gtk4`，會產生一份錯誤的表格，而且沒有任何其他東西會抓到——請傳入你實際建置的那一個。
#
# 各欄位的讀法：
#
#   launch    擷取當下該行程仍然存活；STALE 代表該 exe 早於視窗選擇修正，因而根本沒有執行
#   replay    app 自己輸出的 `-actionfile:` 行，需要 SCUI_DEBUG 建置才會存在。
#             `ok` 表示跑完**且**每一次點擊都落在該 app 上；`ASTRAY` 表示跑完了、但點擊落在
#             別的視窗上，因此什麼也證明不了；`CHECKER` 表示壞的是本腳本自己的命中檢查，
#             而不是那次執行
#   capture   `window` 為真正的視窗擷取；`desktop` 為回退
#
# 對 WinUI 而言 `desktop` 是預期的，對 GTK 而言則是問題。WinUI 透過 DirectComposition 繪製，
# `BitBlt` 會回傳全黑，因此 testapp/screenshot.zsh 會回退——這在其自身檔頭已有記載。GTK 透過
# OpenGL/WGL 繪製，擷取完全正常，因此在 GTK 上出現 `desktop`，代表視窗根本沒被找到。

set -uo pipefail

script_path="${0:A}"
repo="${${script_path:h}:h:h}"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    # Through line 48, the end of the English half. Widened when the header grew
    # -- a hard-coded range silently truncates the synopsis the moment anything
    # is added above it, and the columns section is the part a reader came for.
    # 至第 48 行，即英文段落的結尾。標頭變長時一併加寬——寫死的範圍會在其上方新增任何內容的那一刻
    # 靜默截斷說明，而「各欄位的讀法」正是讀者前來尋找的部分。
    sed -n '2,48p' "$script_path" | sed 's/^# \{0,1\}//'
    exit 0
fi

label=gtk4
if [ "${1:-}" = "-l" ]; then
    if [ "$#" -lt 2 ]; then
        printf 'sweep_drive.zsh: -l needs a label\n' >&2
        exit 64
    fi
    label="$2"
    shift 2
fi

# The suffix the build actually writes. Cased as compile.zsh writes it -- the
# filesystem is case-insensitive here but a name that does not match what is on
# disk is a trap on any other machine.
# 建置實際寫出的後綴。大小寫依 compile.zsh 的寫法——此處的檔案系統不分大小寫，但一個與磁碟上
# 不相符的名稱，在任何其他機器上都是陷阱。
case "$label" in
    winui|WinUI) suffix=-WinUI ;;
    gtk4) suffix=-gtk4 ;;
    *)
        printf 'sweep_drive.zsh: -l must be gtk4 or winui, not %s\n' "$label" >&2
        exit 64
        ;;
esac

out="$repo/testapp/output"
actions="$repo/testapp/actions/win"
log_dir="/tmp/sweep_drive-$label"
mkdir -p "$log_dir"

# Where each run's rows are appended. The file is the history; coverage.zsh
# renders the current matrix out of it. Rows accumulate -- nothing is ever
# rewritten -- so an old result stays visible with its own date rather than
# being replaced by a newer one that might have tested something different.
#
# `windows` is hard-coded because this script is the Windows driver: it uses
# tasklist, taskkill and gdigrab. A WSL driver would append `wsl` rows to the
# same file.
#
# 每次執行的資料列都追加至此。該檔案即是歷史；coverage.zsh 由它算繪出當前的矩陣。資料列只增不改
# ——從不覆寫——因此舊的結果會連同它自己的日期一併留著，而不會被一個「可能測的是別的東西」的新結果
# 取代。
#
# `windows` 寫死，因為本腳本就是 Windows 的驅動器：它使用 tasklist、taskkill 與 gdigrab。WSL 的
# 驅動器會把 `wsl` 的資料列追加到同一個檔案。
results="$repo/matrix_coverage/results.csv2"
platform=windows
run_date="$(date +%F)"

if [ ! -f "$results" ]; then
    printf 'sweep_drive.zsh: %s is missing; it is the history file and ships with the repo\n' \
        "$results" >&2
    exit 1
fi

export PATH="/c/gtk4/bin:$PATH"

# The commit that decided which window the replay drives. Looked up rather than
# hard-coded as a date, so it stays right if the branch is rebased.
# 決定「重放要驅動哪一個視窗」的那個 commit。以查詢取得而非寫死日期，如此在分支被 rebase 之後
# 它仍然正確。
fix_commit=2d163c9b
fix_epoch="$(git -C "$repo" log -1 --format=%ct "$fix_commit" 2>/dev/null)"

winmin="$repo/testapp/helper/bin/winmin.exe"

# CLEAR FIRST, THEN DISMISS, and the order is the whole of it.
#
# Windows grants a foreground change only to a process already in front, owning
# the last input, or finding no foreground window; an app launched from a shell
# is none of those, so the replay pins itself topmost instead. That carries
# mouse files. Keys cannot ride it -- a key event goes to whatever holds focus
# -- so the synthesiser refuses outright, and on 2026-09-06 all three keyboard
# files in actions/win refused: P10-ctrl-q, P18-three-dialogs,
# P31-tab-and-escape, which is every file there carrying a key and no others.
#
# What held the foreground was `SearchHost.exe`, the Start menu's search
# surface, class Windows.UI.Core.CoreWindow. It is a protected UWP process, so
# AttachThreadInput to it returns ACCESS_DENIED, and it ate two of P10's clicks
# as well. `--clear` cannot touch it: a CoreWindow ignores the
# WM_SYSCOMMAND/SC_MINIMIZE that --clear sends. `--dismiss` presses Escape at
# it, which is what a person does to that window -- the process keeps running.
#
# Order, measured: after a `--clear` the foreground is `Shell_TrayWnd` or
# SearchHost, because minimising everything is exactly what hands the foreground
# to the shell. Dismissing before the clear dismisses the wrong moment. Clearing
# first and dismissing last leaves `Progman` in front -- explorer.exe, which
# attaches without complaint -- and P31 went from refusing to run to REACTED.
#
# Twice, because dismissing one surface can promote another: three attempts of
# one file saw Shell_TrayWnd, SearchHost and Progman in turn.
#
# **先 clear，後 dismiss**，而順序就是全部的關鍵。
#
# Windows 只把前景切換授予「已在前景」、「擁有最後一個輸入」或「找不到前景視窗」的行程；由 shell
# 啟動的 app 三者皆非，因此重放改為把自己釘為 topmost。那能撐住滑鼠檔案。按鍵則搭不上——按鍵事件
# 會送往持有焦點者——所以 synthesiser 會直接拒絕；而 2026-09-06，actions/win 中的三個鍵盤檔案
# 全部被拒：P10-ctrl-q、P18-three-dialogs、P31-tab-and-escape，恰好就是該目錄中帶按鍵的全部檔案。
#
# 當時持有前景的是 `SearchHost.exe`——「開始」選單的搜尋表面，類別 Windows.UI.Core.CoreWindow。
# 它是受保護的 UWP 行程，對它呼叫 AttachThreadInput 會得到 ACCESS_DENIED，而且它還吃掉了 P10 的
# 兩次點擊。`--clear` 碰不到它：CoreWindow 會忽略 --clear 送出的 WM_SYSCOMMAND/SC_MINIMIZE。
# `--dismiss` 對它按下 Escape，那正是人對該視窗會做的事——該行程繼續執行。
#
# 順序，實測：`--clear` 之後前景是 `Shell_TrayWnd` 或 SearchHost，因為「把所有東西最小化」正是
# 把前景交給 shell 的動作。在 clear 之前 dismiss，等於在錯誤的時機 dismiss。先 clear、最後
# dismiss，留在前面的是 `Progman`——explorer.exe，附加到它不會有任何抱怨——而 P31 也就從「拒絕
# 執行」變成了 REACTED。
#
# 做兩次，因為關掉一個表面可能讓另一個遞補：同一個檔案的三次嘗試依序遇上 Shell_TrayWnd、
# SearchHost 與 Progman。
clear_desktop() {
    [ -x "$winmin" ] || return 0
    "$winmin" --clear >/dev/null 2>&1
    "$winmin" --dismiss >/dev/null 2>&1
    "$winmin" --dismiss >/dev/null 2>&1
    sleep 1
}

if [ "$#" -gt 0 ]; then
    apps=("$@")
else
    apps=(P1 P2 P3 P4 P5 P7 P8 P9 P10 P11 P12 P13 P14 P15 P16 P17 P18 P19 P20 P21 P22 P23 P24 P25 P26)
fi

printf '=== drive: %s ===\n' "$label"
printf '%-30s %-8s %-9s %-9s %s\n' 'app / action file' launch replay capture note
printf '%s\n' '----------------------------------------------------------------------'

for app in $apps; do
    launch=- replay=- capture=- note=

    exe="$out/$app$suffix.exe"

    if [ ! -x "$exe" ]; then
        printf '%-30s %-8s %-9s %-9s %s\n' "$app" 'no exe' - - "no $app$suffix.exe"
        continue
    fi

    # IS THIS BINARY OLDER THAN THE FIX THAT DECIDES WHICH WINDOW TO DRIVE?
    # If it is, nothing the run says is about the app, and the check costs one
    # stat where finding out afterwards costs the whole sweep.
    #
    # 2d163c9b taught the synthesiser to skip a window owned by another visible
    # one. Before it, Direct Composition's `GdkWin32GL` content surface -- the
    # same size as its toplevel but at origin (0, 0) rather than (78, 78) -- won
    # the tie, and every frame-relative coordinate was converted against the
    # wrong origin. Clicks then land tens of pixels away, often on the desktop,
    # and the app correctly does nothing.
    #
    # A whole 40-file sweep was read before this was noticed on 2026-09-05. Only
    # P0-P10 had been rebuilt; the other 32 binaries predated the fix by four
    # hours, and the tell was in every one of their logs -- the only class ever
    # marked `<- CHOSEN` was `GdkWin32GL`, where a rebuilt binary shows
    # `gdkSurfaceToplevel`. Four files came back "clicks hit 0x10196", which is
    # Program Manager, i.e. the desktop, and that was briefly written up as an
    # action-file coordinate defect. It was a stale build, and `git status` was
    # clean throughout, because stale copies of a fix are build output.
    #
    # 這個執行檔是否早於「決定要驅動哪一個視窗」的那項修正？若是，該次執行所說的一切都與這支 app
    # 無關；而這項檢查只花一次 stat，事後才發現則要賠上整輪 sweep。
    #
    # 2d163c9b 讓 synthesiser 略過「被另一個可見視窗所擁有」的視窗。在它之前，Direct Composition
    # 的 `GdkWin32GL` 內容表面——與其 toplevel 同尺寸，但原點是 (0, 0) 而非 (78, 78)——會贏得平手，
    # 於是每一個 frame 相對座標都以錯誤的原點換算。點擊因此落在數十像素之外，往往落在桌面上，
    # 而 app 正確地什麼也沒做。
    #
    # 2026-09-05，整整一輪 40 個檔案的 sweep 被讀完之後才發現這件事。當時只有 P0-P10 重建過，
    # 其餘 32 個執行檔早於該修正四小時，而線索就在它們每一份 log 裡——被標記 `<- CHOSEN` 的類別
    # **只有** `GdkWin32GL`，而重建過的執行檔顯示的是 `gdkSurfaceToplevel`。有四個檔案回報
    # 「clicks hit 0x10196」，那是 Program Manager，也就是桌面，而它一度被寫成動作檔的座標缺陷。
    # 它其實是過期的建置，而 `git status` 全程乾淨——因為「修正的過期副本」是建置產物。
    if [ -n "$fix_epoch" ] && [ "$(date -r "$exe" +%s)" -lt "$fix_epoch" ]; then
        printf '%-30s %-8s %-9s %-9s %s\n' "$app" 'STALE' - - \
            "built before $fix_commit -- rebuild with SCUI_DEBUG=1"
        continue
    fi

    # EVERY action file for this app, not the first one.
    #
    # `head -1` discarded 5 of the 38 files in actions/win, silently: P46 has
    # three, and P24, P20, P19, P13 and P10 have two each, and only the first
    # of each was ever driven. The ones that never ran are not spares -- P10's
    # pair is a keyboard shortcut and a hit test, which are different questions
    # about different code.
    #
    # `-winui` files are excluded because their coordinates were measured
    # against WinUI's window, and WinUI gives 860x700 where GTK gives 860x661
    # (issue #79). Driving one against the gtk4 build addresses points 39 px out
    # and calls the result a verdict.
    #
    # An app with no action file still gets one pass through the loop, with an
    # empty `action_file`: launching and capturing it is a real run and the
    # columns already say so.
    #
    # 這支 app 的**每一個**動作檔，而不是第一個。
    #
    # `head -1` 靜默地丟掉了 actions/win 中 38 個檔案裡的 5 個：P46 有三個，P24、P20、P19、P13
    # 與 P10 各有兩個，而每一組都只有第一個曾被驅動。那些沒跑過的並不是備品——P10 的那一對是
    # 「鍵盤快捷鍵」與「命中測試」，是關於不同程式碼的不同問題。
    #
    # `-winui` 檔案被排除，因為它們的座標是對著 WinUI 的視窗量的，而 WinUI 給 860x700、GTK 給
    # 860x661（issue #79）。拿它去驅動 gtk4 建置，等於在偏差 39 px 的位置下手，然後把結果當成判決。
    #
    # 沒有動作檔的 app 仍會走一次迴圈，`action_file` 為空：把它啟動並擷取本來就是一次真實的執行，
    # 而各欄位已經如實說明了這一點。
    action_files=("${(@f)$(ls "$actions/$app"-*.csv 2>/dev/null | grep -v -- '-winui')}")
    [[ -z "${action_files[1]:-}" ]] && action_files=("")

    for action_file in "${action_files[@]}"; do
    attempt=1
    while :; do
    launch=- replay=- capture=- note=
    file_label="${action_file:t}"

    # One log and one capture PER FILE, keyed by the file rather than the app.
    # With two files under one name the second overwrote the first, and the hit
    # check would then have read the wrong run's dump -- which is the failure
    # this whole file spends its comments guarding against.
    # 每一個檔案各有自己的 log 與擷圖，以**檔案**而非 app 為鍵。若兩個檔案共用一個名字，第二個會
    # 覆蓋第一個，而命中檢查接著會讀到另一次執行的傾印——那正是本檔的註解通篇在防範的失敗。
    run_key="${file_label%.csv}"
    [[ -z "$run_key" ]] && run_key="$app"
    run_log="$log_dir/$run_key.log"

    # A leftover process makes the next launch exit 0 with no window, which
    # reads as the app failing rather than the sweep failing.
    # 殘留行程會讓下一次啟動以 0 結束卻沒有視窗，那看起來像是 app 失敗，而非本掃描失敗。
    MSYS2_ARG_CONV_EXCL='*' taskkill /F /IM "$app$suffix.exe" >/dev/null 2>&1
    sleep 1

    clear_desktop

    # `--debug` IS REQUIRED BY THE HIT CHECK BELOW, not a nicety.
    #
    # Win32Synthesiser's per-move dump -- the `hitRoot=` line and the window
    # candidate list -- is guarded on `-actionfile` AND `--debug`, deliberately:
    # it fires on every move rather than once per run, so it does not get the
    # always-on exemption that `ActionFileReplay.report` has.
    #
    # Without it the check has no input, `ours` and `hits` are both empty, and
    # every run passes it. Measured on this script's first merged run: P16 and
    # P31 both reported `replay=ok` with the hit check having examined nothing
    # at all -- a guard added to stop a silent pass, silently passing.
    #
    # 下方的命中檢查**需要** `--debug`，那不是可有可無的裝飾。
    #
    # Win32Synthesiser 的逐次移動傾印——`hitRoot=` 那一行與視窗候選清單——同時受 `-actionfile`
    # 與 `--debug` 把關，而且是刻意的：它在**每一次移動**時觸發，而非每次執行一行，因此不適用
    # `ActionFileReplay.report` 所享有的「一律輸出」豁免。
    #
    # 少了它，該檢查就沒有輸入，`ours` 與 `hits` 皆為空，於是每一次執行都會通過。本腳本合併後的
    # 首次執行實測：P16 與 P31 都回報 `replay=ok`，而命中檢查根本什麼都沒檢查過——一道為了阻止
    # 靜默通過而加入的防護，自己靜默地通過了。
    if [ -n "$action_file" ]; then
        ( cd "$out" && ./"$app$suffix.exe" --debug -actionfile "$(cygpath -m "$action_file")" \
            > "$run_log" 2>&1 & )
    else
        ( cd "$out" && ./"$app$suffix.exe" --debug > "$run_log" 2>&1 & )
    fi

    # Derived from the file rather than fixed, because a fixed wait silently
    # truncates the long ones. Measured 2026-08-27: 14 seconds was hard-coded,
    # P20-open-level-1.csv holds 16.8 s of sleeps, the replay starts 1 s after
    # launch -- so P20 needed 17.8 s and was captured and killed at 14. Its log
    # had `replaying` and no `replayed`, and the sweep reported it as though the
    # app were at fault. Every other file is at or under 10.4 s, so P20 was the
    # only one affected, which is exactly why it looked like an app defect.
    #
    # 由檔案本身推導而非固定，因為固定的等待會靜默截斷較長的動作檔。2026-08-27 實測：當時寫死
    # 14 秒，而 P20-open-level-1.csv 的睡眠總長為 16.8 秒，重放又在啟動後 1 秒才開始——因此 P20
    # 需要 17.8 秒，卻在第 14 秒就被擷取並終止。它的 log 有 `replaying`、沒有 `replayed`，而掃描
    # 把它報成了 app 的問題。其餘每個檔案都在 10.4 秒以內，所以只有 P20 受影響——這正是它看起來
    # 像 app 缺陷的原因。
    wait_seconds=14
    if [ -n "$action_file" ]; then
        wait_seconds="$(
            awk -F, '!/^#/ && !/^action,/ {s += $7}
                     END {
                         # the file, plus the replay delay, plus room for the
                         # actions themselves
                         # 檔案本身、加上重放延遲、再加上動作自身所需的餘裕
                         want = (s / 1000000) + 5
                         printf "%d", (want > 14 ? want : 14)
                     }' "$action_file"
        )"
    fi
    sleep "$wait_seconds"

    # No MSYS2_ARG_CONV_EXCL, and a doubled slash. The taskkill above wants the
    # opposite -- the exclusion and a single slash -- and mixing them up fails
    # silently in the worst way: with the exclusion set, `//FI` reaches tasklist
    # literally, it answers "ERROR: Invalid argument/option" on stderr, and
    # every app reads as having failed to launch. Measured 2026-08-27, on this
    # script's first run: P1 and P2 reported "exited before the capture" with
    # their windows plainly on screen.
    #
    # 此處不設 MSYS2_ARG_CONV_EXCL，並使用雙斜線。上方的 taskkill 要的正好相反——要設排除、用單
    # 斜線——而把兩者搞混的失敗方式最糟：設了排除時，`//FI` 會原封不動送達 tasklist，它會在
    # stderr 回覆「ERROR: Invalid argument/option」，於是每個 app 都被判讀為啟動失敗。於
    # 2026-08-27 本腳本首次執行時實測：P1 與 P2 的視窗明明在螢幕上，卻回報「exited before the
    # capture」。
    # SOME FILES PASS BY THE PROCESS BEING GONE, and for those this test is
    # exactly backwards.
    #
    # `P10-ctrl-q.csv` asks whether Ctrl-Q reaches the application. Its own
    # header says the instrument is the process rather than a screenshot:
    # success is the process having quit. Judged by the rule below it reported
    # `launch FAIL -- exited before the capture` on a run where exiting IS the
    # pass, and a verdict that is exactly inverted is worse than none, because
    # it reads as a defect in the app.
    #
    # The expectation is declared in the ACTION FILE, as `# expect:
    # process-exits`, beside the prose that already explains why. A table of
    # exceptions kept here would be a second copy of a fact the file already
    # holds, and it would drift the first time a file was added or renamed.
    # Checked: P10-ctrl-q is currently the only file in actions/win carrying the
    # marker, and also the only one whose actions can quit the app.
    #
    # 有些檔案的通過條件是「行程已結束」，對它們而言下方這項測試恰好是反的。
    #
    # `P10-ctrl-q.csv` 要問的是 Ctrl-Q 是否送達應用程式。它自己的標頭寫明：量測儀器是行程本身而非
    # 截圖，「成功」即為該行程已經結束。若以下方的規則判定，它會在「結束才是通過」的那次執行中回報
    # `launch FAIL -- exited before the capture`；而一個**恰好相反**的判決比沒有判決更糟，因為它
    # 讀起來像是 app 有缺陷。
    #
    # 該預期宣告於**動作檔**之中，寫作 `# expect: process-exits`，就在早已解釋其理由的那段散文
    # 旁邊。若在此處另存一張例外表，那會是「該檔案已經持有的事實」的第二份副本，並且在第一次有檔案
    # 被新增或改名時就開始漂移。經查：P10-ctrl-q 目前是 actions/win 中唯一帶有該標記的檔案，
    # 也是唯一其動作會讓 app 結束的檔案。
    expect_exit=no
    if [ -n "$action_file" ] \
        && grep -qE '^# *expect: *process-exits' "$action_file" 2>/dev/null; then
        expect_exit=yes
    fi

    if tasklist.exe //FI "IMAGENAME eq $app$suffix.exe" 2>&1 | grep -q "$app$suffix.exe"; then
        if [ "$expect_exit" = yes ]; then
            launch=FAIL
            note='still running -- this file passes by the process quitting'
        else
            launch=ok
        fi
    else
        if [ "$expect_exit" = yes ]; then
            launch=ok
            note='quit as expected'
        else
            launch=FAIL
            note='exited before the capture'
        fi
    fi

    # NOTHING TO CAPTURE, AND NO REPLAY VERDICT TO GIVE, when the file passes by
    # the app quitting. Both of the remaining columns invert for it too, and
    # leaving them to the normal path produced two more misleading cells on top
    # of the launch one:
    #
    #   capture  `desktop`, because there is no window left -- correct, and it
    #            reads as "the window was not found", which for GTK is the
    #            spelling of a problem. It also spends a capture on an image of
    #            the empty desktop that nobody will ever look at.
    #   replay   `running`, i.e. "still replaying when captured", because the
    #            process died before writing `actionfile: replayed`. It died
    #            because Ctrl-Q worked. That is the pass, printed as a warning.
    #
    # `n/a` rather than `ok` for the replay: the pass condition for this file is
    # the process being gone, and `launch` already carries that. Claiming a
    # separate replay verdict would be inventing a second measurement out of the
    # first. coverage.zsh already reads `n/a` as "no replay was expected".
    #
    # 當某個檔案的通過條件是「app 結束」時，就沒有東西可擷取，也沒有重放判決可下。餘下的兩欄對它
    # 而言同樣是反的；把它們留給一般路徑處理，會在 launch 那一欄之外再產生兩格誤導：
    #
    #   capture  `desktop`，因為已經沒有視窗——這是正確的，但它讀起來是「視窗沒被找到」，而那對
    #            GTK 而言正是「有問題」的寫法。它同時還把一次擷取花在一張沒有人會看的空桌面上。
    #   replay   `running`，即「擷取當下仍在重放」，因為該行程在寫出 `actionfile: replayed` 之前
    #            就死了。它之所以死，正是因為 Ctrl-Q 生效了。那是通過，卻被印成警告。
    #
    # replay 欄採 `n/a` 而非 `ok`：本檔的通過條件是「行程已不存在」，而 `launch` 欄已經承載了它。
    # 另外宣稱一個重放判決，等於從同一次量測裡憑空生出第二次量測。coverage.zsh 本來就把 `n/a`
    # 讀作「本就不預期有重放」。
    if [ "$expect_exit" = yes ] && [ "$launch" = ok ]; then
        capture='n/a'
        replay='n/a'
        # The action file goes in the CSV note, because the `app` column cannot
        # hold it and several apps now contribute more than one row per run.
        # Without it those rows are indistinguishable in the history.
        # 動作檔名寫入 CSV 的 note 欄，因為 `app` 欄放不下它，而現在有數支 app 每次執行會貢獻不只
        # 一列。少了它，那些資料列在歷史中就無從分辨。
        csv_note="${file_label:+$file_label: }$note"
        printf '%-30s %-8s %-9s %-9s %s\n' "$run_key" "$launch" "$replay" "$capture" "$note"
        printf '%s,%s,%s,%s,%s,%s,%s,"%s"\n' \
            "$run_date" "$platform" "$label" "$app" \
            "$launch" "$replay" "$capture" "${csv_note//\"/\"\"}" \
            >> "$results"
        break
    fi

    case "$(zsh "$repo/testapp/screenshot.zsh" -w "$app" "$label-$run_key" 2>&1 | tail -1)" in
        *'priority 1'*) capture=window ;;
        *'priority 2'*|*desktop*) capture=desktop ;;
        *) capture='?' ;;
    esac

    if [ -n "$action_file" ]; then
        if grep -q 'status 5' "$run_log" 2>/dev/null; then
            replay=LOCKED
            note="${note:+$note; }workstation locked -- input result is void"
        elif grep -q 'actionfile: replayed' "$run_log" 2>/dev/null; then
            replay=ok

            # A REPLAY THAT FINISHED IS NOT A REPLAY THAT LANDED.
            #
            # Every pointer move dumps `hitRoot=0x...`, the root window
            # `WindowFromPoint` says will receive the button event. If one of
            # those is not a window the app itself dumped as a candidate, the
            # click went somewhere else -- and a click that lands elsewhere
            # raises nothing here, so `replayed` is printed and the run reads as
            # a pass.
            #
            # Checked unconditionally, not only when the foreground was lost.
            # Gating it on the foreground warning was wrong in the direction
            # that matters: on 2026-09-06 P10 DID take the foreground, so the
            # gate skipped the check, and then a `Windows.UI.Core.CoreWindow`
            # came to the front mid-run and swallowed two clicks. Taking the
            # foreground at the start says nothing about who holds it three
            # seconds later.
            #
            # `tr '\n' ' '` on the candidate set is load-bearing: the test below
            # needs a space either side of every handle, and left
            # newline-separated only the first and last could ever match. That
            # bug reported `clicks hit 0x520c0e` for a log whose own dump read
            # `window 0x520c0e ... <- CHOSEN` two lines above.
            #
            # 「重放跑完了」不等於「重放打中了」。
            #
            # 每一次指標移動都會傾印 `hitRoot=0x...`，即 `WindowFromPoint` 認定將收下該按鍵事件
            # 的 root 視窗。若其中有任何一個不是該 app 自己傾印過的候選視窗，那次點擊就落到了別處
            # ——而落在別處的點擊在此不會引發任何東西，於是 `replayed` 照樣印出，該次執行讀起來
            # 就是通過。
            #
            # 無條件檢查，而非只在「前景已失去」時檢查。把它掛在前景警告之下，錯在最要緊的那個
            # 方向：2026-09-06，P10 **確實**取得了前景，於是這道關卡被跳過，接著一個
            # `Windows.UI.Core.CoreWindow` 在執行途中跑到最前面，吞掉了兩次點擊。在開始時取得
            # 前景，說明不了三秒之後是誰持有它。
            #
            # 對候選集合使用 `tr '\n' ' '` 是承重的：下方的測試要求每個 handle 前後各有一個空格，
            # 若維持以換行分隔，就只有第一項與最後一項有可能相符。那個 bug 曾對一份 log 回報
            # 「clicks hit 0x520c0e」，而該 log 上方兩行正寫著 `window 0x520c0e ... <- CHOSEN`。
            ours="$(grep -oE 'actionfile: window 0x[0-9a-f]+' "$run_log" \
                | grep -oE '0x[0-9a-f]+' | sort -u | tr '\n' ' ')"
            hits="$(grep -oE 'hitRoot=0x[0-9a-f]+' "$run_log" \
                | sed 's/hitRoot=//' | sort -u)"
            chosen="$(grep -oE 'actionfile: window 0x[0-9a-f]+ .*<- CHOSEN' "$run_log" \
                | grep -oE '0x[0-9a-f]+' | head -1)"

            # A positive control that must hold BY CONSTRUCTION: the window the
            # replay chose is always one of the app's own. If it is not in the
            # set, this check is broken and the run says nothing either way --
            # which is exactly what happened when the separator was wrong, and
            # nothing said so at the time.
            # 一項**依構造必然成立**的正向對照：重放所選中的視窗，永遠是該 app 自己的視窗之一。
            # 若它不在集合中，壞掉的是這道檢查，而該次執行兩邊都說明不了什麼——那正是分隔符寫錯時
            # 發生的事，而當時沒有任何東西這麼說。
            if [ -z "$chosen" ]; then
                # NO DUMP AT ALL means the check did not run, and saying so is
                # the whole point of having it. An empty candidate set makes
                # every membership test below vacuously true, so silence here
                # would be indistinguishable from "every click landed".
                # 完全沒有傾印，代表這道檢查根本沒有執行；而把這件事說出來，正是設置它的全部意義。
                # 空的候選集合會讓下方每一項成員測試都空洞地為真，因此此處的沉默，將與「每一次點擊
                # 都命中了」無從分辨。
                note="${note:+$note; }hit check did not run -- no window dump in the log"
            elif [ "${ours#*$chosen}" = "$ours" ]; then
                replay='CHECKER'
                note="${note:+$note; }hit check broken: chosen $chosen not in own dump"
            else
                strays=
                for h in ${(f)hits}; do
                    case " $ours " in
                        *" $h "*) ;;
                        *) strays="$strays $h" ;;
                    esac
                done
                if [ -n "$strays" ]; then
                    replay=ASTRAY
                    note="${note:+$note; }clicks hit$strays"
                fi
            fi
        elif grep -q 'actionfile: failed' "$run_log" 2>/dev/null; then
            replay=FAIL
            note="${note:+$note; }$(grep -m1 -oE 'failed: .*' "$run_log" | cut -c1-40)"
        elif grep -q 'actionfile: replaying' "$run_log" 2>/dev/null; then
            # Started and never finished. Distinguished from "no output at all"
            # because they have different causes and the old script reported
            # both as "built without SCUI_DEBUG?", which was wrong twice in one
            # afternoon -- once for a WinUI build whose output cannot reach a
            # file at all, and once for a wait that was too short.
            #
            # 開始了但沒跑完。與「完全沒有輸出」分開，因為兩者成因不同；舊版腳本把兩者都報成
            # 「built without SCUI_DEBUG?」，而那在一個下午之內就錯了兩次——一次是 WinUI 建置的
            # 輸出根本到不了檔案，一次是等待時間不足。
            replay='running'
            note="${note:+$note; }still replaying when captured"
        else
            replay='no line'
            note="${note:+$note; }no output at all -- WinUI build, or no SCUI_DEBUG"
        fi
    fi

    # SAY WHEN THE APP CANNOT BE JUDGED FROM A LOG, so the row is not read as
    # weaker evidence than it is.
    #
    # Eleven apps contain no debug-events writer anywhere in their source --
    # P1 P2 P3 P4 P29 P41 P15-DARK P17-DOE P27 P39 P40 -- and their action files
    # say so in as many words: P4's header opens "READ THIS FIRST -- P4 HAS NO
    # DEBUG LOG", and P4, P9, P29, P41 and P46-scroll-to-lazy all state that the
    # verdict is a capture because nothing in the app writes on that
    # interaction. A sweep on 2026-09-05 returned "no log" for exactly six files
    # and all six were in that set; reported bare, six correct outcomes read as
    # six failures.
    #
    # DERIVED FROM THE SOURCE, not from a list kept here. A list would be a
    # second copy of a fact the code already holds and the two would drift with
    # nothing to report it. Deliberately coarse: it says the app CAN log, not
    # that it logs for THIS interaction, so an app like P9 -- which does log, but
    # whose verdict is still a picture -- is not covered and its action file
    # header remains the authority.
    #
    # **當某支 app 無法以 log 判定時就說出來**，以免該列被讀成比實際更弱的證據。
    #
    # 有十一支 app 的原始碼中沒有任何 debug-events 寫入器——P1 P2 P3 P4 P29 P41 P15-DARK
    # P17-DOE P27 P39 P40——而它們的動作檔也明白寫著這件事：P4 的標頭開頭就是「READ THIS FIRST
    # -- P4 HAS NO DEBUG LOG」，而 P4、P9、P29、P41 與 P46-scroll-to-lazy 都載明其判準是擷圖，
    # 因為該互動不會讓 app 寫出任何東西。2026-09-05 的一輪 sweep 對恰好六個檔案回報「no log」，
    # 六個全在該集合內；若照原樣回報，六個正確的結果會被讀成六個失敗。
    #
    # **由原始碼推導**，而非在此另存一份清單。清單會是「程式碼已經持有的事實」的第二份副本，
    # 兩者會漂移而無人回報。它刻意是粗粒度的：它說的是「這支 app **能**寫 log」，而不是「它會為
    # **這個**互動寫 log」；因此像 P9 這種「會寫、但判準仍是圖片」的 app 不在涵蓋範圍內，其動作檔
    # 標頭仍是權威。
    if [ -n "$action_file" ] \
        && ! grep -qi 'debug-events' "$repo/testapp/$app.swift" 2>/dev/null; then
        note="${note:+$note; }no log writer in $app.swift -- judge from the capture"
    fi

    MSYS2_ARG_CONV_EXCL='*' taskkill /F /IM "$app$suffix.exe" >/dev/null 2>&1

    # RETRY WHEN THE FOREGROUND WAS LOST, because that is a property of the
    # desktop at that instant and not of the app.
    #
    # A file that presses keys cannot run without focus, and Windows shell
    # surfaces take the foreground back on their own: `SearchHost.exe` returned
    # between two runs of P31 on 2026-09-06, so the same file passed and then
    # failed with nothing about it changed. Reporting the second run as a defect
    # would be reporting the desktop.
    #
    # The retry re-clears and re-dismisses first, which is the only thing that
    # can change the outcome -- and it stops at the first attempt that gets past
    # this, rather than looping for a better answer. Three attempts, then the
    # failure stands: at that point the honest reading is that this desktop
    # cannot hold the foreground still for the length of a replay, and that is
    # worth reporting rather than retrying away.
    #
    # 當前景遺失時重試，因為那是**該瞬間桌面的性質**，不是 app 的性質。
    #
    # 會按鍵的檔案沒有焦點就無法執行，而 Windows 的 shell 表面會自行把前景搶回去：2026-09-06，
    # `SearchHost.exe` 在 P31 的兩次執行之間回來了，於是同一個檔案先通過、後失敗，而其間沒有任何
    # 與它有關的東西改變過。把第二次執行報成缺陷，等於在回報桌面。
    #
    # 重試會先重新 clear 與 dismiss，那是唯一可能改變結果的動作——而且它在「第一次順利通過這一關」
    # 時就停止，不會為了更好看的答案繼續繞。三次之後失敗即成立：到那個地步，誠實的讀法是「這台桌面
    # 無法在一次重放的時間內把前景穩住」，而那值得被回報，不該被重試掩蓋。
    # ASTRAY RETRIES TOO, for the same reason and with less excuse for not
    # having said so the first time.
    #
    # P16-force-update came back ASTRAY on 2026-09-06 with
    # `hitClass=ConsoleWindowClass foreground=0x50832` -- a console window on
    # top of the app at the moment of the click. The run was correct in every
    # other respect: right toplevel, right origin, coordinates inside the
    # window. The console does not belong to the app either; the app reports
    # `this process has no console window to hide`, so it is the harness's own,
    # raised by one of the subprocesses this script spawns.
    #
    # That is the same class of interference as losing the foreground -- the
    # desktop at that instant -- and the same answer applies. It is NOT a claim
    # that P16 is fine: an ASTRAY that survives three attempts is reported, and
    # a real coordinate defect would survive all three.
    #
    # ASTRAY 同樣重試，而且比前一項更沒有「第一次沒想到」的藉口。
    #
    # 2026-09-06，P16-force-update 回報 ASTRAY，附帶
    # `hitClass=ConsoleWindowClass foreground=0x50832`——點擊當下有一個主控台視窗蓋在 app 之上。
    # 那次執行在其他每一方面都正確：toplevel 正確、原點正確、座標落在視窗內。而該主控台也不屬於
    # 該 app；app 回報的是 `this process has no console window to hide`，因此它是本腳本自己所衍生
    # 的子行程所帶起的、屬於測試框架的主控台。
    #
    # 那與「失去前景」屬於同一類干擾——都是該瞬間的桌面——因此適用同一個答案。這**不是**在主張
    # P16 沒問題：連續三次仍為 ASTRAY 會如實回報，而真正的座標缺陷會三次都存活。
    if { [ "$replay" = FAIL ] \
            && grep -q 'could not bring our window to the front' "$run_log" 2>/dev/null; } \
        || [ "$replay" = ASTRAY ]; then
        if [ "$attempt" -lt 3 ]; then
            attempt=$(( attempt + 1 ))
            continue
        fi
    fi

    # DID THE WINDOW HAVE THE SIZE THE COORDINATES WERE MEASURED AT?
    #
    # `replay=ok` means the replay finished and every click landed on the app's
    # own window. It does NOT mean a click landed on the control it names, and
    # nothing else here checks that. A window of a different size lays its
    # contents out differently, so the same coordinate reaches something else,
    # and the run is clean, quiet and wrong.
    #
    # Measured 2026-09-06: P16-force-update.csv records `Measured on a 916x639
    # window capture at 100% display scale`, and the live window was 928x629 --
    # twelve pixels wider and ten shorter. Five consecutive rounds reported
    # `ok ok window`, and every one of them clicked somewhere other than
    # "Force update (0)". The operator saw it on screen; the harness could not.
    #
    # Read from the action file's own header, which most of them carry, rather
    # than from a table here -- same reason as `# expect:`. Files with no
    # recorded size are skipped and said to be skipped: a check that quietly
    # passes when it has no input is the failure this whole script is built
    # against.
    #
    # A MISMATCH IS NOT AUTOMATICALLY THE FILE BEING STALE. The window may be
    # the thing that changed, and issue #79 is open on exactly that -- GTK on
    # Windows comes out short against WinUI. Which side to correct is a
    # judgement; reporting the disagreement is not.
    #
    # 視窗的尺寸，是否就是那些座標被量測時的尺寸？
    #
    # `replay=ok`的意思是「重放跑完了，而且每一次點擊都落在該 app 自己的視窗上」。它**不**代表
    # 某次點擊落在它所指名的控制項上，而此處也沒有別的東西在檢查那件事。尺寸不同的視窗會以不同方式
    # 排版其內容，於是同一個座標會抵達別的東西，而該次執行乾淨、安靜、且錯誤。
    #
    # 2026-09-06 實測：P16-force-update.csv 記載「Measured on a 916x639 window capture at 100%
    # display scale」，而實際視窗是 928x629——寬了十二像素、矮了十像素。連續五輪都回報
    # `ok ok window`，而其中每一輪點的都不是「Force update (0)」。操作者在畫面上看見了；本工具
    # 看不見。
    #
    # 由動作檔自己的標頭讀取（多數檔案都有記載），而非在此另存一張表——理由與 `# expect:` 相同。
    # 沒有記載尺寸的檔案會被略過，而且會**說明它被略過**：一項「沒有輸入時就安靜通過」的檢查，
    # 正是整份腳本所要對抗的那種失敗。
    #
    # 尺寸不符**不自動等於「動作檔過期」**。改變的可能是視窗，而 issue #79 正是為此開著的——
    # Windows 上的 GTK 相對 WinUI 偏小。該修哪一邊是判斷；把這個分歧回報出來則不是。
    if [ -n "$action_file" ] && [ "$replay" = ok ]; then
        want_size="$(grep -oE '[0-9]{3,4}x[0-9]{3,4}' "$action_file" | head -1)"
        # Two steps, and NO `[^\n]` in the pattern. grep is line-oriented, so
        # inside a bracket expression `\n` is not a newline -- it is the two
        # characters backslash and n. `[^\n]*` therefore means "not a backslash
        # and not the letter n", and the line contains `enabled`. The pattern
        # matched nothing, `got_size` came out empty, and the check passed
        # vacuously on the very run it was written to catch.
        #
        # 分兩步，而且樣式中**不使用** `[^\n]`。grep 以行為單位，因此在 bracket expression 中，
        # `\n` 不是換行，而是「反斜線」與「n」兩個字元。`[^\n]*` 於是代表「不是反斜線也不是字母 n」，
        # 而該行含有 `enabled`。樣式因此毫無匹配、`got_size` 成為空字串，這道檢查就在「它被寫出來
        # 所要捕捉的那一次執行」上空洞地通過了。
        got_size="$(grep -E 'class=gdkSurfaceToplevel.*CHOSEN' "$run_log" 2>/dev/null \
            | head -1 | grep -oE '[0-9]+x[0-9]+@' | tr -d '@')"
        if [ -z "$want_size" ]; then
            note="${note:+$note; }no measured size in the action file -- geometry unchecked"
        elif [ -z "$got_size" ]; then
            note="${note:+$note; }no toplevel size in the log -- geometry unchecked"
        elif [ "$want_size" != "$got_size" ]; then
            replay=GEOMETRY
            note="${note:+$note; }measured at $want_size, ran at $got_size -- coordinates address a different layout"
        fi
    fi

    csv_note="${file_label:+$file_label: }$note"
    printf '%-30s %-8s %-9s %-9s %s\n' "$run_key" "$launch" "$replay" "$capture" "$note"

    # Appended so the matrix has evidence with a date on it. A hand-maintained
    # Pn-versus-platform table drifts from reality silently, which is the exact
    # failure this project spent a day chasing elsewhere; a table generated from
    # rows that each carry the day they were measured cannot.
    #
    # Quoted with `""` doubling, per RFC 4180, because `note` regularly contains
    # commas -- and splitting a CSV on `,` is what `csv2` exists in this project
    # to stop people doing.
    #
    # 追加寫出，好讓矩陣擁有「帶日期的證據」。手動維護的 Pn × 平台表格會靜默地與現實脫節——這正是
    # 本專案在別處花了一整天追查的同一種失敗；而由「每一列都記著自己是哪一天量到的」所生成的表格
    # 不會。
    #
    # 依 RFC 4180 以 `""` 進行跳脫，因為 `note` 經常含有逗號——而「用 `,` 切 CSV」正是 `csv2` 在本
    # 專案中存在的目的所要阻止的事。
    printf '%s,%s,%s,%s,%s,%s,%s,"%s"\n' \
        "$run_date" "$platform" "$label" "$app" \
        "$launch" "$replay" "$capture" "${csv_note//\"/\"\"}" \
        >> "$results"
    break
    done
    done
done

printf '\nlogs in %s ; captures in testapp/output/screenshots/%s-*.png\n' "$log_dir" "$label"
printf 'results appended to %s -- run coverage.zsh to regenerate the matrix\n' "$results"
exit 0
