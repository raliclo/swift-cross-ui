import Testing

@testable import SwiftCrossUI

/// GSAP's timeline positions and the player's playhead, without a frame clock:
/// the player is advanced by hand as the driver's ticker would advance it.
///
/// GSAP 的 timeline 位置與播放器的播放頭，不需要 frame clock:以手動推進播放器，如同 driver 的 ticker 會做的。
@MainActor
@Suite("Animation timeline")
struct AnimationTimelineTests {
    @MainActor
    final class Values {
        var a = 0.0
        var b = 0.0
        var c = 0.0
        var writes = 0
    }

    /// a: 0-1 s; b: 0.25-0.75 s (with a, 0.25 in); label "c" 0.2 s after b ends,
    /// at 0.95 s; c: 0.95-1.45 s.
    /// a:0–1 秒;b:0.25–0.75 秒(與 a 同時、晚 0.25);標籤 "c" 在 b 結束後 0.2 秒，即 0.95 秒;c:0.95–1.45 秒。
    func timeline(_ values: Values) -> AnimationTimeline {
        var timeline = AnimationTimeline()
        timeline.add(.linear(duration: 1)) {
            values.a = $0
            values.writes += 1
        }
        timeline.add(.linear(duration: 0.5), at: .withPrevious(offset: 0.25)) { values.b = $0 }
        timeline.addLabel("c", at: .afterPrevious(gap: 0.2))
        timeline.add(.linear(duration: 0.5), at: .label("c")) { values.c = $0 }
        return timeline
    }

    @Test("Positions resolve as GSAP's do")
    func positions() {
        let timeline = timeline(Values())
        #expect(timeline.segments.map(\.start) == [0, 0.25, 0.95])
        #expect(timeline.labels["c"] == 0.95)
        #expect(abs(timeline.duration - 1.45) < 1e-12)
        #expect(timeline.resolve(.at(3)) == 3)
        // A label that does not exist resolves to the end.
        // 不存在的標籤解析為結尾。
        #expect(abs(timeline.resolve(.label("missing", offset: 0.1)) - 1.55) < 1e-12)
    }

    @Test("Seeking sets every segment to where it is at that time")
    func seek() {
        let values = Values()
        let player = TimelinePlayer(timeline(values))
        player.seek(to: 0.5)
        #expect(values.a == 0.5)
        #expect(values.b == 0.5)
        #expect(values.c == 0)
        player.seek(progress: 1)
        #expect(values.a == 1 && values.b == 1 && values.c == 1)
        // Back again: a timeline is a function of its time, so seeking backwards
        // undoes what went forwards.
        // 再倒回去:timeline 是時間的函數，往回跳就會還原往前走的結果。
        player.seek(to: 0.1)
        #expect(abs(values.a - 0.1) < 1e-12)
        #expect(values.b == 0)
    }

    @Test("Play advances, stops at the end; reverse runs back and stops at the start")
    func playAndReverse() {
        let values = Values()
        let player = TimelinePlayer(timeline(values))
        player.usesFrameClock = false
        player.play()
        #expect(player.advance(by: 0.5))
        #expect(abs(player.time - 0.5) < 1e-12)
        #expect(!player.advance(by: 2))
        #expect(player.time == player.duration)
        #expect(!player.isPlaying)
        player.reverse()
        player.timeScale = 2
        #expect(player.advance(by: 0.25))
        #expect(abs(player.time - 0.95) < 1e-12)
        #expect(!player.advance(by: 1))
        #expect(player.time == 0)
        #expect(values.a == 0 && values.c == 0)
    }

    @Test("A segment whose progress did not change is not written again")
    func unchangedNotRewritten() {
        let values = Values()
        let player = TimelinePlayer(timeline(values))
        player.seek(to: 1.2)
        let writes = values.writes
        player.seek(to: 1.3)
        // a ended at 1 s: still 1, not written.
        // a 在 1 秒結束：仍是 1,不再寫入。
        #expect(values.writes == writes)
    }

    @Test("Total duration counts delay, plays and speed")
    func totalDuration() {
        #expect(Animation.linear(duration: 1).delay(0.5).repeatCount(3).totalDuration == 3.5)
        #expect(Animation.linear(duration: 1).speed(2).totalDuration == 0.5)
        #expect(Animation.linear(duration: 1).repeatForever().totalDuration == .infinity)
    }
}
