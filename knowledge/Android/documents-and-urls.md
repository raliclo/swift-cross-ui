# Documents, file dialogs and incoming URLs on Android

Checked 2026-10-24 against commits, todo.md and package_android.zsh.

## Opening a document

The Storage Access Framework returns `content://` URIs, which Foundation on
Android cannot read (`NSURLErrorDomain -1002 "unsupported URL"`). So
`AndroidBackendHelpers.stagingPathForOpen` copies each chosen document through
the ContentResolver into a cache folder of its own, under its display name,
takes the persistable grant when offered, and returns that path (d7ea02c4).

- Types with no Android MIME type are offered, then checked by name
  (9b557a9b).
- A document that cannot be written opens read-only (32985ad1).

## Saving

- Saves go to a staged file; `mirrorBack` writes it to the original with mode
  `"wt"`. The folder is watched for `CLOSE_WRITE` **and** `MOVED_TO`, because
  an atomic write renames a temporary file over the staged one and produces no
  `CLOSE_WRITE` (3cd856a3).
- `saveDocument()` used to report success once the staged file was written,
  while the copy to the document failed later in logcat alone.
  `BackendFeatures.FileWriteBack`: `commitStagedSave` copies synchronously
  under the observer's lock, so the result is the real one (c8a533e8).
- A copy is marked by a SHA-256 of the bytes written (it was length and mtime,
  which could skip a same-length save), and an explicit save always writes.
  Compiled and run 2026-10-22 (P75 "read back: saved by P75").

**Open (todo.md, 2026-10-22):** two saves of equal length within one
millisecond; no action file drives it.

## Incoming URLs

`url_schemes` in Bundler.android.toml (`scui-testapp`) becomes one `VIEW`
intent filter per scheme on `MainActivity`. With `singleTop`, a link while the
app is in front arrives through `onNewIntent` instead of a second activity.
An action file cannot open a URL; P78's pass is
`test_support/p78_send_urls_android.zsh` (launch URL, then one while running:
"received 2", 2026-10-20).

---

# Android 上的文件、檔案對話框與傳入的 URL

2026-10-24 對照 commit、todo.md 與 package_android.zsh 查過。

## 開啟文件

Storage Access Framework 回傳 `content://` URI,而 Android 上的 Foundation 讀不了它(`NSURLErrorDomain -1002 "unsupported URL"`)。
因此 `AndroidBackendHelpers.stagingPathForOpen` 會經 ContentResolver 把每個選到的文件以其顯示名稱複製到專屬的快取資料夾，
有提供時取得永久授權，再回傳該路徑(d7ea02c4)。

- Android 沒有 MIME 類型的檔案類型會先提供，再依檔名檢查(9b557a9b)。
- 無法寫入的文件以唯讀開啟(32985ad1)。

## 存檔

- 存檔先寫到代用檔，再由 `mirrorBack` 以 `"wt"` 模式寫回原檔。資料夾同時監看 `CLOSE_WRITE` **與** `MOVED_TO`,因為原子寫入是把
  暫存檔改名蓋過代用檔，不會產生 `CLOSE_WRITE`(3cd856a3)。
- `saveDocument()` 原本在代用檔寫好時就回報成功，而複製到文件的動作稍後才在 logcat 裡失敗。`BackendFeatures.FileWriteBack`:
  `commitStagedSave` 在 observer 的鎖內同步複製，所以結果是真的(c8a533e8)。
- 複製以寫入位元組的 SHA-256 標記(原本是長度與修改時間，可能略過長度相同的存檔),明確存檔一律寫入。2026-10-22 已編譯並執行
  (P75「read back: saved by P75」)。

**未解決(todo.md,2026-10-22):** 同一毫秒內兩次長度相同的存檔；沒有動作檔能驅動。

## 傳入的 URL

Bundler.android.toml 的 `url_schemes`(`scui-testapp`)會在 `MainActivity` 上變成每個 scheme 一個 `VIEW` intent filter。
有了 `singleTop`,app 在前景時收到的連結經由 `onNewIntent` 送達，而不是再開第二個 activity。動作檔無法開啟 URL;P78 的通過條件
由 `test_support/p78_send_urls_android.zsh` 判定(先以 URL 啟動，執行中再送一個:「received 2」,2026-10-20)。
