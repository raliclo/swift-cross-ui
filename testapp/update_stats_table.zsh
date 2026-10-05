#!/usr/bin/env zsh
# One table of every test app's update timings, Android against iOS against
# macOS, from the files the sweeps write:
#
#   testapp/output/update-stats-android.csv2   sweep_android.zsh
#   testapp/output/update-stats-ios.csv2       sweep_apple.zsh --ios
#   testapp/output/update-stats-macos.csv2     sweep_apple.zsh --macos
#
#   zsh testapp/update_stats_table.zsh            Markdown table on stdout
#   zsh testapp/update_stats_table.zsh -o FILE    also write it to FILE
#
# Each cell is "median / p95 / max ms (n updates)" for that platform's run, with
# ", first F / rest R" inside the parentheses when the run reported the first
# update apart (files written before 2026-10-05 do not have it). An
# app with several action files on one platform shows the one with the most
# updates, and says how many others there were, because the action files are
# written per platform and do not line up one to one. "none" means the app ran
# and reported nothing; a blank cell means no file for that app on that
# platform. The numbers come from UpdateTimings.swift.
#
# Read with `csv2 -r --json`, never by splitting on commas.
#
# 每支測試 app 的更新耗時，Android、iOS、macOS 並列成一張表，資料來自 sweep 寫出的檔案。每格是該平台
# 那次執行的「中位數 / p95 / 最大 ms(n 次更新)」;該次執行有分開回報第一次更新時，括號內再加上
# 「, first F / rest R」(2026-10-05 以前寫的檔案沒有)。一支 app 在同一平台有多份動作檔時，取更新次數最多的
# 那一份，並註明還有幾份，因為動作檔是依平台分別寫的，不是一一對應。「none」表示 app 跑了但什麼都沒
# 回報；空白表示該平台沒有這支 app 的檔案。以 `csv2 -r --json` 讀取，絕不以逗號切割。

set -euo pipefail
script_dir="${0:A:h}"
out=""
if [ "${1:-}" = "-o" ]; then out="${2:?-o needs a file}"; fi

json=""
for platform in android ios macos; do
    f="$script_dir/output/update-stats-$platform.csv2"
    [ -f "$f" ] || continue
    json+="$(csv2 -r --json -i "$f" | sed "s/^/$platform\t/")"$'\n'
done

table="$(print -rn -- "$json" | python3 -c '
import json, re, sys
best = {}
others = {}
for line in sys.stdin:
    if "\t" not in line:
        continue
    platform, payload = line.rstrip("\n").split("\t", 1)
    record = json.loads(payload)
    if "fields" not in record:
        continue
    f = record["fields"]
    key = (f["app"], platform)
    count = int(f["count"]) if f["count"].isdigit() else -1
    others[key] = others.get(key, 0) + 1
    if key not in best or count > best[key][0]:
        best[key] = (count, f)

def order(app):
    m = re.match(r"P(\d+)(.*)", app)
    return (int(m.group(1)), m.group(2)) if m else (10**9, app)

apps = sorted({app for app, _ in best}, key=order)
print("| App | Android | iOS | macOS |")
print("| --- | --- | --- | --- |")
for app in apps:
    cells = []
    for platform in ("android", "ios", "macos"):
        if (app, platform) not in best:
            cells.append("")
            continue
        count, f = best[(app, platform)]
        extra = others[(app, platform)] - 1
        plural = "s" if extra > 1 else ""
        more = f" +{extra} file{plural}" if extra else ""
        if count < 0:
            cells.append("none" + more)
        elif count == 0:
            cells.append("0 updates" + more)
        else:
            median, p95, top = f["median_ms"], f["p95_ms"], f["max_ms"]
            first, rest = f.get("first_ms", ""), f.get("rest_median_ms", "")
            split = ""
            if first:
                split = f", first {first}" + (f" / rest {rest}" if rest else "")
            cells.append(f"{median} / {p95} / {top} ms (n={count}{split}){more}")
    print(f"| {app} | " + " | ".join(cells) + " |")
')"

print -r -- "$table"
if [ -n "$out" ]; then
    print -r -- "$table" > "$out"
    print -u2 "written to $out"
fi
