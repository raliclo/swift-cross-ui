import AppKit
import SwiftCrossUI

extension AppKitBackend: BackendFeatures.FrameClocks {
    /// A display link on macOS 14 and up, and a timer below it.
    ///
    /// **`NSView.displayLink(target:selector:)` is macOS 14+, and this package
    /// builds against macOS 12.** The `if #available` is therefore not
    /// defensive: it is the difference between a clock locked to the display's
    /// refresh -- 120 Hz on a ProMotion screen, and correct when that changes
    /// because the window moved to another monitor -- and one that assumes 60.
    ///
    /// The timer below it is honestly worse and says so: it fires at a fixed
    /// 60 Hz, so on a 120 Hz display every second frame repeats. That is a
    /// visible difference rather than a wrong one, and it only affects macOS 12
    /// and 13.
    ///
    /// 在 macOS 14 以上使用 display link，在其之下使用計時器。
    ///
    /// **`NSView.displayLink(target:selector:)` 是 macOS 14+，而本套件是對著 macOS 12 建置的。**
    /// 因此那個 `if #available` 不是防禦性寫法:它是「一個鎖在顯示器更新率上的時鐘」(ProMotion 螢幕上
    /// 是 120 Hz，而且在視窗被移到另一台螢幕而更新率改變時仍然正確)與「一個假設 60 的時鐘」之間的差別。
    ///
    /// 其下那個計時器誠實地說明自己比較差:它以固定 60 Hz 觸發，因此在 120 Hz 顯示器上每隔一幀就重複
    /// 一次。那是一個**看得出來**的差別，而不是一個錯誤的結果，而且它只影響 macOS 12 與 13。
    public func startFrameClock(handler: @escaping @MainActor (Double) -> Void) {
        stopFrameClock()
        frameClockHandler = handler

        if #available(macOS 14, *), let view = NSApp.keyWindow?.contentView {
            let link = view.displayLink(
                target: FrameClockTarget.shared,
                selector: #selector(FrameClockTarget.tick(_:))
            )
            link.add(to: .main, forMode: .common)
            frameClockLink = link
        } else {
            let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { _ in
                MainActor.assumeIsolated {
                    AppKitBackend.deliverFrame(
                        at: ProcessInfo.processInfo.systemUptime
                    )
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            frameClockTimer = timer
        }
    }

    public func stopFrameClock() {
        if #available(macOS 14, *), let link = frameClockLink as? CADisplayLink {
            link.invalidate()
        }
        frameClockLink = nil
        frameClockTimer?.invalidate()
        frameClockTimer = nil
        frameClockHandler = nil
    }

    /// Delivered through a type property because the display link's target has
    /// to be an `NSObject` and there is exactly one clock.
    /// 透過型別屬性遞送，因為 display link 的 target 必須是一個 `NSObject`，而時鐘恰好只有一個。
    static func deliverFrame(at timestamp: Double) {
        AppKitBackend.currentFrameClockHandler?(timestamp)
    }
}

/// The `NSObject` a display link needs as its target.
///
/// `@MainActor` on the class rather than `nonisolated(unsafe)` on the property:
/// a display link added to the main run loop only ever fires on the main
/// thread, so the isolation is a statement of the truth rather than a promise
/// being made.
///
/// display link 所需要的那個 `NSObject` target。
///
/// 在**類別**上標 `@MainActor`，而不是在屬性上標 `nonisolated(unsafe)`:一個被加進主 run loop 的
/// display link 只會在主執行緒上觸發，因此這個 isolation 是在陳述事實，而不是在許下一個承諾。
@MainActor
final class FrameClockTarget: NSObject {
    static let shared = FrameClockTarget()

    /// Typed as `Any` so this file compiles against macOS 12, where
    /// `CADisplayLink` does not exist as an AppKit type at all. The cast back is
    /// guarded by the same `#available` that created the link.
    /// 型別寫成 `Any`，好讓本檔能對著 macOS 12 編譯——在該版本上 `CADisplayLink` 作為 AppKit 型別
    /// 根本不存在。轉型回來的那一步，由「當初建立這個 link 的那個 `#available`」把關。
    @objc func tick(_ sender: Any) {
        let timestamp: Double
        if #available(macOS 14, *), let link = sender as? CADisplayLink {
            timestamp = link.timestamp
        } else {
            timestamp = ProcessInfo.processInfo.systemUptime
        }
        AppKitBackend.deliverFrame(at: timestamp)
    }
}
