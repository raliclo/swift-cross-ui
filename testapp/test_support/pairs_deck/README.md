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
