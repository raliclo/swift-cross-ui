# iOS build pitfalls: stale products, PIF cache, compilers, SCUI_DEBUG

Five ways an iOS build has reported success while producing the wrong thing,
and the guard compile.zsh now has against each. Checked against compile.zsh
and test_ios.zsh on 2026-10-24.

## 1. Xcode's custom build location sends products elsewhere

- **Symptom.** From 2026-09-25 06:40 to 2026-09-27 every `compile.zsh -ios`
  printed BUILD SUCCEEDED, installed and launched the executable of 2026-09-25.
  The copy step gave it a fresh timestamp. A layout fix was reported working
  from a run of the old program (mistakes.md entry 29).
- **Cause.** This Mac's Xcode has `IDEBuildLocationStyle = Custom` with an
  absolute `IDECustomBuildProductsPath`. That preference outranks
  `-derivedDataPath`, so fresh products went to the custom folder while the
  bundle step copied an old file from `Build/Products`.
- **Guard.** Every xcodebuild call pins `SYMROOT` and `OBJROOT`. The bundle step
  touches a marker first and refuses an executable not newer than it, printing
  `defaults read com.apple.dt.Xcode | grep -i BuildLocation`.
- **Second occurrence (2026-09-29).** test_ios.zsh's own `build-for-testing` of
  the XCUITest runner lacked the pin; the runner under test was the one from
  2026-09-22, so a new verb (`orient`) read "unsupported". Rule: every
  `xcodebuild` in the tree needs SYMROOT/OBJROOT.
- **Rule of thumb.** When a change seems to have no effect, grep the INSTALLED
  binary for a string the change added.

## 2. An up-to-date build is rejected by the freshness check

xcodebuild does not relink when nothing changed, so the marker check rejected
nine correct builds on 2026-10-05. compile.zsh now deletes
`<products>/<Pn>` before building, so the executable is always relinked
(f1fa54c0).

## 3. "Redefinition of module '_SwiftSyntaxCShims'"

- **Cause (2026-10-05, P76/P77/P12).** xcodebuild without `-derivedDataPath`
  resolved packages into `~/Library/Developer/Xcode/DerivedData/TestApps-*`
  while Swift Bundler used `.compile-work-ios/.../SourcePackages`, over one
  OBJROOT. Cached PIFs (`XCBuildData/PIFCache`) hold absolute package paths and
  an unchanged target keeps its PIF, so `SwiftCrossUIMacrosPlugin` got both sets
  of `-I`.
- **Guard.** One `-derivedDataPath` (5deb2156). Before each build compile.zsh
  greps the PIF cache for a `SourcePackages/` outside this tree and, if found,
  deletes `XCBuildData` (one full rebuild, announced) (68974ff7).

## 4. CC/CXX from a shell profile

A profile exporting `CC`/`CXX` as Homebrew LLVM made xcodebuild compile the C
targets with it and turn explicit modules off: one P12 build had 341 Homebrew
clang lines and 354 "did not match the configured compiler". compile.zsh runs
`unset CC CXX` for the xcodebuild subshell only.

## 5. SCUI_DEBUG is cached with the manifest

- SwiftPM caches the result of evaluating `Package.swift`, keyed on the manifest
  and toolchain, not the environment it read. Flipping `SCUI_DEBUG` between two
  runs changed nothing (measured 2026-09-02: a build without it still had the
  `#if SCUI_DEBUG` strings). compile.zsh stamps the value in
  `.compile-work-*/.scui-debug-value` and clears the manifest caches when it
  changes; it also exports the variable so the child `swift`/xcodebuild sees it.
- The gate is the define, not the configuration: `BUILD_CONFIG=debug` never
  defined SCUI_DEBUG.
- test_ios.zsh rebuilds with `SCUI_DEBUG=1`. Before that (2026-09-02) its
  rebuild replaced a debug build with one where `DebugFeatures.isCompiledIn`
  was false: `--actionfile` parsed, the run reported success, and nothing was
  replayed.

## Also

- A plain host `swift build` on macOS does not build UIKitBackend. A UIKit edit
  is verified only by `compile.zsh -ios` (missed twice, e.g. 2026-09-20).
- A disk with under 1 GB free failed an iOS build (P100, 2026-10-17).

## Evidence

mistakes.md entry 29 (line 2317); 91e0b600, 5deb2156, 68974ff7, f1fa54c0,
c5ebafe2; testapp/compile.zsh notes beside `scui_debug_stamp`, `xcbuild_data`
and `bundle_started`; test_ios.zsh comment above `xcodebuild build-for-testing`.

---

# iOS 建置陷阱:陳舊產物、PIF 快取、編譯器、SCUI_DEBUG

iOS 建置曾經五度回報成功卻產出錯誤的東西，以及 compile.zsh 現在對每一種的防護。
2026-10-24 對照 compile.zsh 與 test_ios.zsh 確認。

## 1. Xcode 的自訂建置位置把產物送到別處

- **症狀。** 2026-09-25 06:40 到 2026-09-27,每次 `compile.zsh -ios` 都印出 BUILD SUCCEEDED,
  安裝並啟動的卻是 2026-09-25 的執行檔。複製步驟給了它新的時間戳。一項版面修正因此根據舊程式的
  執行結果被回報為有效(mistakes.md 第 29 條)。
- **原因。** 這台 Mac 的 Xcode 設為 `IDEBuildLocationStyle = Custom`,並有絕對路徑的
  `IDECustomBuildProductsPath`。這個偏好設定優先於 `-derivedDataPath`,所以新產物寫到自訂資料夾，
  而打包步驟從 `Build/Products` 複製了舊檔。
- **防護。** 每個 xcodebuild 呼叫都釘住 `SYMROOT` 與 `OBJROOT`。打包步驟先 touch 一個標記檔，
  執行檔不比它新就拒絕，並印出 `defaults read com.apple.dt.Xcode | grep -i BuildLocation`。
- **第二次發生(2026-09-29)。** test_ios.zsh 為 XCUITest runner 做的 `build-for-testing` 沒有釘住，
  受測的 runner 是 2026-09-22 的那一個，所以新的動作(`orient`)被報成「unsupported」。規則：樹中每個
  `xcodebuild` 都要帶 SYMROOT/OBJROOT。
- **經驗法則。** 修改看似沒有效果時，先在**已安裝**的執行檔中 grep 該修改新增的字串。

## 2. 無變更的建置被新鮮度檢查拒絕

沒有變更時 xcodebuild 不會重新連結，所以 2026-10-05 標記檢查拒絕了九次正確的建置。compile.zsh 現在
建置前先刪除 `<products>/<Pn>`,執行檔一定會重新連結(f1fa54c0)。

## 3. 「Redefinition of module '_SwiftSyntaxCShims'」

- **原因(2026-10-05,P76/P77/P12)。** 沒有 `-derivedDataPath` 的 xcodebuild 把套件解析到
  `~/Library/Developer/Xcode/DerivedData/TestApps-*`,Swift Bundler 則用
  `.compile-work-ios/.../SourcePackages`,兩者共用一個 OBJROOT。快取的 PIF(`XCBuildData/PIFCache`)
  含有套件的絕對路徑，內容沒變的 target 會沿用它的 PIF,於是 `SwiftCrossUIMacrosPlugin` 拿到兩組 `-I`。
- **防護。** 只用一個 `-derivedDataPath`(5deb2156)。每次建置前 compile.zsh 會在 PIF 快取中 grep
  本樹以外的 `SourcePackages/`,找到就刪除 `XCBuildData`(一次完整重建，會明白印出)(68974ff7)。

## 4. shell 設定檔中的 CC/CXX

設定檔把 `CC`/`CXX` 匯出為 Homebrew LLVM 時,xcodebuild 用它編譯 C target 並關掉 explicit modules:
一次 P12 建置有 341 行 Homebrew clang 與 354 次「did not match the configured compiler」。compile.zsh
只在 xcodebuild 的子 shell 中 `unset CC CXX`。

## 5. SCUI_DEBUG 跟著 manifest 一起被快取

- SwiftPM 快取的是求值 `Package.swift` 的結果，鍵值是 manifest 與工具鏈，不含它讀取的環境。
  兩次執行之間切換 `SCUI_DEBUG` 沒有任何效果(2026-09-02 實測：不帶它的建置仍含有 `#if SCUI_DEBUG`
  的字串)。compile.zsh 把值蓋印在 `.compile-work-*/.scui-debug-value`,值改變時清除 manifest 快取;
  它也匯出該變數，讓子程序 `swift`/xcodebuild 看得到。
- 閘門是那個定義，不是組態:`BUILD_CONFIG=debug` 從來不會定義 SCUI_DEBUG。
- test_ios.zsh 以 `SCUI_DEBUG=1` 重建。在此之前(2026-09-02)它的重建會把 debug 建置換成
  `DebugFeatures.isCompiledIn` 為 false 的建置:`--actionfile` 照樣解析、執行回報成功，卻什麼都沒重放。

## 其他

- macOS 上單純的主機 `swift build` 不會建置 UIKitBackend。UIKit 的修改只能用 `compile.zsh -ios`
  驗證(曾漏掉兩次，例如 2026-09-20)。
- 磁碟剩餘空間不足 1 GB 時 iOS 建置失敗(P100,2026-10-17)。

## 證據

mistakes.md 第 29 條(第 2317 行);91e0b600、5deb2156、68974ff7、f1fa54c0、c5ebafe2;
testapp/compile.zsh 中 `scui_debug_stamp`、`xcbuild_data`、`bundle_started` 旁的註解;
test_ios.zsh 中 `xcodebuild build-for-testing` 上方的註解。
