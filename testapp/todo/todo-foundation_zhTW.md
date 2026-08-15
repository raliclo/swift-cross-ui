# 準備提交給 swift-corelibs-foundation 的事項

這些是在建立 P6 Windows video path 時發現的問題。每一項都讓 `testapp/P6.swift` 必須加入 workaround；如果 Foundation 暴露底層 Win32 能力，這些 workaround 就不需要存在。量測資料來自本機：Windows 11、AMD Radeon iGPU + RTX 4060、1920x1080 @ 125%。

## 1. Windows 上的 `Pipe` 無法設定 buffer size

`Sources/Foundation/FileHandle.swift` 會用 hardcoded `0` 建立每條 pipe：

```swift
if !CreatePipe(&hReadPipe, &hWritePipe, &saAttr, 0) {
  fatalError("CreatePipe failed")
}
```

`0` 代表使用 kernel 預設值，也就是幾 KB。對串流大量 binary data 來說太小：一張 8 MB video frame 會拆成數千次 read，而且每次 `read(upToCount:)` 都會配置一個 `Data`，呼叫端再把它 append 到逐漸長大的 buffer。

**量測結果**：把一張 1080p frame 從 child process 移進 app 要 102-164 ms，而 frame budget 是 33 ms。改成用 `CreatePipe` 建立約 2 張 frame 大小的 buffer，並用 `ReadFile` 讀取後，同樣工作降到 2-9 ms。

**建議**：傳入較大的預設 `nSize`，或新增可指定 buffer size 的 initializer（`Pipe(bufferSize:)`）。單純提高預設值就能修掉大多數案例，而且不破壞 API。

**注意**：越大不一定越好。4K60 實測：25 MB 為 49.9 fps、128 MB 為 51.6、512 MB 為 48.2、2 GB 為 45.3。重點是 buffer 至少能容納一個 message；再大只會增加 latency。

## 2. Windows 上 `FileHandle.fileDescriptor` 不可用

讀取它會 trap：「Cannot perform non-owning handle to fd conversion」，而且沒有其他方式取得底層 `HANDLE`。這讓任何 zero-copy read 都不可能：bytes 無法直接讀到呼叫端提供的記憶體（此處是 mapped D3D11 staging texture），每次 read 都必須經過 Foundation 配置的 `Data`。

**建議**：在 Windows 暴露 native handle。可以讓 `fileDescriptor` 可用，或新增一個文件化的 Windows-only property 回傳 `HANDLE`。`Pipe` 和 `FileHandle` 都需要。

**P6 workaround**：`P6WideWin32Pipe` 用 `CreatePipe` 建立 pipe 並保留 raw handles，因此 `ReadFile` 可以直接寫進 GPU-visible memory。

## 3. `Process` 無法設定 process creation flags

`CreateProcessW` 目前只帶一個 flag：

```swift
DWORD(CREATE_UNICODE_ENVIRONMENT), UnsafeMutableRawPointer(mutating: wszEnvironment),
```

沒有方式加入 `CREATE_NO_WINDOW`。console child 在父程序有 console 時會繼承；**父程序沒有 console 時會自行開一個 console window**。GUI app 從 Explorer 或 pty-based terminal 啟動時就屬於這種情況。P6 會 spawn ffmpeg、ffplay、zstd、ffprobe，並在每次解析度或 frame-rate 變更時重啟 decoder，因此 console window 會一直蓋到播放器上。

**建議**：提供影響 creation flags 的方式。就算只是一個 Windows-only 的 `Process` property（例如 `createsNoWindow`，預設維持現行行為）也能涵蓋常見情境；一般化版本則可用 options set。

**P6 workaround**：`P6WindowlessProcess` 直接呼叫 `CreateProcessW` 並帶 `CREATE_NO_WINDOW`，也因此必須依 `CommandLineToArgvW` 規則重作 argument quoting、handle inheritance、termination 和 exit code。

---

不屬於 Foundation，但一起發現、值得回報給 swift-cross-ui：

- `WinUIElementRepresentable` 的預設 `sizeThatFits` 會向 element 詢問 desired size；而 `WinUI.Canvas` 不會 measure 子元素，所以任何以 Canvas 為 root 的 representable 都會量到 0x0，然後 layout 會把它置中。
- Windows file picker 不會把 activation 還給擁有它的 window，所以選完檔案後 app 會留在底下的視窗後面。這裡已在 `WinUIBackend.showFileOpenDialog` 和相關函式中修正。
