import Foundation
import Testing

@testable @_spi(Backends) import SwiftCrossUI

/// GSAP's MotionPath: measuring a `Path` by length (points, directions,
/// trimming) and the effect that places a view on it.
///
/// GSAP 的 MotionPath:以長度量測 `Path`(點、方向、裁切),以及把 view 放在路徑上的效果。
@MainActor
@Suite("Motion path")
struct MotionPathTests {
    func close(_ a: Double, _ b: Double, _ tolerance: Double = 1e-9) -> Bool {
        abs(a - b) <= tolerance
    }

    func close(_ a: SIMD2<Double>?, _ b: SIMD2<Double>, _ tolerance: Double = 1e-9) -> Bool {
        guard let a else { return false }
        return close(a.x, b.x, tolerance) && close(a.y, b.y, tolerance)
    }

    var lShape: Path {
        Path().move(to: SIMD2(0, 0)).addLine(to: SIMD2(100, 0)).addLine(to: SIMD2(100, 50))
    }

    @Test("Lines: length, points by length and the direction of travel")
    func lines() {
        let path = lShape
        #expect(close(path.length, 150))
        #expect(close(path.point(at: 0)?.position, SIMD2(0, 0)))
        #expect(close(path.point(at: 0.5)?.position, SIMD2(75, 0)))
        #expect(close(path.point(at: 0.8)?.position, SIMD2(100, 20)))
        #expect(close(path.point(at: 1)?.position, SIMD2(100, 50)))
        #expect(path.point(at: 0.5)?.direction == .zero)
        // Down the screen is a quarter turn clockwise. / 往螢幕下方是順時針四分之一圈。
        #expect(close(path.point(at: 0.8)?.direction.radians ?? 0, .pi / 2))
        #expect(close(path.currentPoint, SIMD2(100, 50)))
        #expect(Path().point(at: 0.5) == nil)
    }

    @Test("A circle measures 2π r and runs clockwise from the trailing point")
    func circle() {
        let path = Path().addCircle(center: SIMD2(0, 0), radius: 100)
        #expect(close(path.length, 2 * .pi * 100, 0.01))
        #expect(close(path.point(at: 0.25)?.position, SIMD2(0, 100), 0.01))
        // Tangent at the bottom points to the leading side.
        // 在最下方的切線指向前緣那一側。
        let direction = path.point(at: 0.25)?.direction.radians ?? 0
        #expect(close(abs(direction), .pi, 0.01))
    }

    @Test("Curves: a quadratic's end and length against its chord")
    func curves() {
        let path = Path().move(to: SIMD2(0, 0)).addQuadCurve(control: SIMD2(50, 100), to: SIMD2(100, 0))
        #expect(close(path.point(at: 1)?.position, SIMD2(100, 0)))
        // Symmetric: the middle by length is the apex (50, 50).
        // 對稱：長度的中點就是頂點 (50, 50)。
        #expect(close(path.point(at: 0.5)?.position, SIMD2(50, 50), 0.05))
        #expect(path.length > 100 && path.length < 2 * (50 * 50 + 100 * 100).squareRoot())
    }

    @Test("Arcs go the way `clockwise` says; transforms move what came before")
    func arcsAndTransforms() {
        let clockwise = Path().addArc(center: .zero, radius: 10, startAngle: 0, endAngle: .pi / 2, clockwise: true)
        #expect(close(clockwise.length, 5 * .pi, 1e-3))
        #expect(close(clockwise.point(at: 1)?.position, SIMD2(0, 10), 1e-9))
        let counter = Path().addArc(center: .zero, radius: 10, startAngle: 0, endAngle: .pi / 2, clockwise: false)
        #expect(close(counter.length, 15 * .pi, 1e-2))

        let moved = lShape.applyTransform(.translation(x: 10, y: 20))
        #expect(close(moved.point(at: 0)?.position, SIMD2(10, 20)))
        #expect(close(moved.length, 150))
    }

    @Test("Subpaths: the jump between them is not part of the length")
    func subpaths() {
        let path = Path()
            .move(to: SIMD2(0, 0)).addLine(to: SIMD2(10, 0))
            .move(to: SIMD2(100, 100)).addLine(to: SIMD2(100, 110))
        #expect(close(path.length, 20))
        #expect(close(path.point(at: 0.75)?.position, SIMD2(100, 105)))
    }

    @Test("trimmedPath keeps the part between two fractions; its end is currentPoint")
    func trimmed() {
        let trimmed = lShape.trimmedPath(from: 0.2, to: 0.8)
        #expect(close(trimmed.length, 90))
        #expect(close(trimmed.point(at: 0)?.position, SIMD2(30, 0)))
        #expect(close(trimmed.currentPoint, SIMD2(100, 20)))
        #expect(lShape.trimmedPath(from: 0.6, to: 0.3).actions.isEmpty)
        // SwiftUI's idiom for "where along the path": the trimmed path's end.
        // SwiftUI 表達「在路徑上的哪裡」的慣用法：裁切後路徑的終點。
        #expect(close(lShape.trimmedPath(from: 0, to: 0.5).currentPoint, lShape.point(at: 0.5)!.position))
    }

    @Test("The effect puts the anchor on the point and turns about it")
    func effect() {
        let measure = PathMeasure(lShape)
        let size = SIMD2<Double>(20, 10)
        let plain = MotionPathModifier<EmptyView>.effect(
            measure, progress: 0.8, size: size, anchor: .center, orientsAlongPath: false
        )
        #expect(close(plain.translation, SIMD2(90, 15)))
        #expect(plain.rotation == .zero)
        let turned = MotionPathModifier<EmptyView>.effect(
            measure, progress: 0.8, size: size, anchor: .center, orientsAlongPath: true
        )
        #expect(close(turned.rotation.radians, .pi / 2))
        // Wherever the view is turned, its centre lands on the path.
        // 不論 view 怎麼轉，它的中心都落在路徑上。
        let transform = turned.resolved(in: size)
        let centre = PathMeasure.apply(transform, SIMD2(10, 5))
        #expect(close(centre, SIMD2(100, 20), 1e-9))
        let corner = MotionPathModifier<EmptyView>.effect(
            measure, progress: 0, size: size, anchor: .topLeading, orientsAlongPath: false
        )
        #expect(close(corner.translation, SIMD2(0, 0)))
    }
}
