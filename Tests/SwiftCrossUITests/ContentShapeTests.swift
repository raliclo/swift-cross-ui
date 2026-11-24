import DummyBackend
import Testing

@testable @_spi(Backends) import SwiftCrossUI

/// contentShape(_:eoFill:) resolves a shape into a HitRegion that backends test
/// pointer positions against.
/// contentShape(_:eoFill:) 把形狀解析為 HitRegion,backend 以它判斷指標位置。
@MainActor
struct ContentShapeTests {
    func region(_ shape: some Shape, width: Double, height: Double, eoFill: Bool = false)
        -> HitRegion
    {
        HitRegion(
            path: shape.path(in: Path.Rect(x: 0, y: 0, width: width, height: height)),
            evenOdd: eoFill
        )
    }

    @Test("A circle in a square takes its centre and not its corners")
    func circle() {
        let circle = region(Circle(), width: 120, height: 120)
        #expect(circle.contains([60, 60]))
        #expect(circle.contains([60, 3]))
        #expect(circle.contains([115, 60]))
        #expect(!circle.contains([5, 5]))
        #expect(!circle.contains([115, 115]))
        #expect(!circle.contains([5, 115]))
        // Just inside and just outside the radius along a diagonal.
        // 沿對角線，半徑內側一點與外側一點。
        let d = 60 / 2.0.squareRoot()
        #expect(circle.contains([60 + d - 1, 60 + d - 1]))
        #expect(!circle.contains([60 + d + 1, 60 + d + 1]))
    }

    @Test("A rectangle takes its whole frame and nothing outside it")
    func rectangle() {
        let rectangle = region(Rectangle(), width: 300, height: 40)
        #expect(rectangle.contains([1, 1]))
        #expect(rectangle.contains([150, 20]))
        #expect(rectangle.contains([299, 39]))
        #expect(!rectangle.contains([301, 20]))
        #expect(!rectangle.contains([150, -1]))
    }

    @Test("An ellipse follows its own width and height")
    func ellipse() {
        let ellipse = region(Ellipse(), width: 200, height: 100)
        #expect(ellipse.contains([100, 50]))
        #expect(ellipse.contains([195, 50]))
        #expect(ellipse.contains([100, 5]))
        #expect(!ellipse.contains([10, 10]))
        #expect(!ellipse.contains([190, 90]))
    }

    @Test("Even-odd leaves a hole where non-zero winding fills it")
    func fillRule() {
        // Two rectangles drawn the same direction, one inside the other.
        // 兩個同方向繪製、一個在另一個之內的矩形。
        let path = Path()
            .addRectangle(Path.Rect(x: 0, y: 0, width: 100, height: 100))
            .addRectangle(Path.Rect(x: 25, y: 25, width: 50, height: 50))
        #expect(HitRegion(path: path, evenOdd: false).contains([50, 50]))
        #expect(!HitRegion(path: path, evenOdd: true).contains([50, 50]))
        #expect(HitRegion(path: path, evenOdd: true).contains([10, 50]))
    }

    @Test("Lines and curves close back to their start; a transform moves what came before")
    func flattening() {
        let triangle = HitRegion(
            path: Path().move(to: [0, 0]).addLine(to: [100, 0]).addLine(to: [0, 100])
        )
        #expect(triangle.contains([10, 10]))
        #expect(!triangle.contains([90, 90]))

        let moved = HitRegion(
            path: Path()
                .addRectangle(Path.Rect(x: 0, y: 0, width: 10, height: 10))
                .applyTransform(.translation(x: 50, y: 0))
        )
        #expect(moved.contains([55, 5]))
        #expect(!moved.contains([5, 5]))

        let curve = HitRegion(
            path: Path().move(to: [0, 0]).addQuadCurve(control: [50, 100], to: [100, 0])
        )
        #expect(curve.contains([50, 40]))
        #expect(!curve.contains([50, 60]))
        #expect(HitRegion(path: Path()).contains([0, 0]) == false)
    }

    @Test("Scaling for device pixels scales every point")
    func scaling() {
        let circle = region(Circle(), width: 10, height: 10).scaled(by: 3)
        #expect(circle.contains([15, 15]))
        #expect(!circle.contains([2, 2]))
        #expect(circle.flattenedPoints.count == 2 * circle.contourPointCounts.reduce(0, +))
    }

    @Test("The modifier gives the content's widget the shape resolved at its size")
    func modifierCommitsRegion() {
        let node = ViewGraphHelpers.committedNode(
            for: Color.red.frame(width: 80, height: 40).contentShape(Circle())
        )
        let widget = node.widget
        let committed = widget.contentShape
        #expect(committed == region(Circle(), width: 80, height: 40))
        #expect(committed?.contains([40, 20]) == true)
        #expect(committed?.contains([2, 2]) == false)
    }

    @Test("The shape travels up through a one-child wrapper and not through a stack")
    func preference() {
        func shape<V: View>(of view: V) -> ContentShape? {
            ViewGraphHelpers.computeLayout(of: view).preferences.contentShape
        }
        #expect(shape(of: Color.red) == nil)
        #expect(shape(of: Color.red.contentShape(Circle())) != nil)
        #expect(shape(of: Color.red.contentShape(Circle()).padding(4)) != nil)
        #expect(shape(of: HStack { Color.red.contentShape(Circle()); Color.blue }) == nil)
        #expect(shape(of: Color.red.contentShape(Circle(), eoFill: true))?.eoFill == true)
    }

    @Test("contentShape leaves the layout alone")
    func layoutUnchanged() {
        let plain = ViewGraphHelpers.computeLayout(of: Color.red.frame(width: 30, height: 20))
        let shaped = ViewGraphHelpers.computeLayout(
            of: Color.red.frame(width: 30, height: 20).contentShape(Circle())
        )
        #expect(plain.size == shaped.size)
    }
}
