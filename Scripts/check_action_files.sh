#!/bin/sh
#
# Fails when results.csv2 cites an action file that is not in the tree.
#
# **A `(VERIFIED …)` note is a claim that someone ran something and looked.**
# Two artefacts back that claim and they are not equal:
#
#   the screenshot     names where the evidence WAS. `/testapp/output/` is
#                      gitignored, so it exists on one machine and nowhere else.
#                      Nobody else can open it.
#   the action file    is the reproducible half. A reader re-runs it and takes
#                      their own screenshot.
#
# So the action file is the one that has to survive, and a citation pointing at
# a file that is not tracked is a claim nobody can check -- while reading
# exactly like one they can.
#
# Found on 2026-09-09: P34's first click was verified by a file that spent a day
# in a scratch directory, and the row citing it was already committed.
#
# 當 results.csv2 引用了一個不在樹裡的動作檔時，失敗。
#
# **一句 `(VERIFIED …)` 是「有人跑過某件事、而且看了」這個主張。** 支撐該主張的產物有兩種，而它們並不
# 對等：
#
#   截圖        說明證據當時**在哪裡**。`/testapp/output/` 被 gitignore，因此它存在於一台機器上、
#               而不存在於其他任何地方。別人打不開它。
#   動作檔      才是可重現的那一半。讀者重跑它，並拍下自己的截圖。
#
# 因此必須存活下來的是動作檔；而一個指向未被追蹤之檔案的引用，是一個沒有人能檢查的主張——但它讀起來
# 與一個可以檢查的主張完全相同。
#
# 2026-09-09 發現：P34 的第一次點擊是由一個在暫存目錄裡待了一天的檔案驗證的，而引用它的那一列早已提交。

cd "$(dirname "$0")"/../ || exit 1

python3 - "$@" <<'PY'
import csv, glob, os, re, sys

rows = list(csv.reader(open("matrix_coverage/results.csv2", newline="")))
present = {os.path.basename(p) for p in glob.glob("testapp/actions/*/*.csv")}

missing = {}
for number, row in enumerate(rows[2:], start=3):
    if len(row) <= 8:
        continue
    for name in re.findall(r"[A-Za-z0-9][A-Za-z0-9_.-]*\.csv", row[8]):
        if name not in present:
            missing.setdefault(name, []).append((number, row[3]))

if not missing:
    sys.exit(0)

print("check_action_files: results.csv2 cites action files that are not in the tree.",
      file=sys.stderr)
print("check_action_files: results.csv2 引用了不在樹裡的動作檔。", file=sys.stderr)
for name, uses in sorted(missing.items()):
    where = ", ".join(f"row {n} ({app})" for n, app in uses[:3])
    more = "" if len(uses) <= 3 else f" and {len(uses) - 3} more"
    print(f"  {name}  --  {where}{more}", file=sys.stderr)
print(file=sys.stderr)
print("  Either add the file under testapp/actions/, or correct the note to name", file=sys.stderr)
print("  the file that actually produced the run. Do not delete the row.", file=sys.stderr)
print("  請把該檔案加進 testapp/actions/，或更正該備註以指出真正產生那次執行的檔案。", file=sys.stderr)
print("  不要刪除那一列。", file=sys.stderr)
sys.exit(1)
PY
