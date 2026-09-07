# Action files for the ten undriven Windows/GtkBackend apps (todo #89)

**Design only. This document contains no coordinates, and writing one into it
would defeat its purpose.** Every number in an action file has to be read off a
capture of the real window. A plausible coordinate that was never measured
replays without error, clicks empty space, and reports success — the one failure
shape this project has already paid for twice (`P24-push-one-level.csv`, and the
`748x518` / `648x458` capture sizes corrected on 2026-09-06). What follows is
everything that can be settled from the source; the coordinates come from the
captures.

**僅為設計，本文件不含任何座標，寫入座標會使其失去意義。** 動作檔中的每一個數字都必須從真實視窗
的擷圖上讀出。一個從未量測過、卻看似合理的座標，重放時不會報錯、會點在空白處，並回報成功——而這
正是本專案已經付過兩次代價的失敗形狀（`P24-push-one-level.csv`，以及 2026-09-06 更正的
`748x518` / `648x458` 擷圖尺寸）。以下是所有能從原始碼確立的事；座標則來自擷圖。

---

## How the ten were derived / 這十支如何推導而來

Re-derive rather than trust this list — it is true on the day it was written and
a new build or a new file changes it:

```zsh
ls -1 testapp/output/P*-gtk4.exe | sed 's#.*/##;s#-gtk4\.exe##' | sort -u > built
ls -1 testapp/actions/win/ | grep -oE '^P[0-9]+(-[A-Z]+)?' | sort -u > have
comm -23 built have
```

Run 2026-09-07: 43 built, 33 with a file, **10 without** — P11, P15-DARK,
P17-DOE, P25, P27, P37, P39, P40, P43, P44. That matched the list this task was
given, exactly.

請重新推導而非信任此清單——它只在撰寫當日為真，一次新的建置或一個新檔案都會改變它。
2026-09-07 執行結果：已建置 43 支、有動作檔者 33 支、**無動作檔者 10 支**，與本任務所給清單完全相符。

---

## Summary / 總覽

| App | Verdict | Why, in one line |
|---|---|---|
| **P44** | **Drivable** | One real `Button` that toggles state, relabels itself, moves a status line and rewrites cell 3 — and logs the transition to a file |
| **P11** | **Drivable** | Three `Button`s, two `Slider`s reachable by `mousedown`/`move`/`mouseup`, a 40-row `ScrollView` and a `DatePicker`; write counters make a drag falsifiable |
| **P27** | **Partly** | No buttons, but a real `WebView` (GtkBackend conforms to `BackendFeatures.WebViews`) that `scroll` can move — everything else is a still picture |
| **P15-DARK** | **Partly** | Its one `Button` has an empty action and proves nothing; the evidence is the window's colour at launch, which needs no input |
| **P17-DOE** | **Not drivable** | Zero controls. Three static columns compared by eye; the DOE it exists to decide was already settled (`#389` is `fixed-gtk-p3`) |
| **P39** | **Not drivable** | Zero controls. Ten static cells read against the control cell |
| **P40** | **Not drivable** | Zero controls. Seven static tiles plus two bare-text rows |
| **P43** | **Not drivable** | Zero controls. Four static shapes; the claim is which pixels are background |
| **P37** | **Not drivable — and a driven file would lie** | `prepareForReplay` pins the window `HWND_TOPMOST` unconditionally, so the replay harness supplies the exact property `.topmost()` is under test for |
| **P25** | **Not drivable** | Drag and drop is an OLE negotiation, not a held button; `SendInput` cannot originate one, so the drop and even the hover feedback are unreachable |

| App | 判定 | 一句話理由 |
|---|---|---|
| **P44** | **可驅動** | 一個真正的 `Button`，會切換狀態、改變自己的標籤、移動狀態列並重繪第 3 格，且將該轉換寫入檔案 |
| **P11** | **可驅動** | 三個 `Button`、兩個可用 `mousedown`/`move`/`mouseup` 觸及的 `Slider`、一個 40 列 `ScrollView` 與一個 `DatePicker`；寫入計數器使拖曳成為可證偽的 |
| **P27** | **部分** | 沒有按鈕，但有一個真正的 `WebView`（GtkBackend 符合 `BackendFeatures.WebViews`），`scroll` 可以捲動它；其餘皆為靜態畫面 |
| **P15-DARK** | **部分** | 它唯一的 `Button` 動作為空，證明不了任何事；證據是啟動時視窗的顏色，而那不需要輸入 |
| **P17-DOE** | **不可驅動** | 零控制項。三欄靜態畫面以肉眼比較；它所要決定的 DOE 早已定案（`#389` 狀態為 `fixed-gtk-p3`） |
| **P39** | **不可驅動** | 零控制項。十個靜態格子，與對照格相比 |
| **P40** | **不可驅動** | 零控制項。七個靜態方塊，外加兩列純文字 |
| **P43** | **不可驅動** | 零控制項。四個靜態形狀；其主張在於「哪些像素是背景」 |
| **P37** | **不可驅動——且驅動它的檔案會說謊** | `prepareForReplay` 無條件將視窗釘為 `HWND_TOPMOST`，因此重放框架親手提供了 `.topmost()` 正要受測的那項性質 |
| **P25** | **不可驅動** | 拖放是一場 OLE 協商，而非「按住按鍵」；`SendInput` 無法發起它，因此放置乃至懸停回饋都構不到 |

**Split: 2 drivable, 2 partly, 6 not drivable.** Six of the ten cannot be driven
by clicks and keys, and saying so is the result — not a gap to be filled with
files that pass by doing nothing.

**分佈：可驅動 2、部分 2、不可驅動 6。** 十支中有六支無法以點擊與按鍵驅動，而如實說出這件事本身
就是結果——那不是一個「該用『靠什麼都不做而通過』的檔案來填補」的缺口。

---

## The decision this document cannot make: does a `sleep`-only file belong in `win/`?

**Six of the ten have no controls, and the repository already contains two
opposite answers about what to do with such an app.** The parent session has to
pick one; this section states both fairly, because picking wrongly is how the
"passes by doing nothing" failure gets in.

**`testapp/actions/win/README.md` says no.** Its "Eight apps that should never
get a file here" section names P25, P27, P37, P38, P39, P40, P42 and P43 —
**six of these ten** — and argues: all have zero interactive controls, a click
row aimed at one lands on a gradient and still reports success, and *"even a
`sleep`-only file could produce no readable evidence: it would take a
screenshot, and `screenshot.zsh` already does that without a replay in the
way."*

**`actions/mac/`, `actions/ios/` and `actions/android/` say yes**, and they say
it for these exact apps. Every one of the ten except P15-DARK and P17-DOE has a
mac file; ios has all ten. Their form is not an empty `sleep` — it is a sequence
of `sleep` rows whose `note` column each carries **one measured, falsifiable
claim** about the capture, marked `(VERIFIED)`. `mac/P43-gradient-clipped-to-the-shape.csv`
asserts that a probe at the corner of the circle's frame reads the window
background while the same relative corner of the *rectangle* reads a filled
colour — which is what turns "the fill was clipped" from an impression into a
measurement, and the second probe is the control that stops the first from being
a miss.

**`actions/wsl/P13-zstack.csv` is the precedent on this backend**, and it is the
weak form: a single `sleep` whose note says only *"let the window settle before
the screenshot"*. Its header gives the honest reason — the file exists *"so the
run is driven the same way as every other, and so the screenshot is taken at a
defined moment rather than whenever the script got round to it."* That is a real
benefit and a small one, and it is the thing `win/README.md` is right to say
`screenshot.zsh` already provides.

**So the two idioms are not the same thing and the disagreement is narrower than
it looks.** `win/README.md` is right about the weak form and does not address
the mac form. The mac form's value is not that it drives anything — it drives
nothing — but that the assertions are **written down, in the repository, next to
the app, in a form a later reader can re-check against a new capture**. A
screenshot alone carries no claim; a person looking at P40's seven tiles a month
from now has no record of what "correct" was.

**A recommendation, not a decision.** Where this document proposes a `sleep`-only
file below, it proposes the **mac form only** — one claim per row, each naming a
probe and the reading it must give — and never the weak form. If the parent
session does not want to measure those probes, the correct outcome is **no
file**, not a file with unmeasured notes. An unverified `(VERIFIED)` marker is
the same lie as an unmeasured coordinate, one layer up.

## 本文件無法代為做出的決定：只含 `sleep` 的檔案該不該進入 `win/`？

**十支中有六支沒有控制項，而本儲存庫對於「這種 app 該怎麼辦」已經同時存在兩個相反的答案。** 必須由
上層工作階段擇一；本節公平地陳述兩者，因為選錯正是「靠什麼都不做而通過」得以混入的途徑。

**`testapp/actions/win/README.md` 說不。** 其「八支永遠不該有動作檔的 app」一節點名 P25、P27、P37、
P38、P39、P40、P42、P43——即**這十支中的六支**——並主張：它們全都沒有可互動的控制項；指向它們的點擊
列會落在漸層上卻仍回報成功；而且*「即使是只有 `sleep` 的檔案也產生不了可讀的證據：它只會擷一張圖，
而 `screenshot.zsh` 本來就能做到，不需要一次重放擋在中間。」*

**`actions/mac/`、`actions/ios/` 與 `actions/android/` 說是**，而且正是針對這些 app 這麼說。除
P15-DARK 與 P17-DOE 外，這十支每一支都有 mac 檔；ios 則十支俱全。它們的形式並非一個空的 `sleep`
——而是一串 `sleep` 列，每一列的 `note` 欄承載**一項已量測、可證偽的主張**，並標記 `(VERIFIED)`。
`mac/P43-gradient-clipped-to-the-shape.csv` 主張：在圓形 frame 角落的取樣點讀到視窗背景，而**矩形**
的相同相對角落卻讀到填充色——正是這一點把「填充被裁切了」從印象變成量測，而第二個取樣點就是那個
「使第一個不至於只是落空」的對照。

**`actions/wsl/P13-zstack.csv` 是本 backend 上的先例**，且屬於弱形式：單一個 `sleep`，其 note 只寫
*「讓視窗在截圖前安定下來」*。其標頭給出了誠實的理由——該檔存在的目的，是*「讓這次執行與其他所有
執行以相同方式驅動，並使截圖發生在一個明確的時點，而非腳本恰好輪到的時候。」* 那是真實但微小的
好處，也正是 `win/README.md` 有理由指出「`screenshot.zsh` 本來就能提供」的那一項。

**因此這兩種形式並非同一回事，分歧也比表面上窄。** `win/README.md` 對弱形式的判斷是對的，而它並未
論及 mac 的形式。mac 形式的價值不在於它驅動了什麼——它什麼也沒驅動——而在於那些主張被**寫了下來、
存在儲存庫裡、就放在該 app 旁邊，且其形式讓日後的讀者能拿新的擷圖重新核對**。單張截圖不承載任何
主張；一個月後看著 P40 那七個方塊的人，手上沒有任何「何謂正確」的記錄。

**這是建議，不是決定。** 下文凡提議只含 `sleep` 的檔案處，一律只提議 **mac 形式**——每列一項主張，
各自指名一個取樣點及其必須給出的讀數——絕不提議弱形式。若上層工作階段不打算量測那些取樣點，正確的
結果是**不寫檔案**，而不是寫一個帶著未量測 note 的檔案。一個未經查證的 `(VERIFIED)` 標記，與一個
未經量測的座標是同一種謊言，只是高了一層。

---

# P44 — clipping / 裁切

**Do this one first.** It is the only app of the ten whose whole point is a state
change driven by one press, and the only one that writes the transition to a log
file, so the run leaves evidence that does not depend on reading pixels.

**這一支請最先做。** 它是十支之中唯一一支「整個重點就是一次按壓所驅動的狀態改變」的 app，也是唯一
一支會把該轉換寫進 log 檔的，因此該次執行留下的證據不必靠判讀像素取得。

### 1. What it is for / 它的用途

`testapp/P44.swift`, written 2026-09-04. Does `clipped()` cut a child down to its
frame? It exists because nothing exercised `BackendFeatures.Clipping` on Android
and AndroidBackend did not implement it, so `clipped()` went through
`@CastBackend` and would have taken the process down. **GtkBackend does conform**
— `Sources/GtkBackend/GtkBackend.swift:49` lists `BackendFeatures.Clipping` — so
on Windows/GtkBackend the question is not "does it abort" but "does it actually
cut".

No issue number. **P44 is absent from `UI-test-plan overall-en.md` entirely**
(the plan stops at P41) and absent from `issues.csv`, `P0-P26-windows-findings.md`
and `UI-test-results_overall_en.md`. Its own header is the only specification;
that is not a defect in the app, but it means there is no second source to
cross-check against.

`testapp/P44.swift`，撰於 2026-09-04。`clipped()` 會把子元件裁到它的 frame 之內嗎？它的存在是因為
Android 上沒有任何東西用到 `BackendFeatures.Clipping`，而 AndroidBackend 並未實作它。**GtkBackend
確實符合該 conformance**（`Sources/GtkBackend/GtkBackend.swift:49`），因此在 Windows/GtkBackend 上，
問題不是「會不會中止」，而是「究竟有沒有裁切」。無 issue 編號。**P44 完全未出現在
`UI-test-plan overall-en.md` 中**（該計畫停在 P41），亦未出現於 `issues.csv` 與各結果文件。

### 2. Interactive controls, in layout order / 可互動控制項（依版面順序）

| Line | Control | Live? |
|---|---|---|
| 120 | `Button(clipThirdCell ? "Unclip the third cell" : "Clip the third cell")` | **Yes — the only control in the app.** Toggles `clipThirdCell`, and calls `P44Diagnostics.write` |
| 127 | `Text("third cell: ...")` | Inert readout, driven by the button |
| 145 | `P44Cell(label: "no clipped()", clipped: false)` | Inert. Fixed control cell |
| 146 | `P44Cell(label: "clipped()", clipped: true)` | Inert. Fixed clipped cell |
| 147 | `P44Cell(label: "toggled", clipped: clipThirdCell)` | Inert, but **redrawn by the button** |

One clickable target. Window `defaultSize` 420x620 (line 80) — the narrowest of
the ten, and the cells are stacked vertically with 80pt gaps (line 144), so the
button sits well above them and a miss cannot accidentally land on a cell.

僅一個可點擊目標。視窗 `defaultSize` 為 420x620（第 80 行），是十支中最窄的；各格沿垂直方向以 80pt
間距堆疊（第 144 行），因此按鈕位於它們上方甚遠處，落空的點擊不會誤中某一格。

### 3. The sequence worth replaying / 值得重放的序列

1. **Settle.** `sleep` long enough for the three cells to lay out. The mac file
   uses 1.5 s and P44 has three cells to build; do not shorten this to 0.4 s.
   *Proves nothing on its own — it stops the first click racing the layout.*
2. **Read the label before pressing.** No action; this is a note on the settle
   row. The button must read `Clip the third cell` and line 127 must read
   `third cell: no clipped()`. *Establishes the starting state, so step 3 is a
   transition rather than an observation.*
3. **Click the button.** *This is the whole test.* Three things must move
   together: the button relabels to `Unclip the third cell`, line 127 becomes
   `third cell: clipped()`, and **cell 3's orange must shrink from 200x100 to
   120x60 with its blue corner gone**. The blue corner is the load-bearing part —
   see step 5.
4. **Settle again** so the redraw completes before the capture.
5. **Click the button a second time.** *Proves the change is a toggle and not a
   one-way latch, and that the app can return to the spilling state.* Cell 3
   must go back to spilling, blue corner restored. This step is cheap and
   catches a real failure class: a backend that applies a clip and cannot remove
   it.

The order matters and cell 1 and cell 2 are never clicked, deliberately: they
never rebuild, they differ in exactly one modifier, and they are the reference
that makes cell 3's change legible. A file that touched them would be measuring
nothing.

順序是重要的，而第 1、2 格刻意從不被點擊：它們從不重建、彼此恰好只差一個 modifier，並且是「使第 3
格的變化可被讀出」的參照。碰它們的檔案什麼也量不到。

### 4. What a reader should see afterwards / 事後應看到什麼

Three independent, simultaneous changes, and **all three must move or the run is
a failure**:

- The button's own label, `Clip the third cell` → `Unclip the third cell`.
- The status line, `third cell: no clipped()` → `third cell: clipped()`.
- Cell 3's orange block: 200x100 with a 40x40 blue corner → 120x60, **orange
  only**.

**The blue corner is what makes this evidence rather than a launch check.** The
app's own header (lines 206-239) explains why: a uniformly orange child measures
120x60 both when it is *clipped to the centre of the frame* and when it is
*resized to the frame*, and the picture is identical. The 40x40 marker sits at
the top-left of the 200x100 child and the frame centres its child, so a clip to
120x60 keeps the middle and throws the whole marker away. So:

- orange only, 120x60 → the child was **CLIPPED** (correct)
- blue corner still present, 120x60 → the child was **RESIZED**, not clipped
- still 200x100 → nothing happened

**And there is a log.** `P44Diagnostics.write` (line 122) appends
`third cell clipped: true` / `false` to `p44-debug-events.log` on every press —
but **only under `--debug`** (line 46), so the launch must pass it or the file
will not exist. Per `actions/win/README.md`, the log lands in the **current
directory** of whatever launched the app, not `testapp/output/`. Two presses must
leave two lines, `true` then `false`. That is the part of the result that does
not require anyone to interpret an image.

**藍色角落正是使這件事成為證據、而非啟動檢查的關鍵。** app 自身標頭（206-239 行）說明了理由：純橘色
的子元件在「被裁到 frame 中央」與「被縮小到 frame」兩種情況下都量得 120x60，畫面完全相同。因此：僅
橘色 120x60 → **已裁切**（正確）；藍角仍在 → 被**縮小**而非裁切；仍為 200x100 → 什麼都沒發生。
**另有 log**：`P44Diagnostics.write`（第 122 行）每次按壓都會追加一行，但**僅在 `--debug` 之下**
（第 46 行）；依 `actions/win/README.md`，該檔落在啟動者的**當前目錄**。兩次按壓必須留下 `true`、
`false` 兩行——那是結果中不需要任何人判讀影像的部分。

### 5. Caveats / 注意事項

- **Pass `--debug`** or there is no log and the run degrades to a picture.
- **The mac file records a trap worth knowing before reading the Windows
  result.** On the first macOS recording all three cells already measured
  120x60 *before* the press, which the app could report and not explain. The
  cause was `NSView.clipsToBounds` defaulting to `true` on a modern SDK — every
  container was a clipped container, and 199 of 199 were clipping without being
  asked. **The Windows analogue to check for: if cell 1 does not spill, the
  backend is clipping something it was never asked to clip**, which is a
  different defect from `clipped()` not working, and it makes the button's
  effect invisible. Read cell 1 first, before judging cell 3.
- Three clicks is the natural upper bound here; there is nothing else to press.

- **必須傳入 `--debug`**，否則沒有 log，該次執行會退化成一張圖。
- **mac 檔記錄了一個值得在判讀 Windows 結果前知道的陷阱**：首次於 macOS 錄製時，三格在按壓**之前**
  就都量得 120x60。成因是新版 SDK 上 `NSView.clipsToBounds` 預設為 `true`。**在 Windows 上要對應
  檢查的是：若第 1 格沒有溢出，代表該 backend 裁切了它從未被要求裁切的東西**——那與「`clipped()`
  無效」是不同的缺陷，且會使按鈕的效果變得不可見。請先讀第 1 格，再判斷第 3 格。

---

# P11 — sliders, scrollbars and pickers / 滑桿、捲軸與選取器

**Do this one second.** It is the richest app of the ten — five clickable
targets, a genuine drag, a scrollable region — and it is the only one of the ten
that has never been run on this machine at all.

**這一支請排第二。** 它是十支中內容最豐富的——五個可點擊目標、一次真正的拖曳、一個可捲動區域——
而且是十支中唯一一支在本機上從未執行過的。

### 1. What it is for / 它的用途

`testapp/P11.swift`. Three AppKitBackend issues, per `UI-test-plan overall-en.md`
lines 546-552 and `issues.csv`:

- **#82** (`repro-p11`, AppKitBackend) — sliders jitter when two of them
  constrain each other. The minimum is clamped below the maximum and vice versa.
- **#485** (`repro-p11`, AppKitBackend) — the scrollbar renders pointing the
  wrong way.
- **#473** (`repro-p11`, AppKitBackend) — compact `DatePicker` sizing is off with
  Liquid Glass.
- #404 and #425 are noted-only and out of reach from a view tree.

**All three are AppKit's issues, so on Windows/GtkBackend this app is not a
repro — it is a portability check**, and it should be reported as one. The
value here is that P11 has *never been driven anywhere on the Windows track*,
and the three mechanisms it exercises (a clamped binding under a drag, a
scrollbar, a date picker) are unusual enough that "does GtkBackend do these at
all" is worth its own answer. `#82`'s write counters make that answer numeric
rather than visual.

**三個 issue 全屬 AppKit，因此在 Windows/GtkBackend 上這支 app 不是重現，而是可攜性檢查**，回報時
也應如此陳述。其價值在於 P11 *在 Windows 這條線上從未被驅動過*，而它所操作的三種機制（拖曳下的
互相箝制綁定、捲軸、日期選取器）足夠特殊，使「GtkBackend 究竟做不做得到」值得一個獨立的答案。

### 2. Interactive controls, in layout order / 可互動控制項（依版面順序）

| Line | Control | Live? |
|---|---|---|
| 151/154/156 | Title, `backend ->`, `status` | Inert readouts. 156 is written by four of the controls below |
| 163 | `Text` showing `minimum` / `maximum` and both write counters | **The instrument.** Inert itself, but it is where #82 is read |
| 168 | `Slider($minimum, in: 0...100)`, `.frame(width: 700)` | **Yes — needs a drag**, `mousedown` → `move` → `mouseup`. Clamps itself to `maximum` |
| 180 | `Slider($maximum, in: 0...100)`, `.frame(width: 700)` | **Yes — needs a drag.** Clamps itself to `minimum` |
| 192 | `Button("Reset counters")` | **Yes.** Zeroes both write counters and rewrites `status` |
| 198 | `Button("Separate them")` | **Yes.** Sets 20 / 80 — neither clamp active |
| 204 | `Button("Collide them")` | **Yes.** Sets 50 / 50 — any further drag hits the clamp |
| 218 | `ScrollView` of 40 rows, `.frame(340x130)` | **Yes — needs `scroll`**, which is proven on Windows by `P41-wheel-scroll.csv` |
| 276-281 | `DatePicker`, `.compact` if the backend offers it | **Yes**, but see the caveat below — the style branch is not what the source comment says |
| 286 | `Button("Reference")` | **Yes.** Rewrites `status`; exists as a height reference for #473 |

Five buttons-and-equivalents, two drags, one scroll. Window `defaultSize`
760x620 (line 111), and the sliders are 700 wide, so a drag has a long usable
travel.

五個按鈕類目標、兩次拖曳、一次捲動。視窗 `defaultSize` 為 760x620（第 111 行），滑桿寬 700，因此
拖曳有很長的可用行程。

### 3. The sequence worth replaying / 值得重放的序列

The order is chosen so each step starts from a state a previous step
established. `mac/P11-sliders-scrollbar-and-picker.csv` uses this same shape and
is worth reading first — for the shape, not the coordinates.

1. **Click `Reset counters`.** *Puts both write counters at 0 so step 3's numbers
   mean something.* Line 163 must read `writes: min 0, max 0`.
2. **Click `Separate them`.** *Sets 20 / 80, so neither clamp is active and the
   drag in step 3 starts from a defined, uncontested position.*
3. **Drag the minimum slider's knob from its left end rightwards past where the
   maximum sits** — `mousedown` on the knob, three or four `move` rows with a
   short `sleep` between each, then `mouseup`. **This is #82.** Intermediate
   `move` rows are not padding: a single jump from start to end may be delivered
   as one motion event and never exercise the clamp at all, which is the whole
   mechanism under test.
4. **Click `Collide them`.** *Sets both to 50, the state in which every further
   drag immediately hits the clamp* — the worst case for a feedback loop.
5. **Drag the maximum slider a short distance downwards.** *The other side of the
   clamp, from the collided state.* If #82's shape exists here, this is where
   both counters climb together while the values barely move.
6. **Move the pointer inside the 40-row `ScrollView`, then `scroll` down several
   notches, then back up.** *#485 — which way does the thumb go, and does it
   return.* The rows are numbered `Row 1 of 40` … `Row 40 of 40`, so the capture
   says exactly how far it travelled.
7. **Click `Reference`.** *A last known-good click that also rewrites `status`* —
   if `status` moved, the app was still taking input at the end of the run,
   which separates "the later steps did nothing" from "the app stopped
   responding". This matters because `P0-P26-windows-findings.md` records
   exactly that failure on P20 and P24: clicks stop arriving after a subtree is
   replaced.

**Do not click the `DatePicker`.** #473 is a *sizing* question — is the picker
visibly taller or shorter than the `Reference` button beside it, and does it clip
its own text — and that is answered by the capture, not by opening it. Opening a
picker popover risks the P20 failure shape, where a second popover page appears
and nothing on it responds.

**請勿點擊 `DatePicker`。** #473 是一個**尺寸**問題——該選取器是否明顯高於或低於旁邊的 `Reference`
按鈕、是否裁掉自己的文字——那由擷圖回答，而非由「打開它」回答。打開 popover 有觸及 P20 失敗形狀的
風險：第二層頁面出現，而其上一切都不回應。

### 4. What a reader should see afterwards / 事後應看到什麼

- **#82 is a number, not a picture.** Line 163 after step 5 carries `minimum`,
  `maximum`, and both write counts. A clean drag moves one value monotonically
  and increments *one* counter roughly in step with the motion events. **The
  #82 shape is both counters climbing together while the two values barely
  change** — that is a feedback loop, and it is visible in the counters and in
  nothing else. Record the counter values; they are the finding.
- **#485 is the scrollbar's thumb.** After step 6 the visible rows must have
  moved down by the number of notches and come back. A thumb that sits near the
  bottom while the first rows are showing, or that moves opposite to the
  content, is #485.
- **#473 is a height comparison**, read off the capture: the `DatePicker` against
  the `Reference` button on the same `HStack` row (lines 233-289). Clipped text
  inside the picker counts too.
- **`status` (line 156)** must read `Reference button height is the comparison
  baseline.` at the end, from step 7.

### 5. Caveats / 注意事項

- **P11 has a Windows crash history and it is the one app of the ten whose
  launch should be confirmed before any coordinate is measured.** Its own header
  (lines 53-57) records that it *"dies with `Illegal instruction` on
  Windows/GtkBackend"*, leaving no stdout, no event-log entry and exit code 0
  either way. The cause was found and fixed — `.compact` was requested,
  `datePickerStyle` called `assertionFailure` before falling back, and an
  assertion traps in a debug build, which is what Windows builds. It now asks
  `supportedDatePickerStyles` first. **The `-gtk4.exe` exists, so it compiles;
  that is not the same as running.** `p11-startup.log` is the instrument — it is
  written unconditionally, not gated on `--debug` (lines 64-80), so the stages it
  records say how far the process got.
- **The source comment explaining that fix is now stale, and it inverts which
  branch runs.** `P11.swift:250-253` says *"GtkBackend supports
  `[.automatic, .graphical]`"*. `Sources/GtkBackend/GtkBackend.swift:193-196`
  now declares, for every non-macOS platform, `[.automatic, .graphical, .compact,
  .wheel]`. So on Windows/GtkBackend `supportedDatePickerStyles.contains(.compact)`
  is **true**, the `if` branch at line 277 is taken, and a genuinely `.compact`
  picker is on screen. That is good news for #473 — the style the issue names is
  actually being exercised — but anyone reading the comment would expect the
  fallback. Corroborated by `P41-wheel-scroll.csv`, which drives a `.wheel` cell
  on Windows and could not exist if that list were the two-element one.
- **Two drags in one file is the most input-heavy design of the ten.** If the
  run has to be cut short, steps 1-3 alone answer #82 and are worth more than
  steps 6-7.

- **P11 有 Windows 崩潰前科，是十支中唯一一支「量測任何座標之前應先確認其能啟動」的 app。** 其
  標頭（53-57 行）記載它在 Windows/GtkBackend 上以 `Illegal instruction` 結束。成因已找到並修正。
  **`-gtk4.exe` 存在代表它能編譯；那與「能執行」不是同一件事。** `p11-startup.log` 是量測儀器——它
  無條件寫出，不受 `--debug` 限制（64-80 行）。
- **解釋該修正的原始碼註解現已過期，且把「走哪個分支」講反了。** `P11.swift:250-253` 寫著 GtkBackend
  支援 `[.automatic, .graphical]`；而 `GtkBackend.swift:193-196` 現在對所有非 macOS 平台宣告
  `[.automatic, .graphical, .compact, .wheel]`。因此在 Windows/GtkBackend 上第 277 行的 `if` 分支
  會被採用，畫面上是一個真正 `.compact` 的選取器。對 #473 而言這是好消息，但照著註解讀的人會預期
  回退分支。`P41-wheel-scroll.csv` 在 Windows 上驅動 `.wheel` 格，可作佐證。

---

# P27 — backend feature coverage / backend 功能覆蓋

**Partly drivable.** No buttons anywhere, but one region that a `scroll` can
genuinely move.

### 1. What it is for / 它的用途

`testapp/P27.swift`. A falsifiable version of the claim that a missing backend
conformance is *not* a degradation: `@CastBackend` expands to
`fatalError("'GtkBackend' does not implement ...")`, so an app containing a
`WebView` aborted the moment that view was laid out, and `AngularGradient` did
the same. This app shows both. **If the window appears at all, neither
aborted.** No issue number; `UI-test-plan overall-en.md` lines 1332-1355 is the
plan section.

Since then it also grew a second row of three gradient cases (lines 130-155)
that the first row cannot see: two rings and a reversed sweep. Their header
(lines 113-129) is explicit that each *"was drawn wrongly with no diagnostic"*
and *"looks perfectly reasonable on its own"* — they are only wrong next to the
row above. That is a comparison, not a driven test.

### 2. Interactive controls, in layout order / 可互動控制項（依版面順序）

| Line | Control | Live? |
|---|---|---|
| 89-110 | Three `gradientSample` cells — Linear, Radial, Angular | Inert. `Color`/gradient views |
| 131-154 | Three more — Ring (start 30), Ring reversed, Sweep reversed | Inert |
| 180 | `WebView($url)`, `.frame(width: 700, height: 160)`, bound to `https://example.com` | **The only live region.** Scrollable, and clickable in principle |

**Zero `Button`, `Toggle`, `TextField`, `Slider` or `Picker`.** The
`WebView` is live because **GtkBackend conforms to `BackendFeatures.WebViews`**
— `Sources/GtkBackend/GtkBackend.swift:46` — so this is a real web view on this
backend and not the labelled placeholder the source comment (lines 157-176)
describes for backends without one.

**零個 `Button`、`Toggle`、`TextField`、`Slider` 或 `Picker`。** `WebView` 之所以是活的，是因為
**GtkBackend 符合 `BackendFeatures.WebViews`**（`GtkBackend.swift:46`），因此在此 backend 上它是
一個真正的 web view，而非原始碼註解（157-176 行）所描述的、給沒有 web view 之 backend 用的佔位。

### 3. The sequence worth replaying / 值得重放的序列

Exactly what `mac/P27-scroll-the-webview.csv` does, and for the same reason:

1. **`move` the pointer into the `WebView`'s frame**, then settle.
2. **`scroll` down a few notches.** *Proves the page moves **inside** the view
   and does not scroll the window instead.* Both failures are real and they look
   different: a window that scrolls means the wheel event went to the wrong
   widget; nothing moving at all means the web view is a hosted control that
   never received it.
3. **`scroll` further**, then **`scroll` back up by the total.** *Proves it
   returns to the top rather than latching* — and returns the app to a state a
   later capture can compare against the baseline.

**Do not click a link.** `example.com` has exactly one, and following it needs
the network, changes `$url`, and makes the run depend on something outside the
repository. The scroll question is answerable offline against whatever the view
rendered.

### 4. What a reader should see afterwards / 事後應看到什麼

- **The six gradient cells are unchanged**, and the window is not scrolled.
  A capture in which the *gradients* moved means the wheel reached the window
  and not the web view — that is the finding, and it is more interesting than
  the scroll working.
- **The web view's content has moved and come back.** Whether `example.com`
  rendered at all is the separate question, and it belongs to P38 — the P27
  header (lines 162-167) records that on WinUIBackend four `msedgewebview2.exe`
  processes ran while the frame stayed empty, so the control initialises and
  nothing is painted. **If the GTK web view is blank, P27 still passes its own
  test** (the app did not abort) and the blankness is a P38 result.
- The `Angular`, `Ring reversed` and `Sweep reversed` cells against their
  neighbours — a cell filling its whole 160x120 box edge to edge, or showing one
  flat colour, is the defect the second row exists to catch.

### 5. Caveats / 注意事項

- **A scroll-only file is thin, and `actions/win/README.md` names P27 as one of
  the eight that should never get a file** on the grounds that it *"has no
  control at all"*. That is true of buttons and false of the web view; the mac
  and ios folders both drive it by scrolling. This is the clearest case where
  the `win/` README and the other platforms disagree, and it is a judgement
  call, not a fact.
- **The gradient half cannot be driven at all** and should be recorded as
  measured claims (the mac form) or left to the baseline capture.
- The window is `defaultSize` 760x520 (line 52) with a 700x160 web view near the
  bottom — check the web view is fully on screen before measuring, since the
  content above it is tall.

- **只含 scroll 的檔案內容單薄，且 `actions/win/README.md` 把 P27 列為「八支不該有檔案」之一**，
  理由是它*「完全沒有任何控制項」*。這句話對按鈕為真、對 web view 為假；mac 與 ios 兩邊都以捲動
  驅動它。這是 `win/` 的 README 與其他平台分歧最明顯的一例，屬判斷而非事實。
- **漸層那一半完全無法驅動**，應記為已量測的主張（mac 形式），或交給基準擷圖。

---

# P15-DARK — `preferredColorScheme(.dark)` / 深色配色覆寫

**Partly, and the interesting half needs no input at all.** Its one button is
inert by construction. Read this section before deciding — the evidence value is
high and the *drivability* is near zero, and those two are easy to confuse.

**部分可驅動，而有意思的那一半根本不需要輸入。** 它唯一的按鈕在設計上就是惰性的。證據價值高、
可驅動性近乎零——這兩者很容易混淆。

### 1. What it is for / 它的用途

`testapp/P15-DARK.swift`, 51 lines. **#386** — GTK dark mode. It is P15 with the
input step deliberately removed: rather than P15's three scheme buttons, it asks
for `.dark` unconditionally at line 49. Its header says why in as many words —
clicking a small button through synthesised input is unreliable under
client-side decorations, *"so asking for dark unconditionally removes the input
step from the measurement: launch it under a light theme, and if the override
works the window comes up dark."*

**The app was designed not to need an action file.** That is not a gap; it is
the design.

**這支 app 的設計就是不需要動作檔。** 那不是缺口，那是設計本身。

### 2. Interactive controls, in layout order / 可互動控制項（依版面順序）

| Line | Control | Live? |
|---|---|---|
| 39 | Title `Text` | Inert |
| 42 | `Text("Requested: dark   Resolved: \(resolved == .dark ? ...)")` | **The instrument.** Inert, reads `@Environment(\.colorScheme)` |
| 44 | `Text("Plain text on the default background")` | Inert — and it is the subject of #386 |
| 45 | `Button("A button") {}` | **Live target, empty action.** A click changes no state |
| 46 | Expectation `Text` | Inert |

**One clickable control, whose closure is `{}`.** Clicking it can only produce a
transient pressed/prelight appearance. Nothing in the app records that a click
arrived — no counter, no status line, no log; P15-DARK has no `Diagnostics` enum
at all.

**唯一可點擊的控制項，其 closure 是 `{}`。** 點它只能產生短暫的按下／高亮外觀。app 中沒有任何東西
記錄「點擊有抵達」——沒有計數器、沒有狀態列、沒有 log；P15-DARK 完全沒有 `Diagnostics` enum。

### 3. The sequence worth replaying / 值得重放的序列

**Honest answer: there is no sequence worth replaying, and the run worth doing
is a launch under a light theme.** The observation is the window's colour and
the text at line 42, both present from launch.

If a file is written anyway, the only defensible content is the mac form — one
`sleep` row per measured claim:

1. *`Requested: dark   Resolved: dark`* — the app's own readout agrees with what
   it asked for.
2. *The window background is dark*, sampled at a point clear of every label.
3. *The title bar is dark too.* This one is separate on purpose — see below.
4. *`Plain text on the default background` is legible against that background*,
   as a foreground/background contrast pair rather than as an impression.

`mac/P15-DARK-button-under-an-overridden-scheme.csv` does click the button, with
the note *"it must respond inside an overridden window"* — that is a real
question on AppKit, where an appearance override is per-window and could plausibly
break hit-testing. **On GtkBackend the override is per-display** (see below), so
there is no per-window mechanism to break and the click proves correspondingly
less. It is one cheap row; it is not the point.

### 4. What a reader should see afterwards / 事後應看到什麼

**Under a light system theme, the window must come up dark and readable.** The
three readings that matter are `Requested`, `Resolved`, and what is actually on
screen — and the reason to take all three is that
`P0-P26-windows-findings.md` lines 712-716 records them **disagreeing** on P15:

> After `Light` then `Dark` the app reads `Requested: dark`, `Resolved: dark`,
> and the window — title bar included — is drawn light with the text still in
> its dark-mode colours, so almost nothing is legible.

**That is the defect P15-DARK isolates**, and it is why this app is worth a run
even though it is barely drivable: P15 reached that state through two clicks and
the finding explicitly leaves open *"which click produced it, and whether the
override is honoured in one direction only"*. P15-DARK reaches the same request
with **zero** clicks. If P15-DARK comes up correctly dark, the defect is in the
transition rather than the override, and the open question closes.

**這正是 P15-DARK 所隔離出來的缺陷**，也是為什麼這支 app 儘管幾乎無法驅動卻值得跑一次：P15 是經由
兩次點擊才到達該狀態，而該筆記錄明確地把「是哪一次點擊造成的、override 是否只在單一方向被遵從」
留為未決。P15-DARK 以**零**次點擊到達相同的請求。若 P15-DARK 正確地以深色呈現，缺陷就在轉換過程
而非 override 本身，那個未決問題也就解決了。

### 5. Caveats / 注意事項

- **The system theme is a precondition, not a detail.** The test only means
  anything under a *light* theme — under a dark one, a window that comes up dark
  proves nothing. The plan's P15 run line is `GTK_THEME=Adwaita:dark ./P15` for
  the opposite reason; for P15-DARK the launch must be under light.
- **`UI-test-plan overall-en.md` lines 670-676 will mislead whoever reads it
  next.** It states, as something *"checked in the source before writing these
  steps"*, that `GtkBackend.swift` declares
  `canOverrideWindowColorScheme = false` with a
  `TODO(stackotter): Support preferredColorScheme`, and concludes the scheme
  buttons *"are therefore expected to do nothing on GtkBackend"*. **The source
  now says the opposite**: `GtkBackend.swift:207` is
  `public let canOverrideWindowColorScheme = true`, its comment at 202 reads
  *"#386: preferredColorScheme is honoured (see updateWindow)"*, and
  `updateWindow` at 1560-1584 implements it by asking GTK for the matching theme
  variant. `issues.csv` agrees — #386's status is **`fixed-gtk-p15`**. Anyone
  following the plan would record a correct dark window as unexpected.
- **The override is per-display, not per-window** (`GtkBackend.swift:202-206`),
  because GTK has no per-window theme variant. Two windows asking for opposite
  schemes cannot both win. P15-DARK has one window, so the common case holds —
  but it bounds what a pass here proves.
- **There is no log to fall back on.** Unlike P11, P25, P37, P43 and P44, this
  app writes nothing, so the capture is the entire result and `--debug` buys
  nothing.

- **系統主題是前提，不是細節。** 此測試僅在**淺色**主題下具有意義。
- **`UI-test-plan overall-en.md` 670-676 行會誤導下一位讀者。** 它以「撰寫這些步驟前已查核原始碼」
  的口吻聲稱 `canOverrideWindowColorScheme = false`，並據此斷定配色按鈕在 GtkBackend 上「預期不會
  有任何作用」。**原始碼現在說的正好相反**：`GtkBackend.swift:207` 為 `true`，且 `updateWindow`
  已實作之；`issues.csv` 中 #386 的狀態為 **`fixed-gtk-p15`**。照計畫執行的人，會把一個正確的深色
  視窗記成非預期結果。
- **該 override 是 per-display 而非 per-window**（`GtkBackend.swift:202-206`）。
- **沒有 log 可作後備。** 此 app 什麼都不寫，擷圖即是全部結果，`--debug` 買不到任何東西。

---

# The six that cannot be driven / 六支無法驅動者

Each gets the same treatment: what it is for, the control inventory (all empty
but one), and **the specific reason input cannot reach it**. A truthful "this one
cannot be driven from an action file, and here is why" is the deliverable for
these six — not a sequence invented to fill a row.

每一支都以相同方式處理：用途、控制項清單（除一支外全為空），以及**輸入為何構不到它的具體理由**。
對這六支而言，如實寫下「它無法用動作檔驅動，理由如下」就是交付成果——而不是為了填滿一列而編造的序列。

---

## P37 — window level / 視窗層級

### Not drivable, and this is the strongest "no" of the six.

**The reason is not that P37 has no buttons — it is that the replay harness
supplies the property under test.** `Win32Synthesiser.prepareForReplay`
(`Sources/InputEvent/Win32Synthesiser.swift:163-180`) calls
`SetWindowPos(window, HWND_TOPMOST, ...)` **unconditionally**, before any action
runs, on every file. P37's entire question is whether `.topmost()` keeps its
window in front. **Under a replay the window is topmost either way**, so the
observation is guaranteed to pass and guarantees nothing. That is circular, and
a circular test that reports success is worse than no test.

**理由不是 P37 沒有按鈕，而是重放框架親手提供了受測的那項性質。**
`Win32Synthesiser.prepareForReplay`（`Win32Synthesiser.swift:163-180`）在任何動作執行之前、對每個
檔案都**無條件**呼叫 `SetWindowPos(window, HWND_TOPMOST, ...)`。而 P37 的全部問題就是 `.topmost()`
能否讓視窗保持在前。**在重放之下視窗無論如何都是置頂的**，因此該觀察必然通過，也因此什麼都保證
不了。那是循環論證，而一個回報成功的循環測試比沒有測試更糟。

This reason is **stronger and different from the one recorded elsewhere**.
`mac/P37-floating-level-and-what-a-replay-cannot-do.csv` gives the reason as
*"there is no button here, which is why this file drives nothing"*, and
`actions/win/README.md` groups P37 under "zero interactive controls". Both are
true and neither is the binding constraint on Windows. **Contamination is.**

### 1-2. What it is for, and its controls

`testapp/P37.swift`. Does `.topmost()` (line 84, equivalently
`.windowLevel(.floating)`) keep the window in front? Plan section
`UI-test-plan overall-en.md` 1835-1892. **Zero interactive controls**, and line
117-119 says the omission is deliberate: *"Deliberately an instruction rather
than a button. Raising another window is the test, and no button inside this
window can do that to itself."* Lines 93-131 are all `Text`, including a
four-line instruction block.

### 3-4. What a run can and cannot establish

**Can, without any input:** the readout at line 103,
`supported levels -> ...`. On Windows it must list `automatic, normal,
floating`; in WSL only the first two. `UI-test-results_overall_en.md:149`
already records exactly that split, measured. Line 105-109's conditional
sentence must read *"floating is supported: this window should stay in front"*.
Neither is contaminated by the pin — they are readouts of
`@Environment(\.supportedWindowLevels)`, not of window position.

**Cannot, under any file:** whether the window actually stays in front. That
needs a second application raised over it and a **desktop** capture, not a window
capture — plan step 2 says so — and it must be done with no replay running.

### 5. What to do instead

A human step, or a two-process harness outside the action-file format. If a file
is written at all it must assert **only the two readout lines** and must say in
its header that the topmost behaviour is unmeasurable under replay, or the next
reader will take a topmost window in the capture as a pass.

若真要寫檔案，它只能主張**那兩行讀數**，並且必須在標頭中寫明「置頂行為在重放之下無法量測」，
否則下一位讀者會把擷圖中一個置頂的視窗當成通過。

---

## P25 — drag and drop / 拖放

### Not drivable. Three independent sources already say so, and they are right.

- `UI-test-plan overall-en.md:1303-1305`: *"this cannot be driven by an action
  file. Drag and drop is an OS-level negotiation, not a sequence of mouse
  events, so `InputEvent` cannot synthesise it."*
- `P0-P26-windows-findings.md:125,141-145`: *"drag and drop is an OLE
  negotiation, not a held button"*, and `Sources/InputEvent/README.md` states
  the format does not promise it.
- `actions/win/README.md`: *"`SendInput` cannot originate an OLE drag."*

### 1-2. What it is for, and its controls

`testapp/P25.swift`. The first app above the backends to exercise
`onDrop(of:isTargeted:perform:)` / `BackendFeatures.DragAndDrop`. Two
`P25DropArea`s (lines 100-118): one accepting `.fileURL`, one offering
`application/x-p25-nothing` so it refuses everything. **Zero `Button`, `Toggle`,
`TextField`, `Slider` or `Picker`.** The only live things are the `onDrop`
handler at line 165 and the `onChange(of: hovering)` at line 181.

### 3. Why even the hover half is out of reach

This is the part worth stating precisely, because it looks like an opening.
The app's header presents hover feedback as *separately observable* from the
drop — *"the area changes colour on hover, before the button is released, so the
feedback stage is observable separately from the drop stage"* — which invites
the idea that a plain `move` row could at least drive `hovering`.

**It cannot.** `hovering` is bound through `onDrop(of:isTargeted:)`, so it is a
drop-target enter/leave signal, not a pointer-motion signal. It fires only while
a drag with a matching offered type is in flight. **A `move` with no button held
and no OLE data object produces no enter event**, so `state` stays `idle`,
`P25Diagnostics` logs no `hover enter`, and the colour at lines 147-151 stays at
its resting value. A file of `move` rows over both zones would replay cleanly,
change nothing, and report success — the exact failure this whole document is
written against.

**它做不到。** `hovering` 是透過 `onDrop(of:isTargeted:)` 綁定的，因此它是「放置目標的進入／離開」
訊號，而非指標移動訊號。**未按住按鍵、也沒有 OLE 資料物件的 `move` 不會產生 enter 事件**。一個對
兩個區域發出 `move` 列的檔案會乾淨地重放、什麼都不改變、並回報成功。

### 4-5. What a run can establish, and the honest form

Only the resting state, and only as measured claims — which is precisely what
`mac/P25-drop-zones-at-rest.csv` does, and its filename says so. Its five rows
assert the backend line, both zones' titles and geometry, that both read
`state idle / received (nothing yet) / type - / count 0`, and that both are the
resting half of the app's own hover colour with blue below green. **That last
one is the clever row**: it pins down the resting colour numerically, so a later
capture can tell "not hovering" from "hover is broken". On Windows the
`received` value is the cross-platform question (`CF_HDROP` path vs
`text/uri-list`), and it can only be answered by a real drag performed by a
person, with `--debug` on so `p25-debug-events.log` catches the verbatim payload.

僅能確立靜止狀態，且只能以「已量測的主張」形式呈現——`mac/P25-drop-zones-at-rest.csv` 正是如此，
其檔名亦已言明。Windows 上 `received` 的值是跨平台的關鍵問題（`CF_HDROP` 路徑 vs `text/uri-list`），
而它只能由真人執行一次真正的拖曳來回答，並開啟 `--debug` 以便 `p25-debug-events.log` 捕捉原樣酬載。

---

## P17-DOE, P39, P40, P43 — four static comparisons / 四支靜態比較

**These four share one shape and one verdict.** Each renders a fixed grid at
launch, each is judged by comparing cells against a control cell in the same
window, and **none has a single `Button`, `Toggle`, `TextField`, `Slider`,
`Picker` or `ScrollView`.** There is nothing for a click to reach and nothing for
a `scroll` to move — verified by reading all four view bodies, not by counting
matches.

**這四支共有同一種形狀與同一個判定。** 每一支在啟動時繪出固定的格線，各以「同一視窗內的格子與對照
格相比」判定，且**沒有任何一個 `Button`、`Toggle`、`TextField`、`Slider`、`Picker` 或 `ScrollView`**。
沒有東西可供點擊抵達，也沒有東西可供 `scroll` 移動。

### The control inventory, for the record / 控制項清單（存證用）

| App | Window | Content | Interactive |
|---|---|---|---|
| P17-DOE | 760x480 (`:65`) | Three columns: Control, `cornerRadius(0)`, `clipped()` (`:89-91`) | **none** |
| P39 | 860x780 (`:72`) | Ten `P39Cell`s in rows of three (`:77-100`, `:140-142`) | **none** |
| P40 | 900x640 (`:60`) | Seven `P40Cell` tiles (`:65-89`, `:101-103`) plus two bare-text rows (`:115-133`) | **none** |
| P43 | 720x420 (`:76`) | Four shapes: circle+gradient, circle+flat, rectangle+gradient, circle+gradient stroke (`:110-167`) | **none** |

### What each is for / 各自的用途

**P17-DOE** — a design-of-experiments app for the **#389** image-clipping fix,
putting two candidate fixes side by side so the better could be chosen *"by
looking rather than by argument"*. **Its question is already settled**:
`issues.csv` records #389 as `fixed-winui-p3;fixed-gtk-p3` — fixed via P3, in
both directions, not via this DOE. `P0-P26-windows-findings.md:594-596` already
records the Windows reading: *"P17-DOE's control column overflows while both fix
directions confine it"*, which is the expected outcome and the DOE's whole
result. **A file here would re-take a decided experiment.**

**P39** — visual effects: opacity, blur, saturation ×3, brightness, contrast,
grayscale, hueRotation, against an `.identity` control. The defect class it
exists to catch is *"the effect silently doing nothing"*, so every cell is read
against cell 1 and never against expectation.

**P40** — geometric effects: offset, scale ×2, rotation ×2, an arbitrary shear
matrix, plus two bare-text rows. Shaped to catch a **transposed matrix** (scaling
matrices are symmetric, so a wrong 2x2 order scales perfectly and rotates
wrongly) and a **double-applied anchor** (`rotate 30 topLeading` stays centred
instead of swinging down-right). Overlap between tiles is correct here; a cell
that pushes its neighbours aside is the defect.

**P43** — is a gradient clipped to the shape, or does it fill a rectangle?
Four cells, and the ring is the one a backend is *"most likely to get wrong in a
way that looks right"*: the middle must stay empty, or the gradient went to the
fill region instead of the stroke.

### Why no sequence is proposed / 為何未提出任何序列

For all four, an action file could contain nothing but `sleep` rows. **The
capture is the entire experiment**, and `screenshot.zsh` produces it without a
replay. If the parent session adopts the mac form, the claim shapes to measure
are below — the *shapes*, not the numbers, which must come off the Windows
captures. Each is chosen because it is falsifiable and has a built-in control:

- **P17-DOE** — the control column's orange must **spill** past its grey
  viewport vertically while both fix columns confine it to the viewport's
  height. The blocks are 100 wide and 280 tall in a 180x120 viewport (`:76-79`),
  so overflow is vertical only and the columns cannot bleed into each other.
  **The control spilling is the load-bearing half**: if all three confine, #389
  does not reproduce and the DOE says nothing — which is exactly what
  `mac/P17-DOE-the-control-clips-too.csv` recorded on AppKit.
- **P39** — one row per cell, each naming the cell's probe colour against cell
  1's. The three saturation cells are the strongest set because they must form a
  **monotonic ladder** (0 < 0.5 < control < 2.5); a single cell "looking
  desaturated" is not a judgement anyone can make from one picture. Note also
  that grayscale 1 and saturation 0 must be **different greys** — mac measured
  94 and 144 — or one is being routed to the other.
- **P40** — the pair that matters most is `rotate 30 centre` against
  `rotate 30 topLeading`, which must **differ**. Wrong anchor arithmetic makes
  them identical or throws the tile off screen, and either failure looks like the
  transform working. Then: the shear must lean without rotating the blue block's
  top edge off horizontal, and the two bare-text rows separate "can transform a
  leaf" from "can transform a subtree".
- **P43** — the corner probe on the gradient circle must read window background
  **and** the same relative corner on the rectangle must read a filled colour.
  The second is the control that stops the first from being a miss. Then: the
  ring's middle must read background, the flat green control must show no ramp,
  and the ring itself must carry red at the top and blue at the bottom.

### Caveats / 注意事項

- **P39 and P40 have a Windows history that a fresh capture must be read
  against.** `UI-test-results_overall_en.md:151` records that on Windows/WinUI
  only opacity changed pixels — blur, saturation, brightness, contrast,
  grayscale and hue rotation all returned `mean_diff=0.00` — and that this was
  **superseded 2026-09-02** when Win2D effects landed. **That is the WinUI
  backend, not GtkBackend.** For GtkBackend the recorded result is WSLg's, where
  every non-control sample differs. A Windows `-gtk4` reading has no prior on
  record; do not carry the WinUI numbers across.
- **P39's window height is load-bearing and has bitten before.** Its header
  (`:62-71`) records that the tenth sample started a fourth row that fell outside
  the old 620pt window and *"was never laid out — and a cell that is never laid
  out never applies its effect"*, so `hueRotation 120` vanished from the log
  while the nine visible cells all looked correct, and nothing reported it.
  **Confirm all ten cells are present in the capture before reading any of
  them.** `--debug` prints the sample count (`:148`), which is the check.
- **P17-DOE is settled and is the lowest-value app of the ten.** If effort has
  to be spent somewhere, it should not be here.
- **P43's ring has a known cosmetic artefact that is not a bug**: its four
  corners come out flattened because a 14pt stroke sits half outside the path,
  so 7pt falls beyond the 120x120 frame and is clipped (`:154-162`). The ring
  looks like a rounded square at a glance. Recorded so it does not get filed.

- **P39 與 P40 有一段 Windows 歷史，新的擷圖必須對照它來讀。**
  `UI-test-results_overall_en.md:151` 所記錄「僅 opacity 改變像素」者是 **WinUI backend，不是
  GtkBackend**；GtkBackend 有記錄的結果來自 WSLg。Windows `-gtk4` 尚無任何先前記錄，**請勿把 WinUI
  的數字搬過來**。
- **P39 的視窗高度是關鍵，且曾經出過事**（`:62-71`）：第十個樣本曾落在視窗之外而從未被配置，未被
  配置的格子不會套用其效果，於是它從記錄中消失，而可見的九格看起來全都正確。**判讀任何一格之前，
  請先確認十格都在擷圖中。**
- **P17-DOE 已定案，是十支中價值最低的一支。**
- **P43 的環有一個已知的外觀假象，並非 bug**（`:154-162`）：14pt 描邊有一半落在路徑之外而被裁掉，
  使該環乍看像個圓角方形。記於此處以免日後被當成 bug 回報。

---

# Format notes for whoever writes the files / 撰寫檔案者須知

Learned from `P7-list-selection.csv`, `P10-hit-testing.csv`, `P10-ctrl-q.csv`
and `P21-buttons-and-disabled.csv`. Not a substitute for reading them.

- **Columns**: `action,x,y,origin,button,key,micros,note,platform`. Verbs the
  parser accepts, from `Sources/InputEvent/ActionFile.swift:166-188`: `move`,
  `click`, `doubleclick`, `mousedown`, `mouseup`, `scroll`, `keydown`, `keyup`,
  `key`, `sleep`. **`mousedown`/`move`/`mouseup` is why P11's slider drag is
  expressible** — it is not a `drag` verb, it is three rows.
- **`platform` is `windows`** for every row in `actions/win/`. The `wsl/` files
  use `gtk`; copying a row across without changing it fails at parse.
- **`origin` is `frame`, never `client`**, because `screenshot.zsh -w` captures
  the window including its title bar and every coordinate is measured on that
  image.
- **Record the capture size the coordinates were measured against**, in the
  header, in the form *"Measured on a WxH window capture at 100% display
  scale."* Verify it with `ffprobe` rather than transcribing it — three files
  (P3, P7, P9) carried the same +9 error and P10 carried +31, which is how it is
  known these were transcribed from something other than the capture:

  ```zsh
  ffprobe -v error -select_streams v:0 -show_entries stream=width,height \
          -of csv=p=0 <capture.png>
  ```

- **Bilingual header comment block**, English then Traditional Chinese, saying
  what the file asks and what would count as a failure. Where a measurement
  contradicts the expectation, record both — `P10-hit-testing.csv`'s
  `Expected: ... Hidden clicks: 0 / Measured: ... Hidden clicks: 1` is the model.
- **`# expect: process-exits`** marks a file whose pass condition is the process
  being *gone* afterwards. It is read by `sweep_drive.zsh:477`, and
  `P10-ctrl-q.csv` is currently the only file carrying it. **None of these ten
  needs it** — no app among them quits from its own controls.
- **Kill leftover GTK processes before any launch test.** A leftover makes the
  next Windows launch exit 0 with no window, via GTK's single-instance handoff —
  which looks exactly like a launch failure and has already made one bisection
  wrong.

- **欄位**與**動詞**如上；`mousedown`/`move`/`mouseup` 三列即為 P11 滑桿拖曳可被表達的原因。
- **`platform` 一律為 `windows`**（`wsl/` 用 `gtk`，直接照搬會在剖析時失敗）。
- **`origin` 一律為 `frame`，絕不用 `client`**。
- **在標頭記錄座標所依據的擷圖尺寸**，並以 `ffprobe` 查驗而非抄寫——P3、P7、P9 曾同時帶有 +9 的
  誤差，P10 則為 +31。
- **雙語標頭註解區塊**；當量測與預期相衝突時，兩者都要記下。
- **任何啟動測試之前，先清除殘留的 GTK 行程**，否則下一次 Windows 啟動會以 exit 0 結束且沒有視窗。

---

# Where the source contradicted the docs / 原始碼與文件相衝突之處

Seven, found while deriving the above. Listed because each would mislead the
next reader, and four of them would change how a result is judged.

以下七項，皆為推導上述內容時發現。之所以列出，是因為每一項都會誤導下一位讀者，而其中四項會改變
一項結果如何被判定。

1. **`canOverrideWindowColorScheme` — the plan says `false`, the source says
   `true`.** `UI-test-plan overall-en.md:670-676` presents *"checked in the
   source before writing these steps"* and concludes the scheme buttons *"are
   therefore expected to do nothing on GtkBackend"*.
   `Sources/GtkBackend/GtkBackend.swift:207` is `true`, `updateWindow`
   (`:1560-1584`) implements the override, and `issues.csv` gives #386 the status
   `fixed-gtk-p15`. **Changes the verdict**: a correct dark window would be
   recorded as unexpected. Affects P15-DARK and P15.

2. **`supportedDatePickerStyles` — P11's own comment is stale and inverts the
   branch taken.** `P11.swift:250-253` says *"GtkBackend supports
   `[.automatic, .graphical]`"*. `GtkBackend.swift:193-196` declares, for all
   non-macOS platforms, `[.automatic, .graphical, .compact, .wheel]`. So the
   `if supportedDatePickerStyles.contains(.compact)` at `:276` is **true** on
   Windows and a genuinely `.compact` picker renders. **Changes the verdict** for
   #473: the style the issue names is on screen, not the fallback. Corroborated
   by `P41-wheel-scroll.csv` driving a `.wheel` cell on Windows.

3. **Keyboard rows: three docs, three different claims, none matching the
   code.**
   - `P10-hit-testing.csv` header: *"`prepareForReplay` refuses any file
     containing `key`, `keydown` or `keyup`"*. **False** — there is no such
     refusal anywhere in `Sources/InputEvent/`.
   - `P0-P26-windows-findings.md:178-202`: *"Keyboard files cannot run"*, and
     `:717-719` *"Keyboard checks remain out of reach, unchanged and by
     design"*.
   - `actions/win/README.md` (2026-09-03): *"Keys work: `key tab` moved focus
     out of a `TextField` and `key space` activated the button,
     `p31-debug-events.log` recording `button clicked count=1`."*

   The code is the authority and says something more precise than any of them:
   `Win32Synthesiser.swift:138-142` — *"focus is attempted, and its failure is
   fatal only for a file that presses keys. A mouse-only file is safe on the
   topmost pin alone."* So key files are **attempted, not refused**, and whether
   they work depends on whether the process can take the foreground.
   `P10-ctrl-q.csv` exists in `actions/win/`, whose README says a file appears
   there *only* after being run and seen to work. **Does not affect these ten**
   — none of the designs above needs a key — but it will affect the next person
   who reads the P10 header.

4. **`actions/win/README.md`'s "eight apps that should never get a file" is
   contradicted by three sibling folders.** It names P25, P27, P37, P38, P39,
   P40, P42, P43 and argues even a `sleep`-only file yields no readable
   evidence. `actions/mac/`, `actions/ios/` and `actions/android/` each carry
   files for those same apps, in the assertion-carrying form. Both positions are
   defensible and they are about different file shapes; the disagreement is set
   out in full in the "decision this document cannot make" section above. **Not
   a factual error — an unreconciled policy split**, and it decides six of these
   ten.

5. **P37's stated reason for being undrivable is not the binding one on
   Windows.** `mac/P37-...csv` and `actions/win/README.md` both give "no
   interactive controls". The binding constraint is that
   `prepareForReplay` pins `HWND_TOPMOST` unconditionally
   (`Win32Synthesiser.swift:163-180`), so a replay supplies the property under
   test. **Changes the verdict**: a capture showing a topmost window during a
   replay is not evidence, and under the "no controls" framing it looks like it
   is.

6. **`UI-test-plan overall-en.md` stops at P41 and never covers P42-P46.**
   P43 and P44 — two of these ten, and P44 is the single best candidate — have
   **no plan section, no `issues.csv` row, and no entry in
   `P0-P26-windows-findings.md`**. P44 appears in no `.md` in `testapp/` at all;
   its own source header is the entire specification. `README_zhTW.md:22` does
   count 49 app files including P43 and P44, so the gap is in the plan
   specifically, not in the inventory.

7. **A bilingual pair disagrees in `P0-P26-windows-findings.md`.** The English
   at `:712-716` gives P15's finding in full — *"the app reads `Requested:
   dark`, `Resolved: dark`, and the window — title bar included — is drawn light
   with the text still in its dark-mode colours"*, plus the open question of
   which click produced it. The Traditional Chinese at `:730` compresses this to
   *「只確立了 Requested、Resolved 與螢幕上所見三者互相矛盾」*, dropping both the
   specifics and the open question. A reader of one language gets a materially
   weaker finding than a reader of the other.

Two more that are dated rather than wrong, and are worth re-checking rather than
repeating: `gtk-test-plan-findings.md:1411` says *"P11, P12 and P14 remain out of
scope on this Windows/WSL machine"*, whereas P11 is in scope for this task; and
`P0-P26-windows-findings.md:459` lists P11 among apps *"absent from the table"*
as a macOS app, which is its provenance rather than a statement about whether it
runs on Windows — the app's own line 151 was changed on 2026-09-05 for exactly
this confusion, so that the window names the backend it is *running* on rather
than the one it was written for.

另有兩項屬「過期」而非「錯誤」，值得重新查核而非照抄：`gtk-test-plan-findings.md:1411` 稱 P11 在本機
上仍屬範圍之外，而 P11 正是本任務的範圍之一；`P0-P26-windows-findings.md:459` 把 P11 列為 macOS
app——那是它的出處，而非關於它能否在 Windows 上執行的陳述。

---

# Priority / 建議順序

1. **P44** — one press, three simultaneous observable changes, and a log line
   that does not need a human to read pixels. Smallest window of the ten, one
   click target, lowest risk of a mis-measured coordinate. **Also the only one
   of the ten with no documentation anywhere**, so a driven run is the first
   record it will have.
2. **P11** — the most it is possible to learn from one file: five click targets,
   a real drag with a numeric instrument behind it, and a scroll. Confirm it
   launches and check `p11-startup.log` **before** measuring coordinates; it has
   a crash history on this exact target and a `-gtk4.exe` on disk proves only
   that it compiled.
3. **P15-DARK** — cheapest run of the ten and it closes an open question. Needs
   a light system theme and no clicks at all. Its value is entirely in whether
   #386's fix holds without a transition, which is the half P15 could not
   isolate.
4. **P27** — a scroll inside a real `WebView`. Worth doing, and worth doing
   after the parent has decided the `sleep`-only policy, because the gradient
   half of the app depends on that decision.
5. **P39, P40, P43** — only if the mac form is adopted, and only with the probes
   actually measured. In that order: P39 has the strongest built-in control (the
   saturation ladder), P40 the sharpest single check (`rotate 30 centre` vs
   `topLeading`), P43 the cleanest pair (circle corner vs rectangle corner).
6. **P17-DOE** — last, and arguably never. Its experiment was decided by #389's
   fix landing through P3, and the Windows reading is already recorded.
7. **P37, P25** — no file. Both need something no action file can produce: a
   second window raised over an unpinned P37, and a real OLE drag for P25. For
   P37, a file would be worse than nothing, because the harness guarantees the
   result.

1. **P44**——一次按壓、三項同時可觀察的改變，外加一行不需人工判讀像素的 log。
2. **P11**——單一檔案所能學到最多者。**量測座標之前**先確認它能啟動並檢查 `p11-startup.log`。
3. **P15-DARK**——十支中成本最低的一次執行，且能解決一個未決問題；需要淺色系統主題，且完全不需點擊。
4. **P27**——在真正的 `WebView` 中捲動；宜在上層決定 `sleep` 政策之後再做。
5. **P39、P40、P43**——僅在採用 mac 形式、且取樣點確實經過量測時才做。
6. **P17-DOE**——最後，甚或不做。其實驗已隨 #389 經由 P3 修復而定案。
7. **P37、P25**——不寫檔案。對 P37 而言，寫了比不寫更糟，因為框架本身就保證了那個結果。
