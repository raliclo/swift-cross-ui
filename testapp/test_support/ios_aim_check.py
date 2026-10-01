#!/usr/bin/env python3
"""Does each positioned row of an iOS action file land on the control it names?

    python3 testapp/test_support/ios_aim_check.py <tree dump> <action file>...

The tree dump is the output of
    zsh testapp/test_ios.zsh <Pn> --no-build --dump-tree --no-showtime --actionfile <probe>
with a probe file that only sleeps, so the tree is the launch screen.

A sweep that replays and captures says nothing about aim: a tap on empty space is
not an error. This reads the accessibility tree XCUITest prints -- lines like
    Button, 0x..., {{386.0, 175.0}, {44.0, 22.0}}, label: 'Reset'
-- and, for every click / longpress / doubleclick / mousedown row with a point,
reports the element under that point and whether its label matches the target
the row's note names (the text before " -- ", or a quoted name). Rows after a
scroll, drag, rotation or anything that changes the screen are reported as
AFTER: the launch tree cannot say where they land, so they need a capture.

Written 2026-10-01, when UIKitBackend began running at native size (440x956
instead of a zoomed 428x926) and every iOS file's aim had to be re-checked. The
2026-09-27 table in testapp/measurements/ios-aim-20260927.txt was made the same
way by hand; this is that procedure kept.

一列有座標的 iOS 動作檔，是否點在它所指名的控制項上？重放與擷圖成功，不代表點中目標——點在空白處
不是錯誤。本工具讀取 XCUITest 印出的無障礙樹，對每一列 click / longpress / doubleclick / mousedown
回報座標底下的元素，並比對其標籤與該列註記指名的目標（" -- " 之前的文字，或引號中的名稱）。發生在
捲動、拖曳、旋轉等改變畫面之後的列，標為 AFTER：啟動時的樹無法說明它們落在哪裡，需要擷圖確認。
"""

import csv
import re
import sys

ELEMENT = re.compile(
    r"^(?P<indent>\s*)(?P<type>[A-Za-z]+), 0x[0-9a-f]+, "
    r"\{\{(?P<x>-?[\d.]+), (?P<y>-?[\d.]+)\}, \{(?P<w>[\d.]+), (?P<h>[\d.]+)\}\}"
    r"(?:, (?:identifier: '[^']*', )?label: '(?P<label>[^']*)')?"
    # Anything after the label: a value, or a trailing ", Disabled" -- which a
    # first version did not allow, so every disabled control was skipped.
    r"(?:,.*)?$"
)
CONTAINERS = {"Application", "Window", "Other", "ScrollView", "Group", "Cell", "Table"}
POSITIONED = {"click", "longpress", "doubleclick", "mousedown"}
SCREEN_CHANGING = {"scroll", "mouseup", "orient", "pinch", "rotate", "key", "keydown"}


def read_tree(path):
    elements = []
    for line in open(path, encoding="utf-8", errors="replace"):
        m = ELEMENT.match(line.rstrip("\n"))
        if not m:
            continue
        x, y, w, h = (float(m.group(k)) for k in ("x", "y", "w", "h"))
        elements.append({
            "type": m.group("type"),
            "frame": (x, y, w, h),
            "label": m.group("label") or "",
            "depth": len(m.group("indent")),
        })
    return elements


def window_origin(elements):
    for e in elements:
        if e["type"] == "Window":
            return e["frame"][0], e["frame"][1]
    return 0.0, 0.0


def under(elements, px, py):
    hits = [
        e for e in elements
        if e["type"] not in CONTAINERS
        and e["frame"][0] <= px <= e["frame"][0] + e["frame"][2]
        and e["frame"][1] <= py <= e["frame"][1] + e["frame"][3]
    ]
    return min(hits, key=lambda e: e["frame"][2] * e["frame"][3]) if hits else None


def target_name(note):
    # A leading "(re-aimed ...)" is a measurement record, not the target.
    note = re.sub(r"^\([^)]*\)\s*", "", note.strip())
    quoted = re.findall(r'"([^"]{2,60})"', note)
    head = note.split(" -- ")[0].strip()
    head = re.sub(r"^(the|press|tap|click)\s+", "", head, flags=re.I)
    return quoted, head


def matches(label, quoted, head):
    if not label:
        return False
    l = label.lower()
    if any(q.lower() in l or l in q.lower() for q in quoted):
        return True
    return bool(head) and (head.lower() in l or l in head.lower())


def candidate(elements, quoted, head):
    for e in elements:
        if e["type"] in CONTAINERS:
            continue
        if matches(e["label"], quoted, head):
            return e
    return None


def describe(e):
    return f"{e['type']} '{e['label'][:28]}'" if e else "nothing"


def main(tree_path, action_paths):
    elements = read_tree(tree_path)
    ox, oy = window_origin(elements)
    totals = {"HIT": 0, "MISS": 0, "AFTER": 0, "UNNAMED": 0}
    for path in action_paths:
        changed = False
        with open(path, newline="", encoding="utf-8") as f:
            for lineno, row in enumerate(csv.reader(f), 1):
                if not row or row[0].startswith("#") or row[0] == "action":
                    continue
                verb = row[0].strip()
                if verb in SCREEN_CHANGING:
                    changed = True
                if verb not in POSITIONED or not row[1] or not row[2]:
                    continue
                x, y = float(row[1]), float(row[2])
                note = row[7] if len(row) > 7 else ""
                quoted, head = target_name(note)
                name = path.rsplit("/", 1)[-1]
                if changed:
                    status = "AFTER"
                    detail = "screen changed earlier in the file -- check the capture"
                else:
                    now = under(elements, x + ox, y + oy)
                    if not quoted and not head:
                        status, detail = "UNNAMED", f"now={describe(now)}"
                    elif now and matches(now["label"], quoted, head):
                        status, detail = "HIT", f"now={describe(now)}"
                    else:
                        status = "MISS"
                        c = candidate(elements, quoted, head)
                        if c:
                            cx = c["frame"][0] + c["frame"][2] / 2 - ox
                            cy = c["frame"][1] + c["frame"][3] / 2 - oy
                            detail = (f"now={describe(now)} -> {describe(c)} "
                                      f"at ({cx:.0f},{cy:.0f})")
                        else:
                            detail = f"now={describe(now)} -> no element named like '{head[:30]}'"
                totals[status] += 1
                print(f"{status:7} {name}:{lineno} {verb} ({x:.0f},{y:.0f}) {detail}")
                if verb in ("click", "longpress", "doubleclick") and "tab" in note.lower():
                    changed = True
    print("TOTAL " + " ".join(f"{k}={v}" for k, v in totals.items()))


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__.split("\n\n")[0], file=sys.stderr)
        sys.exit(64)
    main(sys.argv[1], sys.argv[2:])
