#if os(macOS)

    import AppKit
    import Carbon.HIToolbox
    import Foundation

    /// Posts events into this process's own event queue, through `NSApp.postEvent`.
    ///
    /// The other two synthesisers are system-wide: `SendInput` posts to the
    /// foreground window and XTEST to the X server's focus, so both drive whatever
    /// happens to be in front. macOS has the same shape available -- `CGEvent.post`
    /// -- and it is deliberately not used.
    ///
    /// Measured on macOS 27 with the terminal untrusted, which is the state a
    /// developer's machine is in until somebody clicks in System Settings:
    ///
    ///   AXIsProcessTrusted()                     false
    ///   CGEvent.post(tap: .cghidEventTap)        0 events delivered
    ///   CGEvent.postToPid(getpid())              0 events delivered
    ///   NSApp.postEvent(_:atStart:)              delivered; NSButton fired,
    ///                                            NSTextField received the key
    ///
    /// **Re-measured 2026-09-10 with the terminal TRUSTED, because the line above
    /// was being read as "CGEvent does not work on macOS".** It does. With
    /// `AXIsProcessTrusted() == true`, `CGEvent.post(tap: .cghidEventTap)` is
    /// delivered: an `NSButton` fired 23.8 ms after the post, and P28's own button
    /// answered 16 ms after a cold post and 2.9-9.9 ms once warm. So the zero above
    /// is a statement about the PERMISSION, not about the API, and the path P28
    /// still needed -- a real event through the full queue -- is reachable from a
    /// machine where somebody has clicked in System Settings. See
    /// `testapp/test_support/measure/real_mouse_latency.swift`.
    ///
    /// None of that changes what this file does. The default has to work on a
    /// machine where nobody has clicked anything.
    ///
    /// **2026-09-10 在終端機**已被授權**的狀態下重新量測，因為上面那一行正被讀成「CGEvent 在 macOS
    /// 上行不通」。** 它行得通。在 `AXIsProcessTrusted() == true` 之下，
    /// `CGEvent.post(tap: .cghidEventTap)` 會送達：一顆 `NSButton` 在 post 後 23.8 毫秒觸發，而 P28
    /// 自己的按鈕在冷啟後的第一次為 16 毫秒、預熱後為 2.9 至 9.9 毫秒。因此上面那個 0 講的是**權限**，
    /// 不是那個 API；而 P28 仍然需要的那條路徑——一個走完整佇列的真實事件——在「有人到系統設定裡按過」
    /// 的機器上是到得了的。見 `testapp/test_support/measure/real_mouse_latency.swift`。
    ///
    /// 這一切都不改變本檔案的作為。預設路徑必須在「沒有人按過任何東西」的機器上也能運作。
    ///
    /// The first two fail *silently* -- no error, no diagnostic, an app that looks
    /// as though it ignored its input. That is the worst failure this module can
    /// have, and it is the one `-actionfile` exists to avoid. So this path posts
    /// in-process, needs no Accessibility grant, and cannot be defeated by the app
    /// not being frontmost.
    ///
    /// Two consequences follow, and both are improvements rather than compromises.
    /// Events are addressed to a window by number, so a replay cannot leak into
    /// another application the way an early replay does elsewhere. And because
    /// AppKit reads modifier state from the event rather than from the hardware,
    /// the modifiers a file holds down are tracked here (see ``heldModifiers``)
    /// instead of being left to the system.
    ///
    /// 將事件投遞至本行程自身的事件佇列，透過 `NSApp.postEvent`。
    ///
    /// 另外兩個 synthesiser 都是系統層級的：`SendInput` 投遞至前景視窗，XTEST 投遞至 X server 的
    /// 焦點，因此兩者驅動的都是「當下位於前方的任何東西」。macOS 也有同樣形狀的機制——`CGEvent.post`
    /// ——而此處刻意不使用它。
    ///
    /// 在 macOS 27 上實測，終端機未被授予信任（在有人前往「系統設定」點擊之前，開發機器都處於此
    /// 狀態）：上表所列，前兩者投遞出 0 個事件，第三者成功——NSButton 被觸發、NSTextField 收到按鍵。
    ///
    /// 前兩者是**靜默**失敗——沒有錯誤、沒有診斷訊息，只留下一個看似忽略了輸入的應用程式。那是本模組
    /// 所能發生的最糟糕的失敗，也正是 `-actionfile` 存在所要避免的。因此此路徑於行程內投遞，不需要
    /// 輔助使用權限，也不會因應用程式未在前景而失效。
    ///
    /// 由此帶來兩項後果，且兩者都是改進而非妥協。事件依視窗編號定址，因此重放不會像在其他平台上「太早
    /// 開始」那樣外洩至別的應用程式。而由於 AppKit 是從事件本身而非硬體讀取修飾鍵狀態，動作檔按住的
    /// 修飾鍵在此處追蹤（見 ``heldModifiers``），而不交由系統處理。
    public final class AppKitSynthesiser: Synthesiser, @unchecked Sendable {
        /// Modifiers the file is currently holding down.
        ///
        /// Needed because nothing else tracks them. `SendInput` and XTEST post real
        /// key events and the system maintains the modifier state that later events
        /// inherit; a posted `NSEvent` carries its own `modifierFlags` and inherits
        /// nothing, so `keyDown(shift)` followed by `key(a)` would produce a plain
        /// "a" unless the flag is remembered and applied here.
        ///
        /// Guarded by a lock because `Synthesiser` is `Sendable` and a replay runs
        /// off the main thread.
        ///
        /// 之所以需要，是因為沒有別的東西在追蹤它們。`SendInput` 與 XTEST 投遞的是真實按鍵事件，由
        /// 系統維護修飾鍵狀態供後續事件繼承；而被 post 的 `NSEvent` 自帶 `modifierFlags` 且不繼承
        /// 任何狀態，因此若不在此記住並套用該旗標，`keyDown(shift)` 之後的 `key(a)` 只會產生一個普通的
        /// 「a」。
        ///
        /// 以鎖保護，因為 `Synthesiser` 是 `Sendable`，且重放在非主執行緒上執行。
        private let lock = NSLock()
        private var heldModifiers: NSEvent.ModifierFlags = []

        /// Where the file has moved the pointer to, in window coordinates.
        ///
        /// Tracked because nothing else does. `SendInput` and XTEST move the real
        /// cursor, so "where the pointer is" is a question the system can answer;
        /// posting an `NSEvent` moves nothing, so a `click` with no position of its
        /// own would fall back to wherever the user physically left the mouse --
        /// which is not where the file's last `move` put it, and is a click landing
        /// somewhere the file never named.
        ///
        /// `nil` until the file moves or clicks somewhere, which is the only point
        /// at which the real cursor is the honest answer.
        ///
        /// 之所以追蹤，是因為沒有別的東西在做這件事。`SendInput` 與 XTEST 會移動真實游標，因此「指標
        /// 在哪裡」是系統回答得出的問題；而 post 一個 `NSEvent` 不會移動任何東西，於是自身不帶座標的
        /// `click` 會退回到使用者實際把滑鼠留在的位置——那並非檔案上一次 `move` 所指之處，而是一次落在
        /// 檔案從未指名之處的點擊。
        ///
        /// 在檔案首次移動或點擊之前為 `nil`，而那也是「以真實游標為答案」唯一誠實的時刻。
        private var lastPoint: NSPoint?

        public init() {}

        /// The user's own double-click interval, read live.
        ///
        /// `NSEvent.doubleClickInterval` is in seconds and is a main-thread-ish
        /// AppKit read, so it is fetched on the main queue like everything else
        /// here.
        /// 使用者自身的雙擊間隔，即時讀取。`NSEvent.doubleClickInterval` 以秒為單位，且屬於 AppKit
        /// 的讀取，因此與此處其他操作一樣在主佇列上取得。
        public var doubleClickInterval: Int {
            onMain { Int(NSEvent.doubleClickInterval * 1_000_000) }
        }

        // MARK: - Geometry

        /// Where this process's key window is.
        ///
        /// Its own window, not the focused one. The other two synthesisers have to
        /// ask the system which window is focused because they post system-wide;
        /// this one addresses a window by number, so the window it will post to is
        /// the window it measures, and the two cannot disagree.
        ///
        /// 取得的是自身的視窗，而非「當前具有焦點的視窗」。另外兩個 synthesiser 因為是系統層級投遞，
        /// 必須詢問系統哪個視窗具有焦點；而此處依視窗編號定址，因此「將投遞至的視窗」與「所量測的
        /// 視窗」是同一個，兩者不可能不一致。
        public func currentWindowGeometry() throws -> WindowGeometry {
            try onMain {
                guard let window = Self.targetWindow() else {
                    throw SynthesiserError.unsupported("no window to replay against")
                }
                let content = window.contentView.map { window.convertToScreen($0.frame) } ?? window
                    .frame
                return WindowGeometry(
                    frameOrigin: Self.topLeft(of: window.frame),
                    clientOrigin: Self.topLeft(of: content),
                    // Points, not pixels. The other two convert to physical pixels
                    // because SendInput and XTEST address the display in pixels;
                    // AppKit's event and screen coordinates are both in points, and
                    // multiplying by backingScaleFactor here would land every click
                    // at twice its intended offset on a Retina display.
                    // 使用「點」而非「像素」。另外兩者轉換為實體像素，是因為 SendInput 與 XTEST 以
                    // 像素定址顯示器；而 AppKit 的事件座標與螢幕座標都以點為單位，此處若再乘上
                    // backingScaleFactor，在 Retina 顯示器上每次點擊都會落在預期偏移量的兩倍處。
                    scale: 1,
                    // Filled whenever a popover is open, so a file that says
                    // `origin=popover` resolves instead of failing.
                    // 只要有 popover 開著就會被填入——好讓一個寫著 `origin=popover` 的檔案能夠解析，
                    // 而不是失敗。
                    // The popover's CONTENT, not its frame.
                    //
                    // A popover's window is larger than the panel it draws: it
                    // carries the arrow and a shadow margin. Measured 2026-09-11 --
                    // window at (347, 536) sized 314x180, and cropping exactly that
                    // rect out of a screen capture shows the green panel sitting up
                    // and to the left inside it, with the window behind visible
                    // along the top and right edges.
                    //
                    // Anyone writing `origin=popover` measures from the panel they
                    // can see. Using the frame would put every coordinate off by the
                    // margin, and off by a margin is the kind of wrong that still
                    // lands somewhere plausible.
                    //
                    // popover 的**內容**，而不是它的 frame。
                    //
                    // 一個 popover 的視窗比它畫出來的面板大:它帶著箭頭與陰影邊距。2026-09-11 量測——
                    // 視窗位於 (347, 536)、大小 314x180，而把那個矩形從整螢幕擷圖中原樣裁出來，會看到
                    // 綠色面板偏在它的左上方，上緣與右緣露出後面的視窗。
                    //
                    // 任何人寫 `origin=popover` 時，量的是他看得見的那塊面板。若用 frame，每一個座標都會
                    // 差一個邊距——而「差一個邊距」正是那種「依然會落在某個看似合理之處」的錯法。
                    popoverOrigin: Self.popoverWindow(ownedBy: window).map { popover in
                        let content = popover.contentView.map { popover.convertToScreen($0.frame) }
                        return Self.topLeft(of: content ?? popover.frame)
                    }
                )
            }
        }

        /// The window a replay drives.
        ///
        /// Key window first, because keyboard events go to it and a file that types
        /// must agree with where AppKit will route the text. Falling back to the
        /// first visible window covers the moment just after launch, before the
        /// window has been made key.
        /// 重放所驅動的視窗。優先取 key window，因為鍵盤事件會送往它，而會輸入文字的檔案必須與 AppKit
        /// 實際的文字路由一致。退回至第一個可見視窗，是為了涵蓋啟動後、視窗尚未成為 key 的那一刻。
        /// The app's own window, never a popover.
        ///
        /// **`NSApp.keyWindow` is not it while a popover is open, because a popover
        /// takes key.** Every coordinate in an action file that is not
        /// `origin=popover` is about the app's window, so resolving them against
        /// whatever happens to be key would move every click by the popover's offset
        /// the moment one appeared -- and the file would still replay, and every
        /// click would land somewhere plausible.
        ///
        /// Parentless is the test: a popover, a sheet and an attached panel are all
        /// child windows.
        ///
        /// 這個 app 自己的視窗，絕不是 popover。
        ///
        /// **當一個 popover 開著時，`NSApp.keyWindow` 並不是它——因為 popover 會取得 key。** 動作檔中
        /// 每一個不是 `origin=popover` 的座標，講的都是這個 app 的視窗;若拿「當下剛好是 key 的那一個」
        /// 去解析它們，那麼一旦有 popover 出現，每一次點擊都會被平移一個 popover 的位移——而那個檔案
        /// 依然會重放成功，每一次點擊也都會落在某個看似合理的位置。
        ///
        /// 判準是「沒有父視窗」:popover、sheet 與附著式面板全都是子視窗。
        @MainActor
        private static func targetWindow() -> NSWindow? {
            let ownWindows = NSApp.windows.filter { $0.isVisible && $0.parent == nil }
            return ownWindows.first { $0.isKeyWindow } ?? ownWindows.first
        }

        /// The popover attached to `window`, if one is open.
        ///
        /// **Identified the way `Win32Synthesiser` identifies one -- a visible
        /// top-level owned by the driven window and smaller than it -- rather than
        /// by class name.** `NSPopover`'s window is a private `_NSPopoverWindow`,
        /// and matching that string is matching an implementation detail; ownership
        /// and size are what the popover actually is.
        ///
        /// The size test earns its place: a sheet is also an owned visible
        /// top-level and is usually as wide as its parent, so requiring strictly
        /// smaller in both dimensions keeps this from picking one.
        ///
        /// 附著於 `window` 的那個 popover，若有開著的話。
        ///
        /// **以 `Win32Synthesiser` 辨識它的方式來辨識——「一個被所驅動視窗擁有、且比它小的可見
        /// top-level」——而不是靠類別名稱。** `NSPopover` 的視窗是私有的 `_NSPopoverWindow`，對那個字串
        /// 比對，就是在對一個實作細節比對;「歸屬」與「尺寸」才是那個 popover 真正**是**的東西。
        ///
        /// 尺寸這一項有其必要:一個 sheet 同樣是「被擁有的可見 top-level」，而且通常與其父視窗一樣寬，
        /// 因此要求兩個維度都嚴格較小，可以避免挑到它。
        @MainActor
        static func popoverWindow(ownedBy window: NSWindow) -> NSWindow? {
            return NSApp.windows.first { candidate in
                candidate !== window
                    && candidate.isVisible
                    && candidate.parent === window
                    && candidate.frame.width < window.frame.width
                    && candidate.frame.height < window.frame.height
            }
        }

        /// Raises the window whose title matches exactly.
        ///
        /// **Exact, and visible-only.** AppKit keeps closed windows around in
        /// `NSApp.windows`, so a prefix match or a match against a hidden window
        /// would hand back something that cannot receive a click -- and the events
        /// would then go to whatever really is in front, which is the failure this
        /// action exists to remove rather than reproduce.
        ///
        /// `activate()` as well as `makeKeyAndOrderFront`: a window can be key
        /// within an application that is not itself frontmost, and a replay driving
        /// a background application clicks on nothing.
        ///
        /// 讓標題**完全相符**的那個視窗上前。
        ///
        /// **完全相符，且僅限可見的視窗。** AppKit 會把已關閉的視窗留在 `NSApp.windows` 中，因此前綴比對、
        /// 或比對到一個隱藏的視窗，交回的會是一個接收不到點擊的東西——而那些事件接著會落到「真正在前景的
        /// 那個」，正是這個動作要消除、而非重現的失敗。
        ///
        /// 除了 `makeKeyAndOrderFront` 之外還呼叫 `activate()`：一個視窗可以在「本身並非最前景的應用程式」
        /// 之中成為 key window，而驅動一個背景應用程式的重放，點到的是空氣。
        /// The key window's number, or 0 when there is none.
        ///
        /// **The default returns 0, and 0 is the value `replay` treats as "cannot
        /// tell" -- so without this override the geometry was never re-measured on
        /// macOS.** That did not matter while every file drove one window. It
        /// matters the moment `focus` exists: focus moved, and the coordinates after
        /// it kept resolving against the window that had been measured before the
        /// replay began. Measured 2026-09-09 with P60 -- the `focus` row succeeded,
        /// the replay reported all 8 actions, and the `+1` inside the settings
        /// window was posted at a point in the MAIN window's frame.
        ///
        /// `windowNumber` rather than an `ObjectIdentifier`: it is what AppKit
        /// itself uses to identify a window across processes, it is stable while the
        /// window lives, and it is already an `Int`.
        ///
        /// key window 的視窗編號，沒有 key window 時為 0。
        ///
        /// **預設實作回傳 0，而 0 正是 `replay` 用來代表「無法判斷」的值——因此少了這個覆寫，macOS 上的
        /// geometry 從來不會被重新量測。** 在「每個檔案只驅動一個視窗」的年代這不重要；而 `focus` 一旦
        /// 存在就重要了：焦點移動了，而其後的座標仍然相對於「重放開始前所量測的那個視窗」解析。
        /// 2026-09-09 以 P60 實測——`focus` 那一列成功、重放回報 8 個動作全部完成，而設定視窗裡的 `+1`
        /// 被投遞到了**主視窗**框中的某個點。
        ///
        /// 使用 `windowNumber` 而非 `ObjectIdentifier`：那是 AppKit 自己用來跨行程辨識視窗的東西，
        /// 在視窗存活期間穩定，而且它本來就是 `Int`。
        public func currentWindowIdentity() -> Int {
            onMain { NSApp.keyWindow?.windowNumber ?? 0 }
        }

        /// Not `@MainActor` on the method, `onMain` inside it -- the same shape every
        /// other AppKit call in this file uses. Marking the method itself is what the
        /// compiler rejects: *"conformance of 'AppKitSynthesiser' to protocol
        /// 'Synthesiser' crosses into main actor-isolated code"*, because the replay
        /// deliberately runs off the main thread.
        /// 隔離標註不放在方法上，而是在方法內部用 `onMain`——與本檔中其他每一個 AppKit 呼叫同一個形狀。
        /// 把方法本身標為 `@MainActor` 正是編譯器所拒絕的：*「conformance of 'AppKitSynthesiser' to
        /// protocol 'Synthesiser' crosses into main actor-isolated code」*，因為重放是刻意不在主執行緒上跑的。
        public func focusWindow(titled title: String) throws {
            try onMain {
                let candidates = NSApp.windows.filter(\.isVisible)
                guard let window = candidates.first(where: { $0.title == title }) else {
                    throw SynthesiserError.unsupported(
                        "focus '\(title)': no visible window with that exact title; visible titles are "
                            + candidates.map { "'\($0.title)'" }.joined(separator: ", ")
                    )
                }
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
        }

        /// AppKit screen coordinates put `0,0` at the bottom-left of the primary
        /// screen and grow upwards; ``WindowGeometry`` is written top-left-origin,
        /// downwards, like the other two platforms. This is the only place the two
        /// meet.
        ///
        /// The reference edge is the primary screen's top, and it cancels: geometry
        /// is measured against it here and unwound against it in ``windowPoint``,
        /// so a wrong reference would still land on the right control. It is named
        /// correctly anyway, because a caller may supply its own geometry.
        ///
        /// AppKit 的螢幕座標以主螢幕左下角為 `0,0` 且向上增長；``WindowGeometry`` 則如同另外兩個平台，
        /// 以左上角為原點、向下增長。此處是兩者唯一交會之處。
        ///
        /// 參考邊為主螢幕頂端，而它會相互抵消：幾何資訊在此依它量測，並在 ``windowPoint`` 中依它還原，
        /// 因此即使參考取錯，仍會落在正確的控制項上。儘管如此仍取正確的值，因為呼叫端可能自行提供幾何。
        /// A view's rect in **absolute** screen coordinates: top-left origin,
        /// points, measured from the primary screen's top.
        ///
        /// **This is not a number you can write into an action file.** A file's `x`
        /// and `y` are relative to `origin=frame` or `origin=client`, so a caller
        /// subtracts the matching origin from ``currentWindowGeometry``:
        ///
        ///     let rect = AppKitSynthesiser.actionFileRect(of: view)
        ///     let geometry = try AppKitSynthesiser().currentWindowGeometry()
        ///     let x = rect.x - geometry.clientOrigin.x      // for origin=client
        ///     let y = rect.y - geometry.clientOrigin.y
        ///
        /// The first version of this sentence said "the space an action file's
        /// coordinates are written in", which a reader took to mean the numbers were
        /// ready to use -- a fair reading, and the two things are one subtraction
        /// apart. This whole exchange began with two quantities that were both
        /// called coordinates and differed by an origin, so the doc now says which
        /// one this is and shows the subtraction rather than describing it.
        ///
        /// **Take both values from the same pair of calls.** Both this and
        /// ``currentWindowGeometry`` flip against `NSScreen.screens.first`, so that
        /// reference cancels in the subtraction; it does not cancel against a window
        /// position obtained some other way, and mixing the two sources is a
        /// difference no arithmetic reveals.
        ///
        /// Verified on P45, 2026-09-07: the button reports `593,582 104x27` with
        /// `clientOrigin 580,141`, so `origin=client` at `(65,451)` -- the rect
        /// minus that origin, plus half the size -- hits it, and the app's
        /// `selection` reads 2.
        ///
        /// 一個 view 的矩形,以**絕對**螢幕座標表示:左上為原點、單位為點、自主螢幕頂端量起。
        ///
        /// **這不是一個可以直接寫進動作檔的數字。** 檔案裡的 `x` 與 `y` 是相對於 `origin=frame` 或
        /// `origin=client` 的,因此呼叫端要減去 ``currentWindowGeometry`` 中對應的那個原點(見上方
        /// 範例)。
        ///
        /// 本句的第一版寫的是「動作檔座標所在的那個空間」,而一位讀者把它理解成「這些數字可以直接使用」
        /// ——那是合理的讀法,而兩者之間只差一次相減。這整段往返的起點,正是兩個都被稱為座標、卻差一個
        /// 原點的量;因此文件現在會說明「這是哪一個」,並把那次相減寫出來,而不是用描述的。
        ///
        /// **兩個值要取自同一對呼叫。** 本函式與 ``currentWindowGeometry`` 都以
        /// `NSScreen.screens.first` 為翻轉基準,因此該基準會在相減中互相抵消;但它不會與「以其他方式
        /// 取得的視窗位置」互相抵消,而混用兩個來源所造成的差異,是任何算術都看不出來的。
        ///
        /// 2026-09-07 於 P45 上驗證:該按鈕回報 `593,582 104x27`、`clientOrigin 580,141`,因此
        /// `origin=client` 的 `(65,451)`——即該矩形減去那個原點、再加上尺寸的一半——命中它,而 app 的
        /// `selection` 讀到 2。
        ///
        /// Public because a
        /// diagnostic dump that computes this itself will drift from the space the
        /// replay actually uses, and then the two disagree without either being
        /// obviously wrong.
        ///
        /// That is not hypothetical. A peer's dump reported a control at
        /// `190,290 338x27` while the replay resolved the same control at
        /// `24,279 332x20` -- an origin off by 166 points and a size off by six --
        /// and reconciling the two by scanning the control's edges produced a
        /// confident, wrong rule about where controls respond. One function that
        /// both sides call cannot disagree with itself.
        ///
        /// 一個 view 的矩形,以「動作檔座標所使用的那個空間」表示。
        ///
        /// 左上為原點、單位為點、自主螢幕頂端量起——與 ``currentWindowGeometry`` 所回報的是同一個空間,
        /// 因此也就是 `origin=frame` 與 `origin=client` 所相對的那一個。設為 public,是因為一份自行
        /// 計算此值的診斷傾印會與「重放實際使用的空間」漂移開來,屆時兩者互相矛盾,而任一方看起來都不
        /// 明顯是錯的。
        ///
        /// 這並非假設。某位同事的傾印把一個控制項回報為 `190,290 338x27`,而重放把同一個控制項解析在
        /// `24,279 332x20`——原點差了 166 點、尺寸差了六點——而以掃描控制項邊緣的方式去調和兩者,產生了
        /// 一條自信而錯誤的「控制項在哪裡會回應」的規則。一個由雙方共同呼叫的函式,不可能與自己矛盾。
        @MainActor
        public static func actionFileRect(of view: NSView)
            -> (x: Double, y: Double, width: Double, height: Double)
        {
            guard let window = view.window else {
                return (0, 0, Double(view.bounds.width), Double(view.bounds.height))
            }
            let inWindow = view.convert(view.bounds, to: nil)
            let onScreen = window.convertToScreen(inWindow)
            let corner = topLeft(of: onScreen)
            return (corner.x, corner.y, Double(onScreen.width), Double(onScreen.height))
        }

        @MainActor
        private static func topLeft(of rect: NSRect) -> (x: Double, y: Double) {
            (x: Double(rect.minX), y: Double(primaryScreenTop() - rect.maxY))
        }

        @MainActor
        private static func primaryScreenTop() -> CGFloat {
            NSScreen.screens.first?.frame.maxY ?? 0
        }

        /// An action file's point, in the window coordinates `NSEvent` wants.
        ///
        /// Verified against a two-button window before this file existed: with the
        /// content view 200pt tall, client `(150, 40)` resolved to window
        /// `(150, 160)` and hit the top button, and client `(150, 160)` resolved to
        /// `(150, 40)` and hit the bottom one.
        /// 動作檔中的座標，轉換為 `NSEvent` 所需的視窗座標。在本檔存在之前已對一個雙按鈕視窗驗證：
        /// content view 高 200pt 時，client `(150, 40)` 解析為視窗座標 `(150, 160)` 並命中上方按鈕，
        /// client `(150, 160)` 解析為 `(150, 40)` 並命中下方按鈕。
        /// `throws`, because `screenPosition(of:)` does.
        ///
        /// **This did not compile on macOS and did compile everywhere it was
        /// written.** `AppKitSynthesiser.swift` is macOS-only, so a `try` added
        /// inside a non-throwing function here is invisible on the Windows side --
        /// the file is never handed to the compiler there. Found 2026-09-09 by the
        /// first `Scripts/test.sh` run on a Mac after the merge, with
        /// "errors thrown from here are not handled". The fix propagates the throw
        /// rather than swallowing it: a coordinate that cannot be resolved must
        /// stop the replay, not silently click at the last known point.
        ///
        /// `throws`，因為 `screenPosition(of:)` 會 throw。
        ///
        /// **這在 macOS 上編不過，而在它被寫出來的地方編得過。** `AppKitSynthesiser.swift` 僅限 macOS，
        /// 因此「在一個不會 throw 的函式裡加上 `try`」這件事在 Windows 側看不見——那個檔案在那裡根本不會
        /// 被交給編譯器。2026-09-09 由合併之後 Mac 上的第一次 `Scripts/test.sh` 執行發現，訊息為
        /// 「errors thrown from here are not handled」。此處的修法是把該 throw 往外傳，而不是把它吞掉：
        /// 一個無法解析的座標必須讓重放停止，而不是靜靜地點在上一個已知位置。
        @MainActor
        private static func windowPoint(
            for point: Point,
            in geometry: WindowGeometry,
            window: NSWindow
        ) throws -> NSPoint {
            let screen = try geometry.screenPosition(of: point)
            return window.convertPoint(
                fromScreen: NSPoint(
                    x: Double(screen.x),
                    y: Double(primaryScreenTop()) - Double(screen.y)
                )
            )
        }

        // MARK: - Performing

        public func perform(_ action: InputAction, in geometry: WindowGeometry) throws {
            // Sleeping stays on the calling thread. Hopping to the main queue for it
            // would make the application sleep too, which is the failure the
            // protocol's own documentation records.
            // 睡眠留在呼叫端執行緒。若為此跳到主佇列，應用程式也會一併睡著，而那正是本協定文件所記載的
            // 那個失敗。
            // Focus first, and outside the main-queue hop below for the same reason
            // `sleep` is: it changes what "the current window" means, and the
            // caller's loop re-measures geometry on the next action once
            // `currentWindowIdentity()` reports the change.
            // focus 先處理，並且與下方的主佇列跳轉分開，理由與 `sleep` 相同：它改變的是「當前視窗」的
            // 意義，而呼叫端的迴圈會在 `currentWindowIdentity()` 回報變化之後，於下一個動作重新量測 geometry。
            if case .focus(let title) = action {
                try focusWindow(titled: title)
                return
            }

            if case .sleep(let microseconds) = action {
                Thread.sleep(forTimeInterval: Double(microseconds) / 1_000_000)
                return
            }

            if case .doubleClick(let button, let point) = action {
                try performDoubleClick(button, at: point, in: geometry)
                return
            }

            try onMain {
                guard let mainWindow = Self.targetWindow() else {
                    throw SynthesiserError.unsupported("no window to replay against")
                }

                // A popover is its OWN window, and an event addressed to the main
                // one lands outside it.
                //
                // This is what made `origin=popover` Windows-only here: the
                // coordinates could be computed, and the click was then posted to
                // the window BEHIND the popover, which light-dismisses it. From
                // outside, a dismissed popover and a click that missed are the same
                // picture -- the popover is gone either way.
                //
                // 一個 popover 是它**自己的**視窗，而一個投遞給主視窗的事件會落在它之外。
                //
                // 這正是 `origin=popover` 在此處過去僅限 Windows 的原因:座標算得出來，而那次點擊接著被
                // 投遞給了 popover **後方**的視窗——那會把它 light-dismiss 掉。從外部看，「一個被關掉的
                // popover」與「一次沒打中的點擊」是同一張圖:兩種情況下它都不見了。
                let window: NSWindow
                if action.point?.origin == .popover {
                    guard let popover = Self.popoverWindow(ownedBy: mainWindow) else {
                        throw SynthesiserError.unsupported(
                            "origin=popover, but no popover is open on this window"
                        )
                    }
                    window = popover
                } else {
                    window = mainWindow
                }

                // The pointer position a positionless click uses. AppKit has no
                // notion of "where the last synthesised event was", so it is read
                // back from the window rather than remembered: whatever the file
                // last moved to is where the cursor now is.
                // 無座標點擊所使用的指標位置。AppKit 沒有「上一個合成事件在哪裡」的概念，因此改為自
                // 視窗讀回，而非自行記憶：檔案最後移動到的位置，就是游標現在所在之處。
                @MainActor func location(_ point: Point?) throws -> NSPoint {
                    guard let point else {
                        return self.trackedPoint() ?? window.mouseLocationOutsideOfEventStream
                    }
                    let resolved = try Self.windowPoint(for: point, in: geometry, window: window)
                    self.track(resolved)
                    return resolved
                }

                switch action {
                    case .hover(let point):
                        // **Warp, then WAIT FOR THE ANSWER TO CHANGE, then report.**
                        //
                        // A cursor is the one thing `BackendFeatures.Cursors` produces that no
                        // ordinary capture contains: `screencapture` omits the pointer unless
                        // given `-C`, and even with it the picture shows a shape without saying
                        // whose it is. So the verb reads it back -- and reading it back is where
                        // the difficulty turned out to be.
                        //
                        // **Fixed pauses do not work here, and four of them were tried.** The
                        // tracking-area machinery that drives `cursorUpdate` runs from the WINDOW
                        // SERVER's idea of the pointer, not from the synthetic event this posts,
                        // so the round trip is asynchronous and competes with a test app running
                        // a 60 Hz frame clock. On 2026-09-22 a 50 ms pump, a 250 ms pump, posting
                        // the move twice with a pump between, and reading `currentSystem` instead
                        // of `current` all left the reading one event late on some runs: three
                        // runs of the same unchanged file gave (arrow, crosshair), (arrow, arrow)
                        // and (crosshair, arrow). A pause long enough "on this machine today" is
                        // the shape of a test that passes until it matters.
                        //
                        // So this waits for a SIGNAL rather than for a duration: the cursor
                        // before the warp is recorded, and the loop stops the moment the reading
                        // differs from it. A change can only come from AppKit having processed
                        // the move, which is exactly the event being waited on.
                        //
                        // **And when it never changes, that is REPORTED, not hidden.** A row that
                        // moves the pointer between two places with the same cursor legitimately
                        // sees no change, and so does a row whose move never arrived. They are
                        // indistinguishable from here, so the line says `unchanged after Nms` and
                        // lets the reader decide. Silently printing the old value is what made
                        // the earlier versions of this look like a confinement defect.
                        //
                        // **先 warp,然後等那個答案**改變**,再回報。**
                        //
                        // 游標是 `BackendFeatures.Cursors` 所產生、而任何一般擷圖都不含的那一樣東西:
                        // `screencapture` 除非加 `-C` 否則不含指標,而即使加了,那張圖也只顯示一個形狀、
                        // 不說那是誰的。因此這個動作會把它讀回來——而困難之處正是在「讀回來」。
                        //
                        // **固定的等待在此處行不通,而且試過四種。** 驅動 `cursorUpdate` 的 tracking area
                        // 機制,依據的是**視窗伺服器**對指標位置的認知,不是此處投遞的那個合成事件;
                        // 因此那趟往返是非同步的,而且要和一支跑著 60 Hz frame clock 的測試 app 競爭。
                        // 2026-09-22 當天:50 毫秒的 pump、250 毫秒的 pump、把移動事件投遞兩次並在中間
                        // pump、以及改讀 `currentSystem` 而非 `current`——四種都在某些執行中慢了一個事件:
                        // 同一份未經修改的檔案連跑三次,給出 (arrow, crosshair)、(arrow, arrow)、
                        // (crosshair, arrow)。一個「在這台機器上今天夠長」的等待,正是那種
                        // 「在它真正重要之前都會通過」的測試的形狀。
                        //
                        // 因此此處等的是一個**訊號**、不是一段**時間**:先記下 warp 之前的游標,
                        // 而迴圈在「讀到的值與它不同」的那一刻就停止。而那個改變只可能來自
                        // 「AppKit 已經處理了那次移動」——也正是此處所等待的那個事件。
                        //
                        // **而當它始終沒有改變時,那件事會被**回報**、不會被藏起來。** 一列「在兩個游標
                        // 相同的位置之間移動指標」的動作,本來就看不到改變;而一列「移動根本沒送達」的
                        // 動作也一樣。從此處看兩者無法區分,因此那一行會寫 `unchanged after Nms`,
                        // 把判斷交給讀的人。靜默地印出舊值,正是本段早先幾個版本看起來像「侷限性缺陷」
                        // 的原因。
                        // **The window has to be KEY, and that is the whole of why the earlier
                        // attempts were flaky.**
                        //
                        // `NSCursorTarget`'s tracking area is `.activeInKeyWindow` -- deliberately,
                        // because a background window should not repaint the pointer for an app
                        // the user is not in. The consequence for a replay is that if anything has
                        // taken key status (a Terminal, a simulator, the emulator window), AppKit
                        // sends NO `cursorUpdate` at all and the reading never changes. Measured
                        // on 2026-09-23 with the change-detecting wait below: three runs gave one
                        // row that changed and five that reported `unchanged after ~1860ms`,
                        // which is not a slow answer -- it is no answer.
                        //
                        // So this asks for key status before warping rather than assuming it.
                        //
                        // **那個視窗必須是 KEY,而那正是先前幾次嘗試會飄的全部原因。**
                        //
                        // `NSCursorTarget` 的 tracking area 是 `.activeInKeyWindow`——這是刻意的,
                        // 因為一個背景視窗不該替「使用者並不在其中的 app」去改變指標樣子。它對重放的後果是:
                        // 只要有任何東西搶走了 key 狀態(終端機、模擬器、emulator 視窗),AppKit 就
                        // **完全不會**送出 `cursorUpdate`,於是那個讀數永遠不會改變。2026-09-23 以下方的
                        // 變化偵測等待實測:三次執行中,只有一列真的改變了,另外五列回報
                        // `unchanged after ~1860ms`——那不是一個慢的答案,那是**沒有答案**。
                        //
                        // 因此此處在 warp 之前主動要求 key 狀態,而不是假設它成立。
                        NSApp.activate(ignoringOtherApps: true)
                        window.makeKeyAndOrderFront(nil)
                        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

                        let before = Self.cursorReading()
                        do {
                            let screen = try geometry.screenPosition(of: point)
                            CGWarpMouseCursorPosition(
                                CGPoint(x: Double(screen.x), y: Double(screen.y))
                            )
                            CGAssociateMouseAndMouseCursorPosition(1)
                        }
                        try self.postMouse(
                            .mouseMoved,
                            .left,
                            at: try location(point),
                            in: window,
                            clicks: 0
                        )

                        let deadline = Date().addingTimeInterval(2)
                        var elapsed = 0
                        var reading = before
                        while Date() < deadline {
                            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
                            elapsed += 20
                            reading = Self.cursorReading()
                            if reading != before { break }
                        }
                        // One more slice after the change, so that a move which produces an exit
                        // followed by an enter is reported as where it ENDED rather than as the
                        // arrow it passed through.
                        // 改變之後再多跑一段,好讓「先離開、再進入」的一次移動,回報的是它**結束**之處,
                        // 而不是它中途經過的那個箭頭。
                        if reading != before {
                            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
                            reading = Self.cursorReading()
                        }
                        ActionFileReplay.report(
                            "cursor at (\(Int(point.x)), \(Int(point.y))) is \(reading.name)"
                                + (reading == before ? " (unchanged after \(elapsed)ms)" : "")
                        )

                    case .longPress:
                        // Not a right-click in disguise. See `InputAction.longPress`.
                        // 不是偽裝成長按的右鍵。見 `InputAction.longPress`。
                        throw SynthesiserError.unsupported(
                            "longpress: a long press does not raise a context menu here; "
                                + "use `click ... right`"
                        )

                    case .move(let point):
                        // **The PHYSICAL pointer is moved too, and until
                        // 2026-09-20 it was not.** `NSApp.postEvent` delivers a
                        // synthetic mouse-moved event to this application; the
                        // cursor on screen does not follow it. Everything driven
                        // by the event stream worked -- hit testing, hover, drag
                        // -- so nothing complained for months. What does not work
                        // is anything that reads the REAL pointer: the cursor
                        // shape (`.cursor(_:)` and `NSTrackingArea.cursorUpdate`),
                        // `NSEvent.mouseLocation`, and any `screencapture -C`,
                        // which draws the pointer where the mouse physically is.
                        //
                        // This module's own README says the verb is "move the
                        // pointer". It now does.
                        //
                        // `.click` deliberately still does not warp, even though
                        // the README says it "moves first if a position is
                        // given": every verified action file in this tree was
                        // measured with clicks that left the pointer alone, and
                        // moving it could put the real cursor over something that
                        // reacts to hover. That is a separate change with its own
                        // re-verification, not a free rider on this one.
                        //
                        // **實體指標也會被移動了,而在 2026-09-20 之前並不會。** `NSApp.postEvent` 送出的是
                        // 一個給「本應用程式」的合成 mouse-moved 事件;螢幕上的游標不會跟著走。凡是由事件流
                        // 驅動的東西都能運作——hit testing、hover、拖曳——所以幾個月來沒有任何東西抗議。
                        // 不能運作的是「讀取**真實**指標」的那些東西:游標形狀(`.cursor(_:)` 與
                        // `NSTrackingArea.cursorUpdate`)、`NSEvent.mouseLocation`,以及任何
                        // `screencapture -C`——它畫的是滑鼠實體所在之處。
                        //
                        // 本模組自己的 README 寫著這個動作是「移動指標」。現在它真的會。
                        //
                        // `.click` **刻意**仍然不 warp,即使 README 說它「若帶位置則先移動」:這棵樹裡每一份
                        // 已驗證的動作檔,都是在「點擊不會動到指標」的前提下量出來的,而移動它可能把真實游標
                        // 放到某個會對 hover 起反應的東西上。那是另一次變更、要有它自己的重新驗證,
                        // 不能搭這一次的順風車。
                        do {
                            let screen = try geometry.screenPosition(of: point)
                            CGWarpMouseCursorPosition(
                                CGPoint(x: Double(screen.x), y: Double(screen.y))
                            )
                            // Without this the hardware mouse stays disconnected
                            // from the cursor for about a quarter of a second, so
                            // a person nudging the mouse right after a replay sees
                            // it jump back.
                            // 少了這一行,實體滑鼠會與游標失聯約四分之一秒;於是重放結束後立刻動一下滑鼠的人,
                            // 會看到游標跳回去。
                            CGAssociateMouseAndMouseCursorPosition(1)
                        }
                        try self.postMouse(
                            .mouseMoved,
                            .left,
                            at: try location(point),
                            in: window,
                            clicks: 0
                        )

                    case .click(let button, let point):
                        let at = try location(point)
                        try self.postMouse(
                            Self.downType(button),
                            button,
                            at: at,
                            in: window,
                            clicks: 1
                        )
                        try self.postMouse(
                            Self.upType(button),
                            button,
                            at: at,
                            in: window,
                            clicks: 1
                        )

                    case .mouseDown(let button, let point):
                        try self.postMouse(
                            Self.downType(button),
                            button,
                            at: try location(point),
                            in: window,
                            clicks: 1
                        )

                    case .mouseUp(let button, let point):
                        try self.postMouse(
                            Self.upType(button),
                            button,
                            at: try location(point),
                            in: window,
                            clicks: 1
                        )

                    case .keyDown(let key):
                        self.hold(key)
                        try self.postKey(key, down: true, in: window)

                    case .keyUp(let key):
                        // Released BEFORE the event is built, not after.
                        //
                        // **A flagsChanged event carries the modifier state as it is
                        // NOW, and releasing afterwards made every modifier key-up
                        // say the modifier was still held.** Measured 2026-09-19
                        // with P72: `keyup shift` produced `MODIFIERS up
                        // shift=true`, so an app watching a modifier to switch modes
                        // would switch in and never switch back. `release` only
                        // touches `heldModifiers`, so for an ordinary key this
                        // reorder changes nothing.
                        //
                        // 在事件被建構**之前**釋放,而不是之後。
                        //
                        // **一個 flagsChanged 事件所帶的是「此刻」的修飾鍵狀態,而在事後才釋放,
                        // 會讓每一次修飾鍵放開都聲稱該修飾鍵仍被按住。** 2026-09-19 以 P72 實測:
                        // `keyup shift` 產生的是 `MODIFIERS up shift=true`——於是一個「看修飾鍵切換模式」
                        // 的 app 會切進去、再也切不回來。`release` 只動 `heldModifiers`,因此對一般按鍵
                        // 而言,這個順序調換不改變任何事。
                        self.release(key)
                        try self.postKey(key, down: false, in: window)

                    case .key(let key):
                        try self.postKey(key, down: true, in: window)
                        try self.postKey(key, down: false, in: window)

                    case .scroll(let dx, let dy):
                        try self.postScroll(dx: dx, dy: dy, at: try location(nil), in: window)

                    case .pinch, .rotate:
                        // **Refused with a reason, and the reason was looked for
                        // rather than assumed.** A magnify or rotate arrives in
                        // AppKit as an `NSEvent` of type `.magnify` / `.rotate`,
                        // and `NSEvent` publishes no initialiser that makes one:
                        // `mouseEvent`, `keyEvent`, `enterExitEvent` and
                        // `otherEvent` are the whole set, and `otherEvent` rejects
                        // gesture types. `CGEvent` has no public gesture
                        // constructor either -- the scroll path here works because
                        // `scrollWheelEvent2Source` exists and has no counterpart
                        // for gestures.
                        //
                        // So this is not "not implemented yet"; it is the platform
                        // having no public way in, stated where someone looking for
                        // it will find it. A trackpad in front of a person is the
                        // route that works, and Windows drives the same feature
                        // with its own injector -- see testapp/touch_gesture.zsh,
                        // which says "Windows only" in its first line.
                        //
                        // **以理由拒絕,而那個理由是去找出來的,不是假設的。** 一次縮放或旋轉在 AppKit 中
                        // 是型別為 `.magnify` / `.rotate` 的 `NSEvent`,而 `NSEvent` 沒有公開任何能造出它的
                        // 初始化式:`mouseEvent`、`keyEvent`、`enterExitEvent` 與 `otherEvent` 就是全部,
                        // 而 `otherEvent` 拒絕手勢型別。`CGEvent` 同樣沒有公開的手勢建構子——此處的捲動之所以
                        // 行得通,是因為 `scrollWheelEvent2Source` 存在,而手勢沒有對應物。
                        //
                        // 因此這不是「還沒實作」,而是這個平台沒有公開的入口,並且寫在會有人來找的地方。
                        // 真正行得通的路是「有人坐在觸控板前面」;而 Windows 以它自己的注入器驅動同一項功能
                        // ——見 testapp/touch_gesture.zsh,它的第一行就寫著「Windows only」。
                        throw SynthesiserError.unsupported(
                            "pinch and rotate on macOS: NSEvent publishes no initialiser for a"
                                + " .magnify or .rotate event, and CGEvent has no public gesture"
                                + " constructor. Drive these on iOS or Android, or by hand on a"
                                + " trackpad."
                        )

                    case .doubleClick, .sleep, .focus:
                        // All three returned above; listed so a new case cannot be
                        // added without the compiler pointing here. `focus` joins
                        // them because it changes which window later actions are
                        // measured against, which has to happen before this block
                        // resolves a window at all.
                        // 三者皆已於上方返回；在此列出，是為了讓新增 case 時編譯器必定指向此處。
                        // `focus` 之所以歸入此列，是因為它改變的是「其後的動作要相對哪個視窗量測」，
                        // 而那必須發生在本區塊解析出任何視窗之前。
                        break
                }
            }
        }

        // MARK: - Mouse

        private static func downType(_ button: MouseButton) -> NSEvent.EventType {
            switch button {
                case .left: .leftMouseDown
                case .right: .rightMouseDown
                case .middle: .otherMouseDown
            }
        }

        private static func upType(_ button: MouseButton) -> NSEvent.EventType {
            switch button {
                case .left: .leftMouseUp
                case .right: .rightMouseUp
                case .middle: .otherMouseUp
            }
        }

        private static func buttonNumber(_ button: MouseButton) -> Int {
            switch button {
                case .left: 0
                case .right: 1
                case .middle: 2
            }
        }

        @MainActor
        private func postMouse(
            _ type: NSEvent.EventType,
            _ button: MouseButton,
            at location: NSPoint,
            in window: NSWindow,
            clicks: Int
        ) throws {
            guard
                let event = NSEvent.mouseEvent(
                    with: type,
                    location: location,
                    modifierFlags: currentModifiers(),
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber,
                    context: nil,
                    eventNumber: 0,
                    clickCount: clicks,
                    // A zero-pressure mouseDown is a mouseDown that some controls
                    // decline to act on; the paired up event is zero by convention.
                    // 壓力為零的 mouseDown 會被部分控制項拒絕處理；成對的 up 事件依慣例為零。
                    pressure: type == Self.downType(button) ? 1 : 0
                )
            else {
                throw SynthesiserError.unsupported("could not construct \(type) event")
            }

            // otherMouse events carry which button they mean in buttonNumber, which
            // NSEvent.mouseEvent cannot set; middle-click therefore goes through
            // CGEvent, whose NSEvent bridge preserves it.
            // otherMouse 事件以 buttonNumber 表示它指的是哪個按鍵，而 NSEvent.mouseEvent 無法設定它；
            // 因此中鍵改走 CGEvent，其 NSEvent 橋接會保留該欄位。
            if button == .middle, let bridged = middleClickEvent(
                from: event,
                type: type,
                in: window
            ) {
                NSApp.postEvent(bridged, atStart: false)
            } else {
                NSApp.postEvent(event, atStart: false)
            }
        }

        @MainActor
        private func middleClickEvent(
            from event: NSEvent,
            type: NSEvent.EventType,
            in window: NSWindow
        ) -> NSEvent? {
            guard let cg = event.cgEvent else { return nil }
            cg.setIntegerValueField(.mouseEventButtonNumber, value: 2)
            return NSEvent(cgEvent: cg)
        }

        /// Delivers a wheel turn to the view under the file's pointer.
        ///
        /// The only verb that does not go through `NSApp.postEvent`, because it
        /// cannot. `NSEvent` has no scroll-wheel constructor, so the event has to be
        /// built as a `CGEvent` and bridged -- and a bridged event carries
        /// `windowNumber == 0`, which `sendEvent:` has no window to route to.
        /// Measured: posted that way, with the location set correctly and even with
        /// the real cursor warped on top of the target, an `NSScrollView` under the
        /// point received nothing at all. Hit-testing and calling `scrollWheel(with:)`
        /// delivers, and the same scroll view moved from offset 0 to 50.
        ///
        /// Two honest consequences. The delivery skips the event queue, so a scroll
        /// can overtake a click posted immediately before it -- action files put
        /// `sleep` rows between steps anyway, and the module's README already asks
        /// for them. And `locationInWindow` on the delivered event is whatever the
        /// bridge produced rather than the target point; scroll views read the
        /// deltas, which are correct.
        ///
        /// 唯一不經由 `NSApp.postEvent` 的動作，因為它辦不到。`NSEvent` 沒有滾輪事件的建構子，因此該
        /// 事件必須以 `CGEvent` 建構再橋接——而橋接後的事件其 `windowNumber == 0`，`sendEvent:` 沒有
        /// 可路由的視窗。實測：以該方式投遞，即使正確設定了位置、甚至把真實游標移到目標之上，位於該點
        /// 下方的 `NSScrollView` 仍然什麼也沒收到。改以 hit-test 並呼叫 `scrollWheel(with:)` 即可送達，
        /// 同一個 scroll view 的偏移量由 0 移動到 50。
        ///
        /// 兩項需要誠實說明的後果。此路徑略過事件佇列，因此一次捲動可能超前緊接在它之前 post 的點擊
        /// ——動作檔本來就會在步驟之間放置 `sleep` 列，本模組的 README 亦已如此要求。另外，送達事件的
        /// `locationInWindow` 是橋接產生的值而非目標座標；scroll view 讀取的是 delta，而那是正確的。
        @MainActor
        private func postScroll(dx: Int, dy: Int, at point: NSPoint, in window: NSWindow) throws {
            guard dx != 0 || dy != 0 else { return }

            // **The sign IS inverted here, and the note that said otherwise was the
            // defect.** `dy` is positive downwards in the action-file format; an
            // `NSEvent` scrolling delta is the FINGER's direction, so moving the
            // viewport down is a negative delta -- the same inversion the iOS
            // runner documents for its drags.
            //
            // Measured on P57, 2026-09-17, with the clip view's origin printed
            // either side of the event: at y=192, one `scroll 0,8` -- nominally
            // downward -- took it to 0. Upward. It hid behind the compensation
            // below, which moved the view down by exactly what the event had just
            // moved it up; see mistakes entry 18.
            //
            // **此處的符號**確實**要反轉,而先前那句「不需要反轉」的註解正是那個缺陷。**
            // 在動作檔格式中 `dy` 為正代表向下;`NSEvent` 的 scrolling delta 講的是**手指**的方向,
            // 因此「把視口往下移」是一個**負的** delta——與 iOS runner 為它的拖曳所記載的是同一種反轉。
            //
            // 2026-09-17 在 P57 上,把 clip view 的原點印在事件兩側量到:位於 y=192 時,一次名義上
            // 向下的 `scroll 0,8` 把它帶到了 0。是向上。它藏在下面那段補償後面——補償把 view 往下移了
            // 「事件剛剛往上移的同一個量」;見 mistakes 第 18 條。
            // 此處不反轉符號。`dy` 以向下為正，而 AppKit 的行 delta 亦採相同慣例。需要取負的是 Windows。
            guard
                let cg = CGEvent(
                    scrollWheelEvent2Source: nil,
                    units: .line,
                    wheelCount: 2,
                    wheel1: Int32(-dy),
                    wheel2: Int32(-dx),
                    wheel3: 0
                ),
                let event = NSEvent(cgEvent: cg)
            else {
                throw SynthesiserError.unsupported("could not construct a scroll event")
            }

            guard let hit = window.contentView?.hitTest(point) else {
                throw SynthesiserError.unsupported(
                    "nothing to scroll at \(Int(point.x)),\(Int(point.y)) -- move the pointer first"
                )
            }

            // Deliver the wheel event, then check it did something, then make it
            // do something if it did not.
            //
            // The event alone is not enough, and that took measuring to establish.
            // Over a SwiftCrossUI `Text` inside a `ScrollView` the hit view is an
            // `NSTextField`, which swallows the wheel; aiming at the enclosing
            // `NSScrollView` instead did not help either -- calling
            // `scrollWheel(with:)` directly on it left its offset at 0 through four
            // notches. The scroll view was scrollable the whole time: its document
            // was 1078pt tall inside a 100pt clip, and `contentView.scroll(to:)`
            // moved it immediately. So AppKit's scroll views act on wheel events
            // from the window server, not on a synthesised one handed to them.
            //
            // The event is still delivered first, because a view with its own
            // `scrollWheel` override is entitled to see it, and that is the case
            // the compensation must not pre-empt. Then the clip view is checked,
            // and moved only if it did not move on its own -- so a scroll view that
            // does honour the event is not scrolled twice.
            //
            // 先送出滾輪事件，再檢查它是否起了作用，若無作用則使其起作用。
            //
            // 僅靠事件本身並不足夠，而這一點是實測得出的。在 `ScrollView` 內的 SwiftCrossUI `Text` 上，
            // hit view 是會吞掉滾輪事件的 `NSTextField`；改為瞄準外圍的 `NSScrollView` 亦無濟於事——
            // 直接對其呼叫 `scrollWheel(with:)`，四格捲動之後偏移量仍為 0。該 scroll view 自始至終都是
            // 可捲動的：其 document 高 1078pt、clip 僅 100pt，而 `contentView.scroll(to:)` 立即使其移動。
            // 因此 AppKit 的 scroll view 所回應的是來自 window server 的滾輪事件，而非交到它手上的合成事件。
            //
            // 仍先送出該事件，因為自行覆寫了 `scrollWheel` 的 view 有權看到它，而那正是補償機制不得搶先
            // 介入的情況。隨後檢查 clip view，僅在它未自行移動時才移動它——如此一來，確實會回應該事件的
            // scroll view 不會被捲動兩次。
            let scrollView = hit.enclosingScrollView
            let before = scrollView?.contentView.bounds.origin

            hit.scrollWheel(with: event)

            // **Give the event a turn before deciding it did nothing.**
            // `NSScrollView` applies a wheel event on a later pass, so the check
            // below always read "unchanged" and the compensation always fired --
            // which is how an inverted delta stayed invisible. Mistakes entry 18.
            //
            // **先給那個事件一個回合,再判斷它什麼都沒做。** `NSScrollView` 是在稍後的一輪才套用滾輪
            // 事件,因此下面那個檢查永遠讀到「沒有改變」、補償每次都開火——而那正是一個反了的 delta
            // 得以隱形的方式。見 mistakes 第 18 條。
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))

            // Says what it found and what it did, the way the hit tester does for
            // clicks. **A scroll that moves nothing is the one outcome this method
            // cannot report by its result** -- it throws when there is nothing under
            // the pointer and otherwise returns successfully either way, so an
            // impossible scroll, a view that swallows the wheel, and a scroll view
            // already at the end all produce the same silence.
            //
            // 說出它找到了什麼、做了什麼——與 hit tester 對點擊所做的相同。**一次「什麼都沒移動」的
            // 捲動,正是這個方法唯一無法由其回傳值回報的結果**——指標下方沒有東西時它會拋錯,除此之外
            // 兩種情況都成功返回,因此「不可能的捲動量」、「吞掉滾輪的 view」、「已經到底的 scroll
            // view」會產生同一種沉默。
            let after = scrollView?.contentView.bounds.origin
            func describe(_ origin: NSPoint?) -> String {
                origin.map { "(\(Int($0.x)),\(Int($0.y)))" } ?? "none"
            }
            var note =
                "-scroll: dx=\(dx) dy=\(dy) at (\(Int(point.x)),\(Int(point.y))) "
                    + "hit=\(type(of: hit)) "
                    + "scrollView=\(scrollView.map { "\(type(of: $0))" } ?? "none") "
                    + "before=\(describe(before)) afterEvent=\(describe(after))"
            if let scrollView {
                let doc = scrollView.documentView?.frame.height ?? 0
                let clip = scrollView.contentView.bounds.height
                note += " doc=\(Int(doc)) clip=\(Int(clip)) range=\(Int(max(0, doc - clip)))"
            }

            if let scrollView, let before, scrollView.contentView.bounds.origin == before {
                // Lines to points, using the scroll view's own line height rather
                // than a number chosen here, so a file scrolls by as much as a real
                // notch would in that view.
                // 由「行」換算為「點」，採用該 scroll view 自身的行高而非此處自訂的數字，使動作檔捲動的
                // 幅度與該 view 中真實的一格相同。
                // CLAMPED to what the scroll view can actually show. An unclamped
                // target is how a scroll up at the top drew nothing at all:
                // `contentView.scroll(to:)` accepts a point above the document, and
                // a clip view parked there shows empty space -- measured at y=-192,
                // five hundred rows with none of them on screen. AppKit's own wheel
                // handling clamps; this path replaced it and had not.
                //
                // 夾在這個 scroll view 真正顯示得出來的範圍內。沒有夾範圍的目標點,正是「在頂端往上捲
                // 會什麼都不畫」的成因:`contentView.scroll(to:)` 接受文件上方的點,而停在那裡的
                // clip view 顯示的是空白——量到 y=-192:五百列,畫面上一列都沒有。AppKit 自己的滾輪
                // 處理會夾範圍;這條路徑取代了它,卻沒有夾。
                let document = scrollView.documentView?.frame.size ?? .zero
                let visible = scrollView.contentView.bounds.size
                let target = NSPoint(
                    x: min(
                        max(0, before.x + Double(dx) * scrollView.horizontalLineScroll),
                        max(0, document.width - visible.width)
                    ),
                    y: min(
                        max(0, before.y + Double(dy) * scrollView.verticalLineScroll),
                        max(0, document.height - visible.height)
                    )
                )
                scrollView.contentView.scroll(to: target)
                scrollView.reflectScrolledClipView(scrollView.contentView)
                note +=
                    " compensated target=(\(Int(target.x)),\(Int(target.y)))"
                    + " lineScroll=\(Int(scrollView.verticalLineScroll))"
                    + " afterCompensation=\(describe(scrollView.contentView.bounds.origin))"
            }
            FileHandle.standardError.write(Data((note + "\n").utf8))
        }

        // MARK: - Keyboard

        @MainActor
        private func postKey(_ key: Key, down: Bool, in window: NSWindow) throws {
            guard let code = Self.virtualKeyCode(for: key) else {
                throw SynthesiserError.unsupported("key '\(key.rawValue)'")
            }

            let modifiers = currentModifiers()

            // A modifier key is a flagsChanged event, not a keyDown. Posting it as
            // a keyDown gives a control a keystroke it cannot interpret, and gives
            // nothing the flag change it is watching for.
            // 修飾鍵是 flagsChanged 事件，而非 keyDown。若以 keyDown 投遞，控制項會收到一個它無法解讀
            // 的按鍵，而真正在等待旗標變化的一方則什麼也收不到。
            if Self.modifierFlag(for: key) != nil {
                guard
                    let event = NSEvent.keyEvent(
                        with: .flagsChanged,
                        location: .zero,
                        modifierFlags: modifiers,
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber,
                        context: nil,
                        characters: "",
                        charactersIgnoringModifiers: "",
                        isARepeat: false,
                        keyCode: code
                    )
                else {
                    throw SynthesiserError.unsupported("could not construct a flagsChanged event")
                }
                NSApp.postEvent(event, atStart: false)
                return
            }

            // **Arrows and function keys do not go through `UCKeyTranslate`, because
            // what it returns is not what a view receives.** `kVK_UpArrow` translates
            // to U+001E, the ASCII record separator; AppKit substitutes
            // `NSUpArrowFunctionKey` (U+F700) before any view sees the event, and
            // U+F700 is what `KeyEquivalent.upArrow` and SwiftUI both mean by the up
            // arrow. Measured 2026-09-19: a replayed up arrow arrived at a view as
            // U+001E and matched nothing, while the same physical key arrives as
            // U+F700. A synthesiser that does not reproduce the hardware makes every
            // arrow-key test agree with itself and disagree with reality.
            //
            // **方向鍵與功能鍵不走 `UCKeyTranslate`,因為它回傳的東西不是 view 收到的東西。**
            // `kVK_UpArrow` 會被轉譯為 U+001E(ASCII 的記錄分隔符);而 AppKit 在任何 view 看到該事件之前,
            // 會把它替換為 `NSUpArrowFunctionKey`(U+F700)——而 U+F700 正是 `KeyEquivalent.upArrow` 與
            // SwiftUI 對「上方向鍵」的共同定義。2026-09-19 實測:一個重放的上方向鍵送到 view 時是 U+001E、
            // 什麼都對不上,而同一顆實體按鍵送達的是 U+F700。一個不重現硬體的 synthesiser,會讓每一個
            // 方向鍵測試自己跟自己一致、卻跟現實不一致。
            let characters: String
            let bare: String
            if let functionKey = Self.functionKeyCharacter(for: key) {
                characters = functionKey
                bare = functionKey
            } else {
                characters = Self.characters(for: code, modifiers: modifiers)
                bare = Self.characters(for: code, modifiers: modifiers.subtracting(.shift))
            }

            guard
                let event = NSEvent.keyEvent(
                    with: down ? .keyDown : .keyUp,
                    location: .zero,
                    modifierFlags: modifiers,
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber,
                    context: nil,
                    characters: characters,
                    charactersIgnoringModifiers: bare,
                    isARepeat: false,
                    keyCode: code
                )
            else {
                throw SynthesiserError.unsupported("could not construct a key event")
            }
            NSApp.postEvent(event, atStart: false)
        }

        /// What the key produces on the user's actual keyboard layout.
        ///
        /// Translated rather than tabulated. A hard-coded "kVK_ANSI_A means a" is
        /// true on a US layout and false on several others, and a file that types
        /// into a text field would then insert the wrong character on a machine
        /// nobody tested on -- silently, since the keystroke still arrives.
        /// `UCKeyTranslate` asks the layout that is actually installed.
        ///
        /// 採用轉換而非查表。寫死「kVK_ANSI_A 即 a」在 US 佈局上成立，在若干其他佈局上並不成立；
        /// 而會向文字欄位輸入的動作檔，便會在無人測試過的機器上插入錯誤的字元——且是靜默的，因為按鍵
        /// 本身仍然送達。`UCKeyTranslate` 詢問的是實際安裝的佈局。
        /// The character AppKit puts in a key event for the keys that have no
        /// printable one, from the `NS*FunctionKey` constants in `NSEvent.h`.
        ///
        /// These are the same scalars ``KeyEquivalent``'s named statics use, which is
        /// the point: a replayed arrow and a pressed arrow must be the same key.
        ///
        /// AppKit 為「沒有可列印字元的鍵」放進按鍵事件中的那個字元,取自 `NSEvent.h` 的
        /// `NS*FunctionKey` 常數。
        ///
        /// 這些 scalar 與 ``KeyEquivalent`` 各具名靜態值所用的相同,而那正是重點:一個**重放的**方向鍵
        /// 與一個**按下的**方向鍵,必須是同一個鍵。
        private static func functionKeyCharacter(for key: Key) -> String? {
            let scalar: UInt32? =
                switch key {
                    case .upArrow: 0xF700
                    case .downArrow: 0xF701
                    case .leftArrow: 0xF702
                    case .rightArrow: 0xF703
                    case .f1: 0xF704
                    case .f2: 0xF705
                    case .f3: 0xF706
                    case .f4: 0xF707
                    case .f5: 0xF708
                    case .f6: 0xF709
                    case .f7: 0xF70A
                    case .f8: 0xF70B
                    case .f9: 0xF70C
                    case .f10: 0xF70D
                    case .f11: 0xF70E
                    case .f12: 0xF70F
                    case .f13: 0xF710
                    case .f14: 0xF711
                    case .f15: 0xF712
                    case .f16: 0xF713
                    case .f17: 0xF714
                    case .f18: 0xF715
                    case .f19: 0xF716
                    case .f20: 0xF717
                    case .forwardDelete: 0xF728
                    case .home: 0xF729
                    case .end: 0xF72B
                    case .pageUp: 0xF72C
                    case .pageDown: 0xF72D
                    default: nil
                }
            return scalar.flatMap(Unicode.Scalar.init).map(String.init)
        }

        private static func characters(
            for code: CGKeyCode,
            modifiers: NSEvent.ModifierFlags
        ) -> String {
            guard
                let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
                let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
            else {
                return ""
            }

            let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
            var deadKeyState: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 8)

            // Carbon's modifier field is the old event-record layout: the flags sit
            // in the high byte, hence the shift by 8.
            // Carbon 的修飾鍵欄位沿用舊的 event record 佈局：旗標位於高位元組，故右移 8 位。
            var carbonModifiers: UInt32 = 0
            if modifiers.contains(.shift) { carbonModifiers |= UInt32(shiftKey >> 8) }
            if modifiers.contains(.option) { carbonModifiers |= UInt32(optionKey >> 8) }
            if modifiers.contains(.capsLock) { carbonModifiers |= UInt32(alphaLock >> 8) }

            let status = data.withUnsafeBytes { buffer -> OSStatus in
                guard let base = buffer.baseAddress else { return -1 }
                return UCKeyTranslate(
                    base.assumingMemoryBound(to: UCKeyboardLayout.self),
                    code,
                    UInt16(kUCKeyActionDown),
                    carbonModifiers,
                    UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysBit),
                    &deadKeyState,
                    characters.count,
                    &length,
                    &characters
                )
            }

            guard status == noErr, length > 0 else { return "" }
            return String(utf16CodeUnits: characters, count: length)
        }

        // MARK: - Modifier state

        private func hold(_ key: Key) {
            guard let flag = Self.modifierFlag(for: key) else { return }
            lock.lock()
            heldModifiers.insert(flag)
            lock.unlock()
        }

        private func release(_ key: Key) {
            guard let flag = Self.modifierFlag(for: key) else { return }
            lock.lock()
            heldModifiers.remove(flag)
            lock.unlock()
        }

        private func track(_ point: NSPoint) {
            lock.lock()
            lastPoint = point
            lock.unlock()
        }

        private func trackedPoint() -> NSPoint? {
            lock.lock()
            defer { lock.unlock() }
            return lastPoint
        }

        private func currentModifiers() -> NSEvent.ModifierFlags {
            lock.lock()
            defer { lock.unlock() }
            return heldModifiers
        }

        private static func modifierFlag(for key: Key) -> NSEvent.ModifierFlags? {
            switch key {
                case .shift, .rightShift: .shift
                case .control, .rightControl: .control
                case .option, .rightOption: .option
                case .command, .rightCommand: .command
                case .capsLock: .capsLock
                case .function: .function
                default: nil
            }
        }

        // MARK: - Key codes

        /// `Key` to the Carbon virtual key code of the same name.
        ///
        /// The enum's cases are documented as being the `kVK_*` constants with the
        /// prefix dropped, so this reads the constants rather than repeating their
        /// numbers: a table of 90 hand-copied integers is a table with a typo in
        /// it, and the typo would present as one key in a file doing nothing.
        ///
        /// 由 `Key` 對應至同名的 Carbon 虛擬鍵碼。該列舉的 case 已載明為去除前綴的 `kVK_*` 常數，
        /// 因此此處直接引用常數而非複寫其數值：一張 90 個手抄整數的表，就是一張含有錯字的表，而該錯字
        /// 的表現形式會是「動作檔中的某一個按鍵毫無作用」。
        private static func virtualKeyCode(for key: Key) -> CGKeyCode? {
            let code: Int
            switch key {
                case .a: code = kVK_ANSI_A
                case .b: code = kVK_ANSI_B
                case .c: code = kVK_ANSI_C
                case .d: code = kVK_ANSI_D
                case .e: code = kVK_ANSI_E
                case .f: code = kVK_ANSI_F
                case .g: code = kVK_ANSI_G
                case .h: code = kVK_ANSI_H
                case .i: code = kVK_ANSI_I
                case .j: code = kVK_ANSI_J
                case .k: code = kVK_ANSI_K
                case .l: code = kVK_ANSI_L
                case .m: code = kVK_ANSI_M
                case .n: code = kVK_ANSI_N
                case .o: code = kVK_ANSI_O
                case .p: code = kVK_ANSI_P
                case .q: code = kVK_ANSI_Q
                case .r: code = kVK_ANSI_R
                case .s: code = kVK_ANSI_S
                case .t: code = kVK_ANSI_T
                case .u: code = kVK_ANSI_U
                case .v: code = kVK_ANSI_V
                case .w: code = kVK_ANSI_W
                case .x: code = kVK_ANSI_X
                case .y: code = kVK_ANSI_Y
                case .z: code = kVK_ANSI_Z
                case .zero: code = kVK_ANSI_0
                case .one: code = kVK_ANSI_1
                case .two: code = kVK_ANSI_2
                case .three: code = kVK_ANSI_3
                case .four: code = kVK_ANSI_4
                case .five: code = kVK_ANSI_5
                case .six: code = kVK_ANSI_6
                case .seven: code = kVK_ANSI_7
                case .eight: code = kVK_ANSI_8
                case .nine: code = kVK_ANSI_9
                case .delete: code = kVK_Delete
                case .forwardDelete: code = kVK_ForwardDelete
                case .escape: code = kVK_Escape
                case .space: code = kVK_Space
                case .tab: code = kVK_Tab
                case .return: code = kVK_Return
                case .leftArrow: code = kVK_LeftArrow
                case .rightArrow: code = kVK_RightArrow
                case .upArrow: code = kVK_UpArrow
                case .downArrow: code = kVK_DownArrow
                case .home: code = kVK_Home
                case .end: code = kVK_End
                case .pageUp: code = kVK_PageUp
                case .pageDown: code = kVK_PageDown
                case .shift: code = kVK_Shift
                case .control: code = kVK_Control
                case .option: code = kVK_Option
                case .command: code = kVK_Command
                case .rightShift: code = kVK_RightShift
                case .rightControl: code = kVK_RightControl
                case .rightOption: code = kVK_RightOption
                case .rightCommand: code = kVK_RightCommand
                case .capsLock: code = kVK_CapsLock
                case .function: code = kVK_Function
                case .f1: code = kVK_F1
                case .f2: code = kVK_F2
                case .f3: code = kVK_F3
                case .f4: code = kVK_F4
                case .f5: code = kVK_F5
                case .f6: code = kVK_F6
                case .f7: code = kVK_F7
                case .f8: code = kVK_F8
                case .f9: code = kVK_F9
                case .f10: code = kVK_F10
                case .f11: code = kVK_F11
                case .f12: code = kVK_F12
                case .f13: code = kVK_F13
                case .f14: code = kVK_F14
                case .f15: code = kVK_F15
                case .f16: code = kVK_F16
                case .f17: code = kVK_F17
                case .f18: code = kVK_F18
                case .f19: code = kVK_F19
                case .f20: code = kVK_F20
                case .keypad0: code = kVK_ANSI_Keypad0
                case .keypad1: code = kVK_ANSI_Keypad1
                case .keypad2: code = kVK_ANSI_Keypad2
                case .keypad3: code = kVK_ANSI_Keypad3
                case .keypad4: code = kVK_ANSI_Keypad4
                case .keypad5: code = kVK_ANSI_Keypad5
                case .keypad6: code = kVK_ANSI_Keypad6
                case .keypad7: code = kVK_ANSI_Keypad7
                case .keypad8: code = kVK_ANSI_Keypad8
                case .keypad9: code = kVK_ANSI_Keypad9
                case .keypadDecimal: code = kVK_ANSI_KeypadDecimal
                case .keypadPlus: code = kVK_ANSI_KeypadPlus
                case .keypadMinus: code = kVK_ANSI_KeypadMinus
                case .keypadMultiply: code = kVK_ANSI_KeypadMultiply
                case .keypadDivide: code = kVK_ANSI_KeypadDivide
                case .keypadEnter: code = kVK_ANSI_KeypadEnter
                case .keypadEquals: code = kVK_ANSI_KeypadEquals
                case .keypadClear: code = kVK_ANSI_KeypadClear
            }
            return CGKeyCode(code)
        }

        // MARK: - Threading

        /// Runs a body on the main queue and waits for it.
        ///
        /// AppKit is main-thread-only, and a replay deliberately is not: it spends
        /// nearly all its time asleep and must not do that on the UI's thread. So
        /// the sleeping stays where the replay runs and only the AppKit work hops
        /// across, which is the smallest arrangement that satisfies both.
        ///
        /// A replay already on the main thread would deadlock here, so that case is
        /// handled rather than assumed away -- it is exactly the mistake the
        /// protocol documentation warns about, and it should fail loudly if it is
        /// ever made.
        ///
        /// 在主佇列上執行並等待其完成。AppKit 僅限主執行緒，而重放刻意不在主執行緒上：它幾乎整段時間
        /// 都在睡眠，不能在 UI 執行緒上這麼做。因此睡眠留在重放所在之處，只有 AppKit 的工作跳過去，
        /// 這是同時滿足兩者的最小安排。
        ///
        /// 已在主執行緒上的重放會在此死鎖，因此該情況被實際處理而非假設不存在——那正是協定文件所警告的
        /// 錯誤，一旦發生就應該大聲失敗。
        private func onMain<T: Sendable>(_ body: @MainActor () throws -> T) rethrows -> T {
            if Thread.isMainThread {
                return try MainActor.assumeIsolated(body)
            }
            return try DispatchQueue.main.sync {
                try MainActor.assumeIsolated(body)
            }
        }
    }

    @MainActor
    extension AppKitSynthesiser {
        /// Names a cursor, because `NSCursor` has no name and a pointer in a photograph has no
        /// name either.
        ///
        /// Compared by IDENTITY against the system cursors, not by any property:
        /// `NSCursor.crosshair` is a singleton and `===` against it is exact, while comparing
        /// images would be comparing two renderings of the same thing. Anything unrecognised is
        /// reported as `other` with the hot spot rather than guessed at -- a wrong name here
        /// would be read as a wrong cursor.
        ///
        /// 為一個游標命名,因為 `NSCursor` 沒有名字,而照片裡的一個指標也沒有名字。
        ///
        /// 以**識別**與系統游標比較,不是比較任何屬性:`NSCursor.crosshair` 是單例,對它用 `===`
        /// 是精確的;而比較影像則會變成「比較同一個東西的兩次算繪」。認不出來的東西回報為 `other`
        /// 並附上熱點,而不是用猜的——此處一個錯的名字,會被讀成一個錯的游標。
        /// A cursor reading: the name, plus enough to compare two readings for equality.
        ///
        /// Equality is what the wait loop turns on, so it cannot be identity: `currentSystem`
        /// hands back a COPY, and two reads of the same unchanged cursor are two different
        /// objects. Hot spot and image size are what a copy preserves, and they are also what
        /// separates the cursors this package can set.
        ///
        /// 一次游標讀數:名字,外加「足以比較兩次讀數是否相等」的東西。
        ///
        /// 等待迴圈轉的就是這個相等性,因此它不能是識別:`currentSystem` 交回的是一份**複本**,
        /// 而對同一個未改變的游標讀兩次,會得到兩個不同的物件。熱點與影像尺寸是複本會保留的東西,
        /// 也正是區分「本套件設得出來的那些游標」所需的東西。
        struct CursorReading: Equatable {
            var name: String
            var hotSpot: NSPoint
            var size: NSSize
        }

        static func cursorReading() -> CursorReading {
            // `currentSystem` is what is on SCREEN; `current` is the top of this application's
            // cursor stack and is sticky -- nothing pops it when the pointer leaves the view that
            // set it, so it cannot answer a question about confinement. `currentSystem` can be
            // nil when the app is not entitled to read it, and then there is nothing to report.
            // `currentSystem` 是**螢幕上**的那一個;`current` 是本應用程式游標堆疊的頂端,而且是黏著的
            // ——指標離開那個設定它的 view 時,沒有任何東西把它彈掉——因此它回答不了關於侷限性的問題。
            // 當 app 沒有權限讀取時 `currentSystem` 可能為 nil,那時就沒有東西可回報。
            guard let cursor = NSCursor.currentSystem else {
                return CursorReading(name: "unavailable", hotSpot: .zero, size: .zero)
            }
            return CursorReading(
                name: cursorName(cursor),
                hotSpot: cursor.hotSpot,
                size: cursor.image.size
            )
        }

        static func cursorName(_ cursor: NSCursor) -> String {
            let known: [(String, NSCursor)] = [
                ("arrow", .arrow),
                ("pointingHand", .pointingHand),
                ("crosshair", .crosshair),
                ("text", .iBeam),
                ("resizeHorizontal", .resizeLeftRight),
                ("resizeVertical", .resizeUpDown),
                ("notAllowed", .operationNotAllowed),
                ("openHand", .openHand),
                ("closedHand", .closedHand),
            ]
            for (name, candidate) in known where cursor === candidate { return name }

            // **`currentSystem` hands back a COPY, so identity finds nothing.** Matched on hot
            // spot and image size instead: those are the two things a copy preserves. Ambiguity
            // is reported rather than resolved -- if two system cursors share both, the answer
            // names both, because picking one would be a guess printed as a measurement.
            // **`currentSystem` 交回的是一份**複本**,因此以識別比對什麼也找不到。** 改以熱點與影像
            // 尺寸比對:那是複本會保留的兩樣東西。有歧義時如實回報、不去消解——若兩個系統游標在這兩項上
            // 相同,答案就把兩個都寫出來;挑一個,等於把一個猜測印成一次量測。
            let matches = known.filter {
                $0.1.hotSpot == cursor.hotSpot && $0.1.image.size == cursor.image.size
            }
            .map(\.0)
            if matches.count == 1 { return matches[0] }
            if matches.count > 1 { return "one of \(matches.joined(separator: "/"))" }
            return "other (hotSpot \(cursor.hotSpot), size \(cursor.image.size))"
        }
    }

#endif
