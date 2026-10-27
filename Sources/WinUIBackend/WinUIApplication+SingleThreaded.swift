import Foundation
@_spi(Backends) import SwiftCrossUI
import WinAppSDK
import WinSDK
import WinUI
import WinUIInterop

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
                // See WinUIApplication+Redirect.swift. / 見 WinUIApplication+Redirect.swift。
                if redirectToRunningInstance() {
                    return
                }
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
/// unreachable from here. Kept close to upstream on purpose -- the
/// point of ``WinUIApplication/runSingleThreaded()`` is to change the apartment
/// and nothing else, so any difference in when the run loop is serviced would
/// be a second variable in every comparison against the old path.
///
/// 在 UI 執行緒的 Win32 訊息迴圈內抽取 `RunLoop.main`。
///
/// 這是 swift-winui 的 `MainRunLoopTickler`(0.2.1 的 `Sources/WinUI/Application/
/// MainRunLoopTickler.swift`)的副本,原版為 `internal`,此處無法取用。**刻意盡量貼近上游**——
/// ``WinUIApplication/runSingleThreaded()`` 的目的是只改變 apartment、其他什麼都不動,因此 run loop
/// 何時被服務的任何差異,都會在每一次與舊路徑的比較中成為第二個變數。
///
/// **The one deliberate difference.** Upstream re-arms its timer on
/// every window message, which postpones it for as long as messages keep
/// coming, and raises every wait to 50 ms; `DispatchQueue.main` then stalled
/// for the whole of an animation (P66). See `scheduleDelayedWork(after:)` and `watchMainQueue()`.
/// `SCUI_WINUI_MTA=1` still runs upstream's copy, bug included.
///
/// **唯一刻意的差異。** 上游在每一則視窗訊息上重設計時器——只要訊息不斷就一直被往後推——
/// 並把每次等待墊到 50 ms;於是整段動畫期間 `DispatchQueue.main` 都停住(P66)。見
/// `scheduleDelayedWork(after:)` 與 `watchMainQueue()`。`SCUI_WINUI_MTA=1` 仍跑上游的版本，連同這個問題。
final class WinUIRunLoopTickler {
    private var timerID: UINT_PTR = 0
    /// When the armed timer fires, or nil when none is armed.
    /// 已設定的計時器何時觸發;沒有設定時為 nil。
    private var timerDeadline: TimeInterval?
    private var uiQueue: WinAppSDK.DispatcherQueue?
    private var mainQueueWait: HANDLE?

    private var readyToProcessMessages = false
    private var doWorkRecursionGuard = false

    fileprivate static let minIdleDelay: TimeInterval = 0.05
    fileprivate static let maxIdleDelay: TimeInterval = 1
    /// The shortest wait for a real run-loop date. Win32 timers round it up to
    /// USER_TIMER_MINIMUM (10 ms) anyway. / 等待真正 run-loop 日期的最短時間;Win32 計時器反正會進位到 10 ms。
    fileprivate static let shortestDelay: TimeInterval = 0.001
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
        uiQueue = WinAppSDK.DispatcherQueue.getForCurrentThread()
        watchMainQueue()
        scheduleImmediateWork()
    }

    fileprivate func scheduleDelayedWork(after delay: TimeInterval) {
        let cappedDelay: TimeInterval
        if delay >= nextIdleDelay {
            cappedDelay = nextIdleDelay
            nextIdleDelay = min(nextIdleDelay + Self.minIdleDelay, Self.maxIdleDelay)
        } else if delay == 0 {
            cappedDelay = Self.minIdleDelay
        } else {
            cappedDelay = max(delay, Self.shortestDelay)
        }

        // A timer that will fire sooner stays as it is. `SetTimer` with the
        // same ID re-arms it from NOW, and every window message on this thread
        // asks for work, so while messages kept coming -- a frame clock at 131
        // Hz -- the timer was pushed back on each one and fired only once they
        // stopped: P66 sampled `withAnimation` twice in 0.66 s (0, then 200)
        // where AppKit samples 31 times (2026-10-19).
        // 會更早觸發的計時器維持原樣。`SetTimer` 用同一個 ID 會**從現在起**重新計時，而本執行緒的每一則
        // 視窗訊息都會要求工作，因此只要訊息不斷——131 Hz 的 frame clock——計時器就在每一則訊息上被往後推，
        // 直到訊息停止才觸發:P66 在 0.66 秒內只取樣到 `withAnimation` 兩次(0,然後 200),而 AppKit
        // 取樣 31 次(2026-10-19)。
        let deadline = ProcessInfo.processInfo.systemUptime + cappedDelay
        if let armed = timerDeadline, armed <= deadline {
            return
        }
        timerDeadline = deadline
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
        if let mainQueueWait { UnregisterWait(mainQueueWait) }
    }

    /// Waits, once, for libdispatch to say the main queue has work, then
    /// services the run loop on the UI thread and waits again.
    ///
    /// The timers alone could not keep up: a `DispatchQueue.main.asyncAfter`
    /// is libdispatch's timer, not a RunLoop timer, so `limitDate` never
    /// reports it and the tickler only found it on its 50 ms idle poll, which
    /// WM_TIMER stretched to about 120 ms while frames were drawn -- P66 read 5
    /// samples of a 0.5 s animation with both timer fixes in (2026-10-19).
    /// libdispatch sets this event the moment the main queue has work, which is
    /// what Foundation's own RunLoop waits on.
    ///
    /// 等待一次 libdispatch 告知主佇列有工作，然後在 UI 執行緒上服務 run loop，再重新等待。
    ///
    /// 光靠計時器跟不上:`DispatchQueue.main.asyncAfter` 是 libdispatch 的計時器，不是 RunLoop 的計時器，
    /// 所以 `limitDate` 從不回報它,tickler 只能在 50 ms 的閒置輪詢中發現它，而繪製影格期間 WM_TIMER 把那拉長到
    /// 約 120 ms——兩項計時器修正都已加入時,P66 對 0.5 秒的動畫只讀到 5 個樣本(2026-10-19)。主佇列一有工作
    /// libdispatch 就設定這個事件,Foundation 自己的 RunLoop 等的正是它。
    fileprivate func watchMainQueue() {
        if let mainQueueWait {
            UnregisterWait(mainQueueWait)
            self.mainQueueWait = nil
        }
        guard let handle = _dispatch_get_main_queue_handle_4CF() else { return }
        var wait: HANDLE?
        if RegisterWaitForSingleObject(
            &wait, handle, winUIMainQueueSignalled, nil, INFINITE, ULONG(WT_EXECUTEONLYONCE)
        ) {
            mainQueueWait = wait
        }
    }

    /// On a thread-pool thread: hand the work to the UI thread.
    /// 在執行緒池的執行緒上：把工作交給 UI 執行緒。
    fileprivate func mainQueueSignalled() {
        _ = try? uiQueue?.tryEnqueue(.normal) {
            _dispatch_main_queue_callback_4CF(nil)
            WinUIRunLoopTickler.instance.doWork()
            WinUIRunLoopTickler.instance.watchMainQueue()
        }
    }

    fileprivate func doWork() {
        timerDeadline = nil
        guard doWorkRecursionGuard == false else { return }
        doWorkRecursionGuard = true
        defer { doWorkRecursionGuard = false }

        let nextDate = RunLoop.main.limitDate(forMode: .default)
        // nil and distantFuture both mean "try again promptly", which is the
        // idle poll. A real date -- an `asyncAfter`, a Timer -- is kept as it
        // is, never shorter than `shortestDelay`.
        // nil 與 distantFuture 都代表「盡快再試一次」，也就是閒置輪詢。真正的日期——`asyncAfter`、Timer——
        // 照原值排程，不短於 `shortestDelay`。
        if let nextDate, nextDate != .distantFuture {
            scheduleDelayedWork(after: max(nextDate.timeIntervalSinceNow, Self.shortestDelay))
        } else {
            scheduleDelayedWork(after: 0)
        }
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

private let winUIMainQueueSignalled: WAITORTIMERCALLBACK = { _, _ in
    WinUIRunLoopTickler.instance.mainQueueSignalled()
}
