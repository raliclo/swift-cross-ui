# flow.md —— 在一個沒有人跑得完的矩陣上做開發

How work is done in this repository, framed as SDLC phases and run as a PDCA
loop. Every rule below was paid for; beside each one is where it went wrong
before the rule existed.

這份文件講的是「這個 repository 裡的工作怎麼進行」，以 SDLC 的階段組織，以 PDCA 的迴圈執行。
底下每一條規則都是付過代價的；每一條旁邊都寫著「在它存在之前，它在哪裡出過錯」。

這不是 [`CLAUDE.md`](CLAUDE.md)——那一份只有一條規則（不得降級），而且是硬性的。這一份講的是
「怎麼把工作做到能夠被相信」。

---

## 零、這個專案與其他專案的差別，就是那個矩陣

csv2 是一支工具，四個平台，一台機器跑得完。這裡不是。

| 維度 | 數量 |
| --- | --- |
| 平台 | 6 —— Android、iOS、Linux、macOS、Windows、WSL |
| backend | 5 —— `GtkBackend`、`WinUIBackend`、`AppKitBackend`、`UIKitBackend`、`AndroidBackend` |
| 測試 app | 47（`testapp/P*.swift`） |
| 動作檔格 | 47 × 5 個平台目錄 = 235 |

**而沒有任何一台機器跑得動超過三個平台。** 這台 Mac 能跑 macOS、iOS、Android；Windows 那台能跑
WinUI、GTK-on-Windows、WSL。兩邊都看不到對方的一半。

The single fact this document exists for: **no machine can run more than half
the matrix, so every claim carries the platform it was measured on or it is not
a claim.** Everything below follows from that.

這份文件存在的唯一理由：**沒有任何機器跑得完一半以上的矩陣，因此每一項主張都必須帶著「它是在哪個
平台上量到的」，否則它就不是一項主張。** 底下的一切都由此而來。

---

## 一、Plan —— 先問「這件事在這裡量得到嗎」

在寫任何一行之前，把要做的事分成三堆：

1. **這裡量得到的** —— 做，並且驗證。
2. **這裡量不到的** —— 不做，或做了但明確標記為未驗證，並說明是誰能驗證。
3. **不知道量不量得到的** —— 先花五分鐘查清楚，再回到 1 或 2。

### 為什麼第 2 堆不能省略成第 1 堆

2026-09-01，Windows 那一側新增了 `BackendFeatures.Paths.renderPath(...fillStyle:)`，並在它的
預設實作上寫下這段話：

> 刻意採加法式。改動上方的簽章會同時破壞五個 backend，而其中兩個——AppKit 與 UIKit——沒有 Mac
> 就無法編譯，因此那樣的改動等於為其中 40% 的實作盲寫，並讓下一個 pull 的人拿到建置失敗。

那是**正確的判斷**。它沒有盲寫，而是留下一個會出聲的降級路徑，並寫明誰能把它補完。九天後在 Mac 上
補完只花了一次 session，因為它留下的是「一個明確的缺口」，而不是「一段沒有人驗證過的程式碼」。

反例在同一棵樹裡：`testapp/actions/ios/README.md` 的英文半邊在 2026-09-02 更新為「scroll 已支援」，
中文半邊沒有，於是**同一份文件在四天裡自相矛盾**。雙語文件會半邊半邊地漂移，而只有另一半的讀者
會發現。

---

## 二、Design —— 一項功能要嘛在五個 backend 上都有，要嘛不存在

這一條是 `CLAUDE.md` 的全部內容，此處只補充它在流程上的位置：**它屬於設計階段，不屬於實作階段。**

面對缺失的 conformance，三種回應中只有一種可接受：

| 回應 | 可接受 |
| --- | --- |
| `fatalError`——行程終止 | 否 |
| 降級——警告一次、顯示未修飾的 view | 否（僅限 Curses/LVGL/Qt/Dummy） |
| 實作它 | 是 |

### 「這個平台沒有對應的 API」是待查證的主張

2026-09-02：我曾以「`CALayer.filters` 在 iOS 上不參與合成」為由，拒絕為 UIKitBackend 實作
`VisualEffects`。那個**量測是對的**——P39 的九格中有六格與對照格逐像素相同——而**由它推出的結論是
錯的**。iOS 提供的路徑是「把 filter 套用在子樹的算繪結果上」，而非套用在活的 layer 上。

**一項量測到的平台限制，終究只是「所走那條路」的限制。**

---

## 三、Implement —— 建置系統會對你說謊

這一節不是關於程式碼，而是關於「你以為你建了什麼」。三個都在 2026-09-02 咬過人：

### 3a. SwiftPM 的 manifest 快取不含環境變數

`Package.swift` 讀 `env["SCUI_DEBUG"]` 來決定要不要定義該編譯條件。而 SwiftPM 快取的是「求值
manifest 的結果」，鍵值取自 manifest 的**內容**與工具鏈——不含它所讀取的環境。

於是在 `SCUI_DEBUG=1` 之後跑一次不帶該變數的建置，產出的「release」執行檔裡**仍然含有只存在於
`#if SCUI_DEBUG` 之內的字串**，而那個 debug 專用的浮動控制項照樣出現在畫面上。建置輸出沒有任何
跡象。`testapp/compile.zsh` 現在把該值蓋印在 work 目錄，值一變就清 manifest 快取。

### 3b. bundler 的 build plan 看不見新檔案

`compile.zsh -android` 用 `.build`，swift-bundler 用 `.build-bundler`。**加一個新的 `.swift`
檔到既有 target，bundler 那棵樹不會重新規劃**，於是回報 `cannot find 'X' in scope`，而該型別就
在旁邊的檔案裡。刪掉 `.build-bundler/debug.yaml` 與 `build.db` 即可強制重新規劃，且不丟棄已編譯
的物件。這件事在同一天咬了兩次。

### 3c. 一個寫了卻永不為真的閘門

`AndroidBackend` 不在拿到 `debugSwiftSettings` 的 target 清單裡，因此 `#if SCUI_DEBUG` 在它裡面
永遠是 false，而「啟動動作檔重放的那一行」被編譯掉了。旗標送達了、`CommandLine.arguments` 也持有
它、重放程式碼也連結進了 `.so`、`Show window` 也記錄了——**什麼都沒重放**。

**一個寫了卻永不為真的閘門，與一個被解析後丟掉的選項，是同一種失敗。**

---

## 四、Verify —— 螢幕截圖優先於 log，而截圖要先確認身分

### 4a. 「replayed」不等於「有效果」

`ActionFileReplay` 會在 stderr 印出 `replaying …` / `geometry …` / `replayed …`。三行都出現，
仍然可能什麼都沒發生：座標錯了、視窗不是你的、或該控制項本來就沒反應。**唯一的證據是畫面。**

### 4b. 錯誤的座標不會報錯，它會按到別的東西

Android emulator 的 density 是 2.625。一份沿用舊檔案座標的動作檔用了 299 點，而目標控制項在 942
像素（= 359 點）——**它按到了分頁按鈕**。接下來兩輪，我把由此而來的失敗歸咎於觸控機制本身，還為它
寫了一個「修正」（改成非同步投遞），毫無作用。

因此：**每一份動作檔的檔頭都必須寫明該裝置的 density 與擷取尺寸**，如
`testapp/actions/android/P12-increment-the-counter.csv` 所示。

### 4c. 模擬器與 emulator 是共用的單一裝置

`test_ios.zsh` 把任何 Pn 都複製成固定的 `debugTarget`，bundle id 也固定。**兩個 agent 同時跑,
你的截圖會是對方的 app**，而且沒有任何錯誤。2026-09-02 實際發生兩次:一次逾時、一次拍到主畫面。

**每一張要拿來量座標或驗證的截圖，都必須先確認它顯示的是你的 app**——每支 Pn 都會在頂端印出自己的
標題。

### 4d. 數畫面上的東西，不要數你以為的東西

Android 的清空缺陷，是靠「非白像素數」從 378,653 變成 0 才被釘住的；而它究竟是「尺寸歸零」還是
「元件消失」，是靠 `uiautomator dump` 的**節點數從 85 變成 9** 才分清楚的。形容詞（「看起來空了」）
在這裡沒有用。

---

## 五、Act —— 先把錯的寫下來，再修

### 5a. 錯誤的診斷也要留著

2026-09-02，`bugs/bug-UIkit.md` 寫著「iOS 上點按 List 的列不會選取」。那是從**一支 app 的一個
list** 推及全體。P3 的 detail list 會選取，P7 自己分割視圖裡的 sidebar 也會；真正的原因是
`UIView.hitTest` 對「落在自身 bounds 之外的點」會在查看任何 subview 之前就回傳 nil，而那與 list
無關——P30 的按鈕以同樣方式失敗，而 P30 裡根本沒有 list。

該條目現在保留著「它錯在哪裡」，因為那個錯法會再犯：**從一個樣本推及全體。**

### 5b. 每一句被更正的話都要有一個測試

`testapp/test_rootscroll_ios.zsh` 存在，是因為「release 建置不該顯示那個 debug 按鈕」這句話
**曾經是假的而沒有人知道**。它建置兩次、探測按鈕該在的角落、回報三項檢查。

### 5c. 一次只改一件事，而且要有對照

修 Android 清空缺陷時做過三次改動，每一次都「看起來像是答案」：

| 改動 | 是不是真 bug | 有沒有修好清空 |
| --- | --- | --- |
| 非同步投遞觸控 | 否——是我誤判 | 否 |
| `MATCH_PARENT`(-1) 不再被乘上 density 變成 `WRAP_CONTENT`(-2) | **是** | 否 |
| 為根內容加上捲動宿主 | **是**（iOS 早就有） | 否 |

三個 commit 的訊息都寫明了「這個沒有修好目標問題」。**一個沒說出自己無效的修正，會讓下一個人以為
那條路已經走過了。**

---

## 六、矩陣本身怎麼推進

### 6a. 覆蓋率要用程式數，不要用印象

    cd testapp && python3 -c '
    import glob, os, re
    apps = sorted(os.path.basename(p)[:-6] for p in glob.glob("P*.swift"))
    for plat in ["mac", "ios", "win", "wsl", "android"]:
        have = set()
        for f in glob.glob(f"actions/{plat}/*.csv"):
            m = re.match(r"(P[\w-]*?)-[a-z]", os.path.basename(f))
            if m: have.add(m.group(1))
        missing = [a for a in apps if a not in have]
        print(f"{plat:8} {len(apps)-len(missing):2}/{len(apps)}  missing: {missing}")'

2026-09-03 的實際數字：mac 46/47、ios 46/47、win 22/47、wsl 9/47、android 1/47。
兩個 46 是在這台 Mac 上補起來的；三個低的數字要在別的機器上補。

### 6b. 不是每一個空格都是缺口

`P6-v2.swift` 直接 `import Gtk`，`compile.zsh` 本來就會擋。它在 mac 與 ios 欄永遠是空的，而那
不是覆蓋率有缺，**是計數方式錯了**。先確認一支 app 在該平台上「應該」能跑，再把它算成缺口。

### 6c. 動作檔的硬規則

- 標頭 `action,x,y,origin,button,key,micros,note,platform`，九個欄位，RFC 4180。
  **note 中未加引號的逗號會弄壞整個檔案。**
- 動詞小寫；數字鍵是 `"1"` 不是 `"one"`；iOS 與 Android 都拒絕鍵盤列。
- **會改變版面的點擊，一個檔案只放一個。** 排在它之後的座標，所定址的是一個已不存在的版面。
- `scroll` 一格 40 點、符號相反，而**拖曳必須留在視窗內**——會離開的手勢靜默地什麼都不做。
- 每一列的 note 都必須是一個能從截圖上讀出的主張。重放、看、然後才補上
  `(VERIFIED: 你看到了什麼)`。**若畫面與主張矛盾，寫下實際發生的事**——那比一份會通過的檔案更有
  價值。

### 6d. 一份不主張任何事的檔案，比沒有檔案更糟

它會在功能損壞時通過。`P7-select-a-list-row.csv` 曾一度被改成按一個「由程式碼設定選取」的按鈕，
因為點按列沒有作用。那在當下是對的判斷，卻是不該保留的檔案：**該按鈕證明的是「選取會被算繪」，
而對「人是否做得出一次選取」隻字未提。**

---

## 七、可以直接抄的檢查清單

動一個 backend 的功能時，依序完成：

- [ ] 先問：這件事在這台機器上量得到嗎？量不到的，明確標記並寫明誰能量
- [ ] 讀 `bugs/bug-<Backend>.md` 與 `mistakes/mistakes.md` —— 這件事是不是已經錯過一次
- [ ] 實作（不是降級，不是 `fatalError`）
- [ ] 建置：確認你以為的旗標真的進了執行檔（`strings` 找一個 debug 專用字串）
- [ ] 跑一支能顯示該功能的測試 app，**讀截圖**，確認截圖是你的 app
- [ ] 寫或更新該平台的動作檔，重放，把 `(VERIFIED: …)` 補上實際看到的東西
- [ ] 回歸：跑一份與此無關但相鄰的動作檔（改 hit testing 就跑 P10）
- [ ] 把量到的東西寫進 `bugs/` 或 `matrix_coverage/coverage-matrix.csv2`（用 `csv2`，不要切逗號）
- [ ] 若診斷過程中走錯過路，把錯的那條也寫進 commit 訊息
- [ ] commit 訊息用英文，說明「量到什麼」而不只是「改了什麼」
- [ ] 更新雙語文件的**兩個半邊**

---

## 附錄：這個流程在 2026-09-02 至 09-03 抓到了什麼

依「是什麼抓到的」分類：

**被一支測試 app 抓到的**
- P42 在 iOS 上第一次執行就顯示 `current: 1.0`,而該裝置的顯示縮放是 3——
  `UIKitBackend.computeWindowEnvironment` 留著一行 `// TODO: Record window scale factor in here`
- P39 的九格中有六格與對照格逐像素相同——`CALayer.filters` 在 iOS 上不參與合成
- P43 的環形描邊——「漸層被裁到填充區域而非描邊區域」會產生一個看起來完全合理的實心圓

**被「app 根本跑不起來」抓到的**
- P41 從未為 iOS 建置過（指名了 `@available(iOS, unavailable)` 的符號，卻沒有防護）
- P6 從未為 iOS 建置過（十二個錯誤全被 swift-bundler 的「Failed to run xcodebuild」蓋住）
- P13/P7/P16 在 iPhone 上死於 `createSplitView` 的 `precondition`

**被「重放了卻什麼都沒發生」抓到的**
- Android 的 `--actionfile` 被解析後丟掉、`main(0, nil)`、`CommandLine.arguments` 不來自該 argv、
  `#if SCUI_DEBUG` 在該 target 中永不為真——四層，每一層看起來都像成功

**被既有的動作檔抓到的**
- P11 的動作檔主張了一段那個按鈕不會寫入的狀態文字
- P30 的座標因為頁面水平偏移而失效（y 全部正確，x 全部偏 62 點）

**被「另一個平台」抓到的**
- macOS 上 P42 啟動時歷史就已經是 `1.0 x2 -> 2.0 x8`,與 iOS 修好後的形狀相同——
  因此那是啟動順序，不是哪個 backend 的缺陷
- P17-DOE 的對照組在 AppKitBackend 上也被裁切，因此 #389 在 macOS 上無法判定

**仍然沒抓到的**
- Android：任何讓內容需要更多寬度的狀態變更會清空視窗。已知不是動作檔機制、不是哨兵值 bug、
  不是缺少捲動宿主；已知節點數從 85 掉到 9，也就是元件被移除而非被縮成零。見
  `bugs/bug-Android.md`。
