import DummyBackend
import Testing

@testable @_spi(Backends) import SwiftCrossUI

/// labelsHidden() leaves each control without its separate label, and nothing else
/// changes. / labelsHidden() 讓每個控制項不顯示另外的標籤，其餘不變。
@MainActor
struct LabelsHiddenTests {
    func texts<V: View>(in view: V) -> [String] {
        let node = ViewGraphHelpers.committedNode(for: view)
        func walk(_ widget: DummyBackend.Widget) -> [String] {
            var found: [String] = []
            if let text = widget as? DummyBackend.TextView {
                found.append(text.content)
            }
            if let button = widget as? DummyBackend.Button, let label = button.label {
                found += walk(label)
            }
            return found + widget.getChildren().flatMap(walk)
        }
        return walk(node.widget)
    }

    @Test("Toggle, Stepper and LabeledContent drop their labels")
    func labelsAreHidden() {
        let toggle = Toggle("Volume label", isOn: .constant(true)).toggleStyle(.switch)
        let stepper = Stepper("Count label", value: .constant(1), in: 0...5)
        let labeled = LabeledContent("Name label", value: "Taylor")

        #expect(texts(in: toggle).contains("Volume label"))
        #expect(!texts(in: toggle.labelsHidden()).contains("Volume label"))

        #expect(texts(in: stepper).contains("Count label"))
        #expect(!texts(in: stepper.labelsHidden()).contains("Count label"))

        #expect(texts(in: labeled).contains("Name label"))
        let hidden = texts(in: labeled.labelsHidden())
        #expect(!hidden.contains("Name label"))
        #expect(hidden.contains("Taylor"))
    }

    @Test("labelsHidden(false) shows them again")
    func labelsShownAgain() {
        let stepper = Stepper("Count label", value: .constant(1), in: 0...5)
        #expect(texts(in: stepper.labelsHidden(false)).contains("Count label"))
    }
}
