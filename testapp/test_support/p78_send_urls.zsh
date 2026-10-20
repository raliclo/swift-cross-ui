#!/usr/bin/env zsh
# p78_send_urls.zsh -- P78's pass condition on Windows: launch it with one URL, send a second
# to the running instance, and check the app logged "received 2", launch then running.
#
#   zsh testapp/test_support/p78_send_urls.zsh             WinUI, then Windows GTK
#   zsh testapp/test_support/p78_send_urls.zsh WinUI       one backend (WinUI or gtk4)
#   zsh testapp/test_support/p78_send_urls.zsh --help
#
# Needs output/P78-<backend>.exe (compile.zsh P78 / compile.zsh -gtk4 P78). An action file
# cannot do this: it has no action that opens a URL, so actions/win/P78-received-twice.actions
# only holds the window for the capture and points here. Exit 0 when every backend passed.
#
# P78 在 Windows 上的通過條件：以一個 URL 啟動它，再送第二個給執行中的實例，檢查 app 記下「received 2」,
# 先 launch 後 running。需要 output/P78-<backend>.exe。action 檔做不到——它沒有開啟 URL 的動作，因此
# actions/win/P78-received-twice.actions 只負責讓視窗停留以供截圖，並指向這裡。全部 backend 通過時以 0 結束。
#
# The second launch is the real test. Both backends used to drop it: GTK never passed argv
# to GApplication, and WinUI read only its own launch (2026-10-20).
# 第二次啟動才是真正的測試。兩個 backend 過去都會丟掉它:GTK 從未把 argv 交給 GApplication,WinUI 只讀得到
# 自己的啟動(2026-10-20)。
script_path="${0:A}"
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    sed -n '2,20p' "$script_path" | sed 's/^# \{0,1\}//'
    exit 0
fi

testapp="${script_path:h:h}"
source "$testapp/test_support/gtk_runtime.zsh"
backends=("$@")
(( $#backends )) || backends=(WinUI gtk4)
# Not mktemp: this zsh and cygpath disagree about /tmp, so the app wrote its log to one place and the
# script read another, and both backends "failed" with nothing received (2026-10-20).
# 不用 mktemp:這支 zsh 與 cygpath 對 /tmp 的看法不同,app 把紀錄寫到一處、腳本卻讀另一處，兩個 backend 都以「什麼都沒收到」
# 「失敗」(2026-10-20)。
work="$testapp/output/p78-urls"
rm -rf -- "$testapp/output/p78-urls"
failed=0

for be in $backends; do
    exe="$testapp/output/P78-$be.exe"
    if [[ ! -x "$exe" ]]; then
        printf '%s: FAIL -- %s is missing\n' "$be" "$exe"
        failed=1
        continue
    fi
    out="$work/$be"
    mkdir -p "$out"
    taskkill -f -im "P78-$be.exe" >/dev/null 2>&1
    (
        [[ $be == gtk4 ]] && export PATH="$(scui_gtk_runtime_path):$PATH"
        export SCUI_DEBUG_EVENTS_DIR="$(cygpath -w "$out")"
        "$exe" --debug scui-testapp://launch >"$out/first.txt" 2>&1 &
        sleep 5
        "$exe" --debug scui-testapp://running >"$out/second.txt" 2>&1
        sleep 3
    )
    taskkill -f -im "P78-$be.exe" >/dev/null 2>&1
    log="$out/p78-debug-events.log"
    got="$(grep -a 'received ' "$log" 2>/dev/null | sed 's/.*received /received /' | tr '\n' ';')"
    if [[ "$got" == "received 1: scui-testapp://launch;received 2: scui-testapp://running;" ]]; then
        printf '%s: PASS -- %s\n' "$be" "$got"
    else
        printf '%s: FAIL -- got "%s"\n' "$be" "${got:-nothing}"
        failed=1
    fi
done
# Kept for reading after a failure; the next run clears it. / 保留以便失敗後查看;下一次執行會清掉。
exit $failed
