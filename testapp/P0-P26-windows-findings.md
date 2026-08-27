# Driving P0–P26 with `-actionfile` on Windows

> **This describes the first pass, at 125% display scale, and is superseded per
> app.** A second pass on 2026-08-27 re-measured everything at 100% and took the
> folder from 6 action files to 17. Each file's own header now records what it
> drives, what it found and when it was verified, so **the file is the record
> and this document is the history**. Read `testapp/actions/win/<app>.csv` before
> anything here.
>
> Two findings below were retracted by that pass and are struck through where
> they appear. Both were coordinate mistakes that read as the app ignoring
> input, which is the failure this whole document keeps circling.
>
> **本文件描述的是第一輪、於 125% 顯示縮放下的結果，並已逐 app 被取代。** 2026-08-27 的第二輪在
> 100% 之下重新量測了全部項目，並使該資料夾從 6 個動作檔增為 17 個。每個檔案的標頭現在都記錄了它
> 驅動什麼、發現什麼、以及何時驗證，因此**檔案才是紀錄，本文件是沿革**。在相信此處任何內容之前，
> 請先讀 `testapp/actions/win/<app>.csv`。
>
> 下方有兩項發現已被該輪撤回，並於其出現處以刪除線標示。兩者都是「看起來像 app 忽略輸入」的座標
> 錯誤——正是本文件反覆繞回的那種失敗。

What `Win32Synthesiser` does when it is pointed at each test app's own window,
judged by a screenshot of that app afterwards. Issue #26.

The mechanism being relied on is `d6e35a15`, which replaced `SetForegroundWindow`
— a call Windows refuses to a background-launched process — with
`SetWindowPos(HWND_TOPMOST, SWP_NOACTIVATE)`, which it does not.

All runs below are `-gtk4` (GtkBackend) builds with `SCUI_DEBUG=1`, on one
1920×1080 display at 125%, 2026-08-26. **No WinUIBackend build was driven**; see
"What was not done".

## 在 Windows 上以 `-actionfile` 驅動 P0–P26

把 `Win32Synthesiser` 指向各測試 app 自己的視窗時實際發生了什麼，並以事後對該 app 的截圖判定。
對應 issue #26。

所依賴的機制來自 `d6e35a15`：它以 `SetWindowPos(HWND_TOPMOST, SWP_NOACTIVATE)` 取代了
`SetForegroundWindow`——後者是 Windows 會拒絕背景啟動行程提出的呼叫，前者則不會。

下列所有執行皆為 `-gtk4`（GtkBackend）建置並帶 `SCUI_DEBUG=1`，於單一 1920×1080、縮放 125% 的
顯示器上，日期 2026-08-26。**未驅動任何 WinUIBackend 建置**；詳見「未完成的部分」。

---

## Verdict / 結論

`Win32Synthesiser` works. Pointer motion, single clicks, and the wheel all reach
a GtkBackend window on Windows, the topmost pin holds while the replay runs, and
the window falls back into the normal z-order afterwards. The two failures found
are specific and neither is in the pin:

1. **Keyboard action files cannot run at all** from an app launched by a script.
   Measured, on P19 with a one-row file containing `key,,,,,tab`:

       -actionfile: failed: could not bring our window to the front: this file
       presses keys, and a key event goes to whichever window has focus

   This is `prepareForReplay` refusing, correctly and by design — but the
   practical consequence is worth stating plainly: **no file containing `key`,
   `keydown` or `keyup` is usable on Windows under `testapp/run.zsh`**, so the
   `#478 Ctrl-Q` half of P10 and every text-entry check are out of reach from an
   action file here. Mouse-only files are unaffected.

2. ~~**Clicks stop arriving once SwiftCrossUI replaces a subtree.** P24 pushes one
   navigation level and then ignores everything, including a button in the root
   layout outside the stack. P20 opens its level 2 menu page, which is drawn
   correctly and then responds to nothing. Apps whose view tree stays put — P19,
   P21, P8 — take a whole file of clicks without trouble.~~

   **Wrong, corrected 2026-08-27.** Struck through rather than deleted: it was
   the sweep's most serious-looking finding and what a confident wrong finding
   reads like is worth keeping. The clicks arrive. They were landing on empty
   space, because pushing a level re-lays out the whole window and the controls
   outside the stack move with it. Proved on WSL with xdotool — a different
   synthesiser and a different window system — where the same click at the
   post-push coordinate increments the counter. The relayout itself is real and
   is now #57; the P20 half is not re-tested and is marked suspect, not
   corrected. See the correction block in `actions/win/P24-push-one-level.csv`.

`Win32Synthesiser` 可用。指標移動、單次點擊與滾輪都能抵達 Windows 上的 GtkBackend 視窗；重放期間
置頂釘選維持有效，結束後視窗會回到正常的 z 順序。找到的兩項失敗都很具體，且都不在釘選機制上：

1. **鍵盤動作檔完全無法執行**（由腳本啟動的 app）。在 P19 上以僅含 `key,,,,,tab` 一列的檔案實測，
   得到上方那則錯誤。這是 `prepareForReplay` 依設計正確地拒絕——但實務後果值得直說：**在
   `testapp/run.zsh` 之下，任何含 `key`、`keydown` 或 `keyup` 的檔案在 Windows 上都不可用**，因此
   P10 的「#478 Ctrl-Q」那一半，以及所有文字輸入檢查，在此都無法以動作檔進行。純滑鼠的檔案不受影響。

2. ~~**一旦 SwiftCrossUI 替換了某個子樹，點擊就不再送達。** P24 推入一層之後便對一切無反應，連堆疊
   之外、位於根層版面的按鈕也一樣。P20 的第二層選單頁面有被正確繪出，然後對任何東西都沒有反應。
   而視圖樹維持不變的 app——P19、P21、P8——可以承受整份檔案的點擊而毫無問題。~~

   **此項為誤，已於 2026-08-27 更正。** 採刪除線而非直接移除：它是本次巡檢中看起來最嚴重的發現，而
   「一個自信而錯誤的發現長什麼樣」值得保留。點擊其實有送達，只是落在空白處——推入一層會使整個視窗
   重新排版，堆疊之外的控制項也隨之移動。已在 WSL 上以 xdotool 證實（不同的 synthesiser、不同的視窗
   系統）：以推入後的座標點擊同一個按鈕，counter 確實增加。重新排版本身確有其事，現記錄為 #57；
   P20 的那一半尚未重測，僅標記為存疑而非更正。詳見
   `actions/win/P24-push-one-level.csv` 中的更正區塊。

---

## Per app / 逐一結果

| app | action file | replay reached its own window | what the app did |
|---|---|---|---|
| P0 | none | not run | buttons and an alert; not reached, see below |
| P2 | none | not run | picker and text editor; not reached |
| P3 | none | not run | sidebar list; not reached |
| P5 | none | not run | alerts; not reached |
| P7 | none | not run | list selection; not reached |
| P8 | **new** `P8-scroll-outer.csv` | yes | scrolled down four notches; `Outer row 0–3` became `Outer row 5–8` |
| P9 | none | not run | buttons; not reached |
| P10 | none — **cannot be driven** | n/a | launches, registers the title "P10 hit testing and shortcuts", and shows no window at all. Window capture failed twice and a desktop capture found nothing but the taskbar |
| P13 | none | not run | buttons; not reached |
| P15 | none | not run | scheme buttons; not reached |
| P16 | none | not run | buttons; not reached |
| P17 | none | not run | buttons; not reached |
| P18 | none | not run | opens native file dialogs; see "not worth driving" |
| P19 | existing `P19-open-and-select.csv` | yes | menu opened, `Button item` pressed, `last action -> button item` |
| P20 | **new** `P20-open-level-1.csv` | yes | menu opened, `Level 1 item` pressed. Level 2 page opens and then ignores clicks |
| P21 | **new** `P21-buttons-and-disabled.csv` | yes | `clicks: 3` after three clicks on Enabled and two on Disabled; checkbox ticked |
| P22 | none — nothing to drive | n/a | a size scale plus two width buttons; a screenshot is the whole test |
| P23 | none | not run | table row count and selection; not reached |
| P24 | **new** `P24-push-one-level.csv` | yes | pushed to Level 1, then stopped responding |
| P25 | none — **cannot be driven** | n/a | drag and drop is an OLE negotiation, not a held button; `Sources/InputEvent/README.md` says so and these verbs do not promise it |
| P26 | none | not run | tab switching; not reached |

"not run" means exactly that — the app was built and its window measured or not,
and no replay was attempted before time ran out. It is not a result.

「not run」的意思就是字面上的意思——該 app 已建置，其視窗或量測過或沒有，但在時間用盡前並未嘗試
重放。那不是一項結果。

---

## Apps that are not worth an action file

**P22** — a font size scale. Everything it is for is in one screenshot; the two
width buttons only reflow a paragraph.

**P25** — drag and drop. Holding a button across a move is a drag, and drag and
drop is a different thing: at the operating system level it is an OLE
negotiation in which a source announces types and a target accepts them.
`Sources/InputEvent/README.md` states that the format does not promise it, and
inventing a file that appears to test it would be worse than the gap.

**P27** — shows a `WebView` and an `AngularGradient` and has no control at all.
Its claim is "the window appeared, so neither view aborted", which a screenshot
settles.

**P18** — three buttons, each of which opens a *native* modal dialog. Worth
doing eventually and deliberately skipped here: `testapp/P6.swift` records that a
window pinned topmost puts a file picker behind itself, and `prepareForReplay`
pins for the whole replay, so a file that opens one has a good chance of hanging
a run with an invisible modal dialog holding the app. That needs a session where
somebody can dismiss it by hand.

## 不值得為其撰寫動作檔的 app

**P22**——字級比例尺。它要呈現的一切都在單張截圖裡；那兩個寬度按鈕只是讓段落重新換行。

**P25**——拖放。按住按鍵並移動只是 drag；drag and drop 是另一回事：在作業系統層級，它是一場 OLE
協商，由來源宣告型別、目標決定接受與否。`Sources/InputEvent/README.md` 已載明本格式不對此做出承諾，
而硬編出一個「看起來有在測」的檔案，比留下這個缺口更糟。

**P27**——顯示一個 `WebView` 與一個 `AngularGradient`，完全沒有任何控制項。它的主張是「視窗有出現，
代表兩者都沒有中止」，一張截圖即可判定。

**P18**——三個按鈕，每個都會開啟**原生的** modal 對話框。這件事終究值得做，此處是刻意略過的：
`testapp/P6.swift` 記錄過「置頂的視窗會把檔案選取對話框壓到自己後面」，而 `prepareForReplay` 在
整場重放期間都維持置頂，因此開啟對話框的檔案很可能會讓執行卡在一個看不見、卻抓著 app 的 modal
對話框上。那需要一次「有人能親手把它關掉」的工作階段。

---

## The two failures, in detail

### Keyboard files cannot run

`prepareForReplay` pins the window unconditionally and then, only if the file
contains an action for which `InputAction.needsKeyboardFocus` is true, calls
`SetForegroundWindow` / `BringWindowToTop` and polls `GetForegroundWindow` for
half a second before throwing. On Windows that poll never succeeds for a process
launched from a background shell — which is the whole premise of `d6e35a15`, and
is why the mouse path stopped using `SetForegroundWindow` in the first place.

So the code is right and the limitation is real. What is worth knowing is which
tests it removes: P10's `#478 Ctrl-Q`, P21's `tab` / `shift-tab` focus
traversal, and anything that types. The example in
`Sources/InputEvent/README.md` — the P21 file with `key,,,,,tab` in it — cannot
run on Windows as written.

### 鍵盤檔案無法執行

`prepareForReplay` 會無條件把視窗釘在最上層，然後，只有在檔案中存在 `InputAction.needsKeyboardFocus`
為真的動作時，才呼叫 `SetForegroundWindow` / `BringWindowToTop`，並輪詢 `GetForegroundWindow` 半秒後
拋出例外。在 Windows 上，對於由背景 shell 啟動的行程而言，這個輪詢永遠不會成功——而這正是 `d6e35a15`
的整個前提，也是滑鼠路徑當初不再使用 `SetForegroundWindow` 的原因。

所以程式碼是對的，而這個限制是真實存在的。值得知道的是它移除了哪些測試：P10 的 `#478 Ctrl-Q`、
P21 的 `tab` / `shift-tab` 焦點移動，以及任何需要打字的項目。`Sources/InputEvent/README.md` 中的範例
——那個含有 `key,,,,,tab` 的 P21 檔案——依原樣在 Windows 上無法執行。

### Clicks stop arriving after a subtree is replaced

Two apps, the same shape.

**P24.** The first click pushes: the window reflows, a `‹ Back` bar appears, the
pane reads `Level 1`. Then nothing. Measured twice:

    push, wait 0.9 s, click "Push level 2" twice        -> still Level 1
    push, wait 3.0 s, click "Increment counter",
                      then click "Push level 2"         -> still Level 1, counter 0

The second run is the one that matters: `Increment counter` is in the root
layout outside the stack, so this is not about the pushed view. Both targets
were measured on a capture of the app in exactly that state.

**P20.** Click one opens the menu. Click two on `Level 1 item` works and the app
prints `last action -> level 1`. But clicking `Level 2 submenu` slides the
popover to a second page — confirmed by a desktop capture taken during the
replay, showing `‹ Level 2 submenu`, `Level 2 item` and `Level 3 submenu` — and
nothing on that page responds. Five attempts, settle times from 0.8 s to 3.5 s,
two x positions inside the row, and `last action` never moved off `nothing yet`.

**The control.** P21 takes six clicks in one file at five different positions,
across five state changes, and every one of them lands: three on `Enabled`
counted as 3, two on `Disabled` counted as 0, and the checkbox ticked. So this
is not "the second click never works" and not a coordinate drift.

**What is not established.** Whether *synthesised* clicks stop arriving, or the
app stops responding to clicks at all. Telling those apart needs somebody to
press the button by hand while the app is in that state, which no action file
can do. Note that `testapp/actions/wsl/P24-push-three.csv` pushes three levels in
one file on WSLg, so the sequence is not inherently impossible — but that is a
different platform *and* a different backend build, so it is a hint rather than
a comparison.

### 子樹被替換之後，點擊不再送達

兩個 app，同一種形狀。

**P24。** 第一次點擊確實推入：視窗重新排版、出現 `‹ Back` 列、面板顯示 `Level 1`。之後就沒有反應了。
實測兩次（見上方英文區塊的兩行）。第二次執行才是關鍵：`Increment counter` 位於堆疊之外的根層版面，
因此這與「被推入的視圖」無關。兩個目標座標都是在 app 正處於該狀態時的截圖上量得的。

**P20。** 第一次點擊開啟選單。第二次點擊 `Level 1 item` 成功，app 印出 `last action -> level 1`。
但點擊 `Level 2 submenu` 會讓 popover 滑到第二頁——重放期間的桌面截圖確認了這一點，可看到
`‹ Level 2 submenu`、`Level 2 item` 與 `Level 3 submenu`——而該頁上的任何東西都沒有反應。共五次嘗試，
等待時間從 0.8 秒到 3.5 秒，該列內兩個不同的 x 位置，`last action` 始終停在 `nothing yet`。

**對照組。** P21 在單一檔案中於五個不同位置點擊六次、跨越五次狀態變更，而每一次都命中：`Enabled`
三次計為 3、`Disabled` 兩次計為 0，checkbox 也被勾選。因此這既不是「第二次點擊永遠無效」，也不是
座標漂移。

**尚未確立的部分。** 究竟是**合成的**點擊不再送達，還是 app 根本不再回應任何點擊。要分辨這兩者，
需要有人在 app 處於該狀態時親手按下按鈕，而任何動作檔都做不到。另外，
`testapp/actions/wsl/P24-push-three.csv` 在 WSLg 上能於單一檔案中推入三層，因此這串動作並非本質上
不可能——但那是不同平台**且**不同的 backend 建置，只能算是線索，不能算是對照。

---

## Instrument problems, recorded first

Each of these produces a *plausible* wrong answer rather than an error, and
every app result above is only as good as these.

以下每一項產生的都是「看似合理的錯誤答案」而非錯誤訊息，而上方每一項 app 的結果，其可信度都不會
高於這些前提。

### 1. `ui-lock.zsh` reported "unlocked" for a locked workstation

Measured 2026-08-26 19:28: `ui-lock.zsh status` printed `workstation: unlocked`
while a desktop capture showed the Windows lock screen with "Enter your PIN" on
it. The check was

```zsh
MSYS2_ARG_CONV_EXCL='*' tasklist //FI "IMAGENAME eq LogonUI.exe"
```

`//FI` is the Git Bash spelling that survives MSYS argument conversion as `/FI`
— but `MSYS2_ARG_CONV_EXCL='*'` switches that conversion off, so `tasklist`
received a literal `//FI`, answered `ERROR: Invalid argument/option - '//FI'` on
stderr, and printed nothing on stdout. `grep -q LogonUI.exe` then found nothing.
Side by side, the same prefix with a single `/FI` returns the `LogonUI.exe` row.

**This cost an hour of false results.** Everything run between 19:17 and 20:15
was thrown away: a P19 replay that appeared to click nothing, two probes that
appeared to show a menu refusing to open, and a P21 run that failed with
`SendInput exited with status 5`. Re-run afterwards on a genuinely unlocked
desktop, P19 and P21 both passed on the first attempt. Fixed during this session
by the agent who owns the script, including failing closed when the check cannot
run.

The shape is worth keeping: the exclusion variable and the doubled slash are two
fixes for the same MSYS problem, and they cancel each other out.

於 2026-08-26 19:28 實測：`ui-lock.zsh status` 印出 `workstation: unlocked`，而同時間的桌面截圖
顯示的是 Windows 鎖定畫面。原因為上方那行：`//FI` 是能通過 MSYS 引數轉換而變成 `/FI` 的寫法，但
`MSYS2_ARG_CONV_EXCL='*'` 正好關閉了該轉換，於是 `tasklist` 收到字面上的 `//FI` 並回覆錯誤，stdout
空無一物。

**這件事造成了一小時的假結果。** 19:17 至 20:15 之間的一切都被作廢：一次看似什麼都沒點到的 P19 重放、
兩次看似「選單拒絕開啟」的探測，以及一次以 `SendInput exited with status 5` 失敗的 P21。事後在確實
未鎖定的桌面上重跑，P19 與 P21 都是第一次嘗試就通過。此問題已由負責該腳本的 agent 於本次工作階段
修正，並改為「檢查無法執行時即視為鎖定」。

這個形狀值得記住：排除變數與雙斜線是同一個 MSYS 問題的兩種解法，而它們會互相抵銷。

### 2. What each instrument does on a locked workstation

Only one of them says anything.

| instrument | locked behaviour |
|---|---|
| `SendInput` | fails: `-actionfile: failed: SendInput exited with status 5` (`ERROR_ACCESS_DENIED`) |
| `screenshot.zsh -w` on a GTK window | **succeeds, with fully rendered app content** |
| `screenshot.zsh` on the desktop | returns the lock screen |
| `tasklist /FI "IMAGENAME eq LogonUI.exe"` | present — but see below |

The second row is the trap. A window capture of a GTK window kept coming back
with the app drawn correctly while the desktop behind it was the lock screen, so
"the screenshot looks like the app" is not evidence that the desktop is usable.
Judge the lock by a **desktop** capture, or by `SendInput`'s status 5.

`LogonUI.exe` was present in `tasklist` at 19:18, when input was demonstrably
being delivered, and still present at 21:00 when it was. Its presence alone did
not track the lock state on this machine in either direction — worth re-checking
before trusting a gate built on it.

### 2. 各項儀器在工作站鎖定時的行為

其中只有一項會出聲。表格見上。第二列是陷阱：對 GTK 視窗做視窗擷取，在背後桌面是鎖定畫面的情況下，
仍持續回傳完整算繪的 app 內容——因此「截圖看起來像那個 app」並不能證明桌面可用。判斷是否鎖定，請看
**桌面**擷取，或看 `SendInput` 的 status 5。

`LogonUI.exe` 在 19:18（輸入明顯能送達時）就已存在於 `tasklist` 中，21:00（同樣能送達時）也仍在。
在這台機器上，光憑它的存在與否，無法在任一方向上追蹤鎖定狀態——若某個閘門建立在它之上，值得先重新
確認。

### 3. A GTK popover on Windows is its own top-level window

`screenshot.zsh -w "P20 nested menus"` shows the app with no menu in it, even
with the menu open — which reads exactly like a click that missed. Two runs went
that way before a desktop capture during the replay showed the popover sitting
over the app. **Judge menus by a desktop capture.**

The desktop capture is also what confirms the topmost pin working: with the
replay running, P20's window sat over the browser window that had been covering
it, and after the replay it was back in the normal order.

### 3. Windows 上的 GTK popover 是自己的 top-level 視窗

即使選單已開啟，`screenshot.zsh -w "P20 nested menus"` 顯示的仍是一個沒有選單的 app 畫面——看起來與
「點擊落空」一模一樣。有兩次執行就這樣過去了，直到在重放期間做了一次桌面擷取，才看到 popover 正
覆蓋在 app 之上。**判斷選單請看桌面截圖。**

桌面截圖同時也是「置頂釘選確實有效」的證據：重放進行中時，P20 的視窗壓在原本覆蓋它的瀏覽器視窗之上，
而重放結束後它就回到了正常的順序。

### 4. Coordinates must be pre-divided by the display scale, on GtkBackend

`currentWindowGeometry` reads `GetDpiForWindow` and divides the window origins by
it; `screenPosition` multiplies back. That round trip is correct for a backend
whose layout unit *is* the Windows logical point.

GTK 4 on Windows is not one. Its scale factor is an integer, 125% rounds to 1,
and one GTK layout unit is one physical pixel: an app asking for
`defaultSize(width: 660, height: 460)` captures at 688 × 489 physical pixels.
So a file aimed at a GtkBackend window on a scaled display has to carry
`physical / 1.25`, which is what every file in `testapp/actions/win/` does. It is
a property of the synthesiser meeting GTK, not of the files, and the same file on
a 100% display would need different numbers.

### 4. 在 GtkBackend 上，座標必須先除以顯示縮放比例

`currentWindowGeometry` 讀取 `GetDpiForWindow` 並以其除視窗原點，`screenPosition` 再乘回去。對於
「自身版面單位就是 Windows 邏輯點」的 backend 而言，這一來一回是正確的。

Windows 上的 GTK 4 並非如此。它的 scale factor 是整數，125% 取整為 1，一個 GTK 版面單位就等於一個
實體像素：要求 `defaultSize(width: 660, height: 460)` 的 app，其視窗擷取出來是 688 × 489 實體像素。
因此針對縮放顯示器上的 GtkBackend 視窗所寫的檔案，必須帶入 `實體像素 / 1.25`，而
`testapp/actions/win/` 中的每個檔案都是如此。這是「synthesiser 遇上 GTK」的性質，而非檔案的性質；
同一個檔案在 100% 的顯示器上會需要不同的數字。

### 5. Window-level updates must not undo an action-file pin

Found by reading, and fixed after this note was written.

`prepareForReplay` pins the window with `SetWindowPos(HWND_TOPMOST)` and the
replay depends on it. The first window-level implementation re-applied
`backend.setLevel(ofWindow:to:)` on every `WindowReference.update`; for an app
that never asks for a level, `environment.windowLevel` is `.automatic`, and
`GtkBackend.setLevel` maps anything that is not `.floating` to
`SetWindowPos(handle, HWND_NOTOPMOST, ...)`. So every layout pass during a replay
could un-pin the window the replay just pinned.

The fix is in `WindowReference`: apply the level after the first `show(window:)`,
then reapply unchanged levels only when the effective level is `.floating`.
Unchanged `.automatic` and `.normal` no longer send `HWND_NOTOPMOST` on every
layout pass. Applying after `show(window:)` also matters for GtkBackend, whose
platform handle does not exist until the window is realized.

Verified by compiling P37 on both WSLg and Windows after the fix. This does not
claim to fix the P20/P24 subtree-replacement finding; that remains separate.

### 5. Window level 更新不得解除 action-file 的置頂釘選

由閱讀程式碼發現，並已在寫下本筆記後修正。

`prepareForReplay` 以 `SetWindowPos(HWND_TOPMOST)` 釘住視窗，整場重放都仰賴它。本工作樹中尚未提交的
第一版 `BackendFeatures.WindowLevels` 變更，在每次 `WindowReference.update` 都重新執行
`backend.setLevel(ofWindow:to:)`；對於從未指定 level 的 app，
`environment.windowLevel` 為 `.automatic`，而 `GtkBackend.setLevel` 會把任何非 `.floating` 的值
對應到 `SetWindowPos(handle, HWND_NOTOPMOST, ...)`。於是重放期間的每一次版面配置，都可能把重放剛剛
釘上的視窗解除釘選。

修正位於 `WindowReference`：第一次 `show(window:)` 後才套用 level，之後只有有效 level 為
`.floating` 時才重複套用未改變的 level。未改變的 `.automatic` 與 `.normal` 不再於每次 layout pass
送出 `HWND_NOTOPMOST`。在 `show(window:)` 後才套用同樣重要，因為 GtkBackend 的平台 handle 要到視窗
realize 後才存在。

修正後已編譯 WSLg 與 Windows 的 P37 驗證。這不宣稱已修正 P20/P24 的子樹替換發現；那仍是另一個問題。

### 6. Launching a second instance while the first is alive gives a window-less process

Seen once with P24: a launch produced a live `P24.exe` with a registered window
title and no window on screen, and a relaunch after `taskkill` behaved normally.
This is the GTK single-instance handoff in the form it takes on Windows, and it
is indistinguishable from a launch failure. Kill before every launch and confirm
with `tasklist`, which is what the existing note in `MEMORY.md` says.

P10's window-less state is *not* this: it reproduced from a clean start with no
other instance, twice.

### 6. 在第一個實例仍存活時啟動第二個，會得到一個沒有視窗的行程

在 P24 上遇到一次：某次啟動產生了一個活著的 `P24.exe`，有註冊的視窗標題，螢幕上卻沒有視窗；在
`taskkill` 之後重新啟動則一切正常。這就是 GTK 單一實例交接在 Windows 上呈現的樣子，而它與「啟動失敗」
無從分辨。每次啟動前先 kill，並以 `tasklist` 確認——這正是 `MEMORY.md` 既有筆記所說的。

P10 的無視窗狀態**不是**這一種：它在沒有其他實例的乾淨啟動下重現了兩次。

---

## What was not done, and why

- **No WinUIBackend run.** Every result here is GtkBackend. `Win32Synthesiser`
  is chosen by platform rather than by backend, so the mouse and wheel paths are
  the same code either way — but the *app* side is not, and both failures above
  are on the app side of the boundary. Whether WinUI pushes three navigation
  levels under the same file is open, and it is the most valuable single thing
  left to run.
- **Twelve apps built and measured but never replayed** — P0, P2, P3, P5, P7,
  P9, P13, P15, P16, P17, P23, P26; count them in that list rather than trusting
  the word. Each is a handful of buttons and would take one file; the sweep ran
  out of time waiting for the workstation, which was locked for roughly 70 of the
  150 minutes this took.
- **Nine apps in the P0–P26 range are absent from the table above.** P11, P12 and
  P14 are macOS, Android and iOS apps and out of scope on this machine. P4 and P6
  import the WinUI products, which `-gtk4` removes and `compile.zsh` refuses up
  front, so neither has a GtkBackend build to drive. P1 is dialogs and sheets and
  belongs with P18. P6-v2, P15-DARK and P17-DOE are variants of apps already
  listed.
- **P10 was not diagnosed**, only observed: it starts, keeps running, registers
  its title and shows no window. Whether that predates the uncommitted changes in
  this tree was not checked.

## 未完成的部分，以及原因

- **未執行任何 WinUIBackend 的重放。** 此處所有結果都是 GtkBackend。`Win32Synthesiser` 是依平台而非
  依 backend 選擇的，因此滑鼠與滾輪路徑兩邊都是同一份程式碼——但 **app 端**並非如此，而上述兩項失敗
  都落在這條界線的 app 那一側。WinUI 在同一份檔案下能否推入三層導覽，仍是未知；那是剩下最有價值的
  單一項目。
- **十二個 app 已建置並量測，但從未重放**——P0、P2、P3、P5、P7、P9、P13、P15、P16、P17、P23、P26；
  請直接數那份清單，不要相信這個數字本身。每一個都只是幾個按鈕、只需要一份檔案；本輪掃描是在等待
  工作站的過程中用完了時間——這 150 分鐘裡，工作站約有 70 分鐘處於鎖定狀態。
- **P0–P26 範圍內有九個 app 未出現在上方表格中。** P11、P12、P14 分別是 macOS、Android 與 iOS 的
  app，在本機不在範圍內。P4 與 P6 會 import WinUI 的 product，而 `-gtk4` 會移除它們、`compile.zsh`
  也會提前拒絕，因此兩者都沒有可驅動的 GtkBackend 建置。P1 是對話框與 sheet，與 P18 同類。P6-v2、
  P15-DARK 與 P17-DOE 則是表中已列 app 的變體。
- **P10 只是被觀察，並未被診斷**：它會啟動、持續執行、註冊自己的標題，然後不顯示任何視窗。這是否
  早於本工作樹中尚未提交的變更，並未查證。
