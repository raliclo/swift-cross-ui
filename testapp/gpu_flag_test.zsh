#!/usr/bin/env zsh
# Exercises every form of the -GPU flag on GtkBackend/Windows and checks what
# each one actually did, not merely that it exited 0.
#
#   zsh testapp/gpu_flag_test.zsh            build P40, run every case
#   zsh testapp/gpu_flag_test.zsh --no-build reuse the existing P40.exe
#   zsh testapp/gpu_flag_test.zsh --help
#
# Why each case reads what it reads. The flag's whole purpose is that a request
# it cannot honour must not be answered by quietly doing something else, so
# every check here looks at the thing that would expose a silent substitution:
#
#   -GPU 0    GSK_DEBUG=renderer must name GskCairoRenderer. "It launched" does
#             not distinguish software from hardware.
#   -GPU 1    must name GskGLRenderer. Same reason, other direction.
#   -GPU 2    with nothing on stdin the prompt's blank answer means No, so the
#             REGISTRY MUST BE UNCHANGED afterwards. A test that only read the
#             prompt would pass even if it wrote.
#   -GPU 2 -y blank answer means Yes, so the registry must hold
#             GpuPreference=2 and the relaunched process must report a
#             different adapter than the integrated one.
#   -GPU 5    must print the banner AND leave the registry without a
#             GpuPreference=5, which Windows does not define. Checking only the
#             banner would miss it writing an invalid value.
#   -GPU list must print a parsable table AND start no window.
#   no flag   must behave as -GPU 1, since that is the documented default.
#   -GPU 1 with GL disabled must survive. This combination used to SIGSEGV, so
#             the assertion is that the process is still alive.
#
# The registry pin this creates is removed again at the end, whatever happened.
#
# 於 GtkBackend/Windows 上逐一執行 -GPU 旗標的每一種形式，並檢查每一種「實際做了什麼」，
# 而不只是「結束碼為 0」。
#
# 每個案例為何要那樣讀。這個旗標存在的全部意義，就是「無法遵從的要求，絕不能以安靜地做別的事
# 來回應」，因此此處每一項檢查看的都是「能揭穿無聲替換」的那個東西：
#
#   -GPU 0    GSK_DEBUG=renderer 必須指出 GskCairoRenderer。「它啟動了」無法區分軟體與硬體。
#   -GPU 1    必須指出 GskGLRenderer。同樣的理由，反方向。
#   -GPU 2    stdin 未接任何東西時，提示的空白回答代表「否」，因此事後**登錄檔必須未被更動**。
#             只讀提示內容的測試，即使它真的寫入了也會通過。
#   -GPU 2 -y 空白回答代表「是」，因此登錄檔必須含有 GpuPreference=2，且重新啟動後的行程必須
#             回報與內顯不同的介面卡。
#   -GPU 5    必須印出橫幅，**且**登錄檔中不得出現 GpuPreference=5——那是 Windows 未定義的值。
#             只檢查橫幅會漏掉「它寫入了無效值」。
#   -GPU list 必須印出可被解析的表格，**且**不得啟動任何視窗。
#   無旗標    行為必須等同 -GPU 1，因為那是文件所載的預設值。
#   -GPU 1 且停用 GL 必須存活。這個組合過去會 SIGSEGV，因此斷言是「行程仍然活著」。
#
# 本測試所建立的登錄檔釘定，無論結果如何都會在最後移除。

set -u
script_path="${0:A}"
repo="${script_path:h:h}"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    sed -n '2,40p' "$script_path" | sed 's/^# \{0,1\}//'
    exit 0
fi

export PATH="/c/gtk4/bin:$PATH"
out="$repo/testapp/output"
exe_win='C:\Users\lowei\proj\swift-cross-ui\testapp\output\P40.exe'
key='HKCU\Software\Microsoft\DirectX\UserGpuPreferences'
pass=0
fail=0

cleanup() {
    # `/F /IM`, single slash. Under zsh, `taskkill //F //IM` fails outright with
    # "Invalid argument/option - '//F'" and the process survives -- silently, if
    # stderr is discarded. bash converts `//F` to `/F` and zsh does not, so the
    # same line works interactively and fails in this script. tasklist is the
    # other way round and wants the doubled slash. Measured 2026-08-29.
    # 使用單斜線的 `/F /IM`。在 zsh 底下，`taskkill //F //IM` 會直接失敗並回報
    # 「Invalid argument/option - '//F'」，而行程存活下來——若 stderr 被丟棄，這一切還是無聲的。
    # bash 會把 `//F` 轉為 `/F`，zsh 不會，因此同一行在互動式下可用、在本腳本中卻失敗。
    # tasklist 則相反，要用雙斜線。2026-08-29 實測。
    taskkill /F /IM P40.exe >/dev/null 2>&1
    reg delete "$key" //v "$exe_win" //f >/dev/null 2>&1
}
trap cleanup EXIT

check() {
    # $1 label, $2 expectation, $3 actual-contains
    if [[ "$3" == *"$2"* ]]; then
        printf '  PASS  %s\n' "$1"
        pass=$((pass + 1))
    else
        printf '  FAIL  %s\n        wanted: %s\n        got:    %s\n' "$1" "$2" "$3"
        fail=$((fail + 1))
    fi
}

if [[ "${1:-}" != "--no-build" ]]; then
    printf 'building P40 with SCUI_DEBUG=1 (the flag needs the debug features)\n'
    SCUI_DEBUG=1 zsh "$repo/testapp/compile.zsh" -gtk4 P40 >/dev/null 2>&1 || {
        printf 'build failed\n' >&2
        exit 1
    }
fi

run() {
    # Runs P40 with the given env/args, returns after it settles or exits.
    #
    # WAITS for the previous process to actually be gone, rather than assuming
    # taskkill is synchronous. GTK enforces a single instance by application
    # ID, so launching while the old process is still alive hands the request
    # to it and the new one exits immediately -- code 0, no window, and NO
    # OUTPUT. That is indistinguishable from a launch failure, and it is what
    # made four of these cases report an empty log the first time this ran.
    #
    # 會「等到」前一個行程確實消失，而不是假設 taskkill 是同步的。GTK 以 application ID 實施
    # 單一實例，因此在舊行程仍存活時啟動，會把請求交給它，新的行程隨即結束——結束碼 0、沒有
    # 視窗、也**沒有任何輸出**。那與啟動失敗無從分辨，而這正是本測試首次執行時，四個案例回報
    # 空白日誌的原因。
    # `/F /IM`, single slash. Under zsh, `taskkill //F //IM` fails outright with
    # "Invalid argument/option - '//F'" and the process survives -- silently, if
    # stderr is discarded. bash converts `//F` to `/F` and zsh does not, so the
    # same line works interactively and fails in this script. tasklist is the
    # other way round and wants the doubled slash. Measured 2026-08-29.
    # 使用單斜線的 `/F /IM`。在 zsh 底下，`taskkill //F //IM` 會直接失敗並回報
    # 「Invalid argument/option - '//F'」，而行程存活下來——若 stderr 被丟棄，這一切還是無聲的。
    # bash 會把 `//F` 轉為 `/F`，zsh 不會，因此同一行在互動式下可用、在本腳本中卻失敗。
    # tasklist 則相反，要用雙斜線。2026-08-29 實測。
    taskkill /F /IM P40.exe >/dev/null 2>&1
    local waited=0
    while tasklist //FI "IMAGENAME eq P40.exe" 2>&1 | grep -q P40.exe; do
        sleep 1
        waited=$((waited + 1))
        if [[ "$waited" -gt 15 ]]; then
            printf '  (P40.exe would not die; the next case will be unreliable)\n' >&2
            break
        fi
    done
    ( cd "$out" && eval "$1" ) > "$TMP" 2>&1 &
    sleep "${2:-8}"
}

TMP="$(mktemp)"
reg delete "$key" //v "$exe_win" //f >/dev/null 2>&1

printf '\n=== -GPU list: prints a table, starts nothing ===\n'
( cd "$out" && ./P40.exe --debug -GPU list < /dev/null ) > "$TMP" 2>&1
check "two header rows" "索引,名稱" "$(head -2 "$TMP" | tr '\n' ' ')"
check "no window started" "0" "$(sleep 1; tasklist //FI 'IMAGENAME eq P40.exe' 2>&1 | grep -c P40.exe)"

printf '\n=== -GPU 0: software renderer ===\n'
run 'GSK_DEBUG=renderer ./P40.exe --debug -GPU 0 < /dev/null'
check "GskCairoRenderer" "GskCairoRenderer" "$(grep -o "Using renderer '[A-Za-z]*'" "$TMP" | tail -1)"

printf '\n=== -GPU 1: hardware renderer ===\n'
run 'GSK_DEBUG=renderer ./P40.exe --debug -GPU 1 < /dev/null'
check "GskGLRenderer" "GskGLRenderer" "$(grep -o "Using renderer '[A-Za-z]*'" "$TMP" | tail -1)"

printf '\n=== no flag: same as -GPU 1 ===\n'
run 'GSK_DEBUG=renderer ./P40.exe < /dev/null'
check "GskGLRenderer" "GskGLRenderer" "$(grep -o "Using renderer '[A-Za-z]*'" "$TMP" | tail -1)"

printf '\n=== -GPU 5: refused loudly, and writes nothing invalid ===\n'
run './P40.exe --debug -GPU 5 < /dev/null'
check "banner shown" "CANNOT BE HONOURED" "$(cat "$TMP")"
check "clamped to 2" "GpuPreference unset -> 2" "$(cat "$TMP")"
check "registry has no 5" "" "$(reg query "$key" //v "$exe_win" 2>&1 | grep -o 'GpuPreference=5' || printf '')"

printf '\n=== -GPU 2 without -y: prompt defaults to No, registry untouched ===\n'
run './P40.exe --debug -GPU 2 < /dev/null'
check "prompt shows [y/N]" "[y/N]" "$(cat "$TMP")"
check "cancelled" "Cancelled" "$(cat "$TMP")"
check "registry still unset" "unable to find" "$(reg query "$key" //v "$exe_win" 2>&1)"

printf '\n=== -GPU 2 -y: prompt defaults to Yes, writes and restarts ===\n'
run 'GDK_DEBUG=opengl ./P40.exe --debug -GPU 2 -y < /dev/null' 12
check "prompt shows [Y/n]" "[Y/n]" "$(cat "$TMP")"
check "written" "Written. Restarting." "$(cat "$TMP")"
check "registry now 2" "GpuPreference=2" "$(reg query "$key" //v "$exe_win" 2>&1)"
check "relaunched onto another adapter" "NVIDIA" "$(grep -o 'Renderer: .*' "$TMP" | tail -1)"

printf '\n=== -GPU 1 with GL unavailable: must NOT crash ===\n'
reg delete "$key" //v "$exe_win" //f >/dev/null 2>&1
run 'GSK_DEBUG=renderer GDK_DISABLE=gl,vulkan,d3d11,d3d12 ./P40.exe --debug -GPU 1 < /dev/null'
check "still alive" "1" "$(tasklist //FI 'IMAGENAME eq P40.exe' 2>&1 | grep -c P40.exe)"
check "fell back to software" "GskCairoRenderer" "$(grep -o "Using renderer '[A-Za-z]*'" "$TMP" | tail -1)"

rm -f "$TMP"
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
