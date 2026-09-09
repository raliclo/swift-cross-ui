import Foundation

/// One row of an action file.
///
/// The verbs and their arguments are described in this module's README. Each
/// case carries only what that verb uses, so an unusable combination -- a
/// `sleep` with a button, a `click` with a key -- cannot be constructed.
public enum InputAction: Equatable, Sendable {
    case move(Point)
    case click(MouseButton, at: Point?)
    case doubleClick(MouseButton, at: Point?)
    case mouseDown(MouseButton, at: Point?)
    case mouseUp(MouseButton, at: Point?)
    case keyDown(Key)
    case keyUp(Key)
    case key(Key)

    /// The point this action names, or `nil` for one that names none.
    ///
    /// Exists so the replay loop can ask what FRAME an action is written
    /// against without re-deriving the switch at each call site. Its one caller
    /// today is the `origin=popover` re-measure in ``Synthesiser/replay(_:in:)``.
    /// 本動作所指定的座標點;不指定座標者為 `nil`。
    ///
    /// 它的存在,是為了讓重放迴圈能問出「這個動作是對哪個**參考框架**寫的」,而不必在每個呼叫點
    /// 重寫一次那個 switch。目前唯一的呼叫端,是 ``Synthesiser/replay(_:in:)`` 中的
    /// `origin=popover` 重新量測。
    public var point: Point? {
        switch self {
            case .move(let point): point
            case .click(_, let point), .doubleClick(_, let point),
                .mouseDown(_, let point), .mouseUp(_, let point): point
            // `scroll` names no point on purpose -- ActionFile:176 rejects an
            // `origin` on a scroll row outright, because scrolling does not move
            // the pointer and a frame there means the writer expected it to.
            // `sleep` names none for the obvious reason.
            // `scroll` 刻意不指定座標——ActionFile:176 會直接拒絕 scroll 列上的 `origin`,因為捲動
            // 並不移動指標,而在該處寫下 frame 即代表撰寫者以為它會移動。`sleep` 不指定座標的理由
            // 顯而易見。
            case .keyDown, .keyUp, .key, .scroll, .sleep: nil
        }
    }

    /// Whether this action is delivered by focus rather than by position.
    ///
    /// A mouse event goes to whatever is on top at the point it names, so a
    /// window raised above the others receives it. A key event ignores the
    /// pointer entirely and goes to whichever window holds focus -- which a
    /// synthesiser cannot always obtain, and on Windows often cannot. Telling
    /// the two apart is what lets a mouse-only file run where a file that types
    /// has to be refused.
    ///
    /// 此動作是依「焦點」而非依「位置」投遞的。
    ///
    /// 滑鼠事件送往其所指定座標上方的視窗，因此被抬升至他人之上的視窗即可收到。按鍵事件則完全
    /// 忽略指標，送往持有焦點的視窗——而 synthesiser 並非總能取得焦點，在 Windows 上更是經常
    /// 取不到。能夠分辨兩者，才使得「只用滑鼠的檔案照常執行、會打字的檔案必須拒絕」成為可能。
    public var needsKeyboardFocus: Bool {
        switch self {
            case .keyDown, .keyUp, .key:
                true
            default:
                false
        }
    }

    /// Turns the wheel, in notches, wherever the pointer currently is.
    ///
    /// Positive `dy` scrolls down and positive `dx` scrolls right, which is the
    /// sign convention of every scroll-delta API involved: GDK's
    /// `GdkScrollEvent` deltas, and Windows' horizontal wheel. Vertical on
    /// Windows is the exception -- there positive means *up* -- and that
    /// inversion is handled in the synthesiser rather than left for a file to
    /// know about.
    ///
    /// It takes no position of its own, deliberately. A wheel event goes to
    /// whatever is under the pointer, so a file that scrolls has to put the
    /// pointer somewhere first, and `move` already does that. Giving `scroll` a
    /// position too would make it possible to write a row that says one place
    /// and scrolls another.
    ///
    /// 以「格」為單位轉動滾輪，作用於指標當下所在之處。
    ///
    /// `dy` 為正代表向下捲動，`dx` 為正代表向右，這是所有相關 scroll-delta API 的符號慣例：
    /// GDK 的 `GdkScrollEvent` delta，以及 Windows 的水平滾輪。Windows 的垂直方向是例外——該處
    /// 正值代表**向上**——這項反轉在 synthesiser 內處理，而非留給動作檔去理解。
    ///
    /// 它刻意不帶自己的位置。滾輪事件會送往指標下方的元件，因此會捲動的檔案必須先把指標移到某處，
    /// 而 `move` 已能做到。若讓 `scroll` 也帶位置，就可能寫出「宣稱在某處、實際捲動另一處」的一列。
    case scroll(dx: Int, dy: Int)

    case sleep(microseconds: Int)
}

/// A position and the origin it is measured from.
public struct Point: Equatable, Sendable {
    /// Logical points, not physical pixels. A file written in pixels is correct
    /// only at the display scale it was written at, and fails by clicking
    /// somewhere plausible rather than by reporting anything.
    public var x: Double
    public var y: Double
    public var origin: Origin

    public init(x: Double, y: Double, origin: Origin = .client) {
        self.x = x
        self.y = y
        self.origin = origin
    }
}

/// Where `0,0` sits.
public enum Origin: String, Equatable, Sendable {
    /// Top-left of the client area, below the title bar and inside the border.
    /// The default, and correct for everything the app draws.
    case client

    /// Top-left of the window frame, including the decorations. For the title
    /// bar and the close, minimise and maximise buttons.
    ///
    /// Less portable than `client`: title bar height varies with platform,
    /// theme and display scale, and under GTK's client-side decorations the
    /// title bar is drawn by the app rather than the window manager, so the two
    /// origins can coincide on one machine and differ on another.
    case frame

    /// Top-left of the popover, menu or modal that is currently open over the
    /// window -- a separate top-level owned by it, not a region inside it.
    ///
    /// Exists because neither of the other two can address one. Task #111
    /// measured this three times on 2026-09-09 with the same action file: the
    /// popover opened BELOW the anchor twice and ABOVE it once, because GTK
    /// flips it when `anchor_y + height` no longer fits inside the work area,
    /// and that depends on where the window landed. `origin=frame` survives the
    /// window moving -- it was chosen for that -- but the side GTK picks and the
    /// window's position are the same variable, so no fixed frame coordinate can
    /// name a point inside the popover on every run.
    ///
    /// **A row with this origin FAILS when no popover is open.** It does not
    /// fall back to `client`, and that is deliberate: a fallback would place the
    /// click somewhere plausible inside the main window, which is exactly the
    /// reading the earlier measurements had to be rescued from -- a miss and a
    /// swallowed event look identical from outside.
    ///
    /// Windows only so far. `Win32Synthesiser` finds the popover as the visible
    /// top-level OWNED by the window being driven and smaller than it, which is
    /// what the replay's own window dump has always printed. The other
    /// synthesisers report it as unavailable rather than guessing.
    ///
    /// 目前開啟於視窗之上的 popover、選單或 modal 的左上角——它是一個被該視窗**擁有的獨立
    /// top-level**,而不是視窗內部的某塊區域。
    ///
    /// 它之所以存在,是因為另外兩者都無法為其定址。任務 #111 於 2026-09-09 以同一個動作檔量了三次:
    /// popover 有兩次開在錨點**下方**、一次開在**上方**,因為當 `錨點y + 高度` 容不下工作區時 GTK
    /// 會把它翻面,而那取決於視窗落在哪裡。`origin=frame` 撐得住視窗移動——選它正是為此——但
    /// **GTK 選哪一側與視窗位置是同一個變數**,因此沒有任何固定的 frame 座標能在每一次執行中都指到
    /// popover 內部的某個點。
    ///
    /// **沒有 popover 開著時,使用本原點的資料列會失敗。** 它**不會**退回 `client`,而那是刻意的:
    /// 退回會把點擊放在主視窗內某個看似合理的位置,而那正是先前的量測必須被搶救出來的那種解讀
    /// ——從外部看,「沒打中」與「被吃掉」一模一樣。
    ///
    /// 目前僅 Windows。`Win32Synthesiser` 將 popover 認定為「被所驅動視窗擁有、且比它小的可見
    /// top-level」,那正是重放自己的視窗傾印一直都在印的東西。其他 synthesiser 回報「無法取得」,
    /// 而不是用猜的。
    case popover
}

public enum MouseButton: String, Equatable, Sendable {
    case left
    case right
    case middle
}

/// A key, named as macOS names it.
///
/// The names are Carbon's `kVK_*` constants from `HIToolbox/Events.h` -- the
/// codes `NSEvent.keyCode` returns -- with the `kVK_` prefix and the `ANSI_`
/// infix dropped and the first letter lowercased.
///
/// macOS is the source rather than a set invented here, or either of the two
/// platforms this runs on. It is a real specification with documentation, so an
/// argument about what a name means has somewhere to go; it is complete,
/// including the keypad and the right-hand modifiers, which an invented list
/// would have discovered it needed later; and it belongs to the third backend,
/// so neither Linux nor Windows spelling wins by default.
///
/// Two Mac assumptions come with the names and are not accidents of this
/// implementation:
///
/// - ``delete`` is Backspace. ``forwardDelete`` is the key usually labelled
///   Delete elsewhere.
/// - ``command`` is the physical key in that position -- the Windows key, or
///   Super -- not "whatever this platform uses for shortcuts". A Mac shortcut
///   is Command-based where the same shortcut is Control-based elsewhere, so an
///   action file exercising a shortcut cannot be identical across platforms
///   even though its key names are.
public enum Key: String, Equatable, Sendable, CaseIterable {
    case a, b, c, d, e, f, g, h, i, j, k, l, m
    case n, o, p, q, r, s, t, u, v, w, x, y, z

    case zero = "0", one = "1", two = "2", three = "3", four = "4"
    case five = "5", six = "6", seven = "7", eight = "8", nine = "9"

    case delete, forwardDelete
    case escape, space, tab, `return`

    case leftArrow, rightArrow, upArrow, downArrow
    case home, end, pageUp, pageDown

    case shift, control, option, command
    case rightShift, rightControl, rightOption, rightCommand
    case capsLock, function

    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10
    case f11, f12, f13, f14, f15, f16, f17, f18, f19, f20

    case keypad0, keypad1, keypad2, keypad3, keypad4
    case keypad5, keypad6, keypad7, keypad8, keypad9
    case keypadDecimal, keypadPlus, keypadMinus
    case keypadMultiply, keypadDivide, keypadEnter
    case keypadEquals, keypadClear
}
