# Mobile comparison flow: iOS vs Android, one Pn at a time

Agreed with the user on 2026-10-09. The unit of work is ONE test app, carried
from capture to a verified fix before the next app starts:

```
Pn: capture iOS -> capture Android -> compare -> fix -> re-capture both -> verify -> record -> P(n+1)
```

The first attempt did it in batches instead -- capture all 87 apps on both
platforms, compare in bulk, fix later. That piles up a list of unverified
findings, and a fix made long after its capture is checked against a picture
of older code. One app at a time keeps every fix next to the capture that
proves it.

## Rules

- **One platform at a time, one app at a time.** Never run the iOS and the
  Android harness together, and never a macOS run while either is going
  (user, 2026-10-09: "don't do it in parallel"). Reading screenshots is not a
  run; capturing is.
- **Capture from a fresh build.** No `-n` on the capture that a comparison or a
  fix is judged by.
- **Both captures come from the same commit.** A comparison across two code
  states finds differences in the code, not between the platforms.
- **A fix is verified by re-capturing the same Pn on both platforms**, not by
  reasoning. If the fix touches a shared file (core, a shared Kotlin helper),
  re-capture the other platform too even if only one looked wrong.
- **Five-backend rule still applies** (CLAUDE.md): a fix on UIKit or Android
  that the other backends also lack is not finished until they have it, or it
  is recorded as open for the platform that cannot be run here.

## Steps

1. **Capture iOS.**
   `zsh testapp/test.zsh Pn --ios --showtime 3`
   The final capture is `testapp/output/screenshots/pn-ios-final-<stamp>.png`;
   the log line `==> Screenshot: ...final...` names it.
2. **Capture Android** (after iOS has finished).
   `zsh testapp/test.zsh Pn --android --showtime 3`
   -> `pn-android-final-<stamp>.png`. If the run says "crashed after launch",
   read the logcat it prints before believing it: right after a cold boot the
   emulator can restart its userspace, which is not the app.
3. **Compare.** Open both PNGs and `testapp/Pn.swift` (its header comment and
   on-screen text say what the app tests and what pass looks like). Look for:
   - content present on one platform and missing on the other;
   - content the source puts on screen that is missing on both;
   - clipping, truncation, overlap, text off screen, controls outside their frame;
   - wrong launch state (a value, selection, toggle or label the source sets
     differently);
   - an on-screen pass/fail statement whose condition visibly fails;
   - blank screens, error text, crashes.
   Not findings by themselves: platform conventions (fonts, control chrome,
   iOS blue vs Android grey, status bar, default spacing) and the `actualView`
   debug button -- unless they cause one of the above.
4. **Triage each finding** before fixing:
   - *backend defect* -- fix it in the backend (and the other backends if they
     share it);
   - *test-app defect* -- the app asks for something a phone cannot show (e.g.
     a 1040 pt fixed width); fix the app, or note that the app is desktop-sized;
   - *by design* -- write down why, so the next pass does not re-report it.
   Verify a finding against the image yourself before acting on it; a
   second-hand description of a screenshot is a lead, not evidence.
5. **Fix** -- through csv2 (repo CLAUDE.md).
6. **Re-capture both platforms** (steps 1-2) and compare again. Done when the
   finding is gone on both and nothing new appeared.
7. **Record.** Append a row per platform to `matrix_coverage/results.csv2`
   (`csv2_append`, see testapp/test_support/csv2_rows.zsh), regenerate
   `matrix_coverage/coverage.md`, and commit the fix with the before/after
   evidence in the message. Anything left open goes to `queue.md`.
8. **Next Pn.**

## Known by-design differences (do not re-report)

- **Where an oversized root starts -- ALIGNED 2026-10-09 (user's decision).**
  Content larger than the phone sits in a scroll view on both platforms. Android
  used to start at the window origin, so a desktop-sized app that SwiftCrossUI
  centred past the left/top edge launched with its title off screen; it now
  starts at the content's top-left, just below the status bar, as UIKit does.
  Old Android action files keep working: the replay adds how far the content
  moved (`-actionfile: geometry ... client=`) and scrolls the root to reach a
  point that starts off screen (`-actionfile: scrolled the root by ...`).
- **Mid-word wrapping in a desktop-sized app.** When an app is wider than the
  phone, rows are squeezed and labels wrap inside words ("Rese/t",
  "Disable/d/toggle"). That is the app's size, not a backend defect.

## Before/after evidence

When a fix changes what is drawn, keep a side-by-side of the two captures
(before left, after right) and say in words what changed. Label images with a
font that has CJK glyphs (`/System/Library/Fonts/STHeiti Medium.ttc`) -- the
default font draws Chinese as empty boxes.

---

# 行動平台比對流程:iOS 與 Android,一次一支 Pn

2026-10-09 與使用者議定。工作單位是**一支**測試 app,從截圖一路做到修正驗證完成，才開始下一支：

```
Pn:截 iOS -> 截 Android -> 比對 -> 修正 -> 兩邊重截 -> 驗證 -> 記錄 -> P(n+1)
```

第一次嘗試是分批做的——兩個平台把 87 支全部截完、一起比對、之後再修。那會累積一串未驗證的發現，而且離
截圖很久之後才做的修正，是拿舊程式碼的畫面來檢查。一次一支，讓每個修正都緊貼著證明它的那張截圖。

## 規則

- **一次一個平台、一次一支 app。** iOS 與 Android 的測試不同時跑，其中一個在跑時也不跑 macOS(使用者，
  2026-10-09:「不要平行」)。讀截圖不算執行，截圖才算。
- **截圖來自重新建置。** 用來判斷比對或修正的那次截圖不加 `-n`。
- **兩張截圖來自同一個 commit。** 跨兩種程式碼狀態的比對，找到的是程式碼的差異，不是平台的差異。
- **修正以「兩個平台重截同一支 Pn」驗證**,不是靠推理。修正動到共用檔案(core、共用的 Kotlin helper)時，
  即使只有一邊看起來有問題，另一邊也要重截。
- **五個 backend 的規則照舊**(CLAUDE.md):UIKit 或 Android 上的修正若其他 backend 也缺，要等它們也有了
  才算完成，或為這裡跑不了的平台記為未完成。

## 步驟

1. **截 iOS:**`zsh testapp/test.zsh Pn --ios --showtime 3`,最後一張是
   `testapp/output/screenshots/pn-ios-final-<stamp>.png`。
2. **截 Android**(iOS 跑完之後):`zsh testapp/test.zsh Pn --android --showtime 3`。若顯示
   「crashed after launch」,先讀它印出的 logcat:冷開機後模擬器可能重啟整個 userspace,那不是 app。
3. **比對:** 打開兩張 PNG 與 `testapp/Pn.swift`(標頭註解與畫面文字說明它測什麼、通過長什麼樣子)。找：
   一邊有另一邊沒有的內容；原始碼要顯示但兩邊都沒有的內容；裁切、截斷、重疊、超出畫面；啟動狀態不對；
   畫面上的通過條件明顯不成立；空白、錯誤訊息、崩潰。平台慣例(字型、控制項外觀、iOS 藍與 Android 灰、
   狀態列、預設間距)與 `actualView` 除錯按鈕本身不算，除非造成上述問題。
4. **先分類再修:** backend 缺陷(修 backend,其他 backend 若同樣缺也一起);測試 app 缺陷(app 要求手機
   顯示不了的東西，例如 1040 pt 的固定寬度——修 app,或註明它是桌面尺寸);刻意如此(寫下理由，下次不再
   回報)。動手前親自看圖確認;別人對截圖的描述是線索，不是證據。
5. **修正**——透過 csv2(本 repo 的 CLAUDE.md)。
6. **兩個平台重截**(步驟 1–2)再比對一次。該問題在兩邊都消失、也沒有新問題，才算完成。
7. **記錄:** 每個平台在 `matrix_coverage/results.csv2` 加一列(`csv2_append`),重新產生
   `matrix_coverage/coverage.md`,提交時在訊息裡寫明修正前後的證據。未完成的寫進 `queue.md`。
8. **下一支 Pn。**

## 修正前後的證據

修正改變了畫面時，把兩張截圖並排(左修正前、右修正後)並用文字說明差異。圖上的標籤要用有中文字的字型
(`/System/Library/Fonts/STHeiti Medium.ttc`)——預設字型會把中文畫成方框。
