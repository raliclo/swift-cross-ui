#!/usr/bin/env zsh
# Checks the Windows side of a WSL test host: disk and memory settings (Windows only).
#
#   zsh testapp/test_support/check_wsl_host.zsh           report every check
#   zsh testapp/test_support/check_wsl_host.zsh --quiet   print only problems
#   zsh testapp/test_support/check_wsl_host.zsh --help
#   TEST_WSL_DISTRO=<name> ...                            another distribution (default Ubuntu)
#
# Warnings only: exit 0 whatever it finds, so test.zsh can call it before every
# WSL run without blocking one. Each warning carries the command that fixes it.
# 檢查 WSL 測試主機在 Windows 這一側的磁碟與記憶體設定(僅限 Windows)。只發警告：不論結果都以 0 結束，
# 讓 test.zsh 能在每次 WSL 執行前呼叫而不擋下任何一次。每則警告都附上修正它的指令。
#
# Why each check exists, all measured on 2026-10-22/23:
# - The distribution's ext4.vhdx only grows. Files deleted inside WSL stay
#   allocated on C:; 79 GB in use inside was 82 GB on C:. A sparse vhdx gives
#   freed blocks back (with fstrim, which install_tool_wsl.zsh schedules).
# - C: below 20 GB: the pagefile grows into it, and a full C: is how a
#   background build was killed for low memory on 2026-10-22.
# - .wslconfig without memory= lets the VM take half of RAM, and Linux fills it
#   with file cache that Windows counts as committed (14.9 GB on 2026-10-22).
# 各項檢查的理由(2026-10-22/23 實測):發行版的 ext4.vhdx 只會變大，WSL 裡刪掉的檔案在 C: 上照樣佔著——裡面
# 用 79 GB,C: 上是 82 GB;稀疏的 vhdx 會交還釋出的區塊(配合 install_tool_wsl.zsh 排程的 fstrim)。C: 低於
# 20 GB:分頁檔會長進去,2026-10-22 背景建置就是在 C: 滿了之後因記憶體不足被停掉。.wslconfig 沒有 memory=
# 時 VM 可拿走一半 RAM,Linux 把它塞滿檔案快取，而 Windows 把那些算成已承諾記憶體(2026-10-22 為 14.9 GB)。
set -euo pipefail
script_path="${0:A}"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    sed -n '2,10p' "$script_path" | sed 's/^# \{0,1\}//'
    exit 0
fi

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) ;;
    *) printf 'check_wsl_host.zsh: Windows only (uname -s = %s)\n' "$(uname -s)" >&2; exit 0 ;;
esac

quiet=0
[[ "${1:-}" == "--quiet" ]] && quiet=1
distro="${TEST_WSL_DISTRO:-Ubuntu}"
problems=0

ok() { (( quiet )) || printf '    ok: %s\n' "$1"; }
warn() {
    problems=$(( problems + 1 ))
    printf '!! WSL host: %s\n' "$1" >&2
    shift
    for line in "$@"; do printf '%s\n' "$line" >&2; done
}

# 1. The distribution's vhdx, found through its registry entry.
# 1. 發行版的 vhdx,經由它的登錄項目找到。
lxss='HKCU\Software\Microsoft\Windows\CurrentVersion\Lxss'
base=''
key=''
while IFS= read -r line; do
    case "$line" in
        HKEY_*) key="$line" ;;
        *DistributionName*REG_SZ*)
            if [[ "${line##*REG_SZ}" == *" $distro" ]]; then
                base="$(MSYS2_ARG_CONV_EXCL='*' reg.exe query "$key" /v BasePath 2>/dev/null \
                    | tr -d '\r' | awk -F'REG_SZ' '/BasePath/ { sub(/^[ \t]+/, "", $2); print $2 }' || true)"
            fi
            ;;
    esac
done < <(MSYS2_ARG_CONV_EXCL='*' reg.exe query "$lxss" /s /v DistributionName 2>/dev/null | tr -d '\r' || true)
base="${base#\\\\?\\}"
if [[ -z "$base" ]]; then
    warn "no WSL distribution named $distro in the registry; set TEST_WSL_DISTRO"
else
    vhdx="$base\\ext4.vhdx"
    if [[ ! -e "$(cygpath -u "$vhdx")" ]]; then
        warn "$distro has no ext4.vhdx at $vhdx"
    elif MSYS2_ARG_CONV_EXCL='*' fsutil.exe sparse queryflag "$vhdx" 2>/dev/null | tr -d '\r' \
        | grep -q 'is set as sparse'; then
        ok "$distro's vhdx is sparse ($vhdx)"
    else
        warn "$distro's vhdx is not sparse, so space freed inside WSL stays used on C:" \
            "Run in PowerShell (it stops WSL and everything running in it):" \
            "wsl --shutdown; wsl --manage $distro --set-sparse true"
    fi
fi

# 2. Free space on C:. / 2. C: 的剩餘空間。
free_gb=$(( $(df -k /c | tail -1 | awk '{print $4}') / 1048576 ))
if (( free_gb < 20 )); then
    warn "C: has ${free_gb} GB free (under 20 GB); the pagefile and WSL's vhdx grow into it" \
        "See what is large: du -sh testapp/.compile-work-* testapp/output \"\$LOCALAPPDATA/Temp\""
else
    ok "C: has ${free_gb} GB free"
fi

# 3. .wslconfig. / 3. .wslconfig。
config="$(cygpath -u "$USERPROFILE")/.wslconfig"
if [[ ! -f "$config" ]]; then
    warn "no .wslconfig: WSL may take half of RAM and keep it as file cache" \
        "Create $config with [wsl2] memory=8GB and [experimental] autoMemoryReclaim=DropCache"
else
    section=''
    has_memory=0
    has_reclaim=0
    while IFS= read -r line; do
        line="${line%%#*}"
        if [[ "$line" =~ '^[[:space:]]*\[' ]]; then
            section="${${line#*\[}%%\]*}"
        elif [[ "$section" == wsl2 && "$line" =~ '^[[:space:]]*memory[[:space:]]*=' ]]; then
            has_memory=1
        elif [[ "$section" == experimental && "$line" =~ '^[[:space:]]*autoMemoryReclaim[[:space:]]*=' ]]; then
            has_reclaim=1
        fi
    done < "$config"
    if (( has_memory )); then ok ".wslconfig caps WSL's memory"; else
        warn ".wslconfig has no memory= under [wsl2]; WSL may take half of RAM" \
            "Add under [wsl2] in $config: memory=8GB"
    fi
    if (( has_reclaim )); then ok ".wslconfig sets autoMemoryReclaim"; else
        warn ".wslconfig has no autoMemoryReclaim under [experimental]; WSL keeps its file cache" \
            "Add under [experimental] in $config: autoMemoryReclaim=DropCache"
    fi
fi

(( quiet )) || printf '==> WSL host: %d problem(s)\n' "$problems"
exit 0
