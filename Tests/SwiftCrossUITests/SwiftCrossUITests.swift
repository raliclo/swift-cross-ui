import Testing
import Foundation

import DummyBackend
@testable @_spi(Backends) import SwiftCrossUI

#if canImport(AppKitBackend)
    import AppKit
    import CoreGraphics
    @testable import AppKitBackend
#endif

/// The stack `CounterView` pads, on its own.
///
/// Split out so `testBasicLayout` can measure the same subtree with and without
/// padding. Keeping a second copy of the three controls here instead would let
/// the two drift apart silently, and the test compares them against each other.
///
/// 從 `CounterView` 中分離出來的未加 padding 版本，讓 `testBasicLayout` 能就同一棵子樹
/// 分別量測有無 padding 的結果。若改為在此另寫一份相同的三個控制項，兩者會在無人察覺的
/// 情況下逐漸分歧——而該測試正是拿它們互相比較。
struct CounterStack: View {
    @State var count = 0

    var body: some View {
        VStack {
            Button("Decrease") { count -= 1 }
            Text("Count: 1")
            Button("Increase") { count += 1 }
        }
    }
}

struct CounterView: View {
    var body: some View {
        CounterStack().padding()
    }
}

struct TestError: LocalizedError {
    var message: String

    var errorDescription: String? {
        message
    }
}

@Suite("Testing for SwiftCrossUI")
struct SwiftCrossUITests {
    @Test("Ensures that a NavigationPath can be round tripped to and from JSON")
    func testCodableNavigationPath() throws {
        var path = NavigationPath()
        path.append("a")
        path.append(1)
        path.append([1, 2, 3])
        path.append(5.0)

        let components = path.path(destinationTypes: [
            String.self,
            Int.self,
            [Int].self,
            Double.self,
        ])

        let encoded = try JSONEncoder().encode(path)
        let decodedPath = try JSONDecoder().decode(NavigationPath.self, from: encoded)

        let decodedComponents = decodedPath.path(destinationTypes: [
            String.self,
            Int.self,
            [Int].self,
            Double.self,
        ])

        #expect(Self.compareComponents(ofType: String.self, components[0], decodedComponents[0]))
        #expect(Self.compareComponents(ofType: Int.self, components[1], decodedComponents[1]))
        #expect(Self.compareComponents(ofType: [Int].self, components[2], decodedComponents[2]))
        #expect(Self.compareComponents(ofType: Double.self, components[3], decodedComponents[3]))
    }

    /// Helper function for `testCodableNavigationPath`.
    static func compareComponents<T: Equatable>(
        ofType type: T.Type,
        _ original: Any,
        _ decoded: Any
    ) -> Bool {
        guard
            let original = original as? T,
            let decoded = decoded as? T
        else {
            return false
        }

        return original == decoded
    }

    @Test("Ensure that ScrollView satisfies basic invariants")
    @MainActor
    func testBasicScrollView() async throws {
        let backend = DummyBackend()
        let window = backend.createWindow(withDefaultSize: nil, id: "window")
        let environment = EnvironmentValues(backend: backend)
            .with(\.window, window)

        let blueRectangleHeight = Double(100)
        let view = ScrollView {
            Color.blue.frame(height: blueRectangleHeight)
        }

        let viewGraph = ViewGraph(
            for: view,
            backend: backend,
            environment: environment
        )
        let proposedSize = ViewSize(80, 80)
        let result = viewGraph.computeLayout(
            proposedSize: ProposedViewSize(proposedSize),
            environment: environment
        )
        viewGraph.commit()

        #expect(result.size == ViewSize(80, 80))

        let rootWidget: DummyBackend.Widget = viewGraph.rootNode.widget.into()
        let scrollView = try #require(
            rootWidget.firstWidget(ofType: DummyBackend.ScrollContainer.self)
        )

        #expect(scrollView.hasVerticalScrollBar)
        #expect(!scrollView.hasHorizontalScrollBar)

        #expect(scrollView.size == proposedSize.vector)
        let expectedSize = ViewSize(
            proposedSize.width - Double(backend.scrollBarWidth),
            blueRectangleHeight
        )

        // Direct child of ScrollView is container used to position actual child
        // (for alignment purposes)
        let child = scrollView.child.getChildren()[0]
        #expect(child.size == expectedSize.vector)
    }

    @Test("Ensure that preferredColorScheme modifier works")
    @MainActor
    func testPreferredColorScheme() async throws {
        let backend = DummyBackend()
        let environment = EnvironmentValues(backend: backend)
            .with(\.defaultLaunchBehavior, .presented)

        #expect(environment.colorScheme == .light)

        let ambientColorScheme = Box<ColorScheme?>(nil)

        struct TestView: View {
            @Environment(\.colorScheme) var colorScheme
            var ambientColorScheme: Box<ColorScheme?>

            var body: some View {
                VStack {
                    Text("Button")
                    Button("Button") {}
                        .preferredColorScheme(.dark)
                }
                .onChange(of: colorScheme) {
                    ambientColorScheme.value = colorScheme
                }
            }
        }

        let scene = Window("Test", id: "test") {
            TestView(ambientColorScheme: ambientColorScheme)
        }

        let node = type(of: scene).Node(from: scene, backend: backend, environment: environment)
        node.update(backend: backend, environment: environment)

        let window = node.windowReference!.window as! DummyBackend.Window
        #expect(window.colorScheme == .dark)
        #expect(ambientColorScheme.value == .dark)
    }

    #if canImport(AppKitBackend)
        @Test("Ensure that a basic view has the expected dimensions under AppKitBackend")
        @MainActor
        func testBasicLayout() async throws {
            let backend = AppKitBackend()
            let window = backend.createWindow(withDefaultSize: SIMD2(200, 200), id: "window")

            // Idea taken from https://github.com/pointfreeco/swift-snapshot-testing/pull/533
            // and implemented in AppKitBackend.
            window.backingScaleFactorOverride = 1
            window.colorSpace = .genericRGB

            let environment = EnvironmentValues(backend: backend)
                .with(\.window, window)

            // Lays a view out through the full graph, the way the assertion
            // below needs each piece measured: by the same path, in the same
            // environment, against the same proposal.
            // 以完整的 view graph 佈局一個 view——下方斷言所需的每一塊，都必須經由相同路徑、
            // 在相同 environment 中、對相同的提議尺寸量測。
            func layout<V: View>(_ view: V) -> ViewLayoutResult {
                let graph = ViewGraph(for: view, backend: backend, environment: environment)
                backend.setChild(ofWindow: window, to: graph.rootNode.widget.into())
                return graph.computeLayout(
                    proposedSize: ProposedViewSize(200, 200),
                    environment: environment
                )
            }

            let result = layout(CounterView())

            // This assertion used to read `result.size == ViewSize(92, 96)`, and
            // those numbers were AppKit's, not SwiftCrossUI's. On macOS 27 an
            // NSButton with bezelStyle .regularSquare measures 82x24 for
            // "Decrease" where 92x96 was written against 72x20, so the test
            // failed while the layout system was doing exactly the right thing
            // with the sizes it was given. Nothing caught it for as long as it
            // was wrong, either: this test sits behind `#if canImport(AppKitBackend)`
            // and so runs on macOS alone.
            //
            // What SwiftCrossUI owns is the composition -- widest child, sum of
            // heights, spacing between, padding around -- so that is what is
            // asserted, over control sizes measured here rather than baked in.
            // Every number below comes from the backend or the environment. The
            // test now says the same thing on any macOS, and still fails for a
            // real defect: a child squeezed below its natural width breaks the
            // max, a dropped gap breaks the sum, padding applied once breaks the
            // last line.
            //
            // 此斷言原本寫作 `result.size == ViewSize(92, 96)`，而那組數字屬於 AppKit，
            // 不屬於 SwiftCrossUI。在 macOS 27 上，bezelStyle 為 .regularSquare 的 NSButton
            // 就「Decrease」量得 82x24，而 92x96 是依 72x20 寫成的；於是測試失敗，佈局系統
            // 卻對它所取得的尺寸做出了完全正確的處理。而且在它出錯的整段期間也無人察覺：此測試
            // 位於 `#if canImport(AppKitBackend)` 之後，僅在 macOS 上執行。
            //
            // SwiftCrossUI 真正負責的是「組合」——最寬的子項、高度總和、其間的 spacing、四周的
            // padding——因此所斷言的正是這些，並以此處實際量得的控制項尺寸為依據，而非寫死。
            // 下方每一個數字都來自 backend 或 environment。此測試如今在任何 macOS 上都陳述同一
            // 件事，且仍會因真正的缺陷而失敗：子項被壓到低於自然寬度會破壞 max、遺漏間隔會破壞
            // 總和、padding 只套一次會破壞最後一行。
            let stack = layout(CounterStack()).size
            let decrease = layout(Button("Decrease") {}).size
            let count = layout(Text("Count: 1")).size
            let increase = layout(Button("Increase") {}).size

            let spacing = Double(environment.layoutSpacing)
            let padding = Double(backend.defaultPaddingAmount)

            #expect(
                stack.width == max(decrease.width, count.width, increase.width),
                "VStack width should be its widest child"
            )

            #expect(
                stack.height
                    == decrease.height + count.height + increase.height + 2 * spacing,
                "VStack height should be its children plus one gap between each pair"
            )

            #expect(
                result.size == ViewSize(stack.width + 2 * padding, stack.height + 2 * padding),
                "padding() should add the default amount on all four edges"
            )

            #expect(
                result.preferences.onOpenURL == nil,
                "onOpenURL not nil"
            )
        }

        /// Snapshots an AppKit view to a TIFF image.
        @MainActor
        static func snapshotView(_ view: NSView) throws -> Data {
            view.wantsLayer = true
            view.layer?.backgroundColor = CGColor.white

            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                throw TestError(message: "Failed to create bitmap backing")
            }

            view.cacheDisplay(in: view.bounds, to: bitmap)

            guard let data = bitmap.tiffRepresentation else {
                throw TestError(message: "Failed to create tiff representation")
            }

            return data
        }
    #endif
}
