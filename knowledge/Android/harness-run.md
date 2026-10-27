# How the harness runs an app on Android

testapp/test_android.zsh, reached as `zsh testapp/test.zsh Pn --android`.
Checked against the script on 2026-10-24. Building and packaging are in
build-and-packaging.md; booting the emulator in emulator-avds.md.

## Options

`--no-build`, `--actionfile [FILE]` (with no file, the one
`actions/android/Pn-*.actions` there is; more than one is an error),
`--showtime N`, `--no-showtime`, `--device AVD|serial`, `--debug-build`.
`-noApk` and `-replay` remain as aliases.

## Arguments reach the app through an intent extra

An Android app has no argv and no environment. test_android.zsh pushes the
action file to `/data/local/tmp/<Pn>.actions` (adb can write there without
root, the app can read it, and the path has no space) and launches with
`am start -W -n <pkg>/dev.swiftcrossui.testapp.MainActivity --es scui_args "..."`.
AndroidBackend+Arguments.swift builds `CommandLine.arguments` from that extra
before `main`.

- The extra is split on whitespace, so a value with spaces must be encoded
  (P38's `-url data:...` page is percent-encoded).
- It is quoted twice: `adb shell` joins its words and the device's shell parses
  them again. Unquoted, `am` read `-actionfile` as `-a ctionfile` and set the
  intent's action (2026-09-30).
- A file's `# launch-args:` line and `TEST_APP_ARGS` are appended, as on macOS
  and iOS.
- Anything a desktop app reads from the environment must come as an argument
  here: `SCUI_UPDATE_STATS=1` is passed as one; P92 and P93 read
  `--p92-menu` / `--p93-menu`.
- `<file>.aims` is pushed only when re-aiming is asked for and removed
  otherwise, because `/data/local/tmp` outlives the run (reaim-action-files.md).

## Captures

- Taken with `adb exec-out screencap -p`: the device framebuffer, not the
  emulator window, and no Screen Recording permission needed. Saved as
  `testapp/output/screenshots/<label>-<timestamp>.png` like every platform.
- The file is checked for content, because the shell redirect creates it even
  when nothing arrived; an all-black frame (16 x 16 sample via sips, a pixel
  counts when two bytes exceed 8, since Material dark is #121212) is reported
  and counted. A failed capture is evidence missing, never the assertion.
- The first capture waits **5 s**, not 1 s: a cold start brings up the JVM,
  loads libswiftCore, Foundation and ICU and runs the entrypoint through JNI;
  a 1 s capture once photographed the splash screen (2026-09-05). The file name
  keeps `-1s-` so history stays comparable.
- With an action file the final capture waits for `-actionfile: replayed`
  (or `failed:`) in logcat, up to 60 s, plus 1 s for the last redraw.

## Crash check

`am start -W` returns once the activity exists, so an app that dies a moment
later still "launched" and the captures show whatever was behind it (P15-DARK,
`UnsatisfiedLinkError`, 2026-10-01). The script reads logcat since the launch
time for a Java `FATAL EXCEPTION` or a native crash naming the package. It
does not judge by the front activity, because some files leave the app on
purpose (P38's browser, P75's file manager).

## Logs

The app's `print` goes to logcat under the tag `Swift`
(`adb logcat -d | grep '\[Pn\]'`). The replay's own lines start
`-actionfile:`.

## Other Android scripts

- `sweep_android.zsh`: every action file, one row per file in
  `testapp/output/android-sweep.csv2`; uninstalls each app afterwards and
  retries emulator failures once, recording the retry.
- `verify_replay_android.zsh`: did each file replay at all (`-actionfile:
  replayed` count). Necessary, not sufficient: a run once logged it while the
  screen read "last action -> nothing yet".
- `verify_effect_android.zsh`: launches each app plain and with its file, same
  wait, and compares the two captures; a difference is the file's effect.
- `test_rootscroll_android.zsh`: the root mode button's three states (debug
  shown, release hidden, release with `-allow-rootscroll` shown).
- `test_support/p78_send_urls_android.zsh`: P78's pass condition (a launch URL,
  then one through `onNewIntent`).
- `test_support/android_log_tts/build.zsh [--install]`: a text-to-speech
  engine that speaks nothing and logs every utterance, so
  `adb logcat -s SCUI-TTS` is a transcript of TalkBack. Built with javac, d8,
  aapt2 and apksigner, no Gradle; minimum API 31 (6012fedd).

Results go to `matrix_coverage/results.csv2` (platform `android`, backend
`default`); the `device` column names the AVD since f1f8fbb0 (2026-10-22).

---

# harness 如何在 Android 上執行 app

testapp/test_android.zsh,以 `zsh testapp/test.zsh Pn --android` 呼叫。2026-10-24 對照腳本查過。建置與打包見
build-and-packaging.md;模擬器開機見 emulator-avds.md。

## 選項

`--no-build`、`--actionfile [FILE]`(不給檔案時，用唯一的那個 `actions/android/Pn-*.actions`;多於一個就報錯)、
`--showtime N`、`--no-showtime`、`--device AVD|serial`、`--debug-build`。`-noApk` 與 `-replay` 仍保留為別名。

## 參數經由 intent extra 送進 app

Android app 沒有 argv,也沒有環境變數。test_android.zsh 把動作檔推到 `/data/local/tmp/<Pn>.actions`(adb 不需 root 就能
寫入,app 讀得到，路徑沒有空白),並以 `am start -W -n <pkg>/dev.swiftcrossui.testapp.MainActivity --es scui_args "..."`
啟動。AndroidBackend+Arguments.swift 在 `main` 之前由這個 extra 建出 `CommandLine.arguments`。

- extra 以空白切開，所以含空白的值必須編碼(P38 的 `-url data:...` 頁面以百分比編碼)。
- 要加兩層引號:`adb shell` 會把字詞接起來，裝置上的 shell 再解析一次。沒加時,`am` 把 `-actionfile` 讀成 `-a ctionfile`,
  設定了 intent 的 action(2026-09-30)。
- 動作檔的 `# launch-args:` 行與 `TEST_APP_ARGS` 會附加上去，與 macOS、iOS 相同。
- 桌面 app 從環境變數讀的東西，在這裡都必須改成參數:`SCUI_UPDATE_STATS=1` 以參數傳入;P92 與 P93 讀
  `--p92-menu` / `--p93-menu`。
- `<file>.aims` 只在要求重新瞄準時才推上去，否則刪除，因為 `/data/local/tmp` 會留到下一次執行(reaim-action-files.md)。

## 擷圖

- 以 `adb exec-out screencap -p` 擷取：裝置的 framebuffer,不是模擬器視窗，也不需要螢幕錄製權限。與其他平台一樣存為
  `testapp/output/screenshots/<label>-<timestamp>.png`。
- 會檢查檔案有沒有內容，因為 shell 重導向即使沒收到任何位元組也會建立檔案；全黑的畫面(以 sips 取 16 x 16 樣本，兩個位元組
  超過 8 才算，因為 Material 深色是 #121212)會被回報並計數。擷圖失敗代表缺少證據，絕不是斷言本身。
- 第一張擷圖等 **5 秒**,不是 1 秒：冷啟動要拉起 JVM、載入 libswiftCore、Foundation 與 ICU,並經 JNI 執行進入點;1 秒的
  擷圖曾拍到啟動畫面(2026-09-05)。檔名仍保留 `-1s-`,讓歷史紀錄可以比較。
- 有動作檔時，最後一張擷圖會等 logcat 出現 `-actionfile: replayed`(或 `failed:`),最多 60 秒，再多等 1 秒讓最後一次重繪上螢幕。

## 當機檢查

`am start -W` 在 activity 建立後就返回，所以片刻後才死掉的 app 仍算「已啟動」,擷圖拍到的是它後方的東西(P15-DARK,
`UnsatisfiedLinkError`,2026-10-01)。腳本會讀取啟動時間之後的 logcat,找出點名這個套件的 Java `FATAL EXCEPTION` 或原生當機。
它不以前景 activity 判斷，因為有些動作檔會刻意離開 app(P38 的瀏覽器、P75 的檔案管理員)。

## 紀錄

app 的 `print` 以 `Swift` tag 進入 logcat(`adb logcat -d | grep '\[Pn\]'`)。重播自己的訊息以 `-actionfile:` 開頭。

## 其他 Android 腳本

- `sweep_android.zsh`:跑每一個動作檔，每個檔案一列，寫入 `testapp/output/android-sweep.csv2`;之後解除安裝每支 app,模擬器
  失敗會重試一次並記錄。
- `verify_replay_android.zsh`:每個檔案到底有沒有重播(`-actionfile: replayed` 的筆數)。必要但不充分：曾有一次記錄了這行，
  而畫面上仍是「last action -> nothing yet」。
- `verify_effect_android.zsh`:每支 app 各啟動一次純啟動、一次帶動作檔，等待時間相同，比較兩張擷圖；差異就是動作檔的效果。
- `test_rootscroll_android.zsh`:根模式按鈕的三種狀態(debug 顯示、release 隱藏、release 加 `-allow-rootscroll` 顯示)。
- `test_support/p78_send_urls_android.zsh`:P78 的通過條件(一個啟動 URL,再一個經 `onNewIntent`)。
- `test_support/android_log_tts/build.zsh [--install]`:一個什麼都不唸、記下每段朗讀的文字轉語音引擎，讓
  `adb logcat -s SCUI-TTS` 成為 TalkBack 的逐字稿。以 javac、d8、aapt2、apksigner 建置，不用 Gradle;最低 API 31(6012fedd)。

結果寫入 `matrix_coverage/results.csv2`(platform `android`、backend `default`);自 f1f8fbb0(2026-10-22)起 `device` 欄記錄 AVD 名稱。
