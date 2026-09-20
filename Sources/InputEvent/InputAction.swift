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

    /// A press held for `micros`, which is how a touch screen raises a context
    /// menu.
    ///
    /// **Its own verb rather than `mousedown`, `sleep`, `mouseup`, because that
    /// sequence does not express it.** The iOS runner turns a down/up pair into
    /// `press(forDuration: 0.1, thenDragTo:)` -- a fixed tenth of a second,
    /// whatever `sleep` rows sit between them, because a `sleep` pauses the
    /// REPLAY and not the finger. A context menu needs about half a second, so
    /// the duration has to be part of the action.
    ///
    /// On the desktop synthesisers this is `unsupported`: a long press is not
    /// how a context menu is raised there, and `click ... right` is. A verb that
    /// quietly became a right-click on three platforms would hide exactly the
    /// difference a cross-platform test is looking for.
    ///
    /// 一次持續 `micros` 的按壓——觸控螢幕就是這樣叫出右鍵選單的。
    ///
    /// **它自成一個動作,而不是 `mousedown`、`sleep`、`mouseup` 三連,因為那個序列表達不了它。**
    /// iOS runner 會把一組 down/up 轉成 `press(forDuration: 0.1, thenDragTo:)`——固定的十分之一秒,
    /// 不論中間夾了幾列 `sleep`;因為 `sleep` 暫停的是**重放**,不是那根手指。一個右鍵選單需要大約
    /// 半秒,因此那個時長必須是這個動作的一部分。
    ///
    /// 在桌面的各 synthesiser 上,這是 `unsupported`:在那裡,長按不是叫出右鍵選單的方式,
    /// `click ... right` 才是。一個「在三個平台上靜默變成右鍵」的動作,會藏起跨平台測試正要找的那個差異。
    case longPress(at: Point?, micros: Int)
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
            case .longPress(let point, _): point
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
            // `focus` names no point either: it selects the frame of reference
            // that later points are written against, rather than being written
            // against one itself.
            // `focus` 同樣不指定座標：它**選定**其後座標所依據的參考框架，而不是自己依據某個框架。
            // `pinch` and `rotate` name no point for the same reason `scroll`
            // does not: their two numeric columns are the gesture's own
            // parameters, not a position.
            // `pinch` 與 `rotate` 不指定座標,理由與 `scroll` 相同:它們的兩個數值欄位是這個手勢
            // 自己的參數,不是位置。
            case .keyDown, .keyUp, .key, .scroll, .sleep, .focus, .pinch, .rotate: nil
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

    /// A two-finger pinch, as a scale and a speed.
    ///
    /// **Percentages rather than fractions, because the format's numeric columns
    /// are integers.** `x` is the scale times a hundred -- 200 doubles, 50
    /// halves -- and `y` is the velocity times a hundred, with 0 meaning "the
    /// implementation's own default". Same trick `scroll` uses when it reads its
    /// two columns as wheel notches instead of a position: there is no spare
    /// column to add, and a documented reinterpretation is cheaper than a format
    /// change every platform has to learn.
    ///
    /// 一次雙指縮放,以「比例」與「速度」表示。
    ///
    /// **用百分比而非小數,因為這個格式的數值欄位是整數。** `x` 是比例乘以一百——200 放大兩倍、
    /// 50 縮小一半——而 `y` 是速度乘以一百,0 代表「由實作挑它自己的預設」。與 `scroll` 把兩個欄位
    /// 讀成滾輪格數而非位置,是同一個手法:沒有多餘的欄位可加,而一個寫明的重新詮釋,
    /// 比一次「每個平台都得重學」的格式改動便宜。
    case pinch(scalePercent: Int, velocityPercent: Int)

    /// A two-finger rotation, in degrees.
    ///
    /// `x` is the angle, positive clockwise; `y` is degrees per second, 0 for
    /// the implementation's default. Degrees rather than radians because a file
    /// is written by a person and read back by one.
    ///
    /// 一次雙指旋轉,以「度」表示。
    ///
    /// `x` 是角度,正值為順時針;`y` 是每秒幾度,0 代表由實作挑預設。用度而不用弧度,
    /// 因為這種檔案是人寫的,也是人讀回來的。
    case rotate(degrees: Int, degreesPerSecond: Int)

    case sleep(microseconds: Int)

    /// Brings the named window to the front, so that later coordinates resolve
    /// against it.
    ///
    /// **Every other action in this file is written against ONE window, and
    /// before this there was no way to name a second.** `frame` and `client`
    /// both resolve against whichever window is focused; `popover` is Windows
    /// only and means a popover, not a window. So an app that opens a second
    /// window -- a settings window, a document window -- could be photographed
    /// but not driven: P60's settings window opened on AppKit and the button
    /// inside it was unreachable from a file.
    ///
    /// Nothing else had to change to make the coordinates follow. `replay`
    /// already re-measures the geometry when `currentWindowIdentity()` reports a
    /// different window, which it does the moment focus moves -- so this action
    /// only has to move the focus and the existing machinery does the rest.
    ///
    /// The title is matched exactly. A prefix or fuzzy match would silently
    /// select the wrong window in an app whose windows share a prefix, and
    /// "wrong window" is precisely the failure this action exists to fix.
    ///
    /// 把指名的視窗帶到前景，好讓其後的座標相對於它解析。
    ///
    /// **本檔中其他每一個動作都是針對「單一視窗」而寫的，而在此之前沒有任何方式能指名第二個。**
    /// `frame` 與 `client` 都相對於「當下取得焦點的那個視窗」解析；`popover` 僅限 Windows，且它指的是
    /// popover、不是視窗。因此一個會開出第二個視窗的 app——設定視窗、文件視窗——拍得到卻驅動不了：
    /// P60 的設定視窗在 AppKit 上開得出來，而其中的按鈕從檔案裡構不著。
    ///
    /// 為了讓座標跟著走，其他什麼都不必改。當 `currentWindowIdentity()` 回報視窗不同時，`replay`
    /// 本來就會重新量測 geometry，而焦點一移動它就會如此——因此這個動作只需要移動焦點，其餘由既有的
    /// 機制完成。
    ///
    /// 標題採**完全相符**。前綴或模糊比對會在「視窗標題共用前綴」的 app 中靜默選中錯誤的視窗，
    /// 而「選錯視窗」正是這個動作存在所要修正的失敗。
    case focus(window: String)
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
    case a
    case b
    case c
    case d
    case e
    case f
    case g
    case h
    case i
    case j
    case k
    case l
    case m
    case n
    case o
    case p
    case q
    case r
    case s
    case t
    case u
    case v
    case w
    case x
    case y
    case z

    case zero = "0"
    case one = "1"
    case two = "2"
    case three = "3"
    case four = "4"
    case five = "5", six = "6", seven = "7", eight = "8", nine = "9"

    case delete, forwardDelete
    case escape
    case space
    case tab
    case `return`

    case leftArrow
    case rightArrow
    case upArrow
    case downArrow
    case home
    case end
    case pageUp
    case pageDown

    case shift
    case control
    case option
    case command
    case rightShift
    case rightControl
    case rightOption
    case rightCommand
    case capsLock
    case function

    case f1
    case f2
    case f3
    case f4
    case f5
    case f6
    case f7
    case f8
    case f9
    case f10
    case f11
    case f12
    case f13
    case f14
    case f15
    case f16
    case f17
    case f18
    case f19
    case f20

    case keypad0
    case keypad1
    case keypad2
    case keypad3
    case keypad4
    case keypad5
    case keypad6
    case keypad7
    case keypad8
    case keypad9
    case keypadDecimal
    case keypadPlus
    case keypadMinus
    case keypadMultiply
    case keypadDivide
    case keypadEnter
    case keypadEquals
    case keypadClear
}
