# 平台測試矩陣

此文件說明哪個 repro app 測哪個 issue，以及在各平台執行後能得到什麼結論。各 app 的逐步操作在 `UI-test-plan overall-en.md`；Linux 工作策略在 `UI-test-plan linux-en.md`。本文件只回答一個問題：*這個 issue 要在哪裡跑，而結果算不算數？*

內容來自 `issues.csv`，它是 source of truth。若要重新產生 issue 與 app 的對應：

```sh
awk -F, 'NR>1 && $4 ~ /p[0-9]+$|p[0-9]+;/ {print $4"  #"$1"  "$3}' testapp/issues.csv
```

## 圖例

| | 意義 |
| --- | --- |
| 🎯 | Issue 回報在這個平台上。此平台的一次執行即可判定該 issue。 |
| 🔍 | Issue 不是回報在這個平台上，但執行結果可作為有用比較；一致或不一致本身就是 finding。 |
| ⬜ | 沒有可學到的資訊。App 可建置與執行，但此平台無法呈現這個 issue。 |
| ✅ | 此平台已修正。執行它是 regression check。 |
| 🚫 | 沒有對應硬體、simulator 或 toolchain。這是套用在哪台機器，請看下方表格。 |
| 〰️ | 可在 WSLg 執行，但結果不能判定 issue：這是 WSLg 會扭曲的 window-sizing 案例之一。先在這裡重現，再到 🐧 確認。 |

桌面平台欄位：🪟 Windows（WinUIBackend）· 🌊 WSLg（Wayland compositor 下的 GtkBackend）· 🐧 Linux（真實 desktop session 上的 GtkBackend）· 🍎 macOS（AppKitBackend）。Mobile：📱 iOS（UIKitBackend）· 🤖 Android（AndroidBackend）。

WSLg 和 Linux 分成不同欄位，因為兩者會有差異。WSLg 是 Wayland compositor，不是真正的 desktop session，因此 window sizing、minimum sizes、decorations 行為不同；這也是 `UI-test-plan linux-en.md` 已記錄的 Tier 1 / Tier 2 分界來源。🌊 下標為 〰️、但 🐧 下標為 🎯 的兩列，就是分開兩欄的理由：WSLg 可以顯示症狀，但只有 desktop session 能判定。〰️ 不會出現在 🐧 下，因為它描述的是 WSLg 這個環境，而不是 GtkBackend 本身。

只有 #556 和 #289 使用 〰️。Tier 2 不等於「WSLg 不可信」：它只是收集需要*某種* caveat 的 issue，而原因各不相同。#595 和 #158 標示為非 GTK-specific，#291 回報為 Gtk **未**受影響，#295 的 caveat 則是 Gtk3Backend 半邊不在範圍內。這些都不是在談 WSLg fidelity，因此若把它們標成 〰️，反而會錯稱 compositor 會扭曲與它無關的結果。

## 各平台可在哪裡執行

此 repository 會在兩台機器上工作，所以「這裡」取決於你正在看的 checkout。以下以機器而非檔案說明：

| Platform | Windows workstation | macOS workstation |
| --- | --- | --- |
| 🪟 Windows | ✅ native | 🚫 |
| 🌊 WSLg | ✅ WSL2 + WSLg, GTK 4.22.4, Swift 6.3.3 | 🚫 |
| 🐧 Linux | 🚫 no desktop session | 🚫 |
| 🍎 macOS | 🚫 | ✅ native |
| 📱 iOS | 🚫 | ✅ Simulator, iOS 18.4 |
| 🤖 Android | 🚫 | ✅ SDK + NDK, device or emulator |

兩台機器都沒有真正的 Linux desktop session，因此 🐧 欄目前兩邊都不可達。它仍存在，是因為若干在 🌊 下量到的結果，在有人於 🐧 重跑前都明確只是 provisional。

## Binaries

Windows workstation 可達的兩個平台都已建置全部 18 個 apps：🌊 WSLg 下是 `testapp/output/PN`，🪟 Windows 下是 `testapp/output/PN.exe`。目前沒有任何東西在 🐧 下建置過，所以該欄沒有結果。重新建置：

```sh
zsh testapp/compile.zsh P0 P1 P2 P3 P4 P5 P6 P7 P8 P9 P10 P11 P12 P13 P14 P15 P16 P17
```

## 矩陣

### Open issues -- desktop

| Issue | App | 🪟 | 🌊 | 🐧 | 🍎 | 內容 |
| --- | --- | :-: | :-: | :-: | :-: | --- |
| #389 | P3 | ✅ | 🎯 | 🎯 | ⬜ | Images aren't clipped -- WinUI 半邊已修，GTK 半邊仍 open |
| #390 | P2 | ✅ | 🎯 | 🎯 | ⬜ | Disabled buttons 看起來不像 disabled -- 同樣是 split 狀態 |
| #476 | P7 | ⬜ | 🎯 | 🎯 | ⬜ | List 啟動時第一項已被選取 |
| #556 | P7 | ⬜ | 〰️ | 🎯 | ⬜ | NavigationSplitView size decisions 異常 |
| #417 | P8 | ⬜ | 🎯 | 🎯 | ⬜ | ScrollView cornerRadius 沒有裁切 children |
| #426 | P8 | ⬜ | 🎯 | 🎯 | ⬜ | Horizontal ScrollView 吞掉 parent 的 scroll wheel |
| #504 | P9 | ⬜ | 🎯 | 🎯 | ⬜ | TextField/SecureField 第一次更新後高度縮小 |
| #295 | P9 | ⬜ | 🎯 | 🎯 | ⬜ | Text 沒有被裁切到 zero width |
| #478 | P10 | ⬜ | 🎯 | 🎯 | ⬜ | Ctrl-Q 無法結束 |
| #454 | P10 | ⬜ | 🎯 | 🎯 | 🎯 | Transparent containers 吃掉 clicks -- 兩個 backends 都受影響 |
| #386 | P15 | 🔍 | 🎯 | 🎯 | ⬜ | 不支援 dark mode |
| #289 | P15 | ⬜ | 〰️ | 🎯 | ⬜ | Gtk-drawn title bars 下的 window minimum height |
| #160 | P16 | 🎯 | 🔍 | 🔍 | ⬜ | Split view 第一次 render 時 layout 錯誤 |
| #595 | P13 | 🎯 | 🎯 | 🎯 | 🎯 | ScrollView 內文字被裁切（core） |
| #158 | P13 | 🎯 | 🎯 | 🎯 | 🎯 | ZStack 內的 Group 沿錯誤 axis layout（core） |
| #291 | P13 | 🔍 | 🔍 | 🔍 | 🎯 | NavigationSplitView minimum width -- AppKit 有問題，Gtk 沒問題 |
| #415 | P13 | 🔍 | 🔍 | 🔍 | 🎯 | Non-Identifiable ForEach 在 AppKit crash |
| #264 | P17 | 🎯 | 🎯 | 🎯 | 🎯 | frame(idealWidth:) 永遠沒有到達 fixedSize（core） |
| #266 | P17 | 🎯 | 🎯 | 🎯 | 🎯 | 兩個 layout edge cases（core） |
| #161 | P17 | 🎯 | 🎯 | 🎯 | 🎯 | Picker 依 selection 或最大項目決定大小 -- 需要 2+ platforms |
| #82 | P11 | ⬜ | ⬜ | ⬜ | 🎯 | 互相 clamp 的 sliders 會 jitter |
| #485 | P11 | ⬜ | ⬜ | ⬜ | 🎯 | Scrollbar 方向相反 |
| #473 | P11 | ⬜ | ⬜ | ⬜ | 🎯 | Compact DatePicker sizing |

### Open issues -- mobile

| Issue | App | 📱 | 🤖 | 內容 |
| --- | --- | :-: | :-: | --- |
| #595 | P13 | 🎯 | 🎯 | ScrollView 內文字被裁切（core） |
| #158 | P13 | 🎯 | 🎯 | ZStack 內的 Group 沿錯誤 axis layout（core） |
| #264 | P17 | 🎯 | 🎯 | frame(idealWidth:) 永遠沒有到達 fixedSize（core） |
| #266 | P17 | 🎯 | 🎯 | 兩個 layout edge cases（core） |
| #161 | P17 | 🎯 | 🎯 | Picker 依 selection 或最大項目決定大小 -- 需要 2+ platforms |
| #324 | P14 | 🎯 | ⬜ | Orientation change 時 proposed size 錯誤 |
| #254 | P14 | 🎯 | ⬜ | App background 沒有跟著 system theme 更新 |
| #632 | P12 | ⬜ | 🎯 | Buttons 有不必要 margin |
| #580 | P12 | ⬜ | 🎯 | Rotation 會 reset @State |
| #544 | P12 | ⬜ | 🎯 | Toggle state 沒有視覺呈現 |

Core-layout issues 同時出現在兩張表中：它們是 backend-independent，所以任何平台執行都算數，而兩個平台之間的不一致本身就是 finding。

### 已修正，保留作為 regression checks

| Issues | App | 🪟 | 內容 |
| --- | --- | :-: | --- |
| #493 #548 | P0 | ✅ | Launch-time crashes |
| #523 #659 #660 | P1 | ✅ | Dialogs and sheets |
| #204 #401 #449 #471 | P2 | ✅ | Controls and styling |
| #156 #190 #470 | P4 | ✅ | Bindings and callback storage |

P5 和 P6 沒有 upstream issue number：P5 是 multi-window alerts，P6 是 Windows GPU video path，NV12 工作就是從這裡延伸出來的。

## 依機器列出的執行項目

🌊 **WSLg**，在 Windows workstation 上 -- 17 個 issues，加上 #291 和 #415 作比較。尚未全部執行。〰️ rows 的結果在 🐧 存在前都維持 provisional：

```sh
./testapp/output/P2                            # 390
./testapp/output/P3                            # 389
./testapp/output/P7                            # 476 556
./testapp/output/P8                            # 417 426
./testapp/output/P9                            # 504 295
./testapp/output/P10                           # 478 454
./testapp/output/P13                           # 595 158, and 291 415 as comparisons
GTK_THEME=Adwaita:dark ./testapp/output/P15    # 386 289
./testapp/output/P17                           # 264 266 161
```

🪟 **Windows** -- 6 個 issues，加上 #291 和 #415 作比較：

```sh
./testapp/output/P16.exe                       # 160
./testapp/output/P13.exe                       # 595 158, and 291 415 as comparisons
./testapp/output/P17.exe                       # 264 266 161
./testapp/output/P15.exe                       # 386 as the control only
```

兩份清單在五個 core-layout issues 上重疊，這正是重點：它們是 backend-independent，所以在兩邊都跑，才能看出平台間是否不一致。其他項目則各自屬於特定欄位。

## 會讓結果無效的三件事

- **P15 若沒有 `GTK_THEME=Adwaita:dark`，就不算測 #386。** GtkBackend 宣告 `canOverrideWindowColorScheme = false`，所以 app 自己的 scheme buttons 無法改變任何東西。那些按鈕是 control；ambient theme 才是測試。
- **P16 若已經碰過視窗，就不算測 #160。** Resize 是會修正 layout 的兩件事之一，所以必須在移動任何東西前讀取 pane sizes。
- **P17 只在單一平台上跑，對 #161 沒有答案。** 這個 issue 是 backends 之間不一致，因此至少需要兩次執行來比較。

## 🌊 欄位的 caveats

WSLg 是 Wayland compositor，不是真正的 desktop session。Window sizing、minimum sizes、decorations 在那裡的行為不同，所以 🌊 和 🐧 分成兩欄，而不是合併成一欄。#556 和 #289 標為 〰️，因為兩者都和 window sizing 本身有關；Tier 2 其他項目有其他原因需要 caveat，但不受 compositor 影響。Gtk 在 Wayland 下確實會畫 client-side decorations，所以 #289 的前提成立；但這不是 Fedora + GNOME，因此 negative result 只能界定 bug 範圍，不能直接關閉它。

這裡的 GTK 是 4.22.4，夠新，因此 #702（關於*較舊* GTK 4）完全無法重現。Gtk3Backend 完全不在 scope 內，因此 #286 和 #166 被排除，也表示 #426 只會用 GTK 4 測。
