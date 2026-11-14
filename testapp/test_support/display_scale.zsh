#!/usr/bin/env zsh
# display_scale.zsh -- read or set each active Windows display's scale.
#
#   zsh testapp/test_support/display_scale.zsh get        print each display
#   zsh testapp/test_support/display_scale.zsh set 125    set 125%, print, exit 1 if not taken
#   zsh testapp/test_support/display_scale.zsh --help
#
# For todo item 14 (2026-11-14): CI's windows-latest runner is 1920x1080 at
# 100%, testapp/actions/win was measured at 125%, and the user chose to try the
# runner at 125%. The work is in display_scale.c (per-monitor scale through
# DisplayConfigSetDeviceInfo); this builds it with clang on first use, as
# measure_win.zsh does with uia_rects.c. Windows only.
# display_scale.zsh -- 讀取或設定每個作用中 Windows 顯示器的縮放。為 todo 第 14 項(2026-11-14):CI 的 windows-latest runner
# 是 1920x1080、100%,testapp/actions/win 是在 125% 下量的，使用者選擇嘗試把 runner 設成 125%。實際工作在 display_scale.c
# (透過 DisplayConfigSetDeviceInfo 設定每台顯示器的縮放);本腳本在第一次使用時以 clang 建置它，與 measure_win.zsh 建置
# uia_rects.c 的方式相同。只適用於 Windows。
script_path="${0:A}"
if [[ "${1:-}" == --help || $# -lt 1 ]]; then
    sed -n '2,6p' "$script_path" | sed 's/^# \{0,1\}//'
    exit 0
fi
source_file="${script_path:h}/display_scale.c"
tool="${script_path:h:h}/helper/bin/display_scale.exe"
if [ ! -x "$tool" ] || [ "$source_file" -nt "$tool" ]; then
    mkdir -p "${tool:h}"
    clang -O1 "$source_file" -o "$tool" -luser32 -lshcore || { printf 'display_scale build failed\n' >&2; exit 1; }
fi
exec "$tool" "$@"
