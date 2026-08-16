# testapp

這裡放的是可獨立執行的測試 app，用來重現特定 upstream issue；同時也放置說明哪些 app 測什麼、哪些行為已驗證過的文件。

**這個目錄不存在於 upstream。** 這裡的內容不應直接放進 pull request，因此所有碰到 `testapp/` 的 commit 都在 `issue_commits.csv` 標記為 `local`。如果某個 commit 同時混入 `Sources/` 和 `testapp/` 的變更，送 upstream 前需要把 `testapp/` 那半邊拆掉。

## 從這裡開始

| 問題 | 檔案 |
| --- | --- |
| 這個 issue 要在哪個平台跑？結果算不算數？ | `UI-test-plan platform-en.md` |
| PN app 的測試步驟是什麼？ | `UI-test-plan overall-en.md` |
| GtkBackend 工作計畫是什麼？ | `UI-test-plan linux-en.md` |
| AppKit/Android/iOS 工作計畫是什麼？ | `UI-test-plan bug-en.md` |
| 每個 upstream issue 目前狀態如何？ | `issues.csv` |
| 哪個 commit 修了什麼？能不能送 upstream？ | `issue_commits.csv` |

`UI-test-plan platform-en.md` 是入口文件：它把目前涵蓋的 40 個 issue 對應到 6 個平台，並在每個格子標示該平台的測試結果是否能判定 issue、只是比較用，或沒有資訊價值。

## Apps

P0-P17 每個都是一個 Swift 檔，會建成獨立執行檔。P0-P6 來自 WinUIBackend 工作，P7-P10 與 P15 針對 GtkBackend，P11 針對 AppKitBackend，P12 針對 AndroidBackend，P14 針對 UIKitBackend，P13、P16、P17 則涵蓋 core layout 與 split-view 行為。完整對照在 `UI-test-plan platform-en.md`。

```sh
zsh testapp/compile.zsh P7 P15 P17     # 只建部分 app
zsh testapp/compile.zsh                # 建全部 app
```

輸出會放在 `testapp/output/`：Linux/macOS 上是 `PN`，Windows 上是 `PN.exe`。`output` 目錄和 `.compile-work` 建置樹都不追蹤。

## 環境設定

| Script | 用途 |
| --- | --- |
| `install_tool_wsl.sh` | WSL：GTK 4、Swift tarball，以及 Ubuntu 26.04 需要的 libxml2/ICU shim |
| `install_tools_ios.zsh` | macOS：iOS Simulator toolchain，會由 `compile.zsh -ios` 自動呼叫 |

## 其他 scripts

| Script | 用途 |
| --- | --- |
| `screenshot.zsh` | 擷取合成後的桌面畫面；這是唯一能看到 D3D/DirectComposition 內容的方式 |
| `gpu-matrix.zsh`, `P6-test.zsh`, `test_P6.zsh` | P6 throughput matrix 與無人值守測試 |
| `rebase.zsh` | rebase 後檢查 `issue_commits.csv` 內的 hash 是否仍存在於分支上 |

`rebase.zsh` 存在是因為 rebase 會靜默孤立已記錄的 hash：它們仍可能從 reflog resolve，所以直到下一次 clone 前都看不出問題。

## 紀錄

`P6_findings/` 保存 NV12 工作背後的 throughput 量測資料，`comments/` 則保存準備貼到 upstream issue 的說明稿。

有兩份文件刻意不追蹤、只屬於本地 checkout：`UI-test-plan overall-zhTW.md` 這份繁中測試計畫，以及 `UI-test-results.md`。測試步驟若有更新，繁中與英文兩份都要改，即使目前只有 `UI-test-plan overall-en.md` 會提交。
