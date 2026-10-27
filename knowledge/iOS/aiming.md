# Aiming iOS action files

An iOS action file holds window points, and a tap on empty space is not an
error. How to know a file presses what it names, and how to move its points
when the layout moves. Checked 2026-10-24.

## Why aim needs its own check

- On 2026-09-27 a sweep replayed and captured all 73 iOS files; checked against
  the accessibility tree, only 15 files had every positioned row on its named
  target (a7fd86d4). results.csv2 then recorded `replay=misaimed` for 49 apps.
- Every change to where a root starts or how wide an app is laid out
  invalidates all points at once: native size on 2026-10-01 (84 files),
  default-size layout and top start on 2026-10-12 (86 files re-aimed in
  87c61a0e, more in 9f733bbc; iPad files on 2026-10-13).

## Tools

- `--dump-tree` (test_ios.zsh) and the `dumptree` row print the tree XCUITest
  resolves, the only external view of it on iOS (macOS has ax_dump, Android
  uiautomator). Lines look like
  `Button, 0x..., {{386.0, 175.0}, {44.0, 22.0}}, label: 'Reset'`.
- `testapp/test_support/ios_aim_check.py <tree dump> <action file>...` reports
  the element under each click/longpress/doubleclick/mousedown point and
  whether its label matches the row's note. Rows after a scroll, drag or
  rotation are marked AFTER: the launch tree cannot place them.
- Re-aiming in the runner: `IOS_AIM=record` prints, per row, the smallest
  element containing the point and the nearest labelled element;
  `IOS_AIM_FILE=<recorded output>` moves each point to where those anchors are
  now. A point now off screen gets a `move` plus `scroll` first, printed as rows
  to add. Record on a build where the file is known to land.

## Rules learned

- For a toggle, aim at the Switch element, not its label.
- A tap that comes after earlier rows changed the layout needs a `dumptree` at
  that row; the launch tree is wrong for it (P17's "More height", 2026-10-01).
- Two coordinate spaces can appear in one tree: right after a layout change the
  tree may list stale frames outside the window (eleven 500x463 frames at
  x = -36 for P65). The runner drops out-of-window frames and retries once;
  waiting four seconds did not refresh the tree, one delivered tap did.
- End a file in a state only success can reach. P24's "pushes stays 0" was Pop
  to root resetting the counter (2026-09-28).
- When a tap "does nothing", capture where it went before eliminating anything
  else (mistakes.md entry 28).
- Lists: drags start from the window centre unless a `move` aims first (P57
  needed `move 200,810` onto the list).

---

# 瞄準 iOS 動作檔

iOS 動作檔存的是視窗座標，而點在空白處不是錯誤。如何確認一份檔案按到它所指名的東西，以及版面移動時如何搬動
它的座標。2026-10-24 確認。

## 為什麼瞄準需要獨立檢查

- 2026-09-27 一次 sweep 重放並擷取了全部 73 份 iOS 檔案;對照無障礙樹，只有 15 份檔案的每一列座標都落在
  所指名的目標上(a7fd86d4)。results.csv2 因而為 49 支 app 記下 `replay=misaimed`。
- 根 view 的起點或 app 的排版寬度每改變一次，所有座標就同時失效:2026-10-01 的原生尺寸(84 份檔案)、
  2026-10-12 的 defaultSize 排版與從頂端開始(87c61a0e 重新瞄準 86 份，9f733bbc 再補幾份;iPad 檔案在 2026-10-13)。

## 工具

- `--dump-tree`(test_ios.zsh)與 `dumptree` 列會印出 XCUITest 解析到的樹，這是 iOS 上唯一的外部視角
  (macOS 有 ax_dump,Android 有 uiautomator)。格式如
  `Button, 0x..., {{386.0, 175.0}, {44.0, 22.0}}, label: 'Reset'`。
- `testapp/test_support/ios_aim_check.py <樹的輸出> <動作檔>...` 回報每個 click/longpress/doubleclick/mousedown
  座標底下的元素，以及其標籤是否與該列註記相符。捲動、拖曳或旋轉之後的列標為 AFTER:啟動時的樹無法定位它們。
- runner 中的重新瞄準:`IOS_AIM=record` 逐列印出包含該點的最小元素與最近的有標籤元素;
  `IOS_AIM_FILE=<記錄下來的輸出>` 把每個點移到那些錨點現在的位置。現在位於畫面外的點會先加上 `move` 與
  `scroll`,並印成要加入的列。請在確定檔案會點中的建置上記錄。

## 學到的規則

- 開關要瞄準 Switch 元素，不是它的標籤。
- 前面的列改變了版面之後的點擊，要在那一列加 `dumptree`;啟動時的樹對它是錯的(P17 的「More height」,2026-10-01)。
- 同一棵樹中可能出現兩種座標空間：版面剛改變時，樹可能列出位於視窗外的陳舊框架(P65 有十一個位於 x = -36 的
  500x463 框架)。runner 會丟掉視窗外的框架並重試一次;等四秒不會更新樹，送出一次點擊就會。
- 讓檔案結束在只有成功才能到達的狀態。P24 的「pushes stays 0」是 Pop to root 把計數器歸零(2026-09-28)。
- 點擊「沒有作用」時，先擷圖看它落在哪裡，再排除其他可能(mistakes.md 第 28 條)。
- 清單：拖曳從視窗中央開始，除非先用 `move` 瞄準(P57 需要 `move 200,810` 移到清單上)。
