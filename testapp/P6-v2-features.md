# P6-v2 features

What P6-v2 adds, why each thing exists, and what it is not. Written alongside
the code rather than after it, because several of these were added to replace an
earlier answer that was wrong, and the wrong answer is the part worth recording.

P6-v2 的功能、每一項存在的理由，以及它們不是什麼。與程式碼同步撰寫而非事後補寫，因為其中數項
是為了取代先前的錯誤答案而加入，而那些錯誤答案本身才是值得記錄的部分。

## What P6-v2 is

The GTK counterpart to P6, for comparing GtkBackend against WinUIBackend on the
same questions with the same numbers.

P6 itself is untouched and is not portable: it is the WinUI/D3D11
implementation, and `compile.zsh -gtk4` refuses to build it because a
SwapChainPanel and a D3D11 composition swap chain have no GtkBackend
equivalent. P6-v2 was written fresh rather than copied — roughly 2700 of P6's
3990 lines are the D3D11 measurement apparatus, the macOS Metal and CoreVideo
paths, and stream fetching, none of which a backend comparison needs.

P6 的 GTK 對應版本，用於在相同問題、相同數字下比較 GtkBackend 與 WinUIBackend。

P6 本身完全未動，且不可移植：它是 WinUI/D3D11 的實作，而 `compile.zsh -gtk4` 會拒絕建置它，
因為 SwapChainPanel 與 D3D11 composition swap chain 在 GtkBackend 中沒有對應物。P6-v2 採全新
撰寫而非複製——P6 的 3990 行中約有 2700 行是 D3D11 量測設施、macOS 的 Metal 與 CoreVideo
路徑，以及串流取得，這些都不是 backend 比較所需要的。

## NV12 over the pipe, converted in a shader

The single change that mattered for throughput.

**The problem was transport, not drawing.** At 1080p60 an RGBA frame is 7.91 MB
and needs 475 MB/s through the decoder pipe. The pipe measures 247–416 MB/s. So
playback sat at 30–43 fps and hardware decode bought nothing: 43.5 fps software
against 42.3 with `d3d11va`, within noise of each other.

NV12 carries the same picture in 12 bits per pixel instead of 32 — 2.97 MB per
frame, 178 MB/s. Converting it back to RGB on the CPU would hand the saving
straight back, and there is no `GdkMemoryTexture` format for NV12, so the
conversion moved to the GPU:

- `Sources/GtkCHelpers/gtk_nv12_gl.c` — luma as `GL_R8`, chroma as `GL_RG8`, a
  BT.709 limited-range fragment shader, `glTexSubImage2D` on resident textures
- `Sources/Gtk/Widgets/NV12GLView.swift` — a `GtkGLArea` subclass wrapping it

| | RGBA + memory texture | NV12 + GL |
|---|---|---|
| average fps | 23.1–43.5 | **51.9**, peaks at 61 |
| average read | 19.5–32.4 ms | **8.55 ms** |

The 2.7x drop matches the byte arithmetic; it was predicted before it was
measured.

**This is not zero-copy.** Frames still cross CPU memory through the ffmpeg
pipe. True zero-copy needs in-process decode plus
`glImportMemoryWin32HandleEXT`; `external-objects-win32` is confirmed present on
this machine for whenever that is attempted.

單一一項對吞吐量真正有影響的改動。

**問題在傳輸，不在繪製。** 1080p60 下，RGBA 每幀 7.91 MB，需要 475 MB/s 通過解碼管線，而管線
實測為 247–416 MB/s。因此播放停在 30–43 fps，硬體解碼也毫無助益：軟體 43.5 fps 對上 `d3d11va`
的 42.3 fps，差距落在雜訊內。

NV12 以每像素 12 位元而非 32 位元承載同一張畫面——每幀 2.97 MB、178 MB/s。若在 CPU 上把它轉回
RGB，等於把省下的頻寬立刻還回去，而 `GdkMemoryTexture` 又沒有對應 NV12 的格式，因此轉換移至
GPU 進行（檔案與數據如上表）。

2.7 倍的降幅與位元組算術吻合；它是先被預測、後被量測的。

**這不是零複製。** 影格仍會經由 ffmpeg 管線通過 CPU 記憶體。真正的零複製需要行程內解碼加上
`glImportMemoryWin32HandleEXT`；本機已確認具備 `external-objects-win32`，留待日後嘗試。

## Frame accounting

Three separate ways a frame fails to reach the screen. They were merged into one
"dropped" number that was always zero, which read as "nothing is wrong" while
the app ran at 52 fps against a target of 60.

| shown as | meaning | when non-zero |
|---|---|---|
| `short` | target rate minus achieved rate | the pipe could not carry them; **never produced** |
| `skipped` | read in full, then deliberately not drawn | only with **Frame drop** on |
| `overwritten` | handed to the GL view, replaced before it drew them | the widget could not keep up |

`overwritten` was invisible until it was counted. `NV12GLView.setFrame` stores
into `pendingFrame`, and a frame arriving before the previous one was drawn
simply replaced it — from the decoder's side the handover looked like a success.
That is the number that explains "52 fps with 0 dropped".

The line is always visible, not behind the **Show resolution** toggle. Hiding it
is how "0 dropped" was believed in the first place.

一幀無法抵達螢幕的三種不同方式。它們原本被合併成單一個「dropped」數字，而該數字恆為零，看起來
像是「一切正常」，實際上 app 正以 52 fps 執行、目標卻是 60。

`overwritten` 在被計數之前完全不可見。`NV12GLView.setFrame` 會存入 `pendingFrame`，若下一幀在
前一幀被繪製之前抵達，就會直接取代它——而從解碼端看來，這次交遞看起來是成功的。這正是
「52 fps 卻 0 dropped」的解釋。

該行一律顯示，不置於 **Show resolution** 開關之後。把它藏起來，正是「0 dropped」最初被採信的
原因。

## Back-pressure, and pacing

Two different things, deliberately not merged.

**Back-pressure is always on.** The decode loop waits when the widget already
holds two undrawn frames. Not reading is what throttles ffmpeg: the pipe fills,
ffmpeg blocks on write, and decoding stops costing anything. Before this the
loop read flat out and overwrote — decode work, pipe bandwidth and CPU all spent
on pictures nobody saw.

**`-pace` is opt-in**, and matches P6's flag of the same name: it caps ffmpeg
with `-readrate` so the decoder does not run ahead of the clock. Opt-in for the
reason it is in P6 — with it on, maximum throughput cannot be measured, because
the decoder is deliberately being held back.

The distinction: back-pressure stops work nobody will see; `-pace` stops work
that is merely early.

兩件不同的事，刻意不合併。

**背壓一律開啟。** 當 widget 已持有兩幀未繪製的畫面時，解碼迴圈會等待。「不讀取」正是節流
ffmpeg 的手段：管線填滿後 ffmpeg 會在寫入時阻塞，解碼隨即不再消耗任何資源。在此之前，該迴圈會
全速讀取並覆蓋——解碼工作、管線頻寬與 CPU 全都花在沒有任何人看見的畫面上。

**`-pace` 為選用**，與 P6 的同名旗標一致：它以 `-readrate` 限制 ffmpeg，使解碼器不會超前時鐘。
採用選用制的理由與 P6 相同——開啟時無法量測最大吞吐量，因為解碼器正被刻意抑制。

兩者的區別：背壓阻止的是「沒有人會看到」的工作；`-pace` 阻止的是「只是太早」的工作。

## Decode selection: `-cpu`, `-gpu`, and the fallback

| flag | behaviour |
|---|---|
| `-cpu` | force software decode |
| `-gpu` | force hardware decode; **refuses to start** if none is available |
| (default) | try hardware, fall back to software, and say which ran |

`-gpu` refuses rather than falling back, because a forced mode that silently
becomes its opposite produces a measurement labelled `gpu` taken on the CPU.

**The fallback is decided by the first frame, not by the list.**
`ffmpeg -hwaccels` reports what was compiled in, not what works — in WSL it
lists `cuda` and `vaapi` on a system with no render node at all. Selecting from
that list alone gives a decoder that starts, produces zero frames and leaves a
blank window, which reads as "the backend cannot render" rather than "the
hwaccel is unavailable".

Preference order is platform-specific: Windows takes `d3d11va` before `cuda`,
because which GPU the app got is decided outside the app (see below) and an
NVIDIA-only choice would fail on exactly the runs that landed on the integrated
GPU.

`-gpu` 選擇拒絕而非回退，因為一個被強制指定卻靜默變成其反面的模式，會產生一份標示為 `gpu`、
實際卻在 CPU 上取得的量測結果。

**回退的判斷依據是第一幀，而非清單。** `ffmpeg -hwaccels` 回報的是編譯時納入的項目，而非實際
可用者——在 WSL 上，即使系統完全沒有 render node，它仍會列出 `cuda` 與 `vaapi`。

偏好順序依平台而異：Windows 上 `d3d11va` 排在 `cuda` 之前，因為 app 取得哪一顆 GPU 是由 app
之外決定的（見下節），而僅限 NVIDIA 的選擇會正好在那些落到內顯的執行中失敗。

## Audio

A separate `ffplay -nodisp -autoexit` process, the arrangement P6 uses. Not
decoded in process: audio says nothing about which backend draws faster, so an
SDL dependency and a second buffering model would buy no signal.

- **Sync is not enforced.** Fine at 1x, visibly adrift at 3x. Speed uses
  `atempo=1.5,atempo=2.0` for 3x — a single `atempo` accepts 0.5 to 2.0, and
  passing 3 makes ffplay exit immediately, which presents as "no sound" rather
  than as an error.
- **`-mute`** turns it off for measurement runs, where a second process reading
  the same file competes for the disk.
- **The Sound toggle works during playback**, not only at the next start.

**ffplay is killed however the app exits.** `stop()` covers the Stop button and
the `-seconds` timeout and covers neither of the ways a person actually leaves —
closing the window, or Ctrl-C. Both end the process without unwinding through
the model, and ffplay kept playing with no window left to stop it from. `atexit`
plus SIGINT/SIGTERM handlers cover all of them. P6 had the same defect and fixed
it with Darwin signal sources, which is a macOS-only answer.

獨立的 `ffplay -nodisp -autoexit` 行程，與 P6 的做法相同。不在行程內解碼：音訊無法說明哪個
backend 繪製較快，因此一個 SDL 依賴加上第二套緩衝模型換不到任何訊號。

- **不保證同步。** 1x 時無妨，3x 時會明顯飄移。3x 的速度使用 `atempo=1.5,atempo=2.0`——單一
  `atempo` 僅接受 0.5 至 2.0，直接傳入 3 會讓 ffplay 立即結束，其表現是「沒有聲音」而非錯誤。
- **`-mute`** 於量測執行中關閉它，因為第二個讀取同一檔案的行程會與之爭搶磁碟。
- **Sound 開關於播放期間即時生效**，而非僅在下次開始播放時作用。

**無論 app 以何種方式結束，ffplay 都會被終止。** `stop()` 涵蓋 Stop 按鈕與 `-seconds` 逾時，卻
沒有涵蓋任何一種人們實際離開的方式——關閉視窗，或 Ctrl-C。兩者都會在不經過 model 的情況下結束
行程，而 ffplay 會繼續播放，卻已沒有任何視窗可用來停止它。`atexit` 加上 SIGINT/SIGTERM handler
涵蓋了全部情況。P6 有相同缺陷，並以 Darwin 的訊號來源修正，那是僅適用於 macOS 的解法。

## UI parity with P6

Same controls, same order, same labels, same disabled rules: Choose file, seek
slider with `-5s` / `+5s` / `Seek`, Play/Stop, Speed / FPS / Resolution pickers,
and the Sound / Frame drop / Show resolution toggles. A different arrangement
would make a reader hunt for the equivalent instead of looking at the
difference, which defeats the point of having two apps.

Additions P6 does not have: the **Renderer** label states the presentation path,
and the frame accounting line described above.

控制項、順序、標籤與停用規則皆與 P6 相同。若採用不同的排列方式，讀者會忙於尋找對應項目而非直接
觀察差異，那將使「維持兩支 app」失去意義。

P6 沒有的新增項目：**Renderer** 標籤會標示呈現路徑，以及上述的幀數統計行。

## Running it

```sh
# build with -gtk4; without it the app links WinUIBackend
zsh testapp/compile.zsh -gtk4 P6-v2

# watch and listen
./testapp/output/P6-v2-gtk4.exe -i <file> -autoplay

# measure: fixed sample length, no audio process competing for the disk
./testapp/output/P6-v2-gtk4.exe -i <file> -res 1080p -fps 60 -speed 1x \
    -autoplay -seconds 20 -mute --debug

# which GPU is GTK actually on
GDK_DEBUG=opengl ./testapp/output/P6-v2-gtk4.exe
```

**Set the GPU preference before measuring on a hybrid-graphics laptop.** With no
entry under `HKCU\SOFTWARE\Microsoft\DirectX\UserGpuPreferences` an executable
is given the integrated GPU, silently. This machine reported
`AMD Radeon(TM) Graphics` — the Ryzen APU, identifiable only by the absence of a
model number — while holding an RTX 4060:

```sh
reg.exe add "HKCU\SOFTWARE\Microsoft\DirectX\UserGpuPreferences" \
  //v "C:\...\testapp\output\P6-v2-gtk4.exe" //t REG_SZ //d "GpuPreference=2;" //f
```

The entry is keyed by full path, so every binary needs its own. Without one, a
comparison silently runs two builds on two different GPUs and both sets of
numbers look reasonable.

**在混合顯示卡筆電上量測之前，請先設定 GPU 偏好。** 若 `UserGpuPreferences` 下沒有對應項目，
執行檔會被靜默指派內顯。本機在配備 RTX 4060 的情況下回報 `AMD Radeon(TM) Graphics`，即 Ryzen
APU——唯一的辨識線索是它不含型號。

該設定以完整路徑為鍵，因此每個二進位檔都需各自登記。少了它，一次比較會靜默地在兩顆不同的 GPU
上執行兩個建置版本，而兩邊的數字看起來都很合理。

## Known open items

- **Pickers open a window that does not come to the front and does not close
  after selection.** Reported on Windows/GtkBackend. Same shape as the GTK file
  chooser bug fixed earlier by migrating to `GtkFileDialog`, and not yet
  diagnosed.
- **Zero-copy decode to GL** — see above; distinct from what NV12 achieved.
- **A backend-agnostic video view** does not exist. The app writes its own
  `GtkWidgetRepresentable`; GtkBackend supplies only the escape hatch, not a
  video surface. Making this one API call would need a SwiftCrossUI protocol
  plus implementations in both backends.

- **選單會開啟一個不會被帶到前景、且選取後不會關閉的視窗。** 於 Windows/GtkBackend 上回報。與
  先前透過遷移至 `GtkFileDialog` 修正的 GTK 檔案選擇器缺陷形態相同，尚未診斷。
- **零複製解碼至 GL**——見上文；與 NV12 所達成的並非同一件事。
- **不存在 backend 無關的影片視圖。** app 需自行撰寫 `GtkWidgetRepresentable`；GtkBackend 只提供
  逃生艙，而非影片表面。要讓它成為單一 API 呼叫，需要 SwiftCrossUI 層的協定，以及兩個 backend
  各自的實作。
