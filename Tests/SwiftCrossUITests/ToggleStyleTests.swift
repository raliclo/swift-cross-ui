import DummyBackend
import Testing

@testable @_spi(Backends) import SwiftCrossUI

/// A toggle style written outside the module.
///
/// As with `CountingDatePickerStyle`, this declaration compiling is the test.
/// `ToggleStyle` was a struct with static members until 2026-08-27 -- closer to
/// SwiftUI than the date picker's enum, since it already separated the backend
/// vocabulary into a nested `@_spi(Backends) enum Style` -- but a struct cannot
/// be conformed to, so this could not be written.
///
/// 與 `CountingDatePickerStyle` 相同，這段宣告編得過本身就是測試。`ToggleStyle` 直到 2026-08-27
/// 都還是一個帶有 static 成員的 struct——它比日期選擇器的 enum 更接近 SwiftUI，因為它已經把 backend
/// 詞彙分離到巢狀的 `@_spi(Backends) enum Style` 之中——但 struct 無法被 conform，因此這是寫不出來的。
private struct ShoutingToggleStyle: ToggleStyle {
    func makeView(
        label: String,
        isOn: Binding<Bool>,
        environment: EnvironmentValues
    ) -> Text {
        Text(label.uppercased())
    }
}

@Suite("Toggle styles")
@MainActor
struct ToggleStyleTests {
    @Test("A custom style is supported without asking the backend")
    func customStyleIsSupportedByDefault() {
        #expect(ShoutingToggleStyle().isSupported(backend: DummyBackend()))
    }

    @Test("A built-in style resolves to the backend vocabulary")
    func builtinStylesResolve() {
        let backend = DummyBackend()
        #expect(SwitchToggleStyle()._asBackendToggleStyle(backend: backend) == .switch)
        #expect(ButtonToggleStyle()._asBackendToggleStyle(backend: backend) == .button)
        #expect(CheckboxToggleStyle()._asBackendToggleStyle(backend: backend) == .checkbox)
    }

    @Test("Each built-in style is supported exactly when its own feature is")
    func builtinSupportFollowsTheFeature() {
        // Three separate opt-in features, so support is per style rather than
        // one answer for toggles as a whole. Asserted against what DummyBackend
        // actually conforms to rather than against a hard-coded expectation, so
        // this keeps holding if DummyBackend gains or loses a feature.
        //
        // 三個各自獨立的選用功能，因此「是否支援」是逐一樣式回答，而非對 toggle 整體給一個答案。
        // 此處比對的是 DummyBackend 實際 conform 了什麼，而非寫死的預期值，如此一來即使
        // DummyBackend 日後增減功能，這項斷言依然成立。
        let backend = DummyBackend()
        #expect(
            SwitchToggleStyle().isSupported(backend: backend)
                == (backend is any BackendFeatures.Switches)
        )
        #expect(
            ButtonToggleStyle().isSupported(backend: backend)
                == (backend is any BackendFeatures.ToggleButtons)
        )
        #expect(
            CheckboxToggleStyle().isSupported(backend: backend)
                == (backend is any BackendFeatures.Checkboxes)
        )
    }
}
