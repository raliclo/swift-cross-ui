import DummyBackend
import Foundation
import Testing

@testable @_spi(Backends) import SwiftCrossUI

/// A date picker style written outside the module, which is the entire point of
/// `DatePickerStyle` being a protocol.
///
/// This type existing and compiling *is* the test. `DatePickerStyle` was an
/// enum until 2026-08-27, so this declaration could not be written at all,
/// while `.datePickerStyle(.compact)` compiled either way -- which is why the
/// gap never showed up on a feature checklist. A test that only called the
/// built-in styles would have passed before the change and after it.
///
/// 一個在模組之外撰寫的日期選擇器樣式——這正是 `DatePickerStyle` 之所以要是 protocol 的全部理由。
///
/// 這個型別「存在且編得過」本身就是測試。`DatePickerStyle` 直到 2026-08-27 都還是 enum，因此這段
/// 宣告根本寫不出來；而 `.datePickerStyle(.compact)` 在兩種設計下都編得過——這正是該落差從未出現在
/// 任何功能清單上的原因。一個只呼叫內建樣式的測試，在改動前後都會通過。
private struct CountingDatePickerStyle: DatePickerStyle {
    let label: String

    func makeView(
        selection: Binding<Date>,
        range: ClosedRange<Date>,
        components: DatePickerComponents,
        environment: EnvironmentValues
    ) -> Text {
        Text(label)
    }
}

@Suite("Date picker styles")
@MainActor
struct DatePickerStyleTests {
    @Test("A custom style is supported without asking the backend")
    func customStyleIsSupportedByDefault() {
        let backend = DummyBackend()
        // The default `isSupported` returns true because a custom style draws
        // itself out of ordinary views and needs nothing from the backend.
        // 預設的 `isSupported` 回傳 true，因為自訂樣式是以一般的 view 自行繪製的，不需要 backend
        // 提供任何東西。
        #expect(CountingDatePickerStyle(label: "x").isSupported(backend: backend))
    }

    @Test("A built-in style resolves to the backend vocabulary")
    func builtinStylesResolve() {
        let backend = DummyBackend()
        #expect(
            AutomaticDatePickerStyle()._asBackendDatePickerStyle(backend: backend) == .automatic
        )
        #expect(CompactDatePickerStyle()._asBackendDatePickerStyle(backend: backend) == .compact)
        #expect(
            GraphicalDatePickerStyle()._asBackendDatePickerStyle(backend: backend) == .graphical
        )
    }

    @Test("A backend without the date picker feature supports no built-in style")
    func builtinStylesNeedTheFeature() {
        // Including `.automatic`. There is no date picker to be automatic
        // about, and answering `true` here would report a style as usable on a
        // backend that cannot draw one.
        // `.automatic` 也不例外。根本沒有日期選擇器可以「自動」，而在此回答 `true`，等於向使用者
        // 回報「某個樣式在一個畫不出日期選擇器的 backend 上可用」。
        let backend = DummyBackend()
        #expect(!(backend is any BackendFeatures.DatePickers))
        #expect(!AutomaticDatePickerStyle().isSupported(backend: backend))
    }
}
