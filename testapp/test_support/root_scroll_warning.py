#!/usr/bin/env python3
"""Warns at build time when an app's root view is a ScrollView and its scene sets .defaultSize.

    python3 testapp/test_support/root_scroll_warning.py testapp/P21.swift

On a phone in actualView an app is laid out at its .defaultSize. A root ScrollView with
more content than that height is grown to the screen's height (RootScrollHost, iOS and
Android, 2026-10-12), so the height the scene asks for is not the height on screen. The
framework cannot say so when it compiles: the root is a view whose `body` is opaque, and
the screen is only known when the app runs. This reads the source instead, and prints one
compiler-style line per finding. It never fails a build.

建置時，當 app 的根 view 是 ScrollView 而 scene 又設了 .defaultSize 時發出警告。手機上的 actualView 以
.defaultSize 排版;內容比那個高度多的根 ScrollView 會長到螢幕的高度(RootScrollHost,iOS 與 Android,
2026-10-12),所以 scene 要求的高度不是畫面上的高度。框架在編譯時說不出這件事:根是一個 `body` 不透明的 view,
而螢幕要到 app 執行時才知道。本腳本改讀原始碼，每個發現印一行編譯器格式的訊息，而且永遠不會讓建置失敗。
"""
import os
import re
import sys


def code(line):
    text = line.strip()
    return text if text and not text.startswith("//") else ""


def first_statement(lines, start):
    """The first line of code after `start`, as (index, text)."""
    for i in range(start + 1, len(lines)):
        if code(lines[i]):
            return i, code(lines[i])
    return None, ""


def main(path):
    lines = open(path, encoding="utf-8").read().split("\n")
    name = os.path.basename(path)
    for g, line in enumerate(lines):
        if "WindowGroup" not in code(line):
            continue
        size = next(
            (
                (i, m)
                for i in range(g, min(g + 60, len(lines)))
                for m in [re.search(r"\.defaultSize\(width:\s*(\d+),\s*height:\s*(\d+)\)", lines[i])]
                if m
            ),
            None,
        )
        if size is None:
            continue
        root = None
        for i in range(g + 1, size[0]):
            m = re.match(r"([A-Z]\w*)\s*[({]", code(lines[i]))
            if m:
                root = (i, m.group(1))
                break
        if root is None:
            continue
        at = root[0] if root[1] == "ScrollView" else None
        if at is None:
            decl = next(
                (i for i, l in enumerate(lines) if re.match(rf"\s*struct {root[1]}\b", l)), None
            )
            body = decl is not None and next(
                (i for i in range(decl, len(lines)) if "var body: some View" in lines[i]), None
            )
            if body:
                i, text = first_statement(lines, body)
                if text.startswith("ScrollView"):
                    at = i
        if at is None:
            continue
        height = size[1].group(2)
        print(
            f"{name}:{at + 1}: warning: the root view is a ScrollView and the scene asks for "
            f".defaultSize(height: {height}) on line {size[0] + 1}; on a phone (actualView) a root "
            f"ScrollView with more content than {height} is grown to the screen's height."
        )
        print(
            f"{name}:{at + 1}: 警告:根 view 是 ScrollView,而 scene 在第 {size[0] + 1} 行要求 "
            f".defaultSize(height: {height});在手機上(actualView),內容超過 {height} 的根 ScrollView 會長到螢幕的高度。"
        )


if __name__ == "__main__":
    for arg in sys.argv[1:]:
        try:
            main(arg)
        except OSError as error:
            print(f"root_scroll_warning: {error}", file=sys.stderr)
