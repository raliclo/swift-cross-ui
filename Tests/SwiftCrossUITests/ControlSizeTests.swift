import DummyBackend
import Testing

@testable @_spi(Backends) import SwiftCrossUI

/// controlSize(_:) resizes controls by one factor and leaves other views alone.
/// controlSize(_:) 以同一個倍率改變控制項的尺寸，其他 view 不受影響。
@MainActor
struct ControlSizeTests {
    func size<V: View>(of view: V) -> ViewSize {
        ViewGraphHelpers.computeLayout(of: view).size
    }

    @Test("The cases are ordered by their scale, with regular at 1")
    func ordering() {
        #expect(ControlSize.allCases == [.mini, .small, .regular, .large, .extraLarge])
        #expect(ControlSize.allCases.sorted() == ControlSize.allCases)
        #expect(ControlSize.regular.scale == 1)
        #expect(EnvironmentValues(backend: DummyBackend()).controlSize == .regular)
    }

    @Test("A button's label grows with the control size")
    func button() {
        let small = size(of: Button("Button") {}.controlSize(.small))
        let regular = size(of: Button("Button") {})
        let large = size(of: Button("Button") {}.controlSize(.large))
        #expect(small.width < regular.width && small.height < regular.height)
        #expect(regular.width < large.width && regular.height < large.height)
    }

    @Test("A native control is laid out at the scale and its container drawn at it")
    func switchScaled() throws {
        let regular = size(of: Toggle("", isOn: .constant(true)).toggleStyle(.switch).labelsHidden())
        let large = size(
            of: Toggle("", isOn: .constant(true)).toggleStyle(.switch).labelsHidden()
                .controlSize(.large)
        )
        #expect(regular.width > 0 && regular.height > 0)
        #expect(abs(large.width - regular.width * ControlSize.large.scale) <= 1)
        #expect(abs(large.height - regular.height * ControlSize.large.scale) <= 1)

        let node = ViewGraphHelpers.committedNode(
            for: Slider(value: .constant(0.5), in: 0...1).controlSize(.small),
            proposedSize: ProposedViewSize(170, nil)
        )
        let container = try #require(
            Self.first(DummyBackend.GeometricEffectContainer.self, in: node.widget)
        )
        #expect(container.transform.linearTransform == SIMD4(0.85, 0, 0, 0.85))
        // The slider still fills the width it was given. / slider 仍然填滿它被給定的寬度。
        #expect(node.currentLayout?.size.width == 170)
    }

    @Test("A regular control gets no container")
    func regularUnwrapped() {
        let node = ViewGraphHelpers.committedNode(
            for: Slider(value: .constant(0.5), in: 0...1),
            proposedSize: ProposedViewSize(170, nil)
        )
        #expect(Self.first(DummyBackend.GeometricEffectContainer.self, in: node.widget) == nil)
    }

    @Test("Text is not a control")
    func textUnchanged() {
        #expect(size(of: Text("Text").controlSize(.large)) == size(of: Text("Text")))
    }

    static func first<W: DummyBackend.Widget>(_ type: W.Type, in widget: DummyBackend.Widget) -> W? {
        if let match = widget as? W { return match }
        for child in widget.getChildren() {
            if let match = first(type, in: child) { return match }
        }
        return nil
    }
}
