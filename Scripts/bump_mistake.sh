#!/bin/sh
#
# Records another occurrence of a mistakes.md entry, resolving columns BY NAME.
#
# **Use this and not `~/.claude/skills/mistakes_prevention/scripts/counter.zsh`
# against this repository's counter.** That script hardcodes column numbers --
# `C_TOTAL=3; C_SAMEDAY=4; C_SDATE=5; C_DAYS=6; C_LAST=8; C_CORR=9` -- for the
# eleven-column schema `/Volumes/LinuxCS/mistakes_counter.csv2` uses. This tree's
# file has nine columns and no `sameday_max` or `sameday_date`, so every one of
# those constants points somewhere else here.
#
# On 2026-09-23 running it wrote `$(( 2026-09-16 + 1 ))` -- which zsh evaluates
# to 2002 -- into the `last` column, and then wrote the date into `shape`,
# destroying 650 characters of prose. It exited 0 and printed
# `#13 → total=2 last_seen=2026-09-23`, which is the shape the global CSV rule
# exists for: it succeeded, it reported what it had done, and what it reported
# was not what it did. Worse, `counter.zsh check` reads `C_CORR=9`, which is
# `guard` here, so every ✓ it has printed about this file was about the wrong
# column.
#
# **So this resolves names against the header row and refuses when a name is
# missing.** A schema change then fails loudly instead of writing to whatever
# happens to sit at that index, which is the only difference that matters.
#
# 為 mistakes.md 的某一條記錄「再一次發生」,而欄位是**以名稱**解析的。
#
# **對本倉庫的 counter,請用這一支,不要用
# `~/.claude/skills/mistakes_prevention/scripts/counter.zsh`。** 那支腳本把欄號寫死
# ——`C_TOTAL=3; C_SAMEDAY=4; C_SDATE=5; C_DAYS=6; C_LAST=8; C_CORR=9`——那是
# `/Volumes/LinuxCS/mistakes_counter.csv2` 所用的十一欄 schema。這棵樹的檔案只有九欄,
# 沒有 `sameday_max` 也沒有 `sameday_date`,因此上面每一個常數在此處都指向別的地方。
#
# 2026-09-23 跑它的結果是:把 `$(( 2026-09-16 + 1 ))`——zsh 會算成 2002——寫進了 `last` 欄,
# 接著把日期寫進了 `shape`,毀掉 650 個字元的散文。它以 0 結束,並印出
# `#13 → total=2 last_seen=2026-09-23`;而那正是全域 CSV 規則所針對的形狀:
# 它成功了、它回報了自己做過什麼,而它回報的並不是它做的。更糟的是,`counter.zsh check`
# 讀的是 `C_CORR=9`,在此處那是 `guard`——所以它對這個檔案印過的每一個 ✓,講的都是錯的欄位。
#
# **因此這一支會拿名稱去比對表頭列,而在名稱不存在時拒絕。** schema 改變時它會大聲失敗,
# 而不是往「剛好坐在那個索引上的東西」寫進去——而那是唯一重要的差別。
#
# Usage: Scripts/bump_mistake.sh <id> [YYYY-MM-DD]

cd "$(dirname "$0")"/../ || exit 1

file=${SCUI_COUNTER:-mistakes_counter.csv2}
id="$1"
day="${2:-$(date +%F)}"

if [ -z "$id" ]; then
    echo "usage: Scripts/bump_mistake.sh <id> [YYYY-MM-DD]" >&2
    exit 64
fi

# The header comes from csv2's own metadata line rather than from reading line 1
# as text, because line 1 is CSV and splitting it here would be the very thing
# the global rule forbids.
# 表頭取自 csv2 自己的 metadata 行,而不是把第 1 行當文字讀:第 1 行是 CSV,
# 在此處切它,正好就是全域規則所禁止的那件事。
python3 - "$file" "$id" "$day" <<'PY'
import json
import subprocess
import sys

path, wanted_id, day = sys.argv[1], sys.argv[2], sys.argv[3]

lines = subprocess.run(
    ["csv2", "-r", "-i", path, "--json"], capture_output=True, text=True, check=True
).stdout.splitlines()

header = json.loads(lines[0])["meta"]["header"]
index = {}
for name in ("total", "days", "last"):
    if name not in header:
        print(
            f"bump_mistake: the counter has no '{name}' column; its header is {header}.",
            file=sys.stderr,
        )
        print(
            "bump_mistake: refusing to write. A column resolved by position instead "
            "would land on whatever sits there, which is how this script came to exist.",
            file=sys.stderr,
        )
        sys.exit(1)
    index[name] = header.index(name) + 1

row = None
for line in lines[1:]:
    fields = json.loads(line).get("fields")
    if fields and fields.get("id") == wanted_id:
        row = fields
        break

if row is None:
    print(f"bump_mistake: no entry with id {wanted_id}.", file=sys.stderr)
    sys.exit(1)

updates = [(index["total"], str(int(row["total"]) + 1))]
if row["last"] != day:
    updates.append((index["days"], str(int(row["days"]) + 1)))
updates.append((index["last"], day))

for column, value in updates:
    subprocess.run(
        ["csv2", "-update", f"{wanted_id}:{column}", value, "-i", path, "--in-place"],
        check=True,
    )

print(
    f"#{wanted_id} -> total={int(row['total']) + 1} days="
    f"{int(row['days']) + (0 if row['last'] == day else 1)} last={day}"
)
print("This moved three numbers. The entry's prose and mistakes.md still need updating.")
print("這只動了三個數字。條目本文與 mistakes.md 仍然要一併更新。")
PY
