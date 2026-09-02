# Verified process for running a Pn app

Written after producing two rounds of invalid Windows results and committing a
conclusion drawn from them. Every rule below exists because breaking it produced
a confident wrong answer, not because it is tidy.

在產出兩輪無效的 Windows 結果、並且把據此得出的結論 commit 之後寫下。以下每一條規則的存在，都是
因為違反它曾產生一個「有信心的錯誤答案」，而不是因為它比較整齊。

## The rule

**Use `zsh testapp/test.zsh <Pn>`.** Do not write a new harness.

Single-test wrappers live in `testapp/test_support/test_Pn.zsh` and set the
marker, the arguments and the summary pattern for that app. `test_common.zsh`
does the launching, the liveness checks and the teardown, and it already handles
the things listed below that went wrong.

If an app needs different arguments, edit or add its `test_Pn.zsh`. That is the
extension point. An ad-hoc loop in the scratchpad is not.

**請使用 `zsh testapp/test.zsh <Pn>`。不要另寫測試框架。**

各測試的 wrapper 位於 `testapp/test_support/test_Pn.zsh`，負責設定該 app 的 marker、引數與摘要
比對樣式。`test_common.zsh` 負責啟動、存活檢查與收尾，且已處理下列出過問題的各項。

若某個 app 需要不同引數，請修改或新增其 `test_Pn.zsh`。那才是擴充點；scratchpad 裡的臨時迴圈
不是。

## What went wrong, and why each looked convincing

### An exit code of 0 from a GUI app means nothing

`./P7-WinUI.exe` returns 0 immediately whether it works or not, because Windows
GUI-subsystem binaries do not hold the shell. P18, which opens a window
perfectly, reports exit 0 the same way P7 does.

Ten separate observations of "exit=0, no output" were read as ten crashes. They
were ten non-observations.

**Instead:** ask whether a window exists, or whether the app wrote something.
Never infer from the exit code.

GUI app 回傳 0 沒有任何意義：Windows 的 GUI subsystem 執行檔不會佔住 shell，因此
`./P7-WinUI.exe` 無論成功與否都會立刻回傳 0。能正常開窗的 P18 與 P7 一樣回報 exit 0。

十次「exit=0、零輸出」的觀察被讀成十次崩潰，實際上是十次「沒有觀察到任何東西」。

**改為**：詢問視窗是否存在，或該 app 是否寫出了東西。絕不從結束碼推論。

### A backgrounded child dies when the tool call returns

`./P7-WinUI.exe &` from a Bash tool call is gone the moment that call finishes, so a
check in the *next* call always finds nothing. This produced "process alive=0"
for apps that were fine.

**Instead:** launch and check inside one invocation, or let `test_common.zsh`
own the lifetime.

以背景方式啟動的子行程會在工具呼叫返回時消失：在一次 Bash 呼叫中執行 `./P7-WinUI.exe &`，該行程會在
該次呼叫結束時一併終止，因此*下一次*呼叫中的檢查必然什麼都找不到。這使得原本正常的 app 被回報為
「process alive=0」。

**改為**：在同一次呼叫內完成啟動與檢查，或交由 `test_common.zsh` 掌管其生命週期。

### `cmd /c start /b zsh` hands the script a Windows-form PATH

This is the one that invalidated a whole run and a commit. A script launched
that way starts with `C:\...;C:\...` rather than `/c/...:/c/...`, and prepending
POSIX entries produces a mixture MSYS cannot convert. The child then cannot
resolve the GTK DLLs and dies before any Swift code runs -- no window, no
output, no event log entry.

The same script run from a normal MSYS environment works. So the harness, not
the app, decided the result.

**Instead:** run the harness from the Bash tool's own environment, or set PATH
inside the script from a known-POSIX base rather than prepending to whatever was
inherited.

`cmd /c start /b zsh` 會把 Windows 格式的 PATH 交給腳本——這一項使整輪執行與一個 commit 失效。
以該方式啟動的腳本，其起始 PATH 為 `C:\...;C:\...` 而非 `/c/...:/c/...`，此時在前方接上 POSIX
項目會產生 MSYS 無法轉換的混合格式。子行程因而無法解析 GTK 的 DLL，並在任何 Swift 程式碼執行前
即死亡——沒有視窗、沒有輸出、事件記錄中也沒有任何項目。

同一支腳本在正常的 MSYS 環境下執行則一切正常。因此決定結果的是測試框架，而非 app。

**改為**：在 Bash 工具自身的環境中執行測試框架；或在腳本內以已知為 POSIX 的基底設定 PATH，而非
在繼承來的內容前面接續。

### Absence of output is not evidence

A grep that finds nothing looks identical whether the app printed nothing
because it was silent, or because it never started, or because the pipeline ate
it. "0 GTK warnings" was reported for an app that produced no output at all, and
read as a clean run.

**Instead:** make the app write a file, and check the file exists. A trace at
`App.init`, `App.body` and `RootView.body` answers "how far did it get" with no
ambiguity -- and it was what finally showed P7 starting normally.

沒有輸出並不構成證據：一次找不到結果的 grep，無論是因為 app 本來就安靜、從未啟動，或輸出被
pipeline 吃掉，看起來都完全相同。曾有一支完全沒有任何輸出的 app 被回報為「0 個 GTK 警告」，並被
讀成一次乾淨的執行。

**改為**：讓 app 寫出檔案，並檢查該檔是否存在。在 `App.init`、`App.body` 與 `RootView.body` 設下
追蹤點，可毫無歧義地回答「它進行到哪一步」——而這正是最終顯示 P7 一切正常的方法。

## Checking a window on Windows

`screenshot.zsh -w "<title>"` captures the named window directly whatever is in
front of it, falling back to the desktop and saying which it used. Titles come
from `WindowGroup("...")` in the app's source.

GTK 4 windows on Windows did not respond to AppActivate until `show(window:)`
was changed to call `gtk_window_present`; before that, desktop captures
photographed whatever was in front and three of them were taken for captures of
a player.

在 Windows 上檢查視窗：`screenshot.zsh -w "<標題>"` 會直接擷取指定名稱的視窗，不受前方遮擋影響；
若失敗則回退為擷取桌面，並明白說出實際使用了哪一種。標題取自 app 原始碼中的
`WindowGroup("...")`。

在 `show(window:)` 改為呼叫 `gtk_window_present` 之前，Windows 上的 GTK 4 視窗不回應 AppActivate；
在那之前，桌面擷取拍到的是當時位於前方的任何內容，其中三張被誤認為播放器的截圖。

## Standing requirements

- Build with `-gtk4` on Windows, or the app links WinUIBackend instead.
- Put `C:/gtk4/bin` on PATH before running, in POSIX form.
- On a hybrid-graphics laptop, record the GPU preference per executable before
  measuring anything, or two builds silently run on two different GPUs.

- 於 Windows 上必須以 `-gtk4` 建置，否則 app 會改為連結 WinUIBackend。
- 執行前需將 `C:/gtk4/bin` 以 POSIX 形式加入 PATH。
- 在混合顯示卡筆電上，量測任何項目之前，須先為每個執行檔登記 GPU 偏好，否則兩個建置版本會靜默地
  在兩顆不同的 GPU 上執行。
