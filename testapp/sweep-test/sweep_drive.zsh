#!/usr/bin/env zsh
# Launches every already-built P1-P26 app, replays its action file, captures it.
#
#   zsh testapp/sweep-test/sweep_drive.zsh                 every app
#   zsh testapp/sweep-test/sweep_drive.zsh -l gtk4         drive the -gtk4 builds
#   zsh testapp/sweep-test/sweep_drive.zsh -l winui        drive the -WinUI builds
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
#             means this script's own hit test is broken, not the run;
#             `GEOMETRY` means the window was not the size the coordinates were
#             measured at, so they address a different layout;
#             `UNMET` means the action file declared `# expect: log-contains ...`
#             and nothing the run wrote contains it -- the replay ran, the
#             outcome the file exists to produce did not happen;
#             `UNCHECKED` means that same declaration could not be tested,
#             because the run left no log to read, and unverifiable is not the
#             same answer as satisfied
#   capture   `window` is a real window capture; `desktop` is the fallback
#   renderer  always `default` here: this driver selects no renderer, so GTK
#             and WinUI each use their own. See the comment block above
#             `renderer=default` for why the column exists at all, and why
#             `default` is not the same answer as `unrecorded`
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
# `-l` **現在同時選擇 backend**，而不只是為本次執行命名：`gtk4` 驅動 `Pn-gtk4.exe`，
# `winui` 驅動 `Pn-WinUI.exe`。
#
# 它過去只是個標籤，而本段落曾寫著：「它不會選擇 backend；實際的 backend 取決於
# testapp/output/Pn.exe 當下是哪一個」。當執行檔加上 backend 後綴之後，那句話就不再成立——
# 已經沒有 `Pn.exe` 了。舊做法同時帶有它自己所警告的那種失敗：在 WinUI 建置之後傳 `-l gtk4`
# 會產生一份靜默錯誤的表格。由標籤推導檔名可同時消除這兩者。
#
# 這一段於 2026-09-07 更正。上方的英文半邊在同一天稍早就已改好，中文半邊沒有——於是同一份檔頭的
# 兩半互相矛盾了幾個小時，而 `--help` 兩半都會印出來。本專案的雙語規則之所以要求「同一次編輯改
# 兩邊」，正是為了這件事：一份與自己矛盾的說明，比沒有說明更糟，因為兩邊都會被相信。
#
# 各欄位的讀法：
#
#   launch    擷取當下該行程仍然存活；STALE 代表該 exe 早於視窗選擇修正，因而根本沒有執行
#   replay    app 自己輸出的 `-actionfile:` 行，需要 SCUI_DEBUG 建置才會存在。
#             `ok` 表示跑完**且**每一次點擊都落在該 app 上；`ASTRAY` 表示跑完了、但點擊落在
#             別的視窗上，因此什麼也證明不了；`CHECKER` 表示壞的是本腳本自己的命中檢查，
#             而不是那次執行；`GEOMETRY` 表示視窗的尺寸不是那些座標被量測時的尺寸，
#             因此它們指向的是另一套版面；
#             `UNMET` 表示動作檔宣告了 `# expect: log-contains ...`，而該次執行所寫出的任何
#             東西都不含它——重放跑了，但這個檔案存在所要促成的結果沒有發生；
#             `UNCHECKED` 表示同一項宣告無法被檢驗，因為該次執行沒有留下可讀的 log，
#             而「無法查證」與「已滿足」不是同一個答案
#   capture   `window` 為真正的視窗擷取；`desktop` 為回退
#   renderer  在此永遠是 `default`：本驅動器不選擇 renderer，因此 GTK 與 WinUI 各自使用自身的
#             預設值。本欄位為何存在、以及 `default` 為何與 `unrecorded` 不是同一個答案，
#             見 `renderer=default` 上方的註解區塊
#
# 對 WinUI 而言 `desktop` 是預期的，對 GTK 而言則是問題。WinUI 透過 DirectComposition 繪製，
# `BitBlt` 會回傳全黑，因此 testapp/screenshot.zsh 會回退——這在其自身檔頭已有記載。GTK 透過
# OpenGL/WGL 繪製，擷取完全正常，因此在 GTK 上出現 `desktop`，代表視窗根本沒被找到。

set -uo pipefail

script_path="${0:A}"
repo="${${script_path:h}:h:h}"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    # Through line 61, the end of the English half. Widened when the header grew
    # -- a hard-coded range silently truncates the synopsis the moment anything
    # is added above it, and the columns section is the part a reader came for.
    #
    # This prose said "line 48" while the code said 52, and had for some time:
    # the range was widened once and the sentence describing it was not. Both
    # numbers are updated here in the same edit, which is the only way they stay
    # able to agree.
    #
    # 至第 61 行，即英文段落的結尾。標頭變長時一併加寬——寫死的範圍會在其上方新增任何內容的那一刻
    # 靜默截斷說明，而「各欄位的讀法」正是讀者前來尋找的部分。
    #
    # 這段說明原本寫「第 48 行」，而程式碼寫的是 52，且已如此有一段時間：範圍被加寬過一次，描述它
    # 的句子卻沒有。此處在同一次編輯中一併更新兩個數字——那是讓它們能夠保持一致的唯一辦法。
    sed -n '2,61p' "$script_path" | sed 's/^# \{0,1\}//'
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

# WHERE THE APPS' OWN EVENT LOGS GO. One directory, named by one environment
# variable, `SCUI_DEBUG_EVENTS_DIR`.
#
# This script is BOTH the launcher and the reader for that file, so the two
# halves have to agree here or the expectation check below reports UNCHECKED --
# not a failure, an unverifiable, which is the answer that costs the most to
# read. Exporting it without moving `app_log`, or moving `app_log` without
# exporting it, each produce exactly that.
#
# The apps fall back to their working directory when the variable is unset, so
# nothing outside this script changes. It exists because 38 of the testapp
# sources carried their own copy of
# `URL(fileURLWithPath: FileManager.default.currentDirectoryPath)` and the log
# landed wherever the app was started from: 83 files had collected across the
# repo root, testapp/ and testapp/output/, 44 of them same-named copies from
# different directories. Re-derive with
# `grep -l SCUI_DEBUG_EVENTS_DIR testapp/P*.swift | wc -l` (38 on 2026-09-08) and
# `ls testapp/debug-events | wc -l` (83 on 2026-09-08).
#
# `cygpath -m` for the same reason the action file gets it further down: these
# are native Windows binaries and Foundation cannot open /c/Users/... . A wrong
# form here is silent -- the write goes through `try?`, no file appears, and the
# run looks like an app that logged nothing.
#
# app 自身事件 log 的去處。一個目錄，由一個環境變數 `SCUI_DEBUG_EVENTS_DIR` 指定。
#
# 本腳本同時是該檔案的**啟動者與讀取者**，因此這兩半必須在此取得一致，否則下方的期望檢查會回報
# UNCHECKED——那不是失敗，而是「無法查證」，也是最難讀懂的答案。只 export 而不移動 `app_log`，
# 或只移動 `app_log` 而不 export，都會恰好造成這個結果。
#
# 變數未設定時各 app 退回自己的工作目錄，因此本腳本以外的一切都不改變。它的由來：38 支 testapp
# 原始碼各自帶著一份 `URL(fileURLWithPath: FileManager.default.currentDirectoryPath)`，log 因而
# 落在 app 當時的啟動目錄，最終在 repo 根目錄、testapp/ 與 testapp/output/ 之間累積了 83 個檔案，
# 其中 44 個是來自不同目錄的同名副本。重新推導的指令見上方英文段落。
#
# 使用 `cygpath -m` 的理由，與下方動作檔相同：這些是原生 Windows 執行檔，Foundation 打不開
# /c/Users/... 這類路徑。此處寫錯形式是無聲的——寫入經由 `try?`，不會有檔案出現，那次執行看起來
# 就像一支什麼都沒記錄的 app。
events_dir="$repo/testapp/debug-events"
mkdir -p "$events_dir"
events_dir_win="$(cygpath -m "$events_dir")"
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

# The `renderer` column, added to results.csv2 on 2026-09-07 because a renderer
# decides a verdict: on WSL that day, P11 at 788x649 captured 0.0% non-black
# under `-render hw` (GskGLRenderer) and 92.1% under `-render sw`
# (GskVulkanRenderer on llvmpipe), minutes apart, and no row said which.
#
# This driver has no renderer knob. It launches `Pn-gtk4.exe` / `Pn-WinUI.exe`
# directly through tasklist and gdigrab, setting no GSK_RENDERER, no
# GALLIUM_DRIVER and no LIBGL_ALWAYS_SOFTWARE, so GTK and WinUI each pick their
# own default. `default` says exactly that, and it is a fact about the run
# rather than a guess. If a `-render` flag is ever added here, write its value.
#
# NOT `unrecorded`: that value belongs to the 509 rows that predate the column,
# whose conditions were never written down. Writing it here would throw away a
# thing this script does know. NOT omitted either -- three machines append to
# this file, and 8 fields into a 9-column history is a ragged file for the next
# reader, who is coverage.zsh.
#
# `renderer` 欄，於 2026-09-07 加入 results.csv2，因為 renderer 會決定判決：當天在 WSL 上，P11 於
# 788x649 下，`-render hw`（GskGLRenderer）擷取到的非黑比例是 0.0%，`-render sw`（llvmpipe 上的
# GskVulkanRenderer）則是 92.1%，兩者相隔數分鐘，而沒有任何一列指出是哪一種。
#
# 本驅動器沒有 renderer 開關。它透過 tasklist 與 gdigrab 直接啟動 `Pn-gtk4.exe` / `Pn-WinUI.exe`，
# 不設定 GSK_RENDERER、不設定 GALLIUM_DRIVER、也不設定 LIBGL_ALWAYS_SOFTWARE，因此 GTK 與 WinUI
# 各自選用自身的預設值。`default` 說的正是這件事，而且它是關於該次執行的事實，不是猜測。日後若在
# 此加入 `-render` 旗標，就改寫入該旗標的值。
#
# **不是** `unrecorded`：那個值屬於早於本欄位的那 509 列，它們的執行條件從未被寫下。在此寫入它，
# 等於丟棄一件本腳本確實知道的事。**也不可省略**——有三台機器會追加到本檔案，而把 8 個欄位寫進 9 欄
# 的歷史檔，對下一個讀取者（也就是 coverage.zsh）而言就是一份參差不齊的檔案。
renderer=default

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

    # MARK HOW LONG THE APP'S OWN EVENT LOG IS *BEFORE* THE LAUNCH, so that
    # `# expect: log-contains` further down reads only what THIS run wrote.
    #
    # The apps append and never truncate -- P44Diagnostics.write opens the file,
    # seeks to the end and writes -- so p44-debug-events.log held a line from
    # 12:49 and two more from 12:52 in the same file. Searching the whole file
    # would let a line from a previous run satisfy the expectation of a run in
    # which the click missed entirely, which is the plausible-wrong-data failure
    # this script exists to prevent, not a near miss of it.
    #
    # The name is still DERIVED, `${app:l}-debug-events.log` -- same reason as
    # `# expect:` itself, a table here would be a second copy that drifts. Only
    # the DIRECTORY changed: it is `$events_dir`, which this script exports to
    # the app as SCUI_DEBUG_EVENTS_DIR at the launch a few lines below, instead
    # of the directory the app happens to be launched from. Verified 2026-09-07
    # by listing testapp/output: 37 such files and every one follows that
    # spelling; 83 had accumulated across three directories before they were
    # collected (`ls testapp/debug-events/*debug-events*.log` to re-count now,
    # `ls testapp/output/*debug-events*.log` for what the old wording counted).
    #
    # Reading one directory while the app writes to another does not fail here.
    # It reports UNCHECKED, and "could not be verified" is not the same answer as
    # "did not happen" -- which is why the export and this line have to move
    # together and are commented as one thing.
    #
    # **在啟動之前先記下 app 自身事件 log 的長度**，好讓下方的 `# expect: log-contains` 只讀取
    # **本次執行**所寫入的內容。
    #
    # 這些 app 只追加、從不截斷——P44Diagnostics.write 開檔、seek 到結尾後寫入——因此
    # p44-debug-events.log 中同時存在 12:49 的一行與 12:52 的兩行。若搜尋整個檔案，前一次執行留下
    # 的行就能讓「這一次點擊完全沒中」的執行通過檢查；那正是本腳本所要防範的「看似合理的錯誤資料」，
    # 而不是它的邊緣情況。
    #
    # 檔名依然是**推導而得**的 `${app:l}-debug-events.log`——理由與 `# expect:` 本身相同，在此另存
    # 一張表只會是一份會漂移的副本。改變的只有**目錄**：現在是 `$events_dir`，也就是本腳本在下方
    # 啟動時以 SCUI_DEBUG_EVENTS_DIR 傳給 app 的那一個，而不再是 app 恰好被啟動的目錄。
    # 2026-09-07 以列出 testapp/output 查證：共 37 個這樣的檔案，全部符合該寫法；在被集中之前，
    # 三個目錄合計累積了 83 個（現在重新清點用 `ls testapp/debug-events/*debug-events*.log`，
    # 舊說法所清點的則是 `ls testapp/output/*debug-events*.log`）。
    #
    # 讀一個目錄、而 app 寫在另一個目錄，在此不會失敗，只會回報 UNCHECKED；而「無法查證」與
    # 「沒有發生」不是同一個答案——這正是那個 export 與這一行必須一起移動、並被當成同一件事註解的
    # 原因。
    app_log="$events_dir/${app:l}-debug-events.log"
    app_log_before=0
    if [ -f "$app_log" ]; then
        app_log_before="$(wc -c < "$app_log" 2>/dev/null | tr -d ' ')"
        [ -z "$app_log_before" ] && app_log_before=0
    fi

    # SCUI_DEBUG_EVENTS_DIR is the other half of the mark taken just above: it
    # sends the app's log to the directory `app_log` reads. The `cd "$out"` stays
    # -- the executable and everything else it opens are still there.
    # SCUI_DEBUG_EVENTS_DIR 是上方那個標記的另一半：它把 app 的 log 導向 `app_log` 所讀取的目錄。
    # `cd "$out"` 保留不變——執行檔以及它開啟的其他東西仍在該處。
    if [ -n "$action_file" ]; then
        ( cd "$out" && SCUI_DEBUG_EVENTS_DIR="$events_dir_win" \
            ./"$app$suffix.exe" --debug -actionfile "$(cygpath -m "$action_file")" \
            > "$run_log" 2>&1 & )
    else
        ( cd "$out" && SCUI_DEBUG_EVENTS_DIR="$events_dir_win" \
            ./"$app$suffix.exe" --debug > "$run_log" 2>&1 & )
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

    # THE SECOND DECLARATION IN THE SAME FAMILY, and it answers a different
    # question: not "did the replay run" but "did it achieve what this file is
    # for". Spelling:
    #
    #     # expect: log-contains third cell clipped: true
    #
    # Everything after `log-contains ` is the literal text to look for; it is
    # matched with `grep -F`, so colons, brackets and parentheses in it are
    # text, not syntax.
    #
    # P44 IS WHY IT EXISTS. Driving P44-clip-third-cell.csv on 2026-09-07
    # reported `ok / ok / window`, and only reading the capture and the log by
    # hand showed the button had worked at all:
    #
    #     cell 3 spill, y=620    before x=14..29   after NONE
    #     p44-debug-events.log   third cell clipped: true
    #
    # The driver had no opinion either way. A file whose clicks ALL missed would
    # have reported the same `ok / ok / window`, because `replay=ok` means the
    # replay ran to completion and every click landed on the app's own window --
    # it has never meant the controls did what they are for.
    #
    # In the ACTION FILE, next to the prose that already explains what the press
    # is supposed to change, for the same reason `# expect: process-exits` is
    # there: it is a fact about what THIS file does, and one copy cannot
    # disagree with itself.
    #
    # 同一族的第二項宣告，而它回答的是另一個問題：不是「重放有沒有跑」，而是「它有沒有達成這個檔案
    # 存在的目的」。寫法如上。`log-contains ` 之後的一切都是要尋找的字面文字；比對使用 `grep -F`，
    # 因此其中的冒號、方括號與圓括號都是文字，不是語法。
    #
    # **P44 就是它存在的理由。** 2026-09-07 驅動 P44-clip-third-cell.csv 回報的是
    # `ok / ok / window`，而唯有以人工讀取擷圖與日誌，才看得出那個按鈕究竟有沒有生效（如上）。
    # 驅動器對此毫無意見。一個「每一次點擊都沒中」的檔案，會回報一模一樣的 `ok / ok / window`，
    # 因為 `replay=ok` 的意思是「重放跑完了，而且每一次點擊都落在該 app 自己的視窗上」——它從來
    # 不代表那些控制項做了它們該做的事。
    #
    # 放在**動作檔**中、緊鄰早已解釋「這一按應該改變什麼」的那段散文旁邊，理由與
    # `# expect: process-exits` 相同：這是關於**這個檔案**做了什麼的事實，而一份副本不可能與自己
    # 矛盾。
    expect_log=
    if [ -n "$action_file" ]; then
        expect_log="$(grep -m1 -E '^# *expect: *log-contains .' "$action_file" 2>/dev/null)"
        expect_log="${expect_log#*log-contains }"
        expect_log="${expect_log%$'\r'}"
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
        csv_note="${file_label}${note:+${file_label:+: }$note}"
        printf '%-30s %-8s %-9s %-9s %s\n' "$run_key" "$launch" "$replay" "$capture" "$note"
        # Same rule as the other write site below: bare comma for an empty note,
        # because that is what csv2 emits and results.csv2 is line-merged across
        # two machines. See the comment there for the measurement.
        # 與下方另一個寫入點同一規則：note 為空時寫裸逗號，因為那是 csv2 的輸出形式，而
        # results.csv2 是在兩台機器之間逐行合併的。量測依據見該處註解。
        note_field=""
        [ -n "$csv_note" ] && note_field="\"${csv_note//\"/\"\"}\""
        printf '%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
            "$run_date" "$platform" "$label" "$app" \
            "$launch" "$replay" "$capture" "$renderer" "$note_field" \
            >> "$results"
        break
    fi

    # The whole output is kept now, not only its last line.
    #
    # `tail -1` alone answers "which priority" and nothing else, so every kind of
    # failure landed on `?` with no note -- including the one where a picture WAS
    # taken and then rejected because it came back mostly black. Those two need
    # opposite responses: "no image" points at the capture tool, the window
    # handle or the host, while "rejected on content" points at rendering, and
    # the non-black fraction that screenshot.zsh prints beside it is the
    # measurement that names the cause.
    #
    # Measured on the WSL sweep of 2026-09-07, which had the same conflation:
    # 47 rows recorded "screenshot.zsh produced no image" while 56 PNGs written
    # that day, 1796..3505 bytes and none of them empty, sat in
    # output/screenshots. The wrong note hid a host EGL fault behind the capture
    # tool for several investigation steps.
    #
    # The failure arms read the whole output because the last line on the
    # no-window path is the Chinese half of the message.
    #
    # The two success arms now require the words `captured from`, and that is a
    # bug fix, not tidying. screenshot.zsh prints `captured from ...` only when
    # it succeeded, but its FAILURE message is
    #
    #     !! 優先序 1 失敗：wincap 無法擷取符合的視窗。未使用 desktop fallback；...
    #
    # which is the last line on that path and contains the word `desktop`. The
    # old `*desktop*` therefore recorded `capture=desktop` -- "a screenshot was
    # taken, just of the wrong thing" -- for a run that captured nothing at all.
    # Measured while testing this change, by feeding that exact output through
    # the old arms. `*'priority 1'*` had the matching hole: the English line
    # above it reads `priority 1 failed`, so whenever that line landed last, a
    # total failure was recorded as `window`.
    #
    # 兩個成功分支現在都要求出現 `captured from` 字樣，而那是修正錯誤，不是整理格式。
    # screenshot.zsh 只有在成功時才會印出 `captured from ...`，但它的**失敗**訊息（如上）是該路徑
    # 的最後一行，而其中含有 `desktop` 一詞。因此舊的 `*desktop*` 會把一次什麼都沒擷取到的執行記成
    # `capture=desktop`——讀起來是「有拍到，只是拍錯東西」。這是在測試本次改動時，把該段輸出原封不動
    # 餵進舊分支所實測到的。`*'priority 1'*` 有同樣的漏洞：它上一行英文寫的是 `priority 1 failed`，
    # 因此只要那一行落在最後，一次徹底的失敗就會被記成 `window`。
    #
    # 現在保留整份輸出，而不再只取最後一行。
    #
    # 單靠 `tail -1` 只能回答「哪一個優先序」，別的都答不了，於是每一種失敗都落到 `?` 且沒有任何
    # 備註——包含「照片確實拍了，但因回來時幾乎全黑而被否決」那一種。這兩者需要相反的回應：「沒有
    # 影像」指向擷取工具、視窗 handle 或主機，而「因內容被否決」指向繪製，且 screenshot.zsh 印在
    # 旁邊的非黑像素比例正是指認成因的量測值。
    #
    # 2026-09-07 的 WSL sweep 有同樣的混淆，實測如下：47 列記著「screenshot.zsh produced no
    # image」，而那天寫出的 56 張 PNG（1796 至 3505 位元組，沒有一張是空的）就放在
    # output/screenshots。那則錯誤的備註把一個主機端的 EGL 故障藏在擷取工具背後好幾個調查步驟。
    #
    # `?` 各分支語意不變，`window`/`desktop` 仍由最後一行決定，因此本 driver 既有的判定一個都不會
    # 移動。失敗分支改讀整份輸出，因為「找不到視窗」那條路徑的最後一行是訊息的中文那一半。
    shot_out="$(zsh "$repo/testapp/screenshot.zsh" -w "$app" "$label-$run_key" 2>&1 || true)"
    shot_fraction="$(printf '%s\n' "$shot_out" \
        | grep -oE 'non-black: [0-9]+/[0-9]+ \([0-9.]+%\)' | tail -1 || true)"
    case "$(printf '%s\n' "$shot_out" | tail -1)" in
        *'captured from priority 1'*) capture=window ;;
        *'captured from priority 2'*|*'captured from desktop'*) capture=desktop ;;
        *)
            case "$shot_out" in
                *'rejected on content'*)
                    capture=fail
                    note="${note:+$note; }an image WAS written and rejected on content -- ${shot_fraction:-non-black: unmeasured}; a rendering fault, not a capture one" ;;
                *'no matching window could be captured'*|*'no capture path on this platform'*)
                    capture=fail
                    note="${note:+$note; }screenshot.zsh wrote no image file at all" ;;
                *) capture='?' ;;
            esac ;;
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
    #
    # THE COMPARISON RUNS WHENEVER THERE IS AN ACTION FILE; only the VERDICT is
    # gated on `replay = ok`. The gate used to sit on the whole block, and it
    # made the check unreachable for exactly the files that need it most: an app
    # that writes no `actionfile:` line never reaches `replay = ok`, so nothing
    # was compared AND nothing said so -- including the
    # `no toplevel size in the log -- geometry unchecked` message sitting inside
    # the same block, which could not print for the same reason.
    #
    # Measured 2026-09-07. P2-controls-and-resizing.csv recorded 648x726 while
    # the window was 648x798. Its last click at 115,646 fell inside the Delete
    # row instead of the "Allow window resizing" button 68 px below it: it
    # pressed a different control, reported success, and #401's check never ran
    # -- on every run of that file. Fixed by hand in 11868267; the instrument
    # said nothing. The note those runs carried was `no output at all -- WinUI
    # build, or no SCUI_DEBUG; no log writer in P2.swift -- judge from the
    # capture`, with no mention of geometry at all.
    #
    # Counted the same day: 6 of the 40 win action files belong to apps with no
    # `debug-events` writer, and 3 of those carry a `Measured on a WxH` header
    # (P2, P3, P41). Driving all three showed the proxy is imperfect -- P41's
    # check DID fire, because `class=gdkSurfaceToplevel ... CHOSEN` comes from
    # GtkBackend rather than from the app -- so the real silent-skip set was two,
    # P2 and P3, and P3 was clean (capture 988x629, header 988x629). Two files
    # is also why `got_size` still comes from the log and NOT from the capture:
    # that alternative was considered and the count does not justify it.
    #
    # WHY THE GATE STILL EXISTS, and it must not be removed: a significant
    # mismatch sets `replay=GEOMETRY`, and without the gate that would overwrite
    # a genuine `replay=FAIL` and hide a worse result behind a lesser one. So
    # when the replay was not ok, the geometry finding goes in the note and the
    # verdict is left exactly as it was.
    #
    # **只要存在動作檔就進行比較**，被 `replay = ok` 把關的只有**判決**。這道關卡過去架在整個
    # 區塊之上，而那讓這項檢查對「最需要它的那些檔案」恰好無法抵達：不寫出 `actionfile:` 行的 app
    # 永遠到不了 `replay = ok`，於是什麼都沒被比較、也沒有任何東西這麼說——連同區塊內那句
    # `no toplevel size in the log -- geometry unchecked` 也因為同一個理由而印不出來。
    #
    # 2026-09-07 實測。P2-controls-and-resizing.csv 記載 648x726，而實際視窗是 648x798。它最後
    # 一次點擊落在 115,646，落進了 Delete 那一列，而不是位於其下方 68 px 的「Allow window
    # resizing」按鈕：它按了另一個控制項、回報成功，而 #401 的檢查從未執行過——該檔案的每一次執行
    # 皆然。已於 11868267 手動修正；量測儀器全程沉默。那些執行所帶的備註是 `no output at all --
    # WinUI build, or no SCUI_DEBUG; no log writer in P2.swift -- judge from the capture`，
    # 完全沒有提到 geometry。
    #
    # 同日清點：40 個 win 動作檔中有 6 個屬於「沒有 debug-events 寫入器」的 app，其中 3 個帶有
    # `Measured on a WxH` 標頭（P2、P3、P41）。實際驅動這三個之後可知該代理指標並不精確——P41 的
    # 檢查**確實**觸發了，因為 `class=gdkSurfaceToplevel ... CHOSEN` 來自 GtkBackend 而非該 app
    # ——因此真正被靜默略過的只有兩個：P2 與 P3，而 P3 是乾淨的（擷圖 988x629、標頭 988x629）。
    # 「只有兩個檔案」也正是 `got_size` 仍取自 log 而**不**改取自擷圖的理由：該替代方案被考慮過，
    # 而這個數量並不足以支持它。
    #
    # **這道關卡為何仍然存在**，且不可移除：顯著的尺寸不符會設定 `replay=GEOMETRY`，少了關卡，
    # 它會覆蓋一個真正的 `replay=FAIL`，把較嚴重的結果藏在較輕微的結果之後。因此當重放並非 ok 時，
    # 這項發現只寫進 note，判決維持原樣。
    if [ -n "$action_file" ]; then
        # ANCHORED ON THE SENTENCE, not on the first NNNxNNN in the file.
        #
        # Action-file headers are prose and they mention other sizes. P3's
        # first match is `220x140`, the black picture frame the test is about,
        # eight lines above the window size it actually records -- so the check
        # reported "measured at 220x140, ran at 988x629, off by 768x489" and
        # called P3 the second-worst offender in the suite. It is not an
        # offender at all; 988x638 versus 988x629 is nine pixels.
        #
        # The wording is consistent where it exists: `Measured on a WxH window
        # capture`. Twelve of the win files carry it; thirty-one contain some
        # NNNxNNN. That gap is the measurement -- matching the loose pattern
        # would have silently invented a size for nineteen files.
        #
        # 錨定於**那個句子**，而非檔案中第一個 NNNxNNN。
        #
        # 動作檔的標頭是散文，其中會提到其他尺寸。P3 的第一個匹配是 `220x140`——那是本測試所關注
        # 的黑色圖片框，位於它真正記載的視窗尺寸之上八行——於是檢查回報「measured at 220x140,
        # ran at 988x629, off by 768x489」，並把 P3 列為全套件第二嚴重者。它根本不是問題：
        # 988x638 對 988x629，差九個像素。
        #
        # 該措辭在存在之處是一致的：`Measured on a WxH window capture`。win 目錄下有十二個檔案帶
        # 有它，而含有任何 NNNxNNN 的則有三十一個。這個落差本身就是量測結果——若採寬鬆樣式，
        # 會為其中十九個檔案憑空捏造一個尺寸。
        want_size="$(grep -oE 'Measured on a [0-9]+x[0-9]+ window capture' "$action_file" \
            | head -1 | grep -oE '[0-9]+x[0-9]+')"
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
            # GRADED BY HOW FAR OUT IT IS, because "different" and "different
            # enough to hit another control" are not the same claim.
            #
            # The first version reported every difference as GEOMETRY and made
            # 15 of 26 files fail, including P23 at 848x648 versus 848x649 and
            # P26 at 928x688 versus 928x689. One pixel cannot move a control
            # past anything; calling that the same finding as P24, measured at
            # 1920x1080 and run at 748x589, buries the one that matters.
            #
            # Eight pixels is the line, and it is a judgement with a number
            # behind it: P16 reports its own row height as 22 (`sidebar: 180 x
            # 22`), so a shift under a third of a row leaves a click inside the
            # control it was aimed at. Anything at or above that can cross a
            # boundary and is reported as GEOMETRY.
            #
            # Below the line is still said out loud, in the note. It is not
            # nothing -- the window is not the one that was measured -- it is
            # just not evidence that the clicks went astray.
            #
            # 依「差多遠」分級，因為「不一樣」與「不一樣到會打到別的控制項」不是同一個主張。
            #
            # 第一版把所有差異一律報成 GEOMETRY，使 26 個檔案中的 15 個失敗，其中包含 P23 的
            # 848x648 對 848x649、以及 P26 的 928x688 對 928x689。一個像素不可能把控制項推過任何
            # 邊界；把那個與「P24 量測於 1920x1080、實際跑在 748x589」算成同一項發現，會把真正
            # 要緊的那個埋掉。
            #
            # 以八像素為界，而這是一個「背後有數字」的判斷：P16 自己回報的列高是 22
            # （`sidebar: 180 x 22`），因此小於三分之一列的位移，會讓點擊仍落在它原本瞄準的控制項
            # 之內。達到或超過該值者則可能跨越邊界，回報為 GEOMETRY。
            #
            # 低於該界線者仍會明說，寫在 note 裡。那並非無事——這個視窗不是當初被量測的那一個——
            # 只是它不構成「點擊跑掉了」的證據。
            wantw="${want_size%x*}"; wanth="${want_size#*x}"
            gotw="${got_size%x*}";   goth="${got_size#*x}"
            dw=$(( wantw > gotw ? wantw - gotw : gotw - wantw ))
            dh=$(( wanth > goth ? wanth - goth : goth - wanth ))
            if [ "$dw" -ge 8 ] || [ "$dh" -ge 8 ]; then
                # THE ONE PLACE THE VERDICT MOVES, and the only reason the gate
                # above was ever needed. `GEOMETRY` is a downgrade FROM `ok`
                # and from nothing else: a run that already said `FAIL`,
                # `ASTRAY`, `no line` or `running` keeps that word, because it
                # is the worse and more specific finding. The note below is
                # written either way, so the measurement is never lost.
                # **判決唯一會被改動的地方**，也是上方那道關卡當初唯一的存在理由。`GEOMETRY` 只
                # 從 `ok` 降級，不從其他任何值降級：已經是 `FAIL`、`ASTRAY`、`no line` 或
                # `running` 的執行會保留原本的字，因為那是更嚴重也更具體的發現。下方的 note 兩種
                # 情況都會寫，因此量測結果永遠不會遺失。
                if [ "$replay" = ok ]; then
                    replay=GEOMETRY
                fi
                note="${note:+$note; }measured at $want_size, ran at $got_size (off by ${dw}x${dh}) -- coordinates address a different layout"
            else
                note="${note:+$note; }measured at $want_size, ran at $got_size (off by ${dw}x${dh}, under a third of a row)"
            fi
        fi
    fi

    # DID THE REPLAY ACHIEVE WHAT THE FILE SAYS IT IS FOR?
    #
    # Read `# expect: log-contains ...` above for the spelling and for the P44
    # run that made it necessary. This is where the declaration is settled, and
    # these states have to stay apart, because they need different fixes:
    #
    #   the replay never ran        verdict untouched (`no line`, `FAIL`,
    #                               `running`, ...), note says the expectation
    #                               was not checked. There is no evidence about
    #                               the feature either way.
    #   it ran, the app said        `UNMET`. The app was writing and this
    #   things, none of them the    outcome is not among them, so either the
    #   text                        click missed its control, or the control
    #                               does nothing.
    #   it ran, the app said        `UNCHECKED`. Absence of evidence, not
    #   nothing at all              evidence of absence -- an app that logs
    #                               nothing cannot be asked what it did.
    #   the text was found          the verdict it already had, plus a note
    #                               naming what was established.
    #
    # MISSING IS NOT PASSING, AND UNVERIFIABLE IS NOT PASSING EITHER. A file
    # with no `# expect: log-contains` line keeps today's behaviour exactly --
    # `expect_log` is empty and this block does nothing, which is the case for
    # every win action file but P44. A file that HAS one and cannot be shown to
    # have met it does not get to report `ok`: a silent app is `UNCHECKED`,
    # which is the same defect the geometry gate above had and must not be
    # reintroduced here in a new place.
    #
    # WHY THE APP'S OWN LOG AND NOT ONLY THE RUN LOG. `P44Diagnostics.write`
    # does both -- `print("[P44] ...")` to stdout and an append to
    # p44-debug-events.log -- so "check the run log" looked sufficient. Measured
    # 2026-09-07 on the run at 20:52:29: p44-debug-events.log gained
    # `third cell clipped: true`, and `grep -c 'third cell clipped'` on
    # /tmp/sweep_drive-gtk4/P44-clip-third-cell.log returned 0. Not one `[P44]`
    # line reached the run log, because Swift's `print` to a redirected stdout
    # is block-buffered and `taskkill /F` kills the process before it flushes;
    # the `-actionfile:` lines that ARE in that file come from a different,
    # unbuffered writer. Checking the run log alone would have called a working
    # feature `UNMET` -- a false accusation, which is the more expensive
    # direction of the two.
    #
    # The verdict moves only from `ok`, exactly as `GEOMETRY` does above. A run
    # that is already `FAIL` or `GEOMETRY` keeps that word: `GEOMETRY` in
    # particular names a CAUSE for an unmet expectation, and replacing it with
    # the symptom would throw away the more useful half.
    #
    # 這次重放，有沒有達成這個檔案所宣稱的目的？
    #
    # 寫法與「P44 那次執行為何使它成為必要」見上方的 `# expect: log-contains ...`。此處是該宣告
    # 被結算的地方，而這幾種狀態必須分開，因為它們要修的東西不同：重放從未執行（判決不動，note
    # 說明未經檢查，對該功能兩邊都沒有證據）；跑了、app 也寫了東西，但其中沒有那段文字（`UNMET`
    # ——app 當時確實在寫，而這個結果不在其中，因此不是點擊沒打中它的控制項，就是該控制項什麼也
    # 沒做）；跑了、但 app 從頭到尾什麼都沒寫（`UNCHECKED`——那是「缺乏證據」而非「證明其不存在」；
    # 一個什麼都不記錄的 app，無從被詢問它做了什麼）；找到了那段文字（維持原判決，並以 note 指明
    # 所確立的事實）。
    #
    # **沒有宣告不等於通過，無法查證也不等於通過。** 沒有 `# expect: log-contains` 行的檔案，行為
    # 與今日完全相同——`expect_log` 為空、本區塊什麼也不做，而 win 動作檔中除 P44 之外全屬此類。
    # 有宣告卻無法被證明已滿足的檔案，不得回報 `ok`：沉默的 app 即為 `UNCHECKED`，那正是上方
    # geometry 關卡曾有的同一個缺陷，不可在新的地方重新引入。
    #
    # **為何要讀 app 自己的 log，而不只讀 run log。** `P44Diagnostics.write` 兩者都做——
    # `print("[P44] ...")` 寫到 stdout，同時追加到 p44-debug-events.log——因此「查 run log」看似
    # 足夠。2026-09-07 對 20:52:29 那次執行實測：p44-debug-events.log 增加了
    # `third cell clipped: true`，而對 /tmp/sweep_drive-gtk4/P44-clip-third-cell.log 執行
    # `grep -c 'third cell clipped'` 回傳 0。沒有任何一行 `[P44]` 抵達 run log，因為 Swift 的
    # `print` 在 stdout 被重導向時採區塊緩衝，而 `taskkill /F` 在它 flush 之前就殺掉了行程；該檔案
    # 中確實存在的 `-actionfile:` 行來自另一個不帶緩衝的寫入器。只查 run log 會把一項可運作的功能
    # 判成 `UNMET`——那是誣告，而在兩個方向之中它的代價更高。
    #
    # 判決同樣只從 `ok` 移動，與上方的 `GEOMETRY` 完全一致。已經是 `FAIL` 或 `GEOMETRY` 的執行保留
    # 原本的字：`GEOMETRY` 尤其是在指認「期望未達成」的**成因**，若以症狀取代它，等於丟掉更有用的
    # 那一半。
    if [ -n "$expect_log" ]; then
        if ! grep -q 'actionfile: replayed' "$run_log" 2>/dev/null; then
            note="${note:+$note; }expectation '$expect_log' not checked -- the replay did not run"
        else
            # Only the bytes this run appended, per the mark taken before the
            # launch. A file shorter than the mark was rotated or replaced
            # between the two points, so the whole of it is new.
            # 只取本次執行所追加的位元組，依啟動前所記下的標記。若檔案比標記還短，代表它在兩個時點
            # 之間被輪替或替換過，因此整份都是新的。
            app_new=
            if [ -f "$app_log" ]; then
                app_log_now="$(wc -c < "$app_log" 2>/dev/null | tr -d ' ')"
                [ -z "$app_log_now" ] && app_log_now=0
                [ "$app_log_now" -lt "$app_log_before" ] && app_log_before=0
                app_new="$(tail -c "+$(( app_log_before + 1 ))" "$app_log" 2>/dev/null)"
            fi

            # TWO DIFFERENT SETS, ON PURPOSE.
            #
            # `haystack` is everywhere the text could possibly be -- the whole
            # run log plus this run's new bytes -- because failing to find text
            # that IS there would accuse a working feature, and that is the
            # expensive direction.
            #
            # `spoke` is the narrower question "did the app itself say anything
            # this run", and it decides UNCHECKED versus UNMET. Without it
            # UNCHECKED is unreachable: at this point the run log always holds
            # the `actionfile: replayed` line, so a test for an empty log can
            # never fire, and an unreachable branch reporting "not verified" is
            # the same defect as no branch at all -- measured while writing
            # this, on a fabricated case where the app wrote nothing and the
            # verdict came out UNMET.
            #
            # `[Pnn] ` is the app-side stdout prefix; 41 of the testapp sources
            # use it (`grep -lE 'print\("\[P[0-9]+' testapp/P*.swift | wc -l`).
            # The `[]-]` class admits `[P6-v2]` while keeping `[P4]` and `[P44]`
            # apart.
            #
            # `${app}` IS BRACED AND MUST STAY BRACED. Written `$app[]-]`, zsh
            # reads the bracket as an array subscript on `app`, not as text for
            # grep: it printed `invalid subscript`, the pattern never reached
            # grep, `spoke` came back empty, and a run where the app HAD spoken
            # on stdout was reported `UNCHECKED` instead of `UNMET`. Measured
            # here on 2026-09-07, in the harness written to test this block --
            # the wrong answer was plausible, which is why it needed a test
            # rather than a reading.
            #
            # **刻意分成兩個集合。** `haystack` 是那段文字可能出現的一切位置——整份 run log 加上本
            # 次執行新增的位元組——因為「文字明明在那裡卻沒找到」會誣告一項可運作的功能，而那是代價
            # 較高的方向。`spoke` 問的是較窄的問題：「這次執行中，app 自己有沒有說過話」，並由它決定
            # UNCHECKED 或 UNMET。少了它，UNCHECKED 將無法抵達：走到這裡時 run log 必定含有
            # `actionfile: replayed` 那一行，因此「log 為空」的測試永遠不會成立；而一個無法抵達、
            # 卻宣稱「未經查證」的分支，與根本沒有這個分支是同一個缺陷——此事於撰寫本段時，以「app
            # 什麼都沒寫」的捏造案例實測，判決當時落在 UNMET。
            #
            # `[Pnn] ` 是 app 端的 stdout 前綴；testapp 中有 41 份原始碼使用它（重新清點請用
            # `grep -lE 'print\("\[P[0-9]+' testapp/P*.swift | wc -l`）。`[]-]` 這個字元類容許
            # `[P6-v2]`，同時讓 `[P4]` 與 `[P44]` 不會互相誤配。
            #
            # **`${app}` 有加大括號，而且必須保持加著。** 若寫成 `$app[]-]`，zsh 會把方括號讀成對
            # `app` 的陣列下標，而不是要交給 grep 的文字：它印出 `invalid subscript`、樣式從未抵達
            # grep、`spoke` 因而為空，於是一次「app 確實在 stdout 上說過話」的執行被報成
            # `UNCHECKED` 而非 `UNMET`。於 2026-09-07 在為本區塊所寫的測試工具中實測——錯誤答案看
            # 起來完全合理，這正是它需要被測試、而不是被閱讀的理由。
            haystack="$(cat "$run_log" 2>/dev/null; printf '%s' "$app_new")"
            spoke="$(grep -E "^\[${app}[]-]" "$run_log" 2>/dev/null; printf '%s' "$app_new")"

            if printf '%s\n' "$haystack" | grep -qF -- "$expect_log"; then
                note="${note:+$note; }expectation met: '$expect_log'"
            elif [ -z "$spoke" ]; then
                if [ "$replay" = ok ]; then
                    replay=UNCHECKED
                fi
                note="${note:+$note; }expectation '$expect_log' could not be checked -- the replay ran but the app wrote nothing this run"
            else
                if [ "$replay" = ok ]; then
                    replay=UNMET
                fi
                note="${note:+$note; }expectation NOT met: '$expect_log' is absent from what the app wrote -- the click missed its control, or the control does nothing"
            fi
        fi
    fi

    csv_note="${file_label}${note:+${file_label:+: }$note}"
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
    # QUOTE THE NOTE ONLY WHEN THERE IS ONE, because csv2 spells an empty field
    # as a bare comma and this script was spelling it `""`.
    #
    # Both are valid CSV and both read back as empty, but they are DIFFERENT
    # STRINGS, and results.csv2 is merged between two machines by comparing
    # lines. On 2026-09-07 a rebase of this branch onto the Mac side reported 64
    # rows as new that were the same rows already present, differing only in
    # that spelling -- and a naive union would have doubled every one of them in
    # the history the coverage matrix is computed from.
    #
    # csv2 is the authority and it was asked: appending a row with an empty last
    # field produces `5,6,`. The bare comma is the convention; this script was
    # the odd one out because it formats the row with printf instead of going
    # through csv2, and hard-coded the quotes into the format string.
    #
    # 只有在 note 非空時才加引號——因為 csv2 把空欄位寫成裸逗號，而本腳本一直寫成 `""`。
    #
    # 兩者都是合法的 CSV，讀回來也都是空值，但它們是**不同的字串**；而 results.csv2 是靠逐行比對
    # 在兩台機器之間合併的。2026-09-07，把本分支 rebase 到 Mac 那一側時，有 64 列被回報為新增，
    # 而它們其實就是已經存在的同一批列，差別僅在這個寫法——若照單全收做聯集，覆蓋率矩陣所依據的
    # 歷史中，那 64 列每一列都會被算成兩次。
    #
    # csv2 才是權威，而它已經被問過了：追加一列、最後一欄為空，它寫出的是 `5,6,`。裸逗號才是慣例；
    # 本腳本之所以是異類，是因為它用 printf 拼出資料列而不是經由 csv2，並把引號寫死在格式字串裡。
    note_field=""
    [ -n "$csv_note" ] && note_field="\"${csv_note//\"/\"\"}\""
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
        "$run_date" "$platform" "$label" "$app" \
        "$launch" "$replay" "$capture" "$renderer" "$note_field" \
        >> "$results"
    break
    done
    done
done

printf '\nlogs in %s ; captures in testapp/output/screenshots/%s-*.png\n' "$log_dir" "$label"
printf 'results appended to %s -- run coverage.zsh to regenerate the matrix\n' "$results"
exit 0
