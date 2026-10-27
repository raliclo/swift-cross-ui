# macOS: the GTK / macOS pairs deck and the GTK three-way deck

Written 2026-10-24 from testapp/test_support/pairs_deck/README.md and its
scripts.

## What

Slide decks with one test app per slide, captured at rest (no action file),
so two backends start from the same state. The published artifact links are
recorded in `pairs_deck/README.md`; they are private to the owner.

```sh
zsh testapp/test_support/pairs_deck/capture_macos.zsh            # every testapp/P*.swift
zsh testapp/test_support/pairs_deck/capture_macos.zsh P10 P88    # only those
zsh testapp/test_support/pairs_deck/build_deck.zsh OUTDIR        # OUTDIR/index.html + img/
```

- **capture_macos.zsh** runs `test.zsh Pn --macos --showtime 3` once on
  AppKitBackend and once with `TEST_BACKEND=gtk4`, and appends
  `utc,app,backend,exit,image` to `testapp/output/macos-pairs.csv2`; a run with
  no `-final-` capture is recorded with an empty image. About a minute per
  app (most of it the GTK build), about 1.5 h for all, with app windows in
  front meanwhile. Logs: `output/macos-pairs-logs/`.
- **build_deck.zsh** takes the newest record per app and backend, scales each
  capture to 900 px high JPEG with `sips`, and writes the slides between
  `template-head.html` and `template-tail.html` -- the published iOS / Android
  page split around its slides, with `@@TOKENS@@` for what differs (no
  generator for that deck exists). It also writes `OUTDIR/mac-gtk.tsv` (app,
  image, caption) for the three-way deck.
- **The chip is read, not judged**: the newest `mac,gtk4` results.csv2 row for
  the app whose note starts `GTK/macOS comparison:` (`aligned` or `noted`);
  without one the slide says `unrecorded`. Record a comparison with
  `csv2_append` (example in the README).
- **Three-way deck** (Windows, WSLg, macOS GTK): `capture_gtk.zsh --win|--wsl
  [--build] [Pn ...]` writes `output/gtk-pairs-<win|wsl>.csv2`;
  `build_gtk_deck.zsh OUTDIR MAC_TSV [gtk-vs-macos-notes.json]`. macOS is not
  recaptured: MAC_TSV names the images already published, copied server side.
  A publish takes at most 255 files, so it goes in two. The notes JSON
  (116 notes, 2026-10-22) describes specific captures and goes stale when a
  slide is recaptured.
- **Captions** end with the launched build's size and date (`output/Pn`,
  `output/Pn-gtk4`, ...), measured by the builders; a build can be newer than
  the capture.

## Evidence

- 2026-10-15: first full capture; each app got a `GTK/macOS comparison` row
  (results.csv2 mac/gtk4, 2026-10-15). The differences listed there drove
  queue items 17, 18, 22, 26 and 31, all closed by 2026-10-23; later rows
  (2026-10-16, 2026-10-19) record the re-captures.
- 2026-10-21: 106 of 116 three-way slides have all three. P6 has no GTK build
  on Windows by design, P12 and P14 are out of the Windows scope, P105-P112
  were newer than the deck (added on macOS 2026-10-23, ae10e5e6).
- The GTK / macOS captures were taken on the M6 Mac; its 2026-10-18/19 builds
  are what the captions measure (README, 2026-10-22).

## Limits

- A capture at rest can fall mid-animation: P105's AppKit "fault" of
  ae10e5e6 was a capture taken mid-step (76166a4b).
- Exe builds older than Swift 6.4 (before 2026-10-12) and WSL binaries from
  2026-09-08 open no window; capture_gtk.zsh needs `--build` for them.

---

# macOS:GTK / macOS 對照簡報與 GTK 三方簡報

2026-10-24 依 testapp/test_support/pairs_deck/README.md 及其腳本寫成。

## 內容

每支測試 app 一頁，靜止時擷取(不帶動作檔),讓兩個 backend 從同一狀態開始。已發布的 artifact 連結記在
`pairs_deck/README.md`,僅擁有者可開。

- **capture_macos.zsh** 對每支 app 以 AppKitBackend 與 `TEST_BACKEND=gtk4` 各跑一次 `test.zsh Pn --macos --showtime 3`,
  在 `testapp/output/macos-pairs.csv2` 加 `utc,app,backend,exit,image`;沒有 `-final-` 擷圖的執行也記下，影像欄留空。每支 app
  約一分鐘(大多是 GTK 建置),全部約一個半小時，期間 app 視窗在最上層。log 在 `output/macos-pairs-logs/`。
- **build_deck.zsh** 取每支 app 每個 backend 最新的一筆，以 `sips` 縮成 900 像素高的 JPEG,夾在 `template-head.html` 與
  `template-tail.html` 之間——兩者是已發布的 iOS / Android 頁面在各頁前後切開，不同處換成 `@@TOKENS@@`(那份簡報沒有產生器)。
  它也寫出 `OUTDIR/mac-gtk.tsv`(app、影像、說明)給三方簡報用。
- **標籤是讀出來的，不是判斷的**:取 results.csv2 中該 app 最新一筆 `mac,gtk4`、備註以 `GTK/macOS comparison:` 開頭的列
  (`aligned` 或 `noted`);沒有就顯示 `unrecorded`。以 `csv2_append` 記錄比對(範例在 README)。
- **三方簡報**(Windows、WSLg、macOS 的 GTK):`capture_gtk.zsh --win|--wsl [--build] [Pn ...]` 寫
  `output/gtk-pairs-<win|wsl>.csv2`;`build_gtk_deck.zsh OUTDIR MAC_TSV [gtk-vs-macos-notes.json]`。macOS 不重拍,MAC_TSV
  指向已發布的影像，於伺服器端複製。單次發布最多 255 個檔案，所以分兩次。筆記 JSON(116 則,2026-10-22)描述的是特定擷圖，重拍後就過期。
- **說明**最後是啟動的那個建置的大小與日期(`output/Pn`、`output/Pn-gtk4` 等),由產生器量測；建置可能比擷圖新。

## 依據

- 2026-10-15:第一次完整擷取，每支 app 都有一筆 `GTK/macOS comparison` 列(results.csv2 mac/gtk4,2026-10-15)。其中的差異
  帶出 queue 第 17、18、22、26、31 項，到 2026-10-23 全部結案；之後的列(2026-10-16、10-19)記錄重拍結果。
- 2026-10-21:三方簡報 116 頁中 106 頁三邊齊全。P6 在 Windows 上依設計沒有 GTK 建置,P12、P14 不在 Windows 範圍,P105–P112
  晚於該簡報(2026-10-23 在 macOS 補上,ae10e5e6)。
- GTK / macOS 的擷圖是在 M6 那台 Mac 上拍的，說明量的是它 2026-10-18/19 的建置(README,2026-10-22)。

## 限制

- 靜止擷取可能落在動畫中途:ae10e5e6 記下的 P105 AppKit「缺陷」其實是一步做到一半時的擷圖(76166a4b)。
- Swift 6.4 之前(2026-10-12 之前)的 exe 與 2026-09-08 的 WSL 執行檔開不出視窗，capture_gtk.zsh 要加 `--build`。
