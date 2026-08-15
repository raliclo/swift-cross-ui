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
| 已修 | 12 | #493 #548 #523 #659 #660 #449 #471 #401 #470 #204 #190 #156 |
| 只修了 WinUI 半邊 | 2 | #389 #390（GTK 半邊仍開著） |
| 已有 repro，未驗證 | 1 | #160 |

可重跑的核對指令：

```sh
awk -F, 'NR>1 && $3 ~ /WinUIBackend/ && $4 !~ /^fixed-p/' testapp/issues.csv
```

## 總覽

WinUIBackend 剩下 3 件，而且沒有一件屬於原本最擔心的 crash 或生命週期類。
**瓶頸已經從「不知道要修什麼」變成「repro app 都建好了但一次都沒跑過」。**

## 待辦

### 只差執行一次測試

- #160 Fix WinUIBackend NavigationSplitView initial layout

  - 問題：SplitExample 初始 layout 錯誤，但 state change 或 resize 後會恢復。
  - 現況：**P16 已備妥**，複製 SplitExample 的結構並加上每個 pane 的尺寸量測，
    在 WinUIBackend 與 GtkBackend 上都建置通過。
  - 執行：`./testapp/output/P16.exe`，步驟見 `UI-test-plan overall-en.md`。
  - 注意：**先讀數字再動視窗**。縮放視窗正是兩種會修正它的操作之一，任何互動
    都會破壞證據。步驟 2 與步驟 5 的差值就是這個 bug 的量化結果。
  - 可能方向：初次 render 前 WinUI 回報尺寸可能不可靠；需要延後 layout、
    二次 measure，或在 first arrange 後觸發 update。

### WinUI 已修、GTK 半邊仍開著

這兩件的 WinUI 部分已經完成，剩下的工作全在 GtkBackend，屬於 WSL 那條線。
repro 步驟早就存在，是當初修 WinUI 版本時寫的。

- #389 [GTK][WinUI] Images aren't clipped

  - 現況：`fixed-winui-p3;open-gtk`。P3 步驟 6-9 已涵蓋。
  - 可能方向：GTK 側的 frame clipping；WinUI 那邊的修法可作參考。
- #390 [GTK][WinUI] Disabled buttons don't appear disabled

  - 現況：`fixed-winui-p2;open-gtk`。P2 步驟 7-8 已涵蓋。
  - 可能方向：disabled 狀態的 foreground/background/opacity；注意跨 backend parity。

## 建議近期工作切入點

1. **跑 P16**，確認 #160 是否仍重現，並記下兩組 pane 尺寸。這是唯一純
   Windows 的待辦，且不依賴任何其他人。
2. 一併跑 P2、P3 的 GTK 版本（在 WSL），確認 #389、#390 的 GTK 半邊。這三件
   一起測完，WinUIBackend 這條線就清空了。
3. 測完再改 `Sources/`。目前沒有任何一支 repro app 被實際執行過，盲修比不修更糟。

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
