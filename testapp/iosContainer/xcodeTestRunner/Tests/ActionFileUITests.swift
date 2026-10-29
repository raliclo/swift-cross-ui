import Foundation
import UIKit
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
            // iOS has no Back key. The closest things -- a navigation controller's edge
            // swipe, Escape dismissing a presentation -- are a gesture and another key, which
            // a file can already write as such (`mousedown`/`move`/`mouseup`, `escape`); refused.
            // iOS 沒有返回鍵。最接近的——navigation controller 的邊緣滑動、Escape 關閉呈現——是一個手勢與另一個鍵，動作檔本來
            // 就能照實寫出(`mousedown`/`move`/`mouseup`、`escape`);拒絕。
            case "back": return nil
            // `[`, so that Command-[ -- the Back shortcut of UIKit and AppKit -- can be written.
            // `[`,好讓 Command-[——UIKit 與 AppKit 的返回快捷鍵——能被寫出。
            case "leftBracket": return "["
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
        /// The app `activate` last brought forward; `taplabel` searches it.
        /// `activate` 最後帶到前景的 app;`taplabel` 在其中搜尋。
        var frontApp = app
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
                case "dumptree":
                    // The tree as it stands at this row. The dump above is taken
                    // before the first row, so a target that only exists, or only
                    // sits where it does, after earlier rows have changed the
                    // layout could not be measured from it (P17's "More height",
                    // 2026-10-01).
                    // 這一列當下的樹。上面那份在第一列之前取得,所以一個「要等前面幾列改變版面之後
                    // 才出現、或才在那個位置」的目標,無法從它量出來(P17 的「More height」,2026-10-01)。
                    FileHandle.standardError.write(
                        Data(
                            "-actionfile: element tree at dumptree row:\n\(frontApp.debugDescription)\n"
                                .utf8
                        )
                    )
                case "hover":
                    // Moves the pointer to a point without pressing, with whatever
                    // modifiers `keydown` holds.
                    //
                    // Not `XCUICoordinate.hover()`. On the iPad simulator (iOS 27.0,
                    // 2026-10-13) the first call of a run reached the app -- began,
                    // then ended 90 ms later -- and the calls after it mostly did
                    // not: five rows gave one or two deliveries, never five, and
                    // `perform(withKeyModifiers:)` around it never showed Command.
                    // One synthesized event that travels from the previous point
                    // reaches the app on every row and carries the modifiers.
                    //
                    // The pointer does not stay unless the row has `micros`: it leaves about 100 ms after the
                    // travel ends, so the app sees began, changed, ended per row.
                    //
                    // An iPhone has no pointer. `hover()` failed the whole test
                    // there ("Pointer events are not supported for this device");
                    // the synthesized event is accepted and nothing reaches the app
                    // ("hover reports: 0"). So the row is skipped there and says
                    // so; the point is kept, because later rows may start from it.
                    // 把指標移到某點而不按下，連同 `keydown` 按住的 modifier。
                    //
                    // 不用 `XCUICoordinate.hover()`。在 iPad 模擬器上(iOS 27.0,2026-10-13)一次執行裡的第一次
                    // 呼叫會送進 app——began,90 ms 後 ended——其後的呼叫多半不會:五列只送達一兩次，從未五次;
                    // 包在 `perform(withKeyModifiers:)` 裡也從未出現 Command。改成一個從上一點移過來的合成事件後，
                    // 每一列都送達，也帶著 modifier。
                    //
                    // 除非該列帶 `micros`,指標不會停留:移動結束後約 100 ms 就離開，所以 app 每一列看到的是 began、changed、ended。
                    //
                    // iPhone 沒有指標。`hover()` 在那裡會讓整個測試失敗(「Pointer events are not supported for this
                    // device」);合成事件則被接受，但沒有任何東西送進 app(「hover reports: 0」)。所以在那裡這一列會被跳過並明講;點仍然保留，因為後面的列可能從它開始。
                    let target = try coordinate(for: action, in: app)
                    let previous = pointer
                    pointer = target
                    let end = target.screenPoint
                    let start = previous.map(\.screenPoint) ?? CGPoint(x: end.x - 30, y: end.y - 30)
                    guard UIDevice.current.userInterfaceIdiom == .pad else {
                        FileHandle.standardError.write(
                            Data(
                                ("-actionfile: hover skipped at (\(action.x), \(action.y)): "
                                    + "this device has no pointer\n").utf8
                            )
                        )
                        break
                    }
                    // A hover row with `micros` rests the pointer there for that long, and
                    // halfway through writes what is on the screen: a capture into
                    // `IOS_SHOT_DIR` and the labels. Without it the pointer has left before
                    // the run's final capture, which then shows "ended" (P88, 2026-10-13).
                    // 帶 `micros` 的 hover 列讓指標在那裡停留那麼久，並在一半時寫下畫面上有什麼:一張擷圖進
                    // `IOS_SHOT_DIR`,以及標籤。少了它，指標在最後擷圖之前就離開了，擷圖看到的是「ended」。
                    let line = action.line
                    try PointerPath.move(
                        from: start,
                        to: end,
                        modifiers: heldModifiers.rawValue,
                        hold: action.microseconds / 1_000_000
                    ) {
                        if let directory = ProcessInfo.processInfo.environment["IOS_SHOT_DIR"] {
                            let file = "\(directory)/hover-L\(line).png"
                            do {
                                try XCUIScreen.main.screenshot().pngRepresentation
                                    .write(to: URL(fileURLWithPath: file))
                                FileHandle.standardError.write(
                                    Data("-actionfile: resting capture \(file)\n".utf8)
                                )
                            } catch {
                                FileHandle.standardError.write(
                                    Data("-actionfile: resting capture FAILED: \(error)\n".utf8)
                                )
                            }
                        }
                        if let root = try? frontApp.snapshot() {
                            var elements: [XCUIElementSnapshot] = []
                            Self.flatten(root, into: &elements)
                            let labels = elements.map(\.label).filter { !$0.isEmpty }
                            if let data = try? JSONEncoder().encode(labels) {
                                FileHandle.standardError.write(
                                    Data(
                                        ("-actionfile: resting labels line \(line) "
                                            + "\(String(decoding: data, as: UTF8.self))\n").utf8
                                    )
                                )
                            }
                        }
                    }
                    FileHandle.standardError.write(
                        Data(
                            ("-actionfile: hovered (\(action.x), \(action.y)) "
                                + "modifiers=\(Self.describe(heldModifiers))\n").utf8
                        )
                    )
                case "windowframes":
                    // Every window of the app under test, in screen points, so a
                    // file can be measured against where the windows really are.
                    // 受測 app 的每一個視窗(螢幕點)，讓動作檔可以依視窗的實際位置來量。
                    let windows = app.windows.allElementsBoundByIndex
                    var lines = "-actionfile: \(windows.count) window(s)\n"
                    for (index, window) in windows.enumerated() {
                        lines += "-actionfile: window \(index) frame=\(window.frame)\n"
                    }
                    FileHandle.standardError.write(Data(lines.utf8))
                case "activate":
                    // Brings another app to the front -- the key column is its
                    // bundle identifier; empty means the app under test. For
                    // setting the device up (iPad windowed mode lives in
                    // com.apple.Preferences), not for testing it.
                    // 把另一個 app 帶到前景——key 欄是它的 bundle identifier;空白代表受測 app。
                    // 用於設定裝置(iPad 的視窗化模式在 com.apple.Preferences 裡),不是用來測試它。
                    let target = action.key.isEmpty
                        ? app : XCUIApplication(bundleIdentifier: action.key)
                    target.activate()
                    frontApp = target
                    FileHandle.standardError.write(
                        Data(
                            "-actionfile: activated \(action.key.isEmpty ? bundleIdentifier : action.key)\n"
                                .utf8
                        )
                    )
                case "taplabel":
                    // Taps the first hittable element labelled `key` in whichever
                    // app is frontmost. Other apps' layouts differ by device and
                    // OS, so a label survives where a coordinate would not. A
                    // missing label is an error, not a skipped row.
                    // 在最前方的 app 中，點第一個標籤為 `key` 且可點的元素。其他 app 的版面因裝置與系統
                    // 而異，標籤能存活之處座標不能。找不到標籤是錯誤，不是略過的一列。
                    // By type and `firstMatch`, never `descendants(.any)` resolved
                    // in full: on Settings that query never returned and the run
                    // timed out after 600 s (2026-10-02).
                    // 依型別並用 `firstMatch`,絕不完整解析 `descendants(.any)`:在「設定」上那個查詢
                    // 一直沒有返回，執行在 600 秒後逾時(2026-10-02)。
                    let queries: [XCUIElementQuery] = [
                        frontApp.buttons,
                        frontApp.cells,
                        frontApp.switches,
                        frontApp.staticTexts,
                        frontApp.otherElements,
                    ]
                    // Hittable first; failing that, the first that exists. An alert's
                    // buttons report isHittable == false although a tap on them
                    // works, so P5's "OK" was never found (2026-10-02); preferring
                    // a hittable match still picks the front window's button when
                    // a window behind it has one with the same label.
                    // 優先選可點擊的;沒有時，選第一個存在的。alert 的按鈕回報 isHittable == false,但點下去有效，
                    // 所以 P5 的「OK」一直找不到(2026-10-02);優先選可點擊者，在後方視窗也有同名按鈕時仍會選到
                    // 前方視窗的那一個。
                    let candidates = queries.map {
                        $0.matching(NSPredicate(format: "label == %@", action.key)).firstMatch
                    }
                    let match = candidates.first { $0.exists && $0.isHittable }
                        ?? candidates.first { $0.waitForExistence(timeout: 3) }
                    guard let element = match else {
                        throw ActionFileError.unsupported(
                            "taplabel '\(action.key)': no hittable element with that label",
                            action.line
                        )
                    }
                    // `x,y` given: that many points from the centre, as on the
                    // desktop and Android (P41-change-seconds, 2026-10-29).
                    // 有 `x,y` 時：自中心移動那麼多點，與桌面及 Android 相同(P41-change-seconds,2026-10-29)。
                    if action.x == 0 && action.y == 0 {
                        element.tap()
                    } else {
                        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                            .withOffset(CGVector(dx: action.x, dy: action.y))
                            .tap()
                    }
                    FileHandle.standardError.write(
                        Data("-actionfile: tapped '\(action.key)'\n".utf8)
                    )
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
                    if let start = dragStart, action.key.hasPrefix("velocity ") {
                        // A throw: `velocity N` in the key column drags at N points a
                        // second and lets go while moving, so the release carries that
                        // speed (P108's inertia); `velocity N hold S` holds S seconds at
                        // the end first, so the release carries none.
                        // 拋出:key 欄的 `velocity N` 以每秒 N 點拖曳並在移動中放手，讓放手時帶著那個速度(P108 的慣性);
                        // `velocity N hold S` 先在終點停 S 秒，讓放手時不帶速度。
                        let words = action.key.split(separator: " ")
                        let speed = words.count > 1 ? Double(words[1]) ?? 300 : 300
                        let hold = words.count > 3 && words[2] == "hold" ? Double(words[3]) ?? 0 : 0
                        start.press(
                            forDuration: 0.05,
                            thenDragTo: target,
                            withVelocity: XCUIGestureVelocity(rawValue: CGFloat(speed)),
                            thenHoldForDuration: hold
                        )
                        dragStart = nil
                    } else if let start = dragStart, action.microseconds > 0 {
                        // A `micros` on the mouseup row is how long to hold before
                        // moving, and the drag goes slowly. iPadOS starts a window
                        // move or resize only from a held press; a 0.1 s press
                        // dragged at the default speed did nothing to a window.
                        // mouseup 列上的 `micros` 是移動前要按住多久，拖曳會放慢。iPadOS 只有在按住之後
                        // 才開始移動或調整視窗;0.1 秒的按壓以預設速度拖曳，對視窗毫無作用。
                        start.press(
                            forDuration: action.microseconds / 1_000_000,
                            thenDragTo: target,
                            withVelocity: 300,
                            thenHoldForDuration: 0.3
                        )
                        dragStart = nil
                    } else if let start = dragStart {
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
                case "orient":
                    // Turns the simulated device, as a person turning the phone does;
                    // see `InputAction.orientation`. The app gets the same size
                    // change and trait update a real rotation gives it.
                    // 轉動模擬的裝置,就像一個人轉動手機那樣;見 `InputAction.orientation`。app 收到的尺寸改變與 trait
                    // 更新,和一次真正的旋轉完全相同。
                    let orientation: UIDeviceOrientation
                    switch action.key {
                        case "portrait": orientation = .portrait
                        case "portraitUpsideDown": orientation = .portraitUpsideDown
                        case "landscapeLeft": orientation = .landscapeLeft
                        case "landscapeRight": orientation = .landscapeRight
                        default:
                            throw ActionFileError.unsupported("orient \(action.key)", action.line)
                    }
                    XCUIDevice.shared.orientation = orientation
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

        // With `IOS_AIM` or `IOS_AIM_FILE`, every label on screen at the end. Two
        // replays of one file that pressed the same controls end with the same
        // labels -- a counter, a selection, a status line -- so the list from the
        // build the anchors were recorded on is what a re-aimed replay is checked
        // against. A screenshot cannot be compared that way once the layout moved.
        // 設了 `IOS_AIM` 或 `IOS_AIM_FILE` 時,印出結束時畫面上的每一個標籤。同一份檔案的兩次重放若按到相同的
        // 控制項,結束時的標籤就相同——計數、選取、狀態列——所以「記錄錨點的那個建置」留下的清單,就是用來檢查
        // 重新瞄準後那次重放的依據。版面一旦移動,截圖就無法那樣比對。
        let environment = ProcessInfo.processInfo.environment
        if environment["IOS_AIM"] != nil || environment["IOS_AIM_FILE"] != nil,
           let root = try? app.snapshot()
        {
            var elements: [XCUIElementSnapshot] = []
            Self.flatten(root, into: &elements)
            let labels = elements.filter(Self.canAnchor).map(\.label).filter { !$0.isEmpty }
                .sorted()
            if let data = try? JSONEncoder().encode(labels) {
                FileHandle.standardError.write(
                    Data("-actionfile: labels \(String(decoding: data, as: UTF8.self))\n".utf8)
                )
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

    /// What a point in an action file was aimed AT, so the point can be found
    /// again after the layout has moved.
    ///
    /// A file holds window points, and every change to where a root view starts
    /// or how wide an app is laid out leaves all of them stale at once
    /// (2026-10-12: three such changes in three days, 101 files). The element
    /// under a point survives those changes; the point does not.
    ///
    /// `inside` is the smallest element containing the point. `near` is the
    /// closest element that has a label, kept because `inside` is often an
    /// unlabelled container known only by its position in the tree, and a tree
    /// that gained or lost a node renumbers those.
    ///
    /// 動作檔裡的一個點原本瞄準的**是什麼**,好讓版面移動之後還能把那個點找回來。
    ///
    /// 檔案存的是視窗座標,而「根 view 從哪裡開始」或「app 以多寬排版」每改一次,所有座標就同時過期
    /// (2026-10-12:三天內改了三次,101 份檔案)。點底下的元素撐得過那些改動;點本身撐不過。
    ///
    /// `inside` 是框住該點的最小元素。`near` 是最近的、帶標籤的元素;留著它,是因為 `inside` 常常是一個
    /// 沒有標籤、只能靠它在樹中的位置辨認的容器,而一棵多了或少了一個節點的樹會讓那些位置重新編號。
    private struct Anchor: Codable {
        var key: String
        var ordinal: Int
        var dx: Double
        var dy: Double
        var width: Double
        var height: Double
    }

    private struct Aim: Codable {
        var line: Int
        var x: Double
        var y: Double
        var inside: Anchor?
        var near: Anchor?
    }

    /// The anchors `IOS_AIM_FILE` holds, by action-file line; empty without it.
    /// `IOS_AIM_FILE` 所存的錨點,以動作檔行號為鍵;沒有該變數時為空。
    private lazy var aims: [Int: Aim] = {
        guard let path = ProcessInfo.processInfo.environment["IOS_AIM_FILE"],
              let text = try? String(contentsOfFile: path, encoding: .utf8)
        else { return [:] }
        var result: [Int: Aim] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            if let aim = try? JSONDecoder().decode(Aim.self, from: Data(line.utf8)) {
                result[aim.line] = aim
            }
        }
        return result
    }()

    private static func flatten(
        _ node: XCUIElementSnapshot,
        into list: inout [XCUIElementSnapshot]
    ) {
        list.append(node)
        for child in node.children { flatten(child, into: &list) }
    }

    /// Type, identifier and label: what an element is, apart from where it is.
    /// 型別、identifier 與標籤:一個元素「是什麼」,不含它「在哪裡」。
    private static func key(_ element: XCUIElementSnapshot) -> String {
        "\(element.elementType.rawValue)|\(element.identifier)|\(element.label)"
    }

    /// The mode button floats over the content and does not move with it, a
    /// scroll indicator belongs to the viewport, and the application and window
    /// contain every point.
    /// 模式按鈕浮在內容之上、不隨內容移動;捲動指示條屬於視口;application 與 window 則框住每一個點。
    private static func canAnchor(_ element: XCUIElementSnapshot) -> Bool {
        element.elementType != .application && element.elementType != .window
            && element.frame.width > 0 && element.frame.height > 0
            && element.label != "actualView" && element.label != "rwdView"
            && !element.label.contains("scroll bar")
    }

    /// `IOS_AIM=record` prints the anchors of a point; `IOS_AIM_FILE` moves the
    /// point to where those anchors are now. Neither set: the point unchanged.
    ///
    /// Recording is done on a build where the file is known to land, applying
    /// on the build it has to land on. Both print a line per row, because a
    /// point that was moved and a point that could not be matched replay alike.
    ///
    /// `IOS_AIM=record` 印出一個點的錨點;`IOS_AIM_FILE` 把該點移到那些錨點現在的位置。兩者皆未設:點不變。
    ///
    /// 記錄在「已知該檔會點中」的建置上進行,套用則在它必須點中的那個建置上。兩者每一列都印一行,因為
    /// 「被移動過的點」與「對不上的點」重放起來一模一樣。
    private func aim(_ action: Action, window: CGRect, in app: XCUIApplication) -> CGPoint {
        let original = CGPoint(x: action.x, y: action.y)
        let recording = ProcessInfo.processInfo.environment["IOS_AIM"] == "record"
        let wanted = aims[action.line]
        guard recording || wanted != nil, let root = try? app.snapshot() else { return original }
        let onScreen = CGPoint(x: window.minX + original.x, y: window.minY + original.y)

        var elements: [XCUIElementSnapshot] = []
        Self.flatten(root, into: &elements)
        var seen: [String: Int] = [:]
        var entries: [(element: XCUIElementSnapshot, key: String, ordinal: Int)] = []
        for element in elements {
            let key = Self.key(element)
            let ordinal = seen[key, default: 0]
            seen[key] = ordinal + 1
            if Self.canAnchor(element) { entries.append((element, key, ordinal)) }
        }

        if recording {
            func anchor(_ entry: (element: XCUIElementSnapshot, key: String, ordinal: Int))
                -> Anchor
            {
                Anchor(
                    key: entry.key,
                    ordinal: entry.ordinal,
                    dx: Double(onScreen.x - entry.element.frame.minX),
                    dy: Double(onScreen.y - entry.element.frame.minY),
                    width: Double(entry.element.frame.width),
                    height: Double(entry.element.frame.height)
                )
            }
            func distance(_ frame: CGRect) -> CGFloat {
                let dx = max(frame.minX - onScreen.x, 0, onScreen.x - frame.maxX)
                let dy = max(frame.minY - onScreen.y, 0, onScreen.y - frame.maxY)
                return (dx * dx + dy * dy).squareRoot()
            }
            func area(_ frame: CGRect) -> CGFloat { frame.width * frame.height }
            // `<=` so a later element of the same size wins: it is drawn on top.
            // 用 `<=`,讓同樣大小時較後面的元素勝出:它畫在上面。
            var inside: (element: XCUIElementSnapshot, key: String, ordinal: Int)?
            var near: (element: XCUIElementSnapshot, key: String, ordinal: Int)?
            for entry in entries {
                let frame = entry.element.frame
                if frame.contains(onScreen),
                   inside.map({ area(frame) <= area($0.element.frame) }) ?? true
                {
                    inside = entry
                }
                guard !entry.element.label.isEmpty else { continue }
                if let best = near {
                    let new = distance(frame)
                    let old = distance(best.element.frame)
                    if new < old || (new == old && area(frame) <= area(best.element.frame)) {
                        near = entry
                    }
                } else {
                    near = entry
                }
            }
            let aim = Aim(
                line: action.line,
                x: Double(original.x),
                y: Double(original.y),
                inside: inside.map(anchor),
                near: near.map(anchor)
            )
            if let data = try? JSONEncoder().encode(aim) {
                FileHandle.standardError.write(
                    Data("-actionfile: aim \(String(decoding: data, as: UTF8.self))\n".utf8)
                )
            }
            return original
        }

        guard let wanted else { return original }
        typealias Entry = (element: XCUIElementSnapshot, key: String, ordinal: Int)
        // Where the anchors put the point in a given tree, which anchor decided,
        // and how far apart the two put it.
        // 在給定的樹中錨點把該點放在哪裡、由哪個錨點決定、以及兩個錨點算出的位置相距多遠。
        func locate(in entries: [Entry]) -> (point: CGPoint, by: String, apart: String)? {
            // `scaled` stretches the offset with the element, which is right inside
            // it and wrong beside it.
            // `scaled` 讓位移隨元素伸縮——在元素之內是對的,在元素旁邊則不對。
            func resolve(_ anchor: Anchor?, scaled: Bool) -> (point: CGPoint, sameSize: Bool)? {
                guard let anchor,
                      let entry = entries.first(where: {
                          $0.key == anchor.key && $0.ordinal == anchor.ordinal
                      })
                else { return nil }
                let frame = entry.element.frame
                let sx = Double(frame.width) / anchor.width
                let sy = Double(frame.height) / anchor.height
                let point = CGPoint(
                    x: Double(frame.minX - window.minX) + anchor.dx * (scaled ? sx : 1),
                    y: Double(frame.minY - window.minY) + anchor.dy * (scaled ? sy : 1)
                )
                return (point, (0.8...1.25).contains(sx) && (0.8...1.25).contains(sy))
            }
            let inside = resolve(wanted.inside, scaled: true)
            let near = resolve(wanted.near, scaled: false)
            let labelled = wanted.inside.map { !$0.key.hasSuffix("||") } ?? false
            let apart: String
            if let inside, let near {
                let dx = inside.point.x - near.point.x
                let dy = inside.point.y - near.point.y
                apart = String(format: "%.0f", Double((dx * dx + dy * dy).squareRoot()))
            } else {
                apart = "n/a"
            }
            // An unlabelled container is trusted only at its old size, because a tree
            // that gained or lost a node renumbers those.
            // 沒有標籤的容器只在大小不變時才採信,因為一棵多了或少了節點的樹會讓它們重新編號。
            if let inside, labelled || inside.sameSize { return (inside.point, "inside", apart) }
            if let near { return (near.point, "near", apart) }
            if let inside { return (inside.point, "inside-resized", apart) }
            return nil
        }
        func anchors(of root: XCUIElementSnapshot) -> [Entry] {
            var elements: [XCUIElementSnapshot] = []
            Self.flatten(root, into: &elements)
            var seen: [String: Int] = [:]
            var result: [Entry] = []
            for element in elements {
                let key = Self.key(element)
                let ordinal = seen[key, default: 0]
                seen[key] = ordinal + 1
                if Self.canAnchor(element) { result.append((element, key, ordinal)) }
            }
            return result
        }

        var chosen = locate(in: entries)
        // **A point the layout has put off the screen is scrolled to first**, by the
        // drag a `move` to the middle of the window and a `scroll` row would make,
        // and both are printed as the rows to add to the file. The point is then
        // found again, because a drag does not move the content by exactly its own
        // length. Clear of the status bar, the mode button and the home indicator.
        // **被版面放到螢幕外的點,先捲過去**——用的是「一列 `move` 到視窗中央、再一列 `scroll`」會做的那個拖曳,
        // 並把兩者印成要加進檔案的列。之後重新找一次該點,因為拖曳帶動內容的距離不會剛好等於它自己的長度。
        // 要讓開狀態列、模式按鈕與 home 指示條。
        let reach = CGRect(x: 24, y: 110, width: window.width - 48, height: window.height - 170)
        if let found = chosen, !reach.contains(found.point) {
            let dx = found.point.x < reach.minX
                ? found.point.x - reach.minX : max(found.point.x - reach.maxX, 0)
            let dy = found.point.y < reach.minY
                ? found.point.y - reach.minY : max(found.point.y - reach.maxY, 0)
            let notches = CGVector(
                dx: (dx / Self.pointsPerNotch).rounded(.awayFromZero),
                dy: (dy / Self.pointsPerNotch).rounded(.awayFromZero)
            )
            let centre = app.windows.firstMatch.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
            )
            centre.press(
                forDuration: 0.05,
                thenDragTo: centre.withOffset(CGVector(
                    dx: -notches.dx * Self.pointsPerNotch,
                    dy: -notches.dy * Self.pointsPerNotch
                ))
            )
            Thread.sleep(forTimeInterval: 0.6)
            FileHandle.standardError.write(Data((
                "-actionfile: reveal line \(action.line) move "
                    + String(
                        format: "(%.0f, %.0f)",
                        Double(window.width / 2),
                        Double(window.height / 2)
                    )
                    + " scroll (\(Int(notches.dx)), \(Int(notches.dy)))\n"
            ).utf8))
            if let root = try? app.snapshot() { chosen = locate(in: anchors(of: root)) }
        }
        let moved = chosen?.point ?? original
        let visible = window.contains(CGPoint(x: window.minX + moved.x, y: window.minY + moved.y))
        FileHandle.standardError.write(Data((
            "-actionfile: aimed line \(action.line) (\(original.x), \(original.y)) -> "
                + String(format: "(%.0f, %.0f)", Double(moved.x), Double(moved.y))
                + " by=\(chosen?.by ?? "unmatched") apart=\(chosen?.apart ?? "n/a") visible=\(visible)\n"
        ).utf8))
        return moved
    }

    private func coordinate(
        for action: Action,
        in app: XCUIApplication
    ) throws -> XCUICoordinate {
        guard action.origin != "frame" else {
            throw ActionFileError.unsupported("frame origin on iOS", action.line)
        }

        // `screen`: points from the top-left of the SCREEN, through SpringBoard,
        // whose frame is the whole display. Every other row is relative to
        // `app.windows.firstMatch`, which on an iPad in windowed mode is neither
        // at the origin nor reliably the same window -- the drags that were
        // meant to move and size P5's windows were computed against whichever
        // window XCUITest listed first (2026-10-02).
        // `screen`:自**螢幕**左上角起算的點，經由 SpringBoard(其 frame 即整個螢幕)。其他列都相對於
        // `app.windows.firstMatch`,而在視窗化模式的 iPad 上，它既不在原點、也不一定是同一個視窗——那些
        // 要移動並調整 P5 視窗的拖曳，算的是 XCUITest 剛好列在第一個的視窗(2026-10-02)。
        if action.origin == "screen" {
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            return springboard.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: action.x, dy: action.y))
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

        // `IOS_AIM`: the point as the file has it, or as the anchors move it.
        // `IOS_AIM`:檔案裡的那個點,或是錨點把它移到的地方。
        let point = aim(action, window: frame, in: app)
        return window.coordinate(withNormalizedOffset: CGVector(
            dx: point.x / frame.width,
            dy: point.y / frame.height
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

/// Moves the pointer along a line, without a button, as one synthesized event.
/// 以一個合成事件讓指標沿一條線移動，不按任何按鍵。
///
/// `XCPointerEventPath` and `XCSynthesizedEventRecord` are XCTest classes with no
/// public header; each selector is looked up and a missing one is an error that
/// names it, so an Xcode that drops one says which.
/// `XCPointerEventPath` 與 `XCSynthesizedEventRecord` 是沒有公開標頭的 XCTest 類別;每個 selector 都是查出來的，
/// 缺少時會丟出指名它的錯誤，所以哪個版本的 Xcode 拿掉了哪一個會被明講。
private enum PointerPath {
    struct Unavailable: Error, CustomStringConvertible {
        let description: String
    }

    static func move(
        from start: CGPoint,
        to end: CGPoint,
        modifiers: UInt,
        hold: TimeInterval = 0,
        whileResting: () -> Void = {}
    ) throws {
        typealias InitAt = @convention(c) (AnyObject, Selector, CGPoint) -> Unmanaged<AnyObject>
        typealias MoveTo = @convention(c) (AnyObject, Selector, CGPoint, Double, Double) -> Void
        typealias SetModifiers = @convention(c) (AnyObject, Selector, UInt, Bool, Double) -> Void
        typealias InitRecord = @convention(c) (AnyObject, Selector, NSString, Int)
            -> Unmanaged<AnyObject>
        func implementation<T>(
            _ cls: AnyClass,
            _ name: String,
            as type: T.Type
        ) throws -> (T, Selector) {
            let selector = NSSelectorFromString(name)
            guard let method = class_getInstanceMethod(cls, selector) else {
                throw Unavailable(description: "XCTest has no -[\(cls) \(name)]")
            }
            return (unsafeBitCast(method_getImplementation(method), to: type), selector)
        }
        guard let pathClass = NSClassFromString("XCPointerEventPath") as? NSObject.Type,
              let recordClass = NSClassFromString("XCSynthesizedEventRecord") as? NSObject.Type
        else {
            throw Unavailable(description: "XCTest has no XCPointerEventPath")
        }
        let alloc = NSSelectorFromString("alloc")
        let (initAt, initAtSelector) = try implementation(
            pathClass,
            "initForMouseEventsAtLocation:",
            as: InitAt.self
        )
        let (moveTo, moveToSelector) = try implementation(
            pathClass,
            "moveMouseToPoint:atOffset:duration:",
            as: MoveTo.self
        )
        let (setModifiers, setModifiersSelector) = try implementation(
            pathClass,
            "setModifiers:mergeWithCurrentModifierFlags:atOffset:",
            as: SetModifiers.self
        )
        let (initRecord, initRecordSelector) = try implementation(
            recordClass,
            "initWithName:interfaceOrientation:",
            as: InitRecord.self
        )

        let path = initAt(
            pathClass.perform(alloc).takeUnretainedValue(),
            initAtSelector,
            start
        ).takeUnretainedValue()
        if modifiers != 0 {
            setModifiers(path, setModifiersSelector, modifiers, false, 0)
        }
        moveTo(path, moveToSelector, end, 0.05, 0.3)
        // A last step after a pause, and the modifiers let go after that. Without them
        // one row of three reached the app and Command never did (2026-10-13).
        // 停頓之後再走最後一步，其後才放開 modifier。少了它們，三列只有一列送進 app,Command 則從未送達(2026-10-13)。
        moveTo(path, moveToSelector, CGPoint(x: end.x + 1, y: end.y), 0.75, 0.05)
        // A rest: the pointer goes on being moved, one point back and forth, because it
        // leaves about 100 ms after the last event of a path.
        // 停留:指標繼續被來回移動一點，因為一條路徑的最後一個事件之後約 100 ms 它就離開。
        var offset = 0.8
        var away = false
        while offset < 0.8 + hold {
            moveTo(path, moveToSelector, CGPoint(x: end.x + (away ? 1 : 0), y: end.y), offset, 0.05)
            away.toggle()
            offset += 0.1
        }
        if modifiers != 0 {
            setModifiers(path, setModifiersSelector, 0, false, offset + 0.05)
        }
        let record = initRecord(
            recordClass.perform(alloc).takeUnretainedValue(),
            initRecordSelector,
            "pointer move" as NSString,
            UIInterfaceOrientation.portrait.rawValue
        ).takeUnretainedValue()
        _ = record.perform(NSSelectorFromString("addPointerEventPath:"), with: path)

        guard
            let synthesizer = (XCUIDevice.shared as NSObject)
            .perform(NSSelectorFromString("eventSynthesizer"))?.takeUnretainedValue()
        else {
            throw Unavailable(description: "XCUIDevice has no event synthesizer")
        }
        var failure: Error?
        let done = DispatchSemaphore(value: 0)
        let completion: @convention(block) (Bool, NSError?) -> Void = { _, error in
            failure = error
            done.signal()
        }
        _ = synthesizer.perform(
            NSSelectorFromString("synthesizeEvent:completion:"),
            with: record,
            with: completion as AnyObject
        )
        // Halfway through a rest, the caller looks at the screen: that is the only time a
        // resting pointer can be seen, because the path below is waited for to its end.
        // 停留到一半時讓呼叫端看一眼畫面:指標停留的樣子只有這時看得到，因為下面會等這條路徑走完。
        if hold > 0, done.wait(timeout: .now() + 0.8 + hold / 2) == .timedOut {
            whileResting()
        }
        guard done.wait(timeout: .now() + 20 + hold) == .success else {
            throw Unavailable(description: "the pointer move was not acknowledged in 20 s")
        }
        if let failure { throw failure }
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
                kind: fields[0],
                key: fields[5],
                x: x,
                y: y,
                origin: fields[3].isEmpty ? "client" : fields[3],
                microseconds: micros,
                line: line,
                hasPosition: hasPosition
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
