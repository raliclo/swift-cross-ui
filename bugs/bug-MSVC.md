# MSVC — defects in the toolchain, met while building this project's dependencies

Measured on Windows unless a line says otherwise. Everything here came from a
run. The subject of this file is the Microsoft C/C++ compiler, not this
repository and not the library being compiled: a claim of mine that turned out
to be false goes in `mistakes.md`, whose subject is me.

本檔的主詞是 Microsoft C/C++ 編譯器,不是本 repository、也不是被編譯的那個函式庫。每一條都來自實際執行。
我說過而後來被證明為假的話,歸 `mistakes.md`——那一份的主詞是我。

---

## 1. `C1060: compiler is out of heap space` on a large generated file, with 19 GB free

**Measured 2026-09-18**, building GTK 4.22.4 for Windows with
`testapp/install_gtk4_accesskit_windows.zsh`:

```
gtk/gtkresources.c(78895): fatal error C1060: compiler is out of heap space
```

The file is GTK's generated resource blob: **7.3 MB, 104,351 lines**, one huge
static initialiser. The compiler was `cl` 19.44.35229, the **64-bit hosted**
x64 compiler (`VC/Tools/MSVC/14.44.35207/bin/HostX64/x64/cl.exe`, which prints
`for x64`). The machine reported **19,252 MB of physical memory available** and
26 GB of virtual memory available at the time.

**The message names a resource the machine had.** That is the whole reason this
is written down: `out of heap space` reads as "the machine is short of memory",
and the obvious response is to close things and try again, which changes
nothing. Three cheaper explanations were tested and none of them was it:

| tried | result |
| --- | --- |
| `CCACHE_DISABLE=1` (the compile goes through ccache) | same failure, same line |
| Compiling the file by hand without `-Zc:preprocessor`, the new preprocessor, which is known to use more memory | same failure |
| `-Doptimization=1` instead of the release default | same failure, at line 78951 instead of 78895 |

**clang-cl 23.1 compiles the same file, with the same flags, in seconds** --
`clang-cl /nologo /c /MD /O1 ... gtk/gtkresources.c` produced a 1.6 MB object.
Both compilers target `x86_64-pc-windows-msvc`, so the ABI is the same one
Swift and the gvsbuild bundle already use, and the build simply switched: the
install script exports `CC=clang-cl`, with the measurement above quoted beside
it.

**What this costs anyone hitting it.** GTK's own MSVC CI builds this file, so
the failure is not universal -- it depends on the size the resource blob reaches
for a given configuration. Anyone building a large generated translation unit
with MSVC can meet it on a machine with memory to spare, and the error text will
send them looking in the wrong place.

**This repository was never exposed to it.** Asked on 2026-09-19 whether
everything should move to clang-cl, the build manifest was read rather than
answered from memory: `.build/release.yaml` for a `-gtk4` app compiles all
eleven `GtkCHelpers` C files with
`Swift/Toolchains/6.3.3+Asserts/usr/bin/clang.exe` and links with the same
toolchain's `lld-link.exe`. There is no `cl.exe` anywhere in it, and the
scratch tools (`touch_gesture`, `uia_tree`, …) are built with `clang` too. The
only place MSVC's `cl` ever entered was the GTK dependency build, and that is
the one this bug moved to clang-cl. Both target `x86_64-pc-windows-msvc`, so
mixing them is the ABI everything here already uses.

**Not filed anywhere.** Reporting it to Microsoft is the user's call, like the
GTK items in `todo-Gtk.md`.

**在機器還有 19 GB 可用記憶體時,MSVC 對一個大型產生檔回報「堆積空間不足」。** 2026-09-18 以
`install_gtk4_accesskit_windows.zsh` 建置 GTK 4.22.4 時量到:`gtk/gtkresources.c` 為 7.3 MB、104,351 行的
單一巨大初始化式,編譯器是 **64 位元主機版** 的 `cl` 19.44.35229,而當下實體記憶體尚有 19,252 MB。

**這個訊息點名了一項機器其實有的資源**,這正是它被記下來的理由:`out of heap space` 讀起來像「機器記憶體不夠」,
於是人們會去關程式再試一次——而那不會改變任何事。三個更便宜的解釋都試過、都不是:停用 ccache、拿掉
`-Zc:preprocessor`、降低最佳化等級,全部以同一個錯誤結束。

**clang-cl 23.1 用同一組旗標在數秒內編完同一個檔**(產出 1.6 MB 的 object),而兩者的目標三元組相同
(`x86_64-pc-windows-msvc`),因此 ABI 與 Swift 及 gvsbuild bundle 所用的一致;建置遂改用它。

GTK 自己的 MSVC CI 編得過這個檔,所以這並非普遍失敗——它取決於特定組態下資源檔會長到多大。任何人在記憶體充裕
的機器上、以 MSVC 編一個大型產生翻譯單元時都可能遇到,而錯誤訊息會把他指向錯的方向。

**本 repository 從未暴露在這個問題下。** 2026-09-19 被問到「是否該全面改用 clang-cl」時,是去讀建置清單而不是
憑印象回答:`-gtk4` app 的 `.build/release.yaml` 以 Swift 工具鏈的 `clang.exe` 編譯 `GtkCHelpers` 的全部 11 個 C 檔,
並以同一份工具鏈的 `lld-link.exe` 連結,整份清單裡沒有任何 `cl.exe`;scratch 小工具同樣用 `clang`。MSVC 的 `cl`
唯一進入過的地方就是 GTK 這個依賴的建置,而那正是本條所改掉的。兩者目標三元組相同,混用即是此處既有的 ABI。

**尚未對外回報。** 是否回報給 Microsoft 由使用者決定,與 `todo-Gtk.md` 中的 GTK 項目相同。
