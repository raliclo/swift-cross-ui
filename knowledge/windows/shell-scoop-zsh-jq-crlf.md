# The shell on Windows: scoop's zsh, MSYS paths, and jq.exe's CRLF

Written 2026-10-24 from testapp/test_support/pairs_deck/build_gtk_deck.zsh,
testapp/install_gtk4_windows.zsh, testapp/enable_input.ps1, testapp/ui-lock.zsh,
testapp/P0-P26-windows-findings.md, commit 1e2ae4b0 (2026-10-22).

## What

- zsh comes from **scoop** (`C:\Users\<user>\scoop\shims\zsh.exe`), and so does
  Git. The two map `/` and `/tmp` to different roots; write shared temporary
  files to a Windows path (e.g. `C:/gtk4-download`), not `/tmp`.
- Under the scoop zsh shim started from Git Bash, `$PPID` is 1. ui-lock records
  a holder pid only when it is a real process.
- `jq.exe` is the winget package **jqlang.jq 1.8.2** (not scoop). **It ends every
  line with CRLF.** In `build_gtk_deck.zsh` every image path kept a CR and all
  116 slides read "no screenshot", with rc 0. Fix: `| tr -d '\r'` (1e2ae4b0).
  `build_deck.zsh` does not strip CRs yet; it is run on the Mac.
- Other native tools also emit CRLF: `reg.exe`, `pnputil`, `fsutil`,
  `swift build --show-bin-path`, `cat` through `wsl.exe`. Their output goes
  through `tr -d '\r'` in compile.zsh, gpu_select.zsh, check_wsl_host.zsh and
  test_common.zsh.
- Python's csv writer emits CRLF; CSVs here are LF and written with csv2.

## MSYS argument and path conversion

- MSYS rewrites arguments that look like paths. `MSYS2_ARG_CONV_EXCL='*'` turns
  that off; `//FI` is the other workaround. **They cancel each other:** with the
  exclusion set, `tasklist //FI` received a literal `//FI`, printed an error on
  stderr and nothing on stdout, and `ui-lock.zsh` reported a locked workstation
  as unlocked for an hour (2026-08-26). Use one or the other.
- Paths handed to a native exe go through `cygpath -m`; PATH entries through
  `cygpath -u`. A Windows-form `C:/...` on PATH is split at the colon.
- A `$` in a command sent through `wsl.exe` is eaten; expand values on the
  Windows side first.
- `enable_input.ps1` must stay ASCII: PowerShell 5.1 reads a BOM-less file as
  ANSI, and Chinese bytes broke the parser.
- `tasklist /v` took 52-55 s for 412 rows (2026-08-27); plain `tasklist` about
  0.2 s. Do not call `/v` per capture.

## How to apply

Pipe every native tool's text output through `tr -d '\r'` before comparing or
using it as a path. A trailing CR fails silently: the path "does not exist",
the string "does not match", and the script exits 0.

---

# Windows 上的 shell:scoop 的 zsh、MSYS 路徑與 jq.exe 的 CRLF

2026-10-24 依 testapp/test_support/pairs_deck/build_gtk_deck.zsh、testapp/install_gtk4_windows.zsh、
testapp/enable_input.ps1、testapp/ui-lock.zsh、testapp/P0-P26-windows-findings.md、1e2ae4b0(2026-10-22)寫成。

## 內容

- zsh 取自 **scoop**(`C:\Users\<user>\scoop\shims\zsh.exe`),Git 也是。兩者把 `/` 與 `/tmp` 對應到不同的根；共用的
  暫存檔請寫到 Windows 路徑(例如 `C:/gtk4-download`),不要寫 `/tmp`。
- 從 Git Bash 啟動 scoop 的 zsh shim 時,`$PPID` 是 1。ui-lock 只在持有者 pid 是真正的行程時才記錄。
- `jq.exe` 是 winget 套件 **jqlang.jq 1.8.2**(不是 scoop)。**它每行都以 CRLF 結尾。** 在 `build_gtk_deck.zsh`
  中每條影像路徑都帶著 CR,116 張投影片全部顯示「no screenshot」,而 rc 為 0。修正:`| tr -d '\r'`(1e2ae4b0)。
  `build_deck.zsh` 尚未去除 CR;它在 Mac 上執行。
- 其他原生工具也輸出 CRLF:`reg.exe`、`pnputil`、`fsutil`、`swift build --show-bin-path`、經 `wsl.exe` 的 `cat`。
  它們的輸出在 compile.zsh、gpu_select.zsh、check_wsl_host.zsh 與 test_common.zsh 中都經過 `tr -d '\r'`。
- Python 的 csv writer 輸出 CRLF;這裡的 CSV 都是 LF,並以 csv2 寫入。

## MSYS 的引數與路徑轉換

- MSYS 會改寫看起來像路徑的引數。`MSYS2_ARG_CONV_EXCL='*'` 關閉轉換;`//FI` 是另一種解法。**兩者會互相抵銷：**
  設了排除變數時,`tasklist //FI` 收到字面上的 `//FI`,在 stderr 印出錯誤、stdout 空無一物，於是 `ui-lock.zsh`
  把鎖定的工作站回報為未鎖定長達一小時(2026-08-26)。兩者擇一。
- 交給原生 exe 的路徑經 `cygpath -m`;PATH 項目經 `cygpath -u`。PATH 中 Windows 形式的 `C:/...` 會在冒號處被切開。
- 經 `wsl.exe` 送出的命令中的 `$` 會被吃掉；先在 Windows 這一側展開。
- `enable_input.ps1` 必須維持純 ASCII:PowerShell 5.1 把沒有 BOM 的檔案當 ANSI 讀，中文位元組弄壞了解析器。
- `tasklist /v` 412 列要 52–55 秒(2026-08-27);一般的 `tasklist` 約 0.2 秒。不要每次擷取都呼叫 `/v`。

## 如何運用

所有原生工具的文字輸出，在比對或當成路徑使用之前，先經過 `tr -d '\r'`。結尾的 CR 會靜默失敗：路徑「不存在」、
字串「不相符」,而腳本以 0 結束。
