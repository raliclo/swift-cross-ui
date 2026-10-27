# Knowledge

What has been learned about each platform the tests run on: quirks and their
workarounds, how the harness works there, toolchain setup, performance
findings, root causes that could come back, and what is still open. Each
platform has an index file and a folder with one topic per file, English first
and then zh-TW.

| Platform | Index | Backends |
|---|---|---|
| WSL | [WSL.md](WSL.md) | GtkBackend under WSLg (Linux GTK 4 in WSL2 on the Windows machine) |
| Windows | [windows.md](windows.md) | WinUIBackend, and GtkBackend on native Windows |
| macOS | [macOS.md](macOS.md) | AppKitBackend, and GtkBackend on macOS |
| iOS | [iOS.md](iOS.md) | UIKitBackend on the iPhone and iPad simulators |
| Android | [Android.md](Android.md) | AndroidBackend on the Android emulator |

Rules for adding to it:

- One topic per file in the platform's folder, linked from its index with a
  one-line summary.
- State facts and reasons; cite the evidence (file paths, commits,
  `matrix_coverage/results.csv2` rows, dates). Mark open items with the date
  they were last checked.
- When a finding is superseded, update the topic rather than appending its
  history.
- No personal names; the Windows home directory is written `<user>`.

---

# 知識

各個測試平台上學到的東西：平台怪癖與對應做法、測試工具在該平台的運作方式、工具鏈設定、效能發現、可能再發生的根本原因，
以及仍未解決的問題。每個平台有一個索引檔與一個資料夾，每個檔案一個主題，先英文後 zh-TW。

| 平台 | 索引 | backend |
|---|---|---|
| WSL | [WSL.md](WSL.md) | WSLg 下的 GtkBackend(Windows 機器上 WSL2 內的 Linux GTK 4) |
| Windows | [windows.md](windows.md) | WinUIBackend,以及原生 Windows 上的 GtkBackend |
| macOS | [macOS.md](macOS.md) | AppKitBackend,以及 macOS 上的 GtkBackend |
| iOS | [iOS.md](iOS.md) | iPhone 與 iPad 模擬器上的 UIKitBackend |
| Android | [Android.md](Android.md) | Android 模擬器上的 AndroidBackend |

新增時的規則：

- 每個主題一個檔案，放在該平台的資料夾，並在索引中以一行摘要連結。
- 陳述事實與理由，並附證據(檔案路徑、commit、`matrix_coverage/results.csv2` 的列、日期)。未解項目註明最後檢查的日期。
- 發現被推翻時，更新該主題，而不是在後面附加經過。
- 不寫個人姓名;Windows 的家目錄寫成 `<user>`。
