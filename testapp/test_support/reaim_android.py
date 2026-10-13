#!/usr/bin/env python3
"""The parsing half of testapp/reaim_android.zsh; see that file for the workflow.

  labels                       uiautomator XML on stdin -> the sorted texts, as one JSON list
  report WORK ACTIONS [--screen WxH --dpi N] [-v]
                               compare the aim run with the record run; writes WORK/aimed.json
  clean WORK                   the stems `write --all` may touch
  rows WORK STEM               line, old x, old y, new x, new y per moved row, bottom-up; exit 1 if not clean
  setxy LINE OX OY NX NY       the action row with its x,y replaced; exit 1 if it does not hold OX,OY

reaim_android.zsh 的解析部分；流程見該檔。
"""
import csv, glob, html, json, os, re, sys

# Texts that differ between two runs of an unchanged app: clocks, counters, timings.
# 同一支未改動的 app 兩次執行之間本來就會不同的文字：時鐘、計數器、計時。
NOISE = re.compile(
    r"^\d+:\d+|clock ticks|frames|raster |PASS|ticks so far|scrolls:|cache dir|values seen|bytes$"
    r"|PRESS|PER |FIXED|FIRST RENDER|resident|first render|backend ->"
)
PARKING = ("move", "hover")


def read(path):
    return open(path, "rb").read().decode("utf8", "replace") if os.path.exists(path) else None


def labels():
    texts = re.findall(r' text="([^"]+)"', sys.stdin.read())
    kept = sorted(html.unescape(t) for t in texts if t not in ("actualView", "rwdView"))
    print(json.dumps(kept, ensure_ascii=False))


def label_sets(work, stem):
    result = {}
    for mode in ("record", "aim", "check"):
        text = read(f"{work}/{mode}-{stem}.labels")
        try:
            result[mode] = json.loads(text) if text is not None else None
        except ValueError:
            result[mode] = None
    return result


def differing(a, b):
    a, b = set(a), set(b)
    return (
        sorted(t for t in a - b if not NOISE.search(t)),
        sorted(t for t in b - a if not NOISE.search(t)),
    )


def report(work, actions, args):
    verbose = "-v" in args
    width, height, dpi, assumed = 1080, 2400, 420, True
    if "--screen" in args and "--dpi" in args:
        width, height = map(int, args[args.index("--screen") + 1].split("x"))
        dpi, assumed = int(args[args.index("--dpi") + 1]), False
    density = dpi / 160
    points = (width / density, height / density)
    print(
        f"screen {width}x{height} px at {dpi} dpi = {points[0]:.0f} x {points[1]:.0f} points"
        + (" (ASSUMED: no device answered)" if assumed else "")
    )
    out = {}
    for path in sorted(glob.glob(f"{work}/aim-*.logcat")):
        stem = os.path.basename(path)[len("aim-"):-len(".logcat")]
        entry = {"flags": [], "rows": []}
        aimed_log = read(path)
        entry["replay"] = "ok" if "-actionfile: replayed" in aimed_log else "no"
        if entry["replay"] != "ok":
            entry["flags"].append("replay did not reach the end")

        sets = label_sets(work, stem)
        if sets["record"] is None or sets["aim"] is None:
            entry["labels"] = "n/a"
            entry["flags"].append("labels missing")
        else:
            if any("isn't responding" in t for t in sets["record"] + sets["aim"]):
                entry["flags"].append("dialog")
            if not sets["record"] and not sets["aim"]:
                entry["flags"].append("labels empty")
            old_only, new_only = differing(sets["record"], sets["aim"])
            entry["labels"] = "same" if not old_only and not new_only else "DIFF"
            entry["old_only"] = [t[:60] for t in old_only[:6]]
            entry["new_only"] = [t[:60] for t in new_only[:6]]
        if sets["check"] is not None and sets["aim"] is not None:
            a, b = differing(sets["aim"], sets["check"])
            entry["check"] = "same" if not a and not b else "DIFF"

        aimed = re.findall(
            r"-actionfile: aimed (\d+) \((-?\d+), (-?\d+)\)(?: -> \((-?\d+), (-?\d+)\))?"
            r" by=([\w-]+)(?: apart=(-?\d+))?( class-changed)?",
            aimed_log,
        )
        rows = []
        action_file = f"{actions}/{stem}.csv"
        if not os.path.exists(action_file):
            entry["flags"].append("no action file")
        else:
            for number, line in enumerate(open(action_file, newline=""), 1):
                if line.startswith("#") or number == 1:
                    continue
                row = next(csv.reader([line]))
                if len(row) > 2 and row[1].strip() and row[2].strip() and row[0] != "scroll":
                    rows.append((number, float(row[1]), float(row[2]), row[0]))
        if len(rows) != len(aimed):
            entry["flags"].append(f"count rows={len(rows)} aimed={len(aimed)}")
        else:
            for (number, x, y, verb), (_, px, py, nx, ny, by, apart, changed) in zip(rows, aimed):
                if changed:
                    entry["flags"].append(f"class-changed line {number}")
                if by == "unmatched" or nx == "":
                    entry["flags"].append(f"unmatched line {number}")
                    continue
                if by != "inside":
                    entry["flags"].append(f"{by} line {number}")
                new_x = x + round((int(nx) - int(px)) / density)
                new_y = y + round((int(ny) - int(py)) / density)
                if verb in PARKING and not (0 <= new_x <= points[0] and 0 <= new_y <= points[1]):
                    entry["flags"].append(f"park off screen line {number}")
                entry["rows"].append([number, x, y, new_x, new_y, by, apart])
        out[stem] = entry
        if verbose or entry["flags"] or entry["labels"] != "same" or entry.get("check") == "DIFF":
            moved = sum(1 for r in entry["rows"] if (r[1], r[2]) != (r[3], r[4]))
            print(
                f"{stem:50} replay={entry['replay']} labels={entry['labels']}"
                f" check={entry.get('check', '-')} moved={moved} flags={entry['flags']}"
            )
            if entry["labels"] == "DIFF":
                print("      record only:", entry["old_only"], "\n      aim only:   ", entry["new_only"])
    json.dump(out, open(f"{work}/aimed.json", "w"))
    clean = [s for s, e in out.items() if not e["flags"]]
    print(f"{len(out)} files; {len(clean)} clean; {len(out) - len(clean)} to re-aim by hand")
    print("labels=DIFF on a clean file is not a refusal: the layout changed, so look at the capture.")


def load(work):
    return json.load(open(f"{work}/aimed.json"))


def clean(work):
    print(" ".join(s for s, e in load(work).items() if not e["flags"]))


def number(value):
    return str(int(value)) if float(value) == int(value) else str(value)


def moved_rows(work, stem):
    entry = load(work).get(stem)
    if entry is None:
        sys.exit(f"{stem}: not in the report")
    if entry["flags"]:
        sys.exit(f"{stem}: refused, re-aim by hand -- {entry['flags']}")
    for row in sorted(entry["rows"], key=lambda r: -r[0]):
        if (row[1], row[2]) != (row[3], row[4]):
            print(row[0], number(row[1]), number(row[2]), number(row[3]), number(row[4]), sep="\t")


def setxy(line, old_x, old_y, new_x, new_y):
    fields = next(csv.reader([line]))
    if not (float(fields[1]) == float(old_x) and float(fields[2]) == float(old_y)):
        sys.exit(f"the row holds ({fields[1]}, {fields[2]}), not ({old_x}, {old_y}); report again")
    prefix = f"{fields[0]},{fields[1]},{fields[2]},"
    if not line.startswith(prefix):
        sys.exit("the row does not begin with its own verb,x,y")
    sys.stdout.write(f"{fields[0]},{new_x},{new_y}," + line[len(prefix):])


if __name__ == "__main__":
    command, rest = (sys.argv[1] if len(sys.argv) > 1 else ""), sys.argv[2:]
    if command == "labels":
        labels()
    elif command == "report" and len(rest) >= 2:
        report(rest[0], rest[1], rest[2:])
    elif command == "clean" and len(rest) == 1:
        clean(rest[0])
    elif command == "rows" and len(rest) == 2:
        moved_rows(rest[0], rest[1])
    elif command == "setxy" and len(rest) == 5:
        setxy(*rest)
    else:
        sys.exit(__doc__)
