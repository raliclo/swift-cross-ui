import Android
import AndroidApp
import AndroidOS
import AndroidView
import Foundation
import InputEvent
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
/// **What it does not do: keys.** `dispatchKeyEvent` exists and a `KeyEvent`
/// can be built the same way, but a key row needs a keycode mapping from this
/// module's ``Key`` to Android's, and no Android action file uses one today.
/// Rather than write a mapping nothing exercises, a key row throws and says so.
/// The iOS runner rejects key rows for the same reason.
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
/// **它不做的事：按鍵。** `dispatchKeyEvent` 是存在的，`KeyEvent` 也能以同樣方式建構，但按鍵列需要
/// 一份「本模組的 ``Key`` 到 Android keycode」的對照表，而今天沒有任何 Android 動作檔用到它。與其
/// 寫一份沒有任何東西會去驗證的對照表，不如讓按鍵列拋出錯誤並說明原因。iOS 的 runner 基於相同理由
/// 拒絕按鍵列。
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
            density = Self.onMainThread(default: 1.0) {
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
        switch action {
            case .move(let point):
                let position = geometry.screenPosition(of: point)
                lastPoint = (Double(position.x), Double(position.y))
                // No event. A `move` row on a touch screen has nothing to post
                // -- there is no hover -- so it only records where the next
                // click without coordinates should land. Posting an ACTION_MOVE
                // outside a press would be a gesture the file did not ask for.
                // 不投遞任何事件。在觸控螢幕上，`move` 列沒有東西可投遞——沒有 hover 這回事——
                // 因此它只記錄「下一個沒有座標的點擊該落在哪裡」。在按壓之外投遞 ACTION_MOVE，
                // 會是一個檔案並未要求的手勢。

            case .click(_, let point):
                let position = resolve(point, in: geometry)
                let downTime = try dispatch(action: actionDown, at: position, downTime: nil)
                _ = try dispatch(action: actionUp, at: position, downTime: downTime)

            case .doubleClick(let button, let point):
                try performDoubleClick(button, at: point, in: geometry)

            case .mouseDown(_, let point):
                let position = resolve(point, in: geometry)
                pressDownTime = try dispatch(action: actionDown, at: position, downTime: nil)

            case .mouseUp(_, let point):
                let position = resolve(point, in: geometry)
                _ = try dispatch(action: actionUp, at: position, downTime: pressDownTime)
                pressDownTime = nil

            case .scroll(let dx, let dy):
                try scroll(dx: dx, dy: dy)

            case .sleep(let microseconds):
                Thread.sleep(forTimeInterval: Double(microseconds) / 1_000_000)

            case .keyDown, .keyUp, .key:
                throw SynthesiserError.unsupported("key rows on Android")
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

    private func resolve(_ point: Point?, in geometry: WindowGeometry) -> (x: Double, y: Double) {
        guard let point else { return lastPoint }
        let position = geometry.screenPosition(of: point)
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

        let dispatched = Self.onMainThread(default: false) {
            guard let activity = AndroidBackend.activity else { return false }
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
    private static func onMainThread<Result>(
        default fallback: Result,
        _ body: @escaping @MainActor () -> Result
    ) -> Result {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { body() }
        }
        var result = fallback
        DispatchQueue.main.sync { result = MainActor.assumeIsolated { body() } }
        return result
    }
}

extension Activity {
    /// Not in AndroidKit's generated `Activity`, so it is bound here, next to
    /// the only thing that calls it.
    /// AndroidKit 產生的 `Activity` 中沒有這個方法，因此在此處綁定——就放在唯一呼叫它的東西旁邊。
    @JavaMethod
    func dispatchTouchEvent(_ event: MotionEvent?) -> Bool
}
