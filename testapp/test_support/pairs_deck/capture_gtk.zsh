#!/bin/zsh
# Capture every test app at rest with GtkBackend on Windows or under WSL, for the
# GTK three-way deck (build_gtk_deck.zsh): Windows GTK, WSL GTK and GTK on macOS.
#
#   zsh testapp/test_support/pairs_deck/capture_gtk.zsh --win                  every built Pn-gtk4.exe, on Windows
#   zsh testapp/test_support/pairs_deck/capture_gtk.zsh --wsl                  every built Pn, inside WSL
#   zsh testapp/test_support/pairs_deck/capture_gtk.zsh --win P10 P88          only those
#   zsh testapp/test_support/pairs_deck/capture_gtk.zsh --win --build P0 P1    rebuild those first
#   zsh testapp/test_support/pairs_deck/capture_gtk.zsh --help                 this text
#
# The same "at rest" as capture_macos.zsh: no action file, the final screenshot
# after --showtime 3. Each run adds one record to testapp/output/gtk-pairs-<win|wsl>.csv2
# (utc,app,exit,image); build_gtk_deck.zsh takes the newest per app. A run with no
# final screenshot is recorded with an empty image, so the deck says so.
# --no-build unless --build: rebuilding every app is hours. But an exe built by
# Swift 6.3.3 (before 2026-10-12) dies at launch on the 6.4 runtime with no window
# and nothing on stderr -- 2026-10-21, P0-P2 all "no visible window matched" --
# so give those --build.
#
# 為 GTK 三方對照簡報(build_gtk_deck.zsh:Windows GTK、WSL GTK、macOS 上的 GTK)在 Windows 或 WSL 內把每支
# 測試 app 以 GtkBackend 靜止時擷取一次。「靜止」與 capture_macos.zsh 相同：不帶動作檔,--showtime 3 之後的最終擷圖。
# 每次執行在 testapp/output/gtk-pairs-<win|wsl>.csv2 加一筆(utc,app,exit,image),build_gtk_deck.zsh 取每支 app
# 最新的一筆。沒有最終擷圖的執行也記下，影像欄留空，讓簡報明講。除非加 --build,否則用 --no-build:全部重建要好幾個
# 小時。但 Swift 6.3.3(2026-10-12 之前)建出的 exe 在 6.4 runtime 上一啟動就死，沒有視窗、stderr 也沒有任何東西——
# 2026-10-21 的 P0-P2 全是「no visible window matched」——那些要加 --build。

emulate -L zsh
setopt pipe_fail
script_path=${0:A}
repo=${script_path:h:h:h:h}

case ${1:-} in
    --help|-h) sed -n '2,18p' $script_path | sed 's/^# \{0,1\}//'; exit 0 ;;
    --win) where=win; flag=-win; export TEST_BACKEND=gtk4 TEST_GPU=default ;;
    --wsl) where=wsl; flag=--wsl ;;
    *) printf 'usage: capture_gtk.zsh --win|--wsl [--build] [Pn ...]  (--help for more)\n' >&2; exit 2 ;;
esac
shift
build=(--no-build)
if [[ ${1:-} == --build ]]; then
    build=()
    shift
fi

source $repo/testapp/test_support/csv2_rows.zsh
out=$repo/testapp/output/gtk-pairs-${where}.csv2
logs=$repo/testapp/output/gtk-pairs-logs-${where}
mkdir -p $logs
[[ -s $out ]] || csv2_new $out 'utc,app,exit,image' 'UTC 時間,app,結束狀態,影像'

apps=("$@")
if (( ! $#apps )); then
    # The apps with a built binary: Pn-gtk4.exe on Windows, Pn in output/ under WSL.
    # 有建好 binary 的 app:Windows 上是 Pn-gtk4.exe,WSL 下是 output/ 裡的 Pn。
    if [[ $where == win ]]; then
        apps=(${${(f)"$(ls $repo/testapp/output | grep -E '^P[0-9][A-Za-z0-9-]*-gtk4\.exe$')"}%-gtk4.exe})
    else
        apps=(${(f)"$(ls $repo/testapp/output | grep -E '^P[0-9][A-Za-z0-9-]*$')"})
    fi
    apps=(${(f)"$(printf '%s\n' $apps | sort -t P -k2,2n -k2,2)"})
fi

for app in $apps; do
    log=$logs/${app}.log
    # A build can take minutes; a capture alone takes seconds.
    # 建置可能要好幾分鐘;單純擷取只要幾秒。
    if (( $#build )); then limit=180; else limit=2400; fi
    timeout $limit zsh $repo/testapp/test.zsh $app $flag $build --showtime 3 > $log 2>&1
    rc=$?
    image=$(grep -a -o '/[^ ]*screenshots/[^ ]*-final-[0-9-]*\.png' $log | tail -1)
    csv2_append $out "$(date -u +%Y-%m-%dT%H:%M:%SZ)" $app $rc "${image#${repo}/}"
    printf '%s exit %s %s\n' $app $rc ${image:t}
done
