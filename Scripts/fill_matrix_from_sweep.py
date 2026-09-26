#!/usr/bin/env python3
"""Fill one platform column of coverage-matrix.csv2 from a sweep_apple.zsh result.

    python3 Scripts/fill_matrix_from_sweep.py macos testapp/output/macos-sweep.csv2
    python3 Scripts/fill_matrix_from_sweep.py ios testapp/output/ios-sweep.csv2 --write

Without --write it only prints what it would do.

**Only cells that read `-` are touched.** A `-` means "nobody ran this here";
every other mark -- a pass, an amber note, a hammer, a stop, a dash for not
applicable -- is somebody's judgement with a reason in the note, and a sweep
that cannot read the note has no business overwriting it.

**A row becomes a pass only when every app it names has every one of its action
files passing on that platform.** One failing file for an app is enough to
leave the row alone: the row is about a feature, and the file that failed may be
the one that exercises it.

**Rows this cannot decide are listed, not guessed.** `none`, `many`,
`scattered`, ranges such as `P7-P24`, and variants such as `P6-v2` do not name a
set of action files mechanically, so they stay `-` and are printed with the
reason.

The note gains one dated sentence per filled cell, naming the files, so the
evidence can be found from the table.

以一次 sweep_apple.zsh 的結果,填入 coverage-matrix.csv2 的某一個平台欄。

**只動內容是 `-` 的格子。**`-` 代表「沒有人在這裡跑過」;其餘每一個標記——通過、琥珀色註記、鎚子、
停止、表示不適用的橫線——都是某人帶著寫在 note 裡的理由所做的判斷,而一個讀不懂 note 的 sweep 沒有資格
覆寫它。

**一列只有在「它列出的每一支 app 的每一份動作檔都在該平台通過」時才變成通過。**某支 app 只要有一份檔案
失敗,就不動那一列:那一列講的是一項功能,而失敗的那份檔案可能正是驗證它的那一份。

**無法判定的列會被列出來,不會被猜。**`none`、`many`、`scattered`、`P7-P24` 這類範圍、以及 `P6-v2`
這類變體,都無法機械地對應到一組動作檔,因此維持 `-` 並連同理由印出。
"""

import csv
import datetime
import re
import sys

COLUMN = {"macos": "macos_appkit", "ios": "ios_uikit"}
MATRIX = "matrix_coverage/coverage-matrix.csv2"


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    write = "--write" in sys.argv
    # `--exclude=14,27,...`: matrix row numbers (as printed) a person has judged
    # this sweep cannot speak for -- a row about another platform, a row whose
    # capture shows its assertion failing, a row about a defect that needs the
    # capture read. They are left untouched and listed.
    # `--exclude=14,27,...`:由人判斷「這次 sweep 無法替它作證」的矩陣列號(照印出來的編號)——講其他平台
    # 的列、擷圖顯示斷言失敗的列、要讀擷圖才能判斷某個缺陷的列。這些列一律不動,並被列出。
    excluded: set[int] = set()
    for a in sys.argv[1:]:
        if a.startswith("--exclude="):
            excluded |= {int(n) for n in a.split("=", 1)[1].split(",") if n.strip()}
    if len(args) != 2 or args[0] not in COLUMN:
        print(__doc__.splitlines()[0], file=sys.stderr)
        print("usage: fill_matrix_from_sweep.py macos|ios <sweep.csv2> [--write]", file=sys.stderr)
        return 64
    platform, sweep_path = args

    with open(sweep_path, newline="", encoding="utf-8") as handle:
        sweep = list(csv.reader(handle))
    header = sweep[0]
    col = {name: header.index(name) for name in ("app", "action_file", "result")}
    files_by_app: dict[str, list[tuple[str, str]]] = {}
    for row in sweep[2:]:
        files_by_app.setdefault(row[col["app"]], []).append(
            (row[col["action_file"]], row[col["result"]])
        )
    if not files_by_app:
        print(f"{sweep_path} has no result rows; refusing to fill anything", file=sys.stderr)
        return 1

    with open(MATRIX, newline="", encoding="utf-8") as handle:
        matrix = list(csv.reader(handle))
    mheader = matrix[0]
    target = mheader.index(COLUMN[platform])
    covered = mheader.index("covered_by")
    note = mheader.index("note")
    today = datetime.date.today().isoformat()

    filled, left, undecidable, skipped = [], [], [], []
    for index, row in enumerate(matrix[2:], start=2):
        if row[target].strip() != "-":
            continue
        if index in excluded:
            skipped.append((index, row[1]))
            continue
        source = row[covered].strip()
        if re.search(r"P\d+-P?\d+|-v\d|\bnone\b|\bmany\b|\bscattered\b", source) or not source:
            undecidable.append((index, row[1], source or "(empty)"))
            continue
        apps = re.findall(r"\bP\d+\b", source)
        if not apps:
            undecidable.append((index, row[1], source))
            continue
        missing = [a for a in apps if a not in files_by_app]
        failing = [
            f"{name} {result}"
            for a in apps if a in files_by_app
            for name, result in files_by_app[a] if result != "pass"
        ]
        if missing or failing:
            reason = []
            if missing:
                reason.append("no action file run for " + " ".join(missing))
            if failing:
                reason.append("not passing: " + "; ".join(failing))
            left.append((index, row[1], ", ".join(reason)))
            continue
        evidence = ", ".join(name for a in apps for name, _ in files_by_app[a])
        row[target] = "✅"
        row[note] = (row[note] + " " if row[note] else "") + (
            f"{today} {platform} sweep (testapp/sweep_apple.zsh): replayed and captured -- {evidence}."
        )
        filled.append((index, row[1], evidence))

    for index, item, evidence in filled:
        print(f"FILL      row {index}: {item[:70]}  <- {evidence}")
    for index, item, reason in left:
        print(f"LEFT      row {index}: {item[:70]}  ({reason})")
    for index, item, source in undecidable:
        print(f"UNDECIDED row {index}: {item[:70]}  (covered_by: {source})")
    for index, item in skipped:
        print(f"EXCLUDED  row {index}: {item[:70]}")
    print(f"{platform}: {len(filled)} filled, {len(left)} left at '-', "
          f"{len(undecidable)} not mechanically decidable, {len(skipped)} excluded by hand")

    if write:
        # `\n`, because the file is LF and csv.writer's default is `\r\n`: a
        # default write would change every line of the file and report success.
        # Checked by a round trip -- read and rewrite with `\n` is byte-identical.
        # 用 `\n`,因為這份檔案是 LF,而 csv.writer 預設是 `\r\n`:用預設值寫回,會改掉檔案的每一行
        # 並回報成功。以一次往返查證過——讀進再以 `\n` 寫出,逐位元組相同。
        with open(MATRIX, "w", newline="", encoding="utf-8") as handle:
            csv.writer(handle, lineterminator="\n").writerows(matrix)
        print(f"written to {MATRIX}")
    else:
        print("dry run; pass --write to change the matrix")
    return 0


if __name__ == "__main__":
    sys.exit(main())
