# Action-file replay on iOS: the XCUITest runner

How `test.zsh <Pn> --ios --actionfile actions/ios/<file>.actions` presses
things. Checked against test_ios.zsh and
`testapp/iosContainer/xcodeTestRunner/Tests/ActionFileUITests.swift` on
2026-10-24.

## Where the replay runs

Not in the app. A UI-test target (`iOSActionFileRunner`, project in
`testapp/iosContainer/xcodeTestRunnerProject`) is built with
`xcodebuild build-for-testing` into `testapp/.bundledApp/`, the path of the
file is written into the `.xctestrun` with PlistBuddy
(`TestingEnvironmentVariables:IOS_ACTION_FILE`), and
`xcodebuild test-without-building -only-testing:iOSActionFileRunner/ActionFileUITests/testActionFile`
runs it against `debugTarget`, which test_ios.zsh launched 2 s earlier.

Consequences:

- The runner prints `replaying <file> with <n> actions` and, at the end,
  `-actionfile: replayed <file>` on stderr. sweep_apple.zsh judges a replay by
  that line. Before 2026-09-07 there was no such line, which is why iOS cells
  stayed `unverified`.
- The runner reports success whether or not the app survived; a crash shows
  only as a new `debugTarget-*.ips` and a home-screen capture (P73,
  2026-09-27).
- A tap on empty space is not an error. Aim is a separate check
  ([aiming.md](aiming.md)).

## Required staging

- **The file is copied to `$TMPDIR/scui-ios-actions/`.** The test process runs
  under the simulator sandbox, and a path under `/Volumes` fails there with
  `NSCocoaErrorDomain Code=256 "couldn't be opened"`. A symlink does not help.
  This alone kept 45 iOS cells `unverified` until found.
  `IOS_AIM_FILE` is staged the same way.
- **SYMROOT/OBJROOT and `-derivedDataPath` on both xcodebuild calls.** Without
  the pin the runner under test was a stale build (2026-09-29); without
  `-derivedDataPath` on the test step, each run left a new
  `DerivedData/iOSActionFileRunner-<hash>` (166 on 2026-10-04).
- PlistBuddy keys that must not leak between runs (`IOS_AIM`, `IOS_AIM_FILE`,
  `IOS_SHOT_DIR`) are deleted first, because the `.xctestrun` is reused.

## Verbs and their iOS meaning

| Verb | On iOS |
|---|---|
| `click`, `doubleclick`, `move`, `sleep` | tap at a window point; `sleep` pauses the replay, not the finger |
| `mousedown`/`mouseup` | a drag: 0.1 s press; `micros` on mouseup = hold before moving, slow drag (iPad window moves need it); `velocity N [hold S]` in key = a throw at N pt/s (P108) |
| `longpress` | hold for `micros`; the verb exists for this runner, desktop synthesisers refuse it |
| `scroll` | a one-finger drag of 40 pt per notch, sign inverted (positive dy drags up); preceded by a short press so it is not a flick; must stay inside the window or nothing happens; fields are notches, not points |
| `pinch`, `rotate` | XCUITest's native two-contact gestures, aimed at the smallest element containing the last `move` point |
| `key`, `keydown`, `keyup` | `typeKey` through the simulator hardware keyboard; only modifiers can be held, `keydown s` throws; left/right modifier sides are dropped; `delete` is Backspace |
| `hover` | a synthesized pointer path per row (iPad); skipped on iPhone, which has no pointer; with `micros` the pointer rests and the runner captures halfway |
| `orient` | rotates the device (`portrait`, `landscapeLeft`, ...) |
| `taplabel`, `activate`, `dumptree`, `windowframes` | tap by accessibility label in the front app (alert buttons are matched although not hittable); bring another bundle forward (e.g. Settings); print the tree at that row; list the app's windows |

`origin` `screen` measures from the screen through SpringBoard; every other
row is relative to `app.windows.firstMatch`, which on an iPad in windowed mode
is neither at the origin nor reliably the same window.

## File directives

- `# fresh-install` uninstalls the app first, discarding its scene sessions:
  iPadOS reopens every window of the last run, and restoring them crashed the
  simulator's render server (P5 on iPad, 2026-10-02). Opt-in, because P0 and
  P59 assert on what an earlier run stored.
- `# app-args: ...` adds launch arguments, e.g. `--steps-after 6`.
- A file with only `sleep` rows runs without the runner; see
  [self-running-apps.md](self-running-apps.md).
- Rows are read with csv2. Header
  `action,x,y,origin,button,key,micros,note,platform`; an unquoted comma in a
  note breaks the row.

## Stale documents

`testapp/actions/ios/README.md` and testapp/FAQ.md:297 still say keyboard and
scroll rows are rejected and give a 393x852 window. The runner's switch
statement is the current list. A README saying `actions/ios` was "empty;
planned" once caused a rebuild of a driver that already existed (mistakes.md
entry 13).

---

# iOS 上的動作檔重放:XCUITest runner

`test.zsh <Pn> --ios --actionfile actions/ios/<檔案>.actions` 如何按下東西。2026-10-24 對照 test_ios.zsh
與 `testapp/iosContainer/xcodeTestRunner/Tests/ActionFileUITests.swift` 確認。

## 重放在哪裡執行

不在 app 裡。一個 UI 測試 target(`iOSActionFileRunner`,專案在
`testapp/iosContainer/xcodeTestRunnerProject`)以 `xcodebuild build-for-testing` 建進
`testapp/.bundledApp/`,檔案路徑以 PlistBuddy 寫入 `.xctestrun`
(`TestingEnvironmentVariables:IOS_ACTION_FILE`),再由
`xcodebuild test-without-building -only-testing:iOSActionFileRunner/ActionFileUITests/testActionFile`
對 test_ios.zsh 在 2 秒前啟動的 `debugTarget` 執行。

後果:

- runner 會在 stderr 印出 `replaying <檔案> with <n> actions`,結束時印 `-actionfile: replayed <檔案>`。
  sweep_apple.zsh 以這一行判定重放。2026-09-07 之前沒有這一行，這就是 iOS 的格子一直是 `unverified` 的原因。
- 不論 app 是否存活,runner 都回報成功;當機只會表現為新的 `debugTarget-*.ips` 與一張主畫面的擷圖
  (P73,2026-09-27)。
- 點在空白處不是錯誤。是否點中是另一項檢查([aiming.md](aiming.md))。

## 必要的暫存

- **檔案先複製到 `$TMPDIR/scui-ios-actions/`。** 測試行程在模擬器沙盒中執行，位於 `/Volumes` 的路徑在
  那裡會以 `NSCocoaErrorDomain Code=256 "couldn't be opened"` 失敗。符號連結也沒用。光是這一點，在被發現
  之前就讓 45 個 iOS 格子維持 `unverified`。`IOS_AIM_FILE` 也以同樣方式暫存。
- **兩個 xcodebuild 呼叫都要 SYMROOT/OBJROOT 與 `-derivedDataPath`。** 沒有釘住時，受測的 runner 是
  陳舊的建置(2026-09-29);測試步驟沒有 `-derivedDataPath` 時，每次執行都留下一個新的
  `DerivedData/iOSActionFileRunner-<hash>`(2026-10-04 時有 166 個)。
- 不可在兩次執行間殘留的 PlistBuddy 鍵(`IOS_AIM`、`IOS_AIM_FILE`、`IOS_SHOT_DIR`)會先刪除，
  因為 `.xctestrun` 會重複使用。

## 動作與它們在 iOS 上的意義

| 動作 | 在 iOS 上 |
|---|---|
| `click`、`doubleclick`、`move`、`sleep` | 在視窗座標點一下;`sleep` 暫停的是重放，不是手指 |
| `mousedown`/`mouseup` | 拖曳:按 0.1 秒;mouseup 的 `micros` 是移動前的按住時間，並慢速拖曳(iPad 移動視窗需要);key 欄的 `velocity N [hold S]` 是以每秒 N 點甩出(P108) |
| `longpress` | 按住 `micros` 那麼久;此動作是為這個 runner 而設，桌面合成器會拒絕 |
| `scroll` | 單指拖曳，每格 40 點，正負號相反(正的 dy 是往上拖);先短按一下，免得變成甩動;必須留在視窗內，否則什麼都不會發生;欄位是格數，不是點數 |
| `pinch`、`rotate` | XCUITest 原生的雙指手勢，瞄準包含上一個 `move` 點的最小元素 |
| `key`、`keydown`、`keyup` | 經模擬器硬體鍵盤 `typeKey`;只有修飾鍵能按住,`keydown s` 會拋錯;修飾鍵的左右之分被捨棄;`delete` 是 Backspace |
| `hover` | 每列送出一條合成的指標路徑(iPad);iPhone 沒有指標，所以略過;帶 `micros` 時指標停留，runner 在中途擷圖 |
| `orient` | 旋轉裝置(`portrait`、`landscapeLeft`……) |
| `taplabel`、`activate`、`dumptree`、`windowframes` | 在最前面的 app 依無障礙標籤點擊(警示的按鈕即使不可點擊也會比對到);把另一個 bundle 帶到前面(例如「設定」);在該列印出無障礙樹;列出 app 的視窗 |

`origin` 為 `screen` 時從螢幕(經 SpringBoard)量起;其他列都相對於 `app.windows.firstMatch`,而在 iPad 的
視窗模式中，那既不在原點，也不一定是同一個視窗。

## 檔案指示

- `# fresh-install` 先解除安裝 app,丟棄它的 scene session:iPadOS 會重新打開上次執行的每個視窗，而恢復
  它們曾讓模擬器的渲染伺服器崩潰(iPad 上的 P5,2026-10-02)。採 opt-in,因為 P0 與 P59 要斷言前一次執行
  存下的東西。
- `# app-args: ...` 加入啟動參數，例如 `--steps-after 6`。
- 只有 `sleep` 列的檔案不經 runner 執行;見 [self-running-apps.md](self-running-apps.md)。
- 各列以 csv2 讀取。標頭 `action,x,y,origin,button,key,micros,note,platform`;註記中未加引號的逗號會
  破壞該列。

## 過時的文件

`testapp/actions/ios/README.md` 與 testapp/FAQ.md:297 仍說鍵盤與捲動列會被拒絕，並寫著 393x852 的視窗。
runner 的 switch 敘述才是現行清單。曾經有一份 README 說 `actions/ios`「empty; planned」,導致重寫了一個
早已存在的驅動程式(mistakes.md 第 13 條)。
