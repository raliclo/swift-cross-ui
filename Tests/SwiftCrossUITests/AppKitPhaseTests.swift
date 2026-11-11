#if os(macOS)
    @testable import AppKitBackend
    import SwiftCrossUI
    import Testing

    /// AppKitBackend's app and scene phase rule (AppKitBackend.phase(active:beenActive:)): active at
    /// launch, as SwiftUI reports it (measured on macOS 2026-11-10), then the real state once the app
    /// or window has been active. The transitions are tested here because an app launched from this
    /// session is never made active by macOS, so a probe could only see the launch half.
    /// AppKitBackend 的 app 與 scene phase 規則：啟動時為 active(與 SwiftUI 相同，2026-11-10 在 macOS 實測),
    /// App 或視窗 active 過之後依實際狀態。轉換在這裡測，因為從本 session 啟動的 App 從未被 macOS 設為作用中，探測只看得到啟動那一半。
    @Suite("AppKit phase rule")
    struct AppKitPhaseTests {
        @Test("Active until the first activation, then the real state")
        func transitions() {
            // (isActive at each check, the phase expected) / (每次檢查時的 isActive,預期的 phase)
            let steps: [(Bool, AppPhase)] = [
                (false, .active),  // launch, not yet active / 啟動，尚未作用中
                (false, .active),
                (true, .active),  // activated / 成為作用中
                (false, .inactive),  // resigned: now it follows the state / 失去作用：此後依實際狀態
                (true, .active),
                (false, .inactive),
            ]
            var been = false
            for (index, (active, expected)) in steps.enumerated() {
                let (phase, nowBeen) = AppKitBackend.phase(active: active, beenActive: been)
                #expect(phase == expected, "step \(index): isActive=\(active)")
                been = nowBeen
            }
            #expect(been)
        }
    }
#endif
