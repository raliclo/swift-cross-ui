# P6 效能評估與業界標準比較

## 評估版本

- `P6.swift` 提交：`8845476c743d0eae94c783495b4648993aff5587`
- 提交摘要：`P6: improve controls, cleanup, and seek synchronization`
- 測試條件：3 倍速、60 FPS、3840x2160 輸出、開啟音訊、開啟 Frame Drop
- 測試來源：VP9、1920x1080、約 29.97 FPS

## 綜合結論

Gemini 的分析在理論壓力方向上合理，但套用到目前 P6 的實際測試時過度樂觀。較精確的評價是：P6 已達到良好的實驗型播放器與壓力測試水準，但目前證據不足以稱為「工業級效能優異」；尤其記憶體占用仍明顯偏高。

## 實際呈現率不是每秒 180 張 4K 影格

P6 的影片處理順序是：

```text
setpts=(PTS-STARTPTS)/3
-> fps=60
-> scale=3840:2160
-> RGBA rawvideo
-> Metal
```

程式的 Metal 顯示週期仍為 `1 / 60`，即每張約 16.67 ms；每張輸出影格則前進 `3 / 60 = 0.05` 秒的來源時間。FFmpeg 的 `setpts` 修改影格時間戳，後續 `fps=60` filter 再透過複製或丟棄影格產生固定的 60 FPS 輸出。

因此這次實際負載較接近：

- 解碼或巡覽約 `29.97 x 3 = 89.9` 張來源影格／秒。
- FFmpeg 輸出及 Metal 呈現最多 60 張 4K RGBA 影格／秒。
- 並不是 Metal 每秒呈現 180 張 4K 影格。

只有在來源本身是原生 4K 60 FPS，而且解碼器必須解出所有來源影格時，解碼端才可能接近每秒 180 張來源影格；即使如此，目前 P6 的 Metal 輸出仍受 `fps=60` 限制。

FFmpeg 官方參考：

- <https://ffmpeg.org/ffmpeg-filters.html#setpts_002c-asetpts>
- <https://ffmpeg.org/ffmpeg-filters.html#fps-1>

## 60 FPS 的資料搬移壓力仍然很高

一張 3840x2160 RGBA 影格為 33.18 MB，約 31.64 MiB。60 FPS 的 raw RGBA 資料量約為每秒 1.99 GB，或約 1.85 GiB。

所以即使不是 180 FPS，目前的 `FFmpeg 子程序 -> Pipe -> Swift Data -> Metal texture` 仍是一條高頻寬、涉及大量記憶體搬移的管線。

P6 使用三個可重複利用的 Metal texture，三個 4K RGBA texture 約占 94.9 MiB。這符合 Apple 建議的 triple-buffering 最佳化方向，可在 CPU/GPU 平行度、延遲與記憶體占用之間取得平衡。

Apple 官方參考：

- <https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/TripleBuffering.html>

## RSS 有界是好現象，但峰值 2.29 GiB 不能稱為優秀

目前 RSS 紀錄顯示：

- 測試時間約 199 秒。
- 共有 196 筆有效樣本。
- 平均 RSS 約 1.92 GiB。
- 峰值 RSS 為 2,398,896 KiB，約 2.29 GiB。
- P6 結束狀態為 0。

後半段 RSS 大致維持在 2.2 GiB 左右，沒有在這段短測試中呈現明顯的無限制成長。因此可以說暫時沒有發現明顯的持續性記憶體洩漏，但不足以證明完全沒有 leak。以一般影片播放器而言，P6 本體約 2.29 GiB RSS 仍偏高。

`test_P6.zsh` 只使用 `ps` 取樣 P6 的 PID，並未包含 `ffmpeg`、`ffplay` 或 `zstd` 子程序的 RSS。因此開啟音訊所增加的 `ffplay` 記憶體並沒有反映在這份紀錄內。

業界沒有「300 MB 至 800 MB 即為合格」這種通用標準。RSS 也會受到 allocator 保留、Metal shared memory 與記憶體映射影響。應進一步使用 Xcode Memory Report、Metal System Trace、Metal Resource Allocations 與 Memory Graph 分析真正的資源占用。

Apple 官方參考：

- <https://developer.apple.com/documentation/metal/reducing-the-memory-footprint-of-metal-apps>
- <https://developer.apple.com/documentation/xcode/metal-developer-workflows>

## 與工業級 macOS 播放器的架構差異

較成熟的 macOS 播放器通常採用：

```text
Demux
-> VideoToolbox 硬體解碼
-> CVPixelBuffer / NV12
-> CVMetalTextureCache
-> Metal shader 色彩轉換與呈現
```

VideoToolbox 可提供硬體加速影片解碼，而 `CVMetalTextureCache` 可把 Core Video image buffer 映射為 Metal texture，減少 RGBA 中間資料及額外 CPU copy。

目前 P6 採用：

```text
外部 ffmpeg
-> 4K RGBA rawvideo pipe
-> Swift Data
-> texture.replace
-> Metal
```

目前架構容易實作與除錯，也已能播放；但在記憶體頻寬、CPU copy、程序管理與精準影音同步方面，與工業級低拷貝播放管線仍有距離。

Apple 官方參考：

- <https://developer.apple.com/documentation/videotoolbox>
- <https://developer.apple.com/documentation/corevideo/cvmetaltexturecache-q3j>

## 影音同步尚未有量化證據

目前 RSS 紀錄沒有包含：

- 實際顯示 FPS。
- 每秒 dropped frames。
- P95 或 P99 frame time。
- 音訊與視訊時間差。
- CPU／GPU 使用率。
- thermal throttling。

因此不能從這份紀錄證明播放期間維持影音同步且掉幀極低。若以廣播業界作為較嚴格參考，EBU 對最終輸出的整體同步範圍建議為聲音最多提前 40 ms、最多延後 60 ms。

EBU 官方參考：

- <https://tech.ebu.ch/publications/r037>

## 綜合評級

| 項目 | 評價 |
| --- | --- |
| 3 倍速壓力播放可完成 | 良好 |
| Metal 三紋理重複利用 | 符合正確最佳化方向 |
| 4K RGBA 管線吞吐量 | 很高，但記憶體搬移代價也很高 |
| RSS 穩定性 | 短期內有界，尚未發現明顯無限制成長 |
| RSS 效率 | 2.29 GiB 偏高，需要進一步分析 |
| 影音同步 | 目視改善，但尚未量化 |
| 工業級架構 | 尚未達到硬體解碼與低拷貝管線水準 |

最準確的總結是：P6 的結果是很不錯的功能型原型與壓力測試成果，但不能僅依目前紀錄判定為工業級優異。Gemini 對 180 FPS 的說法只適用於特定原生 4K60 解碼情境；目前實際測試是 1080p29.97 解碼後升頻為 4K60。當前最值得改善的是約 2.29 GiB 的 P6 RSS，以及未來將 raw RGBA pipe 改成 VideoToolbox、CVPixelBuffer 與 CVMetalTextureCache 管線。
