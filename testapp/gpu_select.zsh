#!/usr/bin/env zsh
# Chooses which GPU this laptop's test apps run on: AMD (integrated) or NVIDIA.
#
#   zsh testapp/gpu_select.zsh --status                       both GPUs, and per-app picks
#   zsh testapp/gpu_select.zsh --app <exe> nvidia|amd|default  one app's GPU (no admin)
#   zsh testapp/gpu_select.zsh --amd on|off                   enable/disable the AMD GPU (UAC)
#   zsh testapp/gpu_select.zsh --help
#
# 選擇這台筆電的測試 app 用哪一張 GPU:AMD(內顯)或 NVIDIA。
#   --status                        兩張 GPU 的狀態，以及各 app 的指定
#   --app <exe> nvidia|amd|default  單一 app 的 GPU(不需系統管理員)
#   --amd on|off                    啟用／停用 AMD GPU(會跳 UAC)
#
# WHY IT EXISTS. Measured 2026-10-07 on this ASUS TUF A15 (FA507NV): the AMD
# adapter was Disabled in Device Manager, so the panel -- wired to the AMD GPU
# in the normal (hybrid) mode -- ran on the Microsoft Basic Display Driver.
# DXGI then listed the Basic Render Driver (WARP, the CPU) first, every D3D app
# that takes the default adapter rendered on the CPU, and WGL could give only
# "GDI Generic" OpenGL 1.1, so GTK's GL mesh view had no GL at all. `--amd on`
# restores the hybrid mode; `--app` then picks NVIDIA for one executable, the
# same setting as Settings > Display > Graphics.
#
# 存在的原因。2026-10-07 在這台 ASUS TUF A15(FA507NV)上實測:AMD 介面卡在裝置管理員中是「已停用」,於是一般(混合)
# 模式下接在 AMD 上的內建螢幕改由 Microsoft Basic Display Driver 驅動。DXGI 因此把 Basic Render Driver(WARP,CPU)排第一,
# 取預設介面卡的 D3D app 全都在 CPU 上繪製,WGL 也只能給「GDI Generic」OpenGL 1.1,GTK 的 GL mesh view 完全沒有 GL。
# `--amd on` 恢復混合模式;`--app` 再替單一執行檔選 NVIDIA,與「設定 > 顯示器 > 圖形」是同一個設定。
#
# WHAT IT DOES NOT DO: the MUX switch (Armoury Crate's "Ultimate" GPU mode),
# which wires the panel straight to NVIDIA. On this model that is a firmware
# setting written through ASUS's ACPI interface and needs a reboot; use
# Armoury Crate for it. Turning AMD off while the panel is on it leaves the
# basic display driver -- the state above -- not a black screen.
#
# 不做的事:MUX 開關(Armoury Crate 的「Ultimate」GPU 模式),它把螢幕直接接到 NVIDIA。在本機型上那是經由 ASUS ACPI
# 介面寫入的韌體設定，且需要重新開機；請用 Armoury Crate 切換。螢幕接在 AMD 上時關掉 AMD,會回到上述的基本顯示驅動狀態，
# 而不是黑畫面。
#
# Elevation goes through gpu_select.ps1, which only elevates and calls this
# script again; the logic stays here, in zsh. `MSYS2_ARG_CONV_EXCL` is scoped
# to each pnputil/reg call: their `/flags` look like paths to Git Bash.
# 提權經由 gpu_select.ps1,它只負責提權並再次呼叫本腳本；邏輯留在這裡(zsh)。`MSYS2_ARG_CONV_EXCL` 只限定在每個
# pnputil/reg 呼叫上：它們的 `/旗標` 在 Git Bash 眼中像路徑。

set -u
# For `[[:space:]]#` below: trimming pnputil's column padding.
# 供下方 `[[:space:]]#` 使用：去掉 pnputil 的欄位對齊空白。
setopt extendedglob
script_path="${0:A}"
script_dir="${script_path:h}"

show_help() {
    sed -n '2,13p' "$script_path" | sed 's/^# \{0,1\}//'
}

if [[ $# -eq 0 || "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    show_help
    exit 0
fi

gpu_key='HKCU\Software\Microsoft\DirectX\UserGpuPreferences'

# The Display-class devices, as "instance|description|status" lines.
# Display 類裝置，每行為「instance|description|status」。
display_devices() {
    local instance="" description="" line
    MSYS2_ARG_CONV_EXCL='*' pnputil.exe /enum-devices /class Display 2>/dev/null | tr -d '\r' |
        while IFS= read -r line; do
            case "$line" in
                'Instance ID:'*) instance="${${line#Instance ID:}##[[:space:]]#}" ;;
                'Device Description:'*) description="${${line#Device Description:}##[[:space:]]#}" ;;
                'Status:'*)
                    printf '%s|%s|%s\n' "$instance" "$description" "${${line#Status:}##[[:space:]]#}"
                    ;;
            esac
        done
}

amd_instance() {
    display_devices | grep 'VEN_1002' | head -1 | cut -d'|' -f1
}

is_admin() {
    net session >/dev/null 2>&1
}

show_status() {
    printf 'GPUs (pnputil /enum-devices /class Display):\n'
    local row
    display_devices | while IFS= read -r row; do
        printf '  %-40s %s\n' "${${row#*|}%|*}" "${row##*|}"
    done
    printf '\nPer-app GPU picks (%s):\n' "$gpu_key"
    MSYS2_ARG_CONV_EXCL='*' reg.exe query "$gpu_key" 2>/dev/null | tr -d '\r' |
        grep 'GpuPreference=' | sed 's/^ *//' |
        sed 's/GpuPreference=2;/high performance (NVIDIA)/; s/GpuPreference=1;/power saving (AMD)/; s/GpuPreference=0;/let Windows decide/' |
        sed 's/ *REG_SZ */  ->  /' | sed 's/^/  /'
    if display_devices | grep 'VEN_1002' | grep -q 'Disabled'; then
        printf '\nAMD is DISABLED: the panel runs on the basic display driver, the default\n'
        printf 'D3D adapter is WARP and OpenGL is GDI Generic 1.1. Fix: --amd on\n'
    fi
}

case "$1" in
    --status)
        show_status
        ;;

    --app)
        [[ $# -eq 3 ]] || { printf 'usage: --app <exe> nvidia|amd|default\n' >&2; exit 2; }
        exe="$2"
        [[ -f "$exe" ]] || { printf 'no such file: %s\n' "$exe" >&2; exit 2; }
        exe_win="$(cygpath -w "${exe:A}")"
        case "$3" in
            nvidia) value='GpuPreference=2;' ;;
            amd) value='GpuPreference=1;' ;;
            default) value='' ;;
            *) printf 'expected nvidia, amd or default, got %s\n' "$3" >&2; exit 2 ;;
        esac
        if [[ -n "$value" ]]; then
            MSYS2_ARG_CONV_EXCL='*' reg.exe add "$gpu_key" /v "$exe_win" /t REG_SZ /d "$value" /f >/dev/null ||
                { printf 'reg add failed\n' >&2; exit 1; }
        else
            MSYS2_ARG_CONV_EXCL='*' reg.exe delete "$gpu_key" /v "$exe_win" /f >/dev/null 2>&1 || true
        fi
        # Read back rather than trust reg's status. 讀回確認，而非相信 reg 的結束碼。
        now="$(MSYS2_ARG_CONV_EXCL='*' reg.exe query "$gpu_key" /v "$exe_win" 2>/dev/null | tr -d '\r' | grep -o 'GpuPreference=[0-9];')"
        printf '%s -> %s (takes effect the next time it starts)\n' "$exe_win" "${now:-no preference}"
        ;;

    --amd)
        [[ $# -eq 2 && ( "$2" == on || "$2" == off ) ]] || { printf 'usage: --amd on|off\n' >&2; exit 2; }
        instance="$(amd_instance)"
        [[ -n "$instance" ]] || { printf 'no AMD display device found\n' >&2; exit 1; }
        if ! is_admin; then
            printf 'needs administrator rights; approve the UAC prompt\n'
            MSYS2_ARG_CONV_EXCL='*' powershell.exe -NoProfile -ExecutionPolicy Bypass \
                -File "$(cygpath -w "$script_dir/gpu_select.ps1")" --amd "$2" >/dev/null 2>&1 || true
        else
            if [[ "$2" == on ]]; then
                MSYS2_ARG_CONV_EXCL='*' pnputil.exe /enable-device "$instance"
            else
                MSYS2_ARG_CONV_EXCL='*' pnputil.exe /disable-device "$instance"
            fi
            exit $?
        fi
        # The verdict is the device's status afterwards, not a tool's exit code.
        # 判準是事後的裝置狀態，不是工具的結束碼。
        state="$(display_devices | grep 'VEN_1002' | head -1 | cut -d'|' -f3)"
        printf 'AMD is now: %s\n' "${state:-unknown}"
        wanted="Started"; [[ "$2" == off ]] && wanted="Disabled"
        [[ "$state" == "$wanted" ]] || { printf 'expected %s\n' "$wanted" >&2; exit 1; }
        ;;

    *)
        printf 'unknown argument: %s\n' "$1" >&2
        show_help >&2
        exit 2
        ;;
esac
