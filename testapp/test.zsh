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
  zsh testapp/test.zsh P19 -win --actionfile
  zsh testapp/test.zsh P28 --macos --actionfile
  zsh testapp/test.zsh P14 --ios
  zsh testapp/test.zsh P12 --android

Single-test scripts live in testapp/test_support/test_Pn.zsh.
EOF_USAGE
}

if [ "$#" -eq 0 ]; then
    usage >&2
    exit 64
fi

test_name="$1"
shift

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
case "$test_name" in
    P<->) ;;
    *)
        printf 'Unknown test: %s\n' "$test_name" >&2
        usage >&2
        exit 64
        ;;
esac

test_script="$script_dir/test_support/test_${test_name}.zsh"
if [ "$test_name" = "P6" ]; then
    test_script="$script_dir/test_P6.zsh"
fi

if [ ! -f "$test_script" ]; then
    printf 'Missing test script: %s\n' "$test_script" >&2
    exit 1
fi

exec zsh "$test_script" "$@"
