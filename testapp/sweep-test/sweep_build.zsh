#!/usr/bin/env zsh
# Builds every P1-P26 test app on Windows, both backends, and prints a table.
#
#   zsh testapp/sweep-test/sweep_build.zsh              all of them, gtk4 then winui
#   zsh testapp/sweep-test/sweep_build.zsh P8 P19       just these
#   zsh testapp/sweep-test/sweep_build.zsh --help
#
# The pair to sweep_drive.zsh. Split from it deliberately: building needs
# nothing from the desktop and runs fine while the workstation is locked, and it
# is most of the wall clock -- roughly 35 of a 40 minute sweep. Driving needs an
# unlocked desktop. A combined sweep locked itself out during a build gap on
# 2026-08-27, because this machine's screen saver is set to 600 seconds with
# "on resume, display logon screen".
#
# Since sweep_drive.zsh synthesises input every few seconds, and synthesised
# input resets the idle timer, the drive half holds the session open by itself.
# So the split is not a workaround; it is what makes the whole thing survivable.
#
# Both backends, because "compiles on one and not the other" is a real class of
# failure -- found on 2026-08-27 with the Swift 6 migration, where the `Gtk`
# module at v6 built on WSL and failed on Windows with two errors.
#
# P6 is excluded: it is the video player, it wants a network fetch and a GPU
# path, and it has its own harness in testapp/test_P6.zsh.
#
# **A FAIL is not always a defect.** P4 fails its gtk4 build with `missing
# required module 'CWinRT'`, by design: it is the WinUI escape-hatch app and
# imports WinUI behind `#if canImport(WinUIBackend)`, which is true even in a
# `-gtk4` build because that flag forces the default backend rather than
# removing the target. Read the note column before filing anything.
#
# 在 Windows 上建置每一個 P1-P26 測試 app，兩種 backend 各一次，並輸出表格。
#
# 與 sweep_drive.zsh 成對。刻意分開：建置完全不需要桌面，工作站鎖定時照樣執行，且它佔去大部分的
# 實際時間——約為 40 分鐘掃描中的 35 分鐘；驅動則需要解鎖的桌面。2026-08-27 實測，合併版本在某次
# 建置的空檔中把自己鎖在門外，因為這台機器的螢幕保護程式設為 600 秒，且勾選了「繼續執行時顯示
# 登入畫面」。
#
# 由於 sweep_drive.zsh 全程每隔數秒就會合成一次輸入，而合成輸入會重置閒置計時器，驅動那一半能
# 自行維持 session 不被鎖定。因此這樣的拆分並非權宜之計，而正是讓整件事得以完成的關鍵。
#
# 兩種 backend 都建，因為「在一個平台編得過、另一個編不過」是真實存在的一類失敗——2026-08-27 於
# Swift 6 遷移中發現：v6 的 `Gtk` 模組在 WSL 建置成功，在 Windows 上卻有兩個錯誤。
#
# 排除 P6：它是影片播放器，需要網路抓取與 GPU 路徑，且已有自己的測試工具 testapp/test_P6.zsh。
#
# **FAIL 未必代表缺陷。** P4 的 gtk4 建置會以 `missing required module 'CWinRT'` 失敗，而這是依設計
# 如此：它是 WinUI escape hatch 的測試 app，以 `#if canImport(WinUIBackend)` 包住 `import WinUI`，
# 而該條件在 `-gtk4` 建置中同樣為真——該旗標強制的是預設 backend，並未移除該 target。在提報任何
# 問題之前，請先讀 note 欄。

set -uo pipefail

script_path="${0:A}"
# testapp/sweep-test/<this> -> testapp/sweep-test -> testapp -> repo root
# testapp/sweep-test/<本檔> -> testapp/sweep-test -> testapp -> repo 根目錄
repo="${${script_path:h}:h:h}"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    sed -n '2,30p' "$script_path" | sed 's/^# \{0,1\}//'
    exit 0
fi

log_dir=/tmp/sweep_build
mkdir -p "$log_dir"

# The same PATH testapp/run.zsh sets, so the GTK DLLs are found. compile.zsh
# sets it for its own build shell only.
# 與 testapp/run.zsh 相同的 PATH，如此才找得到 GTK 的 DLL。compile.zsh 只為它自己的建置 shell
# 設定該路徑。
export PATH="/c/gtk4/bin:$PATH"

if [ "$#" -gt 0 ]; then
    apps=("$@")
else
    apps=(P1 P2 P3 P4 P5 P7 P8 P9 P10 P11 P12 P13 P14 P15 P16 P17 P18 P19 P20 P21 P22 P23 P24 P25 P26)
fi

printf '%-6s %-8s %-8s %s\n' app gtk4 winui note
printf '%s\n' '--------------------------------------------------'

for app in $apps; do
    note=

    if SCUI_DEBUG=1 zsh "$repo/testapp/compile.zsh" "$app" -gtk4 \
        > "$log_dir/$app-gtk4.log" 2>&1
    then
        gtk4=ok
    else
        gtk4=FAIL
        note="gtk4: $(grep -m1 -oE 'error: .*' "$log_dir/$app-gtk4.log" | cut -c1-46)"
    fi

    if SCUI_DEBUG=1 zsh "$repo/testapp/compile.zsh" "$app" \
        > "$log_dir/$app-winui.log" 2>&1
    then
        winui=ok
    else
        winui=FAIL
        note="${note:+$note; }winui: $(grep -m1 -oE 'error: .*' "$log_dir/$app-winui.log" | cut -c1-46)"
    fi

    printf '%-6s %-8s %-8s %s\n' "$app" "$gtk4" "$winui" "$note"
done

# Whichever ran last is what sits in testapp/output, and that is what
# sweep_drive.zsh will launch. Said out loud because the table above does not
# show it and a drive pass against the wrong backend looks like a mass failure.
# 最後執行的那一次建置，就是留在 testapp/output 中的版本，也正是 sweep_drive.zsh 將會啟動的對象。
# 特別寫明，是因為上方表格看不出這件事，而對著錯誤 backend 執行的驅動，看起來會像大規模失敗。
printf '\ntestapp/output now holds the WinUI builds; logs in %s\n' "$log_dir"
exit 0
