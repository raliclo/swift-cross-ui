"""Compose screenshots side by side without inventing a colour the apps use.

    python3 test_support/contact_sheet.py out.png a.png b.png
    python3 test_support/contact_sheet.py out.png --cols 7 --label p*.png

**The separator is chosen, not fixed.** These sheets used a magenta gutter,
`(255, 0, 255)`, on the reasoning that nothing would render it. That reasoning
was never checked and it is wrong here: of the 45 Android captures taken on
2026-09-06, **28 contain that colour in their own content**, and P17 alone has
over five thousand such pixels in a 160x356 sample. A gutter that a reader has
to distinguish from the screenshot beside it is worse than no gutter, because it
looks like part of the app.

So the gutter is picked per sheet, from a short list, by counting: the first
candidate that appears nowhere in any of the images being composed wins, and the
chosen value is printed. If every candidate appears -- which has not happened
yet -- it falls back to the least common of them and says so, because a silent
collision is the thing this exists to stop.

以並排方式合成截圖，而不憑空發明一個 app 也在用的顏色。

**分隔色是選出來的，不是寫死的。** 這些對照圖原本使用洋紅色的間隔 `(255, 0, 255)`，理由是「應該不會
有東西畫這個顏色」。那個理由從未被查證，而且在此處是錯的：2026-09-06 拍下的 45 張 Android 擷取中，
**有 28 張的內容本身就含有該顏色**，光是 P17 在一個 160x356 的取樣裡就超過五千個那樣的像素。一個
「讀者必須把它與旁邊的截圖區分開來」的間隔，比沒有間隔更糟，因為它看起來像是 app 的一部分。

因此間隔色是逐張選定的：從一份簡短的候選清單中，取第一個「在所有被合成的影像中都不出現」的顏色，
並印出所選的值。若每一個候選都出現過——目前尚未發生——則退回到其中最罕見的那一個，並明說此事，
因為「靜默的撞色」正是本檔存在所要阻止的東西。
"""

import sys
from PIL import Image, ImageDraw

# Ordinary, unsaturated, and unlike anything a control draws. The point is not
# that these are unusable by an app -- the point is that the code checks.
# 一般、低飽和，且不像任何控制項會畫的東西。重點不在於這些顏色 app 一定不會用，而在於程式會去檢查。
CANDIDATES = [
    (255, 214, 0),  # amber
    (0, 200, 160),  # teal
    (140, 90, 40),  # brown
    (90, 90, 90),  # mid grey
]


def pick_gutter(images, samples=40000):
    """The first candidate absent from every image, with its count reported."""
    counts = []
    for candidate in CANDIDATES:
        total = 0
        for image in images:
            small = image.convert("RGB")
            if small.width * small.height > samples:
                ratio = (samples / (small.width * small.height)) ** 0.5
                small = small.resize(
                    (max(1, int(small.width * ratio)), max(1, int(small.height * ratio)))
                )
            total += sum(1 for pixel in small.get_flattened_data() if pixel == candidate)
        if total == 0:
            print(f"gutter {candidate}: absent from all {len(images)} images")
            return candidate
        counts.append((total, candidate))
    counts.sort()
    print(
        f"gutter {counts[0][1]}: every candidate collides; this one is rarest "
        f"at {counts[0][0]} pixels -- read the seams with that in mind"
    )
    return counts[0][1]


def sheet(paths, out, cols=2, labels=False, tile=(176, 391), gap=8):
    images = [Image.open(p).convert("RGB") for p in paths]
    gutter = pick_gutter(images)
    thumbs = []
    for image in images:
        copy = image.copy()
        copy.thumbnail(tile)
        thumbs.append(copy)
    rows = (len(thumbs) + cols - 1) // cols
    label_height = 22 if labels else 0
    width = cols * (tile[0] + gap) + gap
    height = rows * (tile[1] + gap + label_height) + gap
    out_image = Image.new("RGB", (width, height), gutter)
    draw = ImageDraw.Draw(out_image)
    for index, thumb in enumerate(thumbs):
        x = gap + (index % cols) * (tile[0] + gap)
        y = gap + (index // cols) * (tile[1] + gap + label_height)
        out_image.paste(thumb, (x, y))
        if labels:
            name = paths[index].split("/")[-1].split("-")[0]
            draw.text((x + 3, y + thumb.height + 4), name, fill=(255, 255, 255))
    out_image.save(out)
    print(f"wrote {out} {out_image.size} from {len(paths)} images")


if __name__ == "__main__":
    args = sys.argv[1:]
    if len(args) < 2:
        print(__doc__.splitlines()[0])
        raise SystemExit(64)
    out = args[0]
    rest = args[1:]
    cols, labels = 2, False
    files = []
    i = 0
    while i < len(rest):
        if rest[i] == "--cols":
            cols = int(rest[i + 1])
            i += 2
        elif rest[i] == "--label":
            labels = True
            i += 1
        else:
            files.append(rest[i])
            i += 1
    sheet(files, out, cols=cols, labels=labels)
