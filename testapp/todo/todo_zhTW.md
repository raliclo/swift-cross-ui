# WinUIBackend 待辦整理

來源：https://github.com/moreSwift/swift-cross-ui/issues?q=is%3Aissue%20state%3Aopen%20label%3AWinUIBackend

初次整理：2026-07-09
更新：2026-08-14

## 這次更新改了什麼

2026-07-09 版列出 15 件 open issue 並建議先做 #493、#548、#523，再挑
#471、#401、#449 當小 PR。**那份清單上的 12 件現在已經修好了**，包含全部
的建議切入點，所以整份優先順序都已失效。

逐項核對 `testapp/issues.csv` 的結果：

| 狀態 | 件數 | Issues |
|---|---|---|
| 已修 | 14 | #493 #548 #523 #659 #660 #449 #471 #401 #470 #204 #190 #156 #389 #390 |
| 已修，仍需人工互動驗證 | 1 | #160 |
| 已確認未實作 | 1 | P30/P39 WinUI visual effects：opacity 以外仍為 no-op |

可重跑的核對指令：

```sh
awk -F, 'NR>1 && $3 ~ /WinUIBackend/ && $4 !~ /^fixed-p/' testapp/issues.csv
```

## 總覽

WinUIBackend 目前剩下的本地待辦集中在 #160 的互動驗證，以及 P30/P39 visual effects 的
Composition / Win2D effect graph 實作。#389 / #390 的 GTK 半邊已在 `testapp/issues.csv`
標為 fixed，原本「只修 WinUI 半邊」的敘述已過時。

## 待辦

### 只差執行一次測試

- #160 Fix WinUIBackend NavigationSplitView initial layout

  - 問題：SplitExample 初始 layout 錯誤，但 state change 或 resize 後會恢復。
  - 現況：**P16 已備妥**，複製 SplitExample 的結構並加上每個 pane 的尺寸量測，
    在 WinUIBackend 與 GtkBackend 上都建置通過。
  - 執行：`./testapp/output/P16.exe`，步驟見 `UI-test-plan overall-en.md`。
  - 注意：**先讀數字再動視窗**。縮放視窗正是兩種會修正它的操作之一，任何互動
    都會破壞證據。步驟 2 與步驟 5 的差值就是這個 bug 的量化結果。
  - 2026-08-31：Windows initial capture 可見，但 probe 仍回報 `sidebar: 0 x 22`、
    `detail: 0 x 22`、之後 `detail: 734 x 22`。已修正 `compile.zsh` 沒把
    `SCUI_DEBUG=1` 傳成 `-Xswiftc -DSCUI_DEBUG` 的問題，也讓 `ActionFileReplay`
    在 WinUI console redirection 下仍能寫出 `actionfile-replay.log`。目前 replay hook
    可觀察，但 `actions/win/P16-force-update.csv` 尚未讓 Force update / sidebar selection /
    column switch 反映到畫面，需改查 Win32 synthetic input 對 WinUI 控制的命中、focus 或
    activation。
  - 2026-08-31 補充：清空 `actionfile-replay.log` 後重跑，`SendInput` 回報
    `ERROR_ACCESS_DENIED`，此輪不能當作 app 行為證據。final screenshot 仍可見 sidebar row
    內容被壓窄換行；已試過 `ListViewItem.horizontalContentAlignment = .stretch` 與 list item /
    content width sync，截圖未改善並已撤回。真正有效的修正是讓 WinUI `createSplitView`
    初始設定 `openPaneLength = 200`，避免 core layout 第一次以 0-width sidebar 計算 row。
    最新 P16 final screenshot 顯示 `sidebar: 180 x 22`、`detail: 660 x 22`，row 文字不再換行。
  - 可能方向：初次 render 前 WinUI 回報尺寸可能不可靠；需要延後 layout、
    二次 measure，或在 first arrange 後觸發 update。

### 已確認未實作

- P30/P39 WinUI visual effects

  - 現況：`WinUIBackend+VisualEffects.swift` 只設定 `widget.opacity`。P39 的 PIL crop comparison
    已確認 Windows 上 blur、saturation、brightness、contrast、grayscale、hueRotation 與 control
    完全相同；WSLg/GTK 對照則有可量測差異。
  - 2026-09-01：已將 WinUI unsupported-effect warning 改為每個 effect 名稱只回報一次，避免 update
    pass 反覆洗 console。這只是診斷降噪，非 rendering 修復。
  - 原因：WinUI binding 有 `CompositionEffectFactory` / `CompositionEffectBrush`，但目前專案沒有
    Win2D `Microsoft.Graphics.Canvas.Effects` 類型可建立 Gaussian blur / color matrix 類 effect
    graph。
  - 方向：補 Win2D dependency/binding，或建立等價的 `IGraphicsEffect` effect graph 後再套進
    Composition brush；在此之前不要把非 opacity 效果標成已修。

## 建議近期工作切入點

1. **修 WinUI actionfile control activation，或改用另一條可靠輸入路徑**，讓 P16 的 Force update /
   column switch 可以自動驗證。
2. 重跑 P16：先記錄 initial pane width，再執行 Force update，最後切到 3 column 對照。若
   `SendInput` 仍回 `ERROR_ACCESS_DENIED`，先排除 elevated foreground / desktop lock 狀態。
3. 人工點 P16 的 Force update / sidebar selection / column switch，確認 state update 後 layout 仍穩定。

## 已經可以送 PR 的 commit

不在上面的 issue 清單裡，但屬於同一條 Windows 工作線，記錄於
`testapp/issue_commits.csv`：

| Commit | 主題 | 備註 |
|---|---|---|
| `9ac01c11` | GeometryReader doc 範例修正 | 最小的一個：兩行註解，純文件 |
| `b35939f1` | file dialog 後的前景焦點歸還 | 無對應 upstream issue，測 P6 時發現 |
| `8dc6380b` | P6 首幀發布的自我死鎖 crash | 早於本次工作，獨立於 NV12 |

另有兩筆 NV12 的 commit 卡在命名：`Sources/WinUIBackend/D3D11VideoInterop.swift`
有六個 P6- 前綴的 public type，送 PR 前要先改名。

送出前提醒：upstream 的 LLM policy 要求 PR 描述由作者本人撰寫，並揭露 LLM 參與。
