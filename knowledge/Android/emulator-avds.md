# The Android emulator and its AVDs

Checked 2026-10-24 against ~/.android/avd, install_tools_android.zsh and
test_android.zsh.

## The two AVDs

| AVD | Device | Screen | Density | Width |
|---|---|---|---|---|
| `swift-cross-ui-api36b` | pixel_6 | 1080 x 2400 | 420 dpi (2.625) | 411 dp |
| `swift-cross-ui-tablet36` | pixel_tablet | 2560 x 1600 | 320 dpi (2.0) | 1280 dp |

Both use `android-36;google_apis;arm64-v8a`. install_tools_android.zsh creates
only api36b (`ANDROID_AVD_NAME` overrides the name). tablet36 was created by
hand on the M4 Mac on 2026-10-20; its config.ini still says `hw.gpu.mode=auto`,
which test_android.zsh overrides at boot. `--device <AVD or serial>` picks one.
The google_apis image is userdebug, so `adb root` works (profiling.md).

## Storage

Each AVD's data lives on the project volume,
`/Volumes/Windows/proj_Win/.android-avd/<name>.avd`, named by `path=` in
`~/.android/avd/<name>.ini`. The qcow2 overlay grows with every APK install
(10 GB data partition) and filled the system disk mid-sweep (2026-10-02). If
that volume is not mounted, test_android.zsh says so instead of letting the
boot fail. An AVD whose data went bad when the volume dropped was replaced by
api36b on 2026-10-04.

## How the harness boots it

```
emulator -avd <name> -no-snapshot -no-boot-anim -no-metrics -crash-report-mode never -gpu host
```

- `-no-metrics` and `-crash-report-mode never`: without them the emulator can
  log "Showing crashdialog to get consent." and wait for a click a headless run
  never gives; adb never sees it, and the failure reads like a slow boot
  (2026-09-05, again 2026-10-14 after an emulator was killed).
- `-gpu host`, and checked: the renderer is read from SurfaceFlinger after
  boot. On the M4 the host GPU reads "OpenGL ES Translator (Apple M4) ...
  Metal". SwiftShader, llvmpipe or lavapipe make test_android.zsh restart that
  AVD on the host GPU, and stop if it still cannot get one. Left on `auto` the
  emulator chose software GL under memory pressure; timings and animation
  captures from software GL are not comparable (52b9f2f2).
- A running emulator is reused; a second instance on the same AVD can win the
  AVD lock with the wrong flags.
- `ADB_LIBUSB=1`: on macOS 27 the legacy IOKit USB backend can block adb's
  server start.
- `settings put secure stylus_handwriting_enabled 0`: otherwise Gboard answers
  a synthesised tap in a text field with a full-screen "Try out your stylus"
  sheet (seven captures of the 2026-10-02 sweep).

## Quirks that look like app defects

- **Emulator state changes results.** Right after a cold boot the emulator can
  restart its userspace, which reads as "crashed after launch". The first
  launch after a cold boot froze P96's dots with the frame clock stopped
  (2026-10-22); a run late in a cold-boot chain gave P106 CYCLE 3 instead of 7.
  The 2.7 s first-frame stall of 2026-10-23 was seen only on an emulator that
  had run 40 apps (profiling.md). Retry on a warm, fresh emulator before
  calling a regression.
- **Long runs wedge it**: "Failure calling service package: Broken pipe",
  "Can't find service: activity", and a "Pixel Launcher isn't responding"
  dialog that dimmed a capture, all after a dozen ~110 MB APKs and their
  processes were left on the device (2026-09-05). sweep_android.zsh therefore
  force-stops and uninstalls each app and clears logcat before each launch.
- **The vCPU is sometimes not scheduled**: simpleperf showed 28 ms and 57.9 ms
  windows with no sample at all inside measured updates (2026-10-05).
- **No pointer device**: `dumpsys input` lists only `gpio-keys` and
  `virtio_input_multi_touch`, so no mouse cursor is ever drawn or captured.
- **The renderer string's length moves the layout** of apps that print it:
  api36b's is three lines rather than five, which moved P72's controls about
  62 pt and made its action file miss (2026-10-05).
- **Coordinates are per AVD.** A file measured on the phone misses on the
  tablet and the reverse (P60, P17's button file, 2026-10-21/22). On the
  tablet a split-screen window starts at x 1290 px. Prefer `taplabel`.
- The system long-press timeout is 400 ms by default and follows the
  Accessibility touch-and-hold delay.

---

# Android 模擬器與 AVD

2026-10-24 對照 ~/.android/avd、install_tools_android.zsh 與 test_android.zsh 查過。

## 兩個 AVD

| AVD | 裝置 | 螢幕 | 密度 | 寬度 |
|---|---|---|---|---|
| `swift-cross-ui-api36b` | pixel_6 | 1080 x 2400 | 420 dpi(2.625) | 411 dp |
| `swift-cross-ui-tablet36` | pixel_tablet | 2560 x 1600 | 320 dpi(2.0) | 1280 dp |

兩者都用 `android-36;google_apis;arm64-v8a`。install_tools_android.zsh 只建立 api36b(名稱可用 `ANDROID_AVD_NAME` 覆寫)。
tablet36 是 2026-10-20 在 M4 Mac 上手動建立的；它的 config.ini 仍寫 `hw.gpu.mode=auto`,由 test_android.zsh 在開機時覆寫。
`--device <AVD 或 serial>` 指定要用哪一台。google_apis 映像是 userdebug,所以 `adb root` 可用(profiling.md)。

## 儲存位置

每個 AVD 的資料放在專案磁碟區 `/Volumes/Windows/proj_Win/.android-avd/<name>.avd`,由 `~/.android/avd/<name>.ini`
的 `path=` 指定。qcow2 overlay 會隨每次安裝 APK 變大(資料分割區 10 GB),曾在掃描途中塞滿系統磁碟(2026-10-02)。
該磁碟區沒有掛載時,test_android.zsh 會直接說明，而不是讓開機失敗。一個在磁碟區掉線時資料損壞的 AVD,已於 2026-10-04
由 api36b 取代。

## harness 如何開機

```
emulator -avd <name> -no-snapshot -no-boot-anim -no-metrics -crash-report-mode never -gpu host
```

- `-no-metrics` 與 `-crash-report-mode never`:少了它們，模擬器可能記錄「Showing crashdialog to get consent.」,然後等一次
  無人值守的執行永遠不會給的點擊;adb 看不到它，失敗訊息讀起來像開機太慢(2026-09-05,模擬器被砍掉後的 2026-10-14 又一次)。
- `-gpu host`,而且會檢查：開機後從 SurfaceFlinger 讀取 renderer。在 M4 上，主機 GPU 讀作「OpenGL ES Translator
  (Apple M4) ... Metal」。若是 SwiftShader、llvmpipe 或 lavapipe,test_android.zsh 會讓該 AVD 改以主機 GPU 重開，仍拿不到
  就停下。留給 `auto` 時，模擬器在記憶體吃緊時挑過軟體 GL;軟體 GL 的計時與動畫擷圖無法比較(52b9f2f2)。
- 已在執行的模擬器會被重用；同一個 AVD 的第二個實例可能帶著錯誤的旗標搶到 AVD 鎖。
- `ADB_LIBUSB=1`:macOS 27 上舊版 IOKit USB backend 可能讓 adb server 卡住。
- `settings put secure stylus_handwriting_enabled 0`:否則 Gboard 會對文字欄位上的合成點擊跳出全螢幕的「Try out your
  stylus」(2026-10-02 掃描中有七張擷圖拍到它)。

## 看起來像 app 缺陷的怪癖

- **模擬器的狀態會改變結果。** 冷開機後模擬器可能重啟 userspace,讀起來像「啟動後當掉」。冷開機後第一次啟動曾讓 P96 的圓點
  凍住、frame clock 停止(2026-10-22);一連串冷開機執行的後段,P106 的 CYCLE 讀到 3 而不是 7。2026-10-23 那段 2.7 秒的第一幀
  卡頓，只出現在跑過 40 支 app 的模擬器上(profiling.md)。判定退化之前，先在暖機、重開過的模擬器上重試。
- **長時間執行會讓它卡死**:「Failure calling service package: Broken pipe」、「Can't find service: activity」,以及一個讓擷圖
  變暗的「Pixel Launcher isn't responding」對話框，都發生在裝置上留了十幾個約 110 MB 的 APK 與其程序之後(2026-09-05)。
  因此 sweep_android.zsh 每支 app 結束後都 force-stop 並解除安裝，每次啟動前清空 logcat。
- **vCPU 有時沒被排程**:simpleperf 在量測的更新中看到 28 ms 與 57.9 ms 完全沒有取樣的區段(2026-10-05)。
- **沒有指標裝置**:`dumpsys input` 只列出 `gpio-keys` 與 `virtio_input_multi_touch`,所以滑鼠游標永遠不會被畫出或擷取。
- **renderer 字串的長度會移動版面**(對會把它印出來的 app):api36b 的是三行而不是五行，讓 P72 的控制項移動約 62 pt,
  動作檔因此點不中(2026-10-05)。
- **座標依 AVD 而定。** 在手機上量的檔案在平板上點不中，反之亦然(P60、P17 的按鈕檔,2026-10-21/22)。平板上分割畫面的
  視窗從 x 1290 px 開始。請優先使用 `taplabel`。
- 系統的長按逾時預設 400 ms,並跟隨「協助工具」的觸控並按住延遲設定。
