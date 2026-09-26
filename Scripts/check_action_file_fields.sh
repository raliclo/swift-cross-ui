#!/bin/sh
#
# Fails when an action file has a row that will not parse, WHETHER OR NOT git
# tracks it yet.
#
# **The existing guards both miss a file that has just been written.**
# `check_action_files.sh` checks that results.csv2 cites files that exist; it
# never opens them. The Swift suite's check is named "every TRACKED action file
# parses" and enumerates `git ls-files`, so a file created five minutes ago is
# outside it. Between writing a file and committing it there was nothing.
#
# Found on 2026-09-16, writing testapp/actions/mac/P23-column-sorting.csv. A
# note read `this must REVERSE, not restart` -- an unquoted comma -- so every
# field after it shifted one place left and `platform` became `not restart`.
# What that looked like from outside:
#
#   the harness            exited 0
#   the app                launched, rendered, and was screenshotted
#   the summary            printed RENDER COMPLETE and the app's own diagnostics
#   my grep of the log     found nothing, because the harness only greps the
#                          summary pattern and this file's name contains none
#                          of its words
#
# The rejection was one line in testapp/output/p23-actionfile.log:
# "failed: line 48: unknown platform 'not restart'". A file that replays nothing
# produces a screenshot of an app in its initial state, which is a screenshot of
# a feature that does not work.
#
# The comma is the global CSV rule this tree already carries, arrived at from
# the other direction: reading a CSV by splitting on commas. Writing one by
# hand has the same failure and no tool had been pointed at it.
#
# 當某個動作檔有一列無法解析時失敗——**無論 git 是否已經追蹤它**。
#
# **既有的兩道防線都漏掉「剛剛才寫出來」的檔案。** `check_action_files.sh` 檢查的是 results.csv2
# 所引用的檔案是否存在,它從不打開它們。Swift 測試套件那一項名為「every TRACKED action file
# parses」,列舉的是 `git ls-files`,因此五分鐘前建立的檔案在它之外。從「寫出一個檔案」到
# 「提交它」之間,什麼都沒有。
#
# 2026-09-16 在寫 testapp/actions/mac/P23-column-sorting.csv 時發現。有一個 note 寫成
# `this must REVERSE, not restart`——一個沒有加引號的逗號——於是它之後的每一欄都左移一格,
# 而 `platform` 變成了 `not restart`。從外面看起來是這樣:
#
#   harness        以 0 結束
#   那支 app       啟動了、算繪了、也被截圖了
#   摘要           印出 RENDER COMPLETE 與 app 自己的診斷
#   我 grep log    什麼也沒找到,因為 harness 只 grep 摘要樣式,而這個檔名不含它的任何一個字
#
# 那次拒絕只是 testapp/output/p23-actionfile.log 裡的一行:
# 「failed: line 48: unknown platform 'not restart'」。一個什麼都沒重放的檔案,產生的是一張
# 「app 處於初始狀態」的截圖——而那就是一張「這個功能不能用」的截圖。
#
# 那個逗號正是這棵樹早已帶著的全域 CSV 規則,只是從另一個方向抵達:那條規則講的是「用逗號切割去
# **讀** CSV」。用手**寫** CSV 有同樣的失敗模式,而先前沒有任何工具被指向它。
set -eu
cd "$(dirname "$0")/.."
exec python3 - "$@" <<'PY'
import csv, glob, pathlib, re, sys

PLATFORMS = {"any", "macos", "windows", "gtk", "ios", "android"}


def known_verbs():
    """Every verb `ActionFile.parseRow` switches on, read out of the source.

    Read rather than listed, so that adding an action does not mean adding it in two places, and
    so this cannot drift away from the parser it stands in for.

    從原始碼讀出、而不是列在這裡:如此新增一個動作就不必在兩個地方各加一次,
    而這個檢查也不會與它所代表的那個解析器漂移。
    """
    source = pathlib.Path("Sources/InputEvent/ActionFile.swift").read_text(encoding="utf-8")
    verbs = set()
    for line in source.splitlines():
        stripped = line.strip()
        if stripped.startswith('case "'):
            verbs.update(re.findall(r'"([a-z]+)"', stripped))
    if not verbs:
        # An empty set would make every row pass, which is the failure mode this whole file is
        # about: a check that finds nothing because it looked at nothing.
        # 一個空集合會讓每一列都通過,而那正是整個檔案所針對的失敗形態:
        # 一個「因為什麼都沒看所以什麼都沒找到」的檢查。
        print(
            "check_action_file_fields: read no verbs from Sources/InputEvent/ActionFile.swift;"
            " refusing to check action names against an empty set.",
            file=sys.stderr,
        )
        sys.exit(1)
    verbs.add("action")
    return verbs


VERBS = known_verbs()

problems = []
for path in sorted(glob.glob("testapp/actions/*/*.csv")):
    with open(path, newline="", encoding="utf-8") as handle:
        rows = list(csv.reader(handle))
    if not rows:
        problems.append((path, 0, "empty file"))
        continue
    header = [h.strip() for h in rows[0]]
    width = len(header)
    # By NAME, because the platform column is not always last: files that drive
    # more than one window carry a trailing `target`, and hard-coding row[-1]
    # reported every one of those as broken on the first run of this script.
    # 依**名稱**取,因為 platform 欄不一定在最後:會驅動不只一個視窗的檔案帶有尾隨的 `target`,
    # 而寫死 row[-1] 會讓本腳本第一次執行時把那些檔案全部回報成壞的。
    platform_at = header.index("platform") if "platform" in header else None
    for number, row in enumerate(rows[1:], start=2):
        if not row or row[0].lstrip().startswith("#"):
            continue
        # **The verb, and this is the check that was missing until 2026-09-26.**
        #
        # A comment whose leading `#` is lost stops being a comment and becomes a data row. The
        # width check below cannot see that: prose has ONE field, fewer than the header, and fewer
        # is legal here because trailing optional columns get left off all the time. So
        # `actions/mac/P72-cursor.csv` went into a commit carrying
        # " `CGWarpMouseCursorPosition` generates no" as row 55 -- which the replay rejects with
        # `unknown action` -- and every guard in this repository said the file was fine.
        #
        # **那個動作名稱,而這正是 2026-09-26 之前缺少的檢查。**
        #
        # 一句「開頭的 `#` 掉了」的註解,就不再是註解,而成為一列資料。下面那個寬度檢查看不見它:
        # 散文只有**一個**欄位,比表頭少;而「少」在此處是合法的,因為尾端的選用欄位本來就經常被省略。
        # 於是 `actions/mac/P72-cursor.csv` 帶著第 55 列「 `CGWarpMouseCursorPosition` generates no」
        # 進了一個 commit——重放會以 `unknown action` 拒絕它——而本倉庫裡每一個守衛都說那個檔案沒問題。
        verb = row[0].strip()
        if verb and verb not in VERBS:
            problems.append((
                path, number,
                f"'{verb[:48]}' is not an action"
                " -- if this is a comment, its leading # is missing",
            ))
            continue
        # Only MORE fields than the header is a defect. Fewer means trailing
        # optional columns were left off, which every file with a `target`
        # column does on the rows that do not need one.
        # 只有「欄位比表頭**多**」才是缺陷。比較少代表尾端的選用欄位被省略了,而每一個帶有
        # `target` 欄的檔案,在不需要它的那些列上都是這麼寫的。
        if len(row) > width:
            problems.append((
                path, number,
                f"{len(row)} fields, header has {width}"
                " -- an unquoted comma in a note shifts every field after it",
            ))
            continue
        if platform_at is not None and platform_at < len(row):
            platform = row[platform_at].strip()
            if platform and not all(p in PLATFORMS for p in platform.split("|")):
                problems.append((
                    path, number,
                    f"platform {platform!r} is not one of {sorted(PLATFORMS)}",
                ))

if not problems:
    sys.exit(0)

print("check_action_file_fields: action files with rows that will not replay.", file=sys.stderr)
print("check_action_file_fields: 有動作檔的某些列無法被重放。", file=sys.stderr)
for path, number, why in problems:
    print(f"  {path}:{number}  {why}", file=sys.stderr)
print(file=sys.stderr)
print("  A note containing a comma must be quoted: \"...REVERSE, not restart\".", file=sys.stderr)
print("  含有逗號的 note 必須加引號:\"...REVERSE, not restart\"。", file=sys.stderr)
sys.exit(1)
PY
