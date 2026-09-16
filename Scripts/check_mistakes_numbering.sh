#!/bin/sh
#
# Fails when mistakes.md and mistakes_counter.csv2 disagree about numbering.
#
# **Two machines writing on the same day land on the same number routinely.** The
# number is "highest so far, plus one", and neither side sees the other until the
# merge. It happened twice on 2026-09-16, at entries 8 and 13.
#
# One of those two merges CONFLICTED and one did not, and the difference is only
# where in the file each side wrote: appending at the end merges clean and never
# asks, while touching the same line stops and demands a decision. The correct
# resolution is identical either way -- keep both, renumber by date -- so the
# clean merge is the dangerous one. It is the one where nobody is asked.
#
# 當 mistakes.md 與 mistakes_counter.csv2 在編號上各說各話時失敗。
#
# **兩台機器在同一天各自寫下一條、拿到同一個編號,是常態。** 編號取自「目前最大值 +1」,而兩邊在合併
# 之前都看不到對方。2026-09-16 一天之內就發生兩次,在第 8 條與第 13 條。
#
# 那兩次合併中,一次**衝突**、一次沒有,而差別只在於兩邊各寫在檔案的哪個位置:追加在檔尾會乾淨合併、
# 完全不問;改到同一行才會停下來要人決定。兩種情況的正確解法**相同**——兩條都留、依日期重新編號——
# 因此「乾淨的那一次」才是危險的那一次:它不會問任何人。
python3 - "$@" <<'PY'
import csv, re, sys, pathlib
from collections import Counter

md = pathlib.Path("mistakes.md")
counter = pathlib.Path("mistakes_counter.csv2")
if not md.exists() or not counter.exists():
    sys.exit(0)

problems = []

# **`encoding="utf-8"` on BOTH reads, because Python does not default to it.**
# `open()` uses the locale's preferred encoding, which on this Windows machine is
# cp950, and both files are UTF-8 with Traditional Chinese in every entry. The
# script died on its first Windows run with
# `UnicodeDecodeError: 'cp950' codec can't decode byte 0x99` -- before reaching a
# single check, so a repository with duplicate numbers would have looked exactly
# the same. Measured 2026-09-16.
#
# **兩個讀取都要指定 `encoding="utf-8"`,因為 Python 不會預設用它。** `open()` 採用的是
# locale 的偏好編碼,在這台 Windows 上是 cp950,而這兩個檔案都是 UTF-8、而且每一條都有中文。
# 本腳本在 Windows 上第一次執行就以
# `UnicodeDecodeError: 'cp950' codec can't decode byte 0x99` 死掉——**在跑到任何一項檢查之前**,
# 因此一個編號重複的 repository 看起來會與此完全相同。2026-09-16 實測。
rows = [
    r
    for r in list(csv.reader(counter.open(newline="", encoding="utf-8")))[2:]
    if r and r[0].strip()
]
ids = [r[0].strip() for r in rows]
for number, count in sorted(Counter(ids).items(), key=lambda kv: int(kv[0]) if kv[0].isdigit() else 0):
    if count > 1:
        titles = [r[1][:60] for r in rows if r[0].strip() == number]
        problems.append(f"counter has id {number} {count} times: " + " | ".join(titles))

# Every id in the counter needs a heading in the prose, and the other way round.
# Either half alone is a record that reads complete and is not.
# 計數檔裡的每一個 id 都需要散文裡的一個標題,反之亦然。只有其中一半的紀錄,讀起來是完整的,
# 而它不是。
headings = Counter(re.findall(r"^## (\d+)\.", md.read_text(encoding="utf-8"), re.M))
for number in sorted(set(ids) - set(headings), key=int):
    problems.append(f"counter id {number} has no '## {number}.' heading in mistakes.md")
for number in sorted(set(headings) - set(ids), key=int):
    problems.append(f"mistakes.md has '## {number}.' with no row in the counter")

if not problems:
    sys.exit(0)

print("check_mistakes_numbering: the record disagrees with itself.", file=sys.stderr)
print("check_mistakes_numbering: 這份紀錄自相矛盾。", file=sys.stderr)
print("", file=sys.stderr)
for p in problems:
    print(f"  {p}", file=sys.stderr)
print("", file=sys.stderr)
print("  Keep BOTH entries and renumber by date -- see the rule at the top of", file=sys.stderr)
print("  mistakes.md. Never let one overwrite the other: an entry records", file=sys.stderr)
print("  something that happened, and deleting it claims it did not.", file=sys.stderr)
print("  兩條都要留,並依日期重新編號——見 mistakes.md 開頭的規則。絕不要讓一邊蓋掉另一邊:", file=sys.stderr)
print("  一條紀錄記的是一件發生過的事,刪掉它等於宣稱它沒有發生。", file=sys.stderr)
sys.exit(1)
PY
