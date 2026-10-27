# macOS harness: the shared `.macApp/debugTarget.app` bundle

Written 2026-10-24 from testapp/test_support/test_common.zsh (`run_macos`) and
testapp/macContainer/appTemplate.app. Introduced 7daca70c (2026-08-27); frames
dropped since 4b268536 (2026-10-22).

## What

Every macOS run, AppKit or GTK, launches the built binary from inside one bundle:

- `testapp/macContainer/appTemplate.app` (tracked: `Info.plist`, `PkgInfo`) is
  copied to `testapp/.macApp/debugTarget.app` (untracked).
- `CFBundleIdentifier` is stamped per app, lowercased:
  `dev.swiftcrossui.testapp.<pn>` (e.g. `...testapp.p28`).
- Before launch, every `NSWindow Frame <id>` key in that domain is deleted;
  AppStorage keys in the same domain stay. `SCUI_KEEP_WINDOW_FRAME=1` keeps them.
- `output/Pn` (or `output/Pn-gtk4`) is copied in as the bundle executable
  `debugTarget`.

## Why

- **A bare SwiftPM binary has no bundle identifier**: `lsappinfo` reports
  `bundleID=[ NULL ]`. Frame autosave, AppStorage/UserDefaults and the Dock and
  menu-bar identity all key on it.
- **One identifier per app.** With the template's constant identifier every app
  shared one domain. AppKitBackend names the autosaved frame after the root
  view's type (`NSWindow Frame TupleView1<HotReloadableView>-0`, measured
  2026-09-01), which most apps share, so a window's size was whichever app had
  been resized last: P28 opened at 680x448 bare and 1076x907 bundled, same
  binary, and action files measured one way missed by hundreds of points the
  other way. P0's `p0LaunchCount` counted every app's launches.
- **Frames dropped** (2026-10-22): AppKitBackend restores a saved frame over
  `defaultSize`, as SwiftUI does; GTK, Windows and WSL keep none. P41 opened at
  1202x799 on AppKit against 1340x888 on GTK, P17 at 900x846 against 900x860,
  and P92 kept a 460-pt frame from before its `defaultSize` became 640.
- Lowercase, because Launch Services matches identifiers case-insensitively but
  stores them as written; two spellings would be two domains.

## How to apply

- The process is `debugTarget` for every Pn: kill, `pgrep`, `lsappinfo` and
  System Events lookups use that name. The app menu on both backends is titled
  `debugTarget` (results.csv2: 2026-10-23, mac, gtk4, P92).
- Crash reports land as `~/Library/Logs/DiagnosticReports/debugTarget-*.ips`;
  sweep_apple.zsh treats one newer than the run's marker as `crash`, overriding
  a `replayed` line. The iOS runner installs its app as `debugTarget` too.
- A direct run of `output/Pn` uses a different domain (named after the binary)
  than the harness: P59's scene storage looked like leakage once because of a
  stale domain (results.csv2: 2026-09-09, mac, appkit, P59).
- To measure window sizes, `window_sizes_mac.zsh` deletes the whole domain
  (it measures nothing else). To test frame restoration itself, set
  `SCUI_KEEP_WINDOW_FRAME=1`.

## Limits

- Only one bundle exists, so only one macOS test app can run at a time; the
  ui-lock enforces that.
- The frame keys are read with a full `defaults read` and sed, not `| head` or
  `grep -q`, which fail under `pipefail`.

---

# macOS harness:共用的 `.macApp/debugTarget.app` bundle

2026-10-24 依 testapp/test_support/test_common.zsh(`run_macos`)與 testapp/macContainer/appTemplate.app 寫成。
7daca70c(2026-08-27)引入;自 4b268536(2026-10-22)起丟棄儲存的視窗框。

## 是什麼

每次 macOS 執行(AppKit 或 GTK)都從同一個 bundle 裡啟動建置好的執行檔:

- 把 `testapp/macContainer/appTemplate.app`(納入版本控制:`Info.plist`、`PkgInfo`)複製到
  `testapp/.macApp/debugTarget.app`(不納入)。
- 每支 app 寫入各自的 `CFBundleIdentifier`,小寫:`dev.swiftcrossui.testapp.<pn>`(例如 `...testapp.p28`)。
- 啟動前刪掉該 domain 中所有 `NSWindow Frame <id>` 鍵;同一 domain 的 AppStorage 鍵保留。
  `SCUI_KEEP_WINDOW_FRAME=1` 會保留視窗框。
- 把 `output/Pn`(或 `output/Pn-gtk4`)複製成 bundle 的執行檔 `debugTarget`。

## 為什麼

- **SwiftPM 的裸執行檔沒有 bundle identifier**:`lsappinfo` 回報 `bundleID=[ NULL ]`。視窗框自動儲存、
  AppStorage/UserDefaults,以及 Dock 與選單列上的身分都以它為鍵。
- **每支 app 一個 identifier。** 用 template 的固定 identifier 時，所有 app 共用一個 domain。AppKitBackend 以
  root view 的型別命名自動儲存的視窗框(`NSWindow Frame TupleView1<HotReloadableView>-0`,2026-09-01 實測),
  而多數 app 的型別相同，於是視窗大小取決於最後被調整過大小的那支 app:同一個執行檔，P28 裸啟動是 680x448、
  經 bundle 是 1076x907,以其中一種方式量的動作檔用另一種方式重放會差上數百點。P0 的 `p0LaunchCount`
  也把每支 app 的啟動都算進去。
- **丟棄視窗框**(2026-10-22):AppKitBackend 與 SwiftUI 一樣會用儲存的視窗框蓋過 `defaultSize`;GTK、Windows、
  WSL 都不保存。P41 在 AppKit 上開成 1202x799、GTK 上 1340x888,P17 是 900x846 對 900x860,P92 還留著 defaultSize
  改成 640 之前的 460 點視窗框。
- 轉小寫，因為 Launch Services 比對 identifier 不分大小寫、儲存時照原樣；兩種寫法會變成兩個 domain。

## 怎麼用

- 每支 Pn 的行程名都是 `debugTarget`:kill、`pgrep`、`lsappinfo` 與 System Events 查找都用這個名稱。兩個 backend
  的 app 選單標題都是 `debugTarget`(results.csv2:2026-10-23、mac、gtk4、P92)。
- 崩潰報告是 `~/Library/Logs/DiagnosticReports/debugTarget-*.ips`;sweep_apple.zsh 把比該次執行標記檔新的報告記為
  `crash`,蓋過 `replayed`。iOS runner 也把 app 裝成 `debugTarget`。
- 直接執行 `output/Pn` 用的是另一個 domain(以執行檔命名),與 harness 不同:P59 的 scene storage 曾因殘留的 domain
  看起來像外洩(results.csv2:2026-09-09、mac、appkit、P59)。
- 量視窗大小時,`window_sizes_mac.zsh` 會刪整個 domain(它只量尺寸)。要測試視窗框還原本身，設 `SCUI_KEEP_WINDOW_FRAME=1`。

## 限制

- 只有一個 bundle,所以一次只能跑一支 macOS 測試 app;由 ui-lock 保證。
- 視窗框鍵以完整的 `defaults read` 加 sed 讀出，不用 `| head` 或 `grep -q`——那在 `pipefail` 下會失敗。
