# Platform costs that decide a design

Numbers that rule a shape of solution in or out, with the command that produced
each one beside it. Measured on this machine — re-run them rather than quoting
them, because a number nobody can re-derive is guaranteed to be wrong later and
the next reader will not know it.

決定某種解法可不可行的成本數字，每一個數字旁邊都附上產生它的指令。以本機實測——請重新執行而非直接
引用，因為一個沒有人能重新推導的數字，日後必定會是錯的，而下一位讀者不會知道。

---

## Creating a process costs 20–100× more on Windows than on Linux

Measured 2026-08-27.

| | Windows | WSL / Linux |
|---|---|---|
| minimal process | `cmd.exe /c exit` — **43,050 µs** | `/bin/true` — **2,020 µs** |
| a real tool | `tasklist //FI …` — **194,550 µs** | `xdotool getactivewindow` — **3,900 µs** |

`tasklist`'s extra ~150 ms is its own work enumerating every process, so the bare
spawn overhead on Windows is about 43 ms. `xdotool`'s extra ~1.9 ms includes
connecting to the X server.

```zsh
# Windows, from the repo root
s=$(date +%s%N); for i in $(seq 30); do MSYS2_ARG_CONV_EXCL='*' cmd.exe /c exit >/dev/null 2>&1; done
e=$(date +%s%N); printf '%s us\n' "$(( (e-s)/30/1000 ))"

# WSL
for i in $(seq 30); do DISPLAY=:0 xdotool getactivewindow >/dev/null 2>&1; done
```

### This is not a defect, and that is why it matters

Nothing here can be fixed. It is a property of `CreateProcess` against
`fork`/`exec`, and it is recorded because it **rules out a design**: calling an
external tool once per datum is viable on Linux and is not on Windows.

A 20-action replay costs roughly 80 ms of spawn on Linux and 0.9 s on Windows,
where the `sleep` timings an action file specifies would be swamped by overhead
it never asked for.

The project already gets this right, without anyone having measured it.
`Win32Synthesiser` uses `SendInput` in-process and spawns nothing.
`XdotoolSynthesiser` spawns one `xdotool` per invocation across 12 call sites —
a single click can be one to three spawns — and at 4 ms each that is fine.

### A refuted hypothesis, kept because it is the intuitive one

"Spawning from a GUI process is slow because the app's address space is large,
and `fork` has to copy its page tables." Plausible, and wrong. A C probe
spawning before and after touching 200 MB in the same process:

```
small process        fork+exec 0.88 ms    posix_spawn 0.68 ms
after touching 200MB fork+exec 0.76 ms    posix_spawn 0.71 ms
```

No growth. Linux does not copy page tables eagerly, so parent size is not the
mechanism — Windows process creation is simply expensive. The probe is at
`/home/lowei/spawnprobe/spawncost.c` on WSL:
`cc -O2 -o spawncost spawncost.c && ./spawncost 60 200`.

### Where it is worth acting on

- `testapp/ui-lock.zsh` runs `tasklist` on every acquire attempt and every
  status call, at ~195 ms. Fine at the rate it is called, but it is by far the
  most expensive thing that script does, and replacing that check with
  `SendInput`'s return value would make it cheaper *and* more correct — the
  process it looks for is only a proxy for the thing being gated.
- `test_support/test_common.zsh`'s `kill_existing` runs on every test. Worth
  counting how many Windows processes it spawns per run.

---

## 在 Windows 上建立行程比 Linux 貴 20–100 倍

實測於 2026-08-27。

| | Windows | WSL / Linux |
|---|---|---|
| 最小行程 | `cmd.exe /c exit` — **43,050 µs** | `/bin/true` — **2,020 µs** |
| 實際工具 | `tasklist //FI …` — **194,550 µs** | `xdotool getactivewindow` — **3,900 µs** |

`tasklist` 多出的約 150 ms 是它自己列舉所有行程的工作，因此 Windows 上純粹的 spawn 開銷約為 43 ms。
`xdotool` 多出的約 1.9 ms 則包含連上 X server。

### 這不是缺陷，而這正是它重要的原因

此處沒有任何東西可以修。它是 `CreateProcess` 相對於 `fork`/`exec` 的特性；記錄它，是因為它
**排除了一種設計**：「每筆資料呼叫一次外部工具」在 Linux 可行，在 Windows 不可行。

一份含 20 個動作的重放，在 Linux 上約付出 80 ms 的行程建立成本，在 Windows 上則約 0.9 秒——而動作檔
所指定的 `sleep` 時序，會被它從未要求過的開銷完全淹沒。

本專案在無人量測過的情況下已經做對了：`Win32Synthesiser` 於行程內使用 `SendInput`，完全不 spawn；
`XdotoolSynthesiser` 在 12 個呼叫點上每次呼叫 spawn 一個 `xdotool`——單次點擊可能是一到三次
spawn——而每次 4 ms 是可以接受的。

### 一個被推翻的假設，因其符合直覺而保留

「從 GUI 行程 spawn 之所以慢，是因為 app 的位址空間很大，`fork` 必須複製其頁表。」看似合理，實則錯誤。
以 C 探針在同一行程中、於觸碰 200 MB 前後各測一次：

```
small process        fork+exec 0.88 ms    posix_spawn 0.68 ms
after touching 200MB fork+exec 0.76 ms    posix_spawn 0.71 ms
```

毫無成長。Linux 不會急切地複製頁表，因此父行程大小並非成因——單純就是 Windows 的行程建立昂貴。
探針位於 WSL 的 `/home/lowei/spawnprobe/spawncost.c`：
`cc -O2 -o spawncost spawncost.c && ./spawncost 60 200`。

### 值得據此採取行動之處

- `testapp/ui-lock.zsh` 在每次 acquire 嘗試與每次 status 呼叫時執行 `tasklist`，約 195 ms。以目前的
  呼叫頻率尚可接受，但它是該腳本中最昂貴的動作；改以 `SendInput` 的回傳值取代該檢查，會同時更便宜
  **且**更正確——它所尋找的那個行程，只是被把關之事的代理指標。
- `test_support/test_common.zsh` 的 `kill_existing` 於每次測試執行。值得統計它每輪會 spawn 多少個
  Windows 行程。
