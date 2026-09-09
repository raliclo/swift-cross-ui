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
        var popover: (x: Double, y: Double)?
        if let hwnd = popoverWindow(over: window) {
            var rect = RECT()
            if GetWindowRect(hwnd, &rect) {
                popover = (Double(rect.left) / scale, Double(rect.top) / scale)
            }
        }

        return WindowGeometry(
            frameOrigin: (Double(frame.left) / scale, Double(frame.top) / scale),
            clientOrigin: (Double(clientOrigin.x) / scale, Double(clientOrigin.y) / scale),
            scale: scale,
            popoverOrigin: popover
        )
    }

    /// The popover, menu or modal open over `owner`, for `origin=popover`.
    ///
    /// Deliberately NOT the `GW_ENABLEDPOPUP` walk that ``innermostModal(over:)``
    /// uses, and the difference is the whole reason this is a separate function.
    /// That slot holds exactly ONE window, and since Direct Composition became
    /// GtkBackend's default it is already filled by the main window's own
    /// content surface -- same size, correctly rejected by ``isSmaller(_:than:)``,
    /// and the walk therefore never reaches the popover. Measured in #111 on
    /// 2026-09-09: the popover appeared in the replay's own dump on every action
    /// while being invisible to that walk.
    ///
    /// So this asks the question the dump already answers: among the visible
    /// top-levels of this process, which one is OWNED by the window being driven
    /// and smaller than it? On the three runs measured that was the popover and
    /// nothing else -- `291x221`, owner the main window, against a `808x933`
    /// main window whose own owner is none.
    ///
    /// **This does not change which window a replay drives.** `ownWindow()` is
    /// untouched, and it must stay untouched: the walk's choice sets the origin
    /// for `origin=frame`, and making it prefer the popover was tried in #111
    /// and reverted, because the light-dismiss action file has to click OUTSIDE
    /// the popover and its coordinates resolve against the main window. This is
    /// a per-action lookup that sits beside that choice rather than replacing it.
    ///
    /// Smallest rather than largest, when more than one qualifies: a menu opened
    /// from a popover is owned by the same top-level, and the innermost is the
    /// one an action file means.
    ///
    /// 供 `origin=popover` 使用的「開啟於 `owner` 之上的 popover、選單或 modal」。
    ///
    /// **刻意不採用** ``innermostModal(over:)`` 所用的 `GW_ENABLEDPOPUP` 走訪,而兩者的差異正是本
    /// 函式獨立存在的全部理由。那個位置只容納**一個**視窗,而自從 Direct Composition 成為 GtkBackend
    /// 的預設值之後,它早已被主視窗自己的內容 surface 佔滿——尺寸相同,被 ``isSmaller(_:than:)``
    /// 正確地拒絕,於是該走訪永遠到不了 popover。此事於 #111 在 2026-09-09 實測:popover 在重放
    /// 自己的傾印中**每一個動作都出現**,卻對那個走訪不可見。
    ///
    /// 因此本函式問的是傾印早已回答的問題:在本行程的可見 top-level 之中,哪一個**被所驅動的視窗
    /// 擁有**且比它小?在量測過的三次執行中,那就是 popover、且僅有它——`291x221`,owner 為主視窗;
    /// 而主視窗為 `808x933`、其 owner 為 none。
    ///
    /// **本函式不會改變重放所驅動的視窗。** `ownWindow()` 未被更動,而且必須維持不動:走訪的選擇
    /// 決定了 `origin=frame` 的原點,而「讓它偏好 popover」已在 #111 中試過並撤回,因為 light-dismiss
    /// 動作檔必須點在 popover **之外**,其座標是對主視窗換算的。本函式是一個**逐動作**的查找,
    /// 與那個選擇並存而非取代它。
    ///
    /// 當符合者不只一個時取**最小**而非最大:由 popover 開啟的選單被同一個 top-level 擁有,而動作檔
    /// 所指的是最內層的那一個。
    private func popoverWindow(over owner: HWND) -> HWND? {
        let ownerKey = UInt(bitPattern: Int(bitPattern: owner))
        var best: (window: HWND, area: Int)?
        for candidate in visibleWindows() {
            guard candidate != owner else { continue }
            guard let candidateOwner = GetWindow(candidate, UINT(GW_OWNER)),
                UInt(bitPattern: Int(bitPattern: candidateOwner)) == ownerKey,
                isSmaller(candidate, than: owner)
            else { continue }
            var rect = RECT()
            guard GetWindowRect(candidate, &rect) else { continue }
            let area = Int(rect.right - rect.left) * Int(rect.bottom - rect.top)
            if best == nil || area < best!.area {
                best = (candidate, area)
            }
        }
        if let best { return best.window }

        // The driven window may already BE the popover, and before 2026-09-10 it
        // could not be, which is why this branch is new rather than defensive.
        //
        // `innermostModal` now resolves a content surface back to its window, so
        // once a popover is up the walk lands on the POPOVER rather than on the
        // main window. The search above then asks "which visible window is owned
        // by the popover and smaller than it" and correctly finds nothing -- so
        // `origin=popover` failed with "no popover is open" at the exact moment
        // the code had finally started driving one.
        //
        // The test is the same one that identifies a popover anywhere else here:
        // a visible toplevel, owned by another visible window, and smaller than
        // its owner. Asking it of `owner` itself costs one call and removes a
        // failure that would read as the popover being absent.
        //
        // 被驅動的那個視窗**本身**可能就是 popover;而在 2026-09-10 之前它不可能是——這正是本分支
        // 是「新增」而非「防禦性」的原因。
        //
        // `innermostModal` 現在會把內容 surface 解析回它的視窗,因此 popover 一旦升起,走訪會落在
        // **popover** 上而非主視窗上。於是上方的搜尋所問的是「哪一個可見視窗由這個 popover 所擁有
        // 且比它小」,而它正確地找不到任何東西——`origin=popover` 於是在「程式終於開始驅動一個
        // popover」的那一刻,以「沒有 popover 開啟」失敗。
        //
        // 判準與此處其他地方辨識 popover 所用的完全相同:一個可見的 toplevel、被另一個可見視窗所
        // 擁有、且比它的擁有者小。對 `owner` 自己問一次這個問題只多一次呼叫,卻消除了一個
        // 「讀起來像是 popover 不存在」的失敗。
        guard let ownersOwner = GetWindow(owner, UINT(GW_OWNER)),
            IsWindowVisible(ownersOwner),
            isSmaller(owner, than: ownersOwner)
        else { return nil }
        return owner
    }

    /// The HWND `currentWindowGeometry()` would measure, as a comparable value.
    ///
    /// `0` on failure rather than a throw, because the caller reads `0` as
    /// "unchanged" -- an identity check that cannot be answered must not be the
    /// thing that aborts a replay.
    ///
    /// 以可比較的數值回傳 `currentWindowGeometry()` 將會量測的那個 HWND。
    ///
    /// 失敗時回傳 `0` 而非拋出錯誤，因為呼叫端會把 `0` 讀作「未改變」——一個「無法回答的識別檢查」
    /// 不應該成為中止整個重放的原因。
    public func currentWindowIdentity() -> Int {
        guard let window = try? ownWindow() else { return 0 }
        return Int(bitPattern: window)
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
        hideOwnConsoleOnce()

        // Before `ownWindow()`, not after: the remembered focus steers it, so a
        // stale one from a previous replay in the same process would decide
        // which window this replay pins and measures.
        // 放在 `ownWindow()` 之前而非之後:被記住的焦點會左右它,因此同一行程中前一次重放留下的
        // 陳舊值,會決定這一次重放要釘住並量測哪一個視窗。
        Self.forgetFocus()

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

        // SECOND ATTEMPT, and only for a file that cannot proceed without focus.
        //
        // The note above is a live instruction, not history: it says that if a
        // keyboard file ever fails here again, attaching to the foreground
        // thread before `SetForegroundWindow` is the thing to try. On
        // 2026-09-05 all three keyboard files in actions/win did fail --
        // P10-ctrl-q, P18-three-dialogs, P31-tab-and-escape, which is every
        // file there carrying a key event and no others -- so the condition it
        // names has occurred.
        //
        // Placed HERE rather than before the first attempt, so the path that
        // already works is not touched. `SetWindowPos(HWND_TOPMOST)` plus a
        // plain `SetForegroundWindow` is what made keyboard files work when #52
        // was closed, and 15 mouse files still pass on it today; a change ahead
        // of that would put every one of them on an untested path to fix three.
        //
        // WHAT THIS DOES NOT CLAIM: that it works. It did nothing in the
        // 2026-08-27 trial, and that trial's subject was P10 driven by a Ctrl-Q
        // file -- one of the three failing now. Attaching may well fail again,
        // because the window holding the foreground here is Program Manager,
        // the desktop shell, and the input queue we would be joining is
        // explorer.exe's. The reason to add it anyway is that the alternative
        // is three files that cannot run at all, and a second attempt that is
        // measured beats a first attempt that is only regretted.
        //
        // Set SCUI_NO_ATTACH_INPUT=1 to take this path out at runtime, so the
        // with/without comparison is one build and not two.
        //
        // 第二次嘗試，且僅針對「沒有焦點就無法進行」的檔案。
        //
        // 上方那段註解是一道**生效中的指示**，不是歷史紀錄：它寫明若鍵盤動作檔日後在此再次失敗，
        // 該試的就是「在 `SetForegroundWindow` 之前附加至前景執行緒」。2026-09-05，actions/win
        // 中的三個鍵盤檔案全部失敗——P10-ctrl-q、P18-three-dialogs、P31-tab-and-escape，恰好就是
        // 該目錄中帶有按鍵事件的全部檔案，不多不少——因此它所指名的條件已經成立。
        //
        // 放在**這裡**而非第一次嘗試之前，如此已經可行的路徑就不會被動到。`SetWindowPos(HWND_TOPMOST)`
        // 搭配單純的 `SetForegroundWindow`，正是 #52 結案時讓鍵盤檔案得以運作的組合，而今天仍有
        // 15 個滑鼠檔案靠它通過；把改動放在它之前，等於為了修三個而讓那十五個全部走上未經測試的路徑。
        //
        // 本段不主張的事：它會成功。在 2026-08-27 的試驗中它毫無作用，而那次試驗的對象正是以
        // Ctrl-Q 動作檔驅動的 P10——今天失敗的三個之一。附加很可能再次失敗，因為此處持有前景的是
        // Program Manager（桌面 shell），我們要加入的是 explorer.exe 的輸入佇列。仍然加上它的理由
        // 是：另一個選項是三個檔案根本無法執行，而「一次被量測過的第二嘗試」勝過「一次只剩懊悔的
        // 第一嘗試」。
        //
        // 設定 SCUI_NO_ATTACH_INPUT=1 可在執行期停用此路徑，使「有/無」的對照只需一份建置。
        if actions.contains(where: \.needsKeyboardFocus),
            ProcessInfo.processInfo.environment["SCUI_NO_ATTACH_INPUT"] != "1",
            takeForegroundByAttachingInput(to: window)
        {
            return
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

    /// Hides this process's OWN console window, and only its own.
    ///
    /// SwiftPM emits console-subsystem executables -- `objdump -p` reports
    /// subsystem 3 for every `testapp/output/Pn-gtk4.exe` -- so a Pn launched
    /// detached is given a console window of its own. That window is created
    /// after the app starts, holds the foreground, and sits over the app's own
    /// window; `WindowFromPoint` then returns it and every synthesised click
    /// goes to a console instead of to the view under test.
    ///
    /// Measured 2026-09-06 on P16-force-update, whose run was correct in every
    /// other respect -- right toplevel chosen, right origin, coordinates inside
    /// the window -- and still reported `hitClass=ConsoleWindowClass
    /// foreground=0x50832`, a handle adjacent to the app's own 0x50812. Three
    /// clicks, all swallowed. Nothing failed and nothing warned.
    ///
    /// ONLY WHEN THIS PROCESS OWNS IT, which `GetConsoleProcessList` answers:
    /// a count of one means the console exists for this process alone. Launched
    /// from a shell the console belongs to that shell and is shared, and hiding
    /// it would take away the operator's terminal.
    ///
    /// The same test and the same reasoning as `testapp/P6.swift`, which solved
    /// this for itself in `hideOwnConsoleOnce` and recorded that the "jump to
    /// the terminal" people saw was P6's own console. It was solved for one app
    /// and left for the other forty-two; this is the replay path, so every app
    /// driven by an action file gets it.
    ///
    /// 隱藏**本行程自己的**主控台視窗，且僅限自己的。
    ///
    /// SwiftPM 產生的是 console 子系統的執行檔——`objdump -p` 對每一個
    /// `testapp/output/Pn-gtk4.exe` 都回報 subsystem 3——因此以分離方式啟動的 Pn 會獲得一個屬於
    /// 自己的主控台視窗。該視窗在 app 啟動之後才建立、持有前景、並且蓋在 app 自己的視窗之上；
    /// `WindowFromPoint` 於是回傳它，而每一次合成點擊都送進了主控台，而非受測的視圖。
    ///
    /// 2026-09-06 於 P16-force-update 實測：那次執行在其他每一方面都正確——選對了 toplevel、
    /// 原點正確、座標落在視窗內——卻仍然回報 `hitClass=ConsoleWindowClass foreground=0x50832`，
    /// 而該 handle 與 app 自己的 0x50812 相鄰。三次點擊，全被吞掉。沒有任何東西失敗，也沒有任何
    /// 東西發出警告。
    ///
    /// 僅在**本行程擁有它**時才隱藏，而這由 `GetConsoleProcessList` 回答：數量為一，代表該主控台
    /// 只為本行程而存在。若是從 shell 啟動，主控台屬於該 shell 且為多方共用，隱藏它等於奪走操作者
    /// 的終端機。
    ///
    /// 與 `testapp/P6.swift` 相同的判斷與相同的理由——它在 `hideOwnConsoleOnce` 中為自己解決了這
    /// 件事，並記載了使用者所看到的「跳到 terminal」其實是 P6 自己的主控台。那次只為一支 app 解決，
    /// 其餘四十二支被留了下來；此處是重放路徑，因此每一支由動作檔驅動的 app 都會得到它。
    /// `nonisolated(unsafe)` for the same reason the rest of this project uses
    /// it on once-only flags -- see `P11Diagnostics.didAnnounceRender`. A replay
    /// runs on one thread and the flag exists only to keep the console from
    /// being hidden twice; the cost of a race here is a second `ShowWindow` on
    /// an already hidden window.
    /// 使用 `nonisolated(unsafe)` 的理由與本專案其他「只執行一次」的旗標相同——參見
    /// `P11Diagnostics.didAnnounceRender`。重放在單一執行緒上進行，此旗標的存在只是為了避免主控台
    /// 被隱藏兩次；此處競態的代價，不過是對一個已經隱藏的視窗再呼叫一次 `ShowWindow`。
    nonisolated(unsafe) private static var didHideConsole = false

    private func hideOwnConsoleOnce() {
        guard !Self.didHideConsole else { return }
        Self.didHideConsole = true

        // Reported, because a silent return here is the whole failure mode this
        // function exists to stop. The first run after adding it printed NO
        // console line at all and two files passed; that is not evidence the
        // fix worked, it is evidence that nothing was observed -- and reading
        // the pass as a fix is the exact mistake catalogued half a dozen times
        // in mistakes.csv2.
        // 加上回報，因為「安靜地返回」正是本函式存在所要阻止的那一種失敗。加入本函式後的第一次執行
        // **一行 console 訊息都沒有印**，而兩個檔案都通過了；那不是「修正生效」的證據，而是「什麼
        // 都沒被觀察到」的證據——把通過讀成修正，正是 mistakes.csv2 中已記錄六次的同一個錯誤。
        guard let console = GetConsoleWindow() else {
            ActionFileReplay.report("this process has no console window to hide")
            return
        }

        var processes: [DWORD] = Array(repeating: 0, count: 4)
        let count = processes.withUnsafeMutableBufferPointer { buffer in
            GetConsoleProcessList(buffer.baseAddress, DWORD(buffer.count))
        }
        guard count == 1 else {
            ActionFileReplay.report(
                "console is shared with \(count) processes, leaving it alone"
            )
            return
        }

        _ = ShowWindow(console, SW_HIDE)
        ActionFileReplay.report("hid this process's own console window")
    }

    /// Joins the foreground window's input queue, asks again, and reports what
    /// happened either way.
    ///
    /// Windows grants a foreground change to a process that is already in
    /// front, owns the last input event, or finds no foreground window at all.
    /// A test app launched from a shell is none of those. `AttachThreadInput`
    /// makes two threads share one input queue, and for as long as they do,
    /// this process counts as the foreground one for the purposes of that
    /// check.
    ///
    /// Detached in a `defer`, without exception. An attachment left in place
    /// couples this process's input queue to another application's for the rest
    /// of its life -- if that one blocks, this one blocks with it -- and the
    /// early return on success is exactly the path where forgetting is easiest.
    ///
    /// Reports on BOTH outcomes rather than only on failure. This call has
    /// already been added once, measured to do nothing, and removed; a silent
    /// success would leave the next reader unable to tell whether it is
    /// carrying the run or is dead weight again.
    ///
    /// 加入前景視窗的輸入佇列、再要求一次，並且無論結果如何都回報。
    ///
    /// Windows 只把前景切換授予「已在前方」、「擁有最後一個輸入事件」或「當時沒有前景視窗」的
    /// 行程，而由 shell 啟動的測試 app 三者皆非。`AttachThreadInput` 使兩個執行緒共用同一個輸入
    /// 佇列；在共用期間，就上述檢查而言，本行程即被視為前景行程。
    ///
    /// 以 `defer` 解除附加，無一例外。留著不解的附加，會讓本行程的輸入佇列在其餘生中與另一個應用
    /// 程式綁在一起——對方一旦阻塞，本行程也隨之阻塞——而「成功時提早返回」正是最容易忘記解除的
    /// 那條路徑。
    ///
    /// 成功與失敗**都**回報，而非只在失敗時出聲。這個呼叫曾經被加入、被量出毫無作用、然後被移除；
    /// 若成功時保持沉默，下一位讀者將無從分辨它究竟是撐起了這次執行，還是又一次成了無用的重量。
    private func takeForegroundByAttachingInput(to window: HWND) -> Bool {
        // EVERY exit from here reports, including the two early ones. The first
        // measurement of this function produced no line at all on a run where
        // it must have been called -- the file presses keys and the foreground
        // was never taken -- and a silent return is indistinguishable from a
        // function that was never reached. That ambiguity cost an attempt to
        // explain a result that had no evidence behind it either way.
        //
        // 從此處起的**每一條**退出路徑都會回報，包含那兩條提早返回的。本函式的第一次量測，在一次
        // 它必然被呼叫到的執行上（該檔案會按鍵、且前景始終未取得）竟然一行都沒有輸出；而「安靜地
        // 返回」與「根本沒被執行到」是無法分辨的。那份歧義，換來了一次為「兩邊都沒有證據」的結果
        // 所做的解釋。
        guard let foreground = GetForegroundWindow() else {
            // Documented as the case where a foreground change is ALLOWED, so
            // reaching here and still having failed is worth seeing.
            // 文件上這正是「允許切換前景」的情況；因此走到這裡卻仍然失敗，值得被看見。
            ActionFileReplay.report(
                "no window holds the foreground, so there is no input queue to attach to"
            )
            return false
        }

        var foreignProcess: DWORD = 0
        let foreignThread = GetWindowThreadProcessId(foreground, &foreignProcess)
        let ownThread = GetCurrentThreadId()

        // Attaching a thread to itself is documented as an error, and it is
        // also the case where there is nothing to gain: if the foreground
        // window is already ours, the loop above would have returned.
        // 把執行緒附加到它自己，文件上即為錯誤；那同時也是「無利可圖」的情況：若前景視窗本來就是
        // 我方的，上方的迴圈早已返回。
        guard foreignThread != 0, foreignThread != ownThread else {
            ActionFileReplay.report(
                "the foreground window belongs to this thread already (\(foreignThread)), "
                    + "so attaching would be a no-op"
            )
            return false
        }

        // Named, so the next reader is not left guessing which application
        // refused. ACCESS_DENIED from `AttachThreadInput` depends entirely on
        // WHO holds the foreground, and "it failed with 5" without that is a
        // fact that cannot be acted on.
        // 指名道姓，讓下一位讀者不必猜是哪個應用程式拒絕了。`AttachThreadInput` 的 ACCESS_DENIED
        // 完全取決於**誰**持有前景；缺了這一項，「它以 5 失敗」是一個無法據以行動的事實。
        ActionFileReplay.report(
            "attaching to the foreground window \(foreground) class=\(className(of: foreground)) "
                + "thread=\(foreignThread) process=\(foreignProcess)"
        )

        guard AttachThreadInput(ownThread, foreignThread, true) else {
            ActionFileReplay.report(
                "AttachThreadInput to the foreground thread failed (\(GetLastError())); "
                    + "the window cannot take the foreground from here"
            )
            return false
        }
        defer { _ = AttachThreadInput(ownThread, foreignThread, false) }

        SetForegroundWindow(window)
        BringWindowToTop(window)

        for _ in 0..<50 {
            if GetForegroundWindow() == window {
                ActionFileReplay.report(
                    "took the foreground after attaching to the foreground thread"
                )
                return true
            }
            Thread.sleep(forTimeInterval: 0.01)
        }

        ActionFileReplay.report(
            "attached to the foreground thread and still did not take the foreground"
        )
        return false
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
        // EVERY window, not `ownWindow()`'s pick, and the difference is a
        // regression this caught on 2026-09-04. `prepareForReplay` pins whatever
        // `ownWindow()` returned BEFORE the replay -- the main window. Once
        // `ownWindow()` learned to follow a dialog, the two calls stopped naming
        // the same window whenever a file left a dialog open: the sheet had its
        // topmost cleared, which it never had, and the main window kept the
        // topmost it was given -- pinned over everything the user did next, which
        // is exactly what the comment below says must not happen.
        //
        // Clearing it on a window that never had it is a no-op, so the list costs
        // nothing and removes the need to remember which one was pinned. That
        // matters more than it looks: remembering would mean mutable state on a
        // `Sendable` type, and the stateless version cannot get it wrong.
        //
        // **每一個**視窗，而非 `ownWindow()` 的選擇；這個差別是本次（2026-09-04）抓到的一個回歸。
        // `prepareForReplay` 釘住的是重放**之前** `ownWindow()` 回傳的那一個——主視窗。而在
        // `ownWindow()` 學會追隨對話框之後，只要某份檔案結束時仍留著對話框，這兩個呼叫就不再指向
        // 同一個視窗：被解除釘選的是那個從未被釘選的 sheet，而主視窗保留了它被賦予的 topmost——
        // 壓在使用者接下來所做的每一件事之上，正是下方註解明文禁止的情況。
        //
        // 對從未被釘選的視窗解除釘選是 no-op，因此這份清單不花任何代價，並且免去了「記住釘了哪一
        // 個」的需要。這比看起來重要：記住它意味著要在一個 `Sendable` 型別上放可變狀態，而無狀態
        // 的版本不可能出錯。
        let windows = visibleWindows()
        for window in windows {
            // HWND_NOTOPMOST is `((HWND)-2)`.
            _ = SetWindowPos(
                window, HWND(bitPattern: -2), 0, 0, 0, 0,
                UINT(SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE)
            )
        }

        // The LAST look, and it has to be here or a whole class of file cannot
        // be judged at all. Identity is checked BEFORE each action, so a file
        // whose final action is the sleep that waits for a dialog never observes
        // that dialog: the check ran while it was still mapping, and nothing
        // looks again.
        //
        // This cost a false finding on 2026-09-04 and is the reason the line
        // exists. `finishReplay` used to call `ownWindow()`, which dumped as a
        // side effect. Replacing it with the `visibleWindows()` loop above --
        // correct in itself, and a real fix -- silently removed the only
        // observation point after the last action. Three runs of a one-click
        // file then showed no sheet, three runs of a two-click file showed one,
        // and that read exactly like "the first click is consumed". It was not.
        // The click had always worked; the instrument had stopped. Re-measured
        // with one extra sleep row so a check ran after the sheet mapped: 3/3.
        //
        // 最後一次觀察，而它必須在此，否則有一整類檔案根本無法被判定。identity 是在每個動作
        // **之前**檢查的，因此一份「最後一個動作是等待對話框的 sleep」的檔案，永遠不會觀察到
        // 那個對話框：檢查發生在它還在 map 的時候，而之後沒有任何東西再看一眼。
        //
        // 這在 2026-09-04 換來了一個**假發現**，也正是這幾行存在的理由。`finishReplay` 原本
        // 呼叫 `ownWindow()`，而後者會順帶輸出傾印。把它換成上方的 `visibleWindows()` 迴圈
        // ——那本身是正確的，也是一項真正的修正——卻**靜默地**移除了最後一個動作之後唯一的
        // 觀測點。接著單擊版檔案三次執行都看不到 sheet、雙擊版三次都看得到，而那讀起來完全就像
        // 「第一次點擊被吞掉了」。它並沒有。點擊一直都有效，是儀器停了。加一列 sleep 讓檢查在
        // sheet map 之後執行，重新量測：3/3。
        if let largest = largestByArea(of: windows) {
            reportWindowChoice(candidates: windows, chosen: innermostModal(over: largest))
        }
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

            case .focus(let window):
                try focusWindow(titled: window)

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
        let candidates = visibleWindows()

        // A `focus` row overrides largest-by-area, and only a `focus` row can.
        //
        // Largest-by-area is right for the case it was written for -- one window
        // plus the toolkit's helpers -- and wrong for the case `focus` exists to
        // create, because a second window is usually SMALLER than the first. A
        // settings window would lose the area contest to the main window, so
        // geometry and identity would both keep answering "main window" after a
        // successful focus, and every coordinate in the rows below it would be
        // converted against the wrong frame. Nothing would report that: the
        // replay would run to the end and click real controls.
        //
        // `innermostModal` still applies, so a dialog raised over the focused
        // window still wins -- the two rules compose rather than replacing each
        // other.
        //
        // `candidates.contains` is the guard that matters: a window that has
        // since closed must not keep steering the replay, and GTK is documented
        // in `innermostModal` above as keeping a destroyed HWND around briefly.
        // Falling back to largest-by-area is the pre-`focus` behaviour, which is
        // what every file without a `focus` row still gets, unchanged.
        //
        // 一列 `focus` 會覆蓋「面積最大」的規則,而且只有 `focus` 能。
        //
        // 「面積最大」對它當初被寫出來所針對的情況是對的——單一視窗加上 toolkit 的輔助視窗——而對
        // `focus` 所要創造的情況是錯的,因為第二個視窗通常**比第一個小**。設定視窗會在面積競賽中
        // 輸給主視窗,於是在一次成功的 focus 之後,幾何與 identity 都仍然回答「主視窗」,而其下每
        // 一列的座標都會以錯誤的框架換算。沒有任何東西會回報這件事:重放會一路跑到結束,並點到真實
        // 的控制項。
        //
        // `innermostModal` 仍然適用,因此在焦點視窗之上升起的對話框依然勝出——兩條規則是**疊加**
        // 的,不是互相取代。
        //
        // `candidates.contains` 是關鍵的那道防護:一個已經關閉的視窗不可以繼續主導重放,而上方
        // `innermostModal` 的註解已載明 GTK 會在對話框銷毀後短暫保留其 HWND。退回「面積最大」即是
        // `focus` 出現之前的行為,也正是每一個沒有 `focus` 列的檔案至今原封不動得到的行為。
        if let focused = Self.rememberedFocus(), candidates.contains(focused) {
            let chosen = innermostModal(over: focused)
            reportWindowChoice(candidates: candidates, chosen: chosen)
            return chosen
        }

        guard let largest = largestByArea(of: preferringOwners(among: candidates)) else {
            throw SynthesiserError.unsupported("no visible window for this process")
        }
        let chosen = innermostModal(over: largest)
        reportWindowChoice(candidates: candidates, chosen: chosen)
        return chosen
    }

    /// Drops any window that is OWNED by another candidate.
    ///
    /// Added 2026-09-05, when Direct Composition became GtkBackend's default and
    /// broke an action file that had worked for weeks.
    ///
    /// With DComp, GTK creates a second window per toplevel: a `GdkWin32GL`
    /// surface holding the GL content, owned by the real `gdkSurfaceToplevel`.
    /// The two are the SAME SIZE, so "largest by area" is a tie -- and the tie
    /// was going to the GL surface, whose origin is (0, 0) while the toplevel's
    /// is (26, 17). Every frame-relative coordinate was therefore converted
    /// against the wrong origin and every click landed 26 left and 17 up of
    /// where the file said.
    ///
    /// It failed the way this whole directory is written to prevent. Most
    /// targets are large enough to absorb 17px, so nearly every action file kept
    /// passing; only P13-zorder, whose target sits near the bottom edge, missed.
    /// One file in forty reporting a failure that is really a global coordinate
    /// shift is worse than none reporting it -- it reads as one flaky test.
    ///
    /// Ownership rather than class name. `GdkWin32GL` is what this instance is,
    /// but a rule naming it would be a rule about one toolkit's current
    /// spelling. "A window owned by another window I can also see is not the one
    /// the user is looking at" is true of tooltips, GL surfaces and helper
    /// windows alike. If every candidate is owned, the list is returned
    /// unchanged rather than emptied, because an empty list here is a thrown
    /// error and a wrong window still beats no window.
    ///
    /// 移除任何「被另一個候選者所擁有」的視窗。
    ///
    /// 於 2026-09-05 新增，當時 Direct Composition 成為 GtkBackend 的預設值，並弄壞了一份已經
    /// 正常運作數週的動作檔。
    ///
    /// 啟用 DComp 後，GTK 會為每個 toplevel 額外建立一個視窗：一個承載 GL 內容的 `GdkWin32GL`
    /// surface，由真正的 `gdkSurfaceToplevel` 所擁有。兩者**尺寸相同**，因此「面積最大」是平手
    /// ——而平手時勝出的是那個 GL surface，它的原點是 (0, 0)，真正的 toplevel 則是 (26, 17)。
    /// 於是每一個 frame 相對座標都以錯誤的原點換算，每一次點擊都落在檔案所述位置的左方 26、
    /// 上方 17 像素處。
    ///
    /// 它失敗的方式，正是整個目錄的寫法所要防範的那一種。多數目標夠大，足以吸收 17px 的偏移，
    /// 因此幾乎每一份動作檔都照樣通過；只有目標貼近底部邊緣的 P13-zorder 落空。**四十份中只有
    /// 一份回報失敗，而那其實是全域座標偏移**——這比「一份都沒回報」更糟，因為它讀起來像是
    /// 單一個不穩定的測試。
    ///
    /// 以「所有權」而非類別名稱判斷。`GdkWin32GL` 是此次的具體樣貌，但以它命名的規則，會是一條
    /// 關於「某個 toolkit 目前拼法」的規則。「一個被我同樣看得見的另一視窗所擁有的視窗，不會是
    /// 使用者正在看的那一個」——這對 tooltip、GL surface 與各種輔助視窗同樣成立。若所有候選者
    /// 都被擁有，則原樣返回而非清空，因為此處清空等同於拋出錯誤，而「選錯視窗」仍勝過「沒有視窗」。
    private func preferringOwners(among windows: [HWND]) -> [HWND] {
        let visible = Set(windows.map { UInt(bitPattern: Int(bitPattern: $0)) })
        let unowned = windows.filter { window in
            guard let owner = GetWindow(window, UINT(GW_OWNER)) else { return true }
            return !visible.contains(UInt(bitPattern: Int(bitPattern: owner)))
        }
        return unowned.isEmpty ? windows : unowned
    }

    /// The biggest of the given windows, or nil if none can be measured.
    ///
    /// Shared with ``finishReplay()`` rather than written twice. A second copy
    /// would be the sort that drifts: this one decides which window a replay
    /// drives, and the other decides what the final diagnostic reports, so two
    /// copies disagreeing would make the log describe a different window from
    /// the one that was driven -- while both looked right.
    ///
    /// 給定視窗中最大的那一個；若一個都量不到則回傳 nil。
    ///
    /// 與 ``finishReplay()`` 共用，而非寫兩份。第二份會是那種會漂移的副本：這一份決定重放要驅動
    /// 哪個視窗，另一份決定最後的診斷回報什麼；兩份一旦不一致，log 描述的就會是與實際被驅動者
    /// 不同的視窗——而兩邊看起來都沒問題。
    private func largestByArea(of windows: [HWND]) -> HWND? {
        var best: (window: HWND, area: Int)?
        for window in windows {
            var rect = RECT()
            guard GetWindowRect(window, &rect) else { continue }
            let area = Int(rect.right - rect.left) * Int(rect.bottom - rect.top)
            if best == nil || area > best!.area {
                best = (window, area)
            }
        }
        return best?.window
    }

    /// Every visible top-level window belonging to this process.
    ///
    /// Split out of ``ownWindow()`` when ``finishReplay()`` needed the whole list
    /// rather than the winner. Not a tidy-up: the two callers want different
    /// things from the same enumeration, and duplicating it would have given
    /// `finishReplay` a second copy to drift from.
    ///
    /// 本行程所有可見的 top-level 視窗。
    ///
    /// 在 ``finishReplay()`` 需要「整份清單」而非「勝出者」時，自 ``ownWindow()`` 抽出。這不是
    /// 順手整理：兩個呼叫端對同一次列舉想要的東西不同，而複製一份會讓 `finishReplay` 多出一份
    /// 可供漂移的副本。
    private func visibleWindows() -> [HWND] {
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
        return collector.windows
    }

    /// Follows the owned-dialog chain and returns the window input should go to.
    ///
    /// Largest-area alone picks the OWNER whenever a dialog is up, because a
    /// dialog is smaller than what it covers -- P1's sheet measures 428x174
    /// against 648x549. Every `origin=frame` coordinate is then resolved against
    /// the wrong frame origin, so the click is placed on the owner and GTK's
    /// modal grab discards it. That is the whole reason P1, P5, P18 and P31 could
    /// not be driven past the point where they raise a dialog.
    ///
    /// The loop, not a single step, because dialogs nest: P1 opens a sheet that
    /// opens another. The innermost one is the only window accepting input.
    ///
    /// Two guards, and neither is defensive padding. `GetWindow` is documented to
    /// return the window ITSELF when it owns no enabled popup, which would spin
    /// forever -- measured here it returns NULL instead, so the `!= window` test
    /// is what makes the code correct on the documented behaviour as well as the
    /// observed one. The depth cap covers a cycle the API should not produce; if
    /// it ever trips, a hung replay would be the alternative.
    ///
    /// `IsWindowVisible` is required, not decoration: GTK keeps a destroyed
    /// dialog's HWND around briefly, and driving a hidden window sends every
    /// remaining event nowhere while reporting nothing.
    ///
    /// 沿著「被擁有的對話框」這條鏈往下走，回傳輸入真正該送往的視窗。
    ///
    /// 只靠最大面積，在任何對話框開啟時都會選到**擁有者**，因為對話框比它所覆蓋的東西更小——P1 的
    /// sheet 是 428x174，對上 648x549。接著每一個 `origin=frame` 座標都會以錯誤的框架原點來解析，
    /// 於是點擊被放在擁有者身上，並被 GTK 的 modal grab 丟棄。這正是 P1、P5、P18、P31 一旦開啟
    /// 對話框就再也無法被驅動下去的全部原因。
    ///
    /// 用迴圈而非單一步驟，因為對話框會巢狀：P1 會開啟一個 sheet，而它又會開啟另一個。最內層的
    /// 那一個，才是唯一接受輸入的視窗。
    ///
    /// 兩道防護，且兩者都不是為防而防。`GetWindow` 在文件上載明：當視窗不擁有任何啟用中的 popup
    /// 時，它會回傳**視窗自己**——那會導致無窮迴圈；而此處實測回傳的是 NULL，因此 `!= window`
    /// 這個判斷，正是讓這段程式碼在「文件所述行為」與「實測行為」下都正確的東西。深度上限則涵蓋
    /// 這個 API 不該產生的環；若它真的觸發，另一個結果會是一個永遠卡住的重放。
    ///
    /// `IsWindowVisible` 是必要的，不是裝飾：GTK 會在對話框銷毀後短暫保留其 HWND，而驅動一個隱藏
    /// 的視窗，會讓其後每一個事件都送往無處，且什麼都不會回報。
    private func innermostModal(over window: HWND) -> HWND {
        var current = window
        for _ in 0..<8 {
            guard let popup = GetWindow(current, UINT(GW_ENABLEDPOPUP)),
                popup != current,
                IsWindowVisible(popup),
                // A dialog is SMALLER than what it covers. Added 2026-09-05,
                // after Direct Composition became GtkBackend's default: GTK then
                // gives each toplevel a `GdkWin32GL` content surface, registered
                // as that toplevel's enabled popup and exactly the same size.
                // Without this test the walk stepped off the real window onto
                // its own content surface, whose origin is (0, 0) rather than
                // the toplevel's, and every frame-relative coordinate converted
                // against the wrong origin.
                //
                // Size is the right discriminator because it is the same
                // property this function was written for: the comment above
                // records that `largestByArea` always picked the owner, BECAUSE
                // a dialog is smaller. A popup that is not smaller is not the
                // thing this walk is looking for.
                //
                // 對話框比它所覆蓋的東西**小**。此條件於 2026-09-05 新增，起因是 Direct
                // Composition 成為 GtkBackend 的預設值：此後 GTK 會為每個 toplevel 配上一個
                // `GdkWin32GL` 內容 surface，它被登記為該 toplevel 的 enabled popup，且尺寸
                // 完全相同。少了這項判斷，這趟走訪就會從真正的視窗踏上它自己的內容 surface
                // ——後者的原點是 (0, 0) 而非 toplevel 的原點——於是每一個 frame 相對座標都以
                // 錯誤的原點換算。
                //
                // 以尺寸作為判準是正確的，因為那正是本函式當初被寫出來所依據的同一項性質：
                // 上方的說明記載著 `largestByArea` 總是選中擁有者，**正因為**對話框比較小。
                // 一個不比較小的 popup，不是這趟走訪要找的東西。
                isSmaller(realWindow(behind: popup, unless: current), than: current)
            else { return current }
            current = realWindow(behind: popup, unless: current)
        }
        return current
    }

    /// A Direct Composition content surface resolved back to the window it draws
    /// for; anything else returned unchanged.
    ///
    /// **The size guard above is not enough, and this is the run that proved
    /// it.** That guard was written on 2026-09-05 for one shape: a toplevel's
    /// OWN content surface, which is exactly the same size, so `isSmaller`
    /// rejects it. It says nothing about ANOTHER window's content surface, which
    /// is smaller than the window we are standing on and sails straight through.
    ///
    /// Measured 2026-09-10 driving P50 with a popover open. Four windows exist:
    ///
    /// ```
    /// 0x1cc0650  291x221@0,0     GdkWin32GL         owner=0xbd6070a   <- the popover's surface
    /// 0xbd6070a  291x221@211,577 gdkSurfaceToplevel owner=0x1205a2    <- the popover
    /// 0x42a0842  808x933@0,0     GdkWin32GL         owner=0x1205a2    <- the main surface
    /// 0x1205a2   808x933@104,99  gdkSurfaceToplevel owner=none        <- the main window
    /// ```
    ///
    /// `GW_ENABLEDPOPUP` on the main window returns the TOPMOST enabled owned
    /// popup, which once the popover is up is `0x1cc0650` -- the popover's
    /// surface, not the popover. It is smaller than the main window, so the walk
    /// stepped onto it and the replay reported
    /// `re-measured geometry frame=(0.0, 0.0)`. Every `origin=frame` coordinate
    /// after that point was then converted against (0,0) instead of (104,99).
    ///
    /// **Nothing failed.** The replay ran on, and the visible symptom was
    /// `origin=popover, but no popover is open` several rows later -- because
    /// `popoverWindow(over:)` was then searching for popups owned by a content
    /// surface, which owns nothing. A message about popovers, produced by a
    /// z-order walk, three rows away from the cause.
    ///
    /// Resolved by ownership rather than by class name, for the reason
    /// `preferringOwners` already states: `GdkWin32GL` is this toolkit's current
    /// spelling, and a rule naming it would be a rule about a spelling. "A window
    /// owned by another window I can also see is not the one to drive" holds for
    /// content surfaces, tooltips and helper windows alike.
    ///
    /// 把一個 Direct Composition 的內容 surface 解析回它所繪製的那個視窗;其他情況原樣回傳。
    ///
    /// **上方的尺寸防護不夠,而這正是證明它不夠的那一次執行。** 該防護於 2026-09-05 為**一種**形狀
    /// 而寫:一個 toplevel **自己的**內容 surface,尺寸完全相同,因此 `isSmaller` 會擋下它。它對
    /// **別的視窗的**內容 surface 什麼都沒說,而後者比我們當下所站的視窗小,於是長驅直入。
    ///
    /// 2026-09-10 在 popover 開啟的狀態下驅動 P50 實測。當時存在四個視窗(見上方英文區塊)。
    /// 對主視窗呼叫 `GW_ENABLEDPOPUP` 回傳的是**最上層**的 enabled owned popup,而 popover 一旦升起,
    /// 那就是 `0x1cc0650`——**popover 的 surface,不是 popover**。它比主視窗小,於是走訪踏了上去,
    /// 而重放回報 `re-measured geometry frame=(0.0, 0.0)`。自該點之後,每一個 `origin=frame` 座標
    /// 都以 (0,0) 而非 (104,99) 換算。
    ///
    /// **沒有任何東西失敗。** 重放繼續進行,而看得見的症狀是好幾列之後的
    /// 「`origin=popover`,但沒有 popover 開啟」——因為 `popoverWindow(over:)` 此時是在尋找
    /// 「由一個內容 surface 所擁有的 popup」,而它什麼都不擁有。一則關於 popover 的訊息,
    /// 由一次 z 序走訪產生,距離成因三列之遙。
    ///
    /// 以**所有權**而非類別名稱解析,理由 `preferringOwners` 已經寫過:`GdkWin32GL` 是這個 toolkit
    /// 目前的拼法,而以它命名的規則會是一條關於拼法的規則。「一個被我同樣看得見的另一視窗所擁有的
    /// 視窗,不是該驅動的那一個」——這對內容 surface、tooltip 與各種輔助視窗同樣成立。
    private func realWindow(behind popup: HWND, unless current: HWND) -> HWND {
        guard let owner = GetWindow(popup, UINT(GW_OWNER)),
            owner != current,
            IsWindowVisible(owner)
        else { return popup }
        return owner
    }

    /// Whether `inner` covers strictly less area than `outer`.
    ///
    /// Returns `false` when either window cannot be measured, so an unmeasurable
    /// popup is not followed. That is the safe direction: staying on a window
    /// known to be the right size beats stepping onto one nothing is known
    /// about.
    ///
    /// `inner` 所覆蓋的面積是否嚴格小於 `outer`。
    ///
    /// 任一視窗量不到時回傳 `false`，因此量不到的 popup 不會被跟隨。那是安全的方向：留在一個
    /// 已知尺寸正確的視窗上，勝過踏上一個一無所知的視窗。
    private func isSmaller(_ inner: HWND, than outer: HWND) -> Bool {
        var innerRect = RECT()
        var outerRect = RECT()
        guard GetWindowRect(inner, &innerRect), GetWindowRect(outer, &outerRect) else {
            return false
        }
        let innerArea = Int(innerRect.right - innerRect.left) * Int(innerRect.bottom - innerRect.top)
        let outerArea = Int(outerRect.right - outerRect.left) * Int(outerRect.bottom - outerRect.top)
        return innerArea < outerArea
    }

    /// Dumps every candidate this call weighed, and which one won.
    ///
    /// Written to answer ONE question with a measurement instead of a guess: why
    /// the four apps that raise a modal dialog (P1, P5, P18, P31) cannot be
    /// driven. It answered it on the first run, and corrected two guesses that
    /// had been written down as if they were findings:
    ///
    ///   - "the click lands on a window the modal has disabled" -- FALSE. With
    ///     P1's sheet up, the owner measures `enabled=true`. GTK4 does its own
    ///     modality with a grab and does not call `EnableWindow` on Win32.
    ///   - "`GW_ENABLEDPOPUP` is ineffective here" -- FALSE, and this is the one
    ///     that cost the four apps. The owner reports
    ///     `enabledPopup=0x...26d072c`, which is exactly the sheet. The earlier
    ///     attempt was removed for being ineffective without this dump to say
    ///     whether the call had answered; it had.
    ///
    /// What is actually wrong is the GEOMETRY, and largest-area is why: the sheet
    /// measures 428x174 against the owner's 648x549, so the owner wins, and every
    /// `origin=frame` coordinate is then resolved against the owner's frame at
    /// (78,78) instead of the sheet's at (188,265). The click is placed on the
    /// owner, where GTK's grab discards it, and the app looks like it ignored the
    /// input.
    ///
    /// Kept after the fix, not deleted with it: it is what distinguishes "the
    /// popup was not found" from "the popup was found and the click still missed"
    /// the next time, and those two need opposite investigations.
    ///
    /// Behind `--debug` because `ownWindow` runs per event, and
    /// `ActionFileReplay.report` says a per-event line belongs behind the flag.
    ///
    /// 傾印本次呼叫權衡過的每一個候選視窗，以及勝出者。
    ///
    /// 寫它是為了用**量測**而非猜測回答**一個**問題：那四支會開啟 modal dialog 的 app
    /// （P1、P5、P18、P31）為何無法被驅動。它在第一次執行就給出了答案，並且更正了兩個「被當成發現
    /// 寫下來」的猜測：
    ///
    ///   - 「點擊落在一個已被 modal 停用的視窗上」——**假**。P1 的 sheet 開啟時，其擁有者實測為
    ///     `enabled=true`。GTK4 以自己的 grab 處理 modality，並不會在 Win32 上呼叫
    ///     `EnableWindow`。
    ///   - 「`GW_ENABLEDPOPUP` 在此無效」——**假**，而這一項正是那四支 app 的代價所在。擁有者
    ///     回報 `enabledPopup=0x...26d072c`，那正是該 sheet。先前那次嘗試在沒有這份傾印可以判斷
    ///     「該呼叫究竟有沒有回答」的情況下，就以無效為由被移除；它其實回答了。
    ///
    /// 真正錯的是**幾何**，而「取最大面積」正是原因：sheet 為 428x174，擁有者為 648x549，於是
    /// 擁有者勝出，接著每一個 `origin=frame` 座標都改以擁有者位於 (78,78) 的框架、而非 sheet 位於
    /// (188,265) 的框架來解析。點擊被放在擁有者身上，被 GTK 的 grab 丟棄，而 app 看起來就像忽略了
    /// 那個輸入。
    ///
    /// 修好之後保留，而非隨修正一併刪除：下一次它是用來分辨「popup 沒被找到」與「popup 找到了但
    /// 點擊仍然落空」的東西，而這兩者需要的是相反方向的追查。
    ///
    /// 放在 `--debug` 之後，因為 `ownWindow` 是逐事件執行的，而 `ActionFileReplay.report`
    /// 已載明逐事件的輸出應置於該旗標之後。
    private func reportWindowChoice(candidates: [HWND], chosen: HWND) {
        guard CommandLine.arguments.contains("-actionfile"),
            CommandLine.arguments.contains("--debug")
        else { return }

        for window in candidates {
            var rect = RECT()
            let haveRect = GetWindowRect(window, &rect)
            let size =
                haveRect
                ? "\(rect.right - rect.left)x\(rect.bottom - rect.top)"
                    + "@\(rect.left),\(rect.top)"
                : "rect-unavailable"
            // GW_OWNER is the window this one is owned by; GW_ENABLEDPOPUP is the
            // enabled popup it owns, which is the modal when there is one. Both
            // return nil far more often than not, and that is a result.
            // GW_OWNER 是「本視窗被誰擁有」，GW_ENABLEDPOPUP 是「本視窗擁有的、處於啟用狀態的
            // popup」——若存在 modal，那就是它。兩者回傳 nil 的情況遠多於不是，而那也是一項結果。
            let owner = GetWindow(window, UINT(GW_OWNER))
            let popup = GetWindow(window, UINT(GW_ENABLEDPOPUP))
            ActionFileReplay.report(
                "window \(String(describing: window)) \(size) "
                    + "class=\(className(of: window)) "
                    + "enabled=\(IsWindowEnabled(window)) "
                    + "owner=\(owner.map { String(describing: $0) } ?? "none") "
                    + "enabledPopup=\(popup.map { String(describing: $0) } ?? "none") "
                    + "\(window == chosen ? "<- CHOSEN" : "")"
            )
        }
    }

    /// The window class, which names what a window IS where the title does not.
    /// A GTK modal and its owner can carry the same title, so the class is what
    /// tells them apart in the dump above.
    /// 視窗類別；在標題無法辨別時，它說明一個視窗**是什麼**。GTK 的 modal 與其擁有者可能帶有相同
    /// 的標題，因此在上面的傾印中，是類別把兩者區分開來。
    private func className(of window: HWND) -> String {
        var buffer = [WCHAR](repeating: 0, count: 256)
        let length = GetClassNameW(window, &buffer, Int32(buffer.count))
        guard length > 0 else { return "unavailable(\(GetLastError()))" }
        return String(decoding: buffer[0..<Int(length)], as: UTF16.self)
    }

    /// The window's title bar text, which is what a `focus` row names.
    ///
    /// Empty string on failure rather than an optional, because the only caller
    /// compares it and lists it, and an empty title is already a possible real
    /// answer -- GTK gives its Direct Composition content surface no title at
    /// all. Nothing here can distinguish "no title" from "could not read the
    /// title", and pretending otherwise would be the more misleading of the two.
    ///
    /// 視窗標題列的文字,也就是一列 `focus` 所指名的東西。
    ///
    /// 失敗時回傳空字串而非 optional,因為唯一的呼叫端只是拿它比對與列出,而「空標題」本來就是一個
    /// 可能的真實答案——GTK 給它的 Direct Composition 內容 surface 根本沒有標題。此處沒有任何東西
    /// 能區分「沒有標題」與「讀不到標題」,而假裝可以區分,才是兩者中更誤導人的那個。
    private func windowTitle(of window: HWND) -> String {
        var buffer = [WCHAR](repeating: 0, count: 512)
        let length = GetWindowTextW(window, &buffer, Int32(buffer.count))
        guard length > 0 else { return "" }
        return String(decoding: buffer[0..<Int(length)], as: UTF16.self)
    }

    /// Brings this process's window with that exact title to the front, and makes
    /// every later coordinate resolve against it.
    ///
    /// **Two halves, and the second is the one that is easy to omit.** Raising
    /// the window is the visible part; making `ownWindow()` -- and therefore
    /// `currentWindowGeometry()` and `currentWindowIdentity()` -- agree that this
    /// is now the window under test is what makes the rows after a `focus` mean
    /// anything. Without it the focus succeeds, the replay reports every action
    /// done, and each coordinate is still converted against the frame of the
    /// window that was in front when the replay began.
    ///
    /// That is not a hypothetical: it is exactly what `a8627210` measured on
    /// macOS, where `currentWindowIdentity()` returned the protocol default of 0
    /// and the `+1` inside a settings window was posted into the main window's
    /// frame. The Windows shape of the same defect is different and would not
    /// have been fixed by the same change: this file DOES override
    /// `currentWindowIdentity()`, but it answers with `ownWindow()`, which picks
    /// the LARGEST window by area. A settings window is smaller than the main
    /// one, so identity would have kept reporting the main window, replay would
    /// have seen no change, and no geometry would have been re-measured.
    ///
    /// **Exact match, visible windows, this process only.** A prefix match in an
    /// app whose windows share a prefix selects the wrong one silently, which is
    /// the failure the verb exists to remove. The error names every visible title
    /// so a mismatch is one line to diagnose rather than a guess.
    ///
    /// **Throws when the foreground does not arrive**, and does not merely
    /// report. `SetForegroundWindow` returning unchecked is defect #46 in this
    /// project -- two runs drove the editor covering the app and both reported
    /// success. Here the consequence is worse than a wrong click: a `focus` that
    /// quietly did nothing leaves the file clicking real controls in the wrong
    /// window, and the capture then looks like a test that simply failed.
    ///
    /// 把本行程中標題**完全相符**的視窗帶到前景,並讓其後每一個座標都相對於它解析。
    ///
    /// **兩個部分,而第二個才是容易漏掉的那個。** 把視窗抬到前面是看得見的部分;讓 `ownWindow()`
    /// ——連帶 `currentWindowGeometry()` 與 `currentWindowIdentity()`——同意「現在受測的是這個視窗」,
    /// 才是讓 `focus` 之後那些列具有意義的東西。少了它,focus 會成功、重放會回報每個動作都完成,
    /// 而每一個座標仍然是相對於「重放開始時位於前景的那個視窗」的框架換算的。
    ///
    /// 這不是假設:那正是 `a8627210` 在 macOS 上實測到的情形——`currentWindowIdentity()` 回傳協定
    /// 預設值 0,而設定視窗裡的 `+1` 被投遞到了主視窗的框中。同一個缺陷在 Windows 上的形狀不同,
    /// 而且不會被同一項修改治好:本檔**確實**覆寫了 `currentWindowIdentity()`,但它是以
    /// `ownWindow()` 作答的,而後者挑的是**面積最大**的視窗。設定視窗比主視窗小,因此 identity 會
    /// 持續回報主視窗、replay 看不到任何變化,也就不會重新量測任何幾何。
    ///
    /// **完全相符、僅限可見、僅限本行程。** 在視窗共用前綴的 app 中,前綴比對會靜默地選錯一個,
    /// 而那正是這個動詞存在所要消除的失敗。錯誤訊息會列出每一個可見的標題,使一次不相符只需一行
    /// 就能診斷,而不是靠猜。
    ///
    /// **前景沒有到手時丟出錯誤**,而不只是回報。在本專案中,`SetForegroundWindow` 未經檢查就返回
    /// 正是缺陷 #46——兩次執行都驅動了覆蓋在 app 之上的編輯器,而兩次都回報成功。此處的後果比
    /// 「點錯位置」更糟:一個安靜地什麼都沒做的 `focus`,會讓該檔案在**錯誤的視窗**中點到真實的
    /// 控制項,而擷圖看起來就只像是一個失敗的測試。
    public func focusWindow(titled title: String) throws {
        let candidates = visibleWindows()
        guard let window = candidates.first(where: { windowTitle(of: $0) == title }) else {
            throw SynthesiserError.unsupported(
                "focus '\(title)': no visible window of this process has that exact title; "
                    + "visible titles are "
                    + candidates.map { "'\(windowTitle(of: $0))'" }.joined(separator: ", ")
            )
        }

        if IsIconic(window) {
            ShowWindow(window, SW_RESTORE)
        }

        // The same raise `prepareForReplay` uses, and for the same reason: a
        // process that is not already in front cannot simply ask for the
        // foreground, but any process may raise its own window, and
        // SWP_NOACTIVATE means this does not even ask.
        // 與 `prepareForReplay` 相同的抬升方式,理由也相同:一個原本不在前景的行程無法直接要求前景,
        // 但任何行程都可以抬升自己的視窗,而 SWP_NOACTIVATE 意味著這裡連要求都沒有提出。
        guard
            SetWindowPos(
                window, HWND(bitPattern: -1), 0, 0, 0, 0,
                UINT(SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE)
            )
        else {
            throw SynthesiserError.toolFailed(
                "SetWindowPos(HWND_TOPMOST) for focus '\(title)'", status: Int32(GetLastError())
            )
        }

        SetForegroundWindow(window)
        BringWindowToTop(window)

        // Asynchronous, so read it back rather than assume. Half a second is far
        // longer than the switch takes whenever it happens at all -- the same
        // budget and the same loop as `prepareForReplay`.
        // 這是非同步的,因此要讀回而不是假設。半秒遠長於這個切換在任何能夠成功的情況下所需的時間
        // ——與 `prepareForReplay` 相同的預算與相同的迴圈。
        var tookForeground = false
        for _ in 0..<50 {
            if GetForegroundWindow() == window {
                tookForeground = true
                break
            }
            Thread.sleep(forTimeInterval: 0.01)
        }

        guard tookForeground else {
            // Read once. Two calls can disagree, and an error message whose
            // handle and class name come from different instants describes a
            // state that never existed.
            // 只讀一次。兩次呼叫可能給出不同答案,而一則「handle 與 class 名稱取自不同瞬間」的
            // 錯誤訊息,描述的是一個從未存在過的狀態。
            let blocker = GetForegroundWindow()
            throw SynthesiserError.unsupported(
                "focus '\(title)': the window was raised but never took the foreground; "
                    + "the foreground is \(blocker.map { String(describing: $0) } ?? "none") "
                    + "class=\(blocker.map { className(of: $0) } ?? "none"). "
                    + "Every coordinate after this row would have resolved against the "
                    + "previous window, so the replay stops here rather than clicking "
                    + "real controls in the wrong window"
            )
        }

        Self.rememberFocus(window)
        ActionFileReplay.report(
            "focus '\(title)': window \(window) is now the foreground and the window "
                + "geometry will be re-measured against it"
        )
    }

    /// The window a `focus` row named, as a bit pattern, or 0 when no row has.
    ///
    /// Static and `nonisolated(unsafe)` for the same reason as `didHideConsole`
    /// above: one replay per process, and this is the idiom the module already
    /// uses for exactly that. Stored as an `Int` rather than an `HWND` so the
    /// type stays `Sendable` -- the class conforms without `@unchecked`, and a
    /// raw pointer in it would end that.
    ///
    /// 一列 `focus` 所指名的視窗,以 bit pattern 表示;沒有任何一列指名過時為 0。
    ///
    /// 使用 static 與 `nonisolated(unsafe)`,理由與上方的 `didHideConsole` 相同:每個行程只有一次
    /// 重放,而這正是本 module 對這種情況既有的寫法。存成 `Int` 而非 `HWND`,是為了讓型別維持
    /// `Sendable`——本類別的 conformance 沒有用 `@unchecked`,而在其中放一個 raw pointer 會終結它。
    nonisolated(unsafe) private static var focusedWindowBits = 0
    private static let focusLock = NSLock()

    private static func rememberFocus(_ window: HWND) {
        focusLock.lock()
        defer { focusLock.unlock() }
        focusedWindowBits = Int(bitPattern: window)
    }

    /// Cleared at the start of every replay, so a focus cannot outlive the file
    /// that asked for it. Two replays in one process would otherwise have the
    /// second start pointed at the first one's window.
    /// 在每次重放開始時清除,使一次 focus 無法活得比要求它的那個檔案更久。否則同一行程中的兩次重放,
    /// 第二次會從「指向第一次那個視窗」的狀態開始。
    private static func forgetFocus() {
        focusLock.lock()
        defer { focusLock.unlock() }
        focusedWindowBits = 0
    }

    private static func rememberedFocus() -> HWND? {
        focusLock.lock()
        defer { focusLock.unlock() }
        return HWND(bitPattern: focusedWindowBits)
    }

    private func move(to point: Point, in geometry: WindowGeometry) throws {
        let position = try geometry.screenPosition(of: point)

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
        // After the report, so the failing move is in the log with its full hit
        // dump rather than only in the exception. The two are read together.
        // 放在回報之後,使那次失敗的移動連同完整的 hit 傾印一起留在 log 中,而不是只存在於例外裡。
        // 兩者是一起讀的。
        try assertPointIsOurs(point: point, screen: position)
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

        // Who will actually RECEIVE the click about to be sent, which is a
        // different question from where the cursor is and is the one that goes
        // unanswered when a press lands on nothing.
        //
        // `WindowFromPoint` is the decisive one: `SendInput` posts a button
        // event with no target, so whatever this returns is what gets it. It
        // walks down to the deepest child, so a value that is not any of the
        // top-levels in the dump above is normal -- what matters is whether its
        // root is ours. `GetForegroundWindow` and `GetActiveWindow` are printed
        // beside it because "foreground" and "active" are not the same state and
        // a click can be eaten by a mismatch between them.
        //
        // Added 2026-09-04 for the one thing the candidate dump could not
        // explain: P1's FIRST synthesised click does nothing (0/3), while the
        // same click repeated works (3/3) and a `move` first does not help
        // (0/3). Everything already printed looked correct on the failing runs,
        // which is exactly when a new fact is needed rather than more thought.
        //
        // 即將送出的那個點擊，究竟會由**誰**收到——這與「游標在哪裡」是不同的問題，也正是
        // 「一次按壓落在虛無中」時無人回答的那個問題。
        //
        // `WindowFromPoint` 是決定性的一項：`SendInput` 送出的按鍵事件不帶目標，因此它回傳
        // 什麼，就由什麼收下。它會一路下探到最深層的子視窗，所以回傳值不在上面那份 top-level
        // 清單中是正常的——真正要看的是它的 root 是不是我們的。`GetForegroundWindow` 與
        // `GetActiveWindow` 並列印出，是因為「前景」與「作用中」並非同一個狀態，而一次點擊
        // 可能正是被兩者之間的不一致吃掉的。
        //
        // 2026-09-04 新增，為的是候選傾印無法解釋的那一件事：P1 的**第一次**合成點擊毫無作用
        // （0/3），而同一個點擊重複一次就成功（3/3），先 `move` 則沒有幫助（0/3）。在失敗的那些
        // 執行中，已經印出的每一項看起來都是正確的——而那正是需要一個**新事實**、而非更多推理的
        // 時候。
        let target = WindowFromPoint(POINT(x: Int32(screen.x), y: Int32(screen.y)))
        let root = target.map { GetAncestor($0, UINT(GA_ROOT)) } ?? nil
        let foreground = GetForegroundWindow()
        let active = GetActiveWindow()

        // Through the one writer, rather than a second copy of it. Both copies
        // carried the same truncate-on-failure bug; one of them was fixed and
        // the other would not have been.
        // 走同一個寫入器，而非它的第二份副本。兩份副本帶著同一個「失敗即清空」的缺陷，
        // 修好其中一份時，另一份不會跟著被修。
        ActionFileReplay.report(
            "move \(point.origin.rawValue)=(\(point.x), \(point.y)) "
                + "screen=(\(screen.x), \(screen.y)) \(cursorDescription) "
                + "hitTarget=\(target.map { String(describing: $0) } ?? "none") "
                + "hitRoot=\(root.map { String(describing: $0) } ?? "none") "
                + "hitClass=\(target.map { className(of: $0) } ?? "none") "
                + "foreground=\(foreground.map { String(describing: $0) } ?? "none") "
                + "active=\(active.map { String(describing: $0) } ?? "none")"
        )
    }

    /// Stops the replay when the point about to be clicked belongs to another
    /// process.
    ///
    /// Added 2026-09-10, and it enforces something this file has printed for six
    /// days without acting on.
    ///
    /// `hitClass` has been in the move dump since 2026-09-04. On 2026-09-10 two
    /// consecutive runs of P50's popover sweep printed
    /// `hitClass=Chrome_RenderWidgetHostHWND`, which says in as many words that
    /// the click about to be sent would land in a browser -- and the replay
    /// carried on, clicked into Chrome, and then failed several rows later with
    /// "origin=popover, but no popover is open". That message is true and
    /// completely misleading: the popover is not open BECAUSE the click that
    /// would have opened it went to another application. It was read as a
    /// popover defect first.
    ///
    /// This is defect #46's shape one layer up. #46 was `SetForegroundWindow`
    /// unchecked -- asking and not looking. Here the looking was done, printed,
    /// and then not acted on, which is worse: the evidence was in the log the
    /// whole time.
    ///
    /// **Separate from `reportMouseMove`, and that is the point.** The reporter
    /// returns early unless `--debug` was passed, so a check living inside it
    /// would protect exactly the runs that are already being watched and none of
    /// the rest. This runs on every move.
    ///
    /// A throw, not a warning, because the module's rule is that a missed target
    /// and a swallowed event must not look alike -- and because a warning leaves
    /// the run clicking real controls in someone else's window, which is a real
    /// thing happening to the user's desktop as well as a wrong test result.
    ///
    /// 當即將被點擊的那個點屬於**另一個行程**時中止重放。
    ///
    /// 2026-09-10 加入,而它所執行的正是本檔已經印了六天、卻從未據以行動的那件事。
    ///
    /// `hitClass` 自 2026-09-04 起就在移動傾印中。2026-09-10,P50 popover 掃描連續兩次執行都印出
    /// `hitClass=Chrome_RenderWidgetHostHWND`——那已經明說「即將送出的這次點擊會落在一個瀏覽器
    /// 裡」——而重放繼續進行、點進了 Chrome,然後在好幾列之後以「origin=popover,但沒有 popover
    /// 開啟」失敗。那個訊息**是真的,而且極度誤導**:popover 沒有開啟,正是**因為**那個本該開啟它
    /// 的點擊跑到別的應用程式去了。它一開始確實被讀成了 popover 的缺陷。
    ///
    /// 這是缺陷 #46 的形狀高了一層。#46 是 `SetForegroundWindow` 未經檢查——問了卻不看。此處是
    /// **看了、印了,然後沒有據以行動**,而那更糟:證據一直都在 log 裡。
    ///
    /// **與 `reportMouseMove` 分開,而這正是重點。** 該回報函式在未傳入 `--debug` 時會提早返回,
    /// 因此把檢查放在它裡面,保護到的恰好是「已經有人在盯著」的那些執行,其餘一個都保護不到。
    /// 本函式在每一次移動都會執行。
    ///
    /// 用丟出錯誤而非警告,因為本模組的規則是「沒打中的目標與被吞掉的事件不可以長得一樣」——也因為
    /// 警告會讓這次執行繼續在別人的視窗中點到真實的控制項,那既是錯誤的測試結果,也是真的發生在
    /// 使用者桌面上的事。
    private func assertPointIsOurs(point: Point, screen: (x: Int, y: Int)) throws {
        guard let target = WindowFromPoint(POINT(x: Int32(screen.x), y: Int32(screen.y)))
        else { return }

        var targetProcess: DWORD = 0
        GetWindowThreadProcessId(target, &targetProcess)
        guard targetProcess != GetCurrentProcessId() else { return }

        throw SynthesiserError.unsupported(
            "the point \(point.origin.rawValue)=(\(point.x), \(point.y)) -> screen "
                + "(\(screen.x), \(screen.y)) is covered by another application: "
                + "class=\(className(of: target)) process=\(targetProcess), ours is "
                + "\(GetCurrentProcessId()). The click would have gone there, not to the "
                + "window under test, so the replay stops instead of driving someone else's "
                + "application. The topmost pin was applied and did not win, which means "
                + "another window is also topmost -- a full-screen browser or video is the "
                + "usual cause. Close or un-fullscreen it and run again."
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

    /// Whether any modifier is down RIGHT NOW, asked of Windows rather than
    /// tracked here.
    ///
    /// Tracking was the first attempt and the compiler refused it:
    /// `Win32Synthesiser` is `Sendable`, so a mutable stored property is an
    /// error, and `perform(_:in:)` is called once per action with no loop of its
    /// own to hold the state in. Asking is better anyway. An action file spells
    /// a shortcut as a SEQUENCE -- `keydown,control`, `key,q`, `keyup,control` --
    /// so a tracked set would only know about modifiers this synthesiser itself
    /// sent, and would be wrong about one the operator was physically holding.
    /// `GetKeyState`'s high bit is the actual state of the key.
    ///
    /// Shift counts. `shift` + `a` must produce `A`, and only the virtual-key
    /// path applies the keyboard layout; the Unicode path would send a bare `a`.
    ///
    /// 是否**此刻**有任何修飾鍵按著——向 Windows 詢問，而非在此追蹤。
    ///
    /// 追蹤是第一次的做法，而編譯器拒絕了它：`Win32Synthesiser` 是 `Sendable`，因此可變的儲存屬性是錯誤；
    /// 而 `perform(_:in:)` 每個動作被呼叫一次，本身沒有可容納該狀態的迴圈。何況「詢問」本來就更好。動作檔
    /// 是以**序列**拼出快捷鍵的——`keydown,control`、`key,q`、`keyup,control`——因此一份被追蹤的集合只會
    /// 知道本合成器自己送出的修飾鍵，對於操作者實體按著的那一個則會判斷錯誤。`GetKeyState` 的最高位元
    /// 就是該鍵的真實狀態。
    ///
    /// Shift 也算在內。`shift` + `a` 必須產生 `A`，而只有 virtual-key 路徑會套用鍵盤配置；Unicode 路徑
    /// 送出的會是一個單純的 `a`。
    private static var anyModifierHeld: Bool {
        for vk in [VK_CONTROL, VK_MENU, VK_SHIFT, VK_LWIN, VK_RWIN] {
            if GetKeyState(Int32(vk)) & Int16(bitPattern: 0x8000) != 0 { return true }
        }
        return false
    }

    private func send(key: Key, up: Bool) throws {
        if !Self.anyModifierHeld, let scalar = Self.printableScalar(for: key) {
            try sendUnicode(scalar, up: up)
            return
        }

        guard let code = Self.virtualKey(for: key) else {
            throw SynthesiserError.unsupported("key '\(key.rawValue)' on Windows")
        }
        var input = INPUT()
        input.type = DWORD(INPUT_KEYBOARD)
        input.ki.wVk = WORD(code)

        // The scan code is filled in because a keyboard message should carry
        // one -- NOT because it fixed anything here. Read the next paragraph
        // before citing this line as a cause.
        //
        // MEASURED 2026-09-09, AND THE HYPOTHESIS WAS WRONG. `wScan` was 0
        // before this, and the theory was that GDK's Win32 backend derives the
        // character from the scan code and keyboard state rather than from the
        // virtual key, so a zero scan code would translate to the wrong letter.
        // P36 was built with the fix and re-driven: the result did not change
        // at all. Typing `a` then `b` into the focused GtkEntry still produces
        // exactly ONE glyph, still not a letter, and the four sibling fields
        // bound to the same `@State` still show their placeholders. Whatever is
        // wrong with #116, this is not it.
        //
        // Kept rather than reverted: sending wVk without wScan is wrong on its
        // own terms, and reverting would leave a second defect in place for the
        // next person to find. Kept ANNOTATED rather than silent, because a
        // plausible fix with no note attached is exactly what gets cited later
        // as the explanation.
        //
        // MAPVK_VK_TO_VSC is 0, spelled out rather than passed as a literal.
        //
        // 此處填入 scan code，是因為一則鍵盤訊息本來就該攜帶它——**而不是**因為它修好了什麼。在把這一行
        // 當成原因引用之前，請先讀下一段。
        //
        // 2026-09-09 實測，而該假設是錯的。此改動之前 `wScan` 為 0，當時的理論是：GDK 的 Win32 後端由
        // scan code 與鍵盤狀態（而非只由 virtual key）推導字元，因此 scan code 為零會被翻譯成錯的字母。
        // P36 帶著這個修正重新建置並重跑：**結果完全沒有變化**。對取得焦點的 GtkEntry 輸入 `a` 再 `b`，
        // 仍然只產生**一個**字符、仍然不是字母，而綁定同一個 `@State` 的另外四個欄位仍顯示 placeholder。
        // #116 的問題不論是什麼，都不是這裡。
        //
        // 保留而不還原：只送 wVk 而不送 wScan 本身就是錯的，還原只會把第二個缺陷留給下一個人發現。
        // 保留但**加註**而非默默留著，因為「一個看起來合理、卻沒有附註的修正」正是日後會被拿來當成解釋的東西。
        //
        // MAPVK_VK_TO_VSC 的值為 0，此處寫出名稱而非直接傳字面值。
        let mapVKToVSC: UINT = 0  // MAPVK_VK_TO_VSC
        input.ki.wScan = WORD(MapVirtualKeyW(UINT(code), mapVKToVSC))

        input.ki.dwFlags = up ? DWORD(KEYEVENTF_KEYUP) : 0
        try dispatch(&input)
    }

    /// The character a key types when nothing is held, or nil if it is not a
    /// typing key.
    ///
    /// ``Key`` is a `String`-backed enum whose letter and digit cases have
    /// single-character raw values -- `a`, `b`, `0`, `1` -- while every other
    /// case spells a name: `escape`, `leftArrow`, `keypadPlus`. Length one is
    /// therefore the whole test, and `space` is added explicitly because its raw
    /// value is the word rather than a blank.
    ///
    /// 當沒有任何修飾鍵按著時，該鍵所輸入的字元；若它不是輸入字元用的鍵，則為 nil。
    ///
    /// ``Key`` 是以 `String` 支撐的 enum，其字母與數字的 case 具有單一字元的 raw value——`a`、`b`、
    /// `0`、`1`——而其餘每一個 case 拼的都是名稱：`escape`、`leftArrow`、`keypadPlus`。因此「長度為一」
    /// 就是完整的判準；`space` 另外明列，因為它的 raw value 是那個單字而非一個空白。
    private static func printableScalar(for key: Key) -> UInt16? {
        if key == .space { return 0x20 }
        let raw = key.rawValue
        guard raw.count == 1, let scalar = raw.unicodeScalars.first, scalar.value < 0x10000 else {
            return nil
        }
        return UInt16(scalar.value)
    }

    /// Types a character with `KEYEVENTF_UNICODE`, bypassing the keyboard layout
    /// and the input method entirely.
    ///
    /// **WHY THIS PATH EXISTS.** Measured 2026-09-09 on P36/Win-gtk4. Sending
    /// `a` then `b` as virtual keys put ONE non-letter glyph in a focused
    /// GtkEntry, displacing its placeholder, while the entry's `changed` signal
    /// was never emitted -- instrumented, `registerSignals` connected it 6 times
    /// and the handler was entered 0 times, against a positive control that
    /// fired 18. A GtkEntry emits `changed` whenever its BUFFER changes, so
    /// something that displaces the placeholder without emitting it is not
    /// buffer text: it is IME preedit. Raw virtual keys leave GTK's input method
    /// composing, and composition never commits.
    ///
    /// `KEYEVENTF_UNICODE` delivers the character itself rather than a key to be
    /// translated, so there is nothing for an input method to compose.
    /// `wVk` MUST be 0 -- Windows ignores the scan code as a character otherwise.
    ///
    /// Only reached when no modifier is held. A shortcut still needs a real
    /// virtual key, because a Unicode event carries no modifier state and
    /// Ctrl+Q sent this way is just `q`.
    ///
    /// **此路徑存在的理由。** 2026-09-09 於 P36／Win-gtk4 實測。以 virtual key 送出 `a` 再送 `b`，在取得
    /// 焦點的 GtkEntry 中放進了**一個**非字母字符、蓋掉了它的 placeholder，而該 entry 的 `changed` 訊號
    /// 從未發出——插上儀器後，`registerSignals` 連接了 6 次、handler 被進入 0 次，而正對照觸發了 18 次。
    /// GtkEntry 只要 **buffer** 改變就會發出 `changed`，因此「蓋掉 placeholder 卻不發出該訊號」的東西
    /// 就不是 buffer 文字：它是 IME 的 preedit。原始 virtual key 會讓 GTK 的輸入法停在組字狀態，而組字
    /// 從未被 commit。
    ///
    /// `KEYEVENTF_UNICODE` 送的是字元本身，而非一個待翻譯的按鍵，因此沒有東西可供輸入法組字。
    /// `wVk` **必須**為 0——否則 Windows 不會把 scan code 當作字元看待。
    ///
    /// 僅在沒有任何修飾鍵按著時才會走到。快捷鍵仍需真正的 virtual key，因為 Unicode 事件不攜帶修飾鍵
    /// 狀態，以此方式送出的 Ctrl+Q 就只是一個 `q`。
    private func sendUnicode(_ scalar: UInt16, up: Bool) throws {
        var input = INPUT()
        input.type = DWORD(INPUT_KEYBOARD)
        input.ki.wVk = 0
        input.ki.wScan = scalar
        input.ki.dwFlags = DWORD(KEYEVENTF_UNICODE) | (up ? DWORD(KEYEVENTF_KEYUP) : 0)
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
