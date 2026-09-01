#if os(Windows)

import Foundation
import WinSDK

/// Posts events through `SendInput`.
///
/// `SendInput` is a Win32 function in `user32.dll`, not a library to obtain, and
/// it posts to the foreground window rather than to a chosen one -- hence the
/// caller presenting its window before replaying anything.
///
/// Mouse positions go through `MOUSEEVENTF_ABSOLUTE`, which does not take
/// pixels: it takes a position on a 0-65535 grid spanning the virtual desktop.
/// Passing pixels there is a mistake that produces a cursor near the top-left
/// corner rather than an error.
public final class Win32Synthesiser: Synthesiser, Sendable {
    /// What the toolkit laid out with, when the caller knows and Windows
    /// disagrees. `nil` means ask `GetDpiForWindow`.
    /// 當呼叫端知道 toolkit 用了什麼比例、而 Windows 的說法與之不同時，採用此值。`nil` 代表
    /// 改問 `GetDpiForWindow`。
    private let layoutScale: Double?

    public init(layoutScale: Double? = nil) {
        self.layoutScale = layoutScale
    }

    /// The user's setting, read from the system rather than assumed.
    /// `GetDoubleClickTime` returns milliseconds and defaults to 500, but it is
    /// adjustable in Control Panel, so a file that hard-coded a gap would
    /// behave differently on two machines.
    public var doubleClickInterval: Int { Int(GetDoubleClickTime()) * 1000 }

    /// Asks Windows for our own window's frame and client origins.
    ///
    /// `GetWindowRect` gives the frame, decorations included. The client origin
    /// is found by mapping the client area's own `(0,0)` into screen space with
    /// `ClientToScreen`, rather than by subtracting a title bar height --
    /// there is no reliable constant for that, and a window with client-side
    /// decorations has none at all.
    ///
    /// The scale comes from `GetDpiForWindow`, which is per-monitor: a window
    /// dragged to a differently scaled display reports a different value, which
    /// is why it is read here rather than once at startup.
    ///
    /// Our own window, not `GetForegroundWindow`'s. `SendInput` posts to
    /// whatever is in front, so measuring a different window would compute
    /// coordinates in one frame of reference and deliver clicks in another. The
    /// equivalent assumption on Linux was measured to be wrong -- a window
    /// presented at startup was not focused a second later, and a replay
    /// reported success while driving something else.
    ///
    /// 使用自己的視窗，而非 `GetForegroundWindow` 的。`SendInput` 會投遞至位於前方的任何視窗，
    /// 因此量測另一個視窗會導致「在某個參考座標系中計算座標，卻在另一個座標系中投遞點擊」。
    /// Linux 上的同一項假設已實測為錯誤——啟動時 present 的視窗一秒後並未取得焦點，而重放回報
    /// 成功，實際驅動的卻是別的程式。
    public func currentWindowGeometry() throws -> WindowGeometry {
        let window = try ownWindow()

        var frame = RECT()
        guard GetWindowRect(window, &frame) else {
            throw SynthesiserError.toolFailed("GetWindowRect", status: Int32(GetLastError()))
        }

        var clientOrigin = POINT(x: 0, y: 0)
        guard ClientToScreen(window, &clientOrigin) else {
            throw SynthesiserError.toolFailed("ClientToScreen", status: Int32(GetLastError()))
        }

        // The caller's answer wins, because Windows answers a different
        // question. `GetDpiForWindow` reports what the *display* is scaled to;
        // what a coordinate needs is what the *toolkit* laid out with, and GTK 4
        // on Windows rounds to an integer, so at 125% Windows says 1.25 and GTK
        // used 1. See WindowGeometry.scale for the measurement.
        //
        // WinUIBackend passes nothing and so keeps the DPI, which is right for a
        // framework whose own unit is the fractional DIP -- but say plainly that
        // this is reasoning, not a measurement: nothing has ever been driven
        // against WinUIBackend at a scale other than 100%.
        //
        // 呼叫端的答案優先，因為 Windows 回答的是另一個問題。`GetDpiForWindow` 回報的是**顯示器**
        // 被縮放成多少；而座標所需要的，是**toolkit** 排版時所用的比例。Windows 上的 GTK 4 會取整，
        // 因此在 125% 時 Windows 說 1.25、GTK 用的卻是 1。量測依據見 WindowGeometry.scale。
        //
        // WinUIBackend 不傳入任何值，因而沿用 DPI；對一個以小數 DIP 為單位的框架而言這是對的——
        // 但必須明說這是推論而非量測：從來沒有人在 100% 以外的縮放下驅動過 WinUIBackend。
        let dpi = GetDpiForWindow(window)
        let scale = layoutScale ?? (dpi == 0 ? 1.0 : Double(dpi) / 96.0)

        // Divided by the scale so both origins are in logical points, which is
        // what an action file's coordinates are. screenPosition multiplies back
        // by the same scale; doing it in one place keeps the round trip honest.
        return WindowGeometry(
            frameOrigin: (Double(frame.left) / scale, Double(frame.top) / scale),
            clientOrigin: (Double(clientOrigin.x) / scale, Double(clientOrigin.y) / scale),
            scale: scale
        )
    }

    /// Pins our window above every other window, and takes focus if the file
    /// needs it.
    ///
    /// Measuring the right window is not enough on its own. `SendInput` posts to
    /// whatever is on top at the point it names, so a window that is behind
    /// another one gets a replay delivered to that other application: correct
    /// coordinates, computed from the correct window, wrong target. Nothing
    /// reports it -- `SendInput` accepts the events and returns success.
    ///
    /// Measured 2026-08-26, twice, against a real desktop. This was a bare
    /// `SetForegroundWindow(window)` with its result discarded, while every
    /// other Win32 call in this file is guarded, and both runs clicked into the
    /// editor covering the app instead: the first collapsed two tree items in
    /// it, the second opened a new document. Both runs reported success.
    ///
    /// `SetForegroundWindow` cannot be the mechanism. Windows refuses a
    /// foreground change asked for by a process that is neither already in front
    /// nor the owner of the last input event, and flashes the taskbar button
    /// instead -- so an app launched from a background shell can never take it.
    /// `testapp/P6.swift` recorded exactly this and solved it with
    /// `SetWindowPos(HWND_TOPMOST)`, which is subject to no such rule: any
    /// process may raise its own window, and `SWP_NOACTIVATE` means it does not
    /// even ask for focus. Same remedy here.
    ///
    /// Focus is a separate question, and only a keyboard event needs it -- those
    /// go to whatever holds focus, wherever the pointer is. So focus is
    /// attempted, and its failure is fatal only for a file that presses keys. A
    /// mouse-only file is safe on the topmost pin alone, and refusing to run it
    /// would be refusing something that works.
    ///
    /// 將我方視窗釘在所有視窗之上；若動作檔需要，再取得焦點。
    ///
    /// 光是「量對視窗」並不足夠。`SendInput` 投遞至其所指定座標上方的視窗，因此位於他人之後的
    /// 視窗，會把整場重放交給那個應用程式：座標正確、來源視窗也正確，目標卻是錯的。而且沒有任何
    /// 東西會回報——`SendInput` 會接受這些事件並回報成功。
    ///
    /// 於 2026-08-26 對真實桌面實測兩次。此處原本是一行捨棄回傳值的 `SetForegroundWindow(window)`
    /// ——而本檔其他每個 Win32 呼叫都有防護——兩次都改而點進了覆蓋在 app 上方的編輯器：第一次摺疊了
    /// 其中兩個樹狀項目，第二次開了一份新文件。兩次都回報成功。
    ///
    /// `SetForegroundWindow` 不能作為此處的機制。Windows 會拒絕「既不在前方、也不擁有最後一個輸入
    /// 事件」之行程所提出的前景切換，改為閃爍其工作列按鈕——因此由背景 shell 啟動的 app 永遠拿不到
    /// 前景。`testapp/P6.swift` 記錄過的正是此事，並以 `SetWindowPos(HWND_TOPMOST)` 解決；後者不受
    /// 該規則約束：任何行程都可以抬升自己的視窗，而 `SWP_NOACTIVATE` 代表它甚至不會索取焦點。此處
    /// 採用相同的解法。
    ///
    /// 焦點是另一個問題，且只有鍵盤事件需要它——按鍵會送往持有焦點者，與指標位置無關。因此焦點是
    /// 「嘗試取得」，而其失敗僅對「會按鍵的動作檔」才是致命的。只用滑鼠的檔案單靠置頂即可安全執行，
    /// 拒絕執行它等於拒絕了一件本來可行的事。
    public func prepareForReplay(_ actions: [InputAction]) throws {
        let window = try ownWindow()

        if IsIconic(window) {
            ShowWindow(window, SW_RESTORE)
        }

        // HWND_TOPMOST is `((HWND)-1)`, a macro Swift does not import -- the
        // same bit-pattern construction testapp/P6.swift uses.
        // HWND_TOPMOST 是 `((HWND)-1)` 巨集，Swift 不會匯入——此處採用與 testapp/P6.swift 相同的
        // bit-pattern 構造方式。
        guard
            SetWindowPos(
                window, HWND(bitPattern: -1), 0, 0, 0, 0,
                UINT(SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE)
            )
        else {
            throw SynthesiserError.toolFailed(
                "SetWindowPos(HWND_TOPMOST)", status: Int32(GetLastError())
            )
        }

        SetForegroundWindow(window)
        BringWindowToTop(window)

        // The read-back below is not behind the keyboard guard, and that is the
        // point: what is requested here must be looked at. Asking for the
        // foreground and returning without checking is the shape #46 records --
        // `SetForegroundWindow` unchecked, two runs driving the editor that
        // covered the app, both reporting success. The guard decides how loudly
        // a failure is reported, not whether it is noticed.
        // 下方的讀回檢查**不**放在鍵盤 guard 之後，而這正是重點：此處提出的要求，必須被看過。
        // 要求前景卻不檢查就返回，正是 #46 所記錄的形狀——`SetForegroundWindow` 未經檢查，兩次
        // 執行都驅動了覆蓋在 app 上方的編輯器，而兩次都回報成功。guard 決定的是「失敗要多大聲」，
        // 不是「失敗會不會被發現」。

        // No `AttachThreadInput` here, and that is a measurement rather than an
        // omission.
        //
        // The known problem is that Windows grants a foreground change only to
        // a process already in front, owning the last input event, or with no
        // foreground window -- and an app launched from a shell is none of
        // those. `AttachThreadInput` to the foreground thread is the standard
        // remedy, and it was written, tried, and taken out again on 2026-08-27
        // because it changed nothing: P10 driven by a Ctrl-Q file quit with it
        // and quit without it. What made this work is the
        // `SetWindowPos(HWND_TOPMOST)` above, which landed after #52 was filed.
        //
        // Left out because unused code that looks load-bearing is worse than
        // absent code. If a keyboard file ever fails here again, attaching to
        // the foreground thread before the `SetForegroundWindow` above is the
        // thing to try, and this note is the record that it is not currently
        // needed. Named rather than written as "this call": the call moved once
        // already, and a pronoun pointing across a page of comment is how a
        // reader ends up attaching before the read-back loop, where it does
        // nothing.
        //
        // 此處沒有 `AttachThreadInput`，而這是量測的結果，並非疏漏。
        //
        // 已知的問題是：Windows 只允許「已在前景」、「擁有最後一個輸入事件」或「沒有前景視窗」的
        // 行程切換前景，而由 shell 啟動的 app 三者皆非。附加至前景執行緒是標準解法；它已於
        // 2026-08-27 寫出、試過，然後又被移除，因為它什麼也沒改變：以 Ctrl-Q 動作檔驅動的 P10，
        // 加不加它都同樣結束。真正讓此處可行的，是上方的 `SetWindowPos(HWND_TOPMOST)`——它是在
        // #52 被提出之後才加入的。
        //
        // 之所以不留下，是因為「看起來承重、實則無用」的程式碼比「沒有程式碼」更糟。若日後鍵盤
        // 動作檔在此再次失敗，「在上方的 `SetForegroundWindow` 之前附加至前景執行緒」就是該試的
        // 東西，而本註解即是「目前並不需要它」的紀錄。此處直接寫出呼叫名稱而非「此呼叫」：那個呼叫
        // 已經被搬移過一次，而一個跨越整頁註解的指代詞，正是讓讀者把附加動作加在讀回迴圈之前
        // ——那裡什麼也不會發生——的原因。
        // The foreground change is asynchronous, so reading it back immediately
        // can miss a switch that is about to happen. Half a second is far longer
        // than it takes whenever it works at all.
        // 前景切換是非同步的，因此立刻讀回可能會錯過一個即將發生的切換。半秒遠長於它在任何能夠
        // 成功的情況下所需的時間。
        for _ in 0..<50 {
            if GetForegroundWindow() == window {
                return
            }
            Thread.sleep(forTimeInterval: 0.01)
        }

        // Failure from here on, and how much it matters depends on the file.
        //
        // A key event goes to whatever holds focus, so a file that presses keys
        // cannot proceed: it would type into another application. A mouse-only
        // file can, because `SendInput` posts by coordinate to whatever is on
        // top there, and `SetWindowPos(HWND_TOPMOST)` above already put our
        // window on top. This is what the doc comment on this method has said
        // all along; the code simply stopped doing it.
        //
        // Said out loud rather than passed over. The pin makes the run valid,
        // not identical: a window that never took the foreground behaves
        // differently for anything focus-sensitive inside it, and a reader
        // comparing this run against one that did take it deserves to know
        // which they have.
        //
        // 從這裡開始就是失敗了，而它有多要緊取決於動作檔的內容。
        //
        // 按鍵事件會送往持有焦點者，因此會按鍵的檔案無法繼續：它會打字到別的應用程式裡。只用滑鼠的
        // 檔案則可以，因為 `SendInput` 是依座標投遞給該處最上層的視窗，而上方的
        // `SetWindowPos(HWND_TOPMOST)` 已經把我方視窗放到最上層。這正是本方法的文件註解一直以來
        // 所寫的內容；只是程式碼不再那樣做了。
        //
        // 明確說出，而非略過。置頂讓這次執行有效，但不代表兩者相同：一個始終未取得前景的視窗，
        // 對其內部任何與焦點相關的東西，行為都會不同；而拿這次執行去和「確實取得前景」的那次比較的
        // 人，有權知道自己手上是哪一種。
        guard actions.contains(where: \.needsKeyboardFocus) else {
            ActionFileReplay.report(
                "warning: the window never took the foreground. This file only moves and "
                    + "clicks, so it ran on the topmost pin alone -- anything focus-sensitive "
                    + "may differ from a run that did take it."
            )
            return
        }

        throw SynthesiserError.windowNotForeground(
            "this file presses keys, and a key event goes to whichever window has focus"
        )
    }

    /// Lets the window fall back into the normal z-order.
    ///
    /// Not left pinned. Topmost is a state other windows cannot escape, and a
    /// test app that keeps it after its replay sits over everything the user
    /// does next. `testapp/P6.swift` notes the same cost from the other side:
    /// asserting it continuously breaks clicking controls and puts a file
    /// picker behind the window.
    ///
    /// 讓視窗回到正常的 z 順序。
    ///
    /// 不保持釘選狀態。置頂是其他視窗無法擺脫的狀態，一個在重放結束後仍維持置頂的測試 app，會壓在
    /// 使用者接下來所做的每一件事之上。`testapp/P6.swift` 從另一個角度記錄了相同的代價：持續強制
    /// 置頂會使控制項無法點選，也會讓檔案選取對話框跑到視窗後面。
    public func finishReplay() {
        guard let window = try? ownWindow() else { return }
        // HWND_NOTOPMOST is `((HWND)-2)`.
        _ = SetWindowPos(
            window, HWND(bitPattern: -2), 0, 0, 0, 0,
            UINT(SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE)
        )
    }

    public func perform(_ action: InputAction, in geometry: WindowGeometry) throws {
        switch action {
            case .move(let point):
                try move(to: point, in: geometry)

            case .click(let button, let point):
                if let point { try move(to: point, in: geometry) }
                try send(mouseFlags: Self.downFlag(for: button))
                try send(mouseFlags: Self.upFlag(for: button))

            case .doubleClick(let button, let point):
                try performDoubleClick(button, at: point, in: geometry)

            case .mouseDown(let button, let point):
                if let point { try move(to: point, in: geometry) }
                try send(mouseFlags: Self.downFlag(for: button))

            case .mouseUp(let button, let point):
                if let point { try move(to: point, in: geometry) }
                try send(mouseFlags: Self.upFlag(for: button))

            case .keyDown(let key):
                try send(key: key, up: false)

            case .keyUp(let key):
                try send(key: key, up: true)

            case .key(let key):
                try send(key: key, up: false)
                try send(key: key, up: true)

            case .scroll(let dx, let dy):
                // Vertical is inverted here and nowhere else. Windows counts a
                // positive wheel delta as rotation *away* from the user, which
                // scrolls up; our `dy` is positive downwards, matching GDK and
                // the horizontal wheel. Negating here rather than in the format
                // keeps a file meaning the same thing on both platforms, which
                // is the whole point of having one.
                //
                // 只有垂直方向在此處反轉。Windows 將正的滾輪 delta 視為「遠離使用者」的轉動，
                // 亦即向上捲動；而我們的 `dy` 以向下為正，與 GDK 及水平滾輪一致。在此處取負而非
                // 在格式層面處理，可使同一個檔案在兩個平台上意義相同——而那正是統一格式的目的。
                if dy != 0 {
                    try send(wheelFlags: MOUSEEVENTF_WHEEL, delta: -dy * Int(WHEEL_DELTA))
                }
                if dx != 0 {
                    try send(wheelFlags: MOUSEEVENTF_HWHEEL, delta: dx * Int(WHEEL_DELTA))
                }

            case .sleep(let microseconds):
                // Sleep takes milliseconds. A file asking for 500 microseconds
                // gets 1ms rather than 0, because rounding a sub-millisecond
                // wait down to nothing turns a deliberate pause into no pause
                // at all.
                Sleep(DWORD(max(1, microseconds / 1000)))
        }
    }

    /// This process's own visible top-level window, largest by area.
    ///
    /// Largest for the same reason as on Linux: a toolkit owns more than one
    /// top-level window and the first one enumerated can be an invisible helper
    /// or a tooltip host rather than the one the action file was written
    /// against.
    ///
    /// `EnumWindows` takes a C function pointer, which cannot capture, so the
    /// collector is passed through `LPARAM` -- the standard shape for this call
    /// and the reason for the `Unmanaged` round trip.
    ///
    /// 取面積最大者，理由與 Linux 相同：一個 toolkit 會擁有多個 top-level 視窗，而列舉到的第一個
    /// 可能是隱形的輔助視窗或 tooltip host，而非動作檔所針對的那一個。
    ///
    /// `EnumWindows` 接受的是 C function pointer，無法捕獲外部變數，因此收集器透過 `LPARAM`
    /// 傳入——這是此呼叫的標準寫法，也是使用 `Unmanaged` 來回轉換的原因。
    private func ownWindow() throws -> HWND {
        let collector = WindowCollector()
        let context = Unmanaged.passUnretained(collector).toOpaque()
        EnumWindows(
            { window, parameter in
                guard let window,
                    let context = UnsafeRawPointer(bitPattern: Int(parameter))
                else { return true }
                var processID: DWORD = 0
                GetWindowThreadProcessId(window, &processID)
                guard processID == GetCurrentProcessId(), IsWindowVisible(window) else {
                    return true
                }
                Unmanaged<WindowCollector>.fromOpaque(context)
                    .takeUnretainedValue()
                    .windows.append(window)
                return true
            },
            LPARAM(Int(bitPattern: context))
        )

        var best: (window: HWND, area: Int)?
        for window in collector.windows {
            var rect = RECT()
            guard GetWindowRect(window, &rect) else { continue }
            let area = Int(rect.right - rect.left) * Int(rect.bottom - rect.top)
            if best == nil || area > best!.area {
                best = (window, area)
            }
        }

        guard let best else {
            throw SynthesiserError.unsupported("no visible window for this process")
        }
        return best.window
    }

    private func move(to point: Point, in geometry: WindowGeometry) throws {
        let position = geometry.screenPosition(of: point)

        // `SetCursorPos` takes a physical screen coordinate, so multiple
        // monitors need no arithmetic here. Worth stating, because what this
        // replaced did need it and got it wrong once: a `SendInput` with
        // `MOUSEEVENTF_ABSOLUTE` normalises against a rectangle, and the
        // rectangle has to be the VIRTUAL DESKTOP (`SM_XVIRTUALSCREEN` and
        // friends) rather than the primary monitor. Using the primary one put
        // every click on the wrong screen whenever the window was not on it.
        // The bug is gone with the code, and the lesson would have gone too.
        //
        // Status 5 here is ERROR_ACCESS_DENIED and means a locked desktop or a
        // higher-integrity window in front. `testapp/ui-lock.zsh` matches on
        // that status rather than on the name of whichever call reported it,
        // precisely so this change of call did not silence it.
        //
        // `SetCursorPos` 接受的是實體螢幕座標，因此多螢幕在此不需要任何換算。值得寫明，是因為
        // 它所取代的做法確實需要換算，而且曾經算錯過一次：帶 `MOUSEEVENTF_ABSOLUTE` 的
        // `SendInput` 需要對一個矩形做正規化，而那個矩形必須是**虛擬桌面**（`SM_XVIRTUALSCREEN`
        // 等），不是主螢幕。用主螢幕會導致「視窗不在其上時，每一次點擊都落在錯的螢幕」。缺陷隨著
        // 那段程式碼一起消失，而那個教訓本來也會一起消失。
        //
        // 此處的狀態碼 5 是 ERROR_ACCESS_DENIED，代表桌面被鎖定，或前方站著一個完整性等級更高的
        // 視窗。`testapp/ui-lock.zsh` 比對的是該狀態碼，而非「回報它的是哪一個呼叫」的名稱——正是
        // 為了讓這次呼叫的更換不會使它失聲。
        guard SetCursorPos(Int32(position.x), Int32(position.y)) else {
            throw SynthesiserError.toolFailed("SetCursorPos", status: Int32(GetLastError()))
        }
        reportMouseMove(point: point, screen: position)
    }

    /// One line per pointer move, behind `--debug`.
    ///
    /// `-actionfile` alone is not enough to turn this on. That flag asks for a
    /// replay; it does not ask for a trace of one, and this fires on **every
    /// move** rather than once per run. `ActionFileReplay.report` is exempt from
    /// `--debug` on the stated grounds that it is one line per run, which is
    /// what makes an always-on diagnostic acceptable; borrowing that exemption
    /// for per-event output would take the exemption without its reason. See
    /// the project rule: keep normal UI test runs quiet unless `--debug` or an
    /// issue-specific flag is passed.
    ///
    /// 每一次指標移動輸出一行，位於 `--debug` 之後。
    ///
    /// 只有 `-actionfile` 並不足以開啟它。該旗標要求的是「重放」，而非「重放的追蹤紀錄」，
    /// 而這裡是**每一次移動**都會觸發，不是每次執行一行。`ActionFileReplay.report` 之所以能
    /// 免除 `--debug`，其載明的理由正是「每次執行僅一行」——那才是「一律輸出的診斷」可被接受
    /// 的原因；把該豁免借給逐事件的輸出，等於取走豁免卻不帶走它的理由。參見專案規則：除非傳入
    /// `--debug` 或 issue-specific 旗標，一般 UI 測試執行應保持安靜。
    private func reportMouseMove(point: Point, screen: (x: Int, y: Int)) {
        guard CommandLine.arguments.contains("-actionfile"),
            CommandLine.arguments.contains("--debug")
        else { return }

        var cursor = POINT()
        let cursorDescription: String
        if GetCursorPos(&cursor) {
            cursorDescription = "cursor=(\(cursor.x), \(cursor.y))"
        } else {
            cursorDescription = "cursor=unavailable(\(GetLastError()))"
        }

        // Through the one writer, rather than a second copy of it. Both copies
        // carried the same truncate-on-failure bug; one of them was fixed and
        // the other would not have been.
        // 走同一個寫入器，而非它的第二份副本。兩份副本帶著同一個「失敗即清空」的缺陷，
        // 修好其中一份時，另一份不會跟著被修。
        ActionFileReplay.report(
            "move \(point.origin.rawValue)=(\(point.x), \(point.y)) "
                + "screen=(\(screen.x), \(screen.y)) \(cursorDescription)"
        )
    }

    /// One wheel event carrying the whole delta.
    ///
    /// Not one event per notch: `mouseData` is a signed multiple of
    /// `WHEEL_DELTA`, and sending the total in a single event is what a real
    /// wheel with a high-resolution driver produces.
    private func send(wheelFlags: Int32, delta: Int) throws {
        var input = INPUT()
        input.type = DWORD(INPUT_MOUSE)
        input.mi.mouseData = DWORD(bitPattern: Int32(delta))
        input.mi.dwFlags = DWORD(wheelFlags)
        try dispatch(&input)
    }

    private func send(mouseFlags: Int32) throws {
        var input = INPUT()
        input.type = DWORD(INPUT_MOUSE)
        input.mi.dwFlags = DWORD(mouseFlags)
        try dispatch(&input)
    }

    private func send(key: Key, up: Bool) throws {
        guard let code = Self.virtualKey(for: key) else {
            throw SynthesiserError.unsupported("key '\(key.rawValue)' on Windows")
        }
        var input = INPUT()
        input.type = DWORD(INPUT_KEYBOARD)
        input.ki.wVk = WORD(code)
        input.ki.dwFlags = up ? DWORD(KEYEVENTF_KEYUP) : 0
        try dispatch(&input)
    }

    private func dispatch(_ input: inout INPUT) throws {
        let sent = withUnsafeMutablePointer(to: &input) {
            SendInput(1, $0, Int32(MemoryLayout<INPUT>.size))
        }
        guard sent == 1 else {
            throw SynthesiserError.toolFailed("SendInput", status: Int32(GetLastError()))
        }
    }

    private static func downFlag(for button: MouseButton) -> Int32 {
        switch button {
            case .left: MOUSEEVENTF_LEFTDOWN
            case .right: MOUSEEVENTF_RIGHTDOWN
            case .middle: MOUSEEVENTF_MIDDLEDOWN
        }
    }

    private static func upFlag(for button: MouseButton) -> Int32 {
        switch button {
            case .left: MOUSEEVENTF_LEFTUP
            case .right: MOUSEEVENTF_RIGHTUP
            case .middle: MOUSEEVENTF_MIDDLEUP
        }
    }

    /// Our macOS-derived names to Windows virtual-key codes.
    ///
    /// The traps this table has to absorb, both inherited from taking macOS
    /// names: our `delete` is Backspace, which Windows calls `VK_BACK` and
    /// spells `VK_DELETE` for the other one; and our `command` is the physical
    /// key in that position, which is the Windows key.
    private static func virtualKey(for key: Key) -> Int32? {
        switch key {
            case .a: 0x41
            case .b: 0x42
            case .c: 0x43
            case .d: 0x44
            case .e: 0x45
            case .f: 0x46
            case .g: 0x47
            case .h: 0x48
            case .i: 0x49
            case .j: 0x4A
            case .k: 0x4B
            case .l: 0x4C
            case .m: 0x4D
            case .n: 0x4E
            case .o: 0x4F
            case .p: 0x50
            case .q: 0x51
            case .r: 0x52
            case .s: 0x53
            case .t: 0x54
            case .u: 0x55
            case .v: 0x56
            case .w: 0x57
            case .x: 0x58
            case .y: 0x59
            case .z: 0x5A

            case .zero: 0x30
            case .one: 0x31
            case .two: 0x32
            case .three: 0x33
            case .four: 0x34
            case .five: 0x35
            case .six: 0x36
            case .seven: 0x37
            case .eight: 0x38
            case .nine: 0x39

            case .delete: VK_BACK
            case .forwardDelete: VK_DELETE
            case .return: VK_RETURN
            case .escape: VK_ESCAPE
            case .space: VK_SPACE
            case .tab: VK_TAB

            case .leftArrow: VK_LEFT
            case .rightArrow: VK_RIGHT
            case .upArrow: VK_UP
            case .downArrow: VK_DOWN
            case .home: VK_HOME
            case .end: VK_END
            case .pageUp: VK_PRIOR
            case .pageDown: VK_NEXT

            case .shift: VK_LSHIFT
            case .rightShift: VK_RSHIFT
            case .control: VK_LCONTROL
            case .rightControl: VK_RCONTROL
            case .option: VK_LMENU
            case .rightOption: VK_RMENU
            case .command: VK_LWIN
            case .rightCommand: VK_RWIN
            case .capsLock: VK_CAPITAL
            // No Windows equivalent: Fn is handled in keyboard firmware and
            // never reaches the OS as a key. nil rather than a wrong code, so
            // the caller is told instead of pressing something else.
            case .function: nil

            case .f1: VK_F1
            case .f2: VK_F2
            case .f3: VK_F3
            case .f4: VK_F4
            case .f5: VK_F5
            case .f6: VK_F6
            case .f7: VK_F7
            case .f8: VK_F8
            case .f9: VK_F9
            case .f10: VK_F10
            case .f11: VK_F11
            case .f12: VK_F12
            case .f13: VK_F13
            case .f14: VK_F14
            case .f15: VK_F15
            case .f16: VK_F16
            case .f17: VK_F17
            case .f18: VK_F18
            case .f19: VK_F19
            case .f20: VK_F20

            case .keypad0: VK_NUMPAD0
            case .keypad1: VK_NUMPAD1
            case .keypad2: VK_NUMPAD2
            case .keypad3: VK_NUMPAD3
            case .keypad4: VK_NUMPAD4
            case .keypad5: VK_NUMPAD5
            case .keypad6: VK_NUMPAD6
            case .keypad7: VK_NUMPAD7
            case .keypad8: VK_NUMPAD8
            case .keypad9: VK_NUMPAD9
            case .keypadDecimal: VK_DECIMAL
            case .keypadPlus: VK_ADD
            case .keypadMinus: VK_SUBTRACT
            case .keypadMultiply: VK_MULTIPLY
            case .keypadDivide: VK_DIVIDE
            // The keypad's Enter is VK_RETURN with the extended-key flag, which
            // this does not set; unmodified it is the main Return. Close enough
            // for a UI test and noted so nobody reads it as exact.
            case .keypadEnter: VK_RETURN
            // No virtual-key code exists for either.
            case .keypadEquals: nil
            case .keypadClear: VK_CLEAR
        }
    }
}

/// Somewhere for the `EnumWindows` callback to put what it finds.
///
/// A class rather than an inout array because the callback is a C function
/// pointer and receives only an opaque `LPARAM`; a reference type is what can
/// survive that round trip.
///
/// 供 `EnumWindows` callback 存放其結果之處。使用 class 而非 inout array，是因為該 callback
/// 是 C function pointer，只能收到一個不透明的 `LPARAM`；能通過這趟轉換的只有 reference type。
private final class WindowCollector {
    var windows: [HWND] = []
}

#endif
