#!/bin/zsh
# Capture every test app at rest on macOS twice -- AppKitBackend and GtkBackend
# (TEST_BACKEND=gtk4) -- for the GTK / macOS pairs deck (build_deck.zsh).
#
#   zsh testapp/test_support/pairs_deck/capture_macos.zsh            every testapp/P*.swift
#   zsh testapp/test_support/pairs_deck/capture_macos.zsh P10 P88    only those
#
# "At rest" is what the iOS / Android deck shows: the app launched with no
# action file and captured after --showtime seconds, so both sides start from
# the same state. Each run's final screenshot goes into
# testapp/output/macos-pairs.csv2, one record per app and backend; a later run
# of the same pair adds a newer record, and build_deck.zsh takes the newest.
# A run that leaves no final screenshot is recorded with its exit status and no
# image, so the deck can say so instead of leaving the app out.
#
# 為 GTK / macOS 對照簡報(build_deck.zsh)在 macOS 上把每支測試 app 靜止時各拍兩次——AppKitBackend 與
# GtkBackend(TEST_BACKEND=gtk4)。「靜止」與 iOS / Android 簡報相同:不帶動作檔啟動，在 --showtime 秒後擷圖，
# 兩邊從同一個狀態開始。每次執行的最終擷圖寫進 testapp/output/macos-pairs.csv2,每支 app 每個 backend 一筆;
# 同一組合再跑一次會加一筆較新的，build_deck.zsh 取最新的。沒有留下最終擷圖的執行也會記下它的結束狀態、
# 影像欄留空，讓簡報明講，而不是把那支 app 漏掉。

emulate -L zsh
setopt pipe_fail
repo=${0:A:h:h:h:h}
source $repo/testapp/test_support/csv2_rows.zsh
out=$repo/testapp/output/macos-pairs.csv2
logs=$repo/testapp/output/macos-pairs-logs
mkdir -p $logs
[[ -s $out ]] || csv2_new $out 'utc,app,backend,exit,image' 'UTC 時間,app,backend,結束狀態,影像'

apps=("$@")
if (( ! $#apps )); then
    apps=(${${(f)"$(ls $repo/testapp/P*.swift)"}:t:r})
    apps=(${(on)apps})
fi

for app in $apps; do
    for backend in appkit gtk4; do
        log=$logs/$app-$backend.log
        if [[ $backend == gtk4 ]]; then
            TEST_BACKEND=gtk4 zsh $repo/testapp/test.zsh $app --macos --showtime 3 > $log 2>&1
        else
            zsh $repo/testapp/test.zsh $app --macos --showtime 3 > $log 2>&1
        fi
        rc=$?
        image=$(grep -a -o '/[^ ]*screenshots/[^ ]*-final-[0-9-]*\.png' $log | tail -1)
        csv2_append $out "$(date -u +%Y-%m-%dT%H:%M:%SZ)" $app $backend $rc "${image#$repo/}"
        print -r -- "$app $backend exit $rc ${image:t}"
    done
done
