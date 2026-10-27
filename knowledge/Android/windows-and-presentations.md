# Windows, sheets and popovers on Android

Checked 2026-10-24 against commits and Sources/AndroidBackend.

## One activity per window (e71a8327, 2026-10-06)

- The first window is the launch activity (`MainActivity`, `singleTop`). Each
  later window gets a token and, when shown, a `ScuiWindowActivity` of its own,
  started with `NEW_DOCUMENT | MULTIPLE_TASK`. Swift builds the content and
  hands it over by token. Title, background, insets, size, toolbar, close,
  resize and environment handlers are per window (they were single statics, so
  a second window took the first one's).
- `LAUNCH_ADJACENT` only on a tablet or in multi-window mode. On a phone it put
  the window in the split-screen side stage, off screen (c8a533e8).
- The adjacent activity starts only once the opener has window focus, with a
  1 s fallback; a launch from a picker result otherwise left the tablet's main
  stage empty (68a3f89c).
- Back or `close(window:)` finishes the activity and runs the close handler.
- The manifest gives both activities `configChanges` for orientation, size,
  ui mode, density, font scale, locale and more, so these reach
  `onConfigurationChanged` instead of destroying the activity and restarting
  the Swift app (f41c1b07). The density cache is cleared there.
- `ProcessInfo.processName` is set from the application label at the
  entrypoint; the process itself is `app_process64`, which menus showed as
  "Hide app_process64" (1ba5e444).

## Presentations

- A sheet or popover from a later window appears over that window (122bd3cb).
- Popovers sit beside their anchor, centred, kept on screen, with the arrow
  following (63608e89).
- `fullScreenCover` fills the window on a tablet: `BottomSheetBehavior.maxWidth`
  is lifted for covers only; a plain sheet keeps Material's tablet width
  (640 dp of 1280) (af723470, 2026-10-21).
- `sheet(onDismiss:)` runs on programmatic dismissal too (8a6f2aa8).
- Sheets and popovers are separate windows; the replay reaches them through
  FrontWindows (action-file-replay.md).

## Floating windows

`windowLevel(.floating)` adds the content as `TYPE_APPLICATION_OVERLAY`, and
`OverlayService`, a foreground service, keeps the process out of the cached
state so the overlay stays shown after the activity stops (measured
2026-09-04: without it, `Surface: shown=false` once the activity stopped,
through either WindowManager). A foreground service must post a notification,
and from API 34 declare a `foregroundServiceType` (`specialUse` here), so a
floating window on Android always comes with a notification. The permissions
`SYSTEM_ALERT_WINDOW`, `FOREGROUND_SERVICE` and
`FOREGROUND_SERVICE_SPECIAL_USE` are in Bundler.android.toml.

## Evidence

P59 (second window beside the first on a tablet, per-scene state), P81 (sheet
from window B, results.csv2 2026-10-20/21), P49 (cover and sheet on tablet36,
2026-10-21/22), P37 (floating).

---

# Android 上的視窗、sheet 與 popover

2026-10-24 對照 commit 與 Sources/AndroidBackend 查過。

## 每個視窗一個 activity(e71a8327,2026-10-06)

- 第一個視窗是啟動的 activity(`MainActivity`,`singleTop`)。之後的每個視窗取得一個 token,顯示時各自有一個
  `ScuiWindowActivity`,以 `NEW_DOCUMENT | MULTIPLE_TASK` 啟動。Swift 建立內容並以 token 交付。標題、背景、內縮、大小、工具列、
  關閉、縮放與環境 handler 都是每個視窗各自一份(原本是單一的 static,第二個視窗會拿到第一個的)。
- 只有在平板或多視窗模式下才加 `LAUNCH_ADJACENT`。在手機上它會把視窗放進分割畫面的側邊區，跑到螢幕外(c8a533e8)。
- 相鄰的 activity 要等開啟者取得視窗焦點才啟動(1 秒後備);否則從 picker 結果啟動時，平板的主區域會是空的(68a3f89c)。
- 返回鍵或 `close(window:)` 會結束 activity 並執行關閉 handler。
- manifest 給兩種 activity 都設了 `configChanges`(方向、大小、ui mode、密度、字體縮放、語系等),讓這些變更送到
  `onConfigurationChanged`,而不是銷毀 activity、重啟 Swift app(f41c1b07)。密度快取也在那裡清除。
- `ProcessInfo.processName` 在進入點以 application label 設定；程序本身是 `app_process64`,選單曾顯示為「Hide app_process64」
  (1ba5e444)。

## 呈現

- 從後開的視窗發出的 sheet 或 popover 會出現在該視窗上方(122bd3cb)。
- popover 位於錨點旁、置中、保持在螢幕內，箭頭跟著移動(63608e89)。
- 在平板上 `fullScreenCover` 填滿視窗：只對 cover 解除 `BottomSheetBehavior.maxWidth`;一般 sheet 維持 Material 的平板寬度
  (1280 dp 中的 640 dp)(af723470,2026-10-21)。
- `sheet(onDismiss:)` 在以程式關閉時也會執行(8a6f2aa8)。
- sheet 與 popover 是獨立的視窗；重播經由 FrontWindows 碰到它們(action-file-replay.md)。

## 浮動視窗

`windowLevel(.floating)` 把內容以 `TYPE_APPLICATION_OVERLAY` 加入，並由前景服務 `OverlayService` 讓程序不進入 cached 狀態，
activity 停止後 overlay 才會繼續顯示(2026-09-04 量測：沒有它時，不論用哪個 WindowManager,activity 一停止就變成
`Surface: shown=false`)。前景服務必須發出通知，自 API 34 起還要宣告 `foregroundServiceType`(這裡是 `specialUse`),所以
Android 上的浮動視窗一定伴隨一則通知。`SYSTEM_ALERT_WINDOW`、`FOREGROUND_SERVICE` 與 `FOREGROUND_SERVICE_SPECIAL_USE` 權限
寫在 Bundler.android.toml。

## 證據

P59(平板上第二個視窗在第一個旁邊、各場景狀態獨立)、P81(從視窗 B 開 sheet,results.csv2 2026-10-20/21)、P49(tablet36 上的
cover 與 sheet,2026-10-21/22)、P37(浮動)。
