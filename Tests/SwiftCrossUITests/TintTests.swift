import DummyBackend
import Testing

@testable @_spi(Backends) import SwiftCrossUI

/// tint(_:) reaches each control's update through the environment, an inner
/// tint(nil) gives the platform's accent back, and a borderless button's label
/// takes it unless the app named a colour.
/// tint(_:) 經由 environment 抵達每個控制項的 update,內層的 tint(nil) 還原平台的強調色，無框按鈕的標籤除非 app
/// 指定了顏色，否則用它。
@MainActor
struct TintTests {
    func widgets<V: View>(in view: V) -> [DummyBackend.Widget] {
        let node = ViewGraphHelpers.committedNode(for: view)
        func walk(_ widget: DummyBackend.Widget) -> [DummyBackend.Widget] {
            var found = [widget]
            if let button = widget as? DummyBackend.Button, let label = button.label {
                found += walk(label)
            }
            return found + widget.getChildren().flatMap(walk)
        }
        return walk(node.widget)
    }

    func controls<V: View>(in view: V) -> (
        switches: [DummyBackend.ToggleSwitch],
        checkboxes: [DummyBackend.Checkbox],
        sliders: [DummyBackend.Slider]
    ) {
        let all = widgets(in: view)
        return (
            all.compactMap { $0 as? DummyBackend.ToggleSwitch },
            all.compactMap { $0 as? DummyBackend.Checkbox },
            all.compactMap { $0 as? DummyBackend.Slider }
        )
    }

    var controlStack: some View {
        VStack {
            Toggle("Switch", isOn: .constant(true)).toggleStyle(.switch)
            Toggle("Check", isOn: .constant(true)).toggleStyle(.checkbox)
            Slider(value: .constant(0.5), in: 0...1)
        }
    }

    @Test("Untinted controls get nil, the platform's accent")
    func untinted() {
        let found = controls(in: controlStack)
        #expect(found.switches.count == 1)
        #expect(found.checkboxes.count == 1)
        #expect(found.sliders.count == 1)
        #expect(found.switches.allSatisfy { $0.tint == nil })
        #expect(found.checkboxes.allSatisfy { $0.tint == nil })
        #expect(found.sliders.allSatisfy { $0.tint == nil })
    }

    @Test("tint(.green) on a stack reaches every control in it")
    func inherited() {
        let found = controls(in: controlStack.tint(.green))
        #expect(found.switches.map(\.tint) == [.green])
        #expect(found.checkboxes.map(\.tint) == [.green])
        #expect(found.sliders.map(\.tint) == [.green])
    }

    @Test("An inner tint wins, and an inner tint(nil) restores the default")
    func innerWins() {
        let view = VStack {
            Toggle("Red", isOn: .constant(true)).toggleStyle(.switch).tint(.red)
            Toggle("Default", isOn: .constant(true)).toggleStyle(.switch).tint(nil)
            Toggle("Outer", isOn: .constant(true)).toggleStyle(.switch)
        }.tint(.green)
        #expect(controls(in: view).switches.map(\.tint) == [.red, nil, .green])
    }

    @Test("A borderless button's label takes the tint; a foregroundColor still wins")
    func borderlessLabel() {
        let environment = ViewGraphHelpers.environment
        func labelColors<V: View>(_ view: V) -> [Color.Resolved] {
            widgets(in: view).compactMap { ($0 as? DummyBackend.TextView)?.color }
        }
        let tinted = labelColors(Button("Go") {}.buttonStyle(.borderless).tint(.green))
        #expect(tinted == [Color.green.resolve(in: environment)])

        let named = labelColors(
            Button("Go") {}.buttonStyle(.borderless).foregroundColor(.red).tint(.green)
        )
        #expect(named == [Color.red.resolve(in: environment)])

        let disabled = labelColors(
            Button("Go") {}.buttonStyle(.borderless).disabled(true).tint(.green)
        )
        #expect(disabled.count == 1)
        #expect(disabled.first != Color.green.resolve(in: environment))
    }

    @Test("tint changes no size")
    func sizeUnchanged() {
        let plain = ViewGraphHelpers.computeLayout(of: controlStack).size
        let tinted = ViewGraphHelpers.computeLayout(of: controlStack.tint(.green)).size
        #expect(plain == tinted)
    }
}
