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

    @Test("A transform maps every point of a region, and the identity changes nothing")
    func applyingTransform() {
        let square = region(Rectangle(), width: 10, height: 10)
        #expect(square.applying(.identity) == square)
        let moved = square.applying(.translation(x: 100, y: 20))
        #expect(moved.contains([105, 25]))
        #expect(!moved.contains([5, 5]))
        // A quarter turn about the square's corner puts it to the left of the y axis.
        // 繞正方形角落轉四分之一圈，會把它放到 y 軸左側。
        let turned = square.applying(.rotation(degrees: 90, center: [0, 0]))
        #expect(turned.contains([-5, 5]))
        #expect(!turned.contains([5, 5]))
    }

    @Test("A geometric effect moves the shape with the drawn view, for a wrapper outside it")
    func geometricEffectMovesShape() {
        let shape = ViewGraphHelpers.computeLayout(
            of: Color.red.frame(width: 80, height: 80).contentShape(Circle()).offset(x: 100, y: 0)
        ).preferences.contentShape
        let size = ViewSize(80, 80)
        // Outside the effect the circle is where it is drawn, 100 points along.
        // 在效果之外，圓位於它被畫出之處，即右移 100 點。
        #expect(shape?.region(in: size).contains([140, 40]) == true)
        #expect(shape?.region(in: size).contains([40, 40]) == false)
        // The effect's own container is moved by its parent, so its coordinates
        // are the untransformed ones and the outermost effect is left out.
        // 效果自身的容器由父元件移動，其座標是未經變換的，因此最外層的效果不予套用。
        #expect(shape?.region(in: size, outermostEffectApplied: false).contains([40, 40]) == true)

        let scaled = ViewGraphHelpers.computeLayout(
            of: Color.red.frame(width: 80, height: 80).contentShape(Circle())
                .offset(x: 100, y: 0).scaleEffect(0.5)
        ).preferences.contentShape
        // Scaled by half about the centre after the offset: the circle's centre
        // (140, 40) goes to (40 + 0.5 * 100, 40) = (90, 40), radius 20.
        // 位移之後再繞中心縮為一半：圓心 (140, 40) 移到 (40 + 0.5 * 100, 40) = (90, 40),半徑 20。
        #expect(scaled?.region(in: size).contains([90, 40]) == true)
        #expect(scaled?.region(in: size).contains([90, 65]) == false)
        #expect(scaled?.region(in: size, outermostEffectApplied: false).contains([140, 40]) == true)
    }

    @Test("A pointer modifier's own widget takes the shape of the view it wraps")
    func pointerModifierAdoptsShape() {
        let node = ViewGraphHelpers.committedNode(
            for: Color.red.frame(width: 80, height: 40).contentShape(Circle())
                .onDrop(of: [.plainText]) { (_: [DropItem]) in true }
        )
        let adopted = node.widget.contentShape
        #expect(adopted == region(Circle(), width: 80, height: 40))
        #expect(adopted?.contains([2, 2]) == false)

        // Through a geometric effect, the wrapper's shape is where the view is drawn.
        // 經過幾何效果時，包裝層的形狀位於 view 被畫出之處。
        let moved = ViewGraphHelpers.committedNode(
            for: Color.red.frame(width: 80, height: 40).contentShape(Circle())
                .offset(x: 0, y: 30)
                .onDrop(of: [.plainText]) { (_: [DropItem]) in true }
        )
        #expect(moved.widget.contentShape?.contains([40, 50]) == true)
        #expect(moved.widget.contentShape?.contains([40, 12]) == false)

        // Without a shape the wrapper keeps its whole frame.
        // 沒有形狀時，包裝層保留整個 frame。
        let plain = ViewGraphHelpers.committedNode(
            for: Color.red.frame(width: 80, height: 40)
                .onDrop(of: [.plainText]) { (_: [DropItem]) in true }
        )
        #expect(plain.widget.contentShape == nil)
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
