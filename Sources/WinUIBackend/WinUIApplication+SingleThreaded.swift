import Foundation
@_spi(Backends) import SwiftCrossUI
import WinAppSDK
import WinSDK
import WinUI

extension WinUIApplication {
    /// Starts the application on a SINGLE-threaded apartment, which WebView2
    /// needs and `SwiftApplication.main()` does not give.
    ///
    /// **Why this exists instead of `WinUIApplication.main()`.** swift-winui's
    /// `SwiftApplication.main()` hard-codes
    /// `WindowsAppRuntimeInitializer(threadingModel: .multi)`, so the UI thread
    /// is an MTA before any backend code runs -- measured with
    /// `CoGetApartmentType`: `CO_E_NOTINITIALIZED` before `main()`, type 1 in
    /// `onLaunched`. Every XAML control is indifferent to that because XAML
    /// dispatches through its own `DispatcherQueue`. WebView2 is not: its
    /// environment handshake completes back into the caller's apartment, and
    /// under MTA it never completed (P38, 45 s, `EBWebView/` never gained a
    /// profile). With `.single` it completes, and P38 renders example.com.
    /// The C++/WinRT WinUI 3 template also starts single-threaded, so this is
    /// the conventional choice, not a special case.
    ///
    /// **This duplicates two things from swift-winui on purpose, and they should
    /// be deleted if upstream grows a threading-model parameter.** The body of
    /// `SwiftApplication.main()` is four calls, all public. The run-loop tickler
    /// is not public -- it is `internal` to the `WinUI` module -- so a copy lives
    /// below as ``WinUIRunLoopTickler``. Without it `RunLoop.main` is never
    /// drained, which means `DispatchQueue.main` and main-actor tasks silently
    /// never run.
    ///
    /// `SCUI_WINUI_MTA=1` takes the old path. It is the control group -- the
    /// same P38 build under it stays type 1 and never finishes -- and the way
    /// back if single-threaded ever breaks something this change did not.
    ///
    /// 以**單執行緒** apartment 啟動應用程式——WebView2 需要它,而 `SwiftApplication.main()` 不給。
    ///
    /// **為何存在,而不是呼叫 `WinUIApplication.main()`。** swift-winui 的 `SwiftApplication.main()`
    /// 寫死了 `WindowsAppRuntimeInitializer(threadingModel: .multi)`,所以 UI 執行緒在任何 backend
    /// 程式碼執行前就是 MTA——以 `CoGetApartmentType` 量測:`main()` 之前為 `CO_E_NOTINITIALIZED`,
    /// `onLaunched` 中為 type 1。所有 XAML 控制項對此無感,因為 XAML 透過自己的 `DispatcherQueue`
    /// 派送。**WebView2 不是**:它的環境交握是回到呼叫端的 apartment 完成的,而在 MTA 下從未完成
    /// (P38,45 秒,`EBWebView/` 從未建立 profile)。改為 `.single` 後交握完成,P38 顯示 example.com。
    /// C++/WinRT 的 WinUI 3 範本也是以單執行緒啟動,所以這是慣例,不是特例。
    ///
    /// **這裡刻意複製了 swift-winui 的兩樣東西,若上游加入 threading model 參數就應刪除。**
    /// `SwiftApplication.main()` 的本體是四個呼叫,全部 public。run-loop tickler 不是 public——它是
    /// `WinUI` 模組的 `internal`——所以下方放了一份 ``WinUIRunLoopTickler``。少了它 `RunLoop.main`
    /// 永遠不會被抽取,`DispatchQueue.main` 與 main-actor 的工作會**靜默地**永不執行。
    ///
    /// `SCUI_WINUI_MTA=1` 走舊路徑。它是對照組——同一個 P38 建置在它之下維持 type 1、永不完成——
    /// 也是日後若單執行緒弄壞了本次沒發現的東西時的退路。
    static func runSingleThreaded() {
        if ProcessInfo.processInfo.environment["SCUI_WINUI_MTA"] != nil {
            logger.info("WinUIApplication: SCUI_WINUI_MTA set, starting multi-threaded")
            WinUIApplication.main()
            return
        }

        do {
            try withExtendedLifetime(
                WindowsAppRuntimeInitializer(threadingModel: .single)
            ) {
                var application: WinUIApplication!
                Application.start { _ in
                    WinUIRunLoopTickler.setup()
                    application = WinUIApplication()
                }
                application.onShutdown()
                WinUIRunLoopTickler.shutdown()
            }
        } catch {
            // `print` as well as `fatalError`, for the reason upstream gives:
            // the fatalError message does not always reach the console.
            // 除了 `fatalError` 之外也 `print`,理由同上游:fatalError 的訊息不一定會到達主控台。
            print("Failed to initialize WindowsAppRuntimeInitializer: \(error)")
            fatalError("Failed to initialize WindowsAppRuntimeInitializer: \(error)")
        }
    }
}

/// Drains `RunLoop.main` from inside the Win32 message loop on the UI thread.
///
/// A copy of swift-winui's `MainRunLoopTickler` (`Sources/WinUI/Application/
/// MainRunLoopTickler.swift` at 0.2.1), which is `internal` and therefore
/// unreachable from here. Kept behaviourally identical on purpose -- the
/// point of ``WinUIApplication/runSingleThreaded()`` is to change the apartment
/// and nothing else, so any difference in when the run loop is serviced would
/// be a second variable in every comparison against the old path.
///
/// 在 UI 執行緒的 Win32 訊息迴圈內抽取 `RunLoop.main`。
///
/// 這是 swift-winui 的 `MainRunLoopTickler`(0.2.1 的 `Sources/WinUI/Application/
/// MainRunLoopTickler.swift`)的副本,原版為 `internal`,此處無法取用。**刻意保持行為完全一致**——
/// ``WinUIApplication/runSingleThreaded()`` 的目的是只改變 apartment、其他什麼都不動,因此 run loop
/// 何時被服務的任何差異,都會在每一次與舊路徑的比較中成為第二個變數。
final class WinUIRunLoopTickler {
    private var timerID: UINT_PTR = 0

    private var readyToProcessMessages = false
    private var doWorkRecursionGuard = false

    fileprivate static let minIdleDelay: TimeInterval = 0.05
    fileprivate static let maxIdleDelay: TimeInterval = 1
    private static let doWorkMessage = UINT(WM_USER + 0xbc0)

    /// The delay between the next run-loop service and the one after it. It
    /// grows while idle, up to `maxIdleDelay`, and resets on input.
    /// 下一次與再下一次 run-loop 服務之間的延遲。閒置時遞增至 `maxIdleDelay`,有輸入時重設。
    private var nextIdleDelay: TimeInterval = WinUIRunLoopTickler.minIdleDelay
    nonisolated(unsafe) fileprivate static let instance: WinUIRunLoopTickler = .init()

    static func setup() {
        instance.start()
    }

    static func shutdown() {
        instance.shutdown()
    }

    private var hook: HHOOK?
    private func start() {
        // Every window message processed on this thread is a chance to service
        // the run loop.
        // 本執行緒處理的每一則視窗訊息,都是服務 run loop 的機會。
        hook = SetWindowsHookExW(
            WH_CALLWNDPROCRET, winUIRunLoopTicklerWindowHook, nil, GetCurrentThreadId()
        )
        scheduleImmediateWork()
    }

    fileprivate func scheduleDelayedWork(after delay: TimeInterval) {
        let cappedDelay: TimeInterval
        if delay >= nextIdleDelay {
            cappedDelay = nextIdleDelay
            nextIdleDelay = min(nextIdleDelay + Self.minIdleDelay, Self.maxIdleDelay)
        } else {
            cappedDelay = max(delay, Self.minIdleDelay)
        }
        let delayMilliseconds = UInt32(cappedDelay * 1000)
        timerID = SetTimer(nil, timerID, delayMilliseconds, winUIRunLoopTicklerTimerProc)
    }

    fileprivate func scheduleImmediateWork() {
        WinUIRunLoopTickler.instance.nextIdleDelay = WinUIRunLoopTickler.minIdleDelay

        if readyToProcessMessages {
            guard PostMessageW(nil, WinUIRunLoopTickler.doWorkMessage, 0, 0) else {
                print("Failed to post message to message window. Win32 Error Code: \(GetLastError())")
                return
            }
        } else {
            scheduleDelayedWork(after: 0)
        }
    }

    fileprivate func shutdown() {
        UnhookWindowsHookEx(hook)
        KillTimer(nil, timerID)
    }

    fileprivate func doWork() {
        guard doWorkRecursionGuard == false else { return }
        doWorkRecursionGuard = true
        defer { doWorkRecursionGuard = false }

        let nextDate = RunLoop.main.limitDate(forMode: .default)
        // nil and distantFuture both mean "try again promptly".
        // nil 與 distantFuture 都代表「盡快再試一次」。
        let nextDelay = nextDate == .distantFuture ? 0 : nextDate?.timeIntervalSinceNow ?? 0
        scheduleDelayedWork(after: nextDelay)
    }
}

private let winUIRunLoopTicklerWindowHook: HOOKPROC = {
    (nCode: Int32, wParam: WPARAM, lParam: LPARAM) in
    if nCode >= 0 {
        let ptr = UnsafeRawPointer(bitPattern: Int(lParam))?
            .assumingMemoryBound(to: CWPRETSTRUCT.self)
        if let msgInfo = ptr?.pointee {
            // Input gets immediate work, scheduled rather than run here so the
            // run loop is never serviced from inside this hook's call stack.
            // 輸入事件排程立即工作——是「排程」而非在此執行,以免在此 hook 的呼叫堆疊內服務 run loop。
            if (msgInfo.message >= WM_KEYFIRST && msgInfo.message < WM_KEYLAST)
                || (msgInfo.message >= WM_MOUSEFIRST && msgInfo.message < WM_MOUSELAST)
            {
                WinUIRunLoopTickler.instance.scheduleImmediateWork()
            } else if msgInfo.message != WM_GETICON {
                // Windows sends periodic WM_GETICON without user input.
                // Windows 會在沒有使用者輸入時週期性送出 WM_GETICON。
                WinUIRunLoopTickler.instance.scheduleDelayedWork(after: 0)
            }
        }
    }
    return CallNextHookEx(nil, nCode, wParam, lParam)
}

private let winUIRunLoopTicklerTimerProc: TIMERPROC = { (_: HWND?, _: UINT, _: UINT_PTR, _: DWORD) in
    WinUIRunLoopTickler.instance.doWork()
}
