import DefaultBackend
import Foundation
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
// What it deliberately drops is audio. Audio is orthogonal to which backend
// draws the frames, and SDL would be a large dependency for something that
// cannot differentiate the two.
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
// 刻意捨棄的是音訊。音訊與「由哪個 backend 繪製畫面」無關，而 SDL 對於一個無法區分兩者的
// 目的而言是過大的依賴。
//
// Whether GTK itself renders on the GPU is not measured in here, because the app
// cannot see it. Ask GTK directly instead:
//     GDK_DEBUG=opengl ./P6-v2.exe
// which on this machine reports `Renderer: AMD Radeon(TM) Graphics`, OpenGL 4.6
// core over native WGL. A software fallback would name llvmpipe or similar.
// GTK 本身是否以 GPU 繪製並未在此量測，因為 app 看不到這項資訊。請直接詢問 GTK：
//     GDK_DEBUG=opengl ./P6-v2.exe
// 在本機上它回報 `Renderer: AMD Radeon(TM) Graphics`，即經由原生 WGL 的 OpenGL 4.6 core。
// 若是軟體回退路徑，則會顯示 llvmpipe 之類的名稱。
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

    static let acceleration: P6v2Acceleration = {
        if CommandLine.arguments.contains("-cpu") { return .forceCPU }
        if CommandLine.arguments.contains("-gpu") { return .forceGPU }
        return .auto
    }()
}

/// Which decoder ffmpeg is asked to use.
///
/// This switches **decode only**. Presentation goes through GdkMemoryTexture in
/// every mode, because the GPU presentation path needs a GtkGLArea binding that
/// does not exist in Sources/Gtk yet. Naming a flag `-gpu` while half the
/// pipeline stays on the CPU is exactly the kind of thing that gets misread six
/// months later, so the app reports the presentation path in its own status line
/// rather than leaving it to be inferred from the flag.
///
/// `.auto` falls back silently in the sense that it does not fail, but never in
/// the sense that it hides what happened -- the mode that actually ran is in the
/// status line and in the summary.
///
/// 決定 ffmpeg 使用哪種解碼器。
///
/// 此旗標**僅切換解碼**。呈現在所有模式下都經由 GdkMemoryTexture，因為 GPU 呈現路徑需要
/// 一個 Sources/Gtk 中尚不存在的 GtkGLArea 綁定。把旗標命名為 `-gpu`、卻讓管線的一半仍留在
/// CPU 上，正是那種六個月後會被誤讀的設計，因此本 app 在自己的狀態列中回報呈現路徑，而不是
/// 留給旗標名稱去暗示。
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

    var frameByteCount: Int { width * height * 4 }

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
        acceleration: P6v2Acceleration
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
        arguments += [
            "-i", input.path,
            "-an", "-sn", "-dn",
            "-vf", "scale=\(resolution.width):\(resolution.height),fps=\(fps)",
            "-pix_fmt", "rgba",
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
final class P6v2Audio: @unchecked Sendable {
    private let process = Process()

    init?(input: URL, speed: Double) {
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

// MARK: - Model

final class P6v2Model: SwiftCrossUI.ObservableObject {
    @SwiftCrossUI.Published var frame: ImageFormats.Image<RGBA>?
    @SwiftCrossUI.Published var status = "Idle"
    @SwiftCrossUI.Published var isPlaying = false
    @SwiftCrossUI.Published var fpsText = "-- fps"
    @SwiftCrossUI.Published var dropText = "0 dropped/sec"
    @SwiftCrossUI.Published var speedSelection: String? = P6v2Flags.speed
    @SwiftCrossUI.Published var fpsSelection: String? = P6v2Flags.fps
    @SwiftCrossUI.Published var resolutionSelection: String? = P6v2Flags.resolution

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

    var inputURL: URL? {
        P6v2Flags.inputPath.map { URL(fileURLWithPath: $0) }
    }

    var hasInput: Bool { inputURL != nil }

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
                acceleration: P6v2Flags.acceleration
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

        audio = P6v2Flags.isMuted ? nil : P6v2Audio(input: input, speed: speedFactor)

        stats = P6v2Stats()
        shouldStop = false
        isPlaying = true
        decodePath = decoder?.hardwareAcceleration ?? "software"
        let audioText = P6v2Flags.isMuted ? "muted" : (audio == nil ? "no ffplay" : "ffplay")
        status =
            "Playing \(speedSelection ?? "1x") at \(requestedFPS) fps, \(resolution.rawValue)"
            + " -- decode \(decodePath), present memory-texture (CPU), audio \(audioText)"
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
            self?.decodeLoop(resolution: resolution, fps: requestedFPS, speed: speedFactor)
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
        isPlaying = false
        // The decode path goes in the summary, not just the status line. A
        // recorded number without the mode that produced it cannot be compared
        // against anything later.
        // 解碼路徑一併寫入摘要，而不只出現在狀態列。一個沒有註明產生模式的數字，日後無法與
        // 任何結果進行比較。
        let summary =
            "mode=\(P6v2Flags.acceleration.label) decode=\(decodePath) present=memory-texture  "
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

    private func decodeLoop(resolution: P6v2Resolution, fps: Int, speed: Double) {
        // The pace we are trying to hold. 60 fps at 3x means presenting 180
        // frames per second, which is the stress the flag combination is for.
        // 我們嘗試維持的節奏。60 fps 於 3x 表示每秒需呈現 180 幀，而這正是該旗標組合所要
        // 施加的壓力。
        let targetInterval = 1.0 / (Double(fps) * speed)
        var nextDeadline = Date().timeIntervalSince1970
        var isFirstFrame = true

        while !shouldStop {
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

            if isBehind && sourceIsAhead {
                stats.recordDropped()
                continue
            }
            if isBehind {
                nextDeadline = now
            }

            let image = ImageFormats.Image<RGBA>(
                width: resolution.width,
                height: resolution.height,
                bytes: Array(data)
            )
            stats.recordPresented()

            let rolled = stats.rollWindowIfDue()
            let fpsValue = stats.currentFPS
            let dropValue = stats.currentDropsPerSecond

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.frame = image
                if rolled {
                    self.fpsText = "\(fpsValue) fps"
                    self.dropText = "\(dropValue) dropped/sec"
                    P6v2Diagnostics.write("fps=\(fpsValue) dropped/sec=\(dropValue)")
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
        .defaultSize(width: 1040, height: 760)
    }
}

struct P6v2RootView: View {
    // @State, not @ObservedObject. SwiftCrossUI has no ObservedObject -- @State
    // handles observable objects too, and P6 declares its model the same way.
    // 使用 @State 而非 @ObservedObject。SwiftCrossUI 並沒有 ObservedObject——@State 同樣
    //能處理 observable object，P6 也是以相同方式宣告其 model。
    @State var player = P6v2Model()

    let speedOptions = ["1x", "2x", "3x"]
    let fpsOptions = ["30", "45", "60"]
    let resolutionOptions = P6v2Resolution.allCases.map(\.rawValue)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("P6-v2: playback on \(String(describing: DefaultBackend.self))")
                .font(.system(size: 18))

            Group {
                HStack(spacing: 8) {
                    Button(player.isPlaying ? "Stop" : "Play") {
                        if player.isPlaying { player.stop() } else { player.play() }
                    }
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

                HStack(spacing: 16) {
                    Text(player.fpsText)
                    Text(player.dropText)
                }
            }

            // Fixed presentation size so a resolution change alters how much is
            // decoded and pushed, not how large the window is. Comparing two
            // backends at different window sizes would measure the window.
            // 固定呈現尺寸，使解析度變更改變的是解碼與推送的資料量，而非視窗大小。若在不同
            // 視窗尺寸下比較兩個 backend，量到的會是視窗本身。
            Group {
                if let frame = player.frame {
                    SwiftCrossUI.Image(frame)
                        .resizable()
                        .frame(width: 960, height: 540)
                } else {
                    Text(player.hasInput ? "Press Play" : "Pass -i <file> to choose a video")
                        .frame(width: 960, height: 540)
                }
            }

            Text(player.status)
        }
        .padding(16)
        .onAppear {
            P6v2Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            P6v2Diagnostics.renderComplete()

            if P6v2Flags.autoplay { player.play() }

            if let seconds = P6v2Flags.runSeconds {
                DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                    player.stop()
                    exit(0)
                }
            }
        }
    }
}
