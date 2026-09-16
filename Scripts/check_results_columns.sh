#!/bin/sh
#
# Fails when results.csv2 records a platform/backend pair that
# matrix_coverage/coverage.zsh has no column for.
#
# **Such a row is not wrong, it is INVISIBLE.** The row is appended, committed,
# and reads as evidence; the generated matrix simply never shows it, because the
# pivot has nowhere to put it. Nothing about the row looks off -- the app ran,
# the note is true, the date is right.
#
# coverage.zsh does report these on stderr, and that was not enough: on
# 2026-09-16 it printed `29 run(s) recorded as macos/appkit match no column` and
# the run continued. Three of those 29 had been written minutes earlier in that
# same session, by someone who then said the result was recorded. A warning that
# scrolls past is a warning nobody reads, which is why this exits non-zero.
#
# 當 results.csv2 記下一個 matrix_coverage/coverage.zsh 沒有對應欄位的 platform/backend 組合時失敗。
#
# **那樣的一列不是錯的,它是隱形的。** 那一列會被追加、提交,而且讀起來就是證據;只是產生出來的矩陣
# 永遠不會顯示它——因為那個樞紐分析沒有地方放它。那一列本身看不出任何異狀:app 跑過了、備註是真的、
# 日期也對。
#
# coverage.zsh 確實會在 stderr 上回報這件事,而那不夠:2026-09-16 它印出
# `29 run(s) recorded as macos/appkit match no column`,而流程照樣繼續。那 29 列裡有三列,是同一個
# session 幾分鐘前寫下的——而那個人隨後宣稱「結果已記錄」。一個會捲過去的警告,就是一個沒有人會讀的
# 警告;這正是此處以非零結束的原因。
python3 - "$@" <<'PY'
import csv, re, sys, pathlib

results = pathlib.Path("matrix_coverage/results.csv2")
script = pathlib.Path("matrix_coverage/coverage.zsh")
if not results.exists() or not script.exists():
    sys.exit(0)

# The columns, read from the renderer itself rather than duplicated here.
# Duplicating them would mean this check and the matrix could disagree, and the
# check would then pass on rows the matrix still drops.
# 這些欄位是從那個 renderer 自己讀出來的,而不是在此另抄一份。另抄一份會讓這道檢查與那個矩陣可能
# 各說各話,而這道檢查便會在「矩陣仍然會丟掉」的列上通過。
known = set(re.findall(r'key\[\d+\]\s*=\s*"([^"]+)"', script.read_text()))
if not known:
    print("check_results_columns: found no key[] entries in coverage.zsh", file=sys.stderr)
    sys.exit(1)

rows = list(csv.reader(results.open(newline="")))[2:]
bad = {}
for i, r in enumerate(rows, start=3):
    if len(r) < 3 or not r[1] or r[1] == "-":
        continue
    pair = f"{r[1]}/{r[2]}"
    if pair not in known:
        bad.setdefault(pair, []).append((i, r[3] if len(r) > 3 else "?"))

if not bad:
    sys.exit(0)

print("check_results_columns: results.csv2 has pairs the matrix cannot show.", file=sys.stderr)
print("check_results_columns: results.csv2 中有矩陣顯示不出來的 platform/backend 組合。", file=sys.stderr)
print("", file=sys.stderr)
for pair, hits in sorted(bad.items()):
    apps = ", ".join(sorted({a for _, a in hits})[:6])
    print(f"  {pair}  --  {len(hits)} row(s): {apps}", file=sys.stderr)
print("", file=sys.stderr)
print("  Known columns: " + ", ".join(sorted(known)), file=sys.stderr)
print("  Fix the row's platform/backend, or add a column to coverage.zsh.", file=sys.stderr)
print("  A row with no column is appended, committed, and never displayed.", file=sys.stderr)
print("  請修正該列的 platform/backend,或為 coverage.zsh 增加一個欄位。", file=sys.stderr)
print("  一個沒有欄位的列會被追加、提交,然後永遠不被顯示。", file=sys.stderr)
sys.exit(1)
PY
