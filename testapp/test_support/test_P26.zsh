#!/usr/bin/env zsh
# P26 networking: the appCache behaviour, then the usual GUI dry-run.
#
#   zsh testapp/test.zsh P26                 cache checks, then the window
#   zsh testapp/test.zsh P26 --cache-only    just the cache checks
#   zsh testapp/test.zsh P26 --skip-cache    just the window
#
# P26 網路功能：先驗證 appCache 行為，再進行慣例的 GUI dry-run。
#
# Unlike every other test_Pn this one does more than set variables and hand over
# to test_common. A cache is only observable across runs -- fetch, then fetch
# again and see that nothing was downloaded -- and test_common launches an app
# once. The cache half is written here; the window half still goes to
# test_common so P26 reports in the same shape as everything else.
#
# 與其他每一支 test_Pn 不同，本腳本不只是設定變數然後交棒給 test_common。快取的行為唯有跨多次
# 執行才觀察得到——先抓取一次，再抓取一次並確認什麼都沒下載——而 test_common 只會啟動 app 一次。
# 快取的部分寫在此處；視窗的部分仍交給 test_common，使 P26 的回報格式與其他測試一致。
#
# Every check asserts rather than prints. The scratchpad version of this only
# showed the index and left the reading to a person, which is how two runs that
# re-downloaded every time were mistaken for a working cache.
# 每一項檢查都是斷言而非印出。本測試在 scratchpad 中的版本只顯示索引、把判讀留給人，而那正是
# 「連續兩次都重新下載」曾被誤認為「快取正常運作」的原因。

set -uo pipefail

support_dir="${0:a:h}"
script_dir="${support_dir:h}"
script_path="${0:a}"

if [ "${1:-}" = --help ] || [ "${1:-}" = -h ]; then
    sed -n '2,20p' "$script_path" | sed 's/^# \{0,1\}//'
    exit 0
fi

run_cache=1
run_window=1
passthrough=()
for argument in "$@"; do
    case "$argument" in
        --cache-only) run_window=0 ;;
        --skip-cache) run_cache=0 ;;
        *) passthrough+=("$argument") ;;
    esac
done

failures=0

# An empty expectation is refused outright.
#
# `check "the same artifact" "$first" "$(artifact_name)"` compared two empty
# strings and passed when nothing had been fetched at all -- a test reporting
# success because both sides were equally absent. Measured: a build without
# SCUI_DEBUG produced no artifacts, and this printed PASS.
#
# 空的預期值一律直接拒絕。
#
# `check "the same artifact" "$first" "$(artifact_name)"` 曾在「根本沒有抓取任何東西」時比較兩個
# 空字串而判定通過——一個因為「兩邊同樣不存在」而回報成功的測試。實測：未帶 SCUI_DEBUG 的建置沒有
# 產生任何 artifact，而此處印出了 PASS。
check() {
    local label="$1" expected="$2" actual="$3"
    if [ -z "$expected" ]; then
        printf '    FAIL  %s\n' "$label"
        printf '          nothing to compare against; an earlier step produced no value\n'
        failures=$((failures + 1))
        return
    fi
    if [ "$expected" = "$actual" ]; then
        printf '    PASS  %s\n' "$label"
    else
        printf '    FAIL  %s\n' "$label"
        printf '          expected %s, got %s\n' "$expected" "$actual"
        failures=$((failures + 1))
    fi
}

# Everything below runs in WSL, where the app and its cache directory live.
# One invocation per step rather than a single long script, so a step that hangs
# is identifiable from the output rather than taking the rest with it.
# 以下全部在 WSL 中執行，app 與其快取目錄都在該處。每個步驟各自呼叫一次，而非合併為一個長腳本，
# 如此某個卡住的步驟可從輸出中辨識出來，而不會把其餘步驟一併拖住。
wsl() {
    MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu -- zsh -lc "$1"
}

cache_dir='$HOME/.cache/P26/appCache'
app_dir='$HOME/proj/swift-cross-ui/testapp/output'
actions='$HOME/proj/swift-cross-ui/testapp/actions/wsl/P26-swiftcrossui-tab.csv'
render_env="${TEST_RENDER_ENV:-GALLIUM_DRIVER=d3d12 MESA_D3D12_DEFAULT_ADAPTER_NAME=NVIDIA GSK_DEBUG=renderer}"

# The action file switches to the SwiftCrossUI tab, and without it nothing is
# fetched at all: TabView builds only the selected tab and AsyncImage is on the
# third one. Found the hard way -- four runs reported an empty cache, and the
# cache had never been asked for anything.
# 該動作檔會切換至 SwiftCrossUI 分頁；少了它便完全不會發生任何抓取，因為 TabView 只建構被選取的
# 分頁，而 AsyncImage 位於第三個分頁上。此事是吃過虧才知道的——四次執行都回報快取為空，而事實是
# 從頭到尾沒有人向快取要過東西。
launch() {
    wsl "export GDK_BACKEND=x11; cd $app_dir && pkill -x P26 2>/dev/null; sleep 1; \
        (env $render_env ./P26 --debug $1 -actionfile $actions > /tmp/p26-test.log 2>&1 &); \
        sleep 14; pkill -x P26 2>/dev/null; sleep 1" > /dev/null 2>&1
}

artifact_count() {
    wsl "ls $cache_dir/artifacts 2>/dev/null | wc -l" | tr -d ' \r\n'
}

artifact_name() {
    wsl "ls $cache_dir/artifacts 2>/dev/null | head -1" | tr -d ' \r\n'
}

index_lines() {
    wsl "wc -l < $cache_dir/appCache.csv2 2>/dev/null || printf 0" | tr -d ' \r\n'
}

if [ "$run_cache" -eq 1 ]; then
    printf '==> P26 appCache\n'

    # SCUI_DEBUG=1 is not optional here. Without it -actionfile is not compiled
    # into the binary, the tab is never switched, AsyncImage never runs, and
    # every check below examines a cache nobody asked for anything. That is not
    # hypothetical: it happened, and the run reported PASS on two of the checks
    # because both sides of the comparison were equally empty.
    # 此處的 SCUI_DEBUG=1 並非可選。少了它，-actionfile 不會被編入執行檔，分頁不會切換，AsyncImage
    # 不會執行，而下方每一項檢查所檢視的，都是一個沒有人向它要過任何東西的快取。這並非假設：它確實
    # 發生過，且該次執行有兩項檢查回報 PASS——因為比較的兩邊同樣是空的。
    printf '  building P26 with SCUI_DEBUG=1\n'
    wsl "cd \$HOME/proj/swift-cross-ui && SCUI_DEBUG=1 zsh testapp/compile.zsh P26 2>&1 \
        | grep -E 'error:|complete!'" | sed 's/^/    /'

    printf '\n  1. an empty cache fills itself on the first fetch\n'
    wsl "rm -rf \$HOME/.cache/P26" > /dev/null 2>&1
    launch ""
    check "one artifact written" 1 "$(artifact_count)"
    # Three lines: two csv2 headers and one record. A .csv2 carries two headers,
    # and a file with one would have the first record read as the missing second
    # header and silently dropped.
    # 三行：兩列 csv2 標頭加一筆記錄。`.csv2` 帶有兩列標頭；若只有一列，第一筆記錄會被當成缺少的
    # 第二列標頭而靜默消失。
    check "index has two headers and one record" 3 "$(index_lines)"
    first="$(artifact_name)"

    printf '\n  2. a second run reuses it rather than downloading again\n'
    launch ""
    check "still one artifact" 1 "$(artifact_count)"
    check "the same artifact" "$first" "$(artifact_name)"

    printf '\n  3. -force fetches the body and replaces it\n'
    launch "-force"
    check "still one artifact" 1 "$(artifact_count)"
    if [ "$(artifact_name)" = "$first" ]; then
        printf '    FAIL  the artifact was not replaced\n'
        printf '          -force served the cached copy instead of fetching\n'
        failures=$((failures + 1))
    else
        printf '    PASS  the artifact was replaced\n'
    fi
    forced="$(artifact_name)"

    printf '\n  4. the policy is not stuck -- a plain run reuses again\n'
    launch ""
    check "the forced artifact is reused" "$forced" "$(artifact_name)"

    printf '\n  index:\n'
    wsl "cat $cache_dir/appCache.csv2 2>/dev/null" | sed 's/^/    /' | cut -c1-150

    printf '\n==> %s\n' \
        "$([ "$failures" -eq 0 ] && printf 'appCache: all checks pass' \
            || printf "appCache: $failures FAILED")"
fi

if [ "$run_window" -eq 0 ]; then
    exit "$([ "$failures" -eq 0 ] && printf 0 || printf 1)"
fi

if [ "$failures" -ne 0 ]; then
    printf '\n==> skipping the GUI run; the cache checks failed\n'
    exit 1
fi

printf '\n'
export TEST_APP="P26"
export TEST_TITLE="P26 networking"
export TEST_LOG_NAME="p26-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|cache dir|index rows"
export TEST_TARGET="wsl"
exec zsh "$support_dir/test_common.zsh" "${passthrough[@]}"
