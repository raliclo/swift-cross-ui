import AppKit
@_spi(Backends) import SwiftCrossUI

/// `BackendFeatures.ButtonPressState` on AppKit.
///
/// **The state this backend already keeps is unreachable from here, and this
/// file may not edit the file that keeps it.** `NSCustomButton` tracks a press
/// exactly the way the contract wants -- `isPressed` set in `mouseDown`,
/// `isHighlighted` recomputed against `bounds` on every `mouseDragged`, both
/// cleared in `mouseUp` (`AppKitBackend+Button.swift:199-229`) -- but
/// `isPressed` is `private` (line 106) and `isHighlighted` is a plain Swift
/// `var` with a `didSet` (line 110). A plain `var` has no observation hook:
/// KVO needs `@objc dynamic`, and adding either that or a callback to the
/// `didSet` means editing `AppKitBackend+Button.swift`, which this change is not
/// permitted to touch.
///
/// **Nor would hooking it have been enough.** `createSimpleButton()` returns a
/// bare `NSButton` (`AppKitBackend+Button.swift:6`), which has no
/// `NSCustomButton` in it at all, and the contract admits widgets from both
/// factories.
///
/// So the press is read from the event stream both kinds of button sit in, with
/// one application-wide local monitor for `.leftMouseDown`, `.leftMouseDragged`,
/// `.leftMouseUp` and `.mouseMoved`. The monitor returns every event unchanged,
/// so nothing downstream can be disturbed by it -- which is the reason it was
/// preferred to an `NSPressGestureRecognizer` on the button. A recogniser
/// (`AppKitBackend+Gestures.swift:129` uses one for long press) delays primary
/// mouse events to its view by default, and getting that wrong on a button
/// means the button stops working, not that a highlight goes missing.
///
/// **The abandon case** is the `.leftMouseDragged` branch, and it is a
/// transcription of what `NSCustomButton.mouseDragged` already does at
/// `AppKitBackend+Button.swift:206-216`: while the press is down, the reported
/// value is whether the point is inside `bounds`. Drag off, it reports `false`;
/// drag back on, `true` again; release anywhere, `false`.
///
/// **What is not exact, stated rather than hidden.** `NSButtonCell` runs a
/// nested mouse-tracking loop for a plain `NSButton`, dequeuing its own events;
/// if a local monitor does not see the release that ends that loop, the `false`
/// would be late. That is why the state is not merely accumulated from
/// transitions: `.leftMouseDown` and `.mouseMoved` both clear *every* registered
/// button before anything else is decided, so a missed release is corrected by
/// the next mouse movement or the next click rather than latching. Buttons
/// built by `createButton(wrapping:)` -- the ones a `ButtonStyle` actually draws
/// -- are `NSCustomButton`, which overrides `mouseDown`/`mouseUp` instead of
/// running a tracking loop, and are not subject to this at all.
///
/// AppKit 上的 `BackendFeatures.ButtonPressState`。
///
/// **這個 backend 已保存的狀態從此處無法取用，而本檔又不得修改保存它的那個檔案。**
/// `NSCustomButton` 追蹤按壓的方式恰恰就是合約想要的——`mouseDown` 中設定 `isPressed`、每次
/// `mouseDragged` 都以 `bounds` 重新計算 `isHighlighted`、`mouseUp` 中將兩者清除
/// （`AppKitBackend+Button.swift:199-229`）——但 `isPressed` 是 `private`（第 106 行），而
/// `isHighlighted` 是一個帶 `didSet` 的普通 Swift `var`（第 110 行）。普通 `var` 沒有觀察掛勾：
/// KVO 需要 `@objc dynamic`，而無論是加上它、或在 `didSet` 中加一個 callback，都意味著要編輯
/// `AppKitBackend+Button.swift`——而本次變更不得碰觸該檔。
///
/// **況且就算掛上去也不夠。** `createSimpleButton()` 回傳的是一個純粹的 `NSButton`
/// （`AppKitBackend+Button.swift:6`），其中根本沒有任何 `NSCustomButton`，而合約承認來自這兩個
/// 工廠方法的 widget。
///
/// 因此改為從兩種按鈕共處的那條事件串流讀取按壓狀態：一個應用程式層級的 local monitor，監聽
/// `.leftMouseDown`、`.leftMouseDragged`、`.leftMouseUp` 與 `.mouseMoved`。該 monitor 原封不動地
/// 回傳每一個事件，因此下游不可能被它干擾——這正是它勝過「在按鈕上掛 `NSPressGestureRecognizer`」
/// 的理由。gesture recogniser（`AppKitBackend+Gestures.swift:129` 用了一個做長按）預設會延遲送往其
/// view 的主要滑鼠事件，而在按鈕上把這件事弄錯，代價是按鈕直接失效，而不只是少了一個高亮。
///
/// **放棄的情況**就是 `.leftMouseDragged` 那一支，而它是 `NSCustomButton.mouseDragged` 於
/// `AppKitBackend+Button.swift:206-216` 既有作法的謄寫：在按壓期間，回報的值就是「該點是否位於
/// `bounds` 之內」。拖離則回報 `false`、拖回則再次 `true`、在任何位置放開都是 `false`。
///
/// **哪裡並不精確——如實陳述而非隱藏。** 對一個純粹的 `NSButton`，`NSButtonCell` 會跑一個巢狀的滑鼠
/// 追蹤迴圈、自行取走事件；若 local monitor 看不到結束該迴圈的那次放開，`false` 就會遲到。這正是狀態
/// 不單純由轉換累加而來的原因：`.leftMouseDown` 與 `.mouseMoved` 都會在做出任何判斷之前先把**每一個**
/// 已註冊的按鈕清為 false，因此一次錯過的放開會被下一次滑鼠移動或下一次點擊修正，而不會卡住。由
/// `createButton(wrapping:)` 建立的按鈕——也就是 `ButtonStyle` 真正會去繪製的那些——是
/// `NSCustomButton`，它覆寫 `mouseDown`/`mouseUp` 而非執行追蹤迴圈，完全不受此影響。
///
/// **A bare extension, deliberately.** `AppKitBackend` reaches the conformance
/// through `FullAppBackend`'s composition (`FullAppBackend.swift:111`); naming
/// `BackendFeatures.ButtonPressState` again here would be a redundant
/// conformance and would not compile.
///
/// **刻意採用不帶 conformance 的 extension。** `AppKitBackend` 是透過 `FullAppBackend` 的組合取得
/// 該 conformance 的（`FullAppBackend.swift:111`）；在此再次寫出
/// `BackendFeatures.ButtonPressState` 會構成重複 conformance 而無法編譯。
extension AppKitBackend {
    public func updateButtonPressHandler(
        _ button: Widget,
        handler: @escaping (Bool) -> Void
    ) {
        AppKitButtonPressMonitor.shared.install(on: button, handler: handler)
    }
}

/// The one local event monitor, and the buttons it reports for.
///
/// One monitor for the whole application rather than one per button: a monitor
/// is a global interception point, so N of them would each see every event and
/// do N times the work to answer the same question.
///
/// 唯一的那個 local event monitor，以及它所回報的那些按鈕。
///
/// 整個應用程式共用一個，而非每顆按鈕一個：monitor 是一個全域攔截點，因此 N 個 monitor 會各自看到
/// 每一個事件，為了回答同一個問題而做 N 倍的工。
@MainActor
final class AppKitButtonPressMonitor {
    static let shared = AppKitButtonPressMonitor()

    private final class Entry {
        /// Weak, so a button that has been discarded does not stay alive in
        /// this table, and so a dead entry is recognisable.
        /// 弱參考，使已被丟棄的按鈕不會在這張表中續命，也讓死掉的項目能被辨認出來。
        weak var button: NSView?

        var handler: (Bool) -> Void

        /// Whether the press currently in flight started on this button. Kept
        /// apart from ``reported`` because dragging off a held button makes the
        /// two disagree -- the press is still down, it is just not on the
        /// button, and dragging back on has to be able to say `true` again.
        /// 目前進行中的這次按壓是否始於這顆按鈕。與 ``reported`` 分開保存，因為把按住的按鈕拖離會
        /// 讓兩者不一致——按壓仍然按著，只是不在按鈕上；而拖回來時必須還能再說一次 `true`。
        var isDown = false

        var reported = false

        init(button: NSView, handler: @escaping (Bool) -> Void) {
            self.button = button
            self.handler = handler
        }
    }

    private var entries: [ObjectIdentifier: Entry] = [:]
    private var monitor: Any?

    private init() {}

    func install(on button: NSView, handler: @escaping (Bool) -> Void) {
        let key = ObjectIdentifier(button)

        if let existing = entries[key] {
            // Swapped, not replaced. `Button.commit` reinstalls on every update
            // (`Sources/SwiftCrossUI/Views/Button.swift:349`), and a fresh entry
            // would forget a press that is in flight -- the release would then
            // find `reported` already `false` and report nothing, leaving the
            // style latched in the pressed appearance.
            // 是替換 closure 而非替換整筆項目。`Button.commit` 每次更新都會重新安裝
            // （`Sources/SwiftCrossUI/Views/Button.swift:349`），而一筆全新的項目會忘記正在進行中
            // 的按壓——屆時放開時會發現 `reported` 已是 `false` 而不回報任何東西，讓樣式卡在按下的
            // 外觀上。
            existing.handler = handler
            return
        }

        entries = entries.filter { $0.value.button != nil }
        entries[key] = Entry(button: button, handler: handler)

        startMonitoringIfNeeded()
    }

    private func startMonitoringIfNeeded() {
        guard monitor == nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .mouseMoved]
        ) { event in
            MainActor.assumeIsolated {
                AppKitButtonPressMonitor.shared.handle(event)
            }

            // Returned unchanged. A monitor that returned nil would swallow the
            // event and the button would never be clicked at all.
            // 原封不動地回傳。一個回傳 nil 的 monitor 會吞掉該事件，按鈕便從此無法被點擊。
            return event
        }
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
            case .leftMouseDown:
                for entry in entries.values {
                    entry.isDown = contains(entry, event)
                    report(entry, entry.isDown)
                }

            case .leftMouseDragged:
                for entry in entries.values where entry.isDown {
                    report(entry, contains(entry, event))
                }

            case .leftMouseUp, .mouseMoved:
                // `.mouseMoved` is only delivered when no mouse button is down,
                // so it is a free assertion that nothing is pressed -- and the
                // correction for a release swallowed by an `NSButtonCell`
                // tracking loop.
                // `.mouseMoved` 只在沒有任何滑鼠鍵按下時才會送出，因此它等於一次免費的「沒有東西
                // 被按著」斷言——也是對「被 `NSButtonCell` 追蹤迴圈吞掉的放開」的修正。
                for entry in entries.values {
                    entry.isDown = false
                    report(entry, false)
                }

            default:
                break
        }
    }

    /// Whether `event` lands inside `entry`'s button.
    ///
    /// The conversion and the bounds test are the ones `NSCustomButton` performs
    /// on itself at `AppKitBackend+Button.swift:209` and `:221`. Two buttons
    /// that overlap would both answer `true` for a point in the overlap; this
    /// does not hit-test the view hierarchy, and a layout that stacks two live
    /// buttons on the same pixels would report both as pressed.
    ///
    /// `event` 是否落在 `entry` 的按鈕之內。
    ///
    /// 此處的座標轉換與 bounds 判斷，就是 `NSCustomButton` 於 `AppKitBackend+Button.swift:209`
    /// 與 `:221` 對自身所做的那一組。兩顆互相重疊的按鈕，對於重疊區內的一點都會回答 `true`；此處
    /// 並不對 view 階層做 hit test，因此一個把兩顆有效按鈕疊在同一批像素上的版面，會把兩者都回報
    /// 為按下。
    private func contains(_ entry: Entry, _ event: NSEvent) -> Bool {
        guard
            let button = entry.button,
            let window = button.window,
            window === event.window
        else {
            return false
        }

        return button.bounds.contains(button.convert(event.locationInWindow, from: nil))
    }

    private func report(_ entry: Entry, _ pressed: Bool) {
        guard pressed != entry.reported else { return }
        entry.reported = pressed
        entry.handler(pressed)
    }
}
