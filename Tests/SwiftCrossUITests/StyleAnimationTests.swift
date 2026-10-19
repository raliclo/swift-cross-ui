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
        #expect(storage.fill?.isAnimating == false)
    }

    func linear(_ colors: [Color], _ start: UnitPoint = .top, _ end: UnitPoint = .bottom) -> FillDrawing {
        .linear(GradientDrawing(gradient: Gradient(colors: colors), points: [start, end], scalars: []))
    }

    func radial(_ colors: [Color], _ endRadius: Double) -> FillDrawing {
        .radial(GradientDrawing(gradient: Gradient(colors: colors), points: [.center], scalars: [0, endRadius]))
    }

    func stops(_ fill: FillDrawing) -> [[Double]] {
        switch fill {
            case .color(let color): [rgb(color)]
            case .linear(let drawing), .radial(let drawing): drawing.gradient.stops.map { rgb($0.color) }
        }
    }

    @Test("A fill tweens colour to colour as a colour, and is exactly the given value at both ends")
    func fillColours() {
        let half = FillDrawing.interpolated(from: .color(red), to: .color(blue), progress: 0.5)
        #expect(!half.isGradient)
        #expect(close(stops(half)[0], [0.5, 0, 0.5]))
        let gradient = linear([red, blue])
        #expect(FillDrawing.interpolated(from: .color(red), to: gradient, progress: 0) == .color(red))
        #expect(FillDrawing.interpolated(from: .color(red), to: gradient, progress: 1) == gradient)
    }

    @Test("Colour to gradient: the gradient with every stop in that colour, moving to its own stops")
    func fillColourToGradient() {
        let gradient = linear([red, blue], .leading, .trailing)
        let half = FillDrawing.interpolated(from: .color(green), to: gradient, progress: 0.5)
        guard case .linear(let drawing) = half else {
            Issue.record("expected a linear gradient, got \(half)")
            return
        }
        // Geometry is the gradient's; each stop is halfway from green.
        // 幾何是漸層的;每個色標都從綠色走到一半。
        #expect(drawing.points == [.leading, .trailing])
        #expect(close(stops(half)[0], [0.5, 0.5, 0]))
        #expect(close(stops(half)[1], [0, 0.5, 0.5]))
        // And back. / 以及反過來。
        let back = FillDrawing.interpolated(from: gradient, to: .color(green), progress: 0.25)
        #expect(close(stops(back)[0], [0.75, 0.25, 0]))
    }

    @Test("Gradient to gradient moves stops, points and radii; linear to radial takes the target's geometry")
    func fillGradients() {
        let a = radial([red, blue], 0.2)
        let b = radial([blue, red], 0.6)
        guard case .radial(let half) = FillDrawing.interpolated(from: a, to: b, progress: 0.5) else {
            Issue.record("expected a radial gradient")
            return
        }
        #expect(close(half.scalars, [0, 0.4]))
        #expect(close(rgb(half.gradient.stops[0].color), [0.5, 0, 0.5]))
        let mixed = FillDrawing.interpolated(from: linear([red, blue]), to: b, progress: 0.5)
        guard case .radial(let drawing) = mixed else {
            Issue.record("expected the target's kind, radial")
            return
        }
        #expect(drawing.scalars == [0, 0.6])
        #expect(drawing.points == [.center])
    }

    @Test("A fill style goes to a FillDrawing and back unchanged")
    func fillRoundTrip() {
        let environment = ViewGraphHelpers.environment
        let style = ResolvedFillStyle.radialGradient(
            Gradient(colors: [red, blue]), center: .topLeading, startRadius: 0.1, endRadius: 0.9
        )
        let drawing = FillDrawing(style, in: environment)
        guard case .radialGradient(let gradient, let center, let r0, let r1) = drawing.style(in: environment)
        else {
            Issue.record("expected a radial gradient")
            return
        }
        #expect(center == .topLeading)
        #expect(r0 == 0.1 && r1 == 0.9)
        #expect(gradient.stops.map { rgb($0.color) } == [[1, 0, 0], [0, 0, 1]])
    }

    @Test("Text with a gradient foreground style hands the backend a text gradient; a colour clears it")
    func textGradient() {
        let storage = TextColorStorage()
        var environment = ViewGraphHelpers.environment
        environment.foregroundShapeStyle = LinearGradient(colors: [red, blue], startPoint: .leading, endPoint: .trailing)
        let drawn = storage.environment(for: environment)
        guard case .linearGradient(let gradient, let start, let end) = drawn.textGradient else {
            Issue.record("expected a text gradient, got \(String(describing: drawn.textGradient))")
            return
        }
        #expect(start == .leading && end == .trailing)
        #expect(gradient.stops.map { rgb($0.color) } == [[1, 0, 0], [0, 0, 1]])
        // The foreground colour is the gradient's middle. / 前景色是漸層的中間。
        #expect(drawn.foregroundColor.map { close(rgb($0), [0.5, 0, 0.5]) } == true)

        environment.foregroundShapeStyle = nil
        environment.foregroundColor = green
        let flat = storage.environment(for: environment)
        #expect(flat.textGradient == nil)
        #expect(flat.foregroundColor.map(rgb) == [0, 1, 0])
    }

    @Test("Unfilled shapes and text use the foreground style, else the foreground colour")
    func foreground() {
        var environment = ViewGraphHelpers.environment
        environment.foregroundColor = red
        #expect(FillDrawing.foreground(in: environment) == .color(Color(red.resolve(in: environment))))
        environment.foregroundShapeStyle = RadialGradient(
            colors: [red, blue], center: .center, startRadius: 0, endRadius: 0.5
        )
        guard case .radial(let drawing) = FillDrawing.foreground(in: environment) else {
            Issue.record("expected a radial gradient")
            return
        }
        #expect(drawing.scalars == [0, 0.5])
    }
}
