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
printf '%-6s %-8s %-9s %-9s %s\n' app launch replay capture note
printf '%s\n' '--------------------------------------------------------------'

for app in $apps; do
    launch=- replay=- capture=- note=

    exe="$out/$app$suffix.exe"

    if [ ! -x "$exe" ]; then
        printf '%-6s %-8s %-9s %-9s %s\n' "$app" 'no exe' - - "no $app$suffix.exe"
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
        printf '%-6s %-8s %-9s %-9s %s\n' "$app" 'STALE' - - \
            "built before $fix_commit -- rebuild with SCUI_DEBUG=1"
        continue
    fi

    # A leftover process makes the next launch exit 0 with no window, which
    # reads as the app failing rather than the sweep failing.
    # 殘留行程會讓下一次啟動以 0 結束卻沒有視窗，那看起來像是 app 失敗，而非本掃描失敗。
    MSYS2_ARG_CONV_EXCL='*' taskkill /F /IM "$app$suffix.exe" >/dev/null 2>&1
    sleep 1

    clear_desktop

    action_file="$(ls "$actions/$app"-*.csv 2>/dev/null | grep -v -- '-winui' | head -1)"

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
            > "$log_dir/$app.log" 2>&1 & )
    else
        ( cd "$out" && ./"$app$suffix.exe" --debug > "$log_dir/$app.log" 2>&1 & )
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
    if tasklist.exe //FI "IMAGENAME eq $app$suffix.exe" 2>&1 | grep -q "$app$suffix.exe"; then
        launch=ok
    else
        launch=FAIL
        note='exited before the capture'
    fi

    case "$(zsh "$repo/testapp/screenshot.zsh" -w "$app" "$label-$app" 2>&1 | tail -1)" in
        *'priority 1'*) capture=window ;;
        *'priority 2'*|*desktop*) capture=desktop ;;
        *) capture='?' ;;
    esac

    if [ -n "$action_file" ]; then
        if grep -q 'status 5' "$log_dir/$app.log" 2>/dev/null; then
            replay=LOCKED
            note="${note:+$note; }workstation locked -- input result is void"
        elif grep -q 'actionfile: replayed' "$log_dir/$app.log" 2>/dev/null; then
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
            ours="$(grep -oE 'actionfile: window 0x[0-9a-f]+' "$log_dir/$app.log" \
                | grep -oE '0x[0-9a-f]+' | sort -u | tr '\n' ' ')"
            hits="$(grep -oE 'hitRoot=0x[0-9a-f]+' "$log_dir/$app.log" \
                | sed 's/hitRoot=//' | sort -u)"
            chosen="$(grep -oE 'actionfile: window 0x[0-9a-f]+ .*<- CHOSEN' "$log_dir/$app.log" \
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
        elif grep -q 'actionfile: failed' "$log_dir/$app.log" 2>/dev/null; then
            replay=FAIL
            note="${note:+$note; }$(grep -m1 -oE 'failed: .*' "$log_dir/$app.log" | cut -c1-40)"
        elif grep -q 'actionfile: replaying' "$log_dir/$app.log" 2>/dev/null; then
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

    printf '%-6s %-8s %-9s %-9s %s\n' "$app" "$launch" "$replay" "$capture" "$note"

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
        "$launch" "$replay" "$capture" "${note//\"/\"\"}" \
        >> "$results"
done

printf '\nlogs in %s ; captures in testapp/output/screenshots/%s-*.png\n' "$log_dir" "$label"
printf 'results appended to %s -- run coverage.zsh to regenerate the matrix\n' "$results"
exit 0
