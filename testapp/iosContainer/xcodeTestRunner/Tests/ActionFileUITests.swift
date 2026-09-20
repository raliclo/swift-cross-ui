import Foundation
import XCTest

final class ActionFileUITests: XCTestCase {
    private let bundleIdentifier = "dev.swiftcrossui.testapp.debugTarget"

    /// How far one notch of the wheel drags the content.
    ///
    /// 40 points, which is what the GTK and AppKit synthesisers deliver per
    /// notch, so a file written for one platform scrolls a comparable distance
    /// on this one. It is a convention rather than a measurement -- a touch
    /// screen has no notch to measure -- and it is here rather than inline so
    /// there is one place to change it when a file needs a different feel.
    ///
    /// 一格滾輪帶動內容的距離。
    ///
    /// 40 點，與 GTK 及 AppKit 的 synthesiser 每一格所送出的距離相同，因此為某個平台撰寫的檔案在
    /// 此處會捲動相當的距離。這是一個約定而非量測值——觸控螢幕上沒有「一格」可量——並且放在此處而非
    /// 內嵌，使得日後若有檔案需要不同手感時，只有一個地方要改。
    private static let pointsPerNotch: CGFloat = 40

    /// One tree dump per run; see `gestureTarget(at:in:)`.
    /// 一次執行只印一棵樹;見 `gestureTarget(at:in:)`。
    private var didDumpTree = false

    /// The modifier a `keydown`/`keyup` names, or `nil` if it is not a modifier.
    ///
    /// The left/right distinction the format carries is dropped: XCUITest has
    /// one flag per modifier and no side. Dropped rather than rejected, because
    /// a file saying `rightCommand` means "Command is held" on every platform
    /// and only macOS can tell the two apart -- refusing it would fail files
    /// that are correct everywhere else.
    ///
    /// `command` is Command here, matching `EventModifiers.command` and the
    /// AppKit synthesiser.
    ///
    /// 某個 `keydown`/`keyup` 所指名的 modifier;若它不是 modifier 則為 `nil`。
    ///
    /// 格式中帶有的左右之分在此被捨棄:XCUITest 每個 modifier 只有一個旗標,沒有左右。是**捨棄**而
    /// 不是拒絕,因為一個寫著 `rightCommand` 的檔案,在每個平台上的意思都是「Command 被按著」,而
    /// 只有 macOS 分得出兩者——拒絕它會讓一份在別處都正確的檔案失敗。
    ///
    /// `command` 在此就是 Command,與 `EventModifiers.command` 及 AppKit synthesiser 一致。
    private static func modifierFlag(for key: String) -> XCUIElement.KeyModifierFlags? {
        switch key {
            case "command", "rightCommand": return .command
            case "shift", "rightShift": return .shift
            case "option", "rightOption": return .option
            case "control", "rightControl": return .control
            case "capsLock": return .capsLock
            default: return nil
        }
    }

    /// What `typeKey` should be given for a `key` action.
    ///
    /// A single character goes through as itself; the named keys map to
    /// `XCUIKeyboardKey`. `nil` means the format names a key XCUITest has no
    /// constant for, and the caller throws rather than substituting one --
    /// typing the wrong key is worse than refusing.
    ///
    /// `delete` is Backspace, which is Mac's meaning and the format's; the
    /// README warns that this surprises people who learned the names elsewhere,
    /// and getting it backwards here would erase the wrong character silently.
    ///
    /// 一個 `key` 動作該交給 `typeKey` 什麼。
    ///
    /// 單一字元原樣通過;具名按鍵映射到 `XCUIKeyboardKey`。`nil` 代表格式指名了一個 XCUITest 沒有
    /// 常數的按鍵,而呼叫端會 throw、不會拿另一個頂替——打錯鍵比拒絕更糟。
    ///
    /// `delete` 是 Backspace,那是 Mac 的語意、也是本格式的語意;README 警告過這會讓在別處學過這些
    /// 名字的人意外,而在此處弄反,會**靜默地**刪掉錯誤的字元。
    private static func typedKey(for key: String) -> String? {
        if key.count == 1 { return key }
        switch key {
            case "return": return XCUIKeyboardKey.return.rawValue
            case "tab": return XCUIKeyboardKey.tab.rawValue
            case "space": return XCUIKeyboardKey.space.rawValue
            case "escape": return XCUIKeyboardKey.escape.rawValue
            case "delete": return XCUIKeyboardKey.delete.rawValue
            case "forwardDelete": return XCUIKeyboardKey.forwardDelete.rawValue
            case "leftArrow": return XCUIKeyboardKey.leftArrow.rawValue
            case "rightArrow": return XCUIKeyboardKey.rightArrow.rawValue
            case "upArrow": return XCUIKeyboardKey.upArrow.rawValue
            case "downArrow": return XCUIKeyboardKey.downArrow.rawValue
            case "home": return XCUIKeyboardKey.home.rawValue
            case "end": return XCUIKeyboardKey.end.rawValue
            case "pageUp": return XCUIKeyboardKey.pageUp.rawValue
            case "pageDown": return XCUIKeyboardKey.pageDown.rawValue
            default: return nil
        }
    }

    /// Names the held modifiers for the log line.
    /// 為紀錄行寫出目前按著的 modifier。
    private static func describe(_ flags: XCUIElement.KeyModifierFlags) -> String {
        var names: [String] = []
        if flags.contains(.command) { names.append("command") }
        if flags.contains(.shift) { names.append("shift") }
        if flags.contains(.option) { names.append("option") }
        if flags.contains(.control) { names.append("control") }
        if flags.contains(.capsLock) { names.append("capsLock") }
        return names.isEmpty ? "none" : names.joined(separator: "+")
    }

    func testActionFile() throws {
        guard let path = ProcessInfo.processInfo.environment["IOS_ACTION_FILE"] else {
            XCTFail("IOS_ACTION_FILE is required")
            return
        }

        let app = XCUIApplication(bundleIdentifier: bundleIdentifier)
        let actions = try ActionFile.load(at: path)
        var pointer: XCUICoordinate?
        var dragStart: XCUICoordinate?
        /// Modifiers currently held by `keydown`, spent by the next `key`.
        /// 目前由 `keydown` 按住、將被下一個 `key` 花掉的 modifier。
        var heldModifiers: XCUIElement.KeyModifierFlags = []

        // Say what is about to be replayed, and afterwards say that it was.
        //
        // Every other platform ends a replay with `-actionfile: replayed <name>`
        // on stderr, and a run is judged on that line. iOS had nothing: the
        // replay happens in this XCUITest process, not in the app, so the app's
        // unified log never mentions it. Measured 2026-09-07 -- of the 47 iOS
        // run logs in testapp/output, **none** contains a completed-replay line,
        // which is why the coverage matrix carries iOS as `unverified` rather
        // than `pass` for all 45 apps.
        //
        // The count is here because a file that parsed to zero actions replays
        // successfully and does nothing, and those two are the same line
        // otherwise. `stderr` rather than `print`, so it lands beside
        // xcodebuild's own output whichever way the runner is invoked.
        //
        // 先說出將要重放什麼,之後再說它確實被重放了。
        //
        // 其他每一個平台的重放都以 stderr 上的 `-actionfile: replayed <名稱>` 作結,而一次執行正是
        // 依那一行判定的。iOS 上什麼都沒有:重放發生在這個 XCUITest 行程中,而非在 app 內,因此
        // app 的 unified log 從不提及它。2026-09-07 實測——testapp/output 中的 47 份 iOS 執行日誌
        // 裡,**沒有任何一份**含有「重放完成」的行,這正是涵蓋矩陣把 iOS 的全部 45 支記為
        // `unverified` 而非 `pass` 的原因。
        //
        // 此處輸出動作數量,是因為「一個解析出零個動作的檔案」會成功重放且什麼都不做,而若不寫出數量,
        // 那兩者就是同一行字。使用 `stderr` 而非 `print`,好讓它與 xcodebuild 自身的輸出並排,
        // 無論這個 runner 是以哪種方式被呼叫的。
        let fileName = (path as NSString).lastPathComponent
        FileHandle.standardError.write(
            Data("-actionfile: replaying \(fileName) with \(actions.count) actions\n".utf8)
        )

        // `IOS_DUMP_TREE=1` prints the accessibility tree before anything is
        // replayed. **This is the only EXTERNAL view of that tree on iOS.**
        //
        // macOS has `ax_dump`, which reads the real AX tree of a running app
        // from outside it, and Android has `uiautomator dump`. iOS had neither:
        // P69's #123 evidence was the app describing itself, which is an
        // in-process walk of the views that FEED the tree -- and a label set on
        // a wrapper a screen reader never visits reads as correct from there.
        // XCUITest resolves the same tree an assistive technology does, so this
        // is the missing third probe rather than a convenience.
        //
        // Off by default because it is long: P57 holds thousands of rows.
        //
        // `IOS_DUMP_TREE=1` 會在重放任何東西之前印出無障礙樹。**這是 iOS 上對那棵樹唯一的外部視角。**
        //
        // macOS 有 `ax_dump`,它從外部讀取一支執行中 app 的真正 AX 樹;Android 有 `uiautomator dump`。
        // iOS 兩者都沒有:P69 為 #123 提出的證據是「app 自己描述自己」,那是對「餵養那棵樹的 view」
        // 所做的行程內走訪——而一個設在螢幕閱讀器從不造訪之包裝上的標籤,從那裡看起來是正確的。
        // XCUITest 解析的是與輔助技術相同的那棵樹,因此這是缺席的第三支探針,而不是便利功能。
        //
        // 預設關閉,因為它很長:P57 有數千列。
        if ProcessInfo.processInfo.environment["IOS_DUMP_TREE"] == "1", !didDumpTree {
            didDumpTree = true
            FileHandle.standardError.write(
                Data("-actionfile: element tree before replay:\n\(app.debugDescription)\n".utf8)
            )
        }

        for action in actions {
            switch action.kind {
            case "sleep":
                Thread.sleep(forTimeInterval: action.microseconds / 1_000_000)
            case "move":
                pointer = try coordinate(for: action, in: app)
            case "click":
                let target = try coordinateIfPresent(for: action, current: pointer, in: app)
                target.tap()
                pointer = target
            case "longpress":
                // **The one verb that exists FOR this runner.** A context menu on
                // a touch screen is raised by holding, and the down/up pair above
                // cannot express it: `mouseup` presses for a fixed 0.1s whatever
                // `sleep` rows sit between, because a `sleep` pauses the replay
                // and not the finger. The desktop synthesisers refuse this verb
                // rather than turning it into a right-click, so a file that uses
                // it says plainly which platform it is for.
                //
                // **唯一為這個 runner 而存在的動作。** 觸控螢幕上的右鍵選單是靠「按住」叫出來的,
                // 而上面那組 down/up 表達不了它:`mouseup` 固定按壓 0.1 秒,不論中間夾了幾列 `sleep`
                // ——因為 `sleep` 暫停的是重放、不是那根手指。桌面的各 synthesiser 會**拒絕**這個動作,
                // 而不是把它變成右鍵,因此一份用到它的檔案,會明白地說出它是為哪個平台寫的。
                let target = try coordinateIfPresent(for: action, current: pointer, in: app)
                target.press(forDuration: action.microseconds / 1_000_000)
                pointer = target
            case "doubleclick":
                let target = try coordinateIfPresent(for: action, current: pointer, in: app)
                target.doubleTap()
                pointer = target
            case "mousedown":
                let target = try coordinateIfPresent(for: action, current: pointer, in: app)
                pointer = target
                dragStart = target
            case "mouseup":
                let target = try coordinateIfPresent(for: action, current: pointer, in: app)
                if let start = dragStart {
                    start.press(forDuration: 0.1, thenDragTo: target)
                    dragStart = nil
                } else {
                    target.tap()
                }
                pointer = target
            case "scroll":
                // A wheel notch becomes a drag, because a touch screen has no
                // wheel.
                //
                // The sign inverts, and that is the part to get right. In the
                // action-file format a positive `dy` scrolls *down* -- the
                // viewport moves further down the content. A finger does that by
                // moving *up*. Same for `dx`: scrolling right means dragging
                // left. Getting this backwards produces a scroll that works,
                // moves the right distance, and goes the wrong way, which reads
                // as the app scrolling oddly rather than as the runner being
                // wrong.
                //
                // Until this existed the runner threw `unsupported` on every
                // scroll row, so P8, P27 and P38 -- the three apps whose whole
                // subject is scrolling -- had no iOS action file at all.
                //
                // 一格滾輪變成一次拖曳，因為觸控螢幕沒有滾輪。
                //
                // 符號要反過來，而那正是必須弄對的地方。在動作檔格式中，`dy` 為正代表向**下**捲動
                // ——視口沿著內容往下移。手指要達成這件事，是往**上**移動。`dx` 亦然：向右捲動意味著
                // 向左拖曳。若把方向弄反，會得到一個「能運作、距離正確、方向相反」的捲動，那讀起來
                // 像是 app 的捲動行為古怪，而不像是 runner 寫錯了。
                //
                // 在此之前，runner 對每一列 scroll 都會拋出 `unsupported`，因此 P8、P27 與 P38
                // ——那三支整個主題就是捲動的 app——在 iOS 上完全沒有動作檔。
                let origin = pointer ?? app.windows.firstMatch.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
                )
                let destination = origin.withOffset(CGVector(
                    dx: -action.x * Self.pointsPerNotch,
                    dy: -action.y * Self.pointsPerNotch
                ))
                // A brief press before the drag, as the mouseup case does. A
                // drag with no press is delivered as a flick, whose momentum
                // carries the content past where the row asked for and leaves
                // the next row measuring a position nobody chose.
                // 拖曳前先短暫按住，與 mouseup 的處理相同。沒有按住的拖曳會被視為快速滑動，其慣性
                // 會把內容帶過該列所要求的位置，使下一列量到的是一個沒有人選擇過的位置。
                origin.press(forDuration: 0.05, thenDragTo: destination)
            case "pinch", "rotate":
                // **XCUITest has these natively, which is why iOS is the one
                // platform where this costs nothing.** `pinch(withScale:
                // velocity:)` and `rotate(_:withVelocity:)` synthesise a real
                // two-contact gesture; AppKit publishes no initialiser for a
                // magnify or rotate NSEvent, and X11's XTEST has no gesture
                // channel at all, so both of those refuse with a reason.
                //
                // **Aimed by the preceding `move` row, not by the window.**
                // `x` and `y` on these two rows are the gesture's own
                // parameters, so the aim has to come from somewhere else, and
                // the runner already carries a pointer that `move` sets. The
                // first driven run of P65 sent both gestures to the window's
                // centre: rotate registered (the centre sat on the rotate
                // panel) and the pinch did not, which reads exactly like "iOS
                // cannot pinch". A gesture recogniser lives on one view; a
                // gesture aimed at the middle of the window reaches whichever
                // view happens to be there. See `gestureTarget(at:in:)`.
                //
                // **由前一列 `move` 瞄準,而不是由視窗瞄準。** 這兩列的 `x` 與 `y` 是手勢自己的參數,
                // 因此瞄準必須來自別處——而 runner 本來就帶著一個由 `move` 設定的指標。P65 第一次被
                // 驅動時,兩個手勢都送到視窗中心:旋轉登記了(中心正好落在旋轉那一格),縮放沒有,
                // 而那讀起來完全像是「iOS 無法縮放」。一個手勢辨識器只長在一個 view 上;一個瞄準
                // 視窗正中央的手勢,到達的是那裡剛好是誰。見 `gestureTarget(at:in:)`。
                //
                // **XCUITest 原生就有這兩者,而那正是 iOS 成為「這件事零成本」的唯一平台的原因。**
                // `pinch(withScale:velocity:)` 與 `rotate(_:withVelocity:)` 會合成一次真正的
                // 雙接觸點手勢;AppKit 沒有公開任何能造出 magnify 或 rotate `NSEvent` 的初始化式,
                // 而 X11 的 XTEST 根本沒有手勢通道,因此那兩者都以理由拒絕。
                //
                // 作用在視窗上而非某個定位到的元素:這些手勢講的是「它們底下的那個 view」,
                // 而動作檔格式不帶元素身分——此處它的 `x` 與 `y` 是這個手勢自己的參數,不是位置。
                // 見 `InputAction.pinch`。
                let target = gestureTarget(at: pointer, in: app)
                if action.kind == "pinch" {
                    let scale = CGFloat(action.x) / 100
                    let velocity = action.y == 0 ? 1 : CGFloat(action.y) / 100
                    target.pinch(withScale: scale, velocity: velocity)
                } else {
                    let radians = CGFloat(action.x) * .pi / 180
                    let velocity =
                        action.y == 0 ? 1 : CGFloat(action.y) * .pi / 180
                    target.rotate(radians, withVelocity: velocity)
                }
            case "keydown":
                // A MODIFIER is held; anything else cannot be.
                //
                // XCUITest has no press-and-hold for an ordinary key: the unit
                // is `typeKey(_:modifierFlags:)`, one press with whatever
                // modifiers are down. So `keydown command` accumulates a flag
                // and `key s` spends it. `keydown s` has no expression here and
                // throws rather than quietly typing an `s` -- a held key that
                // silently became a tap is the kind of difference a test is
                // supposed to notice.
                //
                // **按住的必須是 modifier;其他任何鍵都不行。**
                //
                // XCUITest 沒有「按住一個普通按鍵」這種動作:它的單位是
                // `typeKey(_:modifierFlags:)`——一次按下,連同當時按著的那些 modifier。因此
                // `keydown command` 累積一個旗標,而 `key s` 把它花掉。`keydown s` 在此處無法表達,
                // 於是 throw,而不是安靜地打出一個 `s`——一個「被靜默變成單擊的長按」,正是測試本該
                // 察覺的那種差別。
                guard let flag = Self.modifierFlag(for: action.key) else {
                    throw ActionFileError.unsupported(
                        "keydown \(action.key) (only modifiers can be held on iOS)",
                        action.line
                    )
                }
                heldModifiers.insert(flag)
            case "keyup":
                guard let flag = Self.modifierFlag(for: action.key) else {
                    throw ActionFileError.unsupported(
                        "keyup \(action.key) (only modifiers can be held on iOS)",
                        action.line
                    )
                }
                heldModifiers.remove(flag)
            case "key":
                guard let typed = Self.typedKey(for: action.key) else {
                    throw ActionFileError.unsupported(
                        "key \(action.key) (no XCUIKeyboardKey for it)",
                        action.line
                    )
                }
                // Reported before it is sent, and with the modifiers spelled
                // out, because a shortcut that does nothing is otherwise
                // indistinguishable from one that was never sent -- the same
                // reason the coordinate line above exists.
                // 在送出之前先回報,而且把 modifier 明列出來;否則「一個什麼都沒做的快捷鍵」與
                // 「一個從未被送出的快捷鍵」無從分辨——與上方那行座標紀錄存在的理由相同。
                FileHandle.standardError.write(
                    Data(
                        ("-actionfile: line \(action.line) key '\(action.key)' "
                            + "modifiers=\(Self.describe(heldModifiers))\n").utf8
                    )
                )
                app.typeKey(typed, modifierFlags: heldModifiers)
            default:
                throw ActionFileError.unsupported(action.kind, action.line)
            }
        }

        FileHandle.standardError.write(
            Data("-actionfile: replayed \(fileName)\n".utf8)
        )
    }

    /// The element a pinch or rotate should act on: the smallest one whose
    /// frame contains the point the last `move` row set.
    ///
    /// `XCUIElement.pinch` and `.rotate` act on an element and there is no
    /// coordinate-based form of either, so "aim at a point" has to become "find
    /// what is at that point". Smallest-containing rather than first-containing:
    /// the window contains every point, and it is always in the list.
    ///
    /// **Every candidate is printed, not just the winner.** A pinch that lands
    /// on the wrong view and a pinch the view ignored produce the same
    /// screenshot; so does a point that matched nothing and fell back to the
    /// window. Those three need different fixes and the log is the only thing
    /// that separates them.
    ///
    /// 一次 pinch 或 rotate 該作用的元素:框住「前一列 `move` 所設之點」的元素中最小的那一個。
    ///
    /// `XCUIElement.pinch` 與 `.rotate` 作用在元素上,而兩者都沒有以座標為準的形式,因此
    /// 「瞄準一個點」必須變成「找出那個點上是什麼」。取最小而非取第一個:視窗框住每一個點,
    /// 而它永遠在清單裡。
    ///
    /// **每一個候選都印出來,不只印出勝出者。** 一次落在錯誤 view 上的縮放,與一次被該 view 忽略的
    /// 縮放,產生同一張截圖;一個什麼都沒對上、於是退回視窗的點也是。那三者要修的東西不同,
    /// 而這份 log 是唯一能把它們分開的東西。
    private func gestureTarget(
        at pointer: XCUICoordinate?,
        in app: XCUIApplication
    ) -> XCUIElement {
        let window = app.windows.firstMatch
        guard let pointer else {
            FileHandle.standardError.write(
                Data("-actionfile: gesture has no preceding move row; aiming at the window\n".utf8)
            )
            return window
        }

        // The whole tree, once, when a gesture is first aimed.
        //
        // The flat candidate list below says what contains the point; it does
        // not say what those elements ARE, and the first aim of P65 produced a
        // list that matched nothing in the screenshot -- eleven copies of a
        // 500x463 frame in a 440-point window. Guessing at that from the
        // numbers is how the last two runs were spent.
        //
        // 整棵樹,只印一次,在第一個手勢被瞄準時。
        //
        // 下方那份扁平的候選清單只說「什麼框住了這個點」,它不說那些元素**是什麼**;而 P65 的第一次
        // 瞄準產生了一份與截圖對不起來的清單——在一個 440 點寬的視窗裡出現十一個 500x463 的框。
        // 從那些數字去猜它是什麼,正是前兩次執行所花掉的東西。
        if !didDumpTree {
            didDumpTree = true
            FileHandle.standardError.write(
                Data("-actionfile: element tree at first gesture:\n\(app.debugDescription)\n".utf8)
            )
        }

        let point = pointer.screenPoint
        let windowFrame = window.frame
        var best: XCUIElement?
        var bestArea = CGFloat.greatestFiniteMagnitude
        var report = "-actionfile: gesture aimed at \(point)\n"

        // **Two coordinate spaces show up in one tree, and only one of them is
        // the screen's.** P65's first aim listed eleven frames of 500x463 with
        // x = -36 inside a 440-point window, and the panel actually under the
        // point was not in the list at all; the same query after one delivered
        // event listed the panel at its screen position. Those out-of-window
        // frames are a layout the app has already left. An element that is not
        // inside the window cannot be what is under a point on the screen, so
        // they are dropped and the query is retried -- the retry is what waits
        // for the tree to catch up, and `attempt` in the log says how long it
        // took.
        //
        // **一棵樹裡會同時出現兩個座標系,而其中只有一個是螢幕的。** P65 的第一次瞄準,在一個 440 點寬的
        // 視窗裡列出了十一個 x = -36 的 500x463 框,而真正位於該點下方的那一格根本不在清單裡;同一個查詢
        // 在一個事件送出之後,則把那一格列在它的螢幕位置上。那些落在視窗外的框,是這個 app 已經離開的
        // 一份佈局。一個不在視窗內的元素,不可能是螢幕上某一點底下的東西——因此它們被丟棄,並重試查詢;
        // 等待那棵樹跟上的正是這個重試,而 log 裡的 `attempt` 說出它花了多久。
        for attempt in 1...2 {
            best = nil
            bestArea = .greatestFiniteMagnitude
            report += "-actionfile:   attempt \(attempt)\n"

            for element in app.descendants(matching: .any)
                .allElementsBoundByAccessibilityElement
            {
                let frame = element.frame
                guard frame.width > 0, frame.height > 0, frame.contains(point) else { continue }
                let inWindow = windowFrame.contains(frame)
                report += "-actionfile:   candidate \(element.elementType.rawValue) "
                    + "'\(element.identifier)' '\(element.label)' \(frame)"
                    + (inWindow ? "\n" : " OUTSIDE THE WINDOW -- dropped\n")
                guard inWindow else { continue }
                let area = frame.width * frame.height
                if area < bestArea {
                    bestArea = area
                    best = element
                }
            }

            // A container is not an aim. The window, the application and the
            // scroll view all contain every point inside them, so landing on
            // one of those means nothing that was actually drawn at the point
            // reported a usable frame -- which is the state above, not a
            // result. Anything else is a view that is really there.
            //
            // 一個容器不是一次瞄準。視窗、application 與 scroll view 框住其中的每一個點,因此落在
            // 那三者之一上,代表「真正畫在該點上的東西」沒有任何一個回報得出可用的框——那是上面所說的
            // 那個狀態,不是一個結果。其餘任何東西,都是一個真的在那裡的 view。
            let containers: [XCUIElement.ElementType] = [.window, .application, .scrollView]
            if let best, !containers.contains(best.elementType) { break }

            // **Waiting does not fix this, and that was measured rather than
            // assumed.** Eight attempts with `activate()` between them -- four
            // seconds -- left the tree exactly as it was, and the aim still
            // landed on the scroll view. One delivered tap fixed it instantly:
            // the query right after it put the panel at {{0, 332}, {267, 62}},
            // the position the screenshot shows. So the retry is one, for a
            // tree that is merely a frame behind, and the line below says what
            // to do when it is the other thing.
            //
            // **等待修不好這件事,而這是量出來的、不是假設的。** 八次嘗試、其間穿插 `activate()`
            // ——共四秒——那棵樹一動也沒動,瞄準依然落在 scroll view 上。而一次真正送達的輕點立刻
            // 修好了它:緊接其後的查詢把那一格放在 {{0, 332}, {267, 62}},也就是截圖所顯示的位置。
            // 因此重試只留一次,給那些只慢了一幀的樹;而下面那一行,說出遇到另一種情況時該做什麼。
            app.activate()
            Thread.sleep(forTimeInterval: 0.5)
        }

        if let best, [XCUIElement.ElementType.window, .application, .scrollView]
            .contains(best.elementType)
        {
            report += "-actionfile:   only a container is at that point. The app has not "
                + "received an event yet, so its accessibility frames are still in an "
                + "unconverted space. Put one delivered event -- a `click` row on inert "
                + "background -- before the first gesture row.\n"
        }

        if let best {
            report += "-actionfile:   chose \(best.elementType.rawValue) "
                + "'\(best.identifier)' '\(best.label)' \(best.frame)\n"
        } else {
            report += "-actionfile:   nothing inside the window contains that point; "
                + "aiming at the window\n"
        }
        FileHandle.standardError.write(Data(report.utf8))
        return best ?? window
    }

    private func coordinate(
        for action: Action,
        in app: XCUIApplication
    ) throws -> XCUICoordinate {
        guard action.origin != "frame" else {
            throw ActionFileError.unsupported("frame origin on iOS", action.line)
        }

        let window = app.windows.firstMatch
        let frame = window.frame
        guard frame.width > 0, frame.height > 0 else {
            throw ActionFileError.invalidCoordinate(action.line)
        }

        // Says which window it resolved against and where the point landed.
        //
        // **Without this the failure is silent in both directions**: a tap that
        // misses looks exactly like a tap the app ignored, and the wrong window
        // looks exactly like wrong coordinates in the file. Both were live
        // hypotheses for P60 on 2026-09-09 and neither could be told from the
        // other by a screenshot or by the app's own log -- the log proved only
        // that the button never fired.
        //
        // 說出它是相對哪一個視窗解析的，以及那個點落在哪裡。
        //
        // **少了這一行，失敗在兩個方向上都是靜默的**：一次沒打中的點擊，看起來與一次被 app 忽略的
        // 點擊完全相同；而選錯視窗，看起來又與檔案裡座標寫錯完全相同。2026-09-09 的 P60 正是如此，
        // 而無論看截圖或看 app 自己的 log 都分辨不出來——那份 log 只能證明「那顆按鈕從未被觸發」。
        let message = "-actionfile: line \(action.line) point (\(action.x), \(action.y)) "
            + "windows=\(app.windows.count) frame=\(frame) "
            + "normalized=(\(action.x / frame.width), \(action.y / frame.height))\n"
        FileHandle.standardError.write(Data(message.utf8))

        return window.coordinate(withNormalizedOffset: CGVector(
            dx: action.x / frame.width,
            dy: action.y / frame.height
        ))
    }

    private func coordinateIfPresent(
        for action: Action,
        current: XCUICoordinate?,
        in app: XCUIApplication
    ) throws -> XCUICoordinate {
        if action.hasPosition {
            return try coordinate(for: action, in: app)
        }
        guard let current else {
            throw ActionFileError.invalidCoordinate(action.line)
        }
        return current
    }
}

private struct Action {
    let kind: String
    /// The `key` column, which the parser used to drop.
    ///
    /// It was dropped because nothing read it: `keydown`, `keyup` and `key` all
    /// threw `unsupported`. Carrying it is the first half of not throwing.
    /// `key` 欄位;parser 過去會把它丟掉。
    ///
    /// 之所以丟掉,是因為沒有人讀它:`keydown`、`keyup`、`key` 三者都 throw `unsupported`。
    /// 把它帶上,是「不再 throw」的前半。
    let key: String
    let x: CGFloat
    let y: CGFloat
    let origin: String
    let microseconds: TimeInterval
    let line: Int
    let hasPosition: Bool
}

private enum ActionFile {
    static func load(at path: String) throws -> [Action] {
        let text = try String(contentsOfFile: path, encoding: .utf8)
        return try text.split(whereSeparator: \.isNewline).enumerated().compactMap { index, raw in
            let line = index + 1
            let fields = parseCSV(String(raw))
            guard !fields.isEmpty, !fields[0].isEmpty, fields[0].first != "#" else { return nil }
            guard fields[0] != "action" else { return nil }
            guard fields.count >= 7 else { throw ActionFileError.malformed(line) }
            if fields.count > 8, !fields[8].isEmpty,
                fields[8] != "any", fields[8] != "ios"
            {
                throw ActionFileError.wrongPlatform(fields[8], line)
            }

            let hasPosition = !fields[1].isEmpty || !fields[2].isEmpty
            let x = CGFloat(Double(fields[1]) ?? 0)
            let y = CGFloat(Double(fields[2]) ?? 0)
            let micros = Double(fields[6]).map(TimeInterval.init) ?? 0
            return Action(
                kind: fields[0], key: fields[5], x: x, y: y,
                origin: fields[3].isEmpty ? "client" : fields[3],
                microseconds: micros, line: line, hasPosition: hasPosition
            )
        }
    }

    private static func parseCSV(_ line: String) -> [String] {
        var fields: [String] = []
        var field = ""
        var quoted = false
        var characters = Array(line)
        characters.append(",")

        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if quoted, index + 1 < characters.count, characters[index + 1] == "\"" {
                    field.append("\"")
                    index += 1
                } else {
                    quoted.toggle()
                }
            } else if character == "," && !quoted {
                fields.append(field.trimmingCharacters(in: .whitespaces))
                field = ""
            } else {
                field.append(character)
            }
            index += 1
        }
        return fields
    }
}

private enum ActionFileError: Error, CustomStringConvertible {
    case malformed(Int)
    case invalidCoordinate(Int)
    case unsupported(String, Int)
    case wrongPlatform(String, Int)

    var description: String {
        switch self {
        case .malformed(let line): return "Malformed action file row at line \(line)"
        case .invalidCoordinate(let line): return "Invalid iOS coordinate at line \(line)"
        case .unsupported(let action, let line): return "Unsupported iOS action '\(action)' at line \(line)"
        case .wrongPlatform(let platform, let line):
            return "Action file platform '\(platform)' is not valid for iOS at line \(line)"
        }
    }
}
