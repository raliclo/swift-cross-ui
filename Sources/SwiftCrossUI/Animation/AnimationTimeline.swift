import Foundation

/// GSAP's timeline: animations placed on one time axis, played, paused,
/// reversed and scrubbed as one.
///
/// ```swift
/// var timeline = AnimationTimeline()
/// timeline.add(.easeOut(duration: 1)) { x = 200 * $0 }
/// timeline.add(.easeIn(duration: 0.5), at: .withPrevious(offset: 0.25)) { y = 100 * $0 }
/// timeline.addLabel("fade", at: .afterPrevious(gap: 0.2))
/// timeline.add(.linear(duration: 0.4), at: .label("fade")) { opacity = 1 - $0 }
/// let player = TimelinePlayer(timeline)
/// player.play()
/// ```
///
/// **Each segment writes its value through a closure, from a progress, and
/// the progress is a function of the timeline's time alone.** That is what
/// lets the player seek and reverse: every frame sets every segment to where
/// it is at that moment, rather than stepping tweens forward. The closures
/// assign state as any code does, so the views that read it update on every
/// backend with nothing new to implement.
///
/// The positions are GSAP's: `.afterPrevious(gap:)` is `"+=gap"` (and the
/// default, `">"`), `.withPrevious(offset:)` is `"<"`, `.at(_:)` is an absolute
/// time and `.label(_:offset:)` is `"label+=offset"`. A label not yet added
/// resolves to the current end, as GSAP adds it there.
///
/// GSAP 的 timeline:把多個動畫放在同一條時間軸上，一起播放、暫停、倒轉與拖動。**每個片段經由一個 closure、
/// 依進度寫入它的值，而進度只取決於 timeline 的時間。** 播放器能跳轉與倒轉，靠的就是這一點：每一幀都把每個片段
/// 設定到它在那一刻的位置，而不是讓補間一步步往前走。closure 像任何程式碼一樣賦值給狀態，所以讀取它的 view
/// 在每個 backend 上都會更新，不需要實作任何新東西。位置與 GSAP 相同(見上方英文)。尚未加入的標籤解析為目前的
/// 結尾，與 GSAP 把它加在那裡相同。
public struct AnimationTimeline: Sendable {
    public enum Position: Equatable, Sendable {
        case afterPrevious(gap: Double = 0)
        case withPrevious(offset: Double = 0)
        case at(Double)
        case label(String, offset: Double = 0)
    }

    struct Segment: Sendable {
        let start: Double
        let animation: Animation
        let apply: @MainActor @Sendable (Double) -> Void

        var end: Double { start + animation.totalDuration }
    }

    private(set) var segments: [Segment] = []
    public private(set) var labels: [String: Double] = [:]
    private var previousStart = 0.0
    private var previousEnd = 0.0

    public init() {}

    /// Seconds from the start to the end of the last segment. A `repeatForever`
    /// segment makes it infinite, and the player then never reaches the end.
    /// 從開始到最後一個片段結束的秒數。`repeatForever` 的片段會讓它變成無限，播放器也就永遠到不了結尾。
    public var duration: Double {
        segments.map(\.end).max() ?? 0
    }

    /// Places `animation` at `position`; `apply` receives its progress, `0` before
    /// it starts and `1` once it has ended.
    /// 把 `animation` 放在 `position`;`apply` 收到它的進度：開始前為 `0`,結束後為 `1`。
    public mutating func add(
        _ animation: Animation,
        at position: Position = .afterPrevious(),
        _ apply: @escaping @MainActor @Sendable (Double) -> Void
    ) {
        let segment = Segment(start: max(0, resolve(position)), animation: animation, apply: apply)
        segments.append(segment)
        previousStart = segment.start
        previousEnd = segment.end
    }

    public mutating func addLabel(_ name: String, at position: Position = .afterPrevious()) {
        labels[name] = max(0, resolve(position))
    }

    /// Where `position` falls on the time axis.
    /// `position` 落在時間軸上的哪裡。
    public func resolve(_ position: Position) -> Double {
        switch position {
            case .afterPrevious(let gap):
                return previousEnd + gap
            case .withPrevious(let offset):
                return previousStart + offset
            case .at(let time):
                return time
            case .label(let name, let offset):
                return (labels[name] ?? duration) + offset
        }
    }

    /// Each segment's progress at `time` seconds into the timeline.
    /// 在 timeline 第 `time` 秒時，每個片段的進度。
    public func progress(at time: Double) -> [Double] {
        segments.map { TweenClock($0.animation).state(at: time - $0.start).progress }
    }
}

extension Animation {
    /// From the call to the last frame: delay, then every play at its speed.
    /// 從呼叫到最後一幀：延遲，加上以其速度播放的每一次。
    public var totalDuration: Double {
        if repeatsForever {
            return .infinity
        }
        guard playbackSpeed > 0 else {
            return startDelay
        }
        return startDelay + duration * Double(max(playCount, 1)) / playbackSpeed
    }
}

/// Plays an ``AnimationTimeline`` on the app's frame clock: GSAP's `play`,
/// `pause`, `reverse`, `restart`, `seek`, `progress` and `timeScale`.
///
/// Keep one in `@State` and bind a slider to ``progress`` through
/// ``seek(progress:)`` to scrub it; ``onUpdate`` reports the progress on
/// every frame, for a slider that follows playback.
///
/// 以 app 的 frame clock 播放 ``AnimationTimeline``:即 GSAP 的 `play`、`pause`、`reverse`、`restart`、`seek`、
/// `progress` 與 `timeScale`。放一個在 `@State` 裡，透過 ``seek(progress:)`` 把 slider 綁到 ``progress`` 就能拖動;
/// ``onUpdate`` 每一幀回報進度，讓 slider 跟著播放移動。
@MainActor
public final class TimelinePlayer {
    public let timeline: AnimationTimeline
    public private(set) var time = 0.0
    public private(set) var isPlaying = false
    public private(set) var isReversed = false
    /// 2 plays twice as fast. GSAP's `timeScale`.
    /// 2 代表兩倍速。即 GSAP 的 `timeScale`。
    public var timeScale = 1.0
    public var onUpdate: (@MainActor (Double) -> Void)?

    private var lastTimestamp: Double?
    /// False in tests, which move the playhead with ``advance(by:)`` themselves.
    /// 測試中為 false:測試自己用 ``advance(by:)`` 移動播放頭。
    var usesFrameClock = true
    private var ticker: UUID?
    /// The progress last written per segment: a segment whose progress did not
    /// change is not written again, so a still state does not re-render.
    /// 每個片段上次寫入的進度：進度沒變的片段不再寫入，靜止的狀態就不會重新算繪。
    private var written: [Double?]

    public init(_ timeline: AnimationTimeline) {
        self.timeline = timeline
        written = Array(repeating: nil, count: timeline.segments.count)
    }

    public var duration: Double { timeline.duration }

    /// `0...1`; `0` for an endless timeline.
    /// `0...1`;無限長的 timeline 為 `0`。
    public var progress: Double {
        duration > 0 && duration.isFinite ? time / duration : 0
    }

    /// Forwards from here, or from the start when at the end.
    /// 從目前位置往前播放;已在結尾時從頭開始。
    public func play() {
        isReversed = false
        if time >= duration {
            time = 0
        }
        resume()
    }

    /// Backwards from here, or from the end when at the start.
    /// 從目前位置倒著播放;已在開頭時從結尾開始。
    public func reverse() {
        isReversed = true
        if time <= 0 {
            time = duration
        }
        resume()
    }

    public func pause() {
        isPlaying = false
        stopTicker()
    }

    public func restart() {
        seek(to: 0)
        play()
    }

    public func seek(to time: Double) {
        self.time = min(max(time, 0), duration)
        render()
    }

    public func seek(progress: Double) {
        seek(to: min(max(progress, 0), 1) * duration)
    }

    private func resume() {
        isPlaying = true
        lastTimestamp = nil
        render()
        startTicker()
    }

    /// Moves the playhead `seconds` of real time, scaled and in the current
    /// direction; false once it has reached the end it was heading for.
    /// 讓播放頭前進 `seconds` 秒的真實時間(乘上速度、依目前方向);抵達它前往的那一端後回傳 false。
    func advance(by seconds: Double) -> Bool {
        time += seconds * timeScale * (isReversed ? -1 : 1)
        var reachedEnd = false
        if time >= duration {
            time = duration
            reachedEnd = !isReversed
        } else if time <= 0 {
            time = 0
            reachedEnd = isReversed
        }
        render()
        if reachedEnd {
            isPlaying = false
        }
        return !reachedEnd
    }

    private func render() {
        for (index, progress) in timeline.progress(at: time).enumerated() where written[index] != progress {
            written[index] = progress
            timeline.segments[index].apply(progress)
        }
        onUpdate?(progress)
    }

    private func startTicker() {
        guard ticker == nil, usesFrameClock else { return }
        ticker = AnimationDriver.shared.addTicker { [weak self] timestamp in
            MainActor.assumeIsolated { self?.tick(timestamp) ?? false }
        }
    }

    private func stopTicker() {
        if let ticker {
            AnimationDriver.shared.removeTicker(ticker)
        }
        ticker = nil
    }

    /// One frame. The first frame after `play` only notes the time, so the wait
    /// for it is not played.
    /// 一幀。`play` 之後的第一幀只記下時間，讓等待它的那段時間不被播放。
    private func tick(_ timestamp: Double?) -> Bool {
        guard isPlaying else {
            ticker = nil
            return false
        }
        guard let timestamp else {
            seek(to: isReversed ? 0 : duration)
            isPlaying = false
            ticker = nil
            return false
        }
        defer { lastTimestamp = timestamp }
        guard let last = lastTimestamp else {
            return true
        }
        let playing = advance(by: timestamp - last)
        if !playing {
            ticker = nil
        }
        return playing
    }
}
