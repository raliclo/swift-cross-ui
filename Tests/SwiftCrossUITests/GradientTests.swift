import DummyBackend
import Testing
@testable @_spi(Backends) import SwiftCrossUI

@Suite("Test Gradients")
@MainActor
struct GradientTests {
    @Test("Automatic equal distribution of color")
    func testAutomaticColorDistribution() async throws {
        let gradient = Gradient(colors: .init(repeating: .red, count: 12))

        checkExpectations(gradient: gradient)

        func checkExpectations(gradient: Gradient) {
            let count = Double(gradient.stops.count) - 1

            for (i, stop) in gradient.stops.enumerated() {
                #expect(stop.location ~= (Double(i) / count))
            }
        }
    }

    @Test("Empty array creates transparent stops")
    func testEmptyArrayCreatesTransparentStops() async throws {
        let gradient = Gradient(colors: [])

        #expect(gradient.stops.count == 2)
        #expect(gradient.stops.first!.color.opacityMultiplier == 0)
        #expect(gradient.stops.first!.location == 0)
        #expect(gradient.stops.last!.color.opacityMultiplier == 0)
        #expect(gradient.stops.last!.location == 1)
    }

    @Test("Single color array creates 2 stops of color")
    func testSingleColorArrayCreates2Stops() async throws {
        let gradient = Gradient(colors: [.red])

        #expect(gradient.stops.count == 2)
        #expect(gradient.stops.first!.color == .red)
        #expect(gradient.stops.first!.location == 0)
        #expect(gradient.stops.last!.color == .red)
        #expect(gradient.stops.last!.location == 1)
    }

    @Test("Color order stays the same")
    func testColorOrderStays() async throws {
        let colors: [Color] = [
            .red,
            .orange,
            .yellow,
            .green,
            .blue,
            .purple
        ]

        let gradient = Gradient(colors: colors)

        for (i, stop) in gradient.stops.enumerated() {
            #expect(colors[i] == stop.color)
        }
    }

    @Test("Angular: Unspecified end angle returns original stops")
    func nilEndAngleReturnsOriginalStops() async throws {
        let gradient = AngularGradient(
            stops: [
                .init(color: .red, location: 0),
                .init(color: .blue, location: 1)
            ],
            center: .center,
            angle: .degrees(45)
        )

        let result = gradient.adjustedStops

        #expect(gradient.endAngle == nil)
        #expect(result == gradient.gradient.stops)
    }

    @Test("Angular: Positive range scales correctly")
    func positiveRangeScalesCorrectly() async throws {
        let gradient = AngularGradient(
            stops: [
                .init(color: .red, location: 0),
                .init(color: .blue, location: 0.5),
                .init(color: .green, location: 1)
            ],
            center: .center,
            startAngle: .degrees(0),
            endAngle: .degrees(180)
        )

        let result = gradient.adjustedStops

        #expect(result[0].location == 0)
        #expect(result[1].location ~= 0.25)
        #expect(result[2].location ~= 0.5)
    }

    @Test("Angular: Negative range inverts locations")
    func negativeRangeReversesAndInverts() async throws {
        let gradient = AngularGradient(
            stops: [
                .init(color: .red, location: 0),
                .init(color: .blue, location: 0.5),
                .init(color: .green, location: 1)
            ],
            center: .center,
            startAngle: .degrees(180),
            endAngle: .degrees(0)
        )

        let result = gradient.adjustedStops

        #expect(result[0].color == .green)
        #expect(result[0].location ~= 0)
        #expect(result[1].location ~= 0.25)
        #expect(result[2].location ~= 0.5)
    }

    @Test("Angular: Full circle range")
    func fullCircleRange() async throws {
        let gradient = AngularGradient(
            stops: [
                .init(color: .red, location: 0),
                .init(color: .blue, location: 1)
            ],
            center: .center,
            startAngle: .degrees(0),
            endAngle: .degrees(360)
        )

        let result = gradient.adjustedStops

        #expect(result[0].location == 0)
        #expect(result[1].location ~= 1.0)
    }

    @Test("Radial: negative range returns inverted stops")
    func radialNegativeRangeReturnsInvertedStops() async throws {
        let gradient = RadialGradient(
            stops: [
                .init(color: .red, location: 0.25),
                .init(color: .blue, location: 1)
            ],
            center: .center,
            startRadius: 300,
            endRadius: 0
        )

        let result = gradient.adjustedStops
        let expectedResult: [Gradient.Stop] = [
            .init(color: .blue, location: 0),
            .init(color: .red, location: 0.75)
        ]

        #expect(result == expectedResult)
    }

    @Test("Radial: starting at 0 returns original stops")
    func radialStartingAtZeroReturnsOriginalStops() async throws {
        let gradient = RadialGradient(
            stops: [
                .init(color: .red, location: 0),
                .init(color: .blue, location: 1)
            ],
            center: .center,
            startRadius: 0,
            endRadius: 300
        )

        let result = gradient.adjustedStops

        #expect(result == gradient.gradient.stops)
    }

    @Test("Radial: stops location gets adjusted correctly")
    func radialStopsLocationAdjustedCorrectly() async throws {
        let gradient = RadialGradient(
            stops: [
                .init(color: .red, location: 0),
                .init(color: .green, location: 0.5),
                .init(color: .blue, location: 1)
            ],
            center: .center,
            startRadius: 100,
            endRadius: 200
        )

        let result = gradient.adjustedStops

        #expect(result[0].location ~= 0.5)
        #expect(result[1].location ~= 0.75)
        #expect(result[2].location ~= 1)
    }

    /// The case that was wrong, and it is the commonest gradient there is.
    ///
    /// `Gradient(colors: [.red, .blue])` puts its stops at 0.0 and 1.0. Both
    /// are exactly 0.5 away from the middle; `min(by:)` keeps the first of an
    /// equal pair, so "the stop nearest 0.5" was red. Every backend without a
    /// gradient implementation drew a red rectangle where a red-to-blue ramp
    /// belonged, which reads as the gradient having been ignored -- the exact
    /// outcome `flattened(in:)`'s own note says it exists to avoid.
    ///
    /// 曾經出錯的那個情況，而它是最常見的漸層。
    ///
    /// `Gradient(colors: [.red, .blue])` 的 stop 落在 0.0 與 1.0。兩者距中點都恰好是 0.5；
    /// `min(by:)` 在相等時保留前者，因此「最接近 0.5 的 stop」是紅色。每一個沒有實作漸層的
    /// backend 都會在本該是紅到藍漸變的位置畫出一個紅色矩形，而那讀起來像是漸層被忽略了
    /// ——正是 `flattened(in:)` 自己的說明所稱它要避免的結果。
    @Test("A two-stop gradient flattens to the blend, not to its first stop")
    func testTwoStopGradientFlattensToTheMiddle() {
        let backend = DummyBackend()
        let environment = EnvironmentValues(backend: backend)

        let flattened = ResolvedFillStyle
            .linearGradient(Gradient(colors: [.red, .blue]), startPoint: .top, endPoint: .bottom)
            .flattened(in: environment)

        let red = Color.red.resolve(in: environment)
        let blue = Color.blue.resolve(in: environment)

        #expect(flattened != red)
        #expect(flattened != blue)
        #expect(abs(flattened.red - (red.red + blue.red) / 2) < 0.001)
        #expect(abs(flattened.blue - (red.blue + blue.blue) / 2) < 0.001)
    }

    /// Unevenly spaced stops, which is what the old comment was really about.
    ///
    /// Stops at 0.0, 0.9 and 1.0: the midpoint lies in the first span, nine
    /// tenths of the way from its start to its end being wrong -- it is
    /// five ninths. Picking a stop cannot express that at all.
    ///
    /// 不等距的 stop，那才是舊註解真正指的情況。
    ///
    /// stop 位於 0.0、0.9 與 1.0：中點落在第一段之內，而「從該段起點走九成」是錯的——正確是九分
    /// 之五。「挑一個 stop」根本表達不了這件事。
    @Test("An unevenly spaced gradient interpolates within the right span")
    func testUnevenGradientFlattensWithinItsSpan() {
        let backend = DummyBackend()
        let environment = EnvironmentValues(backend: backend)

        let gradient = Gradient(stops: [
            .init(color: .black, location: 0.0),
            .init(color: .white, location: 0.9),
            .init(color: .black, location: 1.0),
        ])
        let flattened = ResolvedFillStyle
            .linearGradient(gradient, startPoint: .top, endPoint: .bottom)
            .flattened(in: environment)

        // 0.5 is five ninths of the way from 0.0 to 0.9.
        // 0.5 位於 0.0 到 0.9 之間的九分之五處。
        #expect(abs(flattened.red - Float(5.0 / 9.0)) < 0.01)
    }

    /// A gradient entirely on one side of the middle has no midpoint, and the
    /// nearest end is the honest answer rather than an extrapolation.
    ///
    /// 一個整段都落在中點同一側的漸層沒有中點可言，而離它最近的那一端才是誠實的答案，
    /// 不是外插出來的值。
    @Test("A gradient that does not reach 0.5 flattens to its nearest end")
    func testGradientClusteredAtOneEnd() {
        let backend = DummyBackend()
        let environment = EnvironmentValues(backend: backend)

        let gradient = Gradient(stops: [
            .init(color: .red, location: 0.7),
            .init(color: .blue, location: 1.0),
        ])
        let flattened = ResolvedFillStyle
            .linearGradient(gradient, startPoint: .top, endPoint: .bottom)
            .flattened(in: environment)

        #expect(flattened == Color.red.resolve(in: environment))
    }
}

fileprivate extension Double {
    static func ~= (lhs: Self, rhs: Self) -> Bool {
        abs(lhs - rhs) < 1e-6
    }
}
