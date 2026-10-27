# Android lines up with iOS

The rule since 2026-10-09 (testapp/mobile_comparison_flow.md): what Android
shows should line up with iOS, alignment above all, iOS as the reference. A
gap that needs a behaviour choice goes to the project owner rather than being settled
in code. Work is one Pn at a time: capture iOS, capture Android, compare, fix,
re-capture both from the same commit.

## Decisions already made (do not reopen)

| Area | Android now | Commit |
|---|---|---|
| A root larger than the screen | starts at its content's top-left below the status bar, as UIKit; the replay adds the displacement so old files still land | 12c8788b, a5ccf75d |
| A root that fits while its layout does not | centred on the screen (9.5 dp a side on the phone for P89) | 2026-10-12, queue.md |
| Content under the debug mode button | starts below it | 2026-10-12 |
| Status and gesture bars | nothing drawn under them; a grown root ScrollView stops above the gesture bar; rows above the content (toolbar, refresh) clear the status bar | 9f733bbc, f08c7a29 |
| Status-bar icons | follow the colour scheme; a navigation title is a bar | 9c13fe23 |
| Default button | borderless text in `colorPrimary`, as iOS's blue | 615a4b67 |
| Text sizes | the core's mobile table (iOS points) in sp, not the theme's | 895d11a2 |
| Text lines | every line one line height, CJK included; no font padding; a wrapped Text as wide as its widest line | 74a73825, e9958ba1, fb50ed7d |
| Toggle | defaults to a switch; switch, checkbox and button-style drawn as UIKit's | 4a4c47d9, 8d8167a0 |
| System symbols | drawn from Material Symbols | a24c6d50 |
| Date and time pickers | compact fields, calendar and wheels drawn as UIDatePicker's; wheels follow the region's order | 22fc3676, f2993400, 9f96e6a0 |
| Unstyled text field | no border, as UIKit | e404e41f |
| Sizes at fractional pixels | rounded up while positions stay truncated, so no 1 px seam between same-colour neighbours (P95, 120 dp = 315 px at 2.625) | a6d20dcc |
| Grayscale | CIColorMonochrome's linear-light grey, as AppKit | 5c5f29b2 |
| Hover on a touch screen | a long press (system timeout, 400 ms by default) starts it; moves are reported until the lift | 2813e023 |
| Overall brightness | kept as it is, see display-brightness.md | 6b9dce45 |

## By design, not defects

- Mid-word wrapping ("Rese/t") in an app wider than the 411 dp phone: the
  app's size, device width, font and button chrome (731f5668).
- Platform conventions (fonts, control chrome, status bar) unless they clip,
  overlap or hide content.

## How to apply

A fix to a shared Kotlin helper or to the core is re-captured on both
platforms. Before/after evidence keeps both captures side by side; label them
with a CJK font (`/System/Library/Fonts/STHeiti Medium.ttc`). Do not use
magenta for gutters in comparison images; many apps draw that colour.

---

# Android 對齊 iOS

自 2026-10-09 起的原則(testapp/mobile_comparison_flow.md):Android 顯示的內容要與 iOS 對齊，對齊優先,iOS 為參考。需要在
行為上做選擇的差距交給專案負責人決定，不在程式碼裡自行定案。一次處理一支 Pn:擷取 iOS、擷取 Android、比較、修正，再以同一個
commit 重新擷取兩邊。

## 已做的決定(不要重開)

| 範圍 | Android 現在 | Commit |
|---|---|---|
| 比螢幕大的根 | 從內容左上角、狀態列下方開始，與 UIKit 相同；重播會加上位移，舊檔案仍點得中 | 12c8788b、a5ccf75d |
| 根塞得下而版面塞不下 | 置中在螢幕上(P89 在手機上每邊 9.5 dp) | 2026-10-12,queue.md |
| 除錯模式按鈕底下的內容 | 從按鈕下方開始 | 2026-10-12 |
| 狀態列與手勢列 | 不在其下繪製；長到螢幕高的根 ScrollView 停在手勢列上方；內容上方的列(工具列、重新整理)讓開狀態列 | 9f733bbc、f08c7a29 |
| 狀態列圖示 | 跟隨色彩配置；導覽標題是一條 bar | 9c13fe23 |
| 預設按鈕 | `colorPrimary` 的無框文字，如同 iOS 的藍色按鈕 | 615a4b67 |
| 文字大小 | 用核心的行動版表格(iOS point)換成 sp,不用主題的 | 895d11a2 |
| 文字行 | 每行一個行高,CJK 也一樣；不加字型 padding;換行的 Text 寬度等於最寬的一行 | 74a73825、e9958ba1、fb50ed7d |
| Toggle | 預設為開關；開關、核取方塊與按鈕樣式都畫成 UIKit 的樣子 | 4a4c47d9、8d8167a0 |
| 系統符號 | 以 Material Symbols 繪製 | a24c6d50 |
| 日期與時間選擇器 | 精簡欄位、月曆與滾輪都畫成 UIDatePicker 的樣子；滾輪依地區的順序 | 22fc3676、f2993400、9f96e6a0 |
| 未套樣式的文字欄位 | 沒有邊框，與 UIKit 相同 | e404e41f |
| 落在小數像素的大小 | 大小無條件進位、位置維持截斷，同色相鄰 view 之間不再有 1 px 的縫(P95,2.625 下 120 dp = 315 px) | a6d20dcc |
| 灰階 | CIColorMonochrome 的線性光灰，與 AppKit 相同 | 5c5f29b2 |
| 觸控螢幕上的 hover | 長按(系統逾時，預設 400 ms)開始，之後回報每次移動直到放開 | 2813e023 |
| 整體亮度 | 維持現狀，見 display-brightness.md | 6b9dce45 |

## 設計如此，不是缺陷

- 比 411 dp 手機寬的 app 出現字中換行(「Rese/t」):來自 app 的大小、裝置寬度、字型與按鈕外框(731f5668)。
- 平台慣例(字型、控制項外框、狀態列),除非它們造成裁切、重疊或遮住內容。

## 怎麼用

改到共用的 Kotlin helper 或核心時，兩個平台都要重新擷取。前後對照的證據把兩張擷圖並排；標籤用有 CJK 字形的字型
(`/System/Library/Fonts/STHeiti Medium.ttc`)。比對圖的間隔不要用洋紅色；很多 app 自己會畫這個顏色。
