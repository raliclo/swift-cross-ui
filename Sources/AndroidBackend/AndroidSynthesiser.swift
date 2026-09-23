import Android
import AndroidApp
import AndroidOS
import AndroidView
import Foundation
import InputEvent
import Synchronization
import SwiftJava

// `AndroidKit` is deliberately not imported here, and neither is
// `AndroidGraphics`. AndroidKit re-exports the whole set, which brings in
// `android.graphics.Point` -- ambiguous against this file's `Point` -- and
// `android.view.InputEvent`, whose name shadows the MODULE `InputEvent` so that
// `InputEvent.Point` resolves to a member of the Java class and fails. Naming
// the three submodules that are actually used avoids both.
//
// 此處刻意不 import `AndroidKit`，也不 import `AndroidGraphics`。AndroidKit 會轉出整組模組，
// 其中帶進 `android.graphics.Point`——與本檔的 `Point` 產生歧義——以及 `android.view.InputEvent`，
// 後者的名稱會遮蔽 `InputEvent` 這個**模組**，使 `InputEvent.Point` 被解析為該 Java 類別的成員
// 而失敗。改為指名實際用到的三個子模組，可同時避開這兩者。

@_spi(Backends) import SwiftCrossUI

/// Spelled out because this file deliberately imports submodules rather than `AndroidKit`, and
/// because a bare `KeyEvent` next to this module's `Key` invites exactly the confusion the import
/// comment above is about.
/// 明寫出來,因為本檔刻意 import 各子模組而非 `AndroidKit`;也因為一個光禿禿的 `KeyEvent` 擺在本模組的
/// `Key` 旁邊,正好會招來上方那段 import 註解所談的那種混淆。
private typealias AndroidKeyEvent = AndroidView.KeyEvent

/// Replaying an action file on Android, by posting touches into our own
/// activity.
///
/// The other three synthesisers reach a system API directly -- `SendInput`,
/// XTEST through a subprocess, AppKit -- and `InputEvent` builds them itself.
/// Android's events go into a view hierarchy owned by an `Activity`, and the
/// activity belongs to this module, which already depends on `InputEvent`. So
/// this registers itself through ``SynthesiserRegistry`` rather than being
/// constructed there.
///
/// **In-process, like AppKit's and unlike the other two.** `Activity.dispatchTouchEvent`
/// delivers to this app's own window. Nothing here can drive another
/// application, which is the failure `SendInput` and XTEST can have and cannot
/// report.
///
/// **Keys, since 2026-09-22.** This file used to refuse them, on the grounds
/// that a keycode mapping nothing exercised was not worth writing. `.onKeyPress`
/// on Android made something exercise it, so the mapping is here now: ``Key`` to
/// `KeyEvent`'s keycodes, with the held modifiers tracked so that a `keydown`
/// for shift reaches the next row as a meta state. The keys Android genuinely
/// has no code for -- F13 through F20 -- are refused BY NAME rather than the
/// whole verb being refused, so a file that uses F5 works and a file that uses
/// F13 is told which row is the problem.
///
/// 在 Android 上重放動作檔——把觸控事件投遞進我們自己的 activity。
///
/// 另外三個 synthesiser 各自直接取用一個系統 API——`SendInput`、經由子行程的 XTEST、AppKit
/// ——而 `InputEvent` 有能力自行建構它們。Android 的事件則要進入一個由 `Activity` 所擁有的 view
/// 階層，而該 activity 屬於本模組，而本模組本就依賴 `InputEvent`。因此此處透過
/// ``SynthesiserRegistry`` 自行註冊，而不是在那邊被建構。
///
/// **在行程內，與 AppKit 相同、與另外兩者不同。** `Activity.dispatchTouchEvent` 只會投遞到本 app
/// 自己的視窗。此處的任何東西都無法驅動另一個應用程式——而那正是 `SendInput` 與 XTEST 可能發生、
/// 且無法回報的失敗。
///
/// **按鍵,自 2026-09-22 起。** 本檔過去拒絕按鍵,理由是「一份沒有任何東西會去驗證的 keycode 對照表
/// 不值得寫」。Android 上的 `.onKeyPress` 讓它有東西可驗了,因此那份對照表現在在這裡:``Key`` 對到
/// `KeyEvent` 的 keycode,並追蹤被按住的修飾鍵,好讓一列 shift 的 `keydown` 能以 meta state 的形式
/// 抵達下一列。Android 確實沒有對應碼的那些鍵——F13 到 F20——是**逐一具名**拒絕的,而不是整個動作
/// 一起拒絕;因此用到 F5 的檔案能跑,用到 F13 的檔案會被告知是哪一列有問題。
final class AndroidSynthesiser: Synthesiser, @unchecked Sendable {
    /// Points to pixels.
    ///
    /// An action file is written in points so it survives being replayed at a
    /// different display density; `MotionEvent` takes pixels. This is the one
    /// conversion between them and it happens at the last moment, as it does in
    /// the other three.
    ///
    /// 點轉換為像素。
    ///
    /// 動作檔以「點」書寫，如此才能在不同的顯示密度下重放；而 `MotionEvent` 接受的是像素。此處是
    /// 兩者之間唯一的換算，且與另外三者相同，發生在最後一刻。
    private let density: Double

    /// The last position a `move` row named, so a `click` with no coordinates
    /// has somewhere to land.
    ///
    /// A `click` row may omit its point, meaning "where the pointer already
    /// is". Android has no pointer that persists between events -- every
    /// `MotionEvent` carries its own coordinates -- so the position a file
    /// implies has to be remembered here.
    ///
    /// 上一個 `move` 列所指名的位置，好讓沒有座標的 `click` 有地方可落下。
    ///
    /// `click` 列可以省略座標，意思是「指標目前所在之處」。Android 沒有「在事件之間持續存在的
    /// 指標」——每一個 `MotionEvent` 都自帶座標——因此「檔案所隱含的那個位置」必須在此處記住。
    private var lastPoint: (x: Double, y: Double) = (0, 0)

    init(layoutScale: Double?) {
        if let layoutScale, layoutScale > 0 {
            density = layoutScale
        } else {
            // The activity's own density, not the display's. It is what the
            // backend laid the widgets out against, and where the two differ it
            // is the toolkit's number that a coordinate means -- the lesson
            // `WindowGeometry.scale` records from the Windows GTK 4 case.
            // 使用 activity 自身的密度，而非顯示器的。那是 backend 排版 widget 時所依據的數字；
            // 而在兩者不同之處，座標所依據的是 toolkit 的那一個——這正是 `WindowGeometry.scale`
            // 從 Windows 上 GTK 4 的案例所記下的教訓。
            // Read on the main thread, because the activity is main-actor
            // state. A synthesiser is built off the main thread -- the replay
            // runs there -- so this is the one hop `init` needs.
            // 在主執行緒上讀取，因為該 activity 屬於 main actor 的狀態。synthesiser 是在主執行緒
            // 之外被建構的——重放本就在那裡執行——因此這是 `init` 唯一需要的一次跳轉。
            density = Self.onMainThread {
                guard let activity = AndroidBackend.activity else { return 1.0 }
                guard let metrics = activity.getResources()?.getDisplayMetrics() else { return 1.0 }
                return Double(metrics.density)
            }
        }
    }

    /// Zero origin and the density as scale.
    ///
    /// An Android activity fills the screen and has no frame the app can be
    /// positioned within, so `frame` and `client` are the same origin and both
    /// are zero. `WindowGeometry.screenPosition(of:)` then does the point-to-
    /// pixel multiply, in the same place as on every other platform.
    ///
    /// 原點為零，縮放為 density。
    ///
    /// Android 的 activity 填滿整個螢幕，且沒有一個「app 可在其中被定位」的外框，因此 `frame` 與
    /// `client` 是同一個原點，且兩者皆為零。接著由 `WindowGeometry.screenPosition(of:)` 完成點到
    /// 像素的乘算——與其他每個平台在同一個地方。
    func currentWindowGeometry() throws -> WindowGeometry {
        WindowGeometry(frameOrigin: (0, 0), clientOrigin: (0, 0), scale: density)
    }

    /// Android's double-tap timeout, read rather than assumed.
    /// Android 的 double-tap 逾時值，讀取而非假設。
    var doubleClickInterval: Int {
        let milliseconds =
            (try? JavaClass<ViewConfiguration>().getDoubleTapTimeout()) ?? 300
        return Int(milliseconds) * 1000
    }

    func perform(_ action: InputAction, in geometry: WindowGeometry) throws {
        // `focus` first, and it throws here rather than doing nothing.
        //
        // **Android has one window**, so there is no second one to name, and the
        // protocol's own default says so loudly. A silent no-op would leave
        // every later coordinate resolving against the same window while the
        // file claims to have switched -- the failure this verb was added to
        // remove.
        // `focus` 先處理，而它在此處 throw、而不是什麼都不做。
        //
        // **Android 只有一個視窗**，因此沒有第二個可以指名，而本協定自己的預設實作會大聲說出這件事。
        // 一個靜默的空操作，會讓其後每一個座標仍相對於同一個視窗解析，而那個檔案卻宣稱自己切換過了
        // ——那正是這個動作被加進來所要消除的失敗。
        if case .focus(let title) = action {
            try focusWindow(titled: title)
            return
        }

        switch action {
            case .move(let point):
                let position = try geometry.screenPosition(of: point)
                lastPoint = (Double(position.x), Double(position.y))
                // No event. A `move` row on a touch screen has nothing to post
                // -- there is no hover -- so it only records where the next
                // click without coordinates should land. Posting an ACTION_MOVE
                // outside a press would be a gesture the file did not ask for.
                // 不投遞任何事件。在觸控螢幕上，`move` 列沒有東西可投遞——沒有 hover 這回事——
                // 因此它只記錄「下一個沒有座標的點擊該落在哪裡」。在按壓之外投遞 ACTION_MOVE，
                // 會是一個檔案並未要求的手勢。

            case .click(_, let point):
                let position = try resolve(point, in: geometry)
                let downTime = try dispatch(action: actionDown, at: position, downTime: nil)
                _ = try dispatch(action: actionUp, at: position, downTime: downTime)

            case .doubleClick(let button, let point):
                try performDoubleClick(button, at: point, in: geometry)

            case .longPress(let point, let micros):
                try longPress(at: point, micros: micros, in: geometry)

            case .hover(let point):
                try hover(at: point, in: geometry)

            case .mouseDown(_, let point):
                let position = try resolve(point, in: geometry)
                pressDownTime = try dispatch(action: actionDown, at: position, downTime: nil)

            case .mouseUp(_, let point):
                let position = try resolve(point, in: geometry)
                _ = try dispatch(action: actionUp, at: position, downTime: pressDownTime)
                pressDownTime = nil

            case .scroll(let dx, let dy):
                try scroll(dx: dx, dy: dy)

            case .pinch(let scalePercent, let velocityPercent):
                try twoContactGesture(
                    scale: Double(scalePercent) / 100,
                    radians: 0,
                    speed: velocityPercent == 0 ? 1 : Double(velocityPercent) / 100
                )

            case .rotate(let degrees, let degreesPerSecond):
                // The default angular speed is 1 radian per second because that
                // is what the iOS runner picks when the row says 0, and a file
                // that says nothing should mean the same thing on both.
                // 預設角速度為每秒 1 弧度,因為當那一列寫 0 時 iOS 的 runner 就是這麼選的;
                // 一份沒有指定的檔案,在兩者上應該是同一個意思。
                let radians = Double(degrees) * .pi / 180
                let perSecond =
                    degreesPerSecond == 0 ? 1 : Double(degreesPerSecond) * .pi / 180
                try twoContactGesture(
                    scale: 1,
                    radians: radians,
                    speed: perSecond
                )

            case .sleep(let microseconds):
                Thread.sleep(forTimeInterval: Double(microseconds) / 1_000_000)

            case .keyDown(let key):
                try dispatchKey(key, action: keyActionDown)

            case .keyUp(let key):
                try dispatchKey(key, action: keyActionUp)

            case .key(let key):
                try dispatchKey(key, action: keyActionDown)
                try dispatchKey(key, action: keyActionUp)

            case .focus:
                // Returned above; listed so a new case cannot be added without
                // the compiler pointing here.
                // 已於上方返回；在此列出，是為了讓新增 case 時編譯器必定指向此處。
                break
        }
    }

    /// The `downTime` of a press still in progress, so its release names the
    /// same gesture.
    ///
    /// Android identifies a gesture by the `downTime` shared by all its events.
    /// A release carrying a fresh timestamp is a release of nothing, and the
    /// view that took the press never sees it end.
    ///
    /// 進行中按壓的 `downTime`，使其釋放事件指的是同一個手勢。
    ///
    /// Android 以「該手勢所有事件共用的 `downTime`」來識別一個手勢。一個帶著全新時間戳的釋放事件
    /// 是「對無物的釋放」，而接收了該次按壓的 view 永遠等不到它結束。
    private var pressDownTime: Int64?

    /// `throws`, because `screenPosition(of:)` does.
    ///
    /// The same break that hit `AppKitSynthesiser` and for the same reason: this
    /// file is Android-only, so a `try` added inside a non-throwing function is
    /// invisible on every machine that cannot build this backend. Found
    /// 2026-09-10 by the first Android build after the merge.
    /// `throws`，因為 `screenPosition(of:)` 會 throw。
    ///
    /// 與擊中 `AppKitSynthesiser` 的是同一個破壞、理由也相同：本檔僅限 Android，因此「在不會 throw 的
    /// 函式裡加上 `try`」在任何建不了本 backend 的機器上都看不見。2026-09-10 由合併後的第一次
    /// Android 建置發現。
    private func resolve(
        _ point: Point?,
        in geometry: WindowGeometry
    ) throws -> (x: Double, y: Double) {
        guard let point else { return lastPoint }
        let position = try geometry.screenPosition(of: point)
        lastPoint = (Double(position.x), Double(position.y))
        return lastPoint
    }

    /// A drag, because a touch screen has no wheel.
    ///
    /// `scroll` is written in wheel notches, and the runner on iOS settled on
    /// 40 points per notch with the sign inverted -- scrolling down means
    /// dragging up. The same convention is used here so one file means the same
    /// thing on both, and the gesture is kept inside the screen for the reason
    /// the iOS runner had to learn: a drag that leaves the window is not a
    /// short drag, it is no drag at all.
    ///
    /// 以拖曳代替,因為觸控螢幕沒有滾輪。
    ///
    /// `scroll` 是以滾輪格數書寫的，而 iOS 的 runner 最後採用「一格 40 點、符號相反」——向下捲動
    /// 意味著向上拖曳。此處沿用同一套約定，使同一份檔案在兩者上意義相同；而該手勢會被保持在螢幕
    /// 之內，理由與 iOS runner 學到的相同：一個離開視窗的拖曳不是「較短的拖曳」，而是根本沒有拖曳。
    private func scroll(dx: Int, dy: Int) throws {
        let pointsPerNotch = 40.0
        let travel = (
            x: -Double(dx) * pointsPerNotch * density,
            y: -Double(dy) * pointsPerNotch * density
        )

        let start = lastPoint
        let end = (x: start.x + travel.x, y: start.y + travel.y)

        let downTime = try dispatch(action: actionDown, at: start, downTime: nil)

        // Intermediate points, because a single jump from start to end is not
        // read as a fling and some scroll views ignore it entirely.
        // 中間點是必要的：從起點直接跳到終點的單一事件不會被判讀為 fling，而某些捲動視圖會完全
        // 忽略它。
        let steps = 8
        for step in 1...steps {
            let fraction = Double(step) / Double(steps)
            try dispatchMove(
                at: (x: start.x + travel.x * fraction, y: start.y + travel.y * fraction),
                downTime: downTime
            )
        }

        _ = try dispatch(action: actionUp, at: end, downTime: downTime)
        lastPoint = end
    }

    /// Move a mouse pointer there and report the cursor Android would draw.
    ///
    /// **`onResolvePointerIcon` is Android's own answer, not ours, and that is the whole value of
    /// this verb.** `AndroidBackend+Cursors.swift` calls `View.setPointerIcon`; checking that the
    /// setter was called proves nothing about which view the pointer is over. `ViewGroup`'s
    /// implementation hit-tests down to the child under the coordinates, asks it, and falls back
    /// to its own icon -- so calling it on the decor view with a hover event at a point exercises
    /// the REGION as well as the shape. A row inside the mesh view and a row outside it therefore
    /// answer the question a capture cannot: whether the crosshair is confined to the view that
    /// asked for it.
    ///
    /// **The event has to say it came from a mouse.** `onResolvePointerIcon` is only meaningful
    /// for a pointer device; an event left at the default source is a touch, and a touch has no
    /// icon. `setSource(SOURCE_MOUSE)` after `obtain` is what makes it one -- the six-argument
    /// `obtain` has no source parameter.
    ///
    /// **This does NOT prove a pointer is drawn on screen.** This AVD has no pointer device at all
    /// (`dumpsys input` lists only `gpio-keys` and twelve `virtio_input_multi_touch`), so nothing
    /// is rendered and nothing can be photographed. What is proved is the decision: given a
    /// pointer at that coordinate, this is the icon Android resolves.
    ///
    /// 把一個滑鼠指標移到那裡,並回報 Android 會畫出的游標。
    ///
    /// **`onResolvePointerIcon` 是 Android 自己的答案、不是我們的,而那正是這個動作的全部價值。**
    /// `AndroidBackend+Cursors.swift` 呼叫的是 `View.setPointerIcon`;而「確認 setter 被呼叫過」
    /// 對「指標正位於哪個 view 之上」什麼也證明不了。`ViewGroup` 的實作會往下 hit-test 到座標底下的
    /// 子 view、問它,然後才退回自己的圖示——因此在 decor view 上以一個 hover 事件呼叫它,同時檢驗了
    /// **區域**與形狀。於是一列在 mesh view 之內、一列在它之外,就回答了擷圖回答不了的問題:
    /// 那個十字**有沒有被侷限**在提出要求的那個 view 之內。
    ///
    /// **那個事件必須說明自己來自滑鼠。** `onResolvePointerIcon` 只對指標裝置有意義;一個維持預設來源的
    /// 事件是觸控,而觸控沒有圖示。`obtain` 之後的 `setSource(SOURCE_MOUSE)` 才讓它成為指標事件
    /// ——六參數的 `obtain` 沒有 source 參數。
    ///
    /// **這**不**證明螢幕上畫出了一個指標。** 這個 AVD 根本沒有指標裝置(`dumpsys input` 只列出
    /// `gpio-keys` 與十二個 `virtio_input_multi_touch`),因此什麼都不會被繪製、也沒有東西可拍。
    /// 被證明的是那個**決定**:若有一個指標位於該座標,Android 解析出來的就是這個圖示。
    private func hover(at point: Point, in geometry: WindowGeometry) throws {
        let position = try geometry.screenPosition(of: point)
        lastPoint = (Double(position.x), Double(position.y))

        let clock = try JavaClass<SystemClock>()
        let now = clock.uptimeMillis()

        let name = Self.onMainThread { () -> String in
            guard
                let activity = AndroidBackend.activity,
                let decor = activity.getWindow()?.getDecorView(),
                let motionClass = try? JavaClass<MotionEvent>(),
                let deviceClass = try? JavaClass<InputDevice>(),
                let event = try? motionClass.obtain(
                    now,
                    now,
                    motionClass.ACTION_HOVER_MOVE,
                    Float(position.x),
                    Float(position.y),
                    Int32(0)
                )
            else { return "no activity" }

            event.setSource(deviceClass.SOURCE_MOUSE)
            _ = decor.dispatchGenericMotionEvent(event)
            let icon = decor.onResolvePointerIcon(event, 0)
            event.recycle()
            return Self.pointerIconName(icon, in: activity)
        }

        ActionFileReplay.report(
            "cursor at (\(Int(point.x)), \(Int(point.y))) is \(name)"
        )
    }

    /// Names a `PointerIcon` by asking for each system icon and comparing.
    ///
    /// `PointerIcon` has no readable type, so the only way to name one is to ask for the icons
    /// whose names are known and compare. `equals` compares the type, and `getSystemIcon` returns
    /// a cached instance per type, so this is exact rather than approximate. An icon that matches
    /// none of them is reported as `other`, not guessed at.
    ///
    /// 以「逐一索取系統圖示並比較」的方式為一個 `PointerIcon` 命名。
    ///
    /// `PointerIcon` 沒有可讀取的 type,因此為它命名的唯一方式,就是去索取那些**名字已知**的圖示再比較。
    /// `equals` 比較的是 type,而 `getSystemIcon` 對每個 type 回傳一個快取實例,因此這是精確的、
    /// 不是近似的。與任何一個都不相符的圖示會被回報為 `other`,而不是用猜的。
    private static func pointerIconName(
        _ icon: PointerIcon?,
        in context: AndroidApp.Activity
    ) -> String {
        guard let icon, let iconClass = try? JavaClass<PointerIcon>() else { return "none" }
        let named: [(String, Int32)] = [
            ("arrow", iconClass.TYPE_ARROW),
            ("pointingHand", iconClass.TYPE_HAND),
            ("crosshair", iconClass.TYPE_CROSSHAIR),
            ("text", iconClass.TYPE_TEXT),
            ("resizeHorizontal", iconClass.TYPE_HORIZONTAL_DOUBLE_ARROW),
            ("resizeVertical", iconClass.TYPE_VERTICAL_DOUBLE_ARROW),
            ("notAllowed", iconClass.TYPE_NO_DROP),
            ("default", iconClass.TYPE_DEFAULT),
            ("null", iconClass.TYPE_NULL),
        ]
        for (name, type) in named
            where iconClass.getSystemIcon(context, type)?.equals(icon.as(JavaObject.self)) == true
        {
            return name
        }
        return "other"
    }

    /// A press held down, which is how a finger raises a context menu.
    ///
    /// **The hold is real elapsed time and it has to be.** Android does not read
    /// a duration out of the events: `View.onTouchEvent` posts a
    /// `CheckForLongPress` runnable on ACTION_DOWN and cancels it on ACTION_UP,
    /// so the long click happens if, and only if, the main thread's message
    /// queue gets to that runnable before the release arrives. A down and an up
    /// posted back to back with an `eventTime` 500 ms apart is a tap -- the
    /// timestamps are not what is measured.
    ///
    /// That is also why the sleep stays on the replay thread. `dispatch` hops to
    /// the main thread per event and returns; sleeping here leaves the main
    /// thread free to run the runnable that this verb exists to trigger.
    /// Sleeping on the main thread instead would hold the queue shut for exactly
    /// the interval in which the long press was supposed to fire, and the row
    /// would degrade into a tap with nothing to say so.
    ///
    /// No ACTION_MOVE is sent. A move within the touch slop would be harmless
    /// and one beyond it cancels the pending long press, so the useful number of
    /// move events here is zero.
    ///
    /// 一次被按住的按壓,也就是手指叫出脈絡選單的方式。
    ///
    /// **這個「按住」是真實流逝的時間,而且必須是。** Android 並不從事件裡讀取時長:
    /// `View.onTouchEvent` 在 ACTION_DOWN 時 post 一個 `CheckForLongPress` runnable,並在 ACTION_UP
    /// 時取消它;因此長按會發生,若且唯若主執行緒的訊息佇列在釋放事件抵達之前跑到了那個 runnable。
    /// 兩個背靠背投遞、`eventTime` 相差 500 毫秒的 down 與 up,就是一次點擊——被量的不是那些時間戳。
    ///
    /// 那也正是睡眠留在重放執行緒上的原因。`dispatch` 是每個事件跳一次主執行緒然後返回;在此處睡眠,
    /// 會讓主執行緒有空去跑那個「本動作正是為了觸發它而存在」的 runnable。改在主執行緒上睡,則會在
    /// 「長按本該觸發」的那段區間裡把佇列關死,而那一列會退化成一次點擊,且沒有任何東西會說出這件事。
    ///
    /// 不送 ACTION_MOVE。在 touch slop 之內的移動無害,超出的則會取消待處理的長按;因此此處有用的
    /// move 事件數量是零。
    private func longPress(
        at point: Point?,
        micros: Int,
        in geometry: WindowGeometry
    ) throws {
        let position = try resolve(point, in: geometry)
        let downTime = try dispatch(action: actionDown, at: position, downTime: nil)
        Thread.sleep(forTimeInterval: Double(micros) / 1_000_000)
        _ = try dispatch(action: actionUp, at: position, downTime: downTime)
        lastPoint = position
    }

    /// The meta state a `keydown` row has left held.
    ///
    /// **Android does not remember this for you, and neither does the window.** A synthesised
    /// `KeyEvent` carries its own `metaState` field, and nothing infers it from earlier events --
    /// so a `keydown,shift` followed by `key,upArrow` delivers an arrow with no shift unless the
    /// bit is carried here. That is exactly the shape of the AppKit defect found on 2026-09-19,
    /// where a modifier was released before the event that was supposed to carry it.
    ///
    /// 一個 `keydown` 列所留下、仍被按住的 meta state。
    ///
    /// **Android 不會替你記住它,那個視窗也不會。** 一個合成的 `KeyEvent` 自帶 `metaState` 欄位,
    /// 而沒有任何東西會從先前的事件推導它——因此 `keydown,shift` 之後接 `key,upArrow`,送出的會是一個
    /// **沒有** shift 的方向鍵,除非那個位元由此處帶過去。那正是 2026-09-19 在 AppKit 上找到的缺陷的
    /// 形狀:一個修飾鍵在「本該帶著它的那個事件」之前就被放開了。
    private var heldModifiers: Int32 = 0

    private var keyActionDown: Int32 {
        (try? JavaClass<AndroidKeyEvent>().ACTION_DOWN) ?? 0
    }

    private var keyActionUp: Int32 {
        (try? JavaClass<AndroidKeyEvent>().ACTION_UP) ?? 1
    }

    /// **What a key row reaches, and the one thing it does not.**
    ///
    /// `Activity.dispatchKeyEvent` reaches the view hierarchy, so a view that overrides
    /// `dispatchKeyEvent` sees it -- which is why P72's `.onKeyPress` is driven from an action
    /// file and passes. An APP-MENU shortcut is not in the view hierarchy: it lives in
    /// `View.OnUnhandledKeyEventListener`, which `ViewRootImpl` runs after the whole hierarchy has
    /// declined the key, one level above anything an app can post to.
    ///
    /// Measured on 2026-09-23 with P71, and the pair is what makes it a finding rather than a
    /// guess: `actions/android/P71-shortcuts.csv` replayed all 21 of its actions and left the
    /// counters at 0/0/0, while `adb shell input keycombination -t 120 113 47` -- the same Ctrl-S,
    /// injected at system level -- fired it. The shortcuts work; this route does not carry them.
    ///
    /// Same family as the `PopupMenu` limit on the touch side, and with the same escape: a tool
    /// holding INJECT_EVENTS. `adb shell input keycombination` is that tool.
    ///
    /// **An app cannot become that tool, and this was tried rather than assumed.**
    /// `Instrumentation.sendKeySync` is public API and injects through `InputManager`, which
    /// enters at `ViewRootImpl` the way a keyboard does. `InputDispatcher::checkInjectionPermission`
    /// exempts an injector whose uid owns the focused window, and a replay injects into its own
    /// app's own window -- so on paper it should have been allowed. It is not. Built, wired ahead
    /// of the activity path, run on 2026-09-23, and refused seven times out of seven with:
    ///
    ///     java.lang.SecurityException: Injecting input events requires the caller (or the
    ///     source of the instrumentation, if any) to have the INJECT_EVENTS permission.
    ///
    /// The permission is checked before that uid exemption is ever reached. The code is not kept:
    /// a path that is refused on every supported configuration is dead weight that logs on every
    /// key row, and the useful part of it was the sentence above.
    ///
    /// **一個 app 當不了那個工具,而這件事是**試過**的、不是假設的。**
    /// `Instrumentation.sendKeySync` 是公開 API,它經由 `InputManager` 注入,而那會像鍵盤一樣從
    /// `ViewRootImpl` 進入。`InputDispatcher::checkInjectionPermission` 對「uid 持有聚焦視窗」的注入者
    /// 是豁免的,而一次重放注入的正是它自己這支 app 自己的視窗——紙上看它應該被允許。它沒有。
    /// 2026-09-23 建好、接在 activity 路徑之前、實際執行,七次全數被拒:
    ///
    ///     java.lang.SecurityException: Injecting input events requires the caller (or the
    ///     source of the instrumentation, if any) to have the INJECT_EVENTS permission.
    ///
    /// 那個權限在「uid 豁免」被觸及之前就檢查了。那段程式碼沒有保留:一條在每一個受支援組態下都會被拒絕
    /// 的路徑,是會在每一列按鍵上輸出日誌的死重量;它真正有用的部分,就是上面這段話。
    ///
    /// **一個按鍵列抵達得了什麼,以及它唯一抵達不了的東西。**
    ///
    /// `Activity.dispatchKeyEvent` 抵達得了 view 階層,因此一個覆寫了 `dispatchKeyEvent` 的 view 看得到它
    /// ——那正是 P72 的 `.onKeyPress` 能被動作檔驅動並通過的原因。而一個 **app 選單**快捷鍵不在 view 階層裡:
    /// 它住在 `View.OnUnhandledKeyEventListener`,由 `ViewRootImpl` 在整個階層都拒絕該按鍵之後才執行,
    /// 位於任何 app 投遞得到的層級之上。
    ///
    /// 2026-09-23 以 P71 實測,而「成對」正是它之所以是一項發現、而不是一個猜測的原因:
    /// `actions/android/P71-shortcuts.csv` 把 21 個動作全部重放完成,計數器停在 0/0/0;
    /// 而 `adb shell input keycombination -t 120 113 47`——同樣的 Ctrl-S、在系統層級注入——觸發了它。
    /// 那些快捷鍵是好的;是**這條路徑**載不動它們。
    ///
    /// 與觸控那一側的 `PopupMenu` 限制同族,而且有同一個逃生口:一個握有 INJECT_EVENTS 的工具。
    /// `adb shell input keycombination` 就是那個工具。
    private func dispatchKey(_ key: Key, action: Int32) throws {
        guard let code = Self.keyCode(for: key) else {
            throw SynthesiserError.unsupported(
                "key '\(key.rawValue)' on Android: android.view.KeyEvent has no keycode for it"
            )
        }

        // **Both edges happen BEFORE the event is built, and the release is the one that was
        // wrong first.** A real keyboard's shift-down carries META_SHIFT_ON and its shift-UP does
        // not: Android clears the bit as it generates the release, so the event that says "shift
        // came up" reports shift not held. The first version here removed the bit after
        // dispatching, and the app printed `MODIFIERS up shift=true` -- a release that still
        // claims to be held, which reads as a stuck modifier rather than as a synthesiser bug.
        // AppKitSynthesiser had the identical defect on 2026-09-19 and its fix was the identical
        // move.
        // **兩個邊緣都發生在事件被建構**之前**,而「放開」那一邊正是一開始寫錯的那個。** 實體鍵盤的
        // shift-down 帶有 META_SHIFT_ON,而它的 shift-**up** 沒有:Android 在產生放開事件的同時就
        // 清掉那個位元,因此「shift 放開了」這個事件回報的是「shift 未被按住」。此處第一版是在投遞
        // **之後**才移除那個位元,於是 app 印出 `MODIFIERS up shift=true`——一次「仍宣稱被按住」的放開,
        // 讀起來像是修飾鍵卡住,而不像 synthesiser 的臭蟲。AppKitSynthesiser 在 2026-09-19 有一模一樣
        // 的缺陷,而它的修法也一模一樣。
        if let bit = Self.modifierBit(for: key) {
            if action == keyActionDown {
                heldModifiers |= bit
            } else {
                heldModifiers &= ~bit
            }
        }

        let clock = try JavaClass<SystemClock>()
        let now = clock.uptimeMillis()
        let metaState = heldModifiers

        let dispatched = Self.onMainThread {
            guard let activity = AndroidBackend.activity else { return false }
            let event = AndroidKeyEvent(
                now, // downTime
                now, // eventTime
                action,
                code,
                Int32(0), // repeatCount
                metaState
            )
            _ = activity.dispatchKeyEvent(event)
            return true
        }

        guard dispatched else {
            throw SynthesiserError.unsupported("posting a key without an activity")
        }
    }

    /// `KeyEvent.META_*` for the four modifier keys an action file can hold.
    ///
    /// Left and right spellings set the same bit, because that is what `metaState` records: the
    /// `*_LEFT_ON` / `*_RIGHT_ON` bits exist too, but a view asking "is shift held" reads
    /// `META_SHIFT_ON`, and setting only the side-specific bit would answer no.
    ///
    /// 四個「動作檔可以按住」的修飾鍵所對應的 `KeyEvent.META_*`。
    ///
    /// 左右兩種寫法設定同一個位元,因為 `metaState` 記的就是那個:`*_LEFT_ON` / `*_RIGHT_ON` 也存在,
    /// 但一個 view 問「shift 是不是被按住了」時讀的是 `META_SHIFT_ON`;只設側邊專屬的位元,會得到「否」。
    private static func modifierBit(for key: Key) -> Int32? {
        switch key {
            case .shift, .rightShift: 0x1 // META_SHIFT_ON
            case .option, .rightOption: 0x2 // META_ALT_ON
            case .control, .rightControl: 0x1000 // META_CTRL_ON
            case .command, .rightCommand: 0x1_0000 // META_META_ON
            default: nil
        }
    }

    /// ``Key`` to `android.view.KeyEvent`'s keycodes.
    ///
    /// **Spelled out rather than computed, and F13 upward is the reason it has to be a table.**
    /// The letters and digits are contiguous and could be arithmetic; the function keys are
    /// contiguous only up to F12, because `KEYCODE_F12` is the last one Android defines. Returning
    /// nil there, rather than F12 plus one, is what makes `dispatchKey` able to name the row.
    ///
    /// ``Key`` 到 `android.view.KeyEvent` keycode 的對照。
    ///
    /// **逐項寫出而不是用算的,而「F13 以上」正是它必須是一張表的理由。** 字母與數字是連續的、確實可以
    /// 用算術;功能鍵則只連續到 F12,因為 `KEYCODE_F12` 是 Android 定義的最後一個。在那裡回傳 nil、
    /// 而不是「F12 加一」,才讓 `dispatchKey` 說得出是哪一列有問題。
    private static func keyCode(for key: Key) -> Int32? {
        switch key {
            case .a: 29
            case .b: 30
            case .c: 31
            case .d: 32
            case .e: 33
            case .f: 34
            case .g: 35
            case .h: 36
            case .i: 37
            case .j: 38
            case .k: 39
            case .l: 40
            case .m: 41
            case .n: 42
            case .o: 43
            case .p: 44
            case .q: 45
            case .r: 46
            case .s: 47
            case .t: 48
            case .u: 49
            case .v: 50
            case .w: 51
            case .x: 52
            case .y: 53
            case .z: 54
            case .zero: 7
            case .one: 8
            case .two: 9
            case .three: 10
            case .four: 11
            case .five: 12
            case .six: 13
            case .seven: 14
            case .eight: 15
            case .nine: 16
            case .delete: 67 // KEYCODE_DEL, which is backspace
            case .forwardDelete: 112 // KEYCODE_FORWARD_DEL
            case .escape: 111
            case .space: 62
            case .tab: 61
            case .return: 66 // KEYCODE_ENTER
            case .leftArrow: 21
            case .rightArrow: 22
            case .upArrow: 19
            case .downArrow: 20
            case .home: 122 // KEYCODE_MOVE_HOME, not KEYCODE_HOME (that is the Home BUTTON)
            case .end: 123 // KEYCODE_MOVE_END
            case .pageUp: 92
            case .pageDown: 93
            case .shift: 59 // KEYCODE_SHIFT_LEFT
            case .rightShift: 60
            case .control: 113 // KEYCODE_CTRL_LEFT
            case .rightControl: 114
            case .option: 57 // KEYCODE_ALT_LEFT
            case .rightOption: 58
            case .command: 117 // KEYCODE_META_LEFT
            case .rightCommand: 118
            case .capsLock: 115
            case .function: 119
            case .f1: 131
            case .f2: 132
            case .f3: 133
            case .f4: 134
            case .f5: 135
            case .f6: 136
            case .f7: 137
            case .f8: 138
            case .f9: 139
            case .f10: 140
            case .f11: 141
            case .f12: 142
            // F13 to F20: android.view.KeyEvent stops at KEYCODE_F12.
            case .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20: nil
            case .keypad0: 144
            case .keypad1: 145
            case .keypad2: 146
            case .keypad3: 147
            case .keypad4: 148
            case .keypad5: 149
            case .keypad6: 150
            case .keypad7: 151
            case .keypad8: 152
            case .keypad9: 153
            case .keypadDecimal: 158 // KEYCODE_NUMPAD_DOT
            case .keypadPlus: 157
            case .keypadMinus: 156
            case .keypadMultiply: 155
            case .keypadDivide: 154
            case .keypadEnter: 160
            case .keypadEquals: 161
            // KEYCODE_CLEAR (28) is the general clear key, not the keypad's.
            case .keypadClear: nil
        }
    }

    /// Half the distance between the two contacts a gesture starts with.
    ///
    /// In points, converted at dispatch like every other coordinate here. 40
    /// points is a span of 80 -- wide enough that `ContinuousGestureContainer`
    /// reads a real initial span (it refuses to track when that span is zero)
    /// and narrow enough that doubling it stays on a phone screen.
    ///
    /// 手勢起始時,兩個接觸點之間距離的一半。
    ///
    /// 以「點」為單位,與此處每一個座標一樣在投遞時換算。40 點代表 80 點的跨距——寬到足以讓
    /// `ContinuousGestureContainer` 讀到一個真實的初始跨距(跨距為零時它拒絕追蹤),窄到即使加倍
    /// 也還留在手機螢幕上。
    private static let gestureRadiusInPoints = 40.0

    /// A pinch or a rotation, as two contacts moving around the last point a
    /// `move` row named.
    ///
    /// **Aimed the same way the iOS runner aims**: the gesture happens around
    /// the pointer, because a gesture recogniser lives on one view and a
    /// gesture delivered to the middle of the window reaches whichever view is
    /// there. The first contact is what chooses the target -- Android routes
    /// the whole gesture to whatever the initial `ACTION_DOWN` hit -- so it goes
    /// down at the centre and the second contact joins beside it.
    ///
    /// The stream is the one `ContinuousGestureContainer` reads: `ACTION_DOWN`,
    /// then `ACTION_POINTER_DOWN` with the pointer index in the action's high
    /// bits (that is where it takes the initial span and angle from), then
    /// `ACTION_MOVE` with both contacts, then `ACTION_POINTER_UP`, which is
    /// where it reports the end.
    ///
    /// 一次縮放或旋轉——兩個接觸點繞著「前一列 `move` 所指名的點」移動。
    ///
    /// **瞄準方式與 iOS 的 runner 相同**:手勢發生在指標周圍,因為一個手勢辨識器只長在一個 view 上,
    /// 而一個送到視窗正中央的手勢,到達的是那裡剛好是誰。選定目標的是第一個接觸點——Android 會把整個
    /// 手勢路由給最初那個 `ACTION_DOWN` 打中的東西——因此它落在中心,第二個接觸點再到它旁邊加入。
    ///
    /// 這個事件串正是 `ContinuousGestureContainer` 所讀的:`ACTION_DOWN`,接著是把 pointer index 放在
    /// action 高位元裡的 `ACTION_POINTER_DOWN`(它由此取得初始跨距與角度),接著是兩個接觸點的
    /// `ACTION_MOVE`,最後是 `ACTION_POINTER_UP`——它在那裡回報結束。
    private func twoContactGesture(scale: Double, radians: Double, speed: Double) throws {
        let centre = lastPoint
        let radius = Self.gestureRadiusInPoints * density
        let endRadius = radius * scale

        // How long the gesture takes, from how far it has to travel and how
        // fast the row asked to travel it. Clamped at both ends: a gesture
        // shorter than a few frames has no `ACTION_MOVE` worth reading, and one
        // longer than three seconds outlasts the sleep any action file puts
        // after it, so its end would land after the screenshot.
        //
        // 這個手勢要花多久:由「要走多遠」與「那一列要求多快」算出。兩端都夾住:短於幾個影格的手勢,
        // 不會有任何值得一讀的 `ACTION_MOVE`;而長於三秒的手勢,會比任何動作檔放在它後面的 sleep
        // 還久——那樣它的結束會落在擷圖之後。
        let travel = radians == 0 ? abs(scale - 1) : abs(radians)
        let duration = min(max(travel / max(speed, 0.01), 0.15), 3.0)
        let steps = min(max(Int(duration / 0.016), 8), 90)
        let stepDelay = duration / Double(steps)

        func contacts(at fraction: Double) -> [(x: Double, y: Double)] {
            let r = radius + (endRadius - radius) * fraction
            let angle = radians * fraction
            let dx = cos(angle) * r
            let dy = sin(angle) * r
            return [
                (x: centre.x - dx, y: centre.y - dy),
                (x: centre.x + dx, y: centre.y + dy),
            ]
        }

        let start = contacts(at: 0)
        let downTime = try dispatchContacts(
            action: actionDown,
            contacts: [start[0]],
            downTime: nil
        )
        _ = try dispatchContacts(
            action: pointerAction(actionPointerDown, index: 1),
            contacts: start,
            downTime: downTime
        )

        for step in 1...steps {
            Thread.sleep(forTimeInterval: stepDelay)
            _ = try dispatchContacts(
                action: actionMove,
                contacts: contacts(at: Double(step) / Double(steps)),
                downTime: downTime
            )
        }

        let end = contacts(at: 1)
        _ = try dispatchContacts(
            action: pointerAction(actionPointerUp, index: 1),
            contacts: end,
            downTime: downTime
        )
        _ = try dispatchContacts(
            action: actionUp,
            contacts: [end[0]],
            downTime: downTime
        )
    }

    /// An action with the pointer index packed into its high bits.
    ///
    /// `ACTION_POINTER_DOWN` and `ACTION_POINTER_UP` say WHICH contact went
    /// down or up, and Android carries that index in the same integer as the
    /// action, shifted by `ACTION_POINTER_INDEX_SHIFT`. Sending the bare
    /// constant instead names contact 0 -- the one that is still down -- and
    /// the container would take the wrong pointer's coordinates without
    /// anything reporting a problem.
    ///
    /// 把 pointer index packed 進高位元的 action。
    ///
    /// `ACTION_POINTER_DOWN` 與 `ACTION_POINTER_UP` 要說出**哪一個**接觸點按下或抬起,而 Android
    /// 把那個索引與 action 放在同一個整數裡,位移量為 `ACTION_POINTER_INDEX_SHIFT`。若送出裸的常數,
    /// 指名的會是接觸點 0——那個還按著的——而容器會取到錯誤指標的座標,且不會有任何東西回報問題。
    private func pointerAction(_ action: Int32, index: Int32) -> Int32 {
        action | (index << pointerIndexShift)
    }

    private var actionPointerDown: Int32 {
        (try? JavaClass<MotionEvent>().ACTION_POINTER_DOWN) ?? 5
    }

    private var actionPointerUp: Int32 {
        (try? JavaClass<MotionEvent>().ACTION_POINTER_UP) ?? 6
    }

    private var pointerIndexShift: Int32 {
        (try? JavaClass<MotionEvent>().ACTION_POINTER_INDEX_SHIFT) ?? 8
    }

    private var toolTypeFinger: Int32 {
        (try? JavaClass<MotionEvent>().TOOL_TYPE_FINGER) ?? 1
    }

    private var sourceTouchscreen: Int32 {
        (try? JavaClass<InputDevice>().SOURCE_TOUCHSCREEN) ?? 0x1002
    }

    /// Builds one `MotionEvent` carrying any number of contacts and hands it to
    /// the activity, on the main thread.
    ///
    /// The single-contact `dispatch` above stays as it is: it is what every
    /// click, drag and scroll goes through, it has been driven on a device for
    /// weeks, and the five-argument `obtain` it calls cannot express a second
    /// contact. This is the fourteen-argument overload, which takes the
    /// contacts as arrays of `PointerProperties` and `PointerCoords`.
    ///
    /// 建構一個帶有任意個接觸點的 `MotionEvent`,並在主執行緒上交給該 activity。
    ///
    /// 上面那個單接觸點的 `dispatch` 維持原樣:每一次點擊、拖曳與捲動都走它,它已經在實機上被驅動了
    /// 好幾週,而它所呼叫的五參數 `obtain` 表達不出第二個接觸點。此處用的是十四參數的多載,它以
    /// `PointerProperties` 與 `PointerCoords` 的陣列接收那些接觸點。
    @discardableResult
    private func dispatchContacts(
        action: Int32,
        contacts: [(x: Double, y: Double)],
        downTime: Int64?
    ) throws -> Int64 {
        let clock = try JavaClass<SystemClock>()
        let now = clock.uptimeMillis()
        let down = downTime ?? now
        let toolType = toolTypeFinger
        let source = sourceTouchscreen

        let dispatched = Self.onMainThread {
            guard let activity = AndroidBackend.activity else { return false }
            if !activity.hasWindowFocus() {
                Self.reportPopupOnce()
            }

            var properties: [MotionEvent.PointerProperties?] = []
            var coordinates: [MotionEvent.PointerCoords?] = []
            for (index, contact) in contacts.enumerated() {
                let property = MotionEvent.PointerProperties()
                property.id = Int32(index)
                property.toolType = toolType
                properties.append(property)

                let coordinate = MotionEvent.PointerCoords()
                coordinate.x = Float(contact.x)
                coordinate.y = Float(contact.y)
                coordinate.pressure = 1
                coordinate.size = 1
                coordinates.append(coordinate)
            }

            guard
                let event = try? JavaClass<MotionEvent>().obtain(
                    down,
                    now,
                    action,
                    Int32(contacts.count),
                    properties,
                    coordinates,
                    Int32(0), // metaState
                    Int32(0), // buttonState
                    Float(1), // xPrecision
                    Float(1), // yPrecision
                    Int32(0), // deviceId
                    Int32(0), // edgeFlags
                    source,
                    Int32(0) // flags
                )
            else { return false }
            _ = activity.dispatchTouchEvent(event)
            event.recycle()
            return true
        }

        guard dispatched else {
            throw SynthesiserError.unsupported("posting a touch without an activity")
        }
        return down
    }

    private var actionDown: Int32 {
        (try? JavaClass<MotionEvent>().ACTION_DOWN) ?? 0
    }

    private var actionUp: Int32 {
        (try? JavaClass<MotionEvent>().ACTION_UP) ?? 1
    }

    private var actionMove: Int32 {
        (try? JavaClass<MotionEvent>().ACTION_MOVE) ?? 2
    }

    private func dispatchMove(at position: (x: Double, y: Double), downTime: Int64) throws {
        _ = try dispatch(action: actionMove, at: position, downTime: downTime)
    }

    /// Builds one `MotionEvent` and hands it to the activity, on the main
    /// thread.
    ///
    /// A replay runs off the main thread on purpose -- it is nearly all
    /// sleeping, and on the main thread that sleep is the UI's -- but a view
    /// hierarchy may only be touched from the UI thread. So the sleeping stays
    /// on the replay's thread and each individual post hops over, which is what
    /// `AppKitSynthesiser` does for the same reason.
    ///
    /// Synchronously, so an action is delivered before the next one is built. A
    /// press posted asynchronously can be overtaken by its own release.
    ///
    /// 建構一個 `MotionEvent`，並在主執行緒上交給該 activity。
    ///
    /// 重放刻意在主執行緒之外執行——它幾乎全在睡眠，而在主執行緒上那份睡眠同時也是 UI 的睡眠
    /// ——但 view 階層只能從 UI 執行緒觸碰。因此睡眠留在重放自己的執行緒上，而每一次個別的投遞則
    /// 跳過去執行；`AppKitSynthesiser` 基於相同理由也是這麼做的。
    ///
    /// 採同步方式，使某個動作在下一個被建構之前就已送達。以非同步方式投遞的按壓，可能被它自己的
    /// 釋放事件超車。
    @discardableResult
    private func dispatch(
        action: Int32,
        at position: (x: Double, y: Double),
        downTime: Int64?
    ) throws -> Int64 {
        let clock = try JavaClass<SystemClock>()
        let now = clock.uptimeMillis()
        let down = downTime ?? now

        let dispatched = Self.onMainThread {
            guard let activity = AndroidBackend.activity else { return false }

            // A popup is a different window, and this dispatch cannot reach it.
            //
            // `Activity.dispatchTouchEvent` delivers to this activity's window.
            // A Spinner's dropdown and a `PopupMenu` are separate windows owned
            // by the WindowManager, and Android offers an app no public way to
            // address another window's view: the API that reaches whatever is
            // on top is `Instrumentation.sendPointerSync`, which needs
            // INJECT_EVENTS, a signature permission. Neither popup is even ours
            // to hold a reference to -- `Spinner(MODE_DROPDOWN)` builds its own
            // `ListPopupWindow` and `PopupMenu` its own helper, both private.
            //
            // So the event goes nowhere, and until 2026-09-04 it went nowhere
            // silently: the second click of a file that opened a picker and
            // then chose from it did nothing at all, and the only evidence was
            // a screenshot that looked like the app had ignored its input. That
            // is why the four existing Android files that open a picker or a
            // menu -- P2, P17, P19, P20 -- each stop after one click.
            //
            // Losing window focus is the signal, and it is exact: an activity
            // has window focus unless another window has taken it, which for
            // this app means a popup.
            //
            // 彈出視窗是另一個視窗，而這個 dispatch 抵達不了它。
            //
            // `Activity.dispatchTouchEvent` 只會投遞到本 activity 的視窗。Spinner 的下拉與
            // `PopupMenu` 是由 WindowManager 持有的獨立視窗，而 Android 沒有提供 app 任何公開方式
            // 去定址另一個視窗的 view：能抵達「當下位於最上層者」的 API 是
            // `Instrumentation.sendPointerSync`，它需要 INJECT_EVENTS——一個簽章層級的權限。而且
            // 這兩種彈出視窗都不是我們能持有參照的東西——`Spinner(MODE_DROPDOWN)` 會自建
            // `ListPopupWindow`，`PopupMenu` 會自建其 helper，兩者皆為私有。
            //
            // 因此該事件哪裡也沒去，而在 2026-09-04 之前它是靜默地哪裡也沒去：一份「先開啟選擇器、
            // 再從中選取」的檔案，其第二次點擊完全沒有作用，而唯一的證據是一張「看起來像 app 忽略了
            // 輸入」的截圖。這正是既有的四份「會開啟選擇器或選單」的 Android 檔案——P2、P17、P19、
            // P20——每一份都在一次點擊之後就停止的原因。
            //
            // 失去視窗焦點就是那個訊號，而且它是精確的：一個 activity 除非有另一個視窗奪走了焦點，
            // 否則就擁有視窗焦點；而對這支 app 而言，那個「另一個視窗」就是彈出視窗。
            if !activity.hasWindowFocus() {
                Self.reportPopupOnce()
            }
            guard
                let event = try? JavaClass<MotionEvent>().obtain(
                    down,
                    now,
                    action,
                    Float(position.x),
                    Float(position.y),
                    Int32(0)
                )
            else { return false }
            _ = activity.dispatchTouchEvent(event)
            event.recycle()
            return true
        }

        guard dispatched else {
            throw SynthesiserError.unsupported("posting a touch without an activity")
        }
        return down
    }

    /// Said once per replay, not once per event.
    ///
    /// A click is three dispatches and a drag is many more; one line per event
    /// would bury the replay's own output, which `ActionFileReplay.report`'s
    /// note asks callers not to do. The prefix matches that function's so the
    /// line lands beside the `replaying` and `replayed` pair a reader is
    /// already looking for.
    ///
    /// 每次重放只說一次，而不是每個事件說一次。
    ///
    /// 一次點擊是三次 dispatch，一次拖曳則更多；每個事件一行會把重放自身的輸出淹沒，而那正是
    /// `ActionFileReplay.report` 的說明要求呼叫端不要做的事。此處的前綴與該函式相同，使這一行落在
    /// 讀者本來就在找的 `replaying` 與 `replayed` 這一對旁邊。
    private static let popupReported = Mutex(false)

    private static func reportPopupOnce() {
        let alreadySaid = popupReported.withLock { said -> Bool in
            defer { said = true }
            return said
        }
        guard !alreadySaid else { return }

        let line = "-actionfile: this activity does not have window focus, so a "
            + "popup (a picker dropdown or a menu) is in front. Touches "
            + "synthesised here go to the activity's window and cannot reach "
            + "it; this click will do nothing. See AndroidSynthesiser.\n"
        FileHandle.standardError.write(Data(line.utf8))
    }

    /// Runs the body on the UI thread and waits for it.
    ///
    /// A view hierarchy may only be touched from the UI thread, and a replay
    /// deliberately does not run there. `DispatchQueue.main.sync` from the main
    /// thread deadlocks, so the check is not defensive tidiness -- the registry
    /// closure that builds this type can be called from either.
    ///
    /// Synchronous, so an event is delivered before the next one is built: a
    /// press posted asynchronously can be overtaken by its own release.
    ///
    /// 在 UI 執行緒上執行本體並等待其完成。
    ///
    /// view 階層只能從 UI 執行緒觸碰，而重放刻意不在該處執行。從主執行緒呼叫
    /// `DispatchQueue.main.sync` 會死鎖，因此這個判斷並非防禦性的整理——建構本型別的那個註冊
    /// closure，兩邊都可能呼叫它。
    ///
    /// 採同步方式，使某個事件在下一個被建構之前就已送達：以非同步方式投遞的按壓，可能被它自己的
    /// 釋放事件超車。
    /// The `default:` parameter is gone, and it had never been reachable.
    ///
    /// It seeded a `var` that `DispatchQueue.main.sync` then overwrote
    /// unconditionally -- `sync` does not return until the closure has run, so
    /// the seed was read by nothing, ever. What surfaced it was Swift 6:
    /// capturing that `var` across `sync` needs the closure to be `Sendable`,
    /// which made the compiler ask what the generic parameter was, and the
    /// answer was that the whole dance could be one `return`.
    ///
    /// `Result: Sendable` is a real constraint rather than a formality -- the
    /// value crosses a thread boundary -- and both call sites pass a `Double`
    /// and a `Bool`.
    ///
    /// `default:` 參數已移除,而它從來就到不了。
    ///
    /// 它為一個 `var` 設了初值,而 `DispatchQueue.main.sync` 隨後會無條件覆寫它——`sync` 在 closure
    /// 跑完之前不會回傳,因此那個初值從頭到尾沒有被任何東西讀過。把它揭出來的是 Swift 6:跨越 `sync`
    /// 捕捉那個 `var`,要求該 closure 是 `Sendable`,於是編譯器追問那個泛型參數是什麼——而答案是,
    /// 整套動作可以縮成一個 `return`。
    ///
    /// `Result: Sendable` 是一個真實的約束、不是形式:那個值會跨越執行緒邊界。兩個呼叫端分別傳的是
    /// 一個 `Double` 與一個 `Bool`。
    private static func onMainThread<Result: Sendable>(
        _ body: @escaping @MainActor () -> Result
    ) -> Result {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { body() }
        }
        return DispatchQueue.main.sync { MainActor.assumeIsolated { body() } }
    }

    /// Asynchronous delivery was tried and changed nothing, which is worth
    /// recording because it was tried for a plausible wrong reason.
    ///
    /// A synthesised tap appeared to blank P12's window, so the update running
    /// nested inside a block already on the main queue looked like the cause,
    /// and `DispatchQueue.main.async` looked like the fix. It made no
    /// difference. The real cause was a mis-derived coordinate: 299 points at
    /// density 2.625 is 785 pixels, and "Increment counter" is at 942 -- 785 is
    /// the tab row. Pressing a tab button empties the window, and
    /// `adb shell input tap` on the same button does it too, so it is
    /// AndroidBackend's and not this file's. See `bugs/bug-Android.md`.
    ///
    /// 非同步投遞試過了，什麼都沒改變；這件事值得記下來，因為當初嘗試它的理由聽起來很合理，卻是錯的。
    ///
    /// 合成的觸控看似會清空 P12 的視窗，於是「更新嵌套在一個已於 main queue 上執行的區塊之內」看起來
    /// 就像是原因，而 `DispatchQueue.main.async` 看起來就像是解法。它毫無作用。真正的原因是一個算錯的
    /// 座標：299 點在 density 2.625 下是 785 像素，而「Increment counter」位於 942——785 落在分頁列上。
    /// 按下分頁按鈕會清空視窗，而在同一個按鈕上執行 `adb shell input tap` 也會，因此那屬於
    /// AndroidBackend，不屬於本檔。詳見 `bugs/bug-Android.md`。
}

extension Activity {
    /// Not in AndroidKit's generated `Activity`, so it is bound here, next to
    /// the only thing that calls it.
    /// AndroidKit 產生的 `Activity` 中沒有這個方法，因此在此處綁定——就放在唯一呼叫它的東西旁邊。
    @JavaMethod
    func dispatchTouchEvent(_ event: MotionEvent?) -> Bool
}

extension AndroidApp.Activity {
    /// Not in the generated bindings, though `dispatchTouchEvent` is.
    ///
    /// Both come from `Window.Callback`, which `Activity` implements; the generator bound one and
    /// not the other. Declared here the way `AndroidBackend+Fonts.swift` declares
    /// `TextView.setGravity`, for the same reason and with the same shape.
    ///
    /// Through the ACTIVITY rather than through `getWindow().getDecorView()`: the decor view's
    /// `dispatchKeyEvent` skips the window callback, which is what gives the activity its chance
    /// at Back and at menu shortcuts. A synthesiser that bypassed it would be driving a slightly
    /// different keyboard from the one a person has.
    ///
    /// 不在產生出來的綁定裡,而 `dispatchTouchEvent` 在。
    ///
    /// 兩者都來自 `Activity` 所實作的 `Window.Callback`;產生器綁了其中一個、沒綁另一個。此處的宣告
    /// 方式與 `AndroidBackend+Fonts.swift` 宣告 `TextView.setGravity` 相同,理由與形狀也相同。
    ///
    /// 走 **activity** 而不是 `getWindow().getDecorView()`:decor view 的 `dispatchKeyEvent` 會跳過
    /// window callback,而那正是 activity 得以處理 Back 與選單快捷鍵的地方。一個繞過它的 synthesiser,
    /// 驅動的會是一個與真人手上稍有不同的鍵盤。
    @JavaMethod
    func dispatchKeyEvent(_ arg0: AndroidView.KeyEvent?) -> Bool
}
