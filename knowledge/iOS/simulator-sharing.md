# Sharing the simulator: SoftPCB first, one run at a time

Rules for who may use the iOS simulator and when. Checked 2026-10-24 against
testapp/mobile_comparison_flow.md and test_support/platform_lock.zsh.

## SoftPCB has priority

The SoftPCB project (SoftPCB-UI / SoftPCB-mac sessions) also runs UI tests on
the iOS simulator and the Android emulator. When it asks for them:

- finish the current app's run, do not start the next one;
- say the simulator is free;
- resume only after SoftPCB says it is done.

Never start a test.zsh run on iOS or Android while SoftPCB holds them. A slot
it asked for was 10-15 minutes (P85, 2026-10-09). The rule is in
testapp/mobile_comparison_flow.md ("Yield the simulators to SoftPCB",
479a286b, 2026-10-09).

## One run per platform: the platform lock

`source test_support/platform_lock.zsh ios` (in test_ios.zsh and
`compile.zsh -ios`) makes a second iOS run wait. Two runs share the device,
`.compile-work-ios`, `testapp/.bundledApp` and the `.xctestrun` edited with
PlistBuddy, so a second run could rewrite the first one's action-file path.

- The lock is a directory `testapp/.platform-lock-ios` created by `mkdir`,
  holding the owner PID; a lock whose owner is dead is taken over; a child
  (compile.zsh under test_ios.zsh) passes through via
  `SCUI_PLATFORM_LOCK_IOS`.
- It is SOURCED at top level and released by traps, not a function with
  `zshexit`: zsh does not run `zshexit` when a script ends through `set -e` or
  a signal, and SoftPCB-mac found an iOS lock owned by a dead run (2026-10-05).
  A trap set inside a function fires when the function returns.
- Per platform, not desktop-wide: an Android run need not wait for an iOS run.

## Other rules

- One platform at a time in comparison work: never the iOS and Android harness
  together, and no macOS run while either is going.
- Because every run installs as `debugTarget`, two sessions once photographed
  each other's app without any error (2026-09-02). The lock now serialises
  runs; still check the capture shows the intended app.

---

# 共用模擬器:SoftPCB 優先，一次一個執行

誰可以在何時使用 iOS 模擬器的規則。2026-10-24 對照 testapp/mobile_comparison_flow.md 與
test_support/platform_lock.zsh 確認。

## SoftPCB 優先

SoftPCB 專案(SoftPCB-UI / SoftPCB-mac 工作階段)也在 iOS 模擬器與 Android 模擬器上跑 UI 測試。它要求使用時:

- 跑完目前這支 app,不要開始下一支;
- 告知模擬器已空出;
- 等 SoftPCB 說它完成後才繼續。

SoftPCB 佔用期間，絕不在 iOS 或 Android 上開始任何 test.zsh 執行。它要求過的時段是 10–15 分鐘(P85,2026-10-09)。
這條規則寫在 testapp/mobile_comparison_flow.md(「Yield the simulators to SoftPCB」,479a286b,2026-10-09)。

## 每個平台一次一個執行：平台鎖

`source test_support/platform_lock.zsh ios`(在 test_ios.zsh 與 `compile.zsh -ios` 中)讓第二個 iOS 執行等待。
兩個執行共用裝置、`.compile-work-ios`、`testapp/.bundledApp` 與以 PlistBuddy 修改的 `.xctestrun`,第二個執行可能
改寫第一個執行的動作檔路徑。

- 鎖是以 `mkdir` 建立的目錄 `testapp/.platform-lock-ios`,內含持有者 PID;持有者已結束的鎖會被接手;子程序
  (test_ios.zsh 底下的 compile.zsh)經由 `SCUI_PLATFORM_LOCK_IOS` 直接通過。
- 它在頂層被 **source**,並由 trap 釋放，而不是一個用 `zshexit` 的函式:腳本因 `set -e` 或訊號結束時 zsh 不會執行
  `zshexit`,SoftPCB-mac 就曾遇到一個持有者已結束的 iOS 鎖(2026-10-05)。在函式內設定的 trap 會在函式返回時就觸發。
- 以平台為單位，不是整個桌面:Android 執行不必等 iOS 執行。

## 其他規則

- 比較工作中一次只跑一個平台：不同時跑 iOS 與 Android 的 harness,兩者任一在跑時也不跑 macOS。
- 由於每次執行都以 `debugTarget` 安裝，曾有兩個工作階段互相拍到對方的 app,而且沒有任何錯誤(2026-09-02)。
  現在平台鎖會讓執行依序進行;仍請確認擷圖中是預期的 app。
