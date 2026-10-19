import Foundation

// Keyframes and phases, SwiftUI's names: `keyframeAnimator(initialValue:repeating:
// content:keyframes:)` and its `trigger:` form, `KeyframeAnimator`, `KeyframeTrack`
// with `LinearKeyframe`, `SpringKeyframe`, `CubicKeyframe` and `MoveKeyframe`,
// `KeyframeTimeline`, and `phaseAnimator(_:trigger:content:animation:)`,
// `phaseAnimator(_:content:animation:)` and `PhaseAnimator`.
//
// **Keyframes.** Each track moves one property of the value (a key path) through
// its keyframes, one after another; tracks run side by side and a track that ends
// early holds its last value. The value at a time is a pure function of the time
// (``KeyframeTimeline``), so the animator only feeds it the frame clock: every
// frame it evaluates the timeline and gives the value to the content closure,
// whose body is evaluated again with it -- what SwiftUI does too.
//
// - `LinearKeyframe`: from the value the previous keyframe left to its own, on a
//   `UnitCurve`.
// - `SpringKeyframe`: towards its value as a spring, starting with its
//   `startVelocity`, or the velocity the previous keyframe ended with; the
//   segment ends after `duration` (the spring's response when nil) wherever the
//   spring is, and the next keyframe starts from there with its velocity.
// - `CubicKeyframe`: a cubic Hermite curve whose end velocities are the given
//   `startVelocity` / `endVelocity`, or else continue the neighbours: a
//   Catmull-Rom spline through neighbouring cubic keyframes (timed by the
//   keyframe times, as Barry and Goldman's construction times it), the velocity
//   of a neighbouring keyframe of another kind, half the segment's average at
//   the ends of the track.
// - `MoveKeyframe`: jumps to its value and stops the motion (velocity zero).
//
// Velocities are values of the track's type, per second, measured from
// `AnimatableValue.animatableZero` (0 for `Double` and `Float`, `.zero` for
// `SIMD2`). A type without a zero ignores them and uses the Catmull-Rom spline
// through its neighbours and springs from rest.
//
// **Phases.** The animator draws its content in one phase at a time and moves to
// the next when the previous phase's animation has ended. The change is drawn
// under `.animation(animation(phase), value: phase)`, so the content's effect
// modifiers, frames, paddings and colours tween on the direct path, as for any
// `.animation(_:value:)`.
//
// 關鍵影格與階段，以 SwiftUI 的名稱。**關鍵影格。** 每條軌道讓值的一個屬性(key path)依序經過它的關鍵影格;軌道
// 並行，提早結束的軌道停在它最後的值。某一時刻的值是時間的純函數(``KeyframeTimeline``),所以 animator 只負責把
// frame clock 餵給它：每一幀求出 timeline 的值、交給內容 closure,以它重新求值 body——SwiftUI 也是這樣做的。
// `LinearKeyframe` 以 `UnitCurve` 從前一個關鍵影格留下的值走到自己的值;`SpringKeyframe` 像彈簧般朝它的值移動，起始
// 速度為它的 `startVelocity` 或前一個關鍵影格結束時的速度，區段在 `duration`(nil 時為彈簧的 response)後結束，不論彈簧
// 在哪裡，下一個關鍵影格帶著它的速度從那裡開始;`CubicKeyframe` 是三次 Hermite 曲線，兩端速度為給定的 `startVelocity` /
// `endVelocity`,否則延續鄰居：相鄰三次關鍵影格之間為 Catmull-Rom 樣條(以關鍵影格時間計時，與 Barry 與 Goldman 的構造
// 相同),與其他種類的關鍵影格相鄰處為它的速度，軌道兩端為區段平均速度的一半;`MoveKeyframe` 直接跳到它的值並停止運動
// (速度為零)。速度是軌道型別的值，以每秒計，從 `AnimatableValue.animatableZero` 量起(`Double` 與 `Float` 為 0,
// `SIMD2` 為 `.zero`)。沒有零值的型別忽略速度，使用通過鄰居的 Catmull-Rom 樣條，彈簧從靜止開始。
//
// **階段。** animator 一次以一個階段畫出內容，前一個階段的動畫結束後移到下一個。改變在
// `.animation(animation(phase), value: phase)` 之下畫出，所以內容的效果 modifier、frame、padding 與顏色會走直接
// 路徑補間，與任何 `.animation(_:value:)` 相同。

/// SwiftUI's `UnitCurve`: a function from `0...1` to progress, for
/// `LinearKeyframe`.
/// SwiftUI 的 `UnitCurve`:由 `0...1` 到進度的函數，供 `LinearKeyframe` 使用。
public struct UnitCurve: TimingCurve {
    enum Kind: Equatable, Sendable {
        case linear
        case bezier(CubicBezier)
        case circularEaseIn
        case circularEaseOut
        case circularEaseInOut
    }

    let kind: Kind

    public static let linear = UnitCurve(kind: .linear)
    public static let easeIn = UnitCurve(kind: .bezier(CubicBezier(0.42, 0, 1, 1)))
    public static let easeOut = UnitCurve(kind: .bezier(CubicBezier(0, 0, 0.58, 1)))
    public static let easeInOut = UnitCurve(kind: .bezier(CubicBezier(0.42, 0, 0.58, 1)))
    public static let circularEaseIn = UnitCurve(kind: .circularEaseIn)
    public static let circularEaseOut = UnitCurve(kind: .circularEaseOut)
    public static let circularEaseInOut = UnitCurve(kind: .circularEaseInOut)

    /// A cubic Bézier from (0, 0) to (1, 1) with these control points.
    /// 從 (0, 0) 到 (1, 1)、以這兩個控制點構成的三次貝茲曲線。
    public static func bezier(startControlPoint: UnitPoint, endControlPoint: UnitPoint) -> UnitCurve {
        UnitCurve(
            kind: .bezier(
                CubicBezier(startControlPoint.x, startControlPoint.y, endControlPoint.x, endControlPoint.y)
            )
        )
    }

    /// SwiftUI's name for ``progress(at:)``. / SwiftUI 對 ``progress(at:)`` 的名稱。
    public func value(at progress: Double) -> Double {
        self.progress(at: progress)
    }

    /// The curve's slope at `fraction` (progress per unit of fraction), by a
    /// difference over 1e-5, one-sided at the ends.
    /// 曲線在 `fraction` 處的斜率(每單位 fraction 的進度),以 1e-5 的差分求得，兩端用單邊差分。
    func slope(at fraction: Double) -> Double {
        let h = 1e-5
        let t = min(max(fraction, 0), 1)
        let low = max(t - h, 0)
        let high = min(t + h, 1)
        return (progress(at: high) - progress(at: low)) / (high - low)
    }

    public func progress(at fraction: Double) -> Double {
        let t = min(max(fraction, 0), 1)
        switch kind {
            case .linear:
                return t
            case .bezier(let bezier):
                return bezier.progress(at: t)
            case .circularEaseIn:
                return 1 - (1 - t * t).squareRoot()
            case .circularEaseOut:
                return (1 - (t - 1) * (t - 1)).squareRoot()
            case .circularEaseInOut:
                if t < 0.5 {
                    return (1 - (1 - 4 * t * t).squareRoot()) / 2
                }
                let u = 2 * t - 2
                return ((1 - u * u).squareRoot() + 1) / 2
        }
    }
}

extension Spring {
    /// SwiftUI's preset springs, as `Animation.smooth`, `.snappy` and
    /// `.bouncy` use them. / SwiftUI 的預設彈簧，與 `Animation.smooth`、`.snappy`、`.bouncy` 所用的相同。
    public static let smooth = Spring(duration: 0.5, bounce: 0)
    public static let snappy = Spring(duration: 0.5, bounce: 0.15)
    public static let bouncy = Spring(duration: 0.5, bounce: 0.3)

    /// SwiftUI's perceptual duration: the response. / SwiftUI 的感知時長：即 response。
    public var duration: Double { response }
}

/// One keyframe of a track, as its builder collects it.
/// 一條軌道中的一個關鍵影格，由它的 builder 收集。
public struct _KeyframeSegment<Value: AnimatableValue> {
    enum Kind {
        case linear(UnitCurve)
        case spring(Spring, startVelocity: Value?)
        case cubic(startVelocity: Value?, endVelocity: Value?)
        case move
    }

    let target: Value
    let duration: Double
    let kind: Kind
}

/// Content of a ``KeyframeTrack``: one or more keyframes.
/// ``KeyframeTrack`` 的內容：一個或多個關鍵影格。
public protocol KeyframeTrackContent<Value> {
    associatedtype Value: AnimatableValue
    var _segments: [_KeyframeSegment<Value>] { get }
}

/// Moves from the previous value to `to` in `duration` seconds on `timingCurve`.
/// 在 `duration` 秒內沿 `timingCurve` 從前一個值移到 `to`。
public struct LinearKeyframe<Value: AnimatableValue>: KeyframeTrackContent {
    public var _segments: [_KeyframeSegment<Value>]

    public init(_ to: Value, duration: Double, timingCurve: UnitCurve = .linear) {
        _segments = [_KeyframeSegment(target: to, duration: max(duration, 0), kind: .linear(timingCurve))]
    }
}

/// Moves towards `to` as `spring` for `duration` seconds (the spring's response
/// when nil), starting with `startVelocity` (per second), or when nil with the
/// velocity the previous keyframe ended with (none at the start of the track).
/// 以 `spring` 朝 `to` 移動 `duration` 秒(nil 時為彈簧的 response),起始速度為 `startVelocity`(每秒);nil 時為前一個
/// 關鍵影格結束時的速度(軌道開頭則為零)。
public struct SpringKeyframe<Value: AnimatableValue>: KeyframeTrackContent {
    public var _segments: [_KeyframeSegment<Value>]

    public init(
        _ to: Value,
        duration: Double? = nil,
        spring: Spring = Spring(duration: 0.5, bounce: 0),
        startVelocity: Value? = nil
    ) {
        _segments = [
            _KeyframeSegment(
                target: to, duration: max(duration ?? spring.response, 0),
                kind: .spring(spring, startVelocity: startVelocity)
            )
        ]
    }
}

/// Moves to `to` in `duration` seconds on a cubic curve. Its velocity at each
/// end (per second) is the one given; when nil, next to another cubic keyframe
/// it is a Catmull-Rom spline's through the neighbouring values, next to
/// another kind of keyframe it is that keyframe's velocity there, and at the
/// start or end of the track half the segment's average.
/// 在 `duration` 秒內沿三次曲線移到 `to`。兩端的速度(每秒)為給定的值;nil 時，與另一個三次關鍵影格相鄰處為通過相鄰
/// 值的 Catmull-Rom 樣條的速度，與其他種類的關鍵影格相鄰處為那個關鍵影格在該處的速度，軌道開頭或結尾則為區段平均速度的
/// 一半。
public struct CubicKeyframe<Value: AnimatableValue>: KeyframeTrackContent {
    public var _segments: [_KeyframeSegment<Value>]

    public init(_ to: Value, duration: Double, startVelocity: Value? = nil, endVelocity: Value? = nil) {
        _segments = [
            _KeyframeSegment(
                target: to, duration: max(duration, 0),
                kind: .cubic(startVelocity: startVelocity, endVelocity: endVelocity)
            )
        ]
    }
}

/// Jumps to `to`, taking no time. / 直接跳到 `to`,不花時間。
public struct MoveKeyframe<Value: AnimatableValue>: KeyframeTrackContent {
    public var _segments: [_KeyframeSegment<Value>]

    public init(_ to: Value) {
        _segments = [_KeyframeSegment(target: to, duration: 0, kind: .move)]
    }
}

/// The keyframes a ``KeyframeTrackContentBuilder`` collected.
/// ``KeyframeTrackContentBuilder`` 收集到的關鍵影格。
public struct KeyframeTrackContentList<Value: AnimatableValue>: KeyframeTrackContent {
    public var _segments: [_KeyframeSegment<Value>]

    init(_ segments: [_KeyframeSegment<Value>]) {
        _segments = segments
    }
}

@resultBuilder
public enum KeyframeTrackContentBuilder<Value: AnimatableValue> {
    public static func buildExpression<Content: KeyframeTrackContent>(
        _ content: Content
    ) -> KeyframeTrackContentList<Value> where Content.Value == Value {
        KeyframeTrackContentList(content._segments)
    }

    public static func buildBlock(_ parts: KeyframeTrackContentList<Value>...) -> KeyframeTrackContentList<Value> {
        KeyframeTrackContentList(parts.flatMap(\._segments))
    }

    public static func buildOptional(_ part: KeyframeTrackContentList<Value>?) -> KeyframeTrackContentList<Value> {
        part ?? KeyframeTrackContentList([])
    }

    public static func buildEither(first: KeyframeTrackContentList<Value>) -> KeyframeTrackContentList<Value> {
        first
    }

    public static func buildEither(second: KeyframeTrackContentList<Value>) -> KeyframeTrackContentList<Value> {
        second
    }

    public static func buildArray(_ parts: [KeyframeTrackContentList<Value>]) -> KeyframeTrackContentList<Value> {
        KeyframeTrackContentList(parts.flatMap(\._segments))
    }
}

/// One property's track, evaluated against the value it starts from.
/// 一個屬性的軌道，針對它起始的值求值。
public struct _KeyframeTrackEvaluator<Root> {
    /// The track's length in seconds. / 軌道的長度(秒)。
    let duration: Double
    /// Writes the track's value at a time into the root value.
    /// 把軌道在某一時刻的值寫進根值。
    let apply: (inout Root, Double) -> Void
}

/// Keyframes for a value: one or more tracks.
/// 一個值的關鍵影格：一條或多條軌道。
public protocol Keyframes<Value> {
    associatedtype Value
    /// The tracks, given the value they start from.
    /// 各軌道，給定它們起始的值。
    func _tracks(from initialValue: Value) -> [_KeyframeTrackEvaluator<Value>]
}

/// The keyframes of one property of `Root`, at `keyPath`.
/// `Root` 在 `keyPath` 上那一個屬性的關鍵影格。
public struct KeyframeTrack<Root, Value: AnimatableValue>: Keyframes {
    let keyPath: WritableKeyPath<Root, Value>
    let segments: [_KeyframeSegment<Value>]

    public init(
        _ keyPath: WritableKeyPath<Root, Value>,
        @KeyframeTrackContentBuilder<Value> content: () -> KeyframeTrackContentList<Value>
    ) {
        self.keyPath = keyPath
        segments = content()._segments
    }

    /// A track for the whole value. / 整個值的軌道。
    public init(
        @KeyframeTrackContentBuilder<Value> content: () -> KeyframeTrackContentList<Value>
    ) where Root == Value {
        self.init(\.self, content: content)
    }

    public func _tracks(from initialValue: Root) -> [_KeyframeTrackEvaluator<Root>] {
        let curve = KeyframeCurve(start: initialValue[keyPath: keyPath], segments: segments)
        let keyPath = keyPath
        return [
            _KeyframeTrackEvaluator(duration: curve.duration) { root, time in
                root[keyPath: keyPath] = curve.value(at: time)
            }
        ]
    }
}

/// One track's keyframes laid out in time, from a start value.
///
/// Velocities are values of the track's type measured from
/// `Value.animatableZero`, per second. A type without one (the Barry-Goldman
/// spline then, and springs from rest) still animates; the arithmetic on
/// velocities is built from interpolation, so it needs no more of the type.
///
/// 一條軌道的關鍵影格在時間上的排列，從一個起始值開始。速度是軌道型別的值，從 `Value.animatableZero` 量起，以每秒計。
/// 沒有它的型別(此時用 Barry-Goldman 樣條，彈簧從靜止開始)仍會動畫;速度的運算以插值構成，所以對型別沒有更多要求。
struct KeyframeCurve<Value: AnimatableValue> {
    struct Placed {
        var segment: _KeyframeSegment<Value>
        var startTime: Double
        var startValue: Value
        var endValue: Value
        /// A spring's start velocity. / 彈簧的起始速度。
        var startVelocity: Value?
        /// The velocity at the end, which a following keyframe may take up.
        /// 結束時的速度，後面的關鍵影格可能接續它。
        var endVelocity: Value?
        /// A cubic's velocities at its two ends. / 三次關鍵影格兩端的速度。
        var tangents: (start: Value, end: Value)?
    }

    let start: Value
    private(set) var placed: [Placed] = []
    private(set) var duration = 0.0
    private let zero: Value?

    init(start: Value, segments: [_KeyframeSegment<Value>]) {
        self.start = start
        zero = Value.animatableZero
        var time = 0.0
        var value = start
        // Each segment starts where the previous one ended -- a spring cut
        // short starts the next keyframe from where it got to, and with the
        // velocity it had there.
        // 每個區段從前一個結束之處開始——提早切斷的彈簧，下一個關鍵影格從它到達之處、以它在那裡的速度開始。
        for (index, segment) in segments.enumerated() {
            var entry = Placed(segment: segment, startTime: time, startValue: value, endValue: segment.target)
            if let zero, segment.duration > 0 {
                switch segment.kind {
                    case .spring(_, let given):
                        entry.startVelocity = given ?? placed.last?.endVelocity ?? zero
                    case .cubic(let givenStart, let givenEnd):
                        entry.tangents = (
                            start: givenStart ?? startTangent(of: entry, zero: zero),
                            end: givenEnd ?? endTangent(of: entry, next: segments.dropFirst(index + 1).first, zero: zero)
                        )
                    case .linear, .move:
                        break
                }
            }
            placed.append(entry)
            entry.endValue = self.value(ofSegment: placed.count - 1, at: segment.duration)
            if let zero {
                entry.endVelocity = endVelocity(of: entry, zero: zero)
            }
            placed[placed.count - 1] = entry
            time += segment.duration
            value = entry.endValue
        }
        duration = time
    }

    /// Half the segment's average velocity: a cubic's at an end with no
    /// neighbour, which is what a Catmull-Rom spline gets from a neighbour equal
    /// to that end.
    /// 區段平均速度的一半：沒有鄰居的那一端的三次曲線速度，即 Catmull-Rom 樣條在鄰居等於該端點時得到的值。
    private func halfAverage(_ entry: Placed, zero: Value) -> Value {
        Value.scaled(
            Value.difference(from: entry.startValue, to: entry.segment.target, zero: zero),
            by: 0.5 / entry.segment.duration,
            zero: zero
        )
    }

    /// The Catmull-Rom velocity at `p1` (time `t1`) between `p0` and `p2`,
    /// weighted by the times as Barry and Goldman's construction weights it.
    /// `p0` 與 `p2` 之間、在 `p1`(時間 `t1`)的 Catmull-Rom 速度，以時間加權，與 Barry 與 Goldman 的構造相同。
    private func catmullRom(
        _ p0: Value, _ t0: Double, _ p1: Value, _ t1: Double, _ p2: Value, _ t2: Double, zero: Value
    ) -> Value {
        let before = Value.scaled(
            Value.difference(from: p0, to: p1, zero: zero), by: (t2 - t1) / ((t1 - t0) * (t2 - t0)), zero: zero
        )
        let after = Value.scaled(
            Value.difference(from: p1, to: p2, zero: zero), by: (t1 - t0) / ((t2 - t1) * (t2 - t0)), zero: zero
        )
        return Value.adding(after, to: before, zero: zero)
    }

    /// A cubic's start velocity when none is given: a cubic before it hands
    /// over its end velocity, another kind of keyframe its velocity at the
    /// end; at the start of the track, or after a move, half the average.
    /// 沒有給定時三次曲線的起始速度：前面的三次曲線交出它的結束速度，其他種類的關鍵影格交出它結束時的速度;軌道開頭或
    /// move 之後，為平均速度的一半。
    private func startTangent(of entry: Placed, zero: Value) -> Value {
        guard let previous = placed.last, previous.segment.duration > 0 else {
            return halfAverage(entry, zero: zero)
        }
        return previous.tangents?.end ?? previous.endVelocity ?? halfAverage(entry, zero: zero)
    }

    /// A cubic's end velocity when none is given, from the keyframe after it:
    /// a cubic's given start velocity or else the Catmull-Rom velocity through
    /// its target, a linear keyframe's start velocity, a spring's given start
    /// velocity; otherwise half the average.
    /// 沒有給定時三次曲線的結束速度，取自其後的關鍵影格：三次曲線給定的起始速度，否則為通過其目標的 Catmull-Rom 速度;
    /// 線性關鍵影格的起始速度;彈簧給定的起始速度;其他情況為平均速度的一半。
    private func endTangent(of entry: Placed, next: _KeyframeSegment<Value>?, zero: Value) -> Value {
        guard let next, next.duration > 0 else { return halfAverage(entry, zero: zero) }
        let end = entry.startTime + entry.segment.duration
        switch next.kind {
            case .cubic(let nextStart, _):
                return nextStart
                    ?? catmullRom(
                        entry.startValue, entry.startTime, entry.segment.target, end, next.target,
                        end + next.duration, zero: zero
                    )
            case .linear(let curve):
                return Value.scaled(
                    Value.difference(from: entry.segment.target, to: next.target, zero: zero),
                    by: curve.slope(at: 0) / next.duration,
                    zero: zero
                )
            case .spring(_, let nextStart?):
                return nextStart
            case .spring, .move:
                return halfAverage(entry, zero: zero)
        }
    }

    /// The velocity `entry` ends with. / `entry` 結束時的速度。
    private func endVelocity(of entry: Placed, zero: Value) -> Value {
        let segment = entry.segment
        guard segment.duration > 0 else { return zero }
        switch segment.kind {
            case .move:
                return zero
            case .linear(let curve):
                return Value.scaled(
                    Value.difference(from: entry.startValue, to: segment.target, zero: zero),
                    by: curve.slope(at: 1) / segment.duration,
                    zero: zero
                )
            case .spring(let spring, _):
                let t = segment.duration
                let fromTarget = Value.scaled(
                    Value.difference(from: segment.target, to: entry.startValue, zero: zero),
                    by: spring.remainingRate(at: t),
                    zero: zero
                )
                let fromStart = Value.scaled(
                    entry.startVelocity ?? zero, by: spring.velocityPerUnitVelocity(at: t), zero: zero
                )
                return Value.adding(fromStart, to: fromTarget, zero: zero)
            case .cubic:
                return entry.tangents?.end ?? zero
        }
    }

    /// The value `time` seconds into the track; held at the end after it.
    /// 軌道進行到 `time` 秒時的值;之後停在終點。
    func value(at time: Double) -> Value {
        guard !placed.isEmpty else { return start }
        if time <= 0 {
            // A move at time zero has already happened.
            // 時間零的 move 已經發生了。
            var index = 0
            var value = start
            while index < placed.count, placed[index].segment.duration == 0 {
                value = placed[index].endValue
                index += 1
            }
            return value
        }
        for (index, entry) in placed.enumerated() {
            let end = entry.startTime + entry.segment.duration
            if time < end {
                return value(ofSegment: index, at: time - entry.startTime)
            }
        }
        return placed[placed.count - 1].endValue
    }

    private func value(ofSegment index: Int, at local: Double) -> Value {
        let entry = placed[index]
        let segment = entry.segment
        guard segment.duration > 0 else { return segment.target }
        let fraction = min(max(local / segment.duration, 0), 1)
        switch segment.kind {
            case .move:
                return segment.target
            case .linear(let curve):
                return Value.interpolated(
                    from: entry.startValue, to: segment.target, progress: curve.progress(at: fraction)
                )
            case .spring(let spring, _):
                let t = min(max(local, 0), segment.duration)
                let released = Value.interpolated(
                    from: entry.startValue, to: segment.target, progress: 1 - spring.remaining(at: t)
                )
                guard let zero, let velocity = entry.startVelocity else { return released }
                return Value.adding(
                    Value.scaled(velocity, by: spring.displacementPerUnitVelocity(at: t), zero: zero),
                    to: released,
                    zero: zero
                )
            case .cubic:
                if let zero, let tangents = entry.tangents {
                    return hermiteValue(entry, tangents: tangents, fraction: fraction, zero: zero)
                }
                return cubicValue(ofSegment: index, at: local)
        }
    }

    /// The cubic Hermite curve from the segment's start to its target with
    /// these end velocities. / 從區段起點到目標、帶這兩端速度的三次 Hermite 曲線。
    private func hermiteValue(
        _ entry: Placed, tangents: (start: Value, end: Value), fraction s: Double, zero: Value
    ) -> Value {
        let d = entry.segment.duration
        let h01 = -2 * s * s * s + 3 * s * s
        let h10 = s * s * s - 2 * s * s + s
        let h11 = s * s * s - s * s
        let between = Value.interpolated(from: entry.startValue, to: entry.segment.target, progress: h01)
        let pushed = Value.adding(Value.scaled(tangents.start, by: d * h10, zero: zero), to: between, zero: zero)
        return Value.adding(Value.scaled(tangents.end, by: d * h11, zero: zero), to: pushed, zero: zero)
    }

    /// Barry and Goldman's pyramid for a Catmull-Rom spline through the values
    /// before, at the ends of and after this segment, with the keyframe times as
    /// knots, for a type with no zero to measure velocities from. A missing
    /// neighbour is the segment's own end, so the curve starts or ends without
    /// overshoot.
    /// Barry 與 Goldman 的金字塔：通過此區段之前、兩端與之後的值的 Catmull-Rom 樣條，以關鍵影格時間為節點，供沒有可量
    /// 速度之零值的型別使用。缺少的鄰居以區段自己的端點代替，讓曲線在開頭或結尾不會衝過頭。
    private func cubicValue(ofSegment index: Int, at local: Double) -> Value {
        let entry = placed[index]
        let t1 = entry.startTime
        let t2 = t1 + entry.segment.duration
        let p1 = entry.startValue
        let p2 = entry.segment.target

        var p0 = p1
        var t0 = t1 - entry.segment.duration
        if index > 0, placed[index - 1].segment.duration > 0 {
            p0 = placed[index - 1].startValue
            t0 = placed[index - 1].startTime
        }
        var p3 = p2
        var t3 = t2 + entry.segment.duration
        if index + 1 < placed.count, case .cubic = placed[index + 1].segment.kind,
            placed[index + 1].segment.duration > 0
        {
            p3 = placed[index + 1].segment.target
            t3 = t2 + placed[index + 1].segment.duration
        }

        let t = t1 + local
        func lerp(_ a: Value, _ b: Value, _ from: Double, _ to: Double) -> Value {
            Value.interpolated(from: a, to: b, progress: (t - from) / (to - from))
        }
        let a1 = lerp(p0, p1, t0, t1)
        let a2 = lerp(p1, p2, t1, t2)
        let a3 = lerp(p2, p3, t2, t3)
        let b1 = lerp(a1, a2, t0, t2)
        let b2 = lerp(a2, a3, t1, t3)
        return lerp(b1, b2, t1, t2)
    }
}

/// The tracks a ``KeyframesBuilder`` collected.
/// ``KeyframesBuilder`` 收集到的軌道。
public struct KeyframeList<Value>: Keyframes {
    let makeTracks: [(Value) -> [_KeyframeTrackEvaluator<Value>]]

    init(_ makeTracks: [(Value) -> [_KeyframeTrackEvaluator<Value>]]) {
        self.makeTracks = makeTracks
    }

    public func _tracks(from initialValue: Value) -> [_KeyframeTrackEvaluator<Value>] {
        makeTracks.flatMap { $0(initialValue) }
    }
}

@resultBuilder
public enum KeyframesBuilder<Value> {
    public static func buildExpression<K: Keyframes>(_ keyframes: K) -> KeyframeList<Value>
    where K.Value == Value {
        KeyframeList([{ keyframes._tracks(from: $0) }])
    }

    public static func buildBlock(_ parts: KeyframeList<Value>...) -> KeyframeList<Value> {
        KeyframeList(parts.flatMap(\.makeTracks))
    }

    public static func buildOptional(_ part: KeyframeList<Value>?) -> KeyframeList<Value> {
        part ?? KeyframeList([])
    }

    public static func buildEither(first: KeyframeList<Value>) -> KeyframeList<Value> {
        first
    }

    public static func buildEither(second: KeyframeList<Value>) -> KeyframeList<Value> {
        second
    }

    public static func buildArray(_ parts: [KeyframeList<Value>]) -> KeyframeList<Value> {
        KeyframeList(parts.flatMap(\.makeTracks))
    }
}

/// Keyframes laid out in time from an initial value: the value at any time,
/// with no clock -- SwiftUI's `KeyframeTimeline`.
/// 從初始值開始、在時間上排好的關鍵影格：任何時刻的值，不需要時鐘——SwiftUI 的 `KeyframeTimeline`。
public struct KeyframeTimeline<Value> {
    let initialValue: Value
    let tracks: [_KeyframeTrackEvaluator<Value>]

    /// The length of the longest track, in seconds. / 最長軌道的長度(秒)。
    public let duration: Double

    public init(
        initialValue: Value,
        @KeyframesBuilder<Value> content: () -> KeyframeList<Value>
    ) {
        self.init(initialValue: initialValue, keyframes: content())
    }

    init(initialValue: Value, keyframes: some Keyframes<Value>) {
        self.initialValue = initialValue
        tracks = keyframes._tracks(from: initialValue)
        duration = tracks.map(\.duration).max() ?? 0
    }

    /// The value `time` seconds in. / 進行到 `time` 秒時的值。
    public func value(time: Double) -> Value {
        var value = initialValue
        for track in tracks {
            track.apply(&value, time)
        }
        return value
    }

    /// The value at `progress` (`0...1`) of ``duration``.
    /// 在 ``duration`` 的 `progress`(`0...1`)處的值。
    public func value(progress: Double) -> Value {
        value(time: min(max(progress, 0), 1) * duration)
    }
}

/// SwiftUI's name for the view a `keyframeAnimator` or `phaseAnimator`
/// modifier hands its content closure: the modified view itself.
/// SwiftUI 對 `keyframeAnimator` 或 `phaseAnimator` modifier 交給內容 closure 的 view 的稱呼：就是被修飾的那個 view。
public typealias PlaceholderContentView<Content> = Content

/// What a running keyframe animator evaluated on each frame, for test apps
/// (P106). Not SwiftUI API.
/// 執行中的 keyframe animator 每一幀求出的東西，供測試 app(P106)使用。不是 SwiftUI API。
@_spi(Backends)
@MainActor
public enum KeyframeAnimatorDiagnostics {
    public struct Sample: Sendable {
        /// Frame-clock seconds since the animation started.
        /// 自動畫開始以來 frame clock 的秒數。
        public var elapsed: Double
        /// The time on the timeline: `elapsed`, wrapped when repeating.
        /// timeline 上的時間:`elapsed`,重複播放時取餘數。
        public var time: Double
        public var uptime: Double
    }

    public private(set) static var samples: [Sample] = []

    static func record(elapsed: Double, time: Double) {
        samples.append(Sample(elapsed: elapsed, time: time, uptime: ProcessInfo.processInfo.systemUptime))
    }

    public static func clear() {
        samples = []
    }
}

/// Plays a ``KeyframeTimeline`` on the frame clock and publishes its value.
/// 在 frame clock 上播放 ``KeyframeTimeline`` 並發布它的值。
@MainActor
final class KeyframeAnimatorModel<Value>: ObservableObject {
    @Published var value: Value?
    private var timeline: KeyframeTimeline<Value>?
    private var repeating = false
    private var startTime: Double?
    private var ticker: UUID?
    private var endedAtOnce = false
    var isPlaying: Bool { ticker != nil }

    init() {}

    func play(_ timeline: KeyframeTimeline<Value>, repeating: Bool) {
        stop()
        self.timeline = timeline
        self.repeating = repeating
        startTime = nil
        value = timeline.value(time: 0)
        endedAtOnce = false
        let key = AnimationDriver.shared.addTicker { [weak self] timestamp in
            MainActor.assumeIsolated { self?.tick(timestamp) ?? false }
        }
        // Without a frame clock the ticker already ran to the end inside `addTicker`.
        // 沒有 frame clock 時，ticker 已在 `addTicker` 之內跑到終點。
        ticker = endedAtOnce ? nil : key
    }

    func stop() {
        if let ticker {
            AnimationDriver.shared.removeTicker(ticker)
        }
        ticker = nil
    }

    /// One frame; false once a single play has reached its end. Without a
    /// frame clock (`nil`) the value goes to the end at once.
    /// 一幀;單次播放抵達終點後回傳 false。沒有 frame clock(`nil`)時值直接到終點。
    private func tick(_ timestamp: Double?) -> Bool {
        guard let timeline else { return false }
        guard let timestamp else {
            value = timeline.value(time: timeline.duration)
            endedAtOnce = true
            ticker = nil
            return false
        }
        guard let startTime else {
            self.startTime = timestamp
            KeyframeAnimatorDiagnostics.record(elapsed: 0, time: 0)
            return true
        }
        let elapsed = timestamp - startTime
        var time = elapsed
        var running = true
        if repeating, timeline.duration > 0 {
            time = elapsed.truncatingRemainder(dividingBy: timeline.duration)
        } else if elapsed >= timeline.duration {
            time = timeline.duration
            running = false
        }
        value = timeline.value(time: time)
        KeyframeAnimatorDiagnostics.record(elapsed: elapsed, time: time)
        if !running {
            ticker = nil
        }
        return running
    }

    deinit {
        if let ticker {
            AnimationDriver.shared.removeTicker(ticker)
        }
    }
}

/// An `Equatable` value of any type, for a trigger.
/// 任何型別的 `Equatable` 值，用作觸發條件。
struct AnyEquatableTrigger: Equatable {
    let value: Any
    let isEqual: (Any) -> Bool

    init<T: Equatable>(_ value: T) {
        self.value = value
        isEqual = { ($0 as? T) == value }
    }

    static func == (lhs: AnyEquatableTrigger, rhs: AnyEquatableTrigger) -> Bool {
        lhs.isEqual(rhs.value)
    }
}

/// Draws `content` with a value that keyframes move over time -- SwiftUI's
/// `KeyframeAnimator`. With a trigger the keyframes play once each time it
/// changes, from the value drawn then; with `repeating` they loop from the
/// initial value for as long as the view is shown.
/// 以關鍵影格隨時間移動的值畫出 `content`——SwiftUI 的 `KeyframeAnimator`。有觸發條件時，每次它改變就從當時畫出
/// 的值播放一次;`repeating` 時，只要 view 還在，就從初始值開始循環播放。
public struct KeyframeAnimator<Value, Content: View>: View {
    @State private var model = KeyframeAnimatorModel<Value>()
    let initialValue: Value
    let trigger: AnyEquatableTrigger?
    let repeating: Bool
    let content: (Value) -> Content
    let keyframes: (Value) -> KeyframeList<Value>

    public init(
        initialValue: Value,
        trigger: some Equatable,
        @ViewBuilder content: @escaping (Value) -> Content,
        @KeyframesBuilder<Value> keyframes: @escaping (Value) -> KeyframeList<Value>
    ) {
        self.initialValue = initialValue
        self.trigger = AnyEquatableTrigger(trigger)
        repeating = false
        self.content = content
        self.keyframes = keyframes
    }

    public init(
        initialValue: Value,
        repeating: Bool = true,
        @ViewBuilder content: @escaping (Value) -> Content,
        @KeyframesBuilder<Value> keyframes: @escaping (Value) -> KeyframeList<Value>
    ) {
        self.initialValue = initialValue
        trigger = nil
        self.repeating = repeating
        self.content = content
        self.keyframes = keyframes
    }

    public var body: some View {
        content(model.value ?? initialValue)
            .onAppear {
                guard trigger == nil, repeating else { return }
                model.play(
                    KeyframeTimeline(initialValue: initialValue, keyframes: keyframes(initialValue)),
                    repeating: true
                )
            }
            .onChange(of: trigger) {
                guard trigger != nil else { return }
                let start = model.value ?? initialValue
                model.play(
                    KeyframeTimeline(initialValue: start, keyframes: keyframes(start)),
                    repeating: false
                )
            }
    }
}

extension View {
    /// Draws `content` with a value that keyframes move, looping from
    /// `initialValue` while `repeating` -- SwiftUI's
    /// `keyframeAnimator(initialValue:repeating:content:keyframes:)`.
    /// 以關鍵影格移動的值畫出 `content`,`repeating` 時從 `initialValue` 循環——SwiftUI 的
    /// `keyframeAnimator(initialValue:repeating:content:keyframes:)`。
    public func keyframeAnimator<Value, Modified: View>(
        initialValue: Value,
        repeating: Bool = true,
        @ViewBuilder content: @escaping (PlaceholderContentView<Self>, Value) -> Modified,
        @KeyframesBuilder<Value> keyframes: @escaping (Value) -> KeyframeList<Value>
    ) -> some View {
        KeyframeAnimator(
            initialValue: initialValue,
            repeating: repeating,
            content: { content(self, $0) },
            keyframes: keyframes
        )
    }

    /// Plays the keyframes once each time `trigger` changes -- SwiftUI's
    /// `keyframeAnimator(initialValue:trigger:content:keyframes:)`.
    /// 每次 `trigger` 改變就播放一次關鍵影格——SwiftUI 的 `keyframeAnimator(initialValue:trigger:content:keyframes:)`。
    public func keyframeAnimator<Value, Modified: View>(
        initialValue: Value,
        trigger: some Equatable,
        @ViewBuilder content: @escaping (PlaceholderContentView<Self>, Value) -> Modified,
        @KeyframesBuilder<Value> keyframes: @escaping (Value) -> KeyframeList<Value>
    ) -> some View {
        KeyframeAnimator(
            initialValue: initialValue,
            trigger: trigger,
            content: { content(self, $0) },
            keyframes: keyframes
        )
    }
}

/// Steps through phases on the frame clock: the index shown, moved on when the
/// previous phase's animation has ended.
/// 在 frame clock 上逐一經過各階段：顯示的索引，在前一個階段的動畫結束時往前移。
@MainActor
final class PhaseAnimatorModel: ObservableObject {
    @Published var index = 0
    private var remaining = 0
    private var cycles = false
    private var depth = 0
    private let key = UUID()

    init() {}

    deinit {
        AnimationDriver.shared.cancel(key: key)
    }

    /// Goes through `count` phases once from the first, ending on it again;
    /// or round and round when `cycles`.
    /// 從第一個階段開始經過 `count` 個階段一次，最後回到它;`cycles` 時則一直循環。
    func run(count: Int, cycles: Bool, animation: @escaping (Int) -> Animation?) {
        guard count > 1 else { return }
        self.cycles = cycles
        remaining = count
        index = 0
        advance(count: count, animation: animation)
    }

    private func advance(count: Int, animation: @escaping (Int) -> Animation?) {
        // Without a frame clock each step ends inside `start` and calls this
        // again; one round is as far as that goes.
        // 沒有 frame clock 時，每一步都在 `start` 之內結束並再次呼叫這裡;最多走一輪。
        depth += 1
        defer { depth -= 1 }
        guard depth <= count else { return }
        if !cycles {
            guard remaining > 0 else { return }
            remaining -= 1
        }
        let next = (index + 1) % count
        index = next
        // The phase's own animation times the step; none still waits a frame,
        // so phases without animations do not spin.
        // 由階段自己的動畫為這一步計時;沒有動畫時仍等一幀，讓沒有動畫的階段不會空轉。
        let timing = animation(next) ?? Animation(duration: 0, curve: .linear)
        AnimationDriver.shared.start(
            key: key,
            animation: timing,
            group: nil,
            apply: { _ in },
            finish: { [weak self] in
                MainActor.assumeIsolated {
                    self?.advance(count: count, animation: animation)
                }
            }
        )
    }
}

/// When each phase animator moved to a phase, for test apps (P106). Not
/// SwiftUI API. / 每個 phase animator 移到某個階段的時刻，供測試 app(P106)使用。不是 SwiftUI API。
@_spi(Backends)
@MainActor
public enum PhaseAnimatorDiagnostics {
    public struct Change: Sendable {
        public var index: Int
        public var uptime: Double
    }

    public private(set) static var changes: [Change] = []

    static func record(_ index: Int) {
        changes.append(Change(index: index, uptime: ProcessInfo.processInfo.systemUptime))
    }

    public static func clear() {
        changes = []
    }
}

/// Draws `content` in each of `phases` in turn -- SwiftUI's `PhaseAnimator`.
/// With a trigger it goes through the phases once each time it changes and
/// ends on the first; without one it cycles for as long as the view is shown.
/// The move to a phase is drawn with `animation(phase)`.
/// 依序以 `phases` 中的每個階段畫出 `content`——SwiftUI 的 `PhaseAnimator`。有觸發條件時，每次它改變就經過所有階段
/// 一次、停在第一個;沒有的話，只要 view 還在就一直循環。移到某個階段時以 `animation(phase)` 畫出。
public struct PhaseAnimator<Phase: Equatable, Content: View>: View {
    @State private var model = PhaseAnimatorModel()
    let phases: [Phase]
    let trigger: AnyEquatableTrigger?
    let content: (Phase) -> Content
    let animation: (Phase) -> Animation?

    public init(
        _ phases: some Sequence<Phase>,
        trigger: some Equatable,
        @ViewBuilder content: @escaping (Phase) -> Content,
        animation: @escaping (Phase) -> Animation? = { _ in .default }
    ) {
        self.phases = Array(phases)
        self.trigger = AnyEquatableTrigger(trigger)
        self.content = content
        self.animation = animation
    }

    public init(
        _ phases: some Sequence<Phase>,
        @ViewBuilder content: @escaping (Phase) -> Content,
        animation: @escaping (Phase) -> Animation? = { _ in .default }
    ) {
        self.phases = Array(phases)
        trigger = nil
        self.content = content
        self.animation = animation
    }

    public var body: some View {
        let index = phases.isEmpty ? 0 : min(model.index, phases.count - 1)
        let phase = phases.isEmpty ? nil : phases[index]
        let _ = PhaseAnimatorDiagnostics.recordIfChanged(index, model: model)
        if let phase {
            content(phase)
                .animation(animation(phase), value: index)
                .onAppear {
                    guard trigger == nil else { return }
                    run(cycles: true)
                }
                .onChange(of: trigger) {
                    guard trigger != nil else { return }
                    run(cycles: false)
                }
        }
    }

    private func run(cycles: Bool) {
        let phases = phases
        let animation = animation
        model.run(count: phases.count, cycles: cycles) { animation(phases[$0]) }
    }
}

extension PhaseAnimatorDiagnostics {
    nonisolated(unsafe) private static var lastIndex: [ObjectIdentifier: Int] = [:]

    static func recordIfChanged(_ index: Int, model: PhaseAnimatorModel) {
        let id = ObjectIdentifier(model)
        if lastIndex[id] != index {
            lastIndex[id] = index
            record(index)
        }
    }
}

extension View {
    /// Draws this view through `content` in each of `phases`, once each time
    /// `trigger` changes -- SwiftUI's `phaseAnimator(_:trigger:content:animation:)`.
    /// 每次 `trigger` 改變，就依序以 `phases` 中的每個階段經由 `content` 畫出此 view——SwiftUI 的
    /// `phaseAnimator(_:trigger:content:animation:)`。
    public func phaseAnimator<Phase: Equatable, Modified: View>(
        _ phases: some Sequence<Phase>,
        trigger: some Equatable,
        @ViewBuilder content: @escaping (PlaceholderContentView<Self>, Phase) -> Modified,
        animation: @escaping (Phase) -> Animation? = { _ in .default }
    ) -> some View {
        PhaseAnimator(phases, trigger: trigger, content: { content(self, $0) }, animation: animation)
    }

    /// Cycles this view through `phases` for as long as it is shown --
    /// SwiftUI's `phaseAnimator(_:content:animation:)`.
    /// 只要此 view 還在，就讓它在 `phases` 之間循環——SwiftUI 的 `phaseAnimator(_:content:animation:)`。
    public func phaseAnimator<Phase: Equatable, Modified: View>(
        _ phases: some Sequence<Phase>,
        @ViewBuilder content: @escaping (PlaceholderContentView<Self>, Phase) -> Modified,
        animation: @escaping (Phase) -> Animation? = { _ in .default }
    ) -> some View {
        PhaseAnimator(phases, content: { content(self, $0) }, animation: animation)
    }
}
