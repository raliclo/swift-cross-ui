#!/usr/bin/env zsh
# Shared GUI dry-run helper for test_P*.zsh wrappers.
#
# The flow intentionally matches test_P8.zsh: build, launch, take an early
# screenshot, optionally wait for an app render marker, keep the window open for
# tester collaboration, take a final screenshot, close, and print diagnostics.

set -euo pipefail

support_dir="${0:a:h}"
script_dir="${support_dir:h}"
script_path="${0:a}"
app="${TEST_APP:?TEST_APP is required}"
title="${TEST_TITLE:-$app}"
log_name="${TEST_LOG_NAME:-${app:l}-debug-events.log}"
marker="${TEST_MARKER:-}"
timeout_seconds="${TEST_TIMEOUT_SECONDS:-30}"
showtime_seconds="${TEST_SHOWTIME_SECONDS:-30}"
target="${TEST_TARGET:-wsl}"
target_explicit=0
device_name=""

# WHERE THE APPS' OWN DEBUG-EVENT LOGS GO, and the single contract that decides
# it: the environment variable `SCUI_DEBUG_EVENTS_DIR`.
#
# Every app reads it and falls back to its current working directory when it is
# unset, so a bare `./P44.exe` still writes beside itself and nothing outside a
# launcher changes. This script exports it and creates the directory before each
# launch -- a Foundation write into a directory that does not exist fails through
# `try?` and says nothing at all, which would read as an app that never logged.
#
# Why it exists: 38 of the testapp sources each carried their own copy of
# `URL(fileURLWithPath: FileManager.default.currentDirectoryPath)`, so the log
# landed wherever the app happened to be started from. 83 files had collected
# across the repo root, testapp/ and testapp/output/, 44 of them same-named
# copies from different directories. Re-derive the two numbers with
# `grep -l SCUI_DEBUG_EVENTS_DIR testapp/P*.swift | wc -l` (38 on 2026-09-08) and
# `ls testapp/debug-events | wc -l` (83 on 2026-09-08).
#
# The WSL value names the LINUX copy of the repo, not this one: the app is
# launched from the rsync'd tree under /home/lowei, and /mnt/c would be a
# different checkout. It is expanded here, on the Windows side, so what crosses
# `wsl.exe` is a literal path with no `$` left in it -- see ~/.claude/CLAUDE.md
# on `$var` being eaten crossing Windows to WSL even inside single quotes.
#
# app 自身的 debug-event log 該落在哪裡，以及決定此事的唯一約定：環境變數
# `SCUI_DEBUG_EVENTS_DIR`。
#
# 每支 app 都會讀它，未設定時退回自己的工作目錄，因此直接執行 `./P44.exe` 仍寫在原地，啟動器以外
# 的一切都不改變。本腳本負責 export 它，並在每次啟動前建立該目錄——Foundation 寫入不存在的目錄時
# 會被 `try?` 吞掉，不發出任何聲響，讀起來就像這支 app 從未寫過 log。
#
# 它的由來：38 支 testapp 原始碼各自帶著一份
# `URL(fileURLWithPath: FileManager.default.currentDirectoryPath)`，於是 log 落在 app 當時的啟動
# 目錄，最終在 repo 根目錄、testapp/ 與 testapp/output/ 之間累積了 83 個檔案，其中 44 個是來自不同
# 目錄的同名副本。這兩個數字的重新推導指令見上方英文段落。
#
# WSL 所用的值指向 repo 的 **Linux 副本**，而非此處這一份：app 是由 /home/lowei 底下經 rsync 的樹
# 啟動的，而 /mnt/c 會是另一份 checkout。該值在 Windows 這一側就展開，因此穿過 `wsl.exe` 的是一條
# 不含 `$` 的字面路徑——`$var` 跨越 Windows 到 WSL 時即使加了單引號也會被吃掉，詳見
# ~/.claude/CLAUDE.md。
events_dir="$script_dir/debug-events"
wsl_events_dir="/home/lowei/proj/swift-cross-ui/testapp/debug-events"

# Where the macOS run assembles its .app, and what it assembles from.
#
# The bundle is kept out of Git and only the small template is tracked; each run
# replaces one executable inside it. See run_macos for why it is built at all.
# macOS 執行時所組出的 .app 位置，以及其來源。該 bundle 不納入 Git，僅追蹤小型 template；
# 每次執行只替換其中的一個執行檔。為何要組 bundle，見 run_macos。
mac_bundle_root="$script_dir/.macApp"
mac_template_dir="$script_dir/macContainer/appTemplate.app"
mac_bundle_dir="$mac_bundle_root/debugTarget.app"
mac_bundle_executable="$mac_bundle_dir/debugTarget"
mac_app_pid=""
do_build=1
summary_pattern="${TEST_SUMMARY_PATTERN:-RENDER COMPLETE|content:|geometry|size|scroll|Scroll|#}"
app_args="${TEST_APP_ARGS:---debug}"
host_uname="$(uname -s 2>/dev/null || printf unknown)"

windows_path_mixed() {
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -m "$1"
        return
    fi

    case "$1" in
        /?/*)
            local drive rest
            drive="$(printf '%s' "$1" | cut -c 2 | tr '[:lower:]' '[:upper:]')"
            rest="$(printf '%s' "$1" | cut -c 4-)"
            printf '%s:/%s\n' "$drive" "$rest"
            ;;
        /cygdrive/?/*)
            local drive rest
            drive="$(printf '%s' "$1" | cut -c 11 | tr '[:lower:]' '[:upper:]')"
            rest="$(printf '%s' "$1" | cut -c 13-)"
            printf '%s:/%s\n' "$drive" "$rest"
            ;;
        *)
            printf '%s\n' "$1"
            ;;
    esac
}

posix_path() {
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -u "$1"
        return
    fi

    case "$1" in
        [A-Za-z]:/*)
            local drive rest
            drive="$(printf '%s' "$1" | cut -c 1 | tr '[:upper:]' '[:lower:]')"
            rest="$(printf '%s' "$1" | cut -c 4-)"
            printf '/%s/%s\n' "$drive" "$rest"
            ;;
        [A-Za-z]:\\*)
            local drive rest
            drive="$(printf '%s' "$1" | cut -c 1 | tr '[:upper:]' '[:lower:]')"
            rest="$(printf '%s' "$1" | cut -c 4- | tr '\\' '/')"
            printf '/%s/%s\n' "$drive" "$rest"
            ;;
        *)
            printf '%s\n' "$1"
            ;;
    esac
}

# Environment the app is launched with, as `NAME=value` pairs separated by
# spaces. Empty for most apps.
#
# Some diagnostics live in SwiftCrossUI itself rather than in the test app, and
# those are gated on an environment variable because the library has no
# command line to read. P7 needs SCUI_DEBUG_SPLIT: without it the run still
# reports every content size, but not the bounds the layout system hands the
# backend nor where the divider actually ended up -- and content width is not
# pane width. Reading one as the other produced two confident, wrong diagnoses
# of #556 before the variable existed.
# app 啟動時附帶的環境變數，格式為以空白分隔的 `NAME=value`，多數 app 為空。
#
# 部分診斷位於 SwiftCrossUI 本身而非測試 app，只能以環境變數開關，因為函式庫讀不到
# 命令列。P7 需要 SCUI_DEBUG_SPLIT：少了它仍會回報所有內容尺寸，但看不到 layout
# 系統交給 backend 的上下界，也看不到分隔線最後停在哪——而內容寬度並不等於 pane
# 寬度，把兩者混為一談曾對 #556 造成兩次自信但錯誤的判斷。
app_env="${TEST_APP_ENV:-}"

# An optional second log to clear before the run and include in the summary.
# Diagnostics that live in the library write their own file rather than the
# app's, so without this the run would silently report only half of what it
# collected -- and a summary that looks complete while missing the deciding
# numbers is worse than one that is obviously empty.
# 可選的第二個 log：執行前一併清空，摘要時一併納入。位於函式庫的診斷會寫自己的檔案
# 而非 app 的，若不處理，執行結果會靜默地只呈現一半——而看起來完整卻缺少關鍵數字的
# 摘要，比明顯空白的摘要更危險。
extra_log="${TEST_EXTRA_LOG:-}"

# The remote command is assembled here rather than tested inside the string
# sent to WSL. A conditional written there is parsed before it is evaluated, so
# an empty name still leaves `: >` with nothing to redirect into and the whole
# command dies with `parse error near ';'` -- before the app is ever launched.
# Building the fragment in advance means the empty case contributes no text.
# 遠端指令在此組好，而不是在送往 WSL 的字串內做條件判斷。字串裡的條件式會先被解析
# 再求值，因此名稱為空時 `: >` 仍然沒有重導向目標，整條指令會以
# `parse error near ';'` 失敗——而且是在 app 啟動之前。事先組好片段，空值就不會
# 產生任何文字。
clear_extra_fragment=""
if [ -n "$extra_log" ]; then
    clear_extra_fragment=" && : > $extra_log"
fi

# A CSV action file to replay once the window is up, for `--actionfile`.
#
# Handled by the backend rather than by the app, so it works for every Pn
# without any of them knowing about it -- see Sources/GtkBackend/
# ActionFileReplay.swift and the format in Sources/InputEvent/README.md.
#
# `--actionfile` with no path uses testapp/actions/<app>-*.csv, because the
# common case is one file per app named after it and typing the path each time
# invites the wrong one being replayed against the right app.
#
# 供 `--actionfile` 使用：待視窗出現後重放的 CSV 動作檔。
#
# 由 backend 而非 app 處理，因此每一支 Pn 都不需要知道它的存在——詳見
# Sources/GtkBackend/ActionFileReplay.swift，格式見 Sources/InputEvent/README.md。
#
# `--actionfile` 未帶路徑時使用 testapp/actions/<app>-*.csv：常見情況是每支 app 一個以其命名的
# 檔案，而每次都手打路徑，只會招來「對正確的 app 重放了錯誤的檔案」。
action_file="${TEST_ACTION_FILE:-}"
actionfile_log="${app:l}-actionfile.log"
renderer_log="${app:l}-renderer.log"

# Resolved by test.zsh. Defaults are repeated here so the single-test wrappers
# remain usable directly during development.
# 由 test.zsh 解析；此處保留相同預設，讓開發時仍可直接執行單一測試 wrapper。
render_mode="${TEST_RENDER_MODE:-hw}"
render_env="${TEST_RENDER_ENV:-GALLIUM_DRIVER=d3d12 MESA_D3D12_DEFAULT_ADAPTER_NAME=NVIDIA GSK_DEBUG=renderer}"
render_explicit="${TEST_RENDER_EXPLICIT:-0}"

# The platform folder, not the whole tree.
#
# Action files are filed by the platform they passed on, because a list of
# coordinates does not travel: fonts, decorations and display scale all move
# things. Looking in every folder would find a file that works somewhere else
# and run it here, which fails as a series of clicks landing on nothing.
#
# 只在該平台的資料夾中尋找，而非整棵樹。
#
# 動作檔依「通過驗證的平台」歸檔，因為一串座標無法跨平台：字型、視窗裝飾與顯示縮放都會使位置改變。
# 若在所有資料夾中尋找，會找到一個「在別處可用」的檔案並在此執行，其失敗形式是一連串點擊全部落空。
platform_folder() {
    case "$target" in
        windows) printf 'win' ;;
        macos) printf 'mac' ;;
        # Named rather than left to the default. Falling through to `wsl` is how
        # `--ios --actionfile` came to resolve a WSL file and replay it on the
        # Simulator -- the failure the comment above describes, produced by the
        # very function meant to prevent it.
        # 明確列出，而非交給預設值。正是因為落入 `wsl`，`--ios --actionfile` 才會取得一個 WSL
        # 的動作檔並在模擬器上重放——上方註解所描述的那種失敗，由本應防止它的函式親手造成。
        ios) printf 'ios' ;;
        android) printf 'android' ;;
        *) printf 'wsl' ;;
    esac
}

default_action_file() {
    local folder
    folder="$(platform_folder)"
    local candidates=("$script_dir/actions/$folder/$app"-*.csv(N))

    # Drop candidates that belong to a longer-named app.
    #
    # `$app-*.csv` is a prefix glob, and some apps are prefixes of others:
    # P15 and P15-DARK, P6 and P6-v2, P17 and P17-DOE. Asking for P15 matched
    # P15-DARK's file too and the run stopped with "Several action files for
    # P15" -- which reads as two files for one app rather than one file each
    # for two apps.
    #
    # The other names are read from the .swift files rather than listed here,
    # so a new P15-SOMETHING needs no change to this function.
    #
    # 排除屬於「名稱更長的另一支 app」的候選檔。
    #
    # `$app-*.csv` 是前綴 glob，而有些 app 的名稱正是另一些的前綴：P15 與 P15-DARK、P6 與 P6-v2、
    # P17 與 P17-DOE。要求 P15 時會連 P15-DARK 的檔案一起匹配，執行便以「Several action files for
    # P15」中止——那讀起來像是「一支 app 有兩個檔案」，而實際上是「兩支 app 各有一個檔案」。
    #
    # 其他 app 的名稱是自 .swift 檔讀取，而非列在此處，因此日後新增 P15-SOMETHING 不需要更動本函式。
    if [ "${#candidates}" -gt 1 ]; then
        local other kept=()
        local others=("$script_dir"/"$app"-*.swift(N:t:r))
        for candidate in $candidates; do
            local name="${candidate:t}"
            local claimed=0
            for other in $others; do
                if [[ "$name" == "$other"-* ]]; then
                    claimed=1
                    break
                fi
            done
            [ "$claimed" -eq 0 ] && kept+=("$candidate")
        done
        [ "${#kept}" -gt 0 ] && candidates=($kept)
    fi
    if [ "${#candidates}" -eq 0 ]; then
        printf 'No action file for %s in %s/actions/%s\n' "$app" "$script_dir" "$folder" >&2
        printf 'A file appears there once it has been verified on that platform.\n' >&2
        exit 66
    fi
    if [ "${#candidates}" -gt 1 ]; then
        printf 'Several action files for %s; name one:\n' "$app" >&2
        printf '  %s\n' "${candidates[@]:t}" >&2
        exit 64
    fi
    printf '%s' "${candidates[1]}"
}

usage() {
    cat <<EOF_USAGE
Usage: ${script_path:t} [--wsl|-win|--windows|--macos|--ios|--android|--both] [-render hw|sw] [-n|--no-build] [--showtime [seconds]|--showtime=seconds|--no-showtime] [--actionfile [path]]

Runs $app with the common UI dry-run flow.

The platform flag is optional. $app declares "$target"; on a host that cannot
drive it, the run moves to one that can and says so. Naming a platform this host
cannot drive is refused rather than redirected.
Default showtime: ${showtime_seconds}s

--actionfile replays a CSV of synthesised clicks and keystrokes once the window
is up. With no path, testapp/actions/$app-*.csv is used. The format is
documented in Sources/InputEvent/README.md.

-render hw|sw selects D3D12/NVIDIA or llvmpipe for WSLg GtkBackend runs.
The default is hw.

The app's own event log goes to testapp/debug-events/$log_name, on every
platform, because this script exports SCUI_DEBUG_EVENTS_DIR. Run the executable
by hand and it writes to the current directory instead, as it always has.
EOF_USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        -w|--wsl) target="wsl"; target_explicit=1; shift ;;
        -win|--windows) target="windows"; target_explicit=1; shift ;;
        -mac|--macos) target="macos"; target_explicit=1; shift ;;
        # iOS and Android arrived as their own top-level scripts, so reaching
        # them meant knowing a different command and a different flag spelling
        # for the same act -- run this app on that platform. They are targets
        # here like the rest; the scripts stay where they are and do the work.
        # iOS 與 Android 原本各自是頂層腳本，因此要用到它們就得記住另一個命令與另一套旗標寫法，
        # 而所做的其實是同一件事——在某個平台上執行這支 app。此處將它們與其他平台一視同仁地列為
        # target；那兩支腳本仍留在原處並負責實際工作。
        -ios|--ios) target="ios"; target_explicit=1; shift ;;
        -android|--android) target="android"; target_explicit=1; shift ;;
        -b|--both) target="both"; target_explicit=1; shift ;;
        -render|--render)
            [ "$#" -gt 1 ] || { printf -- '%s requires hw or sw\n' "$1" >&2; exit 64; }
            render_mode="$2"
            render_explicit=1
            case "$render_mode" in
                hw) render_env='GALLIUM_DRIVER=d3d12 MESA_D3D12_DEFAULT_ADAPTER_NAME=NVIDIA GSK_DEBUG=renderer' ;;
                sw) render_env='LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe GSK_DEBUG=renderer' ;;
                *) printf 'Invalid -render value: %s (expected hw or sw)\n' "$render_mode" >&2; exit 64 ;;
            esac
            shift 2
            ;;
        -render=*|--render=*)
            render_mode="${1#*=}"
            render_explicit=1
            case "$render_mode" in
                hw) render_env='GALLIUM_DRIVER=d3d12 MESA_D3D12_DEFAULT_ADAPTER_NAME=NVIDIA GSK_DEBUG=renderer' ;;
                sw) render_env='LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe GSK_DEBUG=renderer' ;;
                *) printf 'Invalid -render value: %s (expected hw or sw)\n' "$render_mode" >&2; exit 64 ;;
            esac
            shift
            ;;
        -n|--no-build) do_build=0; shift ;;
        # Only iOS and Android have a device to choose. It lives here rather
        # than only in those two scripts so that one vocabulary covers every
        # platform; the resolution below refuses it where it means nothing.
        # 只有 iOS 與 Android 有裝置可選。此旗標置於此處而非僅存在於那兩支腳本中，是為了讓同一套
        # 詞彙涵蓋所有平台；下方的解析步驟會在它沒有意義之處拒絕它。
        --device)
            [ "$#" -gt 1 ] || { printf -- '--device requires a name or id\n' >&2; exit 64; }
            device_name="$2"
            shift 2
            ;;
        --showtime)
            if [ "$#" -gt 1 ] && [[ "$2" == <-> ]]; then
                showtime_seconds="$2"
                shift 2
            else
                showtime_seconds=30
                shift
            fi
            ;;
        --showtime=*)
            showtime_seconds="${1#*=}"
            if ! [[ "$showtime_seconds" == <-> ]]; then
                printf 'Invalid --showtime value: %s\n' "$showtime_seconds" >&2
                exit 64
            fi
            shift
            ;;
        --no-showtime) showtime_seconds=0; shift ;;
        --actionfile)
            if [ "$#" -gt 1 ] && [ "${2#-}" = "$2" ]; then
                action_file="$2"
                shift 2
            else
                action_file="$(default_action_file)"
                shift
            fi
            ;;
        --actionfile=*) action_file="${1#*=}"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 64 ;;
    esac
done

if [ -n "$action_file" ]; then
    action_file="${action_file:A}"
fi

# ==============================================================================
# Which platform this run is for, when nobody said.
#
# Every test script declares a TEST_TARGET, and 23 of the 24 name a Windows or
# WSL one -- they were written on the machine that could run them. On a Mac that
# makes the bare command wrong by default: `zsh testapp/test.zsh P8` resolves to
# `both`, reaches for `wsl.exe`, and fails for a reason that has nothing to do
# with P8.
#
# So a target the host cannot drive is replaced by one it can. The declared
# target is still honoured wherever it works, which matters on Windows: P8 says
# `both` there and `both` is exactly right, so nothing changes for that machine.
#
# An explicitly requested target is never substituted. Asking for `--wsl` on a
# Mac is refused rather than quietly redirected -- a flag that silently runs
# somewhere else is worse than one that fails.
#
# 沒有人指定時，這次執行屬於哪個平台。
#
# 每一支測試腳本都宣告了 TEST_TARGET，而 24 支中有 23 支指定的是 Windows 或 WSL——它們是在能夠
# 執行那些目標的機器上寫成的。在 Mac 上，這使得不帶旗標的指令預設就是錯的：
# `zsh testapp/test.zsh P8` 會解析為 `both`、去呼叫 `wsl.exe`，然後以一個與 P8 毫無關係的理由失敗。
#
# 因此，主機無法驅動的 target 會被替換為它能驅動的。在可行之處仍尊重原宣告的 target，這對 Windows
# 很重要：P8 在該處宣告 `both`，而 `both` 正是對的，因此那台機器上什麼也不會改變。
#
# 明確指定的 target 絕不會被替換。在 Mac 上要求 `--wsl` 會被拒絕，而非悄悄改到別處執行——一個
# 安靜地跑到別的地方去的旗標，比一個直接失敗的旗標更糟。
# ==============================================================================
host_platform() {
    # Same classification ui-lock.zsh uses, so the two cannot disagree about
    # what machine this is.
    # 與 ui-lock.zsh 採用相同的分類方式，兩者對「這是哪一台機器」不會有分歧。
    case "$(uname -s 2>/dev/null || printf unknown)" in
        Darwin) printf 'macos' ;;
        MINGW*|MSYS*|CYGWIN*) printf 'windows' ;;
        *) printf 'unknown' ;;
    esac
}

# `wsl` and `both` drive WSL through `wsl.exe`, so they need a Windows host
# rather than a Linux one -- running this from inside WSL, or on plain Linux,
# is not the same thing. `ios` and `android` delegate to scripts that already
# refuse to run anywhere but macOS.
# `wsl` 與 `both` 是透過 `wsl.exe` 驅動 WSL，因此需要的是 Windows 主機而非 Linux 主機——從 WSL
# 內部或在一般 Linux 上執行並非同一回事。`ios` 與 `android` 則委派給本就拒絕在 macOS 以外執行的
# 腳本。
case "$(host_platform)" in
    macos)
        host_targets=(macos ios android)
        host_default="macos"
        ;;
    windows)
        host_targets=(windows wsl both)
        host_default="windows"
        ;;
    *)
        # Unknown host: assume nothing and change nothing. A wrong guess here
        # would send a run to a platform the caller never asked for.
        # 未知主機：不做任何假設，也不做任何更動。此處猜錯會把一次執行送往呼叫者從未要求的平台。
        host_targets=()
        host_default=""
        ;;
esac

if [ -n "$device_name" ] && [[ "$target" != "ios" && "$target" != "android" ]]; then
    printf -- '--device applies to --ios and --android only; target is "%s".\n' "$target" >&2
    exit 64
fi

if [ -n "$host_default" ] && [[ ! " ${host_targets[*]} " == *" $target "* ]]; then
    if [ "$target_explicit" -eq 1 ]; then
        printf 'Target "%s" cannot run on this host (%s).\n' "$target" "$(host_platform)" >&2
        printf 'Available here: %s\n' "${host_targets[*]}" >&2
        exit 64
    fi
    printf '==> %s defaults to "%s"; running "%s" on this host\n' \
        "$app" "$target" "$host_default"
    target="$host_default"
fi

if [ "$render_explicit" -eq 1 ] && [[ "$target" != "wsl" && "$target" != "both" ]]; then
    printf -- '-render applies to WSLg GtkBackend only; target is "%s".\n' "$target" >&2
    exit 64
fi

# Takes a screenshot and says so when it does not.
#
# The call sites used to end in `|| true`, which was accurate while
# screenshot.zsh exited 0 whatever happened -- it could not fail, so there was
# nothing to swallow. It can now: 1 when it produced no image, 3 when the host
# has no capture path at all, 4 when it wrote an image and then rejected it on
# content. `|| true` would discard exactly the signal that was missing before.
#
# The run is not aborted. A screenshot is evidence, not the assertion, and a
# window that rendered and logged its diagnostics is still worth reading. But
# the failure is announced where it happens and counted for the summary, so a
# run that produced no pictures cannot look like one that did.
#
# WHY THIS FUNCTION LOOKS FOR THE FILE.
#
# It did not, and that is the bug it now exists to prevent. The message read
# "screenshot.zsh exited %d and produced no image" for every non-zero code that
# was not 3 -- an inference from an exit status, never a look at the disk.
#
# Measured 2026-09-07: a WSLg sweep recorded 47 rows as "screenshot.zsh produced
# no image". The images existed. 56 PNGs were written that day, none zero-byte,
# 1796..3505 bytes. The wincap log beside one of them reads
#
#     window: [WARN:COPY MODE] P11 sliders, scrollbars and pickers (Ubuntu)
#     size: 788x649  exstyle: 0x80100
#     PrintWindow: true  non-black: 19922/511412 (3.8%)
#
# The picture was taken and it was 96.2% black. Since todo #77 made wincap judge
# content by a non-black FRACTION rather than by any single surviving pixel, a
# capture that succeeds mechanically and comes back mostly black exits non-zero,
# and the old message then said the opposite of what had happened.
#
# The two states need opposite responses. "No image" points at the capture tool,
# the window handle, the host. "Image rejected on content" points at rendering:
# the same app, the same 788x649 window, software-rendered minutes later,
# measures 92.1% non-black. In this instance the wrong message hid a host-level
# EGL fault and several investigation steps went into asking whether
# screenshot.zsh was broken, while 56 PNGs sat on disk contradicting its report.
#
# 擷取畫面；若未能擷取，就明白說出來。
#
# 各呼叫點原本以 `|| true` 結尾，而在 screenshot.zsh 無論如何都回傳 0 的年代，那是準確的——它不
# 可能失敗，因此也沒有什麼可被吞掉。現在它會失敗了：未產生影像時回傳 1，主機根本沒有擷取路徑時
# 回傳 3，寫出影像後才因內容否決時回傳 4。`|| true` 會恰好丟棄那個先前一直欠缺的訊號。
#
# 執行不會因此中止。截圖是證據而非斷言，一個已完成繪製並寫下診斷的視窗仍然值得閱讀。但失敗會在
# 它發生之處被公告，並計入摘要——如此一來，一次沒有產出任何圖片的執行，就不會看起來像有產出。
#
# 本函式為何要去找那個檔案。
#
# 它原本不找，而那正是它如今存在所要防止的錯誤。除 3 以外的每一個非零結束碼，訊息都寫成
# 「screenshot.zsh exited %d and produced no image」——那是從結束碼推論出來的，從未看過磁碟一眼。
#
# 2026-09-07 實測：一次 WSLg sweep 記下 47 列「screenshot.zsh produced no image」。影像是存在的。
# 那天寫出 56 張 PNG，沒有任何一張是零位元組，介於 1796 至 3505 位元組。其中一張旁邊的 wincap
# 日誌寫著上方那三行。
#
# 照片拍到了，而它 96.2% 是黑的。自 todo #77 讓 wincap 改以非黑像素的**比例**判定內容（而非只看
# 有沒有任何一個像素活下來）之後，一次機械上成功、回來卻幾乎全黑的擷取會以非零結束，而舊訊息說的
# 正好與實際發生的事相反。
#
# 這兩種狀態需要的是相反的回應。「沒有影像」指向擷取工具、視窗 handle、主機；「影像因內容被否決」
# 指向繪製：同一支 app、同一個 788x649 視窗，數分鐘後改以軟體繪製，量到 92.1% 非黑。在該次事件中，
# 錯誤的訊息掩蓋了一個主機層級的 EGL 故障，好幾個調查步驟花在追問 screenshot.zsh 是不是壞了，而
# 56 張 PNG 就躺在磁碟上反駁著它自己的回報。
screenshot_failures=0
capture() {
    # errexit and pipefail are off for this function alone. The screenshot is
    # deliberately allowed to fail, and the pipeline below exists so that
    # screenshot.zsh's output can be BOTH streamed to the terminal as it happens
    # -- `ensure_wincap` can run swiftc, which is not something to hide behind a
    # silent buffer -- and read back afterwards. Under `set -e -o pipefail` a
    # non-zero screenshot.zsh would end the run at the pipe. `localoptions`
    # restores both options when the function returns.
    # 僅在本函式內關閉 errexit 與 pipefail。截圖本來就允許失敗，而下方的 pipeline 存在的理由是：
    # screenshot.zsh 的輸出既要在發生當下就串流到終端（`ensure_wincap` 可能會跑 swiftc，那不該被
    # 藏在一個安靜的緩衝區後面），事後又要能被讀回來。在 `set -e -o pipefail` 之下，非零的
    # screenshot.zsh 會在管線處直接結束整個執行。`localoptions` 會在函式返回時把兩個選項還原。
    setopt localoptions noerrexit nopipefail

    local rc out tmp reject_line rejected_png fraction
    tmp="$(mktemp)"
    zsh "$script_dir/screenshot.zsh" "$@" 2>&1 | tee "$tmp"
    # `pipestatus[1]`, not `$?`: `$?` here is tee's, and tee succeeds whatever
    # screenshot.zsh did.
    # 用 `pipestatus[1]` 而非 `$?`：此處的 `$?` 是 tee 的，而無論 screenshot.zsh 發生什麼事，
    # tee 都會成功。
    rc="${pipestatus[1]}"
    out="$(cat "$tmp" 2>/dev/null || true)"
    rm -f "$tmp"
    # Not `status`. That is one of zsh's special parameters -- a read-only alias
    # for $? -- so `local status=$?` aborts the run with
    # "capture:2: read-only variable: status". The same family as `path`,
    # `options` and `watch`; this file's own notes warn about it, and the warning
    # was still not enough to avoid it.
    # 不用 `status`。它是 zsh 的特殊參數之一——`$?` 的唯讀別名——因此 `local status=$?` 會以
    # 「capture:2: read-only variable: status」中止執行。與 `path`、`options`、`watch` 同一族；
    # 本檔自身的註解已提出警告，而該警告仍不足以讓人避開它。
    [ "$rc" -eq 0 ] && return 0

    screenshot_failures=$(( screenshot_failures + 1 ))

    # The fraction is taken from what wincap already measured, not recomputed
    # here. wincap counts the non-black pixels itself and prints the count into
    # the `*-wincap.log` it leaves beside the capture; screenshot.zsh echoes that
    # log to stderr with a `wincap: ` prefix and repeats the fraction on its own
    # rejection line. Recomputing it would need an image decoder this script does
    # not have, and would risk disagreeing with the number in the log.
    #
    # `tail -1` on both: a run takes an early capture and a final one, so the
    # last occurrence is the one this message is about.
    #
    # 比例取自 wincap 已經量好的數值，不在此重新計算。wincap 自行計數非黑像素，並把結果印進它留在
    # 擷取檔旁邊的 `*-wincap.log`；screenshot.zsh 會以 `wincap: ` 前綴把該日誌回顯到 stderr，並在
    # 自己的否決訊息行上再寫一次比例。重新計算需要本腳本沒有的影像解碼器，而且有與日誌裡的數字互相
    # 矛盾的風險。
    #
    # 兩者都取 `tail -1`：一次執行會拍早期與最終兩張，最後出現的那一筆才是本訊息所指的那一次。
    reject_line="$(printf '%s\n' "$out" | grep 'rejected on content' | tail -1 || true)"
    fraction="$(printf '%s\n' "$out" \
        | grep -oE 'non-black: [0-9]+/[0-9]+ \([0-9.]+%\)' | tail -1 || true)"
    rejected_png=""
    if [ -n "$reject_line" ]; then
        rejected_png="${reject_line##*-- kept at }"
    fi

    # The disk is asked, not the exit code. That is the whole point: an exit code
    # says a step failed, a file says whether a picture exists.
    # 這裡問的是磁碟，不是結束碼。這正是重點所在：結束碼說的是某個步驟失敗了，檔案說的才是究竟有
    # 沒有一張圖。
    if [ -n "$rejected_png" ] && [ -f "$rejected_png" ]; then
        printf '!! screenshot rejected on content: an image WAS written -- %s\n' \
            "${fraction:-non-black: unmeasured}" >&2
        printf '!! screenshot rejected on content: the file is %s\n' "$rejected_png" >&2
        printf '!! Read this as a rendering fault, not a capture fault: the capture tool ran,\n' >&2
        printf '!! the window was found and the picture was taken. The fraction above is the\n' >&2
        printf '!! measurement that names the cause -- a healthy capture of the same window is\n' >&2
        printf '!! upwards of 90%% non-black.\n' >&2
        printf '!! 請把這讀成繪製故障，而非擷取故障：擷取工具跑過了、視窗找到了、照片也拍了。\n' >&2
        printf '!! 上方的比例就是指認成因的量測值——同一個視窗健康時的擷取在 90%% 非黑以上。\n' >&2
        return 0
    fi

    case "$rc" in
        3) printf '!! no screenshot: this host has no capture path (screenshot.zsh exited 3)\n' >&2 ;;
        4) printf '!! no screenshot: screenshot.zsh exited 4, so it wrote an image and rejected it,\n' >&2
           printf '!! but %s is not on disk now -- something removed it between the two.\n' \
               "${rejected_png:-the file it named}" >&2 ;;
        *) printf '!! no screenshot: screenshot.zsh exited %d and no image file was written\n' "$rc" >&2 ;;
    esac
    return 0
}

showtime() {
    local label="$1"

    if [ "$showtime_seconds" -le 0 ]; then
        return 0
    fi

    printf '==> Showtime: keeping %s open for %ss after render\n' "$label" "$showtime_seconds"
    printf '    You can inspect or interact with the window now; final screenshot follows.\n'
    sleep "$showtime_seconds"
}

kill_existing() {
    printf '==> Closing any running %s\n' "$app"

    if [ "$target" = "macos" ]; then
        # Both names. A bundled run is a process called debugTarget whatever Pn
        # it is -- that is the bundle's identity, not the app's -- so `pkill -x
        # $app` alone would leave a previous run alive and the next one would
        # screenshot the wrong window.
        # 兩個名稱都要。經 bundle 的執行，無論是哪一支 Pn，行程名都是 debugTarget——那是 bundle
        # 的身分而非 app 的——因此僅用 `pkill -x $app` 會讓前一次執行存活下來，而下一次執行就會
        # 截到錯的視窗。
        pkill -TERM -x "$app" 2>/dev/null || true
        pkill -TERM -x debugTarget 2>/dev/null || true
        printf '    macOS: clear\n'
        return 0
    fi

    # Every backend variant, not just the one about to run. A leftover build of
    # the OTHER backend is the dangerous one: it holds a window with the same
    # title, and `screenshot.zsh -w` matches by title, so the capture comes back
    # looking perfectly good while photographing the wrong process. That
    # happened on 2026-09-02 -- a WSLg P43 was still up and the "WinUI" capture
    # was really the GTK one, identical down to the title bar.
    #
    # 清掉每一個 backend 變體，而不只是即將執行的那一個。殘留的「另一個 backend」才是危險的：
    # 它持有一個標題相同的視窗，而 `screenshot.zsh -w` 是依標題比對的，於是截圖看起來完全正常，
    # 拍到的卻是錯的 process。2026-09-02 就發生過——一個 WSLg 的 P43 還開著，那張「WinUI」截圖
    # 其實是 GTK 的，連標題列都一模一樣。
    local still_running=()
    for image in "$app.exe" "$app-WinUI.exe" "$app-gtk4.exe"; do
        if MSYS2_ARG_CONV_EXCL='*' tasklist.exe /NH /FI "IMAGENAME eq $image" 2>/dev/null \
            | grep -qi "$image"; then
            MSYS2_ARG_CONV_EXCL='*' taskkill.exe /F /IM "$image" >/dev/null 2>&1 || true
        fi
        if MSYS2_ARG_CONV_EXCL='*' tasklist.exe /NH /FI "IMAGENAME eq $image" 2>/dev/null \
            | grep -qi "$image"; then
            still_running+=("$image")
        fi
    done
    if [ ${#still_running[@]} -gt 0 ]; then
        printf '    WARNING: still running on Windows: %s\n' "${still_running[*]}"
    else
        printf '    Windows: clear\n'
    fi

    MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu -- zsh -lc \
        "pkill -x $app 2>/dev/null; sleep 1; pgrep -ax $app || printf '    WSLg: clear\n'" \
        2>/dev/null || true
}

# Reads $events_dir, and takes no argument.
#
# It used to be passed the output directory, because that is where the app was
# launched from and therefore where it wrote. Since SCUI_DEBUG_EVENTS_DIR the two
# are different directories, and a marker wait pointed at the wrong one does not
# fail -- it times out, which reads as an app that never rendered.
# 讀取 $events_dir，且不接受引數。
#
# 它原本會收到 output 目錄，因為那既是 app 的啟動處、也就是它的寫入處。自從有了
# SCUI_DEBUG_EVENTS_DIR，兩者已是不同的目錄；而指錯目錄的等待不會報錯——它會逾時，讀起來就像
# 這支 app 從未完成繪製。
wait_for_marker_windows() {
    local waited=0

    if [ -z "$marker" ]; then
        printf '==> No render marker configured; using screenshot timing\n'
        return 0
    fi

    printf '==> Waiting for "%s"' "$marker"
    while [ "$waited" -lt "$timeout_seconds" ]; do
        if [ -f "$events_dir/$log_name" ] \
            && grep -q "$marker" "$events_dir/$log_name" 2>/dev/null; then
            printf ' -- rendered after %ss\n' "$waited"
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
        printf '.'
    done

    printf '\n==> Timed out after %ss\n' "$timeout_seconds"
    return 1
}

wait_for_marker_wsl() {
    local waited=0

    if [ -z "$marker" ]; then
        printf '==> No render marker configured; using screenshot timing\n'
        return 0
    fi

    printf '==> Waiting for "%s"' "$marker"
    while [ "$waited" -lt "$timeout_seconds" ]; do
        if MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu -- zsh -lc \
            "grep -q '$marker' $wsl_events_dir/$log_name 2>/dev/null"; then
            printf ' -- rendered after %ss\n' "$waited"
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
        printf '.'
    done

    printf '\n==> Timed out after %ss\n' "$timeout_seconds"
    return 1
}

print_summary_windows() {
    local out="$script_dir/output"

    printf '\n==> Windows %s diagnostics\n' "$app"
    # The app's own log from $events_dir; $extra_log is still written by the
    # library into the output directory, so the two paths are not the same.
    # app 自己的 log 取自 $events_dir；$extra_log 仍由函式庫寫入 output 目錄，兩者路徑不同。
    grep -hE "$summary_pattern" "$events_dir/$log_name" ${extra_log:+"$out/$extra_log"} 2>/dev/null \
        | sed "s/^$app [0-9-]* [0-9:]* +0000 //" | sort -u || true
    print_actionfile_report "$out/$actionfile_log"
}

# What the backend said about the replay, if one was asked for.
#
# Printed unconditionally when --actionfile was passed, including when the file
# produced no line at all -- silence there means the app died before the replay
# or the backend never saw the flag, and both look identical to a replay that
# ran and did nothing.
#
# 傳入 --actionfile 時一律印出 backend 對重放的說明，即使該檔案完全沒有產生任何一行——那種沉默
# 代表 app 在重放之前就結束了，或 backend 根本沒看到該旗標，而這兩者與「重放執行了卻毫無作用」
# 在外觀上完全相同。
print_actionfile_report() {
    # `log_path`, not `path`. In zsh `path` is the array tied to `PATH`, so
    # `local path="$1"` -- which is what this line said until 2026-08-27 --
    # replaced the whole of PATH with the name of a log file for the length of
    # this function. Measured: 49 entries outside, one inside, and `command -v`
    # answering NONE for `grep`, `sed` and `zsh` alike. Hashing does not save it
    # either; a grep already run and hashed by print_summary_windows was still
    # not found here.
    #
    # The comment below is kept as it was written, wrong, because what it looks
    # like matters: it is a correct observation ("sed was not on PATH in this
    # context") with the cause missing, and the workaround it justifies was
    # never the fix. With PATH gone, `grep` was not found either, `report` was
    # always empty, and this function printed "no report" for every run it has
    # ever summarised -- including the ones whose replay had worked.
    #
    # What that invalidates is this function's own output, and nothing further:
    # an absent `-actionfile:` line in a test.zsh summary never meant the log
    # was silent. It does not reach testapp/sweep-test/sweep_drive.zsh, which
    # greps those same logs itself, contains no `path` assignment anywhere, and
    # so ran with an intact PATH. That sweep reported `replay ok` for 16 of 17
    # gtk4 apps and no line for every WinUI one -- 16 successes are not
    # something an inert grep can produce, which makes it a controlled
    # comparison rather than an assumption. A retraction that reaches past its
    # evidence costs as much as one that stops short of it.
    #
    # 這裡是 `log_path` 而非 `path`。在 zsh 中 `path` 是與 `PATH` 綁定的陣列，因此
    # `local path="$1"`——直到 2026-08-27 為止這一行都是這樣寫的——會在本函式執行期間，把整個 PATH
    # 換成一個 log 檔的檔名。實測：函式外 49 個項目，函式內剩 1 個，而 `command -v` 對 `grep`、
    # `sed`、`zsh` 一律回答 NONE。命令雜湊也救不了：print_summary_windows 先前已執行並雜湊過的
    # grep，在此處依然找不到。
    #
    # 下方那段註解保留原樣、連同它的錯誤一起，因為「它長什麼樣子」本身很重要：那是一個正確的觀察
    # （「sed 不在此情境的 PATH 上」）卻缺了成因，而它所辯護的替代寫法從來就不是修正。PATH 既然不見了，
    # `grep` 同樣找不到，`report` 永遠是空的，於是本函式對它所摘要過的每一次執行都印出「no report」
    # ——包括那些重放其實成功的執行。
    #
    # 這件事作廢的是**本函式自身的輸出**，僅此而已：test.zsh 摘要中「沒有 `-actionfile:` 這行」，
    # 從來就不代表 log 是空的。它波及不到 testapp/sweep-test/sweep_drive.zsh——那支腳本自己 grep
    # 同一批 log，全檔沒有任何對 `path` 的指派，因此是在 PATH 完好的情況下執行的。該次 sweep 對 17 支
    # gtk4 app 中的 16 支回報 `replay ok`，對每一支 WinUI app 回報 no line——一個從未真正執行的 grep
    # 產不出 16 次成功，因此那是一組對照比較，而非假設。一份超出其證據範圍的撤回，代價與一份不足的
    # 撤回相同。
    local log_path="$1"
    if [ -z "$action_file" ]; then
        return 0
    fi
    printf '==> Action file report\n'

    # Captured and split with zsh's own `${(f)…}` rather than piped through
    # sed. Two reasons, both measured here: `sed` was not on PATH in this
    # context and the function died with `command not found`, and `if grep |
    # sed` tests *sed's* status -- so a grep that found nothing still reported
    # success and printed nothing at all.
    # 以 zsh 自身的 `${(f)…}` 擷取並分行，而非透過管線交給 sed。兩個理由都是在此處實測到的：
    # `sed` 不在此情境的 PATH 上，該函式因而以 `command not found` 中止；而 `if grep | sed`
    # 判斷的是 **sed** 的結束狀態——因此即使 grep 一無所獲，仍會回報成功且什麼都不印。
    # `|| true` because a grep that matches nothing exits 1, and under `set -e`
    # a failed command substitution in an assignment ends the script. The "no
    # report" branch below could not be reached without it -- and that branch is
    # the normal outcome for a WinUI build, whose stdout and stderr are closed
    # before anything can be piped from them. Not noticed earlier only because
    # the line above it was failing first, for the PATH reason described above.
    # 加上 `|| true`：沒有命中的 grep 會以 1 結束，而在 `set -e` 下，指派中失敗的命令替換會終止整個
    # 腳本。少了它，下方的「no report」分支永遠到不了——而那個分支正是 WinUI 建置的正常結果，因為它的
    # stdout 與 stderr 在任何東西能從中導出之前就已被關閉。先前沒發現，只是因為上一行更早就先失敗了，
    # 原因見上方關於 PATH 的說明。
    local report
    local report_source="$log_path"
    report="$(grep -a actionfile "$log_path" 2>/dev/null || true)"
    if [ -z "$report" ]; then
        local replay_log="${log_path:h}/actionfile-replay.log"
        report="$(grep -a actionfile "$replay_log" 2>/dev/null || true)"
        report_source="$replay_log"
    fi
    if [ -n "$report" ]; then
        printf '    %s\n' ${(f)report}
    else
        printf '    no report -- the app exited before replaying, or never saw the flag\n'
    fi

    # What those lines say about the desktop, rather than about this app.
    # `SendInput exited with status 5` there is Windows refusing our input
    # outright -- locked, or an elevated window in front -- and every capture
    # this run took is then evidence about nothing. ui-lock.zsh keeps the
    # observation, so the next acquire waits instead of repeating this run
    # blind. A detector nobody calls is worth as little as a mutex nobody
    # takes, which is why the call is here and not left to the reader.
    #
    # Its status is deliberately dropped: this script's exit code means "the run
    # happened", and a verdict on the desktop is a different claim. `check`
    # states its own on the lines it prints.
    #
    # 那些訊息對「桌面」而非對「這支 app」說了什麼。其中的 `SendInput exited with status 5` 代表
    # Windows 直接拒絕了我方輸入——鎖定中，或前方站著提權視窗——此時本次執行所取得的每一張截圖都
    # 不構成任何證據。ui-lock.zsh 會保留這項觀察，好讓下一次 acquire 選擇等待，而不是盲目重演這次
    # 執行。沒有人呼叫的偵測器，與沒有人取用的互斥鎖一樣不值錢，因此這個呼叫寫在這裡，而不是留給
    # 讀者自行處理。
    #
    # 刻意捨棄它的結束狀態：本腳本的 exit code 表示「這次執行發生了」，而對桌面的判決是另一回事。
    # `check` 會用它自己印出的訊息說明結論。
    zsh "$ui_lock_script" check "$report_source" || true
}

print_summary_wsl() {
    printf '\n==> WSLg %s diagnostics\n' "$app"
    # The app's log by absolute path, the extra log relative to output/ -- the cd
    # still serves the second one, which the library writes there.
    # app 的 log 以絕對路徑指定，extra log 則相對於 output/——那個 cd 仍為後者服務，因為它是由
    # 函式庫寫在該處的。
    MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu -- zsh -lc \
        "cd ~/proj/swift-cross-ui/testapp/output && grep -hE '$summary_pattern' $wsl_events_dir/$log_name $extra_log 2>/dev/null | sed 's/^$app [0-9-]* [0-9:]* +0000 //' | sort -u" || true
    # Read through WSL: the app ran from the rsync'd Linux copy, so its stderr
    # landed in the Linux output directory, not the Windows one.
    # 透過 WSL 讀取：app 是從 rsync 過去的 Linux 副本啟動的，其 stderr 落在 Linux 端的 output
    # 目錄，而非 Windows 端。
    if [ -n "$action_file" ]; then
        printf '==> Action file report\n'
        local report
        report="$(MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu -- zsh -lc \
            "grep -a actionfile ~/proj/swift-cross-ui/testapp/output/$actionfile_log 2>/dev/null" \
            || true)"
        if [ -n "$report" ]; then
            printf '%s\n' "$report" | sed 's/^/    /'
        else
            printf '    no report -- the app exited before replaying, or never saw the flag\n'
        fi
    fi
}

wsl_renderer_preflight() {
    local egl_output egl_renderer expected matched=0
    egl_output="$(MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu -- \
        env ${(z)render_env} timeout 10 eglinfo -p wayland -B 2>&1 || true)"
    egl_renderer="$(printf '%s\n' "$egl_output" \
        | sed -n 's/^OpenGL core profile renderer: //p' | head -1)"

    printf '==> GtkBackend renderer mode: %s\n' "$render_mode"
    printf '    Wayland EGL: %s\n' "${egl_renderer:-unavailable}"
    case "$render_mode" in
        hw) expected='D3D12'; [[ "$egl_renderer" == D3D12\ * ]] && matched=1 ;;
        sw) expected='llvmpipe'; [[ "$egl_renderer" == llvmpipe\ * ]] && matched=1 ;;
        *) printf 'Unknown render mode: %s\n' "$render_mode" >&2; return 64 ;;
    esac
    if [ "$matched" -ne 1 ]; then
        printf 'Renderer preflight failed: -render %s expected %s, got %s\n' \
            "$render_mode" "$expected" "${egl_renderer:-nothing}" >&2
        return 1
    fi
}

print_renderer_wsl() {
    local stderr_file="$1"
    local report
    report="$(MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu -- \
        cat "/home/lowei/proj/swift-cross-ui/testapp/output/$stderr_file" 2>/dev/null \
        | tr -d '\r' \
        | grep -iE 'Not using|renderer is|Failed to realize' \
        | head -10 || true)"
    printf '\n==> GtkBackend GSK renderer diagnostics (%s)\n' "$render_mode"
    if [ -n "$report" ]; then
        printf '%s\n' "$report" | sed 's/^/    /'
    else
        printf '    no renderer rejection lines; EGL preflight above is authoritative\n'
    fi
}

run_windows() {
    local out="$script_dir/output"
    local label="${app:l}-windows"

    # GTK's bin directory on PATH for the launch, not only for the build.
    #
    # compile.zsh exports it, but that only lasts for the build shell -- so an
    # app built with -gtk4 and launched from here died before main with
    # `api-ms-win-crt-locale-l1-1-0.dll: cannot open shared object file`. The
    # missing library is the UCRT rather than GTK, which sends the reader
    # looking for a broken Visual C++ install; what is actually missing is the
    # whole directory that would have satisfied both.
    #
    # This was invisible until an action file forced stderr to be kept. Every
    # earlier Windows run sent it to /dev/null, so a -gtk4 build that never
    # started looked exactly like one that started and rendered nothing.
    #
    # 讓 GTK 的 bin 目錄在「啟動」時也位於 PATH 上，而不只是在「建置」時。
    #
    # compile.zsh 有 export 它，但那只在建置的 shell 中有效——因此以 -gtk4 建置、再由此處啟動的
    # app，會在進入 main 之前就以
    # `api-ms-win-crt-locale-l1-1-0.dll: cannot open shared object file` 死掉。缺少的那個函式庫是
    # UCRT 而非 GTK，這會把讀者引向「Visual C++ 安裝損壞」的方向；但真正缺少的，是那個原本能同時
    # 滿足兩者的整個目錄。
    #
    # 在動作檔迫使 stderr 被保留之前，此問題完全不可見。先前每一次 Windows 執行都把 stderr 送進
    # /dev/null，因此「一個從未啟動的 -gtk4 建置」與「一個啟動了卻什麼都沒繪製的建置」看起來
    # 一模一樣。
    # Converted to POSIX form before it goes anywhere near PATH. `:` is the
    # separator here, so `C:/gtk4/bin` is not one entry -- it is `C` and
    # `/gtk4/bin`, neither of which exists, and the entry that was supposed to
    # fix the launch instead adds two broken ones. The first attempt at this fix
    # did exactly that and changed nothing.
    # 在放進 PATH 之前先轉為 POSIX 形式。此處的 `:` 是分隔符，因此 `C:/gtk4/bin` 並非單一項目——
    # 它是 `C` 與 `/gtk4/bin` 兩項，兩者都不存在；原本要修好啟動問題的那一項，反而新增了兩個壞掉的
    # 項目。本修正的第一次嘗試正是如此，且毫無作用。
    local gtk_prefix="${GTK4_PREFIX:-C:/gtk4}"
    local gtk_bin
    gtk_bin="$(posix_path "$gtk_prefix/bin")"
    if [ -d "$gtk_bin" ]; then
        export PATH="$gtk_bin:$PATH"
    fi

    if [ "$do_build" -eq 1 ]; then
        printf '==> Building %s for Windows\n' "$app"
        # SCUI_DEBUG=1 whenever an action file is being replayed, because
        # without it the flag does not exist in the binary. A build that omits
        # it produces an executable that ignores -actionfile entirely -- which
        # is the whole point of DebugFeatures, and which this script then
        # reported as "the app never saw the flag". Correct, and useless.
        # 只要要重放動作檔就帶上 SCUI_DEBUG=1，因為少了它，該旗標根本不存在於執行檔中。省略它的
        # 建置會產生一個完全忽略 -actionfile 的執行檔——那正是 DebugFeatures 的目的，而本腳本當時
        # 把它回報為「app 從未看到該旗標」。正確，但毫無用處。
        SCUI_DEBUG="${action_file:+1}" \
            zsh "$script_dir/compile.zsh" "$app" | grep -E 'error:|Build of product' || true
    fi

    mkdir -p "$out"
    # Created before the launch, not after. The app writes through `try?`, so a
    # missing directory produces no file, no error and no log line.
    # 在啟動之前建立，而非之後。app 以 `try?` 寫入，因此目錄不存在時不會有檔案、不會有錯誤，
    # 也不會有任何一行 log。
    mkdir -p "$events_dir"
    : > "$events_dir/$log_name"
    # `if`, not `[ -n ... ] && ...`: under `set -e` a false test as the last
    # command in the list aborts the script.
    # 用 `if` 而非 `[ -n ... ] && ...`：在 `set -e` 下，測試為假會使整個腳本中止。
    if [ -n "$extra_log" ]; then
        : > "$out/$extra_log"
    fi
    if [ -n "$action_file" ]; then
        : > "$out/actionfile-replay.log"
    fi
    local args="$app_args"
    if [ -n "$action_file" ]; then
        # cygpath -m, because the app is a Windows binary and cannot open an
        # MSYS path such as /c/Users/... . Nothing reports this: Foundation
        # returns nil, the backend logs that the file could not be read, and
        # the window sits there looking like the replay did nothing.
        # 使用 cygpath -m：該 app 是 Windows 原生執行檔，無法開啟 /c/Users/... 這類 MSYS 路徑。
        # 沒有任何機制會回報此事：Foundation 回傳 nil，backend 記錄檔案無法讀取，而視窗就這樣停在
        # 那裡，看起來就像重放什麼都沒做。
        args="$args -actionfile $(windows_path_mixed "$action_file")"
        printf '==> Action file: %s\n' "${action_file:t}"
    fi

    printf '==> Launching %s.exe\n' "$app"
    # stderr kept, not discarded, when a file is being replayed. The backend
    # reports there whether the replay ran, and a failed replay leaves a window
    # that looks untouched -- indistinguishable from the app ignoring the input,
    # and the wrong thing to go looking for. Measured: the first run through
    # this script dropped the line and the failure read as a product defect.
    # 重放動作檔時保留 stderr 而不丟棄。backend 在該處回報重放是否執行；失敗的重放會留下一個看似
    # 未被觸碰的視窗，與「app 忽略了輸入」無法區分，而那是錯誤的追查方向。實測：本腳本的第一次
    # 執行丟掉了這行訊息，於是該失敗看起來像是產品缺陷。
    # Which build to run, when the same app can exist for both backends.
    #
    # An ambiguity is refused rather than guessed. Picking one silently is the
    # failure this suffix exists to prevent: the wrong backend runs, its window
    # carries the same title, and every capture and every number afterwards
    # describes something nobody asked about. `TEST_BACKEND=gtk4` or
    # `TEST_BACKEND=WinUI` answers it; a per-app test_Pn.zsh can export it.
    #
    # The unsuffixed name is still accepted, alone, so a checkout built before
    # the suffix existed keeps working -- but it loses to a suffixed build,
    # because a stale unsuffixed file is exactly what would otherwise be run.
    #
    # 當同一個 app 兩個 backend 都可能存在時，要執行哪一個。
    #
    # 遇到歧義時拒絕，而不是猜。默默選一個正是這個後綴要防的失敗：錯的 backend 被執行，它的視窗
    # 帶著相同的標題，而其後的每一張截圖與每一個數字，描述的都是沒人問過的東西。
    # `TEST_BACKEND=gtk4` 或 `TEST_BACKEND=WinUI` 可以回答它；各 app 的 test_Pn.zsh 也能 export。
    #
    # 無後綴的名稱在「僅它存在」時仍被接受，使後綴出現之前建置的 checkout 仍可運作——但它會輸給
    # 有後綴的建置，因為一個過期的無後綴檔案，正是否則會被執行的那個東西。
    local candidates=()
    if [ -n "${TEST_BACKEND:-}" ]; then
        if [ -f "$out/$app-$TEST_BACKEND.exe" ]; then
            candidates=("$app-$TEST_BACKEND.exe")
        else
            printf '!! TEST_BACKEND=%s but %s/%s-%s.exe does not exist\n' \
                "$TEST_BACKEND" "$out" "$app" "$TEST_BACKEND" >&2
            exit 1
        fi
    else
        for suffix in -WinUI -gtk4; do
            [ -f "$out/$app$suffix.exe" ] && candidates+=("$app$suffix.exe")
        done
        if [ ${#candidates[@]} -eq 0 ] && [ -f "$out/$app.exe" ]; then
            candidates=("$app.exe")
        fi
    fi
    if [ ${#candidates[@]} -eq 0 ]; then
        printf '!! no build of %s in %s -- run compile.zsh first\n' "$app" "$out" >&2
        exit 1
    fi
    if [ ${#candidates[@]} -gt 1 ]; then
        printf '!! %s exists for more than one backend: %s\n' "$app" "${candidates[*]}" >&2
        printf '!! set TEST_BACKEND=WinUI or TEST_BACKEND=gtk4; refusing to guess\n' >&2
        exit 1
    fi
    win_exe="${candidates[1]}"
    printf '==> Running %s\n' "$win_exe"

    # Mixed Windows form for SCUI_DEBUG_EVENTS_DIR, for the same reason
    # `-actionfile` gets `cygpath -m` a few lines above: this is a native
    # Windows binary and Foundation cannot open an MSYS path such as
    # /c/Users/... . It would fail through `try?` and leave no log at all.
    # SCUI_DEBUG_EVENTS_DIR 採 Windows 混合式路徑，理由與上方 `-actionfile` 使用 `cygpath -m`
    # 相同：這是原生 Windows 執行檔，Foundation 打不開 /c/Users/... 這類 MSYS 路徑，寫入會被
    # `try?` 吞掉，最後連一個 log 檔都不會有。
    local events_dir_win
    events_dir_win="$(windows_path_mixed "$events_dir")"

    if [ -n "$action_file" ]; then
        ( cd "$out" && env SCUI_DEBUG_EVENTS_DIR="$events_dir_win" ${(z)app_env} \
            "./$win_exe" ${(z)args} >/dev/null 2>"$actionfile_log" & )
    else
        ( cd "$out" && env SCUI_DEBUG_EVENTS_DIR="$events_dir_win" ${(z)app_env} \
            "./$win_exe" ${(z)args} >/dev/null 2>&1 & )
    fi

    capture -d 1 -w "$title" "$label-1s"
    if wait_for_marker_windows; then
        showtime "Windows $app"
        capture -d 1 -w "$title" "$label-final"
    else
        capture -d 0 -w "$title" "$label-timeout"
    fi

    if MSYS2_ARG_CONV_EXCL='*' taskkill.exe /F /IM "$win_exe" 2>&1 | grep -q SUCCESS; then
        printf '==> Closed %s\n' "$win_exe"
    else
        printf '==> WARNING: %s may still be running; check with tasklist\n' "$win_exe"
    fi

    print_summary_windows
}

run_wsl() {
    local label="${app:l}-wslg"

    wsl_renderer_preflight

    if [ "$do_build" -eq 1 ]; then
        printf '==> Syncing sources to WSL\n'
        zsh "$script_dir/rsync_WSL.zsh" >/dev/null
        printf '==> Building %s for WSLg\n' "$app"
        # See the Windows branch: without SCUI_DEBUG=1 the -actionfile flag is
        # not compiled into the binary at all.
        # 見 Windows 分支：少了 SCUI_DEBUG=1，-actionfile 旗標根本不會被編入執行檔。
        MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu --cd /home/lowei/proj/swift-cross-ui -- \
            zsh -lc "SCUI_DEBUG='${action_file:+1}' zsh testapp/compile.zsh $app" 2>&1 \
            | grep -E 'error:|Build of product' || true
    fi

    # The event log is created on the LINUX side, in the Linux copy of the repo.
    # `$wsl_events_dir` is expanded by this shell before the string is handed to
    # `wsl.exe`, so nothing with a `$` in it crosses the boundary -- the trap
    # documented in ~/.claude/CLAUDE.md, where `$var` is eaten even inside single
    # quotes. `MSYS2_ARG_CONV_EXCL='*'` keeps MSYS from rewriting the POSIX path
    # on the way out, as on every other wsl.exe call in this file.
    #
    # The renderer and extra logs stay in output/: they are shell redirections and
    # library output, not the app's own event log, so only one of the three moves.
    #
    # 事件 log 建立在 **Linux 側**、位於 repo 的 Linux 副本中。`$wsl_events_dir` 在字串交給
    # `wsl.exe` 之前就由本 shell 展開，因此沒有任何帶 `$` 的東西跨越邊界——那正是
    # ~/.claude/CLAUDE.md 所記載的陷阱：`$var` 即使包在單引號裡也會被吃掉。
    # `MSYS2_ARG_CONV_EXCL='*'` 則防止 MSYS 在送出時改寫該 POSIX 路徑，與本檔其他每一個
    # wsl.exe 呼叫一致。
    #
    # renderer log 與 extra log 仍留在 output/：它們是 shell 重導向與函式庫的輸出，而非 app 自身的
    # 事件 log，因此三者之中只有一個搬家。
    MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu -- zsh -lc \
        "mkdir -p $wsl_events_dir && : > $wsl_events_dir/$log_name && cd ~/proj/swift-cross-ui/testapp/output && : > $renderer_log$clear_extra_fragment"

    local args="$app_args"
    local renderer_stderr="$renderer_log"
    local redirection=">/dev/null 2>$renderer_log"
    if [ -n "$action_file" ]; then
        # Re-rooted onto the WSL copy of the repo. The file lives in the
        # Windows checkout, which WSL can reach as /mnt/c -- but the app is
        # launched from the rsync'd Linux copy, and giving it a /mnt/c path
        # would replay whichever version happened to be on the Windows side.
        # A path outside the repo is rejected rather than guessed at.
        # 重新指向 repo 的 WSL 副本。該檔案位於 Windows 端的 checkout，WSL 可透過 /mnt/c 存取
        # ——但 app 是由 rsync 過去的 Linux 副本啟動的，給它 /mnt/c 路徑等於重放「Windows 端當下
        # 恰好是哪個版本」。位於 repo 之外的路徑一律拒絕，而不做猜測。
        local relative="${action_file#$script_dir/}"
        if [ "$relative" = "$action_file" ]; then
            printf 'Action file must be inside %s: %s\n' "$script_dir" "$action_file" >&2
            exit 64
        fi
        args="$args -actionfile /home/lowei/proj/swift-cross-ui/testapp/$relative"
        # X11, not Wayland. xdotool speaks XTEST, which is an X11 extension; a
        # GTK 4 app left to its own devices under WSLg becomes a Wayland client
        # with no X window at all, and Wayland deliberately does not let one
        # client drive another. Forced here rather than left to the tester,
        # because the failure is a replay that reports it could not find the
        # app's own window -- which reads as a bug in the finding, not as the
        # session being the wrong kind.
        # 強制使用 X11 而非 Wayland。xdotool 使用的 XTEST 是 X11 擴充；在 WSLg 下放任不管的 GTK 4
        # app 會成為 Wayland client，根本沒有 X window，而 Wayland 也刻意不允許一個 client 驅動
        # 另一個。在此強制而非交由測試者設定，是因為其失敗表現為「重放回報找不到 app 自己的視窗」
        # ——那看起來像是尋找邏輯的 bug，而不像是 session 型別不對。
        app_env="GDK_BACKEND=x11 $app_env"
        # See the Windows branch: stderr carries the backend's report of whether
        # the replay ran, and discarding it makes a failed replay look like a
        # product defect.
        # 見 Windows 分支：stderr 承載 backend 對「重放是否執行」的回報，丟棄它會使失敗的重放
        # 看起來像產品缺陷。
        redirection=">/dev/null 2>$actionfile_log"
        renderer_stderr="$actionfile_log"
        printf '==> Action file: %s\n' "${action_file:t}"
    fi

    # SCUI_DEBUG_EVENTS_DIR first, as a literal Linux path. `env` takes the
    # assignments in order and the app is the last word, so adding one here needs
    # nothing else; the value contains no space and no `$`, which is what makes it
    # safe to travel inside the `-lc` string.
    # SCUI_DEBUG_EVENTS_DIR 置於最前，是一條字面的 Linux 路徑。`env` 依序取用這些指派，而 app 是
    # 最後一個詞，因此在此加一項不需要其他改動；該值不含空白也不含 `$`，這正是它能安全穿越 `-lc`
    # 字串的原因。
    local launch_env="SCUI_DEBUG_EVENTS_DIR=$wsl_events_dir $render_env $app_env"

    printf '==> Launching %s under WSLg\n' "$app"
    # Plain `$app_args`, deliberately unadorned. Unlike the Windows branch just
    # above -- which passes real argv words and so wants `(z)` -- this builds a
    # single command *string* for `zsh -lc`, and the inner shell does its own
    # parsing. Both parameter flags break that, in opposite directions:
    #
    #   (q)  escapes the spaces, so the inner shell sees one argument:
    #        P6 received `-f -autoplay --debug` whole and matched no flag.
    #   (z)  splits into separate words even inside double quotes, so `-lc`
    #        took `env ./P6 -f` as the command and quietly dropped the rest
    #        into its positional parameters. Measured: P6 logged
    #        `autoplay off` and never started playback.
    #
    # Every wrapper before P6 passed the single word `--debug`, where `(q)` is
    # a no-op -- which is why the original went unnoticed for so long, and why
    # the first attempt at a fix reproduced the same class of bug.
    # A value containing a space must be quoted inside TEST_APP_ARGS
    # (`-f "/path/with a space.webm"`); the quotes travel as literal text and
    # the inner shell honours them. Verified both ways.
    # 刻意使用未加任何旗標的 `$app_args`。與上方 Windows 分支不同——那裡傳遞的是真正
    # 的 argv 詞，因此需要 `(z)`——這裡組出的是給 `zsh -lc` 的單一命令「字串」，由內層
    # shell 自行解析。兩個參數旗標都會破壞它，且方向相反：
    #
    #   (q)  跳脫空白，內層 shell 只看到一個參數：P6 收到完整的
    #        `-f -autoplay --debug`，任何旗標都比對不到。
    #   (z)  即使在雙引號內仍會拆成多個詞，於是 `-lc` 把 `env ./P6 -f` 當成命令，
    #        其餘的靜靜落入位置參數。實測：P6 記錄 `autoplay off`，從未開始播放。
    #
    # P6 之前的每個 wrapper 都只傳單一詞 `--debug`，該情況下 `(q)` 等同無作用——這正是
    # 原本的問題長期未被發現的原因，也是第一次嘗試修正時又重現同類錯誤的原因。
    # 含空白的值必須在 TEST_APP_ARGS 內自行加引號（`-f "/path/with a space.webm"`）；
    # 引號會以字面文字傳遞，由內層 shell 解讀。兩種情況皆已驗證。
    MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu --cd /home/lowei/proj/swift-cross-ui/testapp/output -- \
        zsh -lc "env $launch_env ./$app $args $redirection" \
        >/dev/null 2>&1 &
    disown 2>/dev/null || true

    capture -d 1 -w "$title" "$label-1s"
    if wait_for_marker_wsl; then
        showtime "WSLg $app"
        capture -d 1 -w "$title" "$label-final"
    else
        capture -d 0 -w "$title" "$label-timeout"
    fi

    MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu -- zsh -lc "pkill -x '$app' 2>/dev/null" || true
    printf '==> Closed %s under WSLg\n' "$app"
    print_renderer_wsl "$renderer_stderr"
    print_summary_wsl
}

# macOS uses AppKitSynthesiser, which posts directly into the app's own event
# queue and therefore does not need System Events Accessibility permission.
# macOS 使用 AppKitSynthesiser，直接把事件送入 app 自己的 event queue，因此不需要
# System Events 的輔助使用權限。
run_macos() {
    local out="$script_dir/output"
    local label="${app:l}-macos"

    if [ "$do_build" -eq 1 ]; then
        printf '==> Building %s for macOS\n' "$app"
        SCUI_DEBUG="${action_file:+1}" \
            zsh "$script_dir/compile.zsh" "$app" | grep -E 'error:|Build complete|Build of product' || true
    fi

    mkdir -p "$out"
    # Same as the Windows branch: the directory has to exist before the launch,
    # because the app's write goes through `try?` and reports nothing.
    # 與 Windows 分支相同：該目錄必須在啟動前就存在，因為 app 的寫入經由 `try?`，什麼都不會回報。
    mkdir -p "$events_dir"
    : > "$events_dir/$log_name"
    local action_log="$out/$actionfile_log"
    : > "$action_log"
    local args=( ${(z)app_args} )
    if [ -n "$action_file" ]; then
        action_file="${action_file:A}"
        args+=( -actionfile "$action_file" )
        printf '==> Action file: %s\n' "${action_file:t}"
    fi

    # Launched from a .app, not as a bare executable.
    #
    # SwiftPM produces a Mach-O with no Info.plist, so a bare launch has no
    # bundle identifier -- measured: lsappinfo reports bundleID=[ NULL ]. Anything
    # keyed on that identity behaves differently or not at all: NSWindow frame
    # autosave (upstream #383), AppStorage and any UserDefaults suite, and the
    # app's Dock and menu-bar identity. Copying the tracked template around the
    # built executable gives it one -- measured on the same binary:
    # bundleID="dev.swiftcrossui.testapp.debugTarget".
    #
    # The identity belongs to the bundle, so the process is called debugTarget
    # whichever Pn it is. That is why the pid is kept and why kill_existing
    # sweeps both names; killing by "$app" would miss it entirely.
    #
    # 以 .app 啟動，而非裸執行檔。
    #
    # SwiftPM 產出的是沒有 Info.plist 的 Mach-O，因此裸啟動不具 bundle identifier——實測：
    # lsappinfo 回報 bundleID=[ NULL ]。任何以該身分為鍵的東西행為都會不同或根本失效：NSWindow
    # 的 frame autosave（upstream #383）、AppStorage 與任何 UserDefaults suite，以及該 app 在
    # Dock 與選單列上的身分。把已納入版本控制的 template 套在建置好的執行檔外層即可賦予它身分——
    # 同一個 binary 實測：bundleID="dev.swiftcrossui.testapp.debugTarget"。
    #
    # 該身分屬於 bundle，因此無論是哪一支 Pn，行程名都是 debugTarget。這正是要保留 pid、且
    # kill_existing 必須兩個名稱都掃的理由；只用 "$app" 去 kill 會完全落空。
    if [ ! -d "$mac_template_dir" ]; then
        printf 'Missing macOS app template: %s\n' "$mac_template_dir" >&2
        return 1
    fi
    # One bundle identifier per Pn, stamped in rather than shipped in the
    # template.
    #
    # The template's identifier is a constant, so every test app used to run as
    # `dev.swiftcrossui.testapp.debugTarget` and share one UserDefaults domain.
    # NSWindow frame autosave lives there, and AppKitBackend keys it on the root
    # view's type -- measured in that domain on 2026-09-01:
    #
    #     "NSWindow Frame TupleView1<HotReloadableView>-0" = "620 65 1076 907 ..."
    #
    # That name is shared by every app whose root view is a plain
    # `TupleView1<HotReloadableView>`, which is most of them, so a window's size
    # was decided by whichever Pn had been resized last. P28 opened at 680x448
    # launched bare and at 1076x907 launched here, same binary, same commit --
    # which is why an action file measured one way missed by hundreds of points
    # replayed the other way.
    #
    # It also means AppStorage was shared: `p0LaunchCount` sat in the same
    # domain, so P0 counted launches of every other app as its own.
    #
    # 每一支 Pn 各有一個 bundle identifier，於此處寫入，而非由 template 帶著。
    #
    # template 的 identifier 是常數，因此每一支測試 app 都以
    # `dev.swiftcrossui.testapp.debugTarget` 執行，共用同一個 UserDefaults domain。NSWindow 的
    # frame autosave 就住在那裡，而 AppKitBackend 以 root view 的型別為其命名——2026-09-01 於該
    # domain 中實測，即為上方那一行。
    #
    # 那個名稱被「root view 為單純 `TupleView1<HotReloadableView>`」的每一支 app 共用，而那是其中
    # 大多數；於是一個視窗的尺寸，是由「最後被調整過大小的那一支 Pn」決定的。P28 以裸執行檔啟動時
    # 是 680x448，在此處啟動時是 1076x907——同一個 binary、同一個 commit——這正是「以其中一種方式
    # 量出的動作檔，用另一種方式重放時會差上數百點」的原因。
    #
    # 這也意味著 AppStorage 是共用的：`p0LaunchCount` 位於同一個 domain，因此 P0 把其他每一支 app
    # 的啟動都算成了自己的。
    mkdir -p "$mac_bundle_dir"
    cp "$mac_template_dir/Info.plist" "$mac_bundle_dir/Info.plist"
    cp "$mac_template_dir/PkgInfo" "$mac_bundle_dir/PkgInfo"
    # Lowercased, because a bundle identifier is matched case-insensitively by
    # Launch Services but stored as written, and two spellings of one app would
    # be two domains.
    # 轉為小寫，因為 Launch Services 比對 bundle identifier 時不分大小寫，但儲存時照原樣保留；
    # 同一支 app 的兩種寫法會變成兩個 domain。
    local bundle_id="dev.swiftcrossui.testapp.${app:l}"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_id" \
        "$mac_bundle_dir/Info.plist" >/dev/null
    printf '    bundle identifier: %s\n' "$bundle_id"
    rm -f "$mac_bundle_executable"
    cp "$out/$app" "$mac_bundle_executable"
    chmod +x "$mac_bundle_executable"

    printf '==> Launching %s on macOS from .macApp/debugTarget.app\n' "$app"
    # A plain POSIX path here: this is a native macOS binary and there is no MSYS
    # layer to convert anything.
    # 此處直接使用 POSIX 路徑：這是原生 macOS 執行檔，沒有任何 MSYS 層需要轉換。
    ( cd "$out" && env SCUI_DEBUG_EVENTS_DIR="$events_dir" ${(z)app_env} \
        "$mac_bundle_executable" ${(q)args} >"$action_log" 2>&1 & )

    # macOS took no screenshots at all until now -- not failed ones, none. The
    # run announced "final screenshot follows" and then did not follow, because
    # screenshot.zsh had no macOS path to call. It has one now.
    # macOS 在此之前完全不曾截圖——不是失敗，而是根本沒有嘗試。執行過程會宣告
    # 「final screenshot follows」，然後並未跟上，因為 screenshot.zsh 當時沒有 macOS 路徑可供
    # 呼叫。現在它有了。
    capture -d 1 -w "$title" "$label-1s"
    if wait_for_marker_macos; then
        showtime "macOS $app"
        capture -d 1 -w "$title" "$label-final"
    else
        capture -d 0 -w "$title" "$label-timeout"
    fi

    pkill -TERM -x debugTarget 2>/dev/null || true
    pkill -TERM -x "$app" 2>/dev/null || true
    printf '==> Closed %s on macOS\n' "$app"
    print_summary_macos
}

wait_for_marker_macos() {
    local waited=0

    if [ -z "$marker" ]; then
        printf '==> No render marker configured; using launch timing\n'
        sleep 1
        return 0
    fi

    printf '==> Waiting for "%s"' "$marker"
    while [ "$waited" -lt "$timeout_seconds" ]; do
        if [ -f "$events_dir/$log_name" ] \
            && grep -q "$marker" "$events_dir/$log_name" 2>/dev/null; then
            printf ' -- rendered after %ss\n' "$waited"
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
        printf '.'
    done

    printf '\n==> Timed out after %ss\n' "$timeout_seconds"
    return 1
}

print_summary_macos() {
    local out="$script_dir/output"
    printf '\n==> macOS %s diagnostics\n' "$app"
    grep -hE "$summary_pattern" "$events_dir/$log_name" "$out/$actionfile_log" 2>/dev/null \
        | sed "s/^$app [0-9-]* [0-9:]* +0000 //" | sort -u || true
}

# Ctrl-C closes the app rather than orphaning it.
#
# The app is launched detached -- a subshell on Windows, `disown` under WSLg --
# so it outlives this script's own process group. Without this trap, Ctrl-C
# during the showtime wait killed the runner and left the window open, and the
# next run's `kill_existing` was the only thing that ever closed it. `kill_existing`
# already knows how to close it on both platforms, so the trap reuses it and
# exits with the conventional 130.
#
# Ctrl-C 會關閉該 app，而非使其成為孤兒行程。
#
# 該 app 以分離方式啟動——Windows 上是子 shell，WSLg 下是 `disown`——因此它的生命週期超出本腳本
# 自身的行程群組。若無此 trap，在 showtime 等待期間按下 Ctrl-C 會結束執行器卻留下視窗開著，而唯一
# 會關掉它的，是下一次執行的 `kill_existing`。`kill_existing` 本就知道如何在兩個平台上關閉它，因此
# 此 trap 直接沿用，並以慣例的 130 結束。
# One UI test at a time, taken here rather than left to whoever is running one.
#
# A mutex nobody calls is not a mutex. ui-lock.zsh was added so two tests could
# not screenshot each other, and then every test runner went on launching apps
# without asking for it -- so it only worked when a person or an agent
# remembered, which is the failure mode it exists to remove. Acquiring it here
# means every path through test.zsh is serialised, including the ones nobody
# thought about.
#
# It also waits while the desktop is known to be refusing synthesised input --
# locked, or with an elevated window in front -- because such a desktop makes
# input reach nothing while a window capture goes on returning the app drawn
# correctly, with no error anywhere. "Known" is the whole difficulty: the answer
# comes from a run that already tried, which is what the `check` call in
# print_actionfile_report records.
#
# SCUI_NO_UI_LOCK=1 skips it. A developer running one test on their own machine
# should not be blocked for up to 60 seconds by a lock left over from something
# they are not running, and a gate with no way past it gets deleted rather than
# fixed.
#
# 一次只跑一個 UI 測試，且由此處取得，而非交給執行測試的人自行處理。
#
# 沒有人呼叫的互斥鎖不是互斥鎖。當初加入 ui-lock.zsh 是為了讓兩個測試不會互相截圖，然而每一支
# 測試 runner 依舊照常啟動 app 而不去索取它——於是它只在人或 agent 記得時才生效，而那正是它要
# 消除的失敗模式。在此取得，代表經過 test.zsh 的每一條路徑都被序列化，包含沒人想到的那些。
#
# 它同時會在「已知桌面正在拒絕合成輸入」時等待——鎖定中，或前方站著提權視窗——因為這樣的桌面會讓
# 輸入什麼也碰不到，而視窗擷取仍持續回傳畫得正確的 app，且任何地方都不會報錯。困難之處全在「已知」
# 二字：答案來自一次已經嘗試過的執行，也就是 print_actionfile_report 中那個 `check` 呼叫所記錄的東西。
#
# SCUI_NO_UI_LOCK=1 可略過。開發者在自己機器上跑單一測試，不該被一個與他無關的殘留鎖擋上 60 秒；
# 而一個沒有繞道的閘門，最終會被刪掉而不是被修好。
ui_lock_script="$script_dir/ui-lock.zsh"
ui_lock_holder="test-${app:l}"
ui_lock_held=0

release_ui_lock() {
    [ "$ui_lock_held" -eq 1 ] || return 0
    ui_lock_held=0
    zsh "$ui_lock_script" release "$ui_lock_holder" >/dev/null 2>&1 || true
}

on_interrupt() {
    printf '\n==> Interrupted; closing %s\n' "$app"
    kill_existing
    release_ui_lock
    exit 130
}
trap on_interrupt INT

# Not for the delegated targets: `exec` replaces this process, so neither the
# release below nor an EXIT trap would ever run, and the lock would be held by
# nobody until it went stale.
# 不套用於委派的 target：`exec` 會取代本行程，因此下方的釋放與 EXIT trap 都不會執行，該鎖將由
# 「沒有人」持有，直到它過期為止。
case "$target" in
    ios|android) ;;
    *)
        if [ "${SCUI_NO_UI_LOCK:-0}" != "1" ]; then
            zsh "$ui_lock_script" acquire "$ui_lock_holder"
            ui_lock_held=1
            trap release_ui_lock EXIT
        fi
        ;;
esac

kill_existing

# iOS and Android delegate rather than reimplement. Their scripts already take a
# Pn as their first argument, so the only thing missing was a way to reach them
# through the same command and the same flag as every other platform.
#
# `exec` so the delegate's exit status is this script's, and so the trap above
# does not outlive it -- the delegate owns the app it launches and does its own
# cleanup.
#
# iOS 與 Android 採「轉呼叫」而非重新實作。那兩支腳本本來就以 Pn 作為第一個引數，因此唯一缺少的，
# 只是一條「用與其他平台相同的命令與相同的旗標」抵達它們的途徑。
#
# 使用 `exec`，讓委派對象的結束狀態即為本腳本的結束狀態，且上方的 trap 不會存活超過它——啟動的
# app 由委派對象自己擁有，也由它自己清理。
# The flags this run resolved to, in the delegate's spelling.
#
# `"$@"` was passed here before, and by this point the parse loop above has
# shifted every argument away -- so the delegate received the app name and
# nothing else. `test.zsh P14 --ios -n --showtime 5` reached test_ios.zsh as
# `test_ios.zsh P14`: the build was performed anyway and showtime fell back to
# 30. Traced with `zsh -x`; the exec line read `zsh …/test_ios.zsh P14`.
#
# Rebuilding the flags from the parsed state rather than forwarding raw
# arguments also means the two vocabularies cannot drift: whatever spelling the
# caller used, the delegate is handed the one it documents.
#
# 本次執行所解析出的旗標，以委派對象的寫法表達。
#
# 此處原本傳的是 `"$@"`，而到達這裡時，上方的解析迴圈已把每一個引數 shift 掉——因此委派對象收到
# 的只有 app 名稱，其餘什麼都沒有。`test.zsh P14 --ios -n --showtime 5` 抵達 test_ios.zsh 時是
# `test_ios.zsh P14`：建置照樣執行，showtime 也退回 30。以 `zsh -x` 追蹤確認，exec 那一行是
# `zsh …/test_ios.zsh P14`。
#
# 由解析後的狀態重建旗標、而非轉送原始引數，也使兩套詞彙不會分歧：無論呼叫端用哪種寫法，交到委派
# 對象手上的都是它自己文件所載的那一種。
delegated_args() {
    local -a args
    [ "$do_build" -eq 0 ] && args+=(--no-build)
    if [ "$showtime_seconds" -eq 0 ]; then
        args+=(--no-showtime)
    else
        args+=(--showtime "$showtime_seconds")
    fi
    [ -n "$action_file" ] && args+=(--actionfile "${action_file:A}")
    [ -n "$device_name" ] && args+=(--device "$device_name")
    printf '%s\n' "${args[@]}"
}

run_ios() {
    local -a args
    args=("${(@f)$(delegated_args)}")
    exec zsh "$script_dir/test_ios.zsh" "$app" "${args[@]}"
}

run_android() {
    local -a args
    args=("${(@f)$(delegated_args)}")
    exec zsh "$script_dir/test_android.zsh" "$app" "${args[@]}"
}

case "$target" in
    wsl) run_wsl ;;
    windows) run_windows ;;
    macos) run_macos ;;
    ios) run_ios ;;
    android) run_android ;;
    both) run_wsl; printf '\n'; run_windows ;;
    *) printf 'Unknown target: %s\n' "$target" >&2; exit 64 ;;
esac

# The counter `capture` keeps is read HERE. Until now it was written and never
# read: the comment above capture() said the failures were "counted for the
# summary", the increment was there, and nothing anywhere printed the total.
# test_ios.zsh (line 373) and test_android.zsh (line 561) both have this line;
# this file had only half of the pattern.
#
# It is a total, not a diagnosis. Which kind of failure each one was -- no image
# at all, or an image rejected on content -- is said by capture() at the moment
# it happens, with the file name and the non-black fraction. This line exists so
# that a run whose pictures did not come out cannot end looking like one whose
# pictures did, which is the same failure mode in a different place.
#
# `ios` and `android` do not reach it: run_ios and run_android use `exec`, and
# the script they hand over to prints its own count.
#
# capture 所維護的計數器在此被讀取。在此之前它只被寫入、從未被讀取：capture() 上方的註解說這些失敗
# 會「計入摘要」，遞增也確實在那裡，卻沒有任何地方印出總數。test_ios.zsh（第 373 行）與
# test_android.zsh（第 561 行）都有這一行；本檔只有這個模式的一半。
#
# 它是總數，不是診斷。每一次失敗屬於哪一種——完全沒有影像，或影像因內容被否決——由 capture() 在事發
# 當下說明，並附上檔名與非黑像素比例。這一行存在的理由是：一次沒有拍出照片的執行，不該在結束時看起來
# 像有拍出照片的執行——那是同一種失敗模式換了個位置。
#
# `ios` 與 `android` 不會走到這裡：run_ios 與 run_android 使用 `exec`，而它們交棒過去的腳本會印出
# 自己的計數。
if [ "$screenshot_failures" -gt 0 ]; then
    printf '\n!! %d screenshot(s) did not succeed; the "!!" lines above say which kind each was.\n' \
        "$screenshot_failures" >&2
fi
