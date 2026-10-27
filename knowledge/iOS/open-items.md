# iOS: known limits and open items

Each item with the date it was last checked. Collected 2026-10-24.

## Open

| Item | Last checked | Source |
|---|---|---|
| No physical iPad, no trackpad, has run any test; the simulator was accepted instead | 2026-10-20 | queue.md:22, :709 |
| XCUITest `pinch`/`rotate` send gestures of their own size; their fidelity against a real two-finger gesture is not measured | 2026-09-17 | completed.md:474-502 (P65) |
| XCUITest's Escape does not reach `pressesBegan` on the iPhone simulator; P49 closes its sheet by swiping | 2026-10-20 | results.csv2 ios P49 |
| P108: one run of five lost the runner's connection to the app, with no crash report | 2026-10-19 | results.csv2 ios P108 |
| P97 at rest: every iOS row still reads "running" at the capture, where Android shows each start/reach line | 2026-10-23 | results.csv2 ios P97 |
| Removing `preferredColorScheme` at run time is not exercised | 2026-10-06 | completed.md:1478-1489 |
| iOS 13-15 code paths (e.g. sheet detents before iOS 16) are built, never run: only an iOS 27 runtime is installed | 2026-10-06 | completed.md:1517 |
| P57's remaining off-screen cells are suspected to come from XCUITest's accessibility snapshot; unproven | 2026-10-04 | completed.md:1894-1903 |

## Limits by design or by platform

- The only window of an iPhone app cannot be closed
  ([windows-and-presentations.md](windows-and-presentations.md)).
- No programmatic window size on iOS or iPadOS ([ipad.md](ipad.md)).
- A Core Animation animation inside a container with a visual effect freezes at
  the last layout ([visual-effects-and-colour.md](visual-effects-and-colour.md)).
- iPhone has no pointer: hover rows are skipped and cursor styles cannot be
  tested there ([pointer-hover-cursors.md](pointer-hover-cursors.md)).
- rwdView scales the finished layout; it does not reflow
  ([root-scroll-host.md](root-scroll-host.md)).

## Stale documents (checked 2026-10-24)

- `testapp/actions/ios/README.md` and testapp/FAQ.md:297-299: say keyboard and
  scroll rows are rejected and give a 393x852 window. The runner supports both;
  the device is 440x956.
- flow.md:99, :145: iPhone 16 at 393x852 pt.
- `install_tools_ios.zsh` creates a missing device as "iPhone 16", while the
  existing `swift-cross-ui` device is an iPhone 17 Pro Max. A fresh machine
  would therefore measure on a different screen size than the action files
  were recorded on.

---

# iOS:已知限制與未解事項

每一項都附上最後確認的日期。2026-10-24 整理。

## 未解

| 項目 | 最後確認 | 來源 |
|---|---|---|
| 沒有任何測試在實體 iPad 或觸控板上跑過;已接受以模擬器代替 | 2026-10-20 | queue.md:22、:709 |
| XCUITest 的 `pinch`/`rotate` 送出的是它自己尺寸的手勢;與真實雙指手勢相比的逼真度未量測 | 2026-09-17 | completed.md:474-502(P65) |
| iPhone 模擬器上 XCUITest 的 Escape 不會到達 `pressesBegan`;P49 改以滑動關閉 sheet | 2026-10-20 | results.csv2 ios P49 |
| P108:五次執行中有一次 runner 與 app 失去連線，沒有當機報告 | 2026-10-19 | results.csv2 ios P108 |
| P97 靜止擷取時，iOS 每一列仍顯示「running」,Android 則每列都有 start/reach 行 | 2026-10-23 | results.csv2 ios P97 |
| 執行期間移除 `preferredColorScheme` 尚未被測試 | 2026-10-06 | completed.md:1478-1489 |
| iOS 13–15 的程式路徑(例如 iOS 16 之前的 sheet detent)有建置但從未執行：只裝了 iOS 27 runtime | 2026-10-06 | completed.md:1517 |
| P57 剩下的畫面外 cell 疑似來自 XCUITest 的無障礙快照;未證實 | 2026-10-04 | completed.md:1894-1903 |

## 設計上或平台上的限制

- iPhone app 唯一的視窗無法關閉([windows-and-presentations.md](windows-and-presentations.md))。
- iOS 與 iPadOS 都無法以程式設定視窗大小([ipad.md](ipad.md))。
- 套用視覺效果的容器內，Core Animation 動畫會停在上一次排版([visual-effects-and-colour.md](visual-effects-and-colour.md))。
- iPhone 沒有指標:hover 列會被略過，游標樣式在那裡無法測試([pointer-hover-cursors.md](pointer-hover-cursors.md))。
- rwdView 縮放完成的版面，不會重新排版([root-scroll-host.md](root-scroll-host.md))。

## 過時的文件(2026-10-24 確認)

- `testapp/actions/ios/README.md` 與 testapp/FAQ.md:297-299:說鍵盤與捲動列會被拒絕，並寫著 393x852 的視窗。runner 兩者都
  支援;裝置是 440x956。
- flow.md:99、:145:iPhone 16,393x852 pt。
- `install_tools_ios.zsh` 在缺少裝置時以「iPhone 16」建立，而現有的 `swift-cross-ui` 裝置是 iPhone 17 Pro Max。因此一台新機器
  會在與動作檔錄製時不同的螢幕尺寸上量測。
