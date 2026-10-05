# Writing the sweeps' .csv2 files through csv2. Sourced, not run.
#
#   csv2_new FILE 'en1,en2,...' 'zh1,zh2,...'   start FILE with its two header rows
#   csv2_append FILE field1 field2 ...          add one record, each field quoted
#   csv2_has FILE app scenario                  is there a record with those two first fields?
#   update_stats_record FILE app scenario LOG   the run's "==> update-stats:" line as a record
#
# These files used to be written by Python's csv module, whose writer ends every
# line in CRLF by default, so every sweep CSV in this tree was CRLF on disk while
# the rest of the project writes LF -- found 2026-10-05 when android-sweep.csv2
# turned out to be CRLF throughout. The user's rule is csv2 for every CSV, and
# csv2 is installed here.
#
# Fields are quoted on the way in, with any " doubled (RFC 4180), so a note that
# holds commas and quotes -- error text often does -- stays one field.
#
# 經由 csv2 寫 sweep 的 .csv2 檔。以 source 載入，不直接執行。這些檔案原本由 Python 的 csv 模組寫出，
# 它的 writer 預設每行以 CRLF 結尾，所以本樹每一份 sweep CSV 在磁碟上都是 CRLF,而專案其餘部分寫的是 LF
# ——2026-10-05 發現 android-sweep.csv2 整份都是 CRLF 時才知道。使用者的規則是所有 CSV 都用 csv2,而這裡有
# csv2。欄位寫入時加上引號，其中的 " 加倍(RFC 4180),因此含有逗號與引號的備註——錯誤訊息常常如此——仍是
# 一個欄位。

csv2_quote() {
    print -rn -- "\"${1//\"/\"\"}\""
}

csv2_new() {
    local file="$1" en="$2" zh="$3"
    mkdir -p "${file:h}"
    print -r -- "$en"$'\n'"$zh" | csv2 -si --headers 2 -t -r -o "$file"
}

csv2_append() {
    local file="$1" row="" field
    shift
    for field in "$@"; do
        row+="${row:+,}$(csv2_quote "$field")"
    done
    csv2 -i "$file" --in-place -append "$row"
}

csv2_has() {
    local file="$1" app="$2" scenario="$3"
    [ -f "$file" ] || return 1
    # The JSON csv2 prints, not the CSV: a field never has to be split by hand.
    # Values here are app and file names, which JSON does not escape.
    # 讀 csv2 印出的 JSON,而不是 CSV:欄位永遠不必手動切割。這裡的值是 app 名稱與檔名，JSON 不會跳脫它們。
    csv2 -r --json -i "$file" 2>/dev/null \
        | grep -qF "\"fields\":{\"app\":\"$app\",\"scenario\":\"$scenario\","
}

# `update-stats: count=N median_ms=A p95_ms=B max_ms=C` from a run's log, or a
# record of "none" when the app reported nothing.
# 從一次執行的 log 取出 `update-stats: ...`;app 什麼都沒回報時記為 none。
update_stats_record() {
    local file="$1" app="$2" scenario="$3" log="$4" line count median p95 max
    [ -f "$file" ] || csv2_new "$file" \
        'app,scenario,count,median_ms,p95_ms,max_ms' \
        '應用程式,情境,更新次數,中位數毫秒,p95毫秒,最大毫秒'
    line="$(grep -ao 'update-stats: count=[0-9]*[^[:cntrl:]]*' "$log" 2>/dev/null | tail -1 || true)"
    count="${${line#*count=}%% *}"
    median="${${line#*median_ms=}%% *}"
    p95="${${line#*p95_ms=}%% *}"
    max="${${line#*max_ms=}%% *}"
    if [ -z "$line" ]; then
        csv2_append "$file" "$app" "$scenario" none "" "" ""
    elif [ "$count" = 0 ]; then
        csv2_append "$file" "$app" "$scenario" 0 "" "" ""
    else
        csv2_append "$file" "$app" "$scenario" "$count" "$median" "$p95" "$max"
    fi
}
