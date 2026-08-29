#!/usr/bin/env zsh
# Exercises every form of the -GPU flag on GtkBackend/Windows and checks what
# each one actually did, not merely that it exited 0.
#
#   zsh testapp/gpu_flag_test.zsh            build P40, run every case
#   zsh testapp/gpu_flag_test.zsh --no-build reuse an existing SCUI_DEBUG=1 P40.exe
#   zsh testapp/gpu_flag_test.zsh --help
#
# Why each case reads what it reads. The flag's whole purpose is that a request
# it cannot honour must not be answered by quietly doing something else, so
# every check here looks at the thing that would expose a silent substitution:
#
#   -GPU 0    GSK_DEBUG=renderer must name GskCairoRenderer. "It launched" does
#             not distinguish software from hardware.
#   -GPU 1    must name whatever the NO-FLAG run named -- a relative assertion,
#             not an absolute one. Which renderer that is, is a fact about the
#             machine; what -GPU 1 MEANS is "the platform's own default".
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
#   no flag   is run FIRST, to establish what the platform default is, and is
#             then what -GPU 1 is compared against.
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
#   -GPU 1    必須指出與**無旗標**那次相同的繪製器——這是相對式斷言，不是絕對式。那究竟是哪個
#             繪製器，是關於這台機器的事實；-GPU 1 的**意義**是「平台自身的預設」。
#   -GPU 2    stdin 未接任何東西時，提示的空白回答代表「否」，因此事後**登錄檔必須未被更動**。
#             只讀提示內容的測試，即使它真的寫入了也會通過。
#   -GPU 2 -y 空白回答代表「是」，因此登錄檔必須含有 GpuPreference=2，且重新啟動後的行程必須
#             回報與內顯不同的介面卡。
#   -GPU 5    必須印出橫幅，**且**登錄檔中不得出現 GpuPreference=5——那是 Windows 未定義的值。
#             只檢查橫幅會漏掉「它寫入了無效值」。
#   -GPU list 必須印出可被解析的表格，**且**不得啟動任何視窗。
#   無旗標    **最先**執行，用以確立平台預設為何，之後作為 -GPU 1 的比對基準。
#   -GPU 1 且停用 GL 必須存活。這個組合過去會 SIGSEGV，因此斷言是「行程仍然活著」。
#
# 本測試所建立的登錄檔釘定，無論結果如何都會在最後移除。

set -u
script_path="${0:A}"
repo="${script_path:h:h}"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    sed -n '2,54p' "$script_path" | sed 's/^# \{0,1\}//'
    exit 0
fi

export PATH="/c/gtk4/bin:$PATH"
out="$repo/testapp/output"
windows_path() {
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -w "$1"
        return
    fi

    case "$1" in
        /?/*)
            local drive rest
            drive="${1[2]:u}"
            rest="${1[4,-1]//\//\\}"
            printf '%s:\\%s\n' "$drive" "$rest"
            ;;
        *)
            printf '%s\n' "$1"
            ;;
    esac
}
exe_win="$(windows_path "$out/P40.exe")"
key='HKCU\Software\Microsoft\DirectX\UserGpuPreferences'
pass=0
fail=0

cleanup() {
    # `-f -im`, the dash form, because it is the ONLY one that works in every
    # shell here. Measured 2026-08-29:
    #
    #     environment                conv   //F //IM     /F /IM    -f -im
    #     Git Bash                   on     ok           'F:/'     ok
    #     zsh -f (no zshrc)          on     ok           'F:/'     ok
    #     packaged zsh (wrapper)     off    '//F' error  ok        ok
    #     MSYS2_ARG_CONV_EXCL='*'    off    '//F' error  ok        ok
    #
    # The doubled slash needs MSYS to rewrite it and the packaged zsh wrapper
    # turns that off; the single slash needs the opposite. Only the dash form
    # needs neither. `tasklist` is a separate case and wants `//FI` -- the two
    # tools do not agree, which is what makes this easy to get wrong.
    #
    # It costs more than a wrong flag usually does: with stderr discarded the
    # failure is silent, and a surviving GTK process then makes the next launch
    # hand off to it and exit 0 with no window and no output.
    #
    # 使用 dash 形式的 `-f -im`，因為它是此處**唯一**在每種 shell 下都可用的形式（上表為
    # 2026-08-29 實測）。雙斜線需要 MSYS 為它改寫，而封裝版 zsh 的 wrapper 把改寫關掉了；單斜線
    # 則需要相反的條件。只有 dash 形式兩者都不需要。`tasklist` 是另一回事，它要的是 `//FI`——
    # 兩個工具的規則並不一致，這正是它容易搞錯的原因。
    #
    # 它的代價比一般旗標寫錯更高：stderr 一被丟棄，失敗就是無聲的；而存活下來的 GTK 行程會讓
    # 下一次啟動被它接管，並以結束碼 0 結束、不產生視窗、也沒有任何輸出。
    taskkill -f -im P40.exe >/dev/null 2>&1
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

check_absent() {
    # $1 label, $2 forbidden text, $3 actual text
    if [[ "$3" == *"$2"* ]]; then
        printf '  FAIL  %s\n        forbidden: %s\n        got:       %s\n' "$1" "$2" "$3"
        fail=$((fail + 1))
    else
        printf '  PASS  %s\n' "$1"
        pass=$((pass + 1))
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
    # `-f -im`, the dash form, because it is the ONLY one that works in every
    # shell here. Measured 2026-08-29:
    #
    #     environment                conv   //F //IM     /F /IM    -f -im
    #     Git Bash                   on     ok           'F:/'     ok
    #     zsh -f (no zshrc)          on     ok           'F:/'     ok
    #     packaged zsh (wrapper)     off    '//F' error  ok        ok
    #     MSYS2_ARG_CONV_EXCL='*'    off    '//F' error  ok        ok
    #
    # The doubled slash needs MSYS to rewrite it and the packaged zsh wrapper
    # turns that off; the single slash needs the opposite. Only the dash form
    # needs neither. `tasklist` is a separate case and wants `//FI` -- the two
    # tools do not agree, which is what makes this easy to get wrong.
    #
    # It costs more than a wrong flag usually does: with stderr discarded the
    # failure is silent, and a surviving GTK process then makes the next launch
    # hand off to it and exit 0 with no window and no output.
    #
    # 使用 dash 形式的 `-f -im`，因為它是此處**唯一**在每種 shell 下都可用的形式（上表為
    # 2026-08-29 實測）。雙斜線需要 MSYS 為它改寫，而封裝版 zsh 的 wrapper 把改寫關掉了；單斜線
    # 則需要相反的條件。只有 dash 形式兩者都不需要。`tasklist` 是另一回事，它要的是 `//FI`——
    # 兩個工具的規則並不一致，這正是它容易搞錯的原因。
    #
    # 它的代價比一般旗標寫錯更高：stderr 一被丟棄，失敗就是無聲的；而存活下來的 GTK 行程會讓
    # 下一次啟動被它接管，並以結束碼 0 結束、不產生視窗、也沒有任何輸出。
    taskkill -f -im P40.exe >/dev/null 2>&1
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
run './P40.exe --debug -GPU list < /dev/null' 2
check "two header rows" "索引,名稱" "$(head -2 "$TMP" | tr '\n' ' ')"
check "no window started" "0" "$(sleep 1; tasklist //FI 'IMAGENAME eq P40.exe' 2>&1 | grep -c P40.exe)"

printf '\n=== -GPU 0: software renderer ===\n'
run 'GSK_DEBUG=renderer ./P40.exe --debug -GPU 0 < /dev/null'
check "GskCairoRenderer" "GskCairoRenderer" "$(grep -o "Using renderer '[A-Za-z]*'" "$TMP" | tail -1)"

# `-GPU 1` is asserted RELATIVELY, against the no-flag run, and deliberately not
# against a renderer name.
#
# Which renderer `-GPU 1` produces is a fact about the machine, not about the
# flag. Here it is GskCairoRenderer, because GTK cannot realize GL without
# Direct Composition; on a machine where GL realizes unaided it would be
# GskGLRenderer, and an absolute assertion would fail there for no reason. What
# `-GPU 1` MEANS is "the platform's own default", so "identical to no flag" is
# the assertion that is true everywhere.
#
# `-GPU 1` 採**相對**斷言，對照的是「不加旗標」的執行結果，並刻意不對照繪製器名稱。
#
# `-GPU 1` 會產生哪個繪製器，是關於這台機器的事實，而非關於這個旗標。此處是 GskCairoRenderer，
# 因為沒有 Direct Composition 時 GTK 無法實現 GL；在一台 GL 能自行實現的機器上它會是
# GskGLRenderer，屆時絕對式斷言會毫無理由地失敗。`-GPU 1` 的**意義**是「平台自身的預設」，
# 因此「與不加旗標完全相同」才是到處都成立的斷言。
printf '\n=== no flag: establishes what the platform default is ===\n'
run 'GSK_DEBUG=renderer ./P40.exe < /dev/null'
default_renderer="$(grep -o "Using renderer '[A-Za-z]*'" "$TMP" | tail -1)"
check "named a renderer at all" "Using renderer" "$default_renderer"
printf '        (this machine: %s)\n' "$default_renderer"

printf '\n=== -GPU 1: must equal the platform default, whatever it is ===\n'
run 'GSK_DEBUG=renderer ./P40.exe --debug -GPU 1 < /dev/null'
check "same as no flag" "$default_renderer" "$(grep -o "Using renderer '[A-Za-z]*'" "$TMP" | tail -1)"

printf '\n=== -GPU 5: refused loudly, and writes nothing invalid ===\n'
run './P40.exe --debug -GPU 5 < /dev/null'
check "banner shown" "CANNOT BE HONOURED" "$(cat "$TMP")"
check "clamped to 2" "GpuPreference unset -> 2" "$(cat "$TMP")"
check_absent "registry has no 5" "GpuPreference=5" "$(reg query "$key" //v "$exe_win" 2>&1)"

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
