# P6 Windows 效能觀察

`gpu-modes.csv` 由 `testapp/gpu-matrix.zsh` 寫入，每次執行、每種 GPU 模式各一列：

```sh
zsh testapp/gpu-matrix.zsh <resolution> <target fps> <seconds>
zsh testapp/gpu-matrix.zsh 4k 60 20
```

欄位為 `date_tested, mode, resolution, target_fps, measured_fps, frames_dropped_per_sec, read_avg_ms, present_avg_ms, seconds, ffmpeg_args`。`ffmpeg_args` 是 P6 該次傳給 ffmpeg 的完整引數，因此每一列都能不靠猜測重現。

`read_avg_ms` 是從 decoder pipe 取得一張影格並寫入 mapped GPU memory 的時間；`present_avg_ms` 是複製到 back buffer 加上 `Present` 的時間。兩者都來自 P6 每秒記錄一次的 `stage timings:` log。

## 2026-08-12 的資料顯示什麼

- **GPU 不是關鍵。** 在每個解析度和 frame rate 下，五種模式：default、`-amd`、`-nvidia`、`-both-gpu`、`-no-gpu`（Microsoft CPU rasteriser）都落在雜訊範圍內。present 成本是 0-6 ms，而 frame budget 是 16-33 ms。選哪張 GPU 不是這個 workload 的有效槓桿。
- **讀取端才是成本。** `read_avg_ms` 幾乎精準追著總負載走：1080p30 約 8 ms、1080p60 約 21 ms、4K30 約 58 ms、4K60 則到 380-1020 ms。
- **decoder 不是成本。** 獨立跑相同 filter chain（`ffmpeg ... -f rawvideo -pix_fmt rgba -y NUL`）時，4K60 約可產生 123 fps，約為 realtime 的 2.1 倍。ffmpeg 能產生的影格遠多於 P6 能消耗的量。
- 剩下的開放問題是 CPU contention：4K60 時，ffmpeg 會把機器吃滿去產生沒有人等的影格，而同一張 33 MB 影格在 4K30 讀取只要 58 ms，在 4K60 卻要多十倍。下一步是嘗試把 decoder pace 到播放速率（`-re` / `-readrate`）。

更早之前，在 P6 還沒有自己擁有 pipe 時，光是 1080p 的 read stage 就要每張 100-160 ms。Foundation 的 `Pipe` 在 Windows 會呼叫 `CreatePipe(..., 0)`，buffer 是系統預設的幾 KB，而且沒有 API 可改；每次 `read(upToCount:)` 也會配置一個 `Data`，再 append 到逐漸長大的 frame-sized buffer，最後再複製第二次到 texture。P6 現在改成建立自己的 8 MB buffer pipe，並用 `ReadFile` 直接讀入 mapped staging texture。
