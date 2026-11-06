#if os(Windows)
    import WinSDK

    /// Runs the app on an 8 MB stack on Windows, the size the main thread has on macOS.
    ///
    /// The Windows linker reserves 1 MB for the main thread, and layout recurses once
    /// per view level. SoftPCB-UI's deepest tab overflowed that 1 MB after ~615 layout
    /// frames (2026-11-07; GtkBackend gave the backtrace, WinUIBackend died the same way
    /// with c00000fd), and the GTK build ran once relinked with `-Xlinker -STACK:8388608`. The reserve is fixed
    /// when the process starts, so instead of asking every app to pass that flag, the
    /// app runs on a fiber with a larger stack. A fiber runs on the same thread:
    /// `Thread.isMainThread`, `MainActor` and the main dispatch queue are unchanged
    /// (checked with a standalone probe on Swift 6.4.2: same thread id, the main queue
    /// and a `@MainActor` task both ran on the fiber, and a 4.8 MB recursion fit).
    /// An executable already linked with 8 MB or more skips the fiber.
    ///
    /// 在 Windows 上以 8 MB 的堆疊執行 app，與 macOS 主執行緒的大小相同。
    ///
    /// Windows 連結器為主執行緒保留 1 MB，而 layout 每一層 view 遞迴一次。SoftPCB-UI 最深的
    /// 分頁在約 615 個 layout frame 後用完那 1 MB(2026-11-07；GtkBackend 給出 backtrace，
    /// WinUIBackend 以 c00000fd 同樣終止)，GTK 版以 `-Xlinker -STACK:8388608` 重新連結後即正常。保留大小在行程啟動時就已固定，
    /// 因此不要求每個 app 都加那個旗標，而是讓 app 在一個堆疊較大的 fiber 上執行。fiber 跑在
    /// 同一條執行緒上：`Thread.isMainThread`、`MainActor` 與 main dispatch queue 都不變
    /// (Swift 6.4.2 上以獨立探測程式確認：執行緒 id 相同，main queue 與 `@MainActor` task
    /// 都在 fiber 上執行，4.8 MB 的遞迴放得下)。已以 8 MB 以上連結的執行檔會略過 fiber。
    @MainActor
    enum WindowsMainStack {
        /// 8 MB. / 8 MB。
        static let size = 8 << 20

        private final class Context {
            let body: @MainActor () -> Void
            let mainFiber: LPVOID
            init(body: @escaping @MainActor () -> Void, mainFiber: LPVOID) {
                self.body = body
                self.mainFiber = mainFiber
            }
        }

        /// Runs `body` on a stack of at least ``size`` bytes, then returns on the
        /// original stack. Falls back to running it directly if a fiber cannot be made.
        /// 在至少 ``size`` bytes 的堆疊上執行 `body`，之後回到原本的堆疊。無法建立 fiber
        /// 時直接執行它。
        static func run(_ body: @MainActor () -> Void) {
            var low: ULONG_PTR = 0
            var high: ULONG_PTR = 0
            GetCurrentThreadStackLimits(&low, &high)
            guard Int(high - low) < size, let mainFiber = ConvertThreadToFiber(nil) else {
                body()
                return
            }
            withoutActuallyEscaping(body) { body in
                let context = Unmanaged.passRetained(Context(body: body, mainFiber: mainFiber))
                let fiber = CreateFiberEx(
                    0, SIZE_T(size), DWORD(FIBER_FLAG_FLOAT_SWITCH),
                    { parameter in
                        // A fiber routine must not return: that would end the thread. The
                        // context is released before switching back, because this frame is
                        // never unwound and `withoutActuallyEscaping` traps if `body` is
                        // still referenced when it ends.
                        // fiber 的進入函式不可返回：返回會結束整條執行緒。切回之前先釋放
                        // context，因為這個 frame 永遠不會被展開，而 `body` 在
                        // `withoutActuallyEscaping` 結束時若仍被引用，它會中止程式。
                        let mainFiber: LPVOID
                        do {
                            let context = Unmanaged<Context>.fromOpaque(parameter!)
                                .takeRetainedValue()
                            mainFiber = context.mainFiber
                            MainActor.assumeIsolated { context.body() }
                        }
                        SwitchToFiber(mainFiber)
                    },
                    context.toOpaque()
                )
                if let fiber {
                    SwitchToFiber(fiber)
                    DeleteFiber(fiber)
                    ConvertFiberToThread()
                } else {
                    context.release()
                    ConvertFiberToThread()
                    body()
                }
            }
        }
    }
#endif
