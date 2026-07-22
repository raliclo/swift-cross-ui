import DefaultBackend
import Foundation
import ImageFormats
import SwiftCrossUI

#if os(macOS)
import AppKit
import AppKitBackend
import Metal
import MetalKit
#endif

// P6 stream player test app:
// - Select MP4, Y4M, or Y4M.ZST input.
// - Decode through FFmpeg; Zstd input is streamed through zstd first.
// - Exercise playback, stop, timeline seek, speed, output FPS, output
//   resolution controls, and audio playback for inputs with audio tracks.
//
// Runtime dependencies: ffmpeg, ffprobe, and (for .zst input) zstd on PATH.
// On macOS, Homebrew and MacPorts tool paths are searched even when PATH is
// minimal.

@main
@HotReloadable
struct P6StreamPlayerApp: App {
    var body: some Scene {
        WindowGroup("P6 stream player") {
            #hotReloadable {
                P6StreamPlayerView()
            }
        }
        .defaultSize(width: 1_060, height: 820)
    }
}

struct P6StreamPlayerView: View {
    @State var player = P6StreamPlayerModel()
    @State var didLoadStartupInput = false

    @Environment(\.chooseFile) var chooseFile

    let speedOptions = ["1x", "2x", "3x"]
    let fpsOptions = ["30", "45", "60"]
    let resolutionOptions = P6OutputResolution.allCases.map(\.label)

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("P6: Zstd stream player")
                        .font(.system(size: 20))

                    Text(player.selectedFileName)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()

                Button("Choose file") {
                    Task {
                        guard let file = await chooseFile(
                            title: "Choose MP4, Y4M, or Y4M.ZST stream",
                            defaultButtonLabel: "Open",
                            initialDirectory: P6StreamPlayerModel.suggestedInputDirectory,
                            allowSelectingFiles: true,
                            allowSelectingDirectories: false
                        ) else {
                            return
                        }
                        player.load(file)
                    }
                }
            }

            ZStack(alignment: .center) {
                Color.black
                    .frame(width: 960, height: 540)

                #if os(macOS)
                if let frame = player.metalFrame {
                    P6MetalVideoView(frame: frame)
                        .frame(width: 960, height: 540)
                } else if player.isLoading {
                    ProgressView("Decoding frame...")
                } else {
                    Text("Choose a stream to begin")
                }
                #else
                if let frame = player.frame {
                    SwiftCrossUI.Image(frame)
                        .resizable()
                        .frame(width: 960, height: 540)
                } else if player.isLoading {
                    ProgressView("Decoding frame...")
                } else {
                    Text("Choose a stream to begin")
                }
                #endif
            }
            .frame(width: 960, height: 540)
            .cornerRadius(4)

            VStack(spacing: 4) {
                Slider(
                    value: player.$seekPosition.onChange { _ in
                        player.seekPositionChanged()
                    },
                    in: 0...player.seekUpperBound
                )
                .frame(width: 960)
                .disabled(!player.hasInput || player.seekUpperBound <= 0)

                HStack {
                    Text("Current: \(player.timeDescription)")
                    Spacer()
                    Text("Seek target: \(player.seekDescription)")
                }
                .frame(width: 960)
            }

            HStack(spacing: 10) {
                Text(player.progressDescription)
                    .frame(width: 132, alignment: .leading)

                Spacer()

                Button("-5s") {
                    player.seek(by: -5)
                }
                .disabled(!player.hasInput || player.isLoading)

                Button(player.isPlaying || player.isLoading ? "Stop" : "Play") {
                    if player.isPlaying || player.isLoading {
                        player.stop()
                    } else {
                        player.play()
                    }
                }
                .disabled(!player.hasInput)

                Button("+5s") {
                    player.seek(by: 5)
                }
                .disabled(!player.hasInput || player.isLoading)

                Button("Seek") {
                    player.seek(to: player.seekPosition, shouldPlay: player.isPlaying)
                }
                .disabled(!player.hasInput || player.isLoading)

                Text("Speed")
                Picker(
                    of: speedOptions,
                    selection: player.$speedSelection.onChange { _ in
                        player.playbackSettingsChanged()
                    }
                )
                .pickerStyle(.menu)
                .frame(width: 84)

                Text("FPS")
                Picker(
                    of: fpsOptions,
                    selection: player.$fpsSelection.onChange { _ in
                        player.playbackSettingsChanged()
                    }
                )
                .pickerStyle(.menu)
                .frame(width: 84)

                Text("Resolution")
                Picker(
                    of: resolutionOptions,
                    selection: player.$resolutionSelection.onChange { _ in
                        player.playbackSettingsChanged()
                    }
                )
                .pickerStyle(.menu)
                .frame(width: 142)

                Button(player.soundEnabled ? "Sound on" : "Sound off") {
                    player.toggleSound()
                }
                .disabled(!player.hasInput)

                Button("Show resolution") {
                    player.displayResolution()
                }
                .disabled(!player.hasInput)
            }
            .frame(width: 960)

            Text(player.status)
                .frame(width: 960, alignment: .leading)
        }
        .padding(18)
        .onAppear {
            guard !didLoadStartupInput else { return }
            didLoadStartupInput = true

            if let inputPath = CommandLine.arguments.dropFirst().first(where: {
                !$0.hasPrefix("--")
            }) {
                player.load(URL(fileURLWithPath: inputPath))
            }
        }
        .onDisappear {
            player.shutdown()
        }
    }
}

@MainActor
final class P6StreamPlayerModel: SwiftCrossUI.ObservableObject {
    static var suggestedInputDirectory: URL? {
        for projectName in ["LZFSE2", "lzfse2"] {
            let candidate = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("proj")
                .appendingPathComponent(projectName)
                .appendingPathComponent("swift_tar")
                .appendingPathComponent("images")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    @SwiftCrossUI.Published
    var frame: ImageFormats.Image<RGBA>?

    #if os(macOS)
    @SwiftCrossUI.Published
    var metalFrame: P6MetalFrame?
    #endif

    @SwiftCrossUI.Published
    var selectedURL: URL?

    @SwiftCrossUI.Published
    var currentTime: Double = 0

    @SwiftCrossUI.Published
    var seekPosition: Double = 0

    @SwiftCrossUI.Published
    var duration: Double?

    @SwiftCrossUI.Published
    var isPlaying = false

    @SwiftCrossUI.Published
    var isLoading = false

    @SwiftCrossUI.Published
    var status = "Ready. ffmpeg, ffprobe, and zstd are searched on PATH plus platform tool directories."

    @SwiftCrossUI.Published
    var speedSelection: String? = "1x"

    @SwiftCrossUI.Published
    var fpsSelection: String? = "60"

    @SwiftCrossUI.Published
    var resolutionSelection: String? = P6OutputResolution.preview.label

    @SwiftCrossUI.Published
    var soundEnabled = true

    @SwiftCrossUI.Published
    var detectedInputResolution: SIMD2<Int>?

    private var generation = 0
    private var frameSerial = 0
    private var playbackTask: Task<Void, Never>?
    private var decoderSession: P6DecoderSession?
    private var audioSession: P6AudioSession?

    var hasInput: Bool { selectedURL != nil }

    var selectedFileName: String {
        selectedURL?.lastPathComponent ?? "No file selected"
    }

    var speed: Double {
        switch speedSelection {
            case "2x": 2
            case "3x": 3
            default: 1
        }
    }

    var framesPerSecond: Int {
        switch fpsSelection {
            case "30": 30
            case "45": 45
            default: 60
        }
    }

    var outputResolution: P6OutputResolution {
        P6OutputResolution(label: resolutionSelection)
    }

    var progress: Double? {
        guard let duration, duration > 0 else { return nil }
        return min(1, max(0, currentTime / duration))
    }

    var seekUpperBound: Double {
        duration.map { max(0, $0) } ?? max(1, currentTime)
    }

    var timeDescription: String {
        let elapsed = Self.formatTime(currentTime)
        guard let duration else { return "\(elapsed) / --:--" }
        return "\(elapsed) / \(Self.formatTime(duration))"
    }

    var seekDescription: String {
        guard duration != nil else { return "--:--" }
        return Self.formatTime(seekPosition)
    }

    var progressDescription: String {
        guard let progress else { return "--%" }
        return "\(Int((progress * 100).rounded()))%"
    }

    func load(_ url: URL) {
        P6Diagnostics.write("load \(url.path)")
        selectedURL = url
        currentTime = 0
        seekPosition = 0
        duration = nil
        detectedInputResolution = nil
        frame = nil
        #if os(macOS)
        metalFrame = nil
        #endif
        startDecoder(at: 0, shouldPlay: false, singleFrame: true)
    }

    func play() {
        guard selectedURL != nil else { return }
        if let duration, currentTime >= duration {
            currentTime = 0
            seekPosition = 0
        }
        startDecoder(at: currentTime, shouldPlay: true, singleFrame: false)
    }

    func stop() {
        invalidateCurrentDecoder()
        isPlaying = false
        isLoading = false
        status = "Stopped at \(Self.formatTime(currentTime))."
    }

    func seek(by offset: Double) {
        guard selectedURL != nil else { return }
        let target = clampedSeekTime(currentTime + offset)
        seek(to: target, shouldPlay: isPlaying)
    }

    func seek(to target: Double, shouldPlay: Bool) {
        guard selectedURL != nil else { return }
        let clampedTarget = clampedSeekTime(target)
        seekPosition = clampedTarget
        startDecoder(at: clampedTarget, shouldPlay: shouldPlay, singleFrame: !shouldPlay)
    }

    func seekPositionChanged() {
        guard selectedURL != nil else { return }
        seekPosition = clampedSeekTime(seekPosition)
        if !isPlaying && !isLoading {
            status = "Seek target set to \(Self.formatTime(seekPosition))."
        }
    }

    func playbackSettingsChanged() {
        guard selectedURL != nil else { return }
        let resolution = outputResolution
        let suffix = isPlaying
            ? " Stop and play, or seek, to apply to the decoder."
            : " Press Play or Seek to apply."
        status = "Selected \(speedSelection ?? "1x"), \(framesPerSecond) FPS, \(resolution.label).\(suffix)"
    }

    func toggleSound() {
        soundEnabled.toggle()
        if !soundEnabled {
            audioSession?.terminate()
            audioSession = nil
            status = "Sound disabled."
        } else {
            status = "Sound enabled. Audio starts on Play for inputs with audio tracks."
            if isPlaying {
                restartAudio(at: currentTime)
            }
        }
    }

    func displayResolution() {
        guard let selectedURL else { return }
        let inputResolution = detectedInputResolution ?? P6MediaProbe.resolution(for: selectedURL)
        detectedInputResolution = inputResolution
        let inputText = inputResolution
            .map { "\($0.x)x\($0.y)" } ?? "unknown"
        let output = outputResolution
        status = "Input resolution: \(inputText). Output resolution: \(output.width)x\(output.height). Viewport: 960x540."
    }

    func shutdown() {
        invalidateCurrentDecoder()
        isPlaying = false
        isLoading = false
    }

    private func startDecoder(at startTime: Double, shouldPlay: Bool, singleFrame: Bool) {
        guard let selectedURL else { return }

        invalidateCurrentDecoder()
        currentTime = max(0, startTime)
        seekPosition = currentTime
        isPlaying = shouldPlay
        isLoading = true
        status = singleFrame ? "Seeking to \(Self.formatTime(currentTime))..." : "Starting playback..."

        let token = generation
        let requestedSpeed = speed
        let requestedFPS = framesPerSecond
        let requestedResolution = outputResolution
        let knownDuration = duration

        playbackTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            do {
                if knownDuration == nil,
                   let probedDuration = P6MediaProbe.duration(for: selectedURL)
                {
                    await self.acceptDuration(probedDuration, token: token)
                }

                let session = try P6DecoderSession(
                    inputURL: selectedURL,
                    startTime: startTime,
                    speed: requestedSpeed,
                    framesPerSecond: requestedFPS,
                    outputResolution: requestedResolution
                )

                guard await self.install(session, token: token) else {
                    session.terminate()
                    return
                }

                if shouldPlay {
                    await self.startAudioIfNeeded(at: startTime, token: token)
                }

                var position = startTime
                var previousFrame: Data?
                let displayInterval = 1 / Double(requestedFPS)
                let sourceAdvance = requestedSpeed / Double(requestedFPS)

                while !Task.isCancelled {
                    let iterationStart = Date()
                    guard let frameData = try session.readFrame() else {
                        await self.finish(token: token, reachedEnd: true, error: nil)
                        return
                    }

                    var rawFrame: Data?
                    var image: ImageFormats.Image<RGBA>?
                    if previousFrame == frameData {
                        rawFrame = nil
                        image = nil
                    } else {
                        #if os(macOS)
                        rawFrame = frameData
                        image = nil
                        #else
                        rawFrame = nil
                        image = ImageFormats.Image(
                            width: requestedResolution.width,
                            height: requestedResolution.height,
                            bytes: Array(frameData)
                        )
                        #endif
                        previousFrame = frameData
                    }

                    await self.acceptFrame(
                        image,
                        rawFrame: rawFrame,
                        at: position,
                        resolution: requestedResolution,
                        token: token
                    )

                    if singleFrame {
                        session.terminate()
                        await self.finish(token: token, reachedEnd: false, error: nil)
                        return
                    }

                    position += sourceAdvance
                    let elapsed = Date().timeIntervalSince(iterationStart)
                    let remaining = displayInterval - elapsed
                    if remaining > 0 {
                        try await Task.sleep(
                            nanoseconds: UInt64(remaining * 1_000_000_000)
                        )
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                await self.finish(
                    token: token,
                    reachedEnd: false,
                    error: error.localizedDescription
                )
            }
        }
    }

    private func invalidateCurrentDecoder() {
        generation &+= 1
        decoderSession?.terminate()
        decoderSession = nil
        audioSession?.terminate()
        audioSession = nil
        playbackTask?.cancel()
        playbackTask = nil
    }

    private func install(_ session: P6DecoderSession, token: Int) -> Bool {
        guard generation == token else { return false }
        decoderSession = session
        return true
    }

    private func acceptDuration(_ value: Double, token: Int) {
        guard generation == token else { return }
        duration = value
        seekPosition = min(seekPosition, value)
    }

    private func acceptFrame(
        _ image: ImageFormats.Image<RGBA>?,
        rawFrame: Data?,
        at position: Double,
        resolution: P6OutputResolution,
        token: Int
    ) {
        guard generation == token else { return }
        #if os(macOS)
        if let rawFrame {
            frameSerial &+= 1
            metalFrame = P6MetalFrame(
                width: resolution.width,
                height: resolution.height,
                rgbaBytes: rawFrame,
                serial: frameSerial
            )
            P6Diagnostics.write(
                "metal frame \(Self.formatTime(position)) \(resolution.width)x\(resolution.height)"
            )
        }
        #else
        if let image {
            frame = image
            P6Diagnostics.write(
                "frame \(Self.formatTime(position)) \(resolution.width)x\(resolution.height)"
            )
        }
        #endif
        currentTime = position
        if isPlaying || abs(seekPosition - position) < 0.5 {
            seekPosition = position
        }
        isLoading = false
        status = isPlaying
            ? "Playing \(speedSelection ?? "1x") at \(framesPerSecond) FPS, \(resolution.label). \(audioStatusText)"
            : "Frame ready at \(Self.formatTime(position))."
    }

    private func finish(token: Int, reachedEnd: Bool, error: String?) {
        guard generation == token else { return }
        decoderSession?.terminate()
        decoderSession = nil
        playbackTask = nil
        isPlaying = false
        isLoading = false

        if let error {
            status = "Playback failed: \(error)"
            P6Diagnostics.write(status)
        } else if reachedEnd {
            if duration == nil {
                duration = currentTime
            }
            status = "End of stream."
            P6Diagnostics.write(status)
        } else {
            status = "Frame ready at \(Self.formatTime(currentTime))."
            P6Diagnostics.write(status)
        }
    }

    private var audioStatusText: String {
        guard soundEnabled else { return "Sound off." }
        guard audioSession != nil else { return "Video-only or ffplay unavailable." }
        return "Sound on."
    }

    private func clampedSeekTime(_ time: Double) -> Double {
        let lowerBound = max(0, time)
        if let duration {
            let upperBound = max(0, duration - 1 / Double(framesPerSecond))
            return min(upperBound, lowerBound)
        }
        return lowerBound
    }

    private func startAudioIfNeeded(at startTime: Double, token: Int) {
        guard generation == token else { return }
        restartAudio(at: startTime)
    }

    private func restartAudio(at startTime: Double) {
        audioSession?.terminate()
        audioSession = nil

        guard soundEnabled, let selectedURL else { return }
        do {
            audioSession = try P6AudioSession(
                inputURL: selectedURL,
                startTime: startTime,
                speed: speed
            )
            P6Diagnostics.write("audio started \(Self.formatTime(startTime))")
        } catch P6PlayerError.unsupportedAudioInput {
            P6Diagnostics.write("audio skipped for \(selectedURL.lastPathComponent)")
        } catch {
            status = "Video playing; audio unavailable: \(error.localizedDescription)"
            P6Diagnostics.write(status)
        }
    }

    private static func formatTime(_ seconds: Double) -> String {
        let safeSeconds = max(0, seconds.isFinite ? seconds : 0)
        let totalSeconds = Int(safeSeconds.rounded(.down))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

#if os(macOS)
struct P6MetalFrame: Sendable, Equatable {
    let width: Int
    let height: Int
    let rgbaBytes: Data
    let serial: Int
}

struct P6MetalVideoView: NSViewRepresentable {
    let frame: P6MetalFrame

    @MainActor
    func makeNSView(context _: Context) -> P6MetalVideoNSView {
        P6MetalVideoNSView(frame: .zero, device: nil)
    }

    @MainActor
    func updateNSView(_ nsView: P6MetalVideoNSView, context _: Context) {
        nsView.update(frame)
    }
}

@MainActor
final class P6MetalVideoNSView: MTKView {
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private var samplerState: MTLSamplerState?
    private var videoTexture: MTLTexture?
    private var lastFrameSerial: Int?

    override init(frame frameRect: NSRect, device: MTLDevice?) {
        let metalDevice = device ?? MTLCreateSystemDefaultDevice()
        super.init(frame: frameRect, device: metalDevice)
        configure()
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        device = MTLCreateSystemDefaultDevice()
        configure()
    }

    func update(_ frame: P6MetalFrame) {
        guard lastFrameSerial != frame.serial else { return }
        lastFrameSerial = frame.serial
        replaceTexture(with: frame)
        draw()
    }

    override func draw(_ dirtyRect: NSRect) {
        renderCurrentTexture()
    }

    private func configure() {
        guard let device else { return }

        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        isPaused = true
        enableSetNeedsDisplay = false
        clearColor = MTLClearColorMake(0, 0, 0, 1)
        commandQueue = device.makeCommandQueue()
        samplerState = makeSampler(device: device)
        pipelineState = makePipeline(device: device)
    }

    private func replaceTexture(with frame: P6MetalFrame) {
        guard let device else { return }

        if videoTexture == nil
            || videoTexture?.width != frame.width
            || videoTexture?.height != frame.height
        {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: frame.width,
                height: frame.height,
                mipmapped: false
            )
            descriptor.usage = [.shaderRead]
            videoTexture = device.makeTexture(descriptor: descriptor)
        }

        guard let videoTexture else { return }
        frame.rgbaBytes.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            videoTexture.replace(
                region: MTLRegionMake2D(0, 0, frame.width, frame.height),
                mipmapLevel: 0,
                withBytes: baseAddress,
                bytesPerRow: frame.width * 4
            )
        }
    }

    private func renderCurrentTexture() {
        guard let commandQueue,
              let pipelineState,
              let samplerState,
              let videoTexture,
              let currentDrawable,
              let descriptor = currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else {
            return
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(videoTexture, index: 0)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        commandBuffer.present(currentDrawable)
        commandBuffer.commit()
    }

    private func makeSampler(device: MTLDevice) -> MTLSamplerState? {
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge
        return device.makeSamplerState(descriptor: descriptor)
    }

    private func makePipeline(device: MTLDevice) -> MTLRenderPipelineState? {
        let source = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut {
            float4 position [[position]];
            float2 texCoord;
        };

        vertex VertexOut vertex_main(uint vertexID [[vertex_id]]) {
            float2 positions[4] = {
                float2(-1.0, -1.0),
                float2( 1.0, -1.0),
                float2(-1.0,  1.0),
                float2( 1.0,  1.0)
            };
            float2 texCoords[4] = {
                float2(0.0, 1.0),
                float2(1.0, 1.0),
                float2(0.0, 0.0),
                float2(1.0, 0.0)
            };

            VertexOut out;
            out.position = float4(positions[vertexID], 0.0, 1.0);
            out.texCoord = texCoords[vertexID];
            return out;
        }

        fragment float4 fragment_main(
            VertexOut in [[stage_in]],
            texture2d<float> imageTexture [[texture(0)]],
            sampler imageSampler [[sampler(0)]]
        ) {
            return imageTexture.sample(imageSampler, in.texCoord);
        }
        """

        do {
            let library = try device.makeLibrary(source: source, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "vertex_main")
            descriptor.fragmentFunction = library.makeFunction(name: "fragment_main")
            descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            P6Diagnostics.write("metal pipeline failed: \(error.localizedDescription)")
            return nil
        }
    }
}
#endif

struct P6OutputResolution: Sendable, Equatable {
    static let preview = P6OutputResolution(label: "Preview 960x540", width: 960, height: 540)
    static let fullHD = P6OutputResolution(label: "1080p 1920x1080", width: 1_920, height: 1_080)
    static let ultraHD = P6OutputResolution(label: "4K 3840x2160", width: 3_840, height: 2_160)

    static let allCases = [preview, fullHD, ultraHD]

    let label: String
    let width: Int
    let height: Int

    init(label: String, width: Int, height: Int) {
        self.label = label
        self.width = width
        self.height = height
    }

    init(label: String?) {
        self = Self.allCases.first { $0.label == label } ?? .preview
    }
}

final class P6DecoderSession: @unchecked Sendable {
    private let ffmpeg: Process
    private let zstd: Process?
    private let outputHandle: FileHandle
    private let frameByteCount: Int
    private let stateLock = NSLock()
    private var terminated = false

    init(
        inputURL: URL,
        startTime: Double,
        speed: Double,
        framesPerSecond: Int,
        outputResolution: P6OutputResolution
    ) throws {
        guard let ffmpegURL = P6ToolLocator.find("ffmpeg") else {
            throw P6PlayerError.missingTool("ffmpeg")
        }

        self.frameByteCount = outputResolution.width * outputResolution.height * 4

        let compressed = inputURL.pathExtension.lowercased() == "zst"
        let outputPipe = Pipe()
        let ffmpeg = Process()
        ffmpeg.executableURL = ffmpegURL
        ffmpeg.standardOutput = outputPipe
        ffmpeg.standardError = FileHandle.standardError

        let seekValue = String(format: "%.6f", max(0, startTime))
        let filter = [
            "setpts=(PTS-STARTPTS)/\(speed)",
            "fps=\(framesPerSecond)",
            "scale=\(outputResolution.width):\(outputResolution.height):force_original_aspect_ratio=decrease:flags=fast_bilinear",
            "pad=\(outputResolution.width):\(outputResolution.height):(ow-iw)/2:(oh-ih)/2:color=black",
        ].joined(separator: ",")

        var arguments = ["-nostdin", "-hide_banner", "-loglevel", "error"]
        var zstdProcess: Process?
        var sourcePipe: Pipe?

        if compressed {
            guard let zstdURL = P6ToolLocator.find("zstd") else {
                throw P6PlayerError.missingTool("zstd")
            }

            let pipe = Pipe()
            sourcePipe = pipe
            ffmpeg.standardInput = pipe
            arguments += ["-f", "yuv4mpegpipe", "-i", "pipe:0"]
            if startTime > 0 {
                arguments += ["-ss", seekValue]
            }

            let process = Process()
            process.executableURL = zstdURL
            process.arguments = ["-q", "-d", "-c", inputURL.path]
            process.standardOutput = pipe
            process.standardError = FileHandle.standardError
            zstdProcess = process
        } else {
            if startTime > 0 {
                arguments += ["-ss", seekValue]
            }
            arguments += ["-i", inputURL.path]
        }

        arguments += [
            "-an", "-sn", "-dn",
            "-vf", filter,
            "-pix_fmt", "rgba",
            "-f", "rawvideo",
            "pipe:1",
        ]
        ffmpeg.arguments = arguments

        do {
            try ffmpeg.run()
            outputPipe.fileHandleForWriting.closeFile()
            sourcePipe?.fileHandleForReading.closeFile()

            if let zstdProcess {
                try zstdProcess.run()
                sourcePipe?.fileHandleForWriting.closeFile()
            }
        } catch {
            if ffmpeg.isRunning {
                ffmpeg.terminate()
            }
            if let zstdProcess, zstdProcess.isRunning {
                zstdProcess.terminate()
            }
            throw error
        }

        self.ffmpeg = ffmpeg
        self.zstd = zstdProcess
        self.outputHandle = outputPipe.fileHandleForReading
    }

    deinit {
        terminate()
    }

    func readFrame() throws -> Data? {
        var data = Data()
        data.reserveCapacity(frameByteCount)

        while data.count < frameByteCount {
            if isTerminated { return nil }
            let remaining = frameByteCount - data.count
            guard let chunk = try outputHandle.read(upToCount: remaining), !chunk.isEmpty else {
                if data.isEmpty { return nil }
                throw P6PlayerError.incompleteFrame(data.count, frameByteCount)
            }
            data.append(chunk)
        }

        return data
    }

    func terminate() {
        stateLock.lock()
        if terminated {
            stateLock.unlock()
            return
        }
        terminated = true
        stateLock.unlock()

        outputHandle.closeFile()
        if ffmpeg.isRunning {
            ffmpeg.terminate()
        }
        if let zstd, zstd.isRunning {
            zstd.terminate()
        }
    }

    private var isTerminated: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return terminated
    }
}

final class P6AudioSession: @unchecked Sendable {
    private let ffplay: Process
    private let stateLock = NSLock()
    private var terminated = false

    init(
        inputURL: URL,
        startTime: Double,
        speed: Double
    ) throws {
        let lowercasedName = inputURL.lastPathComponent.lowercased()
        if lowercasedName.hasSuffix(".zst") || lowercasedName.hasSuffix(".y4m") {
            throw P6PlayerError.unsupportedAudioInput
        }

        guard let ffplayURL = P6ToolLocator.find("ffplay") else {
            throw P6PlayerError.missingTool("ffplay")
        }

        let process = Process()
        process.executableURL = ffplayURL
        process.arguments = [
            "-nodisp",
            "-autoexit",
            "-hide_banner",
            "-loglevel",
            "error",
            "-ss",
            String(format: "%.6f", max(0, startTime)),
            "-i",
            inputURL.path,
            "-vn",
            "-sn",
            "-dn",
            "-af",
            "atempo=\(speed)",
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.standardError

        do {
            try process.run()
        } catch {
            throw error
        }

        ffplay = process
    }

    deinit {
        terminate()
    }

    func terminate() {
        stateLock.lock()
        if terminated {
            stateLock.unlock()
            return
        }
        terminated = true
        stateLock.unlock()

        if ffplay.isRunning {
            ffplay.terminate()
        }
    }
}

enum P6MediaProbe {
    static func duration(for inputURL: URL) -> Double? {
        guard let probeInput = probeInput(for: inputURL),
              let ffprobeURL = P6ToolLocator.find("ffprobe")
        else {
            return nil
        }

        let outputPipe = Pipe()
        let process = Process()
        process.executableURL = ffprobeURL
        process.arguments = [
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            probeInput.path,
        ]
        process.standardOutput = outputPipe
        process.standardError = FileHandle.standardError

        do {
            try process.run()
            outputPipe.fileHandleForWriting.closeFile()
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let value = String(data: data, encoding: .utf8)
                    .flatMap({ Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }),
                  value.isFinite,
                  value > 0
            else {
                return nil
            }
            return value
        } catch {
            return nil
        }
    }

    static func resolution(for inputURL: URL) -> SIMD2<Int>? {
        guard let probeInput = probeInput(for: inputURL),
              let ffprobeURL = P6ToolLocator.find("ffprobe")
        else {
            return nil
        }

        let outputPipe = Pipe()
        let process = Process()
        process.executableURL = ffprobeURL
        process.arguments = [
            "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=width,height",
            "-of", "csv=s=x:p=0",
            probeInput.path,
        ]
        process.standardOutput = outputPipe
        process.standardError = FileHandle.standardError

        do {
            try process.run()
            outputPipe.fileHandleForWriting.closeFile()
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let value = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            else {
                return nil
            }

            let parts = value.split(separator: "x")
            guard parts.count == 2,
                  let width = Int(parts[0]),
                  let height = Int(parts[1]),
                  width > 0,
                  height > 0
            else {
                return nil
            }

            return SIMD2(width, height)
        } catch {
            return nil
        }
    }

    private static func probeInput(for inputURL: URL) -> URL? {
        let name = inputURL.lastPathComponent
        let lowercasedName = name.lowercased()

        if lowercasedName.hasSuffix(".y4m.zst") {
            let baseName = String(name.dropLast(".y4m.zst".count))
            let sibling = inputURL.deletingLastPathComponent()
                .appendingPathComponent("\(baseName).mp4")
            return FileManager.default.fileExists(atPath: sibling.path) ? sibling : nil
        }

        if lowercasedName.hasSuffix(".zst") {
            return nil
        }

        return inputURL
    }
}

enum P6ToolLocator {
    static func find(_ tool: String) -> URL? {
        #if os(Windows)
            let executableName = tool.lowercased().hasSuffix(".exe") ? tool : "\(tool).exe"
            let separator: Character = ";"
        #else
            let executableName = tool
            let separator: Character = ":"
        #endif

        var directories = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: separator)
            .map(String.init) ?? []

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #if os(Windows)
            directories.append("\(home)\\scoop\\shims")
            directories.append("\(home)\\AppData\\Local\\Microsoft\\WinGet\\Links")
        #elseif os(macOS)
            directories += [
                "/opt/homebrew/bin",
                "/usr/local/bin",
                "/opt/local/bin",
                "/usr/bin",
                "/bin",
            ]
        #else
            directories += ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        #endif

        var seen = Set<String>()
        for directory in directories {
            let cleanDirectory = directory.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            guard seen.insert(cleanDirectory).inserted else { continue }
            let candidate = URL(fileURLWithPath: cleanDirectory)
                .appendingPathComponent(executableName)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }
}

enum P6PlayerError: LocalizedError {
    case missingTool(String)
    case incompleteFrame(Int, Int)
    case unsupportedAudioInput

    var errorDescription: String? {
        switch self {
            case .missingTool(let tool):
                return "Required tool '\(tool)' was not found on PATH."
            case .incompleteFrame(let actual, let expected):
                return "Decoder returned an incomplete RGBA frame (\(actual) of \(expected) bytes)."
            case .unsupportedAudioInput:
                return "This input is treated as video-only."
        }
    }
}

enum P6Diagnostics {
    static func write(_ message: String) {
        guard let data = "P6 \(Date()) \(message)\n".data(using: .utf8) else { return }
        try? FileHandle.standardError.write(contentsOf: data)

        let logURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p6-debug-events.log")
        if FileManager.default.fileExists(atPath: logURL.path),
           let handle = try? FileHandle(forWritingTo: logURL)
        {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: logURL)
        }
    }
}
