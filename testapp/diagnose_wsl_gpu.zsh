#!/usr/bin/env zsh
# Reports whether GTK under WSLg is using the GPU, and the evidence either way.
#
#   zsh testapp/diagnose_wsl_gpu.zsh
#   zsh testapp/diagnose_wsl_gpu.zsh --app P7   # ask a specific test app
#
# 回報 WSLg 下的 GTK 是否真的在使用 GPU，並附上兩種情況各自的證據。
#
# This prints measurements, not conclusions. The one thing it does state
# outright is which renderer GTK chose, because that is the question itself
# rather than a proxy for it: GSK tries Vulkan, then GL, then falls back to
# llvmpipe on the CPU, and the fallback is silent. Windows appear, tests pass,
# screenshots look right, and every frame was drawn on the CPU.
# 本腳本輸出的是量測值而非結論。唯一直接斷言的是 GTK 選了哪個 renderer，因為那就是
# 問題本身而非它的代理：GSK 依序嘗試 Vulkan、GL，最後退回 CPU 上的 llvmpipe，而這個
# 退回是靜默的——視窗照開、測試照過、截圖照樣正確，每一格卻都是 CPU 畫的。
#
# Everything else is context for *why*, and is deliberately shown raw. Three
# diagnoses were wrong on this machine because each was confirmed against
# something cheaper than the thing itself:
#
#   - a directory listing instead of its contents: the driver mount had the
#     right names and one entry was empty, which read as "no driver"
#   - a filename pattern instead of `pnputil`: `nvami.inf` was dismissed as
#     NVDIMM storage when it is in fact NVIDIA's display driver
#   - an empty directory instead of the several that were populated
#
# So this script shows file counts, not verdicts on them; it asks pnputil what
# the display driver is rather than guessing from names; and it prints the dxgk
# kernel messages verbatim, because that is the earliest point in the chain
# that says anything at all.
# 其餘一律是「為什麼」的佐證，且刻意以原始形式呈現。本機曾有三次診斷錯誤，每一次都是
# 拿比目標更廉價的東西去驗證：以目錄清單代替目錄內容、以檔名樣式代替 pnputil、以一個
# 空目錄代替其餘幾個有內容的目錄。因此這裡只列出檔案數而不對其下判斷、直接問 pnputil
# 顯示驅動是什麼、並原樣印出 dxgk 的核心訊息——那是整條鏈上最早會發聲的位置。

set -euo pipefail

script_path="${0:a}"
app="P7"

usage() {
    sed -n '2,8p' "$script_path" | sed 's/^# \{0,1\}//'
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --app)
            [ "$#" -ge 2 ] || { printf -- '--app needs a name\n' >&2; exit 64; }
            app="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 64 ;;
    esac
done

wsl() { MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu -- "$@"; }

# Anything with a shell variable in it goes to WSL as a file, never as a
# command string. Variables inside `wsl.exe -- zsh -lc "..."` are eaten
# somewhere between the outer shell, wsl.exe and the inner one: the loop below
# came back with $n and $found empty, so every comparison failed with "integer
# expected" and the summary announced that no driver directory held more than
# 20 files -- on a machine where one holds 165. A file is passed as a path and
# read directly, so nothing rewrites it.
# 任何含 shell 變數的內容一律以「檔案」送進 WSL，不用命令字串。變數在
# `wsl.exe -- zsh -lc "..."` 中會在外層 shell、wsl.exe 與內層 shell 之間被吃掉：
# 下方迴圈的 $n 與 $found 都變成空字串，於是每次比較都以 "integer expected" 失敗，
# 摘要宣告「沒有任何驅動目錄超過 20 個檔案」——而該機器上有一個目錄含 165 個檔案。
# 改以檔案傳遞，路徑進去、直接讀取，中間沒有東西會改寫它。
wsl_script() {
    MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu -- zsh -lc "cat > /tmp/scui-probe.zsh"
    MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu -- zsh /tmp/scui-probe.zsh
}

section() { printf '\n== %s ==\n' "$1"; }

# ---------------------------------------------------------------- ground truth
# Asked first, because it is the answer. Everything below explains it.
# 先問這一項，因為它就是答案；下面所有內容都只是在解釋它。
section "What renderer GTK actually uses"
if wsl zsh -lc "test -x ~/proj/swift-cross-ui/testapp/output/$app" 2>/dev/null; then
    wsl zsh -lc "cd ~/proj/swift-cross-ui/testapp/output && GSK_DEBUG=renderer timeout 8 ./$app 2>&1 | grep -iE 'renderer is|Not using|Failed to realize' | head -4" \
        || printf '  (no renderer lines; the app may not have opened a window)\n'
else
    printf '  %s is not built under WSL. Build it first:\n' "$app"
    printf '    zsh testapp/compile.zsh %s\n' "$app"
fi

# ------------------------------------------------------------------- the chain
# Every WSL-side check lives in one probe file. Three of them were inline
# `zsh -lc` strings first, and the device-node one failed the same way the loop
# had: `/dev/dri/renderD*` matches nothing on this machine, zsh treats that as
# an error rather than passing the pattern through, and the abort swallowed the
# /dev/dxg line printed just before it. One file, one `setopt`, one round trip.
# 所有 WSL 端檢查集中在單一探測檔案。其中三項原本是行內 `zsh -lc` 字串，而裝置節點
# 那項以同樣方式失敗：本機的 `/dev/dri/renderD*` 匹配不到任何東西，zsh 視之為錯誤而
# 非原樣傳遞，中止時連同前一行已印出的 /dev/dxg 一併吞掉。改為單一檔案、單一 setopt、
# 單次往返。
section "Device nodes, kernel, driver payload, Vulkan"
# File counts, not a verdict. An entry can exist with the right name and hold
# nothing; another with a name that looks unrelated can hold the whole driver.
# 只列檔案數，不下判斷。項目可能名稱正確卻空無一物，也可能名稱看似無關卻裝著整個驅動。
# `wc -l` is padded on some builds and the substitution yields an empty string
# when the directory cannot be read, so the count is stripped and defaulted.
# Without that, `[ "$n" -gt 20 ]` aborts with "integer expected", the error is
# lost among 900 directories, and the loop prints "no entry holds more than 20
# files" on a machine whose driver directory holds 165 -- this script's own
# version of the mistake it exists to prevent.
# 某些環境的 `wc -l` 會補空白，目錄讀不到時命令替換又會得到空字串，因此這裡去除空白
# 並給預設值。否則 `[ "$n" -gt 20 ]` 會以 "integer expected" 中止，錯誤淹沒在 900 個
# 目錄裡，而迴圈會在一台驅動目錄有 165 個檔案的機器上印出「沒有任何項目超過 20 個
# 檔案」——本腳本正是為了避免這種錯誤而存在。
wsl_script <<'PROBE'
# NULL_GLOB because this runs under zsh, where a pattern matching nothing is an
# error rather than being passed through as literal text. Without it, the very
# machines worth diagnosing -- no render node, no driver mount -- abort here
# instead of reporting that.
# 使用 NULL_GLOB，因為這段在 zsh 下執行，而 zsh 對「匹配不到任何東西」的樣式會報錯，
# 不像 bash 會原樣傳遞。少了它，最需要診斷的機器（沒有 render node、沒有驅動掛載）
# 反而會在此中止，而非回報該事實。
setopt NULL_GLOB

printf '\n  -- device nodes --\n'
printf '  %-18s ' /dev/dxg
[ -e /dev/dxg ] && printf 'present\n' || printf 'MISSING\n'
printf '  %-18s ' /dev/dri
nodes=(/dev/dri/renderD*)
if [ ${#nodes} -gt 0 ]; then
    printf '%s\n' "${nodes[*]}"
else
    printf 'MISSING\n'
fi

printf '\n  -- kernel: what dxgk reports (verbatim) --\n'
dmesg 2>/dev/null | grep -i dxgk | tail -5 | sed 's/^/  /' \
    || printf '  (dmesg unavailable, or no dxgk messages)\n'

printf '\n  -- vulkan ICDs --\n'
icds=(/usr/share/vulkan/icd.d/*)
if [ ${#icds} -gt 0 ]; then
    for i in "${icds[@]}"; do printf '  %s\n' "${i:t}"; done
else
    printf '  none installed\n'
fi

printf '\n  -- vulkan drivers this mesa was BUILT with --\n'
# The manifest list above says which ICDs are configured. This says which ones
# exist to configure, and the two answer different questions. On this machine
# the manifests looked plentiful -- eight of them -- while every one was for
# hardware that is not present, leaving lavapipe as the only ICD that could
# answer. `dzn`, Mesa's Vulkan-on-D3D12 driver and the only one that could reach
# a GPU through /dev/dxg, is not built by Ubuntu's mesa-vulkan-drivers at all.
# So "no hardware Vulkan here" is not a configuration mistake to correct; the
# driver is absent from the packages. Measured 2026-08-29 on mesa 26.0.3.
# 上方的 manifest 清單說的是「設定了哪些 ICD」，這裡說的是「有哪些 ICD 可供設定」，
# 兩者回答的是不同問題。本機的 manifest 看起來很豐富——共八個——但每一個都對應到不存在
# 的硬體，於是只剩 lavapipe 能回應。而 `dzn`（Mesa 的 Vulkan-on-D3D12 驅動，也是唯一
# 能透過 /dev/dxg 觸及 GPU 的那個）根本未被 Ubuntu 的 mesa-vulkan-drivers 編入。
# 因此「此處沒有硬體 Vulkan」不是一個可以修正的設定錯誤——那個驅動不在套件裡。
# 2026-08-29 於 mesa 26.0.3 實測。
built=(/usr/lib/x86_64-linux-gnu/libvulkan_*.so)
if [ ${#built} -gt 0 ]; then
    for b in "${built[@]}"; do printf '  %s\n' "${b:t}" ; done
    printf '  (libvulkan_lvp.so is lavapipe, software. libvulkan_dzn.so is the\n'
    printf '   D3D12 one WSL would need -- if it is absent, no package here has it.)\n'
else
    printf '  none\n'
fi

printf '\n  -- GL/Vulkan libraries exposed by the Windows driver --\n'
# /usr/lib/wsl/lib is where the Windows GPU driver publishes its Linux
# userspace. A file count is not enough: CUDA, NVENC and OptiX being present
# says nothing about GL or Vulkan, and on this machine those are exactly what is
# there and exactly what is missing.
# /usr/lib/wsl/lib 是 Windows GPU 驅動發布其 Linux userspace 之處。只數檔案不夠：
# CUDA、NVENC 與 OptiX 存在，並不代表 GL 或 Vulkan 也在——而本機的情況正是前者齊備、
# 後者一個都沒有。
exposed=(/usr/lib/wsl/lib/*(glx|GLX|vulkan|VK|icd)*)
if [ ${#exposed} -gt 0 ]; then
    for e in "${exposed[@]}"; do printf '  %s\n' "${e:t}"; done
else
    printf '  none -- the driver exposes no GL or Vulkan userspace to WSL\n'
fi

printf '\n  -- driver payload mounted into WSL --\n'
found=0
for d in /usr/lib/wsl/drivers/*/; do
    [ -d "$d" ] || continue
    n=$(ls -1 "$d" 2>/dev/null | wc -l | tr -dc '0-9')
    [ "${n:-0}" -gt 20 ] || continue
    printf '  %-46s %s files\n' "$(basename "$d")" "$n"
    found=1
done
[ "$found" -eq 1 ] || printf '  no entry holds more than 20 files\n'
printf '  %-46s %s files\n' "/usr/lib/wsl/lib" "$(ls -1 /usr/lib/wsl/lib 2>/dev/null | wc -l | tr -dc '0-9')"
PROBE

# Vulkan ICDs are listed by the probe above. "device is CPU" from GSK means
# only a software ICD such as lavapipe answered.
# Vulkan ICD 已由上方的探測列出。GSK 回報 "device is CPU" 代表只有 lavapipe 這類
# 軟體 ICD 有回應。

# ------------------------------------------------------- the Windows-side facts
section "Display driver, according to Windows"
# pnputil is authoritative. Guessing from INF names is how nvami.inf, which is
# NVIDIA's display driver, got written off as NVDIMM storage.
# pnputil 是權威來源。從 INF 名稱猜測，正是 nvami.inf（NVIDIA 的顯示驅動）被誤判為
# NVDIMM 儲存驅動的原因。
MSYS2_ARG_CONV_EXCL='*' pnputil.exe /enum-drivers 2>/dev/null | tr -d '\0\r' \
    | awk '/^Published Name/{p=$0} /^Original Name/{o=$0} /^Provider Name/{v=$0}
           /^Class Name:[[:space:]]*Display/{printf "  %s\n  %s\n  %s\n  %s\n\n", p, o, v, $0}' \
    | head -20 || printf '  (pnputil unavailable)\n'

section "WSL platform"
MSYS2_ARG_CONV_EXCL='*' wsl.exe --version 2>/dev/null | tr -d '\0\r' | sed 's/^/  /' | head -4

printf '\n'
printf 'If the renderer above is llvmpipe, GTK drew every frame on the CPU.\n'
printf 'UI tests remain valid; anything measuring GPU presentation does not.\n'
printf '若上方的 renderer 是 llvmpipe，代表 GTK 的每一格都由 CPU 繪製。\n'
printf 'UI 測試仍然有效，但任何量測 GPU 呈現的工作都不成立。\n'
