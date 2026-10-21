# pairs_deck — GTK / macOS side by side

A slide deck with one test app per slide: AppKitBackend on the left,
GtkBackend on the right, both captured at rest on this Mac. It is the GTK /
macOS counterpart of the iOS / Android deck published on 2026-10-12
("iOS and Android Pairs"), asked for on 2026-10-15.

Published: https://claude.ai/artifact/Y3a2b3WMcsnqmhck4Eef3y (private to the
owner until shared).

```sh
zsh testapp/test_support/pairs_deck/capture_macos.zsh           # every testapp/P*.swift, both backends
zsh testapp/test_support/pairs_deck/capture_macos.zsh P10 P88   # only those
zsh testapp/test_support/pairs_deck/build_deck.zsh OUTDIR       # OUTDIR/index.html + OUTDIR/img/
```

Then publish `OUTDIR/index.html` with the files under `OUTDIR/img/` to the
same artifact URL.

## capture_macos.zsh

Runs `test.zsh Pn --macos --showtime 3` once with AppKitBackend and once with
`TEST_BACKEND=gtk4`, with no action file, and appends one record per run to
`testapp/output/macos-pairs.csv2` (`utc,app,backend,exit,image`). A run that
leaves no `-final-` screenshot is recorded with an empty image. Logs go to
`testapp/output/macos-pairs-logs/`. Each app takes about a minute for the two
runs, most of it the GTK build, so the whole set takes about an hour and a
half, with the app windows in front of everything else meanwhile.

## build_deck.zsh

Takes the newest record per app and backend, scales each screenshot to 900 px
high as JPEG (`sips`), and writes the slides between `template-head.html` and
`template-tail.html`.

The two templates are the published iOS / Android page itself, split before
and after its slides, with the parts that differ between the decks turned into
`@@TOKENS@@` (title, colours, image box, tile ratio, slide size, tile image
prefix). The publish skeleton the server adds (doctype to `<body>`, and
`</body></html>`) is not in them. No generator for the iOS / Android deck was
found in this tree or on this Mac, which is why the page was taken as the
template.

**The chip on each slide is read, not judged.** It comes from the newest
`mac,gtk4` row for that app in `matrix_coverage/results.csv2` whose note starts
with `GTK/macOS comparison:` -- `aligned` or `noted` after the colon, and the
rest of the note beside the app id. Without such a row the slide says
`unrecorded`: nobody has put the two side by side and written down whether they
match. To record a comparison, append a row with `csv2_append`, for example:

```sh
source testapp/test_support/csv2_rows.zsh
csv2_append matrix_coverage/results.csv2 2026-10-15 mac gtk4 P10 ok n/a window default \
  'GTK/macOS comparison: noted -- the GTK button is 4 pt taller.'
```

## GTK three ways: Windows, WSL and macOS

One slide per app with GtkBackend at rest on Windows (left), under WSLg (middle)
and on macOS (right). Asked for and published on 2026-10-21:
https://claude.ai/artifact/AGQvHbzL4DMuvnraDB6Kqt (private to the owner until
shared).

```sh
zsh testapp/test_support/pairs_deck/capture_gtk.zsh --win            # every Pn-gtk4.exe in testapp/output
zsh testapp/test_support/pairs_deck/capture_gtk.zsh --wsl            # inside WSL: every Pn in testapp/output
zsh testapp/test_support/pairs_deck/capture_gtk.zsh --win --build P55 P56   # rebuild those first
zsh testapp/test_support/pairs_deck/build_gtk_deck.zsh OUTDIR MAC_TSV
```

**capture_gtk.zsh** runs `test.zsh Pn --showtime 3` with no action file and
appends `utc,app,exit,image` to `testapp/output/gtk-pairs-<win|wsl>.csv2`. It
passes `--no-build` unless given `--build`. An exe built with Swift 6.3.3
(before 2026-10-12) and the WSL binaries from 2026-09-08 open no window at all
-- the run ends `no visible window matched` with rc 7 -- so those need
`--build`. The WSL checkout is a separate copy: copy the script there first. An
older copy without `--build` took the flag for an app name, skipped it, and went
on through the list with `--no-build` in parallel with the real run.

**build_gtk_deck.zsh** needs the WSL records and screenshots copied into this
checkout's `testapp/output` at the same relative paths. macOS is not
re-captured: MAC_TSV lists, per app, the image already in the GTK / macOS deck
and its caption, and the publish copies those server side as
`img/mac-pN.jpg`. A publish takes at most 255 files, so it goes in two:
`index.html` with the local images, then the macOS copies to the same URL.

Result on 2026-10-21: 106 of 116 slides have all three. P6 does not build with
GTK on Windows by design (a D3D11 swap chain; P6-v2 is its GTK form), P12 and
P14 are out of the Windows scope, and P105-P112 are newer than the GTK / macOS
deck. Recount with
`grep -o 'chip [a-z]*">[0-9] of 3' OUTDIR/index.html | sort | uniq -c`.

---

# pairs_deck——GTK / macOS 並排

每支測試 app 一頁：左邊 AppKitBackend、右邊 GtkBackend,兩者都在這台 Mac 上靜止時擷取。這是 2026-10-12 發布的
iOS / Android 簡報(「iOS and Android Pairs」)的 GTK / macOS 版，於 2026-10-15 提出需求。

- `capture_macos.zsh`:每支 app 以 AppKitBackend 與 `TEST_BACKEND=gtk4` 各執行一次 `test.zsh Pn --macos --showtime 3`
  (不帶動作檔),每次執行在 `testapp/output/macos-pairs.csv2` 加一筆。沒有最終擷圖的執行也記下，影像欄留空。全部約一個半小時，
  期間 app 視窗會在最上層。
- `build_deck.zsh`:取每支 app 每個 backend 最新的一筆，把擷圖縮成 900 像素高的 JPEG,夾在兩個模板之間寫出各頁。
- 模板就是已發布的 iOS / Android 頁面本身，在各頁前後切開，兩份簡報不同之處換成 `@@TOKENS@@`;伺服器發布時加上的骨架不在其中。
  本樹與本機都找不到 iOS / Android 簡報的產生器，所以才以該頁為模板。
- **每頁的標籤是讀出來的，不是判斷出來的。** 取自 `results.csv2` 中該 app 最新一筆 `mac,gtk4`、備註以 `GTK/macOS comparison:`
  開頭的紀錄;沒有就顯示 `unrecorded`。

## GTK 三方對照:Windows、WSL、macOS

每支 app 一頁,GtkBackend 在 Windows(左)、WSLg(中)與 macOS(右)上的靜止畫面，於 2026-10-21 提出需求並發布:
https://claude.ai/artifact/AGQvHbzL4DMuvnraDB6Kqt(僅擁有者可開，除非另行分享)。

- `capture_gtk.zsh --win|--wsl [--build] [Pn ...]`:在 Windows 或 WSL 內對每支 app 執行 `test.zsh Pn --showtime 3`,
  每次在 `testapp/output/gtk-pairs-<win|wsl>.csv2` 加一筆。預設 `--no-build`;以 Swift 6.3.3 建置的舊 exe(10-12 之前)
  與 WSL 上 09-08 的舊執行檔都開不出視窗(「no visible window matched」),那些要加 `--build`。WSL 的 checkout 是另一份拷貝，
  要先把腳本同步過去——舊版會把 `--build` 當成 app 名稱。
- `build_gtk_deck.zsh OUTDIR MAC_TSV`:WSL 的紀錄與擷圖先複製到本 checkout 的 `testapp/output`(同樣的相對路徑)。macOS 不重拍,
  MAC_TSV 列出 GTK / macOS 簡報裡已發布的影像,發布時以伺服器端複製成 `img/mac-pN.jpg`。單次發布上限 255 個檔案，所以分兩次：
  先 index.html 與本地影像，再補 mac 影像。標籤是有擷圖的邊數。
- 2026-10-21 的結果:116 頁中 106 頁三邊齊全。P6 在 Windows 上刻意不能以 GTK 建置(D3D11 swap chain,由 P6-v2 代替);
  P12、P14 不在 Windows 範圍內;P105-P112 晚於 GTK / macOS 簡報。重算：`grep -o 'chip [a-z]*">[0-9] of 3' OUTDIR/index.html | sort | uniq -c`。
