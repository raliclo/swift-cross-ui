#!/usr/bin/env zsh
# Loader for one-file-per-test UI dry-runs.
#
# The entry point for every platform. iOS and Android have their own top-level
# scripts, and this reaches them too, so one command and one set of flags covers
# all of them.
#
# Examples:
#   zsh testapp/test.zsh P8                        this host's platform
#   zsh testapp/test.zsh P8 --both                 WSLg then Windows
#   zsh testapp/test.zsh P40 --wsl -render hw      D3D12/NVIDIA (default)
#   zsh testapp/test.zsh P40 --wsl -render sw      llvmpipe
#   zsh testapp/test.zsh P19 -win --actionfile     Windows only
#   zsh testapp/test.zsh P28 --macos --actionfile  macOS only
#   zsh testapp/test.zsh P14 --ios                 iOS Simulator
#   zsh testapp/test.zsh P12 --android             Android emulator
#
# The platform flag is optional. Each test declares the platform it was written
# for, and most were written on Windows; on a host that cannot drive that
# platform the run moves to one that can and says so.
#
# Ctrl-C during a run closes the app rather than leaving it open; the target
# and flags are parsed in test_support/test_common.zsh.
#
# 涵蓋所有平台的統一進入點。iOS 與 Android 各有其頂層腳本，此處同樣可抵達它們，因此一個指令、
# 一套旗標即可涵蓋全部。
#
# 平台旗標為選用。每支測試都宣告了它當初所針對的平台，而多數是在 Windows 上寫成的；在無法驅動該
# 平台的主機上，執行會轉往可行的平台並明白告知。
#
# 執行期間按下 Ctrl-C 會關閉該 app，而非留下它開著；target 與旗標在
# test_support/test_common.zsh 中解析。

set -euo pipefail

script_dir="${0:a:h}"

usage() {
    cat <<EOF_USAGE
Usage: test.zsh <Pn> [test options]

The platform flag is optional; without one, this host's platform is used.

Examples:
  zsh testapp/test.zsh P8
  zsh testapp/test.zsh P8 --both
  zsh testapp/test.zsh P40 --wsl -render hw
  zsh testapp/test.zsh P40 --wsl -render sw
  zsh testapp/test.zsh P19 -win --actionfile
  zsh testapp/test.zsh P28 --macos --actionfile
  zsh testapp/test.zsh P14 --ios
  zsh testapp/test.zsh P12 --android

Single-test scripts live in testapp/test_support/test_Pn.zsh.

-render hw|sw selects GtkBackend rendering under WSLg. The default is hw.
It has no effect on WinUI, AppKit, UIKit, or Android backends.
EOF_USAGE
}

if [ "$#" -eq 0 ]; then
    usage >&2
    exit 64
fi

test_name="$1"
shift

# Rendering mode belongs to the top-level test command even though the shared
# helper performs the WSLg launch. Remove it here, export the resolved setting,
# and pass every unrelated option onward unchanged. This also lets special
# wrappers such as P26 use the same setting before they enter test_common.
# renderer 模式屬於頂層 test 命令，實際 WSLg 啟動則由共用 helper 執行。此處先解析並移除
# 該旗標、匯出結果，再將其餘引數原樣轉送；P26 這類在進入 test_common 前就會啟動 app 的
# 特殊 wrapper 也因此能使用同一設定。
render_mode="hw"
render_explicit=0
forward_args=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        -render|--render)
            [ "$#" -ge 2 ] || { printf -- '%s requires hw or sw\n' "$1" >&2; exit 64; }
            render_mode="$2"
            render_explicit=1
            shift 2
            ;;
        -render=*|--render=*)
            render_mode="${1#*=}"
            render_explicit=1
            shift
            ;;
        *)
            forward_args+=("$1")
            shift
            ;;
    esac
done

case "$render_mode" in
    hw)
        render_env='GALLIUM_DRIVER=d3d12 MESA_D3D12_DEFAULT_ADAPTER_NAME=NVIDIA GSK_DEBUG=renderer'
        ;;
    sw)
        render_env='LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe GSK_DEBUG=renderer'
        ;;
    *)
        printf 'Invalid -render value: %s (expected hw or sw)\n' "$render_mode" >&2
        exit 64
        ;;
esac
export TEST_RENDER_MODE="$render_mode"
export TEST_RENDER_ENV="$render_env"
export TEST_RENDER_EXPLICIT="$render_explicit"

case "$test_name" in
    p*) test_name="${test_name:u}" ;;
esac

# Any P followed by digits. The list used to be spelled out as P0..P17 and so
# rejected P18, P19 and P20 although their scripts existed -- the wrapper has to
# be edited every time an app is added, and the one time it was not, three
# working tests were unreachable through the loader. The missing-script check
# below already reports an app that has no test.
# 接受任何「P + 數字」。此處原本逐一列出 P0..P17，因而在 P18、P19、P20 的腳本確實存在的情況下
# 仍將其拒絕——每新增一支 app 就得改一次這個 wrapper，而只要有一次沒改，就有三支可用的測試無法
# 透過 loader 觸及。下方既有的「腳本不存在」檢查已能回報沒有測試的 app。
#
# A trailing variant is accepted too, for the sake of P6-v2. Its wrapper
# documents `zsh testapp/test.zsh P6-v2` and the digits-only pattern refused it,
# so the one command that was supposed to reach it never could.
# 也接受帶後綴的變體，這是為了 P6-v2。其 wrapper 的說明寫的是
# `zsh testapp/test.zsh P6-v2`，而「僅限數字」的樣式會拒絕它——於是那個本應抵達它的唯一指令，
# 從來就到不了。
case "$test_name" in
    P<->|P<->-*) ;;
    *)
        printf 'Unknown test: %s\n' "$test_name" >&2
        usage >&2
        exit 64
        ;;
esac

# No special case for P6.
#
# There was one, sending P6 to the standalone testapp/test_P6.zsh, and it made
# test_support/test_P6.zsh unreachable -- a wrapper written for exactly this
# command, whose own header says so, and which exists because the standalone
# script has no path that launches P6's WSL build. The loader routed around the
# thing that filled the gap.
#
# The standalone script stays. It is what P6-test.zsh and the GPU matrix work
# use, and the wrapper's header says to keep it for them.
#
# 此處不再為 P6 設特例。
#
# 原本有一個，會把 P6 導向獨立的 testapp/test_P6.zsh，因而使 test_support/test_P6.zsh 無法被
# 觸及——那支 wrapper 正是為此指令而寫、其檔頭亦如此聲明，且它存在的理由是「獨立腳本沒有任何路徑
# 能啟動 P6 的 WSL build」。loader 繞過了那個補上缺口的東西。
#
# 獨立腳本予以保留。P6-test.zsh 與 GPU matrix 相關工作使用的是它，wrapper 的檔頭也說明要為那些
# 用途保留它。
test_script="$script_dir/test_support/test_${test_name}.zsh"

if [ ! -f "$test_script" ]; then
    printf 'Missing test script: %s\n' "$test_script" >&2
    exit 1
fi

# **On Windows, say so BEFORE the run when input is already blocked.**
#
# A higher-integrity foreground window makes Windows refuse every synthesised
# event from this process, and refuses it SILENTLY: `SetCursorPos` returns false
# without setting an error, a `SendInput` fallback moves nothing, and screen
# capture keeps working -- so the run produces screenshots of an app that was
# never touched. Measured 2026-09-16, when `AsMonitorControl.exe` cost four
# rounds of debugging aimed at our own code before the cause was found.
#
# `--check` only: this REPORTS, it does not stop anything. A loader that killed
# a process as a side effect of running a test would be a surprise, and the
# blocker usually needs elevation anyway. The fix is one named command, printed
# here so nobody has to go looking for it.
#
# Not fatal either. Plenty of tests assert on a build, a log or a capture and do
# not synthesise input at all; failing those because an unrelated tray utility
# holds the foreground would be worse than the warning.
#
# **在 Windows 上,若輸入已經被擋住,就在執行之前說出來。**
#
# 一個完整性等級較高的前景視窗,會讓 Windows 拒絕本行程送出的每一個合成事件,而且是**無聲**拒絕:
# `SetCursorPos` 回傳 false 卻不設錯誤碼、`SendInput` 的退路推不動任何東西,而**螢幕擷取照常運作**
# ——於是那次執行會產出一堆「那個 app 從未被碰過」的截圖。2026-09-16 實測:`AsMonitorControl.exe`
# 讓四輪除錯都朝著我們自己的程式碼去找,之後才找到真正的成因。
#
# 只用 `--check`:此處僅**回報**,不停掉任何東西。一個「因為要跑測試而順手殺掉某個行程」的 loader
# 會是個意外,而且那個阻擋者通常本來就需要提權。修法是一個具名指令,印在這裡,免得有人還要去找。
#
# 也不讓它變成致命錯誤。有大量測試判定的是建置、log 或擷圖,根本不合成任何輸入;因為一個不相干的
# 系統匣工具佔著前景就讓那些測試失敗,會比這個警告更糟。
case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*)
        if ! zsh "$script_dir/enable_input.zsh" --check >/dev/null 2>&1; then
            printf '!! Windows may refuse synthesised input for this run:\n' >&2
            # Its own words, not a summary. The two cases need opposite advice --
            # an elevated blocker should be stopped, a remote-desktop host must
            # NOT be -- and a fixed message here would be wrong for one of them.
            # 印出它自己的說法,而不是一段摘要。兩種情況需要的建議完全相反——提權的阻擋者應該停掉、
            # 遠端桌面主機**絕對不可以**——而此處若寫死一段訊息,對其中一種必然是錯的。
            zsh "$script_dir/enable_input.zsh" --check 2>&1 | sed 's/^/!! /' >&2
        fi
        ;;
esac

exec zsh "$test_script" "${forward_args[@]}"
