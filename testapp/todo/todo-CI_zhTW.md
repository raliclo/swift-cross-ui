# CI TODO：Android build

此文件追蹤 Android opt-in 變更（`0c90f3fc`）對 CI 的需求，以及仍需在 CI 上確認的事項。以下項目無法在本機完整驗證，因為 CI 環境和這台機器的差異會影響結果。

## 環境差距

Android job 跑在 `macos-15`，Xcode 16.4（Swift 6.1.2）；本機驗證是在 macOS 27，Xcode 27（Swift 6.4）。本機看到的失敗不會自動套用到 CI，反過來也一樣。

| | CI | Local |
| --- | --- | --- |
| Runner / host | macos-15 | macOS 27 |
| Xcode | 16.4 (Swift 6.1.2) | 27 (Swift 6.4) |
| Cross-compile toolchain | swift-6.3-DEVELOPMENT-SNAPSHOT-2026-05-01-a | ...-2026-06-07-a |
| Swift Bundler | `Vendor/swift-bundler` | same submodule |

## 已完成

- [x] 在 android job 的 `env` block 加入 `SCUI_ANDROID: "1"`。沒有它時 package 不再包含 AndroidBackend 或 AndroidBackendShim，因此 examples 無法 link 到 backend。

- [x] Job 會 recursive checkout submodules，並從 `Vendor/` 建 Swift Bundler，而不是重新 clone。這讓 CI 測到此 repository pin 住的 commit。`SWIFT_BUNDLER_REVISION` 已移除；cache key 現在由兩個 Vendor commit 推導。

- [x] `Package.resolved` 不再漂移。Android dependencies 已在 `Package.swift` 無條件宣告，所以不論有沒有 `SCUI_ANDROID`，resolve 都保留同樣 24 個 pin。只有 targets 仍被 gate，這才是避免非 Android build碰到 AndroidBackendShim `<android/log.h>` 的部分。

## 需要在 CI 驗證

- [ ] **Android platform 36 必須可用。** `Examples/Bundler.toml` 裡每個 app 現在都設定 `compile_sdk = 36`，因為 `AndroidBackendHelpers.kt` 呼叫 `TimeZone.getIanaID`（API 36）。`macos-15` runner 預裝 Android SDK 可能沒有 `platforms;android-36`。如果 gradle step 因 `Unresolved reference 'getIanaID'` 失敗，請在 `Build examples` 前加入：

      ```sh
      $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager "platforms;android-36"
      ```

- [ ] **Swift Bundler build。** 它的 `ZIPFoundationModern` dependency 在 Swift 6.3+ 下無法編譯（`data.append(contentsOf: .init(repeating:count:))` 已無法推斷型別；upstream 0.0.9 仍壞）。`Vendor/ZIPFoundationModern` 指向帶有 one-line fix 的 fork，job 現在用 `swift package edit` 注入它。CI 用 Swift 6.1.2 建 bundler，即使未修版也能編譯，所以該 fork 在 CI 上應該無害，但尚未跑過確認。

- [ ] **其餘 examples。** 本機只 bundle 了 CounterExample、WebViewExample、ControlsExample。CI 會建 11 個。其他 8 個只做了相同的 mechanical `Bundler.toml` 編輯，尚未驗證。

## Examples/Package.resolved 仍會漂移

無條件 Android dependencies 修好了 root `Package.resolved`，但沒有修 `Examples/`。那是另一個 package，有自己的 lockfile。若在沒有 `SCUI_ANDROID=1` 的情況下 resolve，仍會 prune 同一批 Android pins：

```text
androidkit, swift-android-native, swift-java, swift-java-jni-core,
swift-subprocess, ...
```

Root package 會保留 24 個 pin，因為 dependencies 在那裡直接宣告。Examples 是透過 `.package(path: "..")` 間接取得，而沒有該環境變數時 graph 內沒有 target 使用它們，所以它們會被移除。

- [ ] 決定 Examples 是否也應該自行宣告 Android dependencies，或 lockfile 是否預期會依 build mode 不同。
- [ ] 在決定前：若在沒有 `SCUI_ANDROID=1` 的情況下於該目錄 build 或 resolve，請之後執行 `git checkout -- Examples/Package.resolved`。這是在該目錄跑 `xcodebuild -list` 時觀察到的。

## 清理事項

- [ ] `SWIFT_RELEASE` 上方註解指向 API level 24 SDK，但 Swift Android SDK 暴露的是 **28**（`aarch64-unknown-linux-android28`）。實際 triple 由 Swift Bundler 選，不是由註解決定，所以這是文件漂移，不是 build failure。

- [ ] 考慮把 android job 移到較新的 Xcode。它和所有 macOS job 一樣 pin 在 16.4，現在已經落後好幾版，也是 CI 與本機 toolchain 分歧的原因。

## 參考

完整本機設定與驗證步驟：
`Scripts/build-tool-install-android-on-Mac.sh`
