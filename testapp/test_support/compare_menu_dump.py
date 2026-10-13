#!/usr/bin/env python3
"""Compare a menu-bar dump with the SwiftUI reference dump of the same mode.

    python3 testapp/test_support/compare_menu_dump.py REFERENCE.txt DUMP.txt [APP NAME IN DUMP]

Both are the indented text P92 and testapp/reference/swiftui-commands/ref.swift write: one item
a line, "---" for a separator, "[@n]" for a shortcut. Before comparing:
  - the reference's app name ("ref") and the dump's are both written as APP;
  - items AppKit adds to any menu titled Edit, on its own, are dropped from both -- Writing Tools,
    AutoFill, Start Dictation, Emoji & Symbols -- with the separators around them;
  - hidden items are dropped (SwiftUI keeps a hidden Toggle Sidebar in Help);
  - a run of separators counts as one, and one at the end of a menu as none: SwiftUI leaves a
    separator for a group that holds nothing.
Exit 0 when the two are the same, 1 with a diff when not.

比對選單列傾印與同一模式的 SwiftUI 基準傾印。比對前:兩邊的 app 名稱都寫成 APP;AppKit 自己加進任何名為 Edit 的選單的
項目(Writing Tools、AutoFill、Start Dictation、Emoji & Symbols)連同前後的分隔線從兩邊移除;隱藏項目移除;
連續的分隔線算一條、選單結尾的不算。相同時結束碼 0,不同時為 1 並印出差異。
"""
import difflib, re, sys

SYSTEM = ("Writing Tools", "AutoFill", "Start Dictation", "Emoji & Symbols")


def normalise(path, app):
    out, skip_depth = [], None
    for raw in open(path, encoding="utf8").read().splitlines():
        if raw.startswith("==="):
            continue
        depth = (len(raw) - len(raw.lstrip(" "))) // 2
        text = raw.strip()
        if skip_depth is not None:
            if depth > skip_depth:
                continue
            skip_depth = None
        if text.endswith("(hidden)"):
            skip_depth = depth
            continue
        if depth == 1 and text.startswith(SYSTEM):
            skip_depth = depth
            continue
        if app:
            text = re.sub(rf"(?<![\w-]){re.escape(app)}(?![\w-])", "APP", text)
        out.append((depth, text))
    cleaned = []
    for i, (depth, text) in enumerate(out):
        if text == "---":
            following = out[i + 1] if i + 1 < len(out) else None
            if not cleaned or cleaned[-1][1] == "---" or cleaned[-1][0] < depth:
                continue
            if following is None or following[0] < depth or following[1] == "---":
                continue
        cleaned.append((depth, text))
    return ["  " * d + t for d, t in cleaned]


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    reference = normalise(sys.argv[1], "ref")
    dump = normalise(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
    if reference == dump:
        print(f"same: {len(dump)} lines")
        return
    sys.stdout.writelines(
        line + "\n" for line in difflib.unified_diff(reference, dump, "reference", "dump", lineterm="", n=1)
    )
    sys.exit(1)


if __name__ == "__main__":
    main()
