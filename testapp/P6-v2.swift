import DefaultBackend
import Foundation
import Gtk
import GtkBackend
import ImageFormats
import SwiftCrossUI

// P6-v2 video playback on GtkBackend, for comparing against P6 on WinUIBackend.
//
// P6 stays exactly as it is. It is the WinUI/D3D11 implementation and cannot be
// switched: a SwapChainPanel with a D3D11 composition swap chain has no
// GtkBackend equivalent, so `-gtk4` refuses to build it rather than failing
// thirteen minutes in. This file is the GTK answer to the same question, written
// fresh rather than copied, because roughly 2700 of P6's 3990 lines are the
// D3D11 measurement apparatus, the macOS Metal and CoreVideo paths, and stream
// fetching -- none of which a backend comparison needs.
//
// What it deliberately keeps is P6's measurement vocabulary, because the whole
// point is to put numbers side by side: the same 1x/2x/3x speeds, the same
// 30/45/60 frame rates, the same resolutions, and the same dropped-frame
// accounting. A comparison against differently-defined numbers is not a
// comparison.
//
// Audio is a separate ffplay process, the arrangement P6 uses. Not decoded in
// process: it says nothing about which backend draws faster, so an SDL
// dependency and a second buffering model would buy no signal. The cost is that
// sync is not enforced -- fine at 1x, visibly adrift at 3x -- and `-mute` turns
// it off for measurement runs, where a second process reading the same file
// competes for the disk.
//
// P6-v2 於 GtkBackend 上的影片播放，用於與 WinUIBackend 上的 P6 對照。
//
// P6 完全保持原樣。它是 WinUI/D3D11 的實作且無法切換：搭配 D3D11 composition swap chain
// 的 SwapChainPanel 在 GtkBackend 中沒有對應物，因此 `-gtk4` 會直接拒絕建置它，而非在
// 十三分鐘後才失敗。本檔是同一個問題的 GTK 答案，採全新撰寫而非複製，因為 P6 的 3990 行
// 中約有 2700 行是 D3D11 量測設施、macOS 的 Metal 與 CoreVideo 路徑，以及串流取得——
// 這些都不是 backend 比較所需要的。
//
// 刻意保留的是 P6 的量測語彙，因為重點正是把數字並列比較：相同的 1x/2x/3x 速度、相同的
// 30/45/60 幀率、相同的解析度，以及相同的掉幀計算方式。以定義不同的數字進行比較，並不算
// 比較。
//
// 音訊採用獨立的 ffplay 行程，與 P6 的做法相同。不在行程內解碼：它無法說明哪個 backend 繪製
// 較快，因此一個 SDL 依賴加上第二套緩衝模型換不到任何訊號。代價是不保證同步——1x 時無妨，
// 3x 時會明顯飄移——而 `-mute` 可在量測執行中關閉它，因為第二個讀取同一檔案的行程會與之
// 爭搶磁碟。
//
// Which GPU GTK draws on is not measured in here, because the app cannot see it.
// Ask GTK directly:
//     GDK_DEBUG=opengl ./P6-v2.exe
// A software fallback names llvmpipe or similar.
//
// On a hybrid-graphics laptop the answer also depends on a Windows setting the
// app has no part in. With no entry under
// HKCU\SOFTWARE\Microsoft\DirectX\UserGpuPreferences an executable is given the
// integrated GPU, and this reported `AMD Radeon(TM) Graphics` -- the Ryzen APU,
// identifiable only by the absence of a model number -- on a machine whose
// discrete GPU is an RTX 4060. Setting `GpuPreference=2;` for the full .exe path
// switched it to `NVIDIA GeForce RTX 4060 Laptop GPU`. The entry is keyed by
// path, so every binary needs its own, and without one a comparison silently
// runs two builds on two different GPUs.
// GTK 在哪一顆 GPU 上繪製並未在此量測，因為 app 看不到這項資訊。請直接詢問 GTK：
//     GDK_DEBUG=opengl ./P6-v2.exe
// 若是軟體回退路徑，會顯示 llvmpipe 之類的名稱。
//
// 在混合顯示卡筆電上，答案還取決於一項 app 無從參與的 Windows 設定。若
// HKCU\SOFTWARE\Microsoft\DirectX\UserGpuPreferences 下沒有對應項目，執行檔會被指派內顯；
// 本機因此回報 `AMD Radeon(TM) Graphics`——即 Ryzen APU，唯一的辨識線索是它不含型號——
// 而該機器的獨顯其實是 RTX 4060。為完整的 .exe 路徑設定 `GpuPreference=2;` 之後，它切換為
// `NVIDIA GeForce RTX 4060 Laptop GPU`。該設定以路徑為鍵，因此每個二進位檔都需各自登記；
// 少了它，一次比較會靜默地在兩顆不同的 GPU 上執行兩個建置版本。
//
// Build this file as a standalone app target.

// MARK: - Diagnostics

enum P6v2Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P6-v2] \(message)")

        guard let data = "P6-v2 \(Date()) \(message)\n".data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p6-v2-debug-events.log")
        if FileManager.default.fileExists(atPath: url.path),
            let handle = try? FileHandle(forWritingTo: url)
        {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    static func renderComplete() {
        guard !didAnnounceRender else { return }
        didAnnounceRender = true
        write("RENDER COMPLETE -- P6-v2 ready")
    }
}

// MARK: - Flags

enum P6v2Flags {
    /// Reads `-flag value`. Returns nil when the flag is absent or trailing.
    /// 讀取 `-flag value`。若旗標不存在或位於結尾則回傳 nil。
    static func value(for flag: String) -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag),
            index + 1 < arguments.count
        else { return nil }
        return arguments[index + 1]
    }

    static let inputPath: String? = value(for: "-i")
    static let autoplay = CommandLine.arguments.contains("-autoplay")

    /// Presets so a measurement run needs no clicking. The three together are
    /// what a comparison varies, and a run that has to be driven by hand cannot
    /// be repeated identically across two backends.
    /// 提供預設值，使量測執行無需點擊。這三者正是比較時所要變動的項目；而必須以手動操作
    /// 驅動的執行，無法在兩個 backend 上以完全相同的方式重複。
    static let speed: String = value(for: "-speed") ?? "1x"
    static let fps: String = value(for: "-fps") ?? "60"
    static let resolution: String = value(for: "-res") ?? "1080p"

    /// Exit after this many seconds and print the summary. Without it a
    /// measurement depends on someone noticing and closing the window, which
    /// makes the sample length a variable.
    /// 於指定秒數後結束並印出摘要。若無此旗標，量測就取決於是否有人注意到並關閉視窗，
    /// 使取樣長度變成一個變數。
    static let runSeconds: Double? = value(for: "-seconds").flatMap(Double.init)

    /// Silences the ffplay process. Wanted for measurement runs, where a second
    /// process reading the same file competes for the disk.
    /// 關閉 ffplay 行程。量測執行時需要此選項，因為第二個讀取同一檔案的行程會與之爭搶磁碟。
    static let isMuted = CommandLine.arguments.contains("-mute")

    /// `--frame-drop`, spelled as P6 spells it so a command line copied from one
    /// works on the other.
    /// `--frame-drop`，拼法與 P6 一致，使從其中一支複製的命令列可直接用於另一支。
    static let isFrameDropEnabled = CommandLine.arguments.contains("--frame-drop")

    /// `-pace`, as P6 spells it: caps ffmpeg at playback speed with `-readrate`
    /// so the decoder does not run ahead of the clock.
    ///
    /// Opt-in for the same reason it is in P6 -- with it on, the maximum
    /// throughput cannot be measured, because the decoder is deliberately being
    /// held back. Back-pressure from the widget is always on and is a different
    /// thing: that stops work nobody will see, this stops work that is simply
    /// early.
    ///
    /// `-pace`，拼法與 P6 一致：以 `-readrate` 將 ffmpeg 限制在播放速度，使解碼器不會超前時鐘。
    ///
    /// 採用選用制的理由與 P6 相同——開啟時無法量測最大吞吐量，因為解碼器正被刻意抑制。來自
    /// widget 的背壓則一律開啟，且是另一回事：後者阻止的是「沒有人會看到」的工作，前者阻止的
    /// 是「只是太早」的工作。
    static let isDecodePaced = CommandLine.arguments.contains("-pace")

    static let acceleration: P6v2Acceleration = {
        if CommandLine.arguments.contains("-cpu") { return .forceCPU }
        if CommandLine.arguments.contains("-gpu") { return .forceGPU }
        return .auto
    }()
}

/// Which decoder ffmpeg is asked to use.
///
/// This switches **decode only**. Presentation is always the GL path now --
/// NV12 straight to two textures and a fragment shader -- so `-cpu` means
/// software decode, not software drawing. The status line names both stages
/// separately for that reason, rather than letting the flag imply either.
///
/// An earlier version of this comment said presentation went through
/// GdkMemoryTexture in every mode because no GtkGLArea binding existed. That
/// was true when written and is not now; the binding is `Gtk.NV12GLView`.
///
/// The switch turned out to matter far less than the format. Measured at
/// 1080p60 on RGBA, software decode gave 43.5 fps and d3d11va 42.3 -- within
/// noise, because the decoder pipe was the ceiling either way. Moving to NV12
/// took the same run to 51.9 fps with read time falling from 19-32 ms to 8.55.
///
/// `.auto` falls back silently in the sense that it does not fail, but never in
/// the sense that it hides what happened -- the mode that actually ran is in the
/// status line and in the summary.
///
/// 決定 ffmpeg 使用哪種解碼器。
///
/// 此旗標**僅切換解碼**。呈現現在一律走 GL 路徑——NV12 直接送入兩張材質並由 fragment shader
/// 處理——因此 `-cpu` 指的是軟體解碼，而非軟體繪製。狀態列正是為此分別標示兩個階段，而不讓
/// 旗標名稱去暗示其中任何一個。
///
/// 本註解的舊版本曾說呈現在所有模式下都經由 GdkMemoryTexture，因為當時不存在 GtkGLArea
/// 綁定。那在撰寫當時屬實，現在則否；該綁定即為 `Gtk.NV12GLView`。
///
/// 結果顯示，這個切換的重要性遠低於格式本身。1080p60 於 RGBA 下實測，軟體解碼為 43.5 fps、
/// d3d11va 為 42.3——差距落在雜訊內，因為兩者的上限都是解碼管線。改用 NV12 後，同樣的執行
/// 達到 51.9 fps，讀取時間也從 19–32 ms 降至 8.55 ms。
///
/// `.auto` 的回退是「不會失敗」意義上的靜默，但絕非「隱藏發生了什麼」——實際執行的模式會
/// 出現在狀態列與摘要中。
enum P6v2Acceleration: Sendable {
    case auto
    case forceGPU
    case forceCPU

    var label: String {
        switch self {
            case .auto: "auto"
            case .forceGPU: "gpu"
            case .forceCPU: "cpu"
        }
    }
}

// MARK: - Resolution

enum P6v2Resolution: String, CaseIterable, Sendable {
    case qhd = "540p"
    case fhd = "1080p"
    case uhd = "2160p"

    var width: Int {
        switch self {
            case .qhd: 960
            case .fhd: 1920
            case .uhd: 3840
        }
    }

    var height: Int {
        switch self {
            case .qhd: 540
            case .fhd: 1080
            case .uhd: 2160
        }
    }

    /// NV12: a full-resolution luma plane followed by a half-resolution
    /// interleaved chroma plane, so 12 bits per pixel against RGBA's 32.
    ///
    /// This is the whole point of the format choice and it is transport, not
    /// drawing. At 1080p60 RGBA needs 475 MB/s through the decoder pipe while
    /// the pipe measures 247-416 MB/s, which held playback at 30-43 fps with
    /// zero dropped frames and made hardware decode worth nothing -- 43.5 fps
    /// software against 42.3 with d3d11va. NV12 needs 178 MB/s.
    ///
    /// P6 reached the same conclusion first and already defaults to NV12,
    /// keeping `-rgba` only as an A/B control. P6-v2 was written with RGBA and
    /// so began on the path P6 had already abandoned.
    ///
    /// NV12：一個全解析度的亮度平面，後接一個半解析度、交錯排列的色度平面，因此每像素 12
    /// 位元，相對於 RGBA 的 32 位元。
    ///
    /// 這正是選擇此格式的全部理由，而理由在於傳輸而非繪製。1080p60 下，RGBA 需要 475 MB/s
    /// 通過解碼管線，而管線實測為 247–416 MB/s，這使播放停在 30–43 fps 且掉幀為零，也讓硬體
    /// 解碼毫無價值——軟體 43.5 fps 對上 d3d11va 的 42.3 fps。NV12 只需要 178 MB/s。
    ///
    /// P6 更早得出相同結論，且早已預設使用 NV12，僅保留 `-rgba` 作為 A/B 對照。P6-v2 起初
    /// 以 RGBA 撰寫，因而一開始就走在 P6 已經放棄的那條路上。
    var frameByteCount: Int { width * height * 3 / 2 }

    /// Byte count of the luma plane, which is also where the chroma plane
    /// starts within a frame.
    /// 亮度平面的位元組數，同時也是色度平面在一幀之內的起始位移。
    var lumaByteCount: Int { width * height }

    static func named(_ label: String) -> P6v2Resolution {
        allCases.first { $0.rawValue == label } ?? .fhd
    }
}

// MARK: - Statistics

/// Frame accounting, updated from the decode thread and read from the UI, so
/// every access goes through a lock.
///
/// `presented` and `dropped` are counted separately rather than derived from
/// each other. A frame that is read but never shown is dropped; a frame that is
/// never read is not, because it was never produced. Deriving one from a
/// expected total conflates "the pipe was slow" with "the display was slow",
/// which are the two things this app exists to tell apart.
///
/// 幀數統計，由解碼執行緒更新、由 UI 讀取，因此每次存取都經過鎖。
///
/// `presented` 與 `dropped` 分別計數，而非由彼此推導。已讀取但未顯示的幀算作掉幀；從未
/// 讀取的幀則不算，因為它根本未被產生。若由「預期總數」推導其一，會混淆「管線慢」與
/// 「顯示慢」這兩件事，而區分這兩者正是本 app 存在的理由。
final class P6v2Stats: @unchecked Sendable {
    private let lock = NSLock()
    private var presentedTotal = 0
    private var droppedTotal = 0
    private var presentedInWindow = 0
    private var droppedInWindow = 0
    private var windowStart = Date()
    private var readNanosTotal: UInt64 = 0
    private var readSamples = 0

    private(set) var currentFPS = 0
    private(set) var currentDropsPerSecond = 0

    let startedAt = Date()

    func recordPresented() {
        lock.lock()
        presentedTotal += 1
        presentedInWindow += 1
        lock.unlock()
    }

    func recordDropped() {
        lock.lock()
        droppedTotal += 1
        droppedInWindow += 1
        lock.unlock()
    }

    func recordRead(nanoseconds: UInt64) {
        lock.lock()
        readNanosTotal += nanoseconds
        readSamples += 1
        lock.unlock()
    }

    /// Where the rest of the loop's time goes.
    ///
    /// Added because the arithmetic did not close: reads averaged 8.47 ms, which
    /// allows 118 iterations a second, and the loop managed 23. Roughly 35 ms per
    /// iteration was unaccounted for, and attributing it to GTK would have been a
    /// guess -- the widget's own upload measures 0.3 ms.
    ///
    /// 迴圈其餘時間的去向。
    ///
    /// 之所以加入，是因為算術對不上：讀取平均 8.47 ms，理論上每秒可跑 118 次迭代，實際卻只有
    /// 23 次。每次迭代約有 35 ms 去向不明，而把它歸咎於 GTK 只會是臆測——widget 自身的上傳
    /// 量得 0.3 ms。
    private var waitNanosTotal: UInt64 = 0
    private var splitNanosTotal: UInt64 = 0

    func recordWait(nanoseconds: UInt64) {
        lock.lock()
        waitNanosTotal += nanoseconds
        lock.unlock()
    }

    func recordSplit(nanoseconds: UInt64) {
        lock.lock()
        splitNanosTotal += nanoseconds
        lock.unlock()
    }

    var phaseBreakdown: String {
        lock.lock()
        defer { lock.unlock() }
        guard readSamples > 0 else { return "no samples" }
        let samples = Double(readSamples)
        return String(
            format: "read %.2fms wait %.2fms split %.2fms",
            Double(readNanosTotal) / samples / 1_000_000,
            Double(waitNanosTotal) / samples / 1_000_000,
            Double(splitNanosTotal) / samples / 1_000_000
        )
    }

    /// Rolls the one-second window. Returns true when the window closed, so the
    /// caller knows the published rates changed.
    /// 推進一秒的取樣視窗。視窗結束時回傳 true，讓呼叫端知道已發布的速率有所變動。
    func rollWindowIfDue() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let elapsed = Date().timeIntervalSince(windowStart)
        guard elapsed >= 1 else { return false }
        currentFPS = Int((Double(presentedInWindow) / elapsed).rounded())
        currentDropsPerSecond = Int((Double(droppedInWindow) / elapsed).rounded())
        presentedInWindow = 0
        droppedInWindow = 0
        windowStart = Date()
        return true
    }

    var summary: String {
        lock.lock()
        defer { lock.unlock() }
        let elapsed = Date().timeIntervalSince(startedAt)
        let averageFPS = elapsed > 0 ? Double(presentedTotal) / elapsed : 0
        let averageReadMs =
            readSamples > 0
            ? Double(readNanosTotal) / Double(readSamples) / 1_000_000
            : 0
        return String(
            format:
                "elapsed %.1fs  presented %d  dropped %d  avg %.1f fps  avg read %.2f ms",
            elapsed,
            presentedTotal,
            droppedTotal,
            averageFPS,
            averageReadMs
        )
    }
}

// MARK: - Decoder

/// Spawns ffmpeg and hands back raw RGBA frames.
///
/// The pipe is the throughput ceiling and that is the finding P6 recorded, not a
/// detail to design around: 4K at 60fps in RGBA needs about 2.0 GB/s, and the
/// measured ceiling is near 1 GB/s. Dropping frames cannot rescue it, because a
/// pipe has no seek -- every frame that will be dropped still has to be read in
/// full. Expect 4K@60 to fail here for the same reason it failed in P6, and to
/// fail identically on both backends, which is itself worth confirming.
///
/// 啟動 ffmpeg 並回傳原始 RGBA 幀。
///
/// 管線本身即為吞吐上限，而這是 P6 已記錄的發現，並非可繞過的細節：4K@60 的 RGBA 需要約
/// 2.0 GB/s，而實測上限接近 1 GB/s。掉幀無法挽救此問題，因為管線無法 seek——即使註定要被
/// 丟棄的幀，仍須完整讀取。預期 4K@60 在此會因與 P6 相同的原因失敗，且在兩個 backend 上
/// 應以相同方式失敗，而這件事本身值得確認。
final class P6v2Decoder: @unchecked Sendable {
    private let process = Process()
    private let outputPipe = Pipe()
    private let frameByteCount: Int
    private var buffer = Data()

    /// The hwaccel actually used, or nil for software decode. Read by the model
    /// so the status line states what ran rather than what was asked for.
    /// 實際使用的 hwaccel，軟體解碼時為 nil。由 model 讀取，使狀態列陳述的是「實際執行的」
    /// 而非「所要求的」。
    let hardwareAcceleration: String?

    init(
        input: URL,
        resolution: P6v2Resolution,
        fps: Int,
        acceleration: P6v2Acceleration,
        startSeconds: Double = 0,
        speed: Double = 1
    ) throws {
        frameByteCount = resolution.frameByteCount

        guard let ffmpeg = P6v2Decoder.locateFFmpeg() else {
            throw P6v2Error.ffmpegMissing
        }

        let chosen: String?
        switch acceleration {
            case .forceCPU:
                chosen = nil
            case .forceGPU:
                guard let available = P6v2Decoder.firstAvailableHWAccel(ffmpeg: ffmpeg) else {
                    throw P6v2Error.noHardwareDecoder
                }
                chosen = available
            case .auto:
                chosen = P6v2Decoder.firstAvailableHWAccel(ffmpeg: ffmpeg)
        }
        hardwareAcceleration = chosen

        var arguments = ["-hide_banner", "-loglevel", "error"]
        // Before -i, not after. hwaccel applies to the input being opened, and
        // placed after it ffmpeg accepts the flag and ignores it -- software
        // decode with no warning and no error.
        // 置於 -i 之前而非之後。hwaccel 作用於「即將開啟的輸入」，若放在其後，ffmpeg 會接受
        // 該旗標並忽略它——結果是軟體解碼，既無警告也無錯誤。
        if let chosen { arguments += ["-hwaccel", chosen] }
        // -ss before -i so ffmpeg seeks by keyframe rather than decoding from
        // the start and discarding. The difference is seconds on a long clip.
        // -ss 置於 -i 之前，使 ffmpeg 依關鍵影格跳轉，而非從頭解碼再丟棄。在長片段上，兩者差
        // 距達數秒。
        if startSeconds > 0 {
            arguments += ["-ss", String(format: "%.3f", startSeconds)]
        }
        // Also before -i: -readrate governs how fast the input is consumed.
        // The initial burst lets playback start without waiting a full second
        // for the first frames.
        // 同樣置於 -i 之前：-readrate 管的是輸入被消耗的速度。初始 burst 讓播放能立即開始，
        // 不必為了最初幾幀等上整整一秒。
        if P6v2Flags.isDecodePaced {
            arguments += [
                "-readrate", String(format: "%.2f", speed),
                "-readrate_initial_burst", "2",
            ]
        }
        arguments += [
            "-i", input.path,
            "-an", "-sn", "-dn",
            "-vf", "scale=\(resolution.width):\(resolution.height),fps=\(fps)",
            "-pix_fmt", "nv12",
            "-f", "rawvideo",
            "pipe:1",
        ]
        P6v2Diagnostics.write("ffmpeg \(arguments.joined(separator: " "))")

        process.executableURL = ffmpeg
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    /// Reads exactly one frame, or nil at end of stream. A single read on a pipe
    /// returns whatever happens to be buffered, which is almost never a whole
    /// frame at these sizes, so the loop is required rather than defensive.
    /// 精確讀取一幀，串流結束時回傳 nil。對管線的單次讀取只會回傳當下緩衝中的內容，在這種
    /// 尺寸下幾乎不可能剛好是完整一幀，因此此迴圈是必要的，而非防禦性寫法。
    func readFrame() -> Data? {
        while buffer.count < frameByteCount {
            guard
                let chunk = try? outputPipe.fileHandleForReading.read(
                    upToCount: frameByteCount - buffer.count
                ),
                !chunk.isEmpty
            else { return nil }
            buffer.append(chunk)
        }
        let frame = buffer.prefix(frameByteCount)
        buffer.removeFirst(frameByteCount)
        return Data(frame)
    }

    func stop() {
        if process.isRunning { process.terminate() }
    }

    /// Asks ffmpeg what it supports and takes the first match from a preference
    /// order, rather than assuming one.
    ///
    /// The order is platform-specific for a reason: on Windows d3d11va is the
    /// one that works on whichever GPU the app was given, and since that is
    /// decided outside the app by the Windows GPU preference, an NVIDIA-only
    /// choice like cuda would fail on exactly the runs that landed on the
    /// integrated GPU.
    ///
    /// 詢問 ffmpeg 支援哪些，再依偏好順序取第一個相符者，而非逕行假設。
    ///
    /// 順序依平台而異是有理由的：在 Windows 上，d3d11va 能在 app 實際取得的任一顆 GPU 上
    /// 運作；而既然那由 app 之外的 Windows GPU 偏好設定決定，像 cuda 這種僅限 NVIDIA 的
    /// 選擇，就會正好在那些落到內顯的執行中失敗。
    private static func firstAvailableHWAccel(ffmpeg: URL) -> String? {
        #if os(Windows)
        let preferred = ["d3d11va", "cuda", "dxva2", "qsv"]
        #elseif os(macOS)
        let preferred = ["videotoolbox"]
        #else
        let preferred = ["cuda", "vaapi", "vdpau"]
        #endif

        let process = Process()
        let pipe = Pipe()
        process.executableURL = ffmpeg
        process.arguments = ["-hide_banner", "-hwaccels"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return nil }
        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()

        // Split on `isNewline`, never on the literal "\n".
        //
        // Swift treats "\r\n" as a single extended grapheme cluster, so it is one
        // Character and it is not equal to "\n". Windows ffmpeg ends every line
        // with CRLF, which means `split(separator: "\n")` finds no separator at
        // all and returns the entire output as one element. The set then holds a
        // single 98-byte string and matches nothing, and the app falls silently to
        // software decode on a machine offering nine hardware decoders.
        //
        // This does not look like a line-ending bug from either end. `od -c`
        // confirms the CR and LF are both present, so the file looks normal; and
        // printing the parsed result sends the terminal's cursor back to column
        // zero at each CR, so the log appears to contain only a header line. Two
        // separate layers hide the same cause.
        //
        // `Character.isNewline` is true for LF, CR and the CRLF cluster alike,
        // which is why it is correct here and on Linux without a platform test.
        //
        // 以 `isNewline` 切分，絕不使用字面量 "\n"。
        //
        // Swift 將 "\r\n" 視為單一 extended grapheme cluster，因此它是「一個」Character，
        // 且不等於 "\n"。Windows 的 ffmpeg 每行皆以 CRLF 結尾，這表示
        // `split(separator: "\n")` 完全找不到分隔符，會把整段輸出當作單一元素回傳。此時該
        // 集合只含一個 98 位元組的字串、比對不到任何項目，於是 app 在一台提供九種硬體解碼器
        // 的機器上靜默退回軟體解碼。
        //
        // 從兩端看，這都不像是行尾字元的問題。`od -c` 顯示 CR 與 LF 皆存在，因此檔案看起來
        // 完全正常；而印出解析結果時，每個 CR 都會讓終端機游標回到第 0 欄，使日誌看起來只有
        // 一行標題。兩個各自獨立的層面掩蓋了同一個成因。
        //
        // `Character.isNewline` 對 LF、CR 與 CRLF cluster 皆為真，因此它在此處以及 Linux 上
        // 都正確，無需平台判斷。
        let reported = Set(
            (String(data: data, encoding: .utf8) ?? "")
                .split(whereSeparator: \.isNewline)
                .map { String($0.filter { !$0.isWhitespace }) }
        )
        P6v2Diagnostics.write(
            "hwaccels reported \(reported.sorted().joined(separator: ",")) "
                + "(\(data.count) bytes)"
        )
        return preferred.first { reported.contains($0) }
    }

    private static func locateFFmpeg() -> URL? {
        let candidates: [String]
        #if os(Windows)
        candidates = ["C:/ffmpeg/bin/ffmpeg.exe", "C:/Program Files/ffmpeg/bin/ffmpeg.exe"]
        #else
        candidates = ["/usr/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/opt/homebrew/bin/ffmpeg"]
        #endif

        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        // PATH last, because a candidate above is the one a measurement was
        // recorded against; falling back silently to a different ffmpeg build
        // would change the numbers without changing the command.
        // PATH 置於最後，因為上方的候選項目才是量測結果所對應的版本；靜默改用另一個 ffmpeg
        // 建置版本，會在命令完全不變的情況下改變數字。
        guard let pathValue = ProcessInfo.processInfo.environment["PATH"] else { return nil }
        #if os(Windows)
        let separator: Character = ";"
        let executable = "ffmpeg.exe"
        #else
        let separator: Character = ":"
        let executable = "ffmpeg"
        #endif
        for directory in pathValue.split(separator: separator) {
            let candidate = URL(fileURLWithPath: String(directory))
                .appendingPathComponent(executable)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}

enum P6v2Error: Error {
    case ffmpegMissing
    case noInput
    case noHardwareDecoder
}

// MARK: - Audio

/// Audio through a separate ffplay process, the same arrangement P6 uses.
///
/// Not decoded in-process and not mixed with the video path. Audio says nothing
/// about which backend draws faster -- it goes to WASAPI or WSLg identically
/// either way -- so decoding it here would add an SDL dependency and a second
/// buffering model to measure around, for no signal.
///
/// The cost is that sync is not enforced. ffplay reads the file itself and plays
/// at its own rate while the video path paces on its own clock, so at 1x they
/// track well enough to watch and at 3x they do not. That is the honest limit of
/// a two-process design and it is stated rather than hidden: the app reports
/// `audio ffplay` in its status line, and `-mute` turns it off for measurement
/// runs where a second process competing for the disk would be noise.
///
/// 音訊透過獨立的 ffplay 行程處理，與 P6 採用相同的做法。
///
/// 不在行程內解碼，也不與視訊路徑混合。音訊無法說明哪個 backend 繪製較快——兩者最終都同樣
/// 送往 WASAPI 或 WSLg——因此在此解碼只會多出一個 SDL 依賴與第二套緩衝模型需要在量測中排除，
/// 卻換不到任何訊號。
///
/// 代價是不保證同步。ffplay 自行讀取檔案並以自己的速率播放，而視訊路徑依自己的時鐘調速，
/// 因此 1x 時兩者貼合到足以觀看，3x 時則不然。這是雙行程設計的誠實限制，且明白說出而非隱藏：
/// app 會在狀態列回報 `audio ffplay`，而 `-mute` 可在量測執行中關閉它——在那種情況下，
/// 第二個行程爭搶磁碟只會是雜訊。
/// Kills ffplay however the app exits.
///
/// `stop()` on the model covers the Stop button and the `-seconds` timeout, and
/// covers neither of the ways a person actually leaves: closing the window, or
/// Ctrl-C in the terminal. Both end the process without unwinding through the
/// model, and ffplay is a separate process, so it kept playing the clip with no
/// window left to stop it from. P6 had the same defect and fixed it with
/// Darwin signal sources, which is a macOS-only answer.
///
/// `atexit` is the one hook that fires for a normal exit whatever triggered it,
/// including the GTK main loop ending on window close. Signals are handled too,
/// because a signal terminates without running atexit handlers.
///
/// 無論 app 以何種方式結束，都確保 ffplay 被終止。
///
/// model 上的 `stop()` 涵蓋 Stop 按鈕與 `-seconds` 逾時，卻沒有涵蓋任何一種人們實際離開的
/// 方式：關閉視窗，或在終端機按 Ctrl-C。兩者都會在不經過 model 的情況下結束行程，而 ffplay
/// 是獨立行程，於是它會繼續播放，卻已沒有任何視窗可用來停止它。P6 有相同缺陷，並以 Darwin
/// 的訊號來源修正，那是僅適用於 macOS 的解法。
///
/// `atexit` 是唯一在正常結束時必定觸發的鉤子，無論起因為何，包括 GTK main loop 因視窗關閉而
/// 結束。訊號則另外處理，因為訊號會直接終止行程而不執行 atexit handler。
enum P6v2Cleanup {
    nonisolated(unsafe) static var audio: P6v2Audio?
    nonisolated(unsafe) private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true

        atexit {
            P6v2Cleanup.audio?.stop()
            P6v2Cleanup.audio = nil
        }

        for signalNumber in [SIGINT, SIGTERM] {
            signal(signalNumber) { received in
                P6v2Cleanup.audio?.stop()
                P6v2Cleanup.audio = nil
                _exit(128 + received)
            }
        }
    }
}

final class P6v2Audio: @unchecked Sendable {
    private let process = Process()

    init?(input: URL, speed: Double, startSeconds: Double = 0) {
        guard let ffplay = P6v2Audio.locateFFplay() else {
            P6v2Diagnostics.write("ffplay not found, running silent")
            return nil
        }

        var arguments = [
            "-hide_banner",
            "-loglevel", "error",
            "-nodisp",
            "-autoexit",
        ]
        // Before -i, like the decoder's hwaccel. After it, ffplay accepts -ss
        // and seeks by decoding from the start, which for a seek near the end of
        // a clip is a long silent pause rather than an error.
        // 置於 -i 之前，與解碼器的 hwaccel 相同。若置於其後，ffplay 仍會接受 -ss，但會從頭解碼
        // 來達成跳轉；對於接近片尾的跳轉，這表現為一段漫長的無聲等待，而非一則錯誤。
        if startSeconds > 0 {
            arguments += ["-ss", String(format: "%.3f", startSeconds)]
        }
        if let filter = P6v2Audio.atempoChain(for: speed) {
            arguments += ["-af", filter]
        }
        arguments += ["-i", input.path]

        process.executableURL = ffplay
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        guard (try? process.run()) != nil else {
            P6v2Diagnostics.write("ffplay failed to start, running silent")
            return nil
        }
        P6v2Diagnostics.write("ffplay \(arguments.joined(separator: " "))")
    }

    /// `atempo` accepts 0.5 to 2.0 per instance, so anything faster has to be
    /// chained. Passing 3 directly is rejected by ffmpeg and the process exits
    /// immediately, which presents as "no sound" rather than as an error.
    /// 每個 `atempo` 實例僅接受 0.5 至 2.0，因此更快的速度必須串接。直接傳入 3 會被 ffmpeg
    /// 拒絕、行程立即結束，而其表現是「沒有聲音」而非一則錯誤訊息。
    private static func atempoChain(for speed: Double) -> String? {
        switch speed {
            case 2: "atempo=2.0"
            case 3: "atempo=1.5,atempo=2.0"
            default: nil
        }
    }

    func stop() {
        if process.isRunning { process.terminate() }
    }

    private static func locateFFplay() -> URL? {
        #if os(Windows)
        let executable = "ffplay.exe"
        let separator: Character = ";"
        #else
        let executable = "ffplay"
        let separator: Character = ":"
        #endif

        guard let pathValue = ProcessInfo.processInfo.environment["PATH"] else { return nil }
        for directory in pathValue.split(separator: separator) {
            let candidate = URL(fileURLWithPath: String(directory))
                .appendingPathComponent(executable)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}

// MARK: - Surface

/// Holds the GL view so the decode side can reach it without the view
/// hierarchy owning the decoder or the other way round.
///
/// A box rather than a `@Published` frame. Publishing the frame would push
/// every decoded frame through the view graph, which for 60 frames a second of
/// 1080p means the diffing machinery runs on a 3 MB value it cannot do anything
/// useful with. The GL view wants the bytes, not a state change.
///
/// 持有 GL view，使解碼端能觸及它，而不必讓視圖樹擁有解碼器、或反過來。
///
/// 使用 box 而非 `@Published` 的 frame。若改為發布 frame，每一張解碼出的畫面都會被推入
/// view graph；以 1080p、每秒 60 幀計算，這代表 diffing 機制要對一個它無法有效處理的 3 MB
/// 值反覆運作。GL view 需要的是位元組，而非一次狀態變更。
final class P6v2SurfaceBox: @unchecked Sendable {
    @MainActor weak var view: NV12GLView?

    /// Frames handed over but not yet drawn.
    ///
    /// This is back-pressure, and it is why the decode loop can stop rather than
    /// run flat out. Without it the loop read and handed over as fast as the
    /// pipe allowed while the widget drew what it could, and every frame that
    /// arrived before the previous one was drawn simply overwrote it: decode
    /// work, pipe bandwidth and CPU all spent on pictures nobody ever saw.
    ///
    /// Counted here rather than read off the view because the decode thread must
    /// not touch a @MainActor object.
    ///
    /// 已交遞但尚未繪製的幀數。
    ///
    /// 這就是背壓機制，也是解碼迴圈能夠停下來、而非全速空轉的原因。少了它，該迴圈會以管線允許
    /// 的最快速度讀取並交遞，而 widget 只能盡力繪製；任何在前一幀被繪製之前抵達的幀都會直接
    /// 覆蓋它——解碼工作、管線頻寬與 CPU 全都花在沒有任何人看見的畫面上。
    ///
    /// 在此計數而非直接讀取 view，是因為解碼執行緒不得觸碰 @MainActor 物件。
    /// Hands a frame to the widget from the decode thread.
    ///
    /// The widget owns the handover now, through `g_idle_add`, so this class no
    /// longer counts pending frames itself. The counter it used to keep drove a
    /// wait loop that cost 28 ms a frame -- it was measuring congestion in a
    /// queue nothing was draining, not congestion in the widget.
    ///
    /// 由解碼執行緒將一幀交給 widget。
    ///
    /// 交遞現在由 widget 透過 `g_idle_add` 自行負責，因此本類別不再自行計算待處理幀數。它先前
    /// 維護的計數器驅動了一個每幀耗費 28 ms 的等待迴圈——它量到的是「一個無人抽取的佇列」的
    /// 壅塞，而非 widget 的壅塞。
    func submit(y: [UInt8], uv: [UInt8], width: Int, height: Int) {
        viewForSubmission?.submitFrame(y: y, uv: uv, width: width, height: height)
    }

    /// Read without the main-actor hop, because the decode thread has to reach
    /// it. `submitFrame` is nonisolated and thread-safe by construction.
    /// 不經 main actor 轉場即可讀取，因為解碼執行緒必須觸及它。`submitFrame` 為 nonisolated，
    /// 且其設計本身即為執行緒安全。
    nonisolated(unsafe) var viewForSubmission: NV12GLView?
}

/// Wraps `NV12GLView` so it can sit in a SwiftCrossUI hierarchy.
/// 包裝 `NV12GLView`，使其能置於 SwiftCrossUI 的視圖樹中。
struct P6v2VideoView: GtkWidgetRepresentable {
    var box: P6v2SurfaceBox
    var width: Double
    var height: Double

    func makeGtkWidget(context: Context) -> NV12GLView {
        let view = NV12GLView()
        box.view = view
        box.viewForSubmission = view
        return view
    }

    func updateGtkWidget(_ gtkWidget: NV12GLView, context: Context) {
        box.view = gtkWidget
        box.viewForSubmission = gtkWidget
    }

    /// Fixed, not the natural size. A `GtkGLArea` that has never rendered
    /// reports a natural size of essentially nothing, and the default
    /// implementation would then lay it out at 10x10 -- a working GL path that
    /// looks like a blank window.
    /// 使用固定尺寸而非自然尺寸。從未算繪過的 `GtkGLArea` 回報的自然尺寸幾乎為零，此時預設
    /// 實作會把它排版成 10x10——一條運作正常的 GL 路徑，看起來卻像一個空白視窗。
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        gtkWidget: NV12GLView,
        context: Context
    ) -> ViewSize {
        ViewSize(width, height)
    }
}

// MARK: - Model

final class P6v2Model: SwiftCrossUI.ObservableObject {
    let surfaceBox = P6v2SurfaceBox()

    @SwiftCrossUI.Published var status = "Idle"
    @SwiftCrossUI.Published var isPlaying = false
    @SwiftCrossUI.Published var fpsText = "-- fps"
    @SwiftCrossUI.Published var dropText = "0 dropped/sec"
    @SwiftCrossUI.Published var speedSelection: String? = P6v2Flags.speed
    @SwiftCrossUI.Published var fpsSelection: String? = P6v2Flags.fps
    @SwiftCrossUI.Published var resolutionSelection: String? = P6v2Flags.resolution

    /// Matches P6's `--frame-drop`, which defaults to off there too.
    ///
    /// With it off nothing is ever skipped: a decoder that cannot keep up shows
    /// every frame and reports a lower rate, which is the honest reading of what
    /// the pipe can carry. With it on, frames that arrive faster than they can
    /// be drawn are discarded to hold the target rate, and `dropped/sec` becomes
    /// the number worth watching. Comparing a run with it on against one with it
    /// off compares two different questions.
    ///
    /// 對應 P6 的 `--frame-drop`，該處預設同樣為關閉。
    ///
    /// 關閉時不會略過任何一幀：跟不上的解碼器會顯示每一幀並回報較低的速率，而那正是「管線能
    /// 承載多少」的誠實讀數。開啟時，到達速度快於可繪製速度的幀會被丟棄以維持目標速率，此時
    /// `dropped/sec` 才是值得關注的數字。把開啟的執行與關閉的執行相比，比較的是兩個不同的問題。
    @SwiftCrossUI.Published var frameDropEnabled = P6v2Flags.isFrameDropEnabled

    /// The remaining P6 controls, kept to the same names and defaults so a
    /// person moving between the two apps is not learning a second vocabulary.
    /// 其餘的 P6 控制項，維持相同的名稱與預設值，使在兩支 app 之間切換的人不必再學一套語彙。
    @SwiftCrossUI.Published var soundEnabled = !P6v2Flags.isMuted
    @SwiftCrossUI.Published var showsResolution = false
    @SwiftCrossUI.Published var seekPosition = 0.0
    @SwiftCrossUI.Published var selectedFileName = "No file chosen"
    @SwiftCrossUI.Published var chosenPath: String? = P6v2Flags.inputPath

    /// Clip length, probed with ffprobe so the seek slider spans the real
    /// duration rather than a guess. Nil until a file is chosen, and the slider
    /// is disabled while it is.
    /// 片長，以 ffprobe 探測，使 seek 滑桿的範圍對應真實長度而非估計值。在選擇檔案之前為 nil，
    /// 此期間滑桿為停用狀態。
    @SwiftCrossUI.Published var duration: Double?

    var seekDescription: String {
        guard let duration else { return "--:-- / --:--" }
        return "\(Self.formatTime(seekPosition)) / \(Self.formatTime(duration))"
    }

    var statusDescription: String {
        status
    }

    var resolutionDescription: String {
        let resolution = P6v2Resolution.named(resolutionSelection ?? "1080p")
        return "Output \(resolution.width)x\(resolution.height), "
            + "\(fpsText), \(dropText), decode \(decodePath), present gl-nv12 (GPU)"
    }

    /// The three ways a frame fails to reach the screen, kept apart because
    /// they have different causes and only one of them is a "drop" in P6's
    /// sense.
    ///
    ///   shortfall  the target rate minus the rate achieved. These frames were
    ///              never produced -- the pipe could not carry them. Not a drop.
    ///   skipped    read in full, then deliberately not drawn to catch up.
    ///              Only ever non-zero with Frame drop on.
    ///   overwritten  handed to the GL view and replaced before it drew them.
    ///              This was invisible until it was counted, and it is the one
    ///              that explains "52 fps with 0 dropped".
    ///
    /// 一幀無法抵達螢幕的三種方式，分開列出，因為它們成因不同，且其中只有一種符合 P6 所謂的
    /// 「掉幀」。
    ///
    ///   shortfall   目標速率減去實際達成的速率。這些幀從未被產生——管線無法承載。不算掉幀。
    ///   skipped     已完整讀取，但為了追上進度而刻意不繪製。僅在 Frame drop 開啟時才可能非零。
    ///   overwritten 已交給 GL view，但在它繪製之前就被取代。這一項在被計數之前完全不可見，
    ///               而它正是「52 fps 卻 0 dropped」的解釋。
    @SwiftCrossUI.Published var frameAccountingText = "no frames yet"

    var rendererLabel: String {
        "gl-nv12 (GPU shader)"
    }

    static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private var decoder: P6v2Decoder?
    /// What decode actually ran as, kept so the summary can state it too. The
    /// status line is overwritten when playback stops.
    /// 解碼實際以何種方式執行，保留下來以便摘要也能陳述。狀態列會在播放停止時被覆寫。
    private var decodePath = "software"
    /// Kept so the decode thread can rebuild the decoder for the CPU fallback
    /// without reaching back into the UI for the flag values.
    /// 保留下來，讓解碼執行緒能為 CPU 回退重建解碼器，而無需回頭向 UI 取得旗標值。
    private var currentInput: URL?
    private var audio: P6v2Audio?
    private var stats = P6v2Stats()
    private var decodeThread: Thread?
    private var shouldStop = false

    /// From `chosenPath`, not the flag directly, so the file dialog and `-i`
    /// feed the same place. Reading the flag here would make a file chosen in
    /// the UI silently ignored.
    /// 取自 `chosenPath` 而非直接讀取旗標，使檔案對話框與 `-i` 進入同一個來源。若在此直接讀取
    /// 旗標，透過 UI 選擇的檔案會被靜默忽略。
    var inputURL: URL? {
        chosenPath.map { URL(fileURLWithPath: $0) }
    }

    var hasInput: Bool { inputURL != nil }

    /// Probes the clip so the seek slider has a real range.
    /// 探測片段長度，使 seek 滑桿具備真實範圍。
    func adoptInput(path: String) {
        chosenPath = path
        selectedFileName = URL(fileURLWithPath: path).lastPathComponent
        seekPosition = 0
        duration = Self.probeDuration(path: path)
        status = duration == nil
            ? "Chosen \(selectedFileName); duration unknown"
            : "Chosen \(selectedFileName), \(Self.formatTime(duration ?? 0))"
        P6v2Diagnostics.write("input \(selectedFileName) duration \(duration ?? -1)")
    }

    private static func probeDuration(path: String) -> Double? {
        #if os(Windows)
        let executable = "ffprobe.exe"
        let separator: Character = ";"
        #else
        let executable = "ffprobe"
        let separator: Character = ":"
        #endif
        guard let pathValue = ProcessInfo.processInfo.environment["PATH"] else { return nil }
        var ffprobe: URL?
        for directory in pathValue.split(separator: separator) {
            let candidate = URL(fileURLWithPath: String(directory))
                .appendingPathComponent(executable)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                ffprobe = candidate
                break
            }
        }
        guard let ffprobe else { return nil }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = ffprobe
        process.arguments = [
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=nw=1:nk=1",
            path,
        ]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()

        // isNewline again, not "\n". ffprobe on Windows ends the line with CRLF,
        // and Swift treats that pair as one Character that is not equal to "\n",
        // so splitting on the literal returns the text with the CR still on it
        // and Double(_:) then yields nil. Same trap as the hwaccel list.
        // 同樣使用 isNewline 而非 "\n"。Windows 上的 ffprobe 以 CRLF 結尾，而 Swift 將該組合
        // 視為單一 Character 且不等於 "\n"，因此以字面量切分會得到仍帶著 CR 的文字，Double(_:)
        // 隨即回傳 nil。與 hwaccel 清單是同一個陷阱。
        return (String(data: data, encoding: .utf8) ?? "")
            .split(whereSeparator: \.isNewline)
            .first
            .map { String($0.filter { !$0.isWhitespace }) }
            .flatMap(Double.init)
    }

    func seek(to seconds: Double) {
        let wasPlaying = isPlaying
        seekPosition = max(0, min(seconds, duration ?? seconds))
        if wasPlaying {
            stop()
            play()
        }
        P6v2Diagnostics.write("seek to \(seekPosition)")
    }

    func nudge(by delta: Double) {
        seek(to: seekPosition + delta)
    }

    /// Starts or stops ffplay without touching the video path, so the toggle
    /// takes effect during playback rather than only at the next start.
    /// 在不影響視訊路徑的情況下啟動或停止 ffplay，使該開關於播放期間即時生效，而非僅在下次
    /// 開始播放時才作用。
    func soundSettingChanged(isEnabled: Bool) {
        guard isPlaying, let input = inputURL else { return }
        if isEnabled {
            guard audio == nil else { return }
            audio = P6v2Audio(
                input: input,
                speed: Self.speedFactor(speedSelection ?? "1x"),
                startSeconds: seekPosition
            )
            P6v2Cleanup.audio = audio
        } else {
            audio?.stop()
            audio = nil
            P6v2Cleanup.audio = nil
        }
    }

    func play() {
        guard !isPlaying else { return }
        guard let input = inputURL else {
            status = "No input. Pass -i <file>."
            return
        }

        let resolution = P6v2Resolution.named(resolutionSelection ?? "1080p")
        let requestedFPS = Int(fpsSelection ?? "60") ?? 60
        let speedFactor = Self.speedFactor(speedSelection ?? "1x")
        currentInput = input

        do {
            decoder = try P6v2Decoder(
                input: input,
                resolution: resolution,
                fps: requestedFPS,
                acceleration: P6v2Flags.acceleration,
                startSeconds: seekPosition,
                speed: speedFactor
            )
        } catch P6v2Error.noHardwareDecoder {
            // -gpu was explicit, so refuse rather than quietly doing the other
            // thing. A forced mode that silently becomes its opposite produces a
            // measurement labelled `gpu` taken on the CPU.
            // 使用者明確指定了 -gpu，因此直接拒絕而非悄悄改做另一件事。一個被強制指定卻靜默
            // 變成其反面的模式，會產生一份標示為 `gpu`、實際卻在 CPU 上取得的量測結果。
            status = "-gpu requested but ffmpeg reports no hardware decoder"
            P6v2Diagnostics.write("no hwaccel available, refusing -gpu")
            return
        } catch {
            status = "ffmpeg not found"
            P6v2Diagnostics.write("ffmpeg missing")
            return
        }

        // The toggle, not the flag. `-mute` sets the toggle's initial value and
        // the toggle decides from then on, so turning sound back on in the UI
        // works even in a run started muted.
        // 依開關而非旗標決定。`-mute` 只設定該開關的初始值，之後一律由開關決定；因此即使是以
        // 靜音啟動的執行，在 UI 中重新開啟聲音仍然有效。
        audio = soundEnabled
            ? P6v2Audio(input: input, speed: speedFactor, startSeconds: seekPosition)
            : nil
        P6v2Cleanup.audio = audio
        let dropEnabled = frameDropEnabled

        stats = P6v2Stats()
        shouldStop = false
        isPlaying = true
        decodePath = decoder?.hardwareAcceleration ?? "software"
        let audioText = P6v2Flags.isMuted ? "muted" : (audio == nil ? "no ffplay" : "ffplay")
        status =
            "Playing \(speedSelection ?? "1x") at \(requestedFPS) fps, \(resolution.rawValue)"
            + " -- decode \(decodePath), present gl-nv12 (GPU), audio \(audioText)"
        P6v2Diagnostics.write(
            "start speed=\(speedSelection ?? "1x") fps=\(requestedFPS)"
                + " res=\(resolution.rawValue) mode=\(P6v2Flags.acceleration.label)"
                + " decode=\(decodePath)"
        )

        // A plain Thread rather than a Task. The decode loop is a tight
        // read-and-pace loop that never awaits, so putting it on the cooperative
        // pool would occupy a pool thread for the whole run.
        // 使用一般的 Thread 而非 Task。解碼迴圈是不含 await 的緊密「讀取並調速」迴圈，若放在
        // 協作式執行緒池上，會在整段執行期間佔住一條池中執行緒。
        let thread = Thread { [weak self] in
            // Read once at start rather than each iteration. Flipping the toggle
            // mid-run would otherwise change what the numbers mean partway
            // through a sample, and the summary has one line for the whole run.
            // 於開始時讀取一次，而非每次迭代都讀。否則在執行途中切換該開關，會使同一份取樣的
            // 前後段數字意義不同，而摘要對整段執行只有一行。
            self?.decodeLoop(
                resolution: resolution,
                fps: requestedFPS,
                speed: speedFactor,
                dropEnabled: dropEnabled
            )
        }
        thread.name = "P6-v2 decode"
        decodeThread = thread
        thread.start()
    }

    func stop() {
        shouldStop = true
        decoder?.stop()
        decoder = nil
        // Stopped explicitly. ffplay outlives its parent otherwise, and a
        // measurement run that exits leaves the clip playing with no window to
        // stop it from.
        // 明確結束。否則 ffplay 會存活得比其父行程久，而一次結束的量測執行會留下仍在播放的
        // 音訊，卻沒有任何視窗可用來停止它。
        audio?.stop()
        audio = nil
        P6v2Cleanup.audio = nil
        isPlaying = false
        // The decode path goes in the summary, not just the status line. A
        // recorded number without the mode that produced it cannot be compared
        // against anything later.
        // 解碼路徑一併寫入摘要，而不只出現在狀態列。一個沒有註明產生模式的數字，日後無法與
        // 任何結果進行比較。
        let summary =
            "mode=\(P6v2Flags.acceleration.label) decode=\(decodePath) present=gl-nv12  "
            + stats.summary
        status = summary
        P6v2Diagnostics.write("SUMMARY \(summary)")
        print("[P6-v2] \(summary)")
    }

    private static func speedFactor(_ label: String) -> Double {
        switch label {
            case "2x": 2
            case "3x": 3
            default: 1
        }
    }

    /// Reads the first frame, retrying on the CPU if a hardware decoder was
    /// chosen and produced nothing.
    ///
    /// This is where the fallback actually lives. `ffmpeg -hwaccels` lists what
    /// was compiled in, not what works: in WSL it reports cuda and vaapi on a
    /// system with no render node at all. Selecting from that list alone gives a
    /// decoder that starts, produces zero frames and leaves a blank window --
    /// which reads as "the backend cannot render" rather than "the hwaccel is
    /// unavailable". The first frame is the only honest test.
    ///
    /// 讀取第一幀，若已選用硬體解碼器卻沒有產出，則改以 CPU 重試。
    ///
    /// 回退機制真正的所在。`ffmpeg -hwaccels` 列出的是編譯時納入的項目，而非實際可用者：在
    /// WSL 上，即使系統完全沒有 render node，它仍會列出 cuda 與 vaapi。僅依該清單選擇，會
    /// 得到一個能啟動、卻產出零幀並留下空白視窗的解碼器——這看起來像是「backend 無法繪製」，
    /// 而非「該 hwaccel 不可用」。第一幀是唯一誠實的測試。
    private func firstFrameWithFallback(resolution: P6v2Resolution, fps: Int) -> Data? {
        if let frame = decoder?.readFrame() { return frame }

        guard P6v2Flags.acceleration == .auto,
            decoder?.hardwareAcceleration != nil,
            let input = currentInput
        else { return nil }

        let failed = decoder?.hardwareAcceleration ?? "?"
        decoder?.stop()
        decoder = try? P6v2Decoder(
            input: input,
            resolution: resolution,
            fps: fps,
            acceleration: .forceCPU
        )
        P6v2Diagnostics.write("hwaccel \(failed) produced no frames, fell back to software")

        let path = "software (\(failed) failed)"
        DispatchQueue.main.async { [weak self] in
            self?.decodePath = path
            self?.status = "Fell back to software decode: \(failed) produced no frames"
        }
        return decoder?.readFrame()
    }

    private func decodeLoop(
        resolution: P6v2Resolution,
        fps: Int,
        speed: Double,
        dropEnabled: Bool
    ) {
        // The pace we are trying to hold. 60 fps at 3x means presenting 180
        // frames per second, which is the stress the flag combination is for.
        // 我們嘗試維持的節奏。60 fps 於 3x 表示每秒需呈現 180 幀，而這正是該旗標組合所要
        // 施加的壓力。
        let targetInterval = 1.0 / (Double(fps) * speed)
        // The rate actually being asked for. 60 fps at 3x is 180 frames a
        // second, and comparing the achieved rate against 60 there would call a
        // run successful when it is delivering a third of what was requested.
        // 實際被要求的速率。60 fps 於 3x 即為每秒 180 幀；若在該情況下仍以 60 作為比較基準，
        // 會把一次只交付了所要求三分之一的執行判定為成功。
        let targetRate = Int((Double(fps) * speed).rounded())
        var nextDeadline = Date().timeIntervalSince1970
        var isFirstFrame = true

        while !shouldStop {
            // No wait loop here any more.
            //
            // There was one, gated on how many frames the widget had not drawn,
            // and it cost 28 ms per frame against 8.4 ms of actual reading. It
            // was not measuring the widget: the counter it watched was decremented
            // from a `DispatchQueue.main.async` block, and nothing in GtkBackend
            // drains that queue, so it was measuring a queue nobody was serving.
            //
            // The widget throttles itself now. `submitFrame` keeps one slot and
            // counts what it overwrites, so frames the display cannot take are
            // dropped there and reported, instead of being waited for here.
            //
            // 此處已不再有等待迴圈。
            //
            // 先前有一個，以「widget 尚未繪製的幀數」為條件，而它每幀耗費 28 ms，相對於真正讀取
            // 所需的 8.4 ms。它量到的並不是 widget：它所監看的計數器是在
            // `DispatchQueue.main.async` 區塊中遞減的，而 GtkBackend 中沒有任何東西在抽取該佇列，
            // 因此它量的是一個無人服務的佇列。
            //
            // 現在由 widget 自行節流。`submitFrame` 只保留一格並計算其覆蓋次數，因此顯示端來不及
            // 接收的幀會在該處被丟棄並回報，而不是在此空等。
            let readStart = DispatchTime.now().uptimeNanoseconds
            let nextFrame =
                isFirstFrame
                ? firstFrameWithFallback(resolution: resolution, fps: fps)
                : decoder?.readFrame()
            isFirstFrame = false
            guard let data = nextFrame else { break }
            let readEnd = DispatchTime.now().uptimeNanoseconds
            stats.recordRead(nanoseconds: readEnd - readStart)

            nextDeadline += targetInterval
            let now = Date().timeIntervalSince1970
            let readMilliseconds = Double(readEnd - readStart) / 1_000_000
            let isBehind = now > nextDeadline + targetInterval

            // Being behind is not on its own a reason to drop, and treating it as
            // one was wrong in a way that produced a clean-looking wrong answer:
            // 400 dropped, 0 presented, 0.0 fps. If the decoder is slower than the
            // target rate, skipping frames saves nothing -- the frame was already
            // read in full, a pipe cannot be seeked -- and the deficit only grows,
            // so once behind it dropped every remaining frame forever.
            //
            // Dropping is only useful when frames arrive faster than they can be
            // shown. A read that returned well inside the frame budget means the
            // pipe already had the data waiting, which is the case where skipping
            // the conversion and the draw lets us catch up. Otherwise the source
            // is the limit: present the frame and resync, so the achieved rate
            // reported is the one the decoder can actually sustain.
            //
            // 落後本身不構成丟幀的理由，而把它當成理由所犯的錯，產生了一個看起來很乾淨的
            // 錯誤答案：丟棄 400、顯示 0、0.0 fps。若解碼器慢於目標速率，略過幀不會節省
            // 任何東西——該幀早已被完整讀取，且管線無法 seek——而虧欠只會不斷累積，因此
            // 一旦落後，之後每一幀都會被永遠丟棄。
            //
            // 只有當幀的到達速度快於可顯示速度時，丟幀才有意義。若一次讀取在幀預算內就
            // 遠遠完成，代表管線中早已有資料等候，那正是「略過轉換與繪製即可追上」的情況。
            // 否則瓶頸在來源：顯示該幀並重新對時，使回報的實際速率是解碼器真正能維持的速率。
            let sourceIsAhead = readMilliseconds < targetInterval * 1000 * 0.25

            if dropEnabled && isBehind && sourceIsAhead {
                stats.recordDropped()
                continue
            }
            if isBehind {
                nextDeadline = now
            }

            // Split rather than convert. The two planes arrive contiguously in
            // one frame and go to the GPU as two textures; nothing here touches
            // the pixels, which is the point of choosing NV12 in the first
            // place.
            // 只做切分，不做轉換。兩個平面在一幀之內連續排列，並以兩張材質送往 GPU；此處不對
            // 任何像素進行處理，而這正是一開始選擇 NV12 的目的。
            let splitStart = DispatchTime.now().uptimeNanoseconds
            let lumaCount = resolution.lumaByteCount
            let luma = [UInt8](data[..<lumaCount])
            let chroma = [UInt8](data[lumaCount...])
            stats.recordSplit(nanoseconds: DispatchTime.now().uptimeNanoseconds - splitStart)
            stats.recordPresented()

            let rolled = stats.rollWindowIfDue()
            let fpsValue = stats.currentFPS
            let dropValue = stats.currentDropsPerSecond
            let frameWidth = resolution.width
            let frameHeight = resolution.height

            // submitFrame, not DispatchQueue.main.async. The frame goes through
            // g_idle_add, which runs in the loop GTK is actually turning; the
            // dispatch main queue is not drained by anything in GtkBackend and
            // cost 28 ms a frame in waiting.
            // 使用 submitFrame 而非 DispatchQueue.main.async。該幀會經由 g_idle_add 交遞，執行於
            // GTK 真正在運轉的迴圈中；dispatch 的 main queue 在 GtkBackend 中無人抽取，每幀為此
            // 付出 28 ms 的等待。
            surfaceBox.submit(y: luma, uv: chroma, width: frameWidth, height: frameHeight)

            // Only when the one-second window closed, not every frame. This
            // posted 52 blocks a second that did nothing 51 times, and anything
            // competing with GDK's redraw timeout at G_PRIORITY_HIGH_IDLE + 20
            // delays it -- the frame clock is a timeout, not a hardware
            // interrupt, so it only fires when the loop gets to it.
            // 僅在一秒的取樣視窗結束時執行，而非每一幀。先前這裡每秒投遞 52 個區塊，其中 51 次
            // 什麼都不做；而任何與 GDK 位於 G_PRIORITY_HIGH_IDLE + 20 的重繪 timeout 競爭的東西
            // 都會延遲它——frame clock 是一個 timeout，而非硬體中斷，只有在迴圈輪到它時才會觸發。
            // `if`, not `guard ... else { continue }`. Skipping the rest of the
            // iteration would skip the pacing sleep below and leave the loop
            // spinning flat out.
            // 使用 `if` 而非 `guard ... else { continue }`。跳過該次迭代的其餘部分會連下方的調速
            // sleep 一併跳過，使迴圈全速空轉。
            if rolled {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.fpsText = "\(fpsValue) fps"
                    self.dropText = "\(dropValue) skipped/sec"

                    // Read from the view, which is the only place that knows.
                    // The decode side cannot tell a frame it handed over from a
                    // frame that was drawn.
                    // 由 view 讀取，因為只有它知道。解碼端無法區分「已交遞的幀」與
                    // 「已繪製的幀」。
                    let accepted = self.surfaceBox.view?.framesAccepted ?? 0
                    let rendered = self.surfaceBox.view?.framesRendered ?? 0
                    let overwritten = self.surfaceBox.view?.framesOverwritten ?? 0
                    let shortfall = max(0, targetRate - fpsValue)
                    self.frameAccountingText =
                        "target \(targetRate)/s, shown \(fpsValue)/s"
                        + " — short \(shortfall) (never produced),"
                        + " skipped \(dropValue) (deliberate),"
                        + " overwritten \(overwritten) (handed over, never drawn)"
                    let uploadMs =
                        Double(self.surfaceBox.view?.lastUploadNanoseconds ?? 0) / 1_000_000
                    P6v2Diagnostics.write(
                        "fps=\(fpsValue) target=\(targetRate) skipped/sec=\(dropValue)"
                            + " accepted=\(accepted) rendered=\(rendered)"
                            + " overwritten=\(overwritten)"
                            + " inbox-discarded=\(self.surfaceBox.view?.framesDiscardedInInbox ?? 0)"
                            + " ticks=\(self.surfaceBox.view?.tickCallbacks ?? 0)"
                            + " render-callbacks=\(self.surfaceBox.view?.renderCallbacks ?? 0)"
                            + String(format: " upload=%.2fms", uploadMs)
                            + " | " + self.stats.phaseBreakdown
                    )
                }
            }

            if now < nextDeadline {
                Thread.sleep(forTimeInterval: nextDeadline - now)
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.stop()
        }
    }
}

// MARK: - View

@main
@HotReloadable
struct P6v2App: App {
    var body: some Scene {
        WindowGroup("P6-v2 GTK playback") {
            #hotReloadable {
                P6v2RootView()
            }
        }
        // 800, not 760. At 760 the content needs 733 and the window's content
        // area is 721, and GTK says so once per run:
        //   Allocation height too small. Tried to allocate 1040x721, but
        //   GtkFixed needs at least 1040x733.
        // That is this app declaring a window 12px too short for what it packs
        // into it, not a backend fault, so it is fixed here rather than by
        // making the backend grow windows behind the app's back.
        // 使用 800 而非 760。在 760 時內容需要 733，而視窗的內容區域為 721，GTK 會於每次執行
        // 回報一次（如上）。那是本 app 宣告的視窗比它自己塞入的內容矮了 12px，並非 backend
        // 的缺陷，因此在此修正，而不是讓 backend 在 app 不知情的情況下自行放大視窗。
        .defaultSize(width: 1040, height: 800)
    }
}

struct P6v2RootView: View {
    // @State, not @ObservedObject. SwiftCrossUI has no ObservedObject -- @State
    // handles observable objects too, and P6 declares its model the same way.
    // 使用 @State 而非 @ObservedObject。SwiftCrossUI 並沒有 ObservedObject——@State 同樣
    //能處理 observable object，P6 也是以相同方式宣告其 model。
    @State var player = P6v2Model()

    // An environment action, not a free function. `chooseFile` is provided
    // through the environment by the backend that supports file dialogs; calling
    // it as a global gives `argument passed to call that takes no arguments`,
    // because the name then resolves to something else entirely.
    // 這是 environment action，而非自由函式。`chooseFile` 由支援檔案對話框的 backend 透過
    // environment 提供；若當成全域函式呼叫，會得到
    // `argument passed to call that takes no arguments`，因為該名稱此時解析到了完全不同的東西。
    @Environment(\.chooseFile) var chooseFile

    let speedOptions = ["1x", "2x", "3x"]
    let fpsOptions = ["30", "45", "60"]
    let resolutionOptions = P6v2Resolution.allCases.map(\.rawValue)

    var body: some View {
        // Laid out to match P6 control for control, in the same order, with the
        // same labels and the same disabled rules. The point of P6-v2 is a
        // side-by-side comparison, and a different arrangement makes a reader
        // hunt for the equivalent instead of looking at the difference.
        // 逐項對應 P6 的控制項編排：相同順序、相同標籤、相同的停用規則。P6-v2 的目的是並排
        // 比較，若採用不同的排列方式，讀者會忙於尋找對應項目，而非直接觀察差異。
        VStack(alignment: .leading, spacing: 10) {
            Group {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("P6-v2: GTK stream player")
                            .font(.system(size: 18))
                        Text(player.selectedFileName)
                        Text("Renderer: \(player.rendererLabel)")
                    }

                    Button("Choose file") { presentFileChooser() }
                }

                Slider(value: player.$seekPosition, in: 0...max(player.duration ?? 1, 1))
                    .frame(width: 960)
                Text("Seek target: \(player.seekDescription)")
            }

            Group {
                HStack(spacing: 6) {
                    Button("-5s") { player.nudge(by: -5) }
                        .disabled(!player.hasInput)

                    Button(player.isPlaying ? "Stop" : "Play") {
                        if player.isPlaying { player.stop() } else { player.play() }
                    }
                    .disabled(!player.hasInput)

                    Button("+5s") { player.nudge(by: 5) }
                        .disabled(!player.hasInput)

                    Button("Seek") { player.seek(to: player.seekPosition) }
                        .disabled(!player.hasInput)

                    Text("Speed")
                    Picker(of: speedOptions, selection: player.$speedSelection)
                        .pickerStyle(.menu)
                        .frame(width: 76)

                    Text("FPS")
                    Picker(of: fpsOptions, selection: player.$fpsSelection)
                        .pickerStyle(.menu)
                        .frame(width: 76)

                    Text("Resolution")
                    Picker(of: resolutionOptions, selection: player.$resolutionSelection)
                        .pickerStyle(.menu)
                        .frame(width: 96)
                }

                HStack(spacing: 6) {
                    Toggle(
                        "Sound",
                        isOn: player.$soundEnabled.onChange { isEnabled in
                            player.soundSettingChanged(isEnabled: isEnabled)
                        }
                    )
                    .toggleStyle(.button)
                    .disabled(!player.hasInput)

                    Toggle("Frame drop", isOn: player.$frameDropEnabled)
                        .toggleStyle(.button)

                    Toggle("Show resolution", isOn: player.$showsResolution)
                        .toggleStyle(.button)
                        .disabled(!player.hasInput)

                    Text(player.fpsText)
                    Text(player.dropText)
                }
            }

            // Fixed presentation size so a resolution change alters how much is
            // decoded and pushed, not how large the window is. Comparing two
            // backends at different window sizes would measure the window.
            // 固定呈現尺寸，使解析度變更改變的是解碼與推送的資料量，而非視窗大小。若在不同
            // 視窗尺寸下比較兩個 backend，量到的會是視窗本身。
            // Always present, not swapped for a placeholder. A GtkGLArea that is
            // created and destroyed as frames come and go loses its GL context
            // and its compiled shader with it, so the first frame after every
            // gap pays for a recompile.
            // 始終存在，不與佔位視圖互換。若 GtkGLArea 隨著畫面有無而反覆建立與銷毀，它會連同
            // GL context 一併失去已編譯的 shader，使每次中斷後的第一幀都要付出重新編譯的代價。
            P6v2VideoView(box: player.surfaceBox, width: 960, height: 540)

            Text(player.statusDescription)

            // Always shown, not behind the toggle. This line is the answer to
            // "is it really 60 fps with nothing dropped", and hiding it behind a
            // switch is how "0 dropped" got believed in the first place.
            // 一律顯示，不置於開關之後。這一行正是「它真的是 60 fps 且沒有掉幀嗎」的答案；把它
            // 藏在開關後面，正是「0 dropped」最初被採信的原因。
            Text(player.frameAccountingText)

            if player.showsResolution {
                Text(player.resolutionDescription)
            }
        }
        .padding(16)
        .onAppear {
            P6v2Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            P6v2Diagnostics.renderComplete()

            // Installed before anything can start ffplay. Registering it later
            // leaves a window where a crash or a close orphans the audio
            // process, which is the defect this exists to prevent.
            // 於任何可能啟動 ffplay 的動作之前安裝。若延後註冊，會留下一段空窗期，此期間的崩潰
            // 或關閉都會遺留孤兒音訊行程，而那正是此機制要防止的缺陷。
            P6v2Cleanup.install()

            if let path = P6v2Flags.inputPath {
                player.adoptInput(path: path)
            }
            if P6v2Flags.autoplay { player.play() }

            if let seconds = P6v2Flags.runSeconds {
                DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                    player.stop()
                    exit(0)
                }
            }
        }
    }

    /// Opens the file dialog and adopts the choice.
    ///
    /// Not named `chooseFile`: that is the environment action this calls, and
    /// having both gives `invalid redeclaration of 'chooseFile()'`.
    /// 不命名為 `chooseFile`：那是本方法所呼叫的 environment action，兩者同名會導致
    /// `invalid redeclaration of 'chooseFile()'`。
    private func presentFileChooser() {
        // `chooseFile`, the same free function P6 calls. This is the GtkFileDialog
        // path since the migration off the deprecated GtkFileChooserNative, and
        // P6-v2 exercising it on Windows is worth having: the original bug was a
        // dialog that would not close, and it was Wayland-only.
        // 使用 `chooseFile`，即 P6 所呼叫的同一個自由函式。自從自已淘汰的 GtkFileChooserNative
        // 遷移之後，這條路徑即為 GtkFileDialog；而讓 P6-v2 在 Windows 上實際走過它是有價值的：
        // 最初的缺陷是對話框無法關閉，且僅出現在 Wayland。
        Task {
            guard let file = await chooseFile(
                title: "Choose MP4, WebM, or Y4M stream",
                defaultButtonLabel: "Open",
                allowSelectingFiles: true,
                allowSelectingDirectories: false
            ) else {
                return
            }
            player.adoptInput(path: file.path)
        }
    }
}
