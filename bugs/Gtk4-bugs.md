# GTK 4 bugs and limitations / GTK 4 的缺陷與限制

Defects that live in GTK 4 itself, not in this project. Kept apart from
`testapp/gtk-silent-noops.md`, which catalogues things **GtkBackend** does
wrong and could fix; everything here is upstream, and the only decisions
available to us are how to detect it and how to degrade.

Each entry records the version it was measured on, because a GTK bug is a
moving target and a fixed one should be found by re-running the reproduction
rather than by someone remembering. **Re-check any entry older than a GTK minor
release before relying on it.**

本檔記錄的是存在於 GTK 4 自身、而非本專案的缺陷。與 `testapp/gtk-silent-noops.md` 分開存放——後者
編錄的是 **GtkBackend** 自己做錯、且有能力修正的事；此處的一切都屬於上游，我們能做的決定只有
「如何偵測」與「如何降級」。

每一條都記下實測所在的版本，因為 GTK 的缺陷是會移動的目標；某條已被修好，應該是靠重跑重現步驟被
發現，而不是靠某人記得。**任何超過一個 GTK 次版本的條目，在依賴它之前請重新查證。**

---

## 1. A transformed widget renders as flat hotpink, losing its content

**Measured 2026-08-27 on GTK 4.22.4** (the current stable release at the time).
Windows and the WSL install were both on 4.22.4.

**Symptom.** Apply any non-identity transform to a widget and the entire
transformed subtree is painted as one flat rectangle of hotpink,
`rgb(255, 105, 180)` — sampled from the capture, not judged by eye. The geometry
is applied: tiles measurably move and change size. What is lost is the content.
Text, colours, child widgets: all replaced by the pink block.

Nothing is logged. No CSS parse error, no warning, no `Gtk-CRITICAL`.

**Why pink.** This is not arbitrary. GTK's own documentation states that a node
the renderer cannot handle is drawn pink, so the colour *is* GSK reporting the
failure in the only channel it has. Reading it as a mystery wastes the one clear
signal available.

**What was ruled out**, before concluding it is GTK rather than us:

| ruled out | how |
|---|---|
| the mechanism | CSS `transform: matrix(...)` and `gtk_fixed_set_child_transform` with a `GskTransform` fail identically, and they are unrelated code paths |
| the renderer | `GSK_RENDERER=cairo` and the default GL renderer produce the same hotpink |
| our own code | a no-op control that built the container and skipped **only** the transform call rendered every tile perfectly, so the container, the modifier and the layout are all innocent |
| the content | a bare `Text`, with no nested containers and no `Color` views inside the transformed subtree, goes hotpink too |
| the version | 4.22.4 is current stable; there is no newer release to move to |

**Reproduce.**

    SCUI_DEBUG=1 zsh testapp/compile.zsh -gtk4 P40
    ( cd testapp/output && ./P40.exe & )
    zsh testapp/screenshot.zsh -w P40

Then count hotpink pixels in the capture; zero means the bug is gone.

**How this project degrades.** `GtkBackend.setGeometricEffect` conforms to
`BackendFeatures.GeometricEffects` and deliberately applies nothing, logging
once through `debugLogOnce`. Declining beats applying it: an untransformed view
is still legible and still clickable, whereas a hotpink rectangle has lost
everything. This is the one case so far where "apply what you can and say so"
loses to "apply nothing and say so".

Conforming-but-declining rather than not conforming is also deliberate:
`@CastBackend` turns a *missing* conformance into `fatalError`, so refusing the
protocol would abort every app that calls `.offset(_:_:)` instead of drawing it
in the wrong place.

**Not GTK-wide.** WinUIBackend implements the same protocol and renders
rotation, scale and offset correctly, so the protocol shape is sound and this is
a GTK-side gap.

**Still untested:** whether Linux GTK behaves the same. Same version, so
probably, but nobody has run it — the WSL box has no screenshot tool installed
and the WSLg window was not reachable from the Windows capture path.

---

**1. 被變換過的 widget 會被畫成一整片 hotpink，其內容完全消失**

**2026-08-27 於 GTK 4.22.4 實測**（當時的最新穩定版）。Windows 與 WSL 兩邊安裝的都是 4.22.4。

**症狀。** 對任何 widget 套用非 identity 的變換，整個被變換的子樹就會被畫成一整塊純色的 hotpink，
`rgb(255, 105, 180)`——此數值取樣自截圖，而非目測判斷。幾何變換確實被套用了：方塊有可量測的位移
與尺寸變化。消失的是內容：文字、顏色、子 widget，全部被那塊粉紅色取代。

過程中沒有任何紀錄。沒有 CSS 解析錯誤、沒有警告、沒有 `Gtk-CRITICAL`。

**為何是粉紅色。** 這並非隨意選色。GTK 官方文件載明「繪製器無法處理的節點會被畫成粉紅色」，因此
這個顏色**就是** GSK 以它僅有的管道回報失敗。把它當成謎團看待，等於浪費了現場唯一明確的訊號。

**在判定為 GTK 而非我方問題之前，已排除的項目**（對應上表）：機制（CSS `transform: matrix(...)`
與搭配 `GskTransform` 的 `gtk_fixed_set_child_transform` 失敗方式完全相同，而兩者是互不相干的程式
路徑）、繪製器（`GSK_RENDERER=cairo` 與預設的 GL 繪製器結果同為 hotpink）、我方程式碼（一組「建立
容器但**只**略過變換呼叫」的對照組，每個方塊都正常繪製，故容器、modifier 與版面皆無涉）、內容
（被變換的子樹中僅有一段純 `Text`、無巢狀容器亦無 `Color` view，同樣變成 hotpink）、版本
（4.22.4 已是最新穩定版，無更新版本可換）。

**重現方式**：指令同上；接著計算截圖中 hotpink 像素的數量，為零即代表此缺陷已消失。

**本專案的降級方式。** `GtkBackend.setGeometricEffect` 會宣告 conformance 但刻意不做任何事，並透過
`debugLogOnce` 記錄一次。拒絕執行優於強行套用：未經變換的 view 仍然可讀、仍然可點擊，而一塊
hotpink 矩形已經失去一切。這是目前唯一一個「盡力套用並明白告知」輸給「什麼都不做但明白告知」的
情況。

選擇「宣告 conformance 但拒絕執行」而非「不宣告」，同樣是刻意的：`@CastBackend` 會把**缺少的**
conformance 轉為 `fatalError`，因此若拒絕實作該 protocol，任何呼叫 `.offset(_:_:)` 的 app 都會直接
中止，而不是把它畫在錯誤的位置。

**這並非 GTK 以外皆然。** WinUIBackend 實作了同一個 protocol，且能正確繪製旋轉、縮放與位移，因此
protocol 本身是健全的，這是 GTK 這一側的缺口。

**仍未測試**：Linux 的 GTK 是否有相同行為。版本相同，結果很可能一致，但確實無人實測過——WSL 環境
未安裝任何截圖工具，而 WSLg 的視窗也無法從 Windows 的擷取路徑取得。
