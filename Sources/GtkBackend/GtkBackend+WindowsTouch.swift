#if os(Windows)
    import Foundation
    import WinSDK

    /// Whether the pointer's motion now is a finger, for GtkBackend on Windows.
    ///
    /// Windows hands GDK a touch twice: as GDK touch events, which
    /// `GtkTouchHold` reads (long press, updates, end), and as emulated mouse
    /// input, which the motion controller took for a mouse hover. Measured
    /// 2026-10-23 on P88 with `testapp/touch_gesture.zsh`: a quick touch drag
    /// reported 23 hovers through the emulated mouse alone, and a hold ended
    /// by GDK_TOUCH_END was made active again by one more emulated move in the
    /// same millisecond. A thread message hook reads the touch's own
    /// `WM_POINTERDOWN` / `WM_POINTERUP`, and the motion controller ignores
    /// motion while a finger is down and for `afterLift` after it lifts. The
    /// mouse cursor that Windows puts back where it was after a touch came
    /// 1.9 s after the lift, and is a real mouse hover.
    ///
    /// The first version of this file stated that GDK never sees a touch on
    /// Windows and drove the whole touch hover from the hook. It was wrong: a
    /// trace showed 30 GDK_TOUCH_UPDATE, one GDK_TOUCH_END and GTK's long press,
    /// and the two paths reported the same finger twice (90 reports for a
    /// 0.8 s hold). The earlier failures were the emulated mouse, not a
    /// missing touch.
    ///
    /// GtkBackend 在 Windows 上：此刻 pointer 的移動是否來自手指。Windows 把一次觸控交給 GDK 兩次：一次是 GDK
    /// 觸控事件(`GtkTouchHold` 讀取：長按、更新、結束),一次是模擬的滑鼠輸入，被 motion 控制器當成滑鼠 hover。
    /// 2026-10-23 以 `testapp/touch_gesture.zsh` 在 P88 量到：快速觸控拖曳單靠模擬滑鼠就回報了 23 次 hover;
    /// 由 GDK_TOUCH_END 結束的按住，又在同一毫秒被一次模擬移動設回 active。執行緒訊息 hook 讀取觸控自己的
    /// `WM_POINTERDOWN`/`WM_POINTERUP`,motion 控制器在手指按下期間與抬起後 `afterLift` 內忽略移動。觸控結束後
    /// Windows 把滑鼠游標放回原處，那次在抬起 1.9 秒後到來，是真正的滑鼠 hover。
    /// 本檔第一版寫著「Windows 上 GDK 從未見過觸控」，並完全由 hook 驅動觸控 hover。那是錯的：追蹤顯示有 30 個
    /// GDK_TOUCH_UPDATE、一個 GDK_TOUCH_END 與 GTK 的長按，兩條路徑把同一根手指回報了兩次(按住 0.8 秒回報 90 次)。
    /// 先前的失敗來自模擬的滑鼠，而不是缺少觸控。
    @MainActor
    enum GtkWindowsTouch {
        /// The touch pointers down now. / 此刻按下的觸控 pointer。
        private static var down: Set<UInt32> = []
        private static var liftTime = -Double.infinity
        private static var hook: HHOOK?

        /// How long after a lift the emulated mouse still belongs to the finger.
        /// 抬起後多久之內，模擬的滑鼠仍屬於手指。
        static let afterLift = 0.5

        /// Whether a motion now belongs to a finger. / 此刻的移動是否屬於手指。
        static var active: Bool {
            !down.isEmpty || ProcessInfo.processInfo.systemUptime - liftTime < afterLift
        }

        /// Installs the hook on this thread, once. / 在本執行緒安裝 hook,只裝一次。
        static func install() {
            guard hook == nil else { return }
            hook = SetWindowsHookExW(WH_GETMESSAGE, gtkWindowsTouchHook, nil, GetCurrentThreadId())
        }

        fileprivate static func received(_ message: MSG) {
            // GET_POINTERID_WPARAM is the low word. / GET_POINTERID_WPARAM 是低位字組。
            let pointer = UInt32(message.wParam & 0xFFFF)
            switch message.message {
                case UINT(WM_POINTERDOWN):
                    var type = POINTER_INPUT_TYPE(0)
                    if GetPointerType(pointer, &type), type == POINTER_INPUT_TYPE(PT_TOUCH.rawValue) {
                        down.insert(pointer)
                    }
                case UINT(WM_POINTERUP):
                    if down.remove(pointer) != nil, down.isEmpty {
                        liftTime = ProcessInfo.processInfo.systemUptime
                    }
                default:
                    break
            }
        }
    }

    private let gtkWindowsTouchHook: HOOKPROC = { nCode, wParam, lParam in
        // Only messages taken off the queue: a PM_NOREMOVE peek sees the same one again.
        // 只看真正從佇列取出的訊息:PM_NOREMOVE 的窺看會再看到同一則。
        if nCode == HC_ACTION, wParam == WPARAM(PM_REMOVE),
            let message = UnsafeRawPointer(bitPattern: Int(lParam))?
                .assumingMemoryBound(to: MSG.self).pointee
        {
            MainActor.assumeIsolated {
                GtkWindowsTouch.received(message)
            }
        }
        return CallNextHookEx(nil, nCode, wParam, lParam)
    }
#endif
