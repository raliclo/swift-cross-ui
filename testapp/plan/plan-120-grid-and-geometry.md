# #120 真正的 Grid 與 `GeometryProxy.frame(in:)`:兩件事、一個共同的牆

**狀態:形狀已定,事實已查證,尚未實作。** 這兩項原本被歸為「純框架、Mac 可獨力完成」,那句話
對 #120 成立、對 `frame(in:)` **不成立**——查證之後才看得出來,而差別在於一個具體的機制。

**Status: shapes settled and facts checked, nothing implemented.** Both were
filed as "pure framework, the Mac side can do them alone". That is true of #120
and NOT true of `frame(in:)`, and the difference only becomes visible once the
mechanism is checked rather than assumed.

---

## 一、先查證的四件事 / What was checked first

以指令查,不憑印象;每一條都改變了原本的計畫:

| 查的東西 | 結果 | 它推翻了什麼 |
| --- | --- | --- |
| `ViewLayoutResult` 是否保有 `childResults` | **否。** 它只在 init 中拿去合併 `preferences`,不儲存 | 「Grid 可以從每一列的結果讀到儲存格寬度」——不行 |
| 有沒有 backend 能回答「這個 widget 在哪」 | **沒有。** `Core` 只有 `setPosition`(setter)與 `naturalSize`;整個 `BackendFeatures/` 沒有位置的 getter | 「`frame(in: .global)` 去問 backend 就好」 |
| `LayoutableChild.commit` 能不能帶東西 | **不能。** 它是 `@MainActor () -> ViewLayoutResult`,兩端都不帶參數 | 「父層可以在 commit 時把座標交給子層」 |
| 環境裡有沒有「請重新版面」 | **沒有通用的。** 只有我為 #117 加的 `onWindowChromeChange`,它是視窗外框專用 | 「先給 0,下一輪再修正」——沒有東西會觸發下一輪 |

`ViewLayoutResult` does not keep `childResults`; no backend can report a
widget's position; `LayoutableChild.commit` carries nothing either way; and
there is no general "lay out again" in the environment.

---

## 二、#120:可以做,而且不需要任何 backend / #120 is doable here

### 為什麼今天的 `Grid` 不是格線

`Grid` 是 `VStack { GridRow… }`,而 `GridRow` 是 `HStack`。一個 `HStack` 只依據自己那一列決定
子項尺寸,因此兩列的第一格若寬度不同,第二格就從不同的 x 開始。`Grid.swift` 自己把這件事寫得很
清楚,並說補救它需要「在 commit 任何一列之前先量測所有列」。

### 那個量測是做得到的,只是不能走 `childResults`

Grid **自己**驅動它那些列的 `computeLayout`,因此它可以在**同一輪**裡呼叫兩次:

1. 第一次不帶計畫。每一格把自己的寬度與跨欄數,經由一個新的 **preference key** 往上報——
   preferences 是這棵樹**唯一**已經在運作的向上通道(`ViewLayoutResult` 會合併它們)。
2. Grid 取各欄最大值,解析成一個 `GridLayoutPlan`(lane = 欄,line 只有一條)。
3. 第二次帶著計畫,放進 `\.layoutGridPlan`。`GridRow` 消費它,把儲存格放進共用的欄。

第 3 步是唯一有結構性代價的一步:**`GridRow` 必須從「一個 body 是 HStack 的組合 view」變成一個
真正的版面容器**,和 `LazyVGrid` 一樣。`ForEach` 已經示範了消費計畫的那一半。

### `gridCellColumns(n)`

它是同一個 preference 的第二個欄位,而不是另一套機制。這也回答了佇列上那句「不得在 grid 裡特判
`ForEach`」:格線讀的是**被回報上來的東西**,誰回報的它不需要知道。

`computeGridLayout` 目前以 `index % laneCount` 決定 lane,那假設了「一格佔一條 lane」。跨欄需要
一份逐子項的 lane 指派表,那是它要新增的參數。

**規模**:一個 preference key、`GridRow` 變成容器、Grid 兩輪、`computeGridLayout` 支援跨欄。
不需要任何 backend,五個平台自動一致。

---

## 三、`frame(in:)`:`.local` 現在就對,`.global` 不是 Mac 一個人的事

### `.local` 是完整且精確的

`frame(in: .local)` 是 `(0, 0, size.width, size.height)`,而 `size` 是 `GeometryProxy` 今天就
有的東西。這一半不需要任何新機制。

### `.global` 與 `.named` 撞上的是「位置只存在於 commit」

位置是由 `commitStackLayout` 這一類函式算出來、當場交給 `backend.setPosition` 的。而:

- 子節點的 `computeLayout` 發生在**位置算出來之前**(要先有尺寸才排得出位置),所以那一輪拿不到。
- `LayoutableChild.commit()` 不帶參數,所以 commit 當下也遞不下去(見上表第三列)。
- 沒有通用的重新版面觸發器,所以「這一輪先給 0、下一輪修正」不會有下一輪(第四列)。

三者中修掉任何一個都能讓 `.global` 成立,而它們的代價差很多:

| 選項 | 動到什麼 | 風險 |
| --- | --- | --- |
| (a) `commit` 改成 `commit(_ context:)` | **46 個呼叫點**,其中數個在 `Views/Modifiers/Layout/`——**Windows 的 #128 區域** | 重疊衝突,而且是核心型別的簽章 |
| (b) 加一個 backend requirement「回報 widget 的位置」 | 五個 backend。AppKit `convert(_:to: nil)`、UIKit `convert(_:to: nil)`、Android `getLocationInWindow`、GTK `gtk_widget_translate_coordinates`、WinUI `TransformToVisual` | 我編得了三個,**GTK 與 WinUI 編不了**——本樹兩週內已被這件事咬過兩次 |
| (c) 通用的「請重新版面」+ 逐輪修正的座標 | 一個環境值加一個觸發器;`onWindowChromeChange` 是同形狀的先例 | 迴圈風險:每次座標變動都要求重新版面 |

**我的建議是 (b),而且不是因為它最便宜。** `.global` 問的是「這個 view 在視窗裡的哪裡」,而
那個問題的權威答案在平台那一側——(a) 與 (c) 都是在框架裡重建一份平台已經知道的資訊,並在每一次
有 modifier 偷偷位移子節點時安靜地出錯。(b) 的代價是誠實的:它需要 Windows 端寫 GTK 與 WinUI
那兩格,與 #122 完全同一個協議。

My recommendation is (b), and not because it is cheapest. `.global` asks where
a view is inside its window, and the platform is the authority on that; (a) and
(c) both rebuild in the framework something the platform already knows, and go
quietly wrong every time a modifier shifts a child. (b)'s cost is honest: two
cells for the Windows side, exactly like #122.

### 要 Windows 回答的兩件事

1. **`frame(in:)` 走 (b) 嗎?** 若是,GTK 的 `gtk_widget_translate_coordinates` 是否已經在產生
   出來的 Swift 裡?(`grabFocus` 就不在——見 `plan-focus-protocol.md`。)
2. **WinUI 的 `TransformToVisual` 是同步的嗎?** 這是 #122 那份草案裡唯一沒能從這台機器查證的
   同一類問題。

### 不在本次範圍內

`GeometryProxy.safeAreaInsets`:全 repo 0 命中,而且它同樣需要五個 backend 回報。它與 `.global`
是同一個決定,一起做或一起等。
