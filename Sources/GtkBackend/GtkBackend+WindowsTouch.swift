#if os(Windows)
    import CGtk
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

    /// The characters of `VK_PACKET` keys, for GtkBackend's key events on Windows.
    ///
    /// A character sent with `KEYEVENTF_UNICODE` -- as the touch keyboard, the
    /// emoji panel and Win32Synthesiser send it -- reaches GDK as a key with
    /// keyval `GDK_KEY_VoidSymbol` and keycode 231 (`VK_PACKET`), so
    /// `.onKeyPress` heard nothing: P91 on Windows GTK, 2026-10-23, five
    /// presses traced, all `keyval=0xffffff keycode=231`, and "A heard" stayed
    /// empty where WSL heard "ab". The character itself comes in the `WM_CHAR`
    /// that `TranslateMessage` makes from the `VK_PACKET` key-down; GDK pumps
    /// every waiting message before it hands its key events on, so the hook has
    /// read that `WM_CHAR` by the time the key-pressed handler asks.
    ///
    /// `VK_PACKET` 按鍵的字元，供 GtkBackend 在 Windows 上的按鍵事件使用。以 `KEYEVENTF_UNICODE` 送出的字元——
    /// 觸控鍵盤、表情符號面板與 Win32Synthesiser 都這樣送——到 GDK 時是 keyval `GDK_KEY_VoidSymbol`、keycode 231
    /// (`VK_PACKET`)的按鍵，因此 `.onKeyPress` 什麼都沒聽到:2026-10-23 Windows GTK 上的 P91,追蹤五次按下全是
    /// `keyval=0xffffff keycode=231`,「A heard」維持空白，而 WSL 聽到了「ab」。字元本身在 `TranslateMessage` 由
    /// `VK_PACKET` 按下所產生的 `WM_CHAR` 裡;GDK 在交出按鍵事件之前會先抽完所有等待中的訊息，因此 key-pressed
    /// handler 詢問時,hook 已讀到那則 `WM_CHAR`。
    @MainActor
    enum GtkWindowsPacketKeys {
        static let keycode: UInt32 = 0xE7  // VK_PACKET
        /// Milliseconds a character may lie before its key event. / 字元可早於其按鍵事件的毫秒數。
        private static let window: UInt32 = 50
        /// The time of the last VK_PACKET key-down, while its WM_CHAR is awaited.
        /// 上一個 VK_PACKET 按下的時間，於等待其 WM_CHAR 期間。
        private static var packetDownTime: UInt32?
        /// Characters by the time of their key-down. A plain queue matched them
        /// in order and went one off as soon as a packet key reached a widget
        /// that does not ask (a button): P91 heard "cdy" for "cde" (2026-10-23).
        /// 依按下時間記錄的字元。單純的佇列依序配對，只要有一個 packet 按鍵送到不會來取的 widget(按鈕)就整個
        /// 錯位一格:P91 把「cde」聽成「cdy」(2026-10-23)。
        private static var pending: [(time: UInt32, scalar: UInt32)] = []
        /// The keyval of the last packet key pressed, for its release.
        /// 上一個按下的 packet 按鍵的 keyval,供其放開時使用。
        private(set) static var lastKeyval: UInt = 0

        /// The same hook as GtkWindowsTouch's. / 與 GtkWindowsTouch 相同的 hook。
        static func install() {
            GtkWindowsTouch.install()
        }

        /// The keyval for the packet key whose event has `time`, or nil if its
        /// character was not seen; characters of earlier keys are dropped.
        /// 事件時間為 `time` 的 packet 按鍵的 keyval;若未見到其字元則為 nil;較早按鍵的字元一併丟棄。
        static func takeKeyval(time: UInt32) -> UInt? {
            // GDK makes event times strictly increasing, adding a millisecond to
            // a key that shares its message time with the one before: "ab" typed
            // together lost the b to an exact match (2026-10-23). So a character
            // matches within `window` before the event; older ones are a key that
            // went elsewhere.
            // GDK 讓事件時間嚴格遞增，與前一個按鍵同一訊息時間的按鍵會被加上一毫秒：一起打的「ab」以完全相符比對時
            // 丟了 b(2026-10-23)。因此字元在事件之前 `window` 以內即算相符;更早的是送到別處的按鍵。
            pending.removeAll { $0.time &+ window < time }
            guard let first = pending.first, first.time <= time else { return nil }
            let keyval = UInt(gdk_unicode_to_keyval(pending.removeFirst().scalar))
            lastKeyval = keyval
            return keyval
        }

        fileprivate static func received(_ message: MSG) {
            switch message.message {
                case UINT(WM_KEYDOWN):
                    packetDownTime = message.wParam == WPARAM(keycode) ? UInt32(message.time) : nil
                case UINT(WM_CHAR):
                    if let time = packetDownTime {
                        pending.append((time, UInt32(truncatingIfNeeded: message.wParam)))
                        packetDownTime = nil
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
                GtkWindowsPacketKeys.received(message)
            }
        }
        return CallNextHookEx(nil, nCode, wParam, lParam)
    }
#endif
