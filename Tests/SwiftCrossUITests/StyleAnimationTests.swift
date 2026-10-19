import DummyBackend
import Testing

@testable @_spi(Backends) import SwiftCrossUI

/// Text colours and gradients under an animation: how a gradient is
/// interpolated (same stops, different stops), and the colour a `Text` is
/// laid out with. The driver has no clock here, so a started tween lands on
/// its end at once.
///
/// 動畫中的文字顏色與漸層：漸層如何插值(色標數相同、不同),以及 `Text` 排版時所用的顏色。這裡的 driver 沒有
/// 時鐘，所以啟動的補間會立刻落在終點。
@MainActor
@Suite("Style animation (text colour, gradients)")
struct StyleAnimationTests {
    let red = Color(red: 1, green: 0, blue: 0)
    let blue = Color(red: 0, green: 0, blue: 1)
    let green = Color(red: 0, green: 1, blue: 0)

    func rgb(_ color: Color) -> [Double] {
        let resolved = color.resolve(in: ViewGraphHelpers.environment)
        return [Double(resolved.red), Double(resolved.green), Double(resolved.blue)]
    }

    func close(_ a: [Double], _ b: [Double], _ tolerance: Double = 1e-6) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) <= tolerance }
    }

    @Test("Same number of stops: each stop's colour and location move to its partner")
    func sameStops() {
        let a = Gradient(stops: [.init(color: red, location: 0), .init(color: blue, location: 1)])
        let b = Gradient(stops: [.init(color: blue, location: 0.2), .init(color: red, location: 0.8)])
        let half = Gradient.interpolated(from: a, to: b, progress: 0.5)
        #expect(half.stops.count == 2)
        #expect(abs(half.stops[0].location - 0.1) < 1e-12)
        #expect(abs(half.stops[1].location - 0.9) < 1e-12)
        #expect(close(rgb(half.stops[0].color), [0.5, 0, 0.5]))
    }

    @Test("Different stops: sampled at the union of locations, exact at both ends")
    func differentStops() {
        let a = Gradient(colors: [red, blue])
        let b = Gradient(colors: [red, green, blue])
        #expect(close(rgb(a.color(at: 0.5)), [0.5, 0, 0.5]))
        let start = Gradient.interpolated(from: a, to: b, progress: 0)
        #expect(start.stops.map(\.location) == [0, 0.5, 1])
        #expect(close(rgb(start.stops[1].color), [0.5, 0, 0.5]))
        let end = Gradient.interpolated(from: a, to: b, progress: 1)
        #expect(close(rgb(end.stops[1].color), [0, 1, 0]))
        let mid = Gradient.interpolated(from: a, to: b, progress: 0.5)
        #expect(close(rgb(mid.stops[1].color), [0.25, 0.5, 0.25]))
    }

    @Test("A drawing moves its points and scalars; a change of form takes the target's geometry")
    func drawing() {
        let gradient = Gradient(colors: [red, blue])
        let a = GradientDrawing(gradient: gradient, points: [.top, .bottom], scalars: [])
        let b = GradientDrawing(gradient: gradient, points: [.leading, .trailing], scalars: [])
        let half = GradientDrawing.interpolated(from: a, to: b, progress: 0.5)
        #expect(half.points[0] == UnitPoint(x: 0.25, y: 0.25))
        #expect(half.points[1] == UnitPoint(x: 0.75, y: 0.75))
        let open = GradientDrawing(gradient: gradient, points: [.center], scalars: [0], isOpen: true)
        let sweep = GradientDrawing(gradient: gradient, points: [.center], scalars: [0, 3], isOpen: false)
        #expect(GradientDrawing.interpolated(from: open, to: sweep, progress: 0.3).scalars == [0, 3])
    }

    @Test("Text: a set colour is laid out through its tween; an unset one stays unset at rest")
    func textColour() {
        let storage = TextColorStorage()
        var environment = ViewGraphHelpers.environment
        #expect(storage.environment(for: environment).foregroundColor == nil)
        environment.foregroundColor = red
        let first = storage.environment(for: environment)
        #expect(first.foregroundColor.map(rgb) == [1, 0, 0])
        environment.foregroundColor = blue
        environment.effectAnimationOverride = EffectTransaction(
            animation: .linear(duration: 1), group: nil, token: .value(-1)
        )
        let animated = storage.environment(for: environment)
        // No clock: the tween has landed on blue. / 沒有時鐘：補間已落在藍色。
        #expect(animated.foregroundColor.map(rgb) == [0, 0, 1])
        #expect(storage.color?.isAnimating == false)
    }
}
