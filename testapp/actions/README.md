# Action files, filed by the platform they passed on

One folder per platform. A file lives where it has actually been run and seen
to work — not where it might work.

每個平台一個資料夾。檔案存放於「它確實被執行過、且確認可運作」的平台之下——而非「它或許可行」
之處。

```
actions/
  wsl/        verified on WSLg with GtkBackend
  win/        verified on Windows
  mac/        verified on macOS
  ios/        empty; planned
  android/    empty; planned
```

## Why per platform rather than one shared folder

Coordinates. An action file is a list of positions, and the same interface does
not put a button in the same place on two platforms: fonts differ, so labels
have different widths; window decorations differ, so everything below the title
bar shifts; display scale differs, so the whole layout does.

A shared folder would say "this file works", and the reader would find out on
which platform only by running it. A file under `win/` is a claim about
Windows, and one that is missing is a gap rather than a silent failure waiting
to happen.

They also record different things. `wsl/P8-scroll-outer.csv` proved a scroll
reaches a GTK `ScrolledWindow`; the Windows equivalent, when it exists, will be
proving that `SendInput`'s wheel does, which is a different mechanism entirely.

## 為何依平台分開，而非共用單一資料夾

座標。動作檔是一串位置，而同一個介面在兩個平台上不會把按鈕放在相同的地方：字型不同，標籤寬度就
不同；視窗裝飾不同，標題列以下的一切都會位移；顯示縮放不同，整個版面也會不同。

共用資料夾等於宣稱「這個檔案可用」，而讀者唯有實際執行才會發現它指的是哪個平台。放在 `win/` 之下
的檔案，是一項針對 Windows 的明確主張；而缺少的那些，則是明顯的缺口，而不是一個等著發生的靜默
失敗。

它們記錄的事情也不同。`wsl/P8-scroll-outer.csv` 證明的是「捲動事件能抵達 GTK 的 `ScrolledWindow`」；
而 Windows 的對應檔案在存在之後，證明的將是「`SendInput` 的滾輪能抵達」——那是完全不同的機制。

## Using one

```zsh
zsh testapp/test.zsh P19 --actionfile          # the default for that app
zsh testapp/test.zsh P19 --actionfile <path>   # a specific file
```

The runner builds with `SCUI_DEBUG=1` when an action file is involved. Without
it the `-actionfile` flag is not compiled into the binary at all — see
`Sources/DebugFeatures/README.md` — and the app would ignore the file while
looking like it had run.

當涉及動作檔時，執行器會以 `SCUI_DEBUG=1` 建置。少了它，`-actionfile` 旗標根本不會被編入執行檔
——詳見 `Sources/DebugFeatures/README.md`——該 app 會忽略該檔案，外觀上卻像是已經執行過。

## The format

`Sources/InputEvent/README.md`. Nine verbs, coordinates in logical points, and
a `scroll` that reads its `x` and `y` as wheel notches rather than a position.

格式見 `Sources/InputEvent/README.md`。九個動作、以邏輯點為單位的座標，以及一個把 `x`、`y` 讀作
滾輪格數而非位置的 `scroll`。
