# flow.md —— 兩台主機，兩條軌，一次一條

How work is done in this repository. It is organised by **host machine** rather
than by feature, because that is the constraint everything else follows from:
no machine can build more than half of this matrix, so the unit of work is a
track, not a task.

這份文件講的是「這個 repository 裡的工作怎麼進行」。它以**主機**組織，而不是以功能組織，因為那才是
其他一切所依循的限制：**沒有任何一台機器建得動一半以上的矩陣**，因此工作的單位是「一條軌」，不是
「一個任務」。

這不是 [`CLAUDE.md`](CLAUDE.md)——那一份只有一條硬規則（不得降級）。這一份講的是「怎麼把工作做到
能夠被相信」。

---

## 零、兩台主機，不是六個平台

| | Mac 軌 | Windows 軌 |
| --- | --- | --- |
| 目標 | macOS / iOS / Android | Win-WinUI / Win-gtk4 / WSL-gtk4 |
| backend | `AppKitBackend`、`UIKitBackend`、`AndroidBackend` | `WinUIBackend`、`GtkBackend`（兩種宿主） |
| **基準平台** | **iOS** | **WinUI** |
| 看不到 | 另一軌的三個 | 另一軌的三個 |

47 支測試 app × 5 個平台目錄 = 235 個動作檔格。兩條軌各自負責其中一半，而**兩邊都無法驗證對方的
那一半**。

### 為什麼每一軌要有一個「基準平台」

同一支 app 在同一軌的三個目標上，應該畫出**同樣大小的視窗**。不是因為好看，而是因為：

- 座標可以互相對照。動作檔以「點」書寫；若 Android 的視窗比 iOS 大或小，同一份檔案的座標在兩邊
  指向不同的東西，而**錯誤的座標不會報錯，它會按到別的東西**。
- 截圖可以並排。「這一格與對照格相同」這種主張，只有在兩張圖的尺度相同時才讀得出來。
- 差異變成訊號。若兩者尺寸本該相同而實際不同，那件事本身就是缺陷，而不是雜訊。

Mac 軌以 iOS 為基準，Windows 軌以 WinUI 為基準。

---

## 一、Mac 軌

依序執行。**每一步都要跑完全部三個目標，再進下一步**——不要把一支 app 一路走到底，因為那樣「同一步
在三個目標上的差異」就看不見了。

### 1. 建置三個目標

    cd testapp
    zsh ./compile.zsh <Pn>                                    # macOS
    SCUI_DEBUG=1 zsh ./compile.zsh -ios <Pn>                  # iOS
    SWIFT_BIN=~/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swift \
      SCUI_DEBUG=1 zsh ./compile.zsh -android <Pn>            # Android

`SWIFT_BIN` 不是選用的：Android SDK bundle 是 Swift 6.3.3，而本機預設的 `swift` 是 6.4，少了它會
直接失敗於「module compiled with Swift 6.3.3 cannot be imported by the Swift 6.4 compiler」。

**建不起來的,本身就是結果。** 2026-09-02 發現 P41 與 P6 從未為 iOS 建置過——各自因為一個沒有防護的
不可用符號,而 swift-bundler 把十二個錯誤全藏在「Failed to run xcodebuild」之後。

### 2. 量體積，並寫進文件

`matrix_coverage/executable-size.csv2`。**目前它只有四欄**：`windows_gtk4_bytes`、
`windows_winui_bytes`、`linux_gtk4_bytes`、`macos_appkit_bytes`——**沒有 iOS，也沒有 Android**。
Mac 軌的這一步現在沒有地方可以記，那是這條流程照出來的第一個缺口。

量的是什麼要說清楚：macOS 量的是執行檔，iOS 與 Android 量的是 **app bundle / APK**，兩者不可比。
欄名要各自說明自己量的是哪一個。

### 3. 保證 Android 的視窗尺寸與 iOS 一致

這一步在「寫動作檔」之前，因為它決定那些座標有沒有意義。

iPhone 16 模擬器：393 × 852 點，擷取 1179 × 2556 像素，比例 3。
Android emulator（`swift-cross-ui-api36`）：1080 × 2400 像素，density **2.625** —— 即 411 × 914 點。

兩者**不相同**，而目前沒有任何東西要求它們相同。這一步要做的是：讓 Android 的測試裝置以 iOS 的
點尺寸呈現，或明確記下兩者的換算，使同一支 app 的兩份動作檔可以互相對照。

`wm size` 與 `wm density` 可以調整 emulator；Android agent 2026-09-02 的普查就是在
`wm density 160` 下拍的，因為原生 420 dpi 下版面會超出 411 dp 而被裁切——**那次改動事後有復原,
而它本身就是「尺寸不一致會改變結論」的證據**。

### 4. 檢查動作檔

    zsh ./test.zsh <Pn> --macos --actionfile
    zsh ./test_ios.zsh <Pn> --no-build --actionfile actions/ios/<file>.csv --showtime 4
    SWIFT_BIN=… SCUI_DEBUG=1 zsh ./test_android.zsh <Pn> --actionfile actions/android/<file>.csv

規則見第三節。

### 5. 更新文件

`matrix_coverage/coverage-matrix.csv2`（用 `csv2`，不要切逗號）、`bugs/bug-<Backend>.md`、
以及任何雙語文件的**兩個半邊**。

---

## 二、Windows 軌

### 1. 建置三個目標

    zsh testapp/compile.zsh <Pn>              # Win-WinUI
    zsh testapp/compile.zsh -gtk4 <Pn>        # Win-gtk4
    # WSL-gtk4：在 WSL 內執行同一支腳本

### 2. 量體積，並寫進文件

`executable-size.csv2` 的三個 Windows/Linux 欄位已經存在，48 筆紀錄。這一軌的這一步是現成的。

### 3. 保證兩個 gtk4 目標的視窗尺寸與 WinUI 一致

同一支 app 在 Win-WinUI、Win-gtk4、WSL-gtk4 上應該給出同樣大小的視窗。

這裡有一個已經付過代價的陷阱，寫在 `Sources/InputEvent/Synthesiser.swift` 的 `WindowGeometry.scale`
上：2026-08-27 這台機器由 125% 改為 100% 時，所有 Windows 動作檔的 13 個 y 座標**無一例外**恰好
變動 1.25 倍——也就是 widget 的實體像素位置根本沒有移動。Windows 上的 GTK 4 會把比例取整為整數，
兩種 DPI 下都以 1 排版，而 synthesiser 仍然照乘 1.25。**一個本應與縮放無關的格式，因此不是。**

所以這一步量的是「toolkit 實際排版時所用的比例」，不是顯示器回報的比例。

### 4. 檢查動作檔

    zsh testapp/test.zsh <Pn> -win --actionfile
    zsh testapp/test.zsh <Pn> --wsl --actionfile

### 5. 更新文件

同 Mac 軌第 5 步。

---

## 三、每一步共通的規則

### 3a. 建置系統會對你說謊

三件事，2026-09-02 各咬過一次，而**三件事從外面看都像成功**：

- **SwiftPM 的 manifest 快取不含環境變數。** `Package.swift` 讀 `env["SCUI_DEBUG"]`，而快取的鍵值
  取自 manifest 的內容與工具鏈。在 `SCUI_DEBUG=1` 之後跑一次不帶該變數的建置，產出的「release」
  執行檔裡仍含有只存在於 `#if SCUI_DEBUG` 之內的字串。`compile.zsh` 現在把該值蓋印在 work 目錄。
- **bundler 的 build plan 看不見新檔案。** 加一個新的 `.swift` 到既有 target，`.build-bundler`
  不會重新規劃，回報 `cannot find 'X' in scope` 而該型別就在旁邊。刪
  `.build-bundler/debug.yaml` 與 `build.db`。
- **一個寫了卻永不為真的閘門。** `AndroidBackend` 不在拿到 `debugSwiftSettings` 的清單裡，因此
  `#if SCUI_DEBUG` 永遠是 false，啟動重放的那一行被編譯掉。旗標送達了、log 也印了、程式碼也連結
  進去了——什麼都沒重放。

**一個寫了卻永不為真的閘門，與一個被解析後丟掉的選項，是同一種失敗。**

### 3b. 螢幕截圖優先於 log，而截圖要先確認身分

`replaying …` / `geometry …` / `replayed …` 三行都出現，仍然可能什麼都沒發生。**唯一的證據是畫面。**

而 `test_ios.zsh` 把任何 Pn 都複製成固定的 `debugTarget`，bundle id 也固定——**兩個 agent 同時跑，
你的截圖會是對方的 app**，沒有任何錯誤。2026-09-02 實際發生兩次。每一張要拿來量座標或驗證的截圖，
都必須先確認它顯示的是你的 app。

### 3c. 數畫面上的東西，不要數你以為的東西

Android 的清空缺陷是靠「非白像素數 378,653 → 0」釘住的；而「是尺寸歸零還是元件消失」，是靠
`uiautomator dump` 的**節點數 85 → 9** 才分清楚。形容詞在這裡沒有用。

### 3d. 動作檔的硬規則

- 標頭 `action,x,y,origin,button,key,micros,note,platform`，九欄，RFC 4180。
  **note 中未加引號的逗號會弄壞整個檔案。**
- 動詞小寫；數字鍵是 `"1"` 不是 `"one"`；iOS 與 Android 都拒絕鍵盤列。
- **會改變版面的點擊，一個檔案只放一個。**
- `scroll` 一格 40 點、符號相反，而**拖曳必須留在視窗內**——會離開的手勢靜默地什麼都不做。
- 檔頭必須寫明該裝置的點尺寸、擷取尺寸與比例。Android 還要寫 density——一份沿用舊座標的檔案用了
  299 點，而目標在 942 像素（359 點），**它按到了分頁按鈕**，而接下來兩輪的失敗都被歸咎到觸控機制。
- 每一列的 note 必須是能從截圖讀出的主張。重放、看，然後才補 `(VERIFIED: …)`。
  **若畫面與主張矛盾，寫下實際發生的事。**

### 3e. 一份不主張任何事的檔案，比沒有檔案更糟

它會在功能損壞時通過。

### 3f. 一項功能要嘛在五個 backend 上都有，要嘛不存在

`CLAUDE.md` 的內容。此處只補一句：**「這個平台沒有對應的 API」是待查證的主張。** 2026-09-02 我曾以
「`CALayer.filters` 在 iOS 上不參與合成」為由拒絕實作 `VisualEffects`。那個量測是對的，由它推出的
結論是錯的——iOS 提供的路徑是「把 filter 套用在子樹的算繪結果上」。**一項量測到的平台限制，終究
只是「所走那條路」的限制。**

### 3g. `mistakes.md` 的維護：記的是「我說錯的話」，不是「找到的 bug」

這兩者常被混為一談，而它們的用途完全不同：

| 檔案 | 記什麼 | 主詞 |
| --- | --- | --- |
| `bugs/bug-<Backend>.md` | 程式的缺陷 | 那個 backend |
| `mistakes/mistakes.csv2` | **我當時的說法，以及實際情況** | 我 |

一個 backend 的缺陷不進 `mistakes`。**一句我說出口、後來被證明是假的話**才進——即使那句話最後
沒有造成任何損害。

#### 怎麼加一列

`mistakes.md` 是**產生出來的**。它自己第五行就寫著「請勿編輯本檔」，而下一次執行產生器會把手改的
內容覆蓋掉。

    csv2 -i mistakes/mistakes.csv2 --in-place \
         -append '2026-09-03,Area,"我當時的說法","實際情況","被什麼抓到","教訓"'
    zsh mistakes/mistakes.zsh

六個欄位。**`caught_by` 是其中最有用的那一個**——該檔開頭自己說明了為什麼：它記的是「當時最便宜的
查證方式是什麼」，而其中大多數，在說出那句話之前就已經可以做了。

#### 三個已經踩過的坑

- **rebase 衝突時手改 `mistakes.md`。** 2026-09-03 我這麼做了,即使該檔第五行就寫著不要。衝突要
  解在 `.csv2` 上,然後重新產生。手改 md 解出來的衝突,會在下一次執行產生器時無聲消失。
- **`.csv2` 有兩行標題**（英文、繁中）。用 `len(rows) - 1` 數資料列會多算一筆,而我就是這樣得出
  「兩個檔案不同步」的錯誤結論——然後才發現是自己數錯。要數就數 `len(rows) - 2`,或直接用
  `zsh mistakes/mistakes.zsh --count`。
- **欄位裡有逗號。** 用 `csv2` 或 Python 的 `csv` 模組,絕不用 `cut -d,`。

#### 什麼時候寫

**在修好之前寫，不是修好之後。** 修好之後，那句錯話會顯得無關緊要，於是它不會被寫下來——而
`caught_by` 這一欄的價值，正好來自「當時我本來可以怎麼發現」，那份記憶在修好之後就模糊了。

2026-09-03 這一天補了三筆，全都是「診斷或量測的錯」而非程式錯誤：把一張裁切圖當成縮放後的證據拿給
人看；從一支 app 的一個控制項推及整個平台的一項功能；以及在檢查輸入之前就先改機制（那個「非同步
投遞」的修正毫無作用，真正錯的是一個座標）。

---

### 3h. 錯誤的診斷也要留著

修 Android 清空缺陷時做過三次改動，每一次都「看起來像是答案」：

| 改動 | 是不是真 bug | 有沒有修好清空 |
| --- | --- | --- |
| 非同步投遞觸控 | 否——誤判 | 否 |
| `MATCH_PARENT`(-1) 不再被乘上 density 變成 `WRAP_CONTENT`(-2) | **是** | 否 |
| 為根內容加上捲動宿主 | **是**（iOS 早就有） | 否 |

三個 commit 都寫明了「這個沒有修好目標問題」。**一個沒說出自己無效的修正，會讓下一個人以為那條路
已經走過了。**

---

## 四、覆蓋率要用程式數

    cd testapp && python3 -c '
    import glob, os, re
    apps = sorted(os.path.basename(p)[:-6] for p in glob.glob("P*.swift"))
    for plat in ["mac", "ios", "android", "win", "wsl"]:
        have = set()
        for f in glob.glob(f"actions/{plat}/*.csv"):
            m = re.match(r"(P[\w-]*?)-[a-z]", os.path.basename(f))
            if m: have.add(m.group(1))
        missing = [a for a in apps if a not in have]
        print(f"{plat:8} {len(apps)-len(missing):2}/{len(apps)}  missing: {missing}")'

2026-09-03：**Mac 軌** mac 46/47、ios 46/47、android 1/47。**Windows 軌** win 22/47、wsl 9/47。

**不是每一個空格都是缺口。** `P6-v2.swift` 直接 `import Gtk`，`compile.zsh` 本來就會擋；它在 mac
與 ios 欄永遠是空的，而那不是覆蓋率有缺，是計數方式錯了。

---

## 五、檢查清單

### Mac 軌

- [ ] 三個目標都建得起來（建不起來本身就是結果，記下來）
- [ ] app bundle / APK 體積寫進 `executable-size.csv2`（**該表目前缺 ios 與 android 欄**）
- [ ] Android 的視窗點尺寸與 iOS 一致，或換算關係已寫明
- [ ] 三份動作檔都重放過，且**讀過截圖**，`(VERIFIED: …)` 寫的是實際看到的東西
- [ ] 回歸：跑一份相鄰但無關的動作檔
- [ ] 若過程中說錯過話，`csv2 -append` 進 `mistakes.csv2`，再跑產生器
- [ ] `coverage-matrix.csv2`、`bugs/`、雙語文件的兩個半邊

### Windows 軌

- [ ] 三個目標都建得起來
- [ ] 執行檔體積寫進 `executable-size.csv2`
- [ ] Win-gtk4 與 WSL-gtk4 的視窗尺寸與 WinUI 一致；量的是 toolkit 的比例，不是顯示器回報的比例
- [ ] 三份動作檔都重放過，且讀過截圖
- [ ] 若過程中說錯過話，`csv2 -append` 進 `mistakes.csv2`，再跑產生器
- [ ] 回歸；文件

---

## 附錄：這兩條軌在 2026-09-02 至 09-03 抓到了什麼

依「是什麼抓到的」分類。

**被一支測試 app 抓到的**
- P42 在 iOS 上第一次執行就顯示 `current: 1.0`，而該裝置的顯示縮放是 3——
  `computeWindowEnvironment` 留著一行 `// TODO: Record window scale factor in here`
- P39 的九格中有六格與對照格逐像素相同——`CALayer.filters` 在 iOS 上不參與合成
- P43 的環形描邊——「漸層被裁到填充區域而非描邊區域」會產生一個看起來完全合理的實心圓

**被「app 根本跑不起來」抓到的**
- P41、P6 從未為 iOS 建置過
- P13 / P7 / P16 在 iPhone 上死於 `createSplitView` 的 `precondition`

**被「重放了卻什麼都沒發生」抓到的**
- Android 的 `--actionfile` 被解析後丟掉、`main(0, nil)`、`CommandLine.arguments` 不來自該 argv、
  `#if SCUI_DEBUG` 永不為真——四層，每一層看起來都像成功

**被既有的動作檔抓到的**
- P11 的動作檔主張了一段那個按鈕不會寫入的狀態文字
- P30 的座標因頁面水平偏移而失效（y 全對，x 全偏 62 點）

**被「另一個平台」抓到的**
- macOS 上 P42 啟動時歷史就已是 `1.0 x2 -> 2.0 x8`，與 iOS 修好後同形——因此是啟動順序，不是
  backend 缺陷
- P17-DOE 的對照組在 AppKitBackend 上也被裁切，因此 #389 在 macOS 上無法判定

**被「這條流程本身」抓到的**
- `executable-size.csv2` 沒有 iOS 與 Android 欄位——Mac 軌的第 2 步無處可寫
- iOS 與 Android 的視窗點尺寸不同（393×852 對 411×914），而目前沒有任何東西要求它們相同
- 這一整天的三個「診斷或量測的錯」一筆都沒進 `mistakes.csv2`——直到寫這一節時才發現，並補上

**仍然沒抓到的**
- Android：任何讓內容需要更多寬度的狀態變更會清空視窗。已知不是動作檔機制、不是哨兵值 bug、
  不是缺少捲動宿主；已知節點數 85 → 9，即元件被移除而非縮成零。見 `bugs/bug-Android.md`。
