import AppKit
import SwiftCrossUI

extension AppKitBackend: BackendFeatures.FocusableViews {
    /// Makes this widget the window's first responder.
    ///
    /// **The widget is often not the responder, the same asymmetry the
    /// accessibility file records.** A ``TextField`` is an `NSView` around an
    /// `NSTextField`, and `makeFirstResponder` on the wrapper puts the keyboard
    /// nowhere: `NSView` returns `false` from `acceptsFirstResponder`, AppKit
    /// declines, and the call returns `false` without touching anything. So the
    /// responder is looked for beneath the widget.
    ///
    /// `nil` window is a refusal and not an error. A widget that is not in a
    /// window yet -- built, not yet attached -- cannot hold the focus, and the
    /// `Bool` return is exactly how that gets reported instead of crashing.
    ///
    /// 讓這個 widget 成為該視窗的 first responder。
    ///
    /// **widget 往往不是那個 responder,與無障礙那個檔案所記載的是同一種不對稱。** 一個 ``TextField``
    /// 是一個包著 `NSTextField` 的 `NSView`,而對那層包裝呼叫 `makeFirstResponder`,會把鍵盤送到
    /// 不存在的地方:`NSView` 的 `acceptsFirstResponder` 回傳 `false`,AppKit 拒絕,該呼叫回傳
    /// `false` 且什麼都沒碰到。因此 responder 要往 widget 底下找。
    ///
    /// 視窗為 `nil` 是一次「拒絕」,不是錯誤。一個還不在視窗裡的 widget——已建立、尚未附加——不可能
    /// 持有焦點;而回傳 `Bool` 正是讓這件事被**回報**、而不是讓程式崩潰的方式。
    @discardableResult
    public func focus(_ widget: Widget) -> Bool {
        let target = responder(in: widget)
        // `acceptsFirstResponder` on the TARGET, checked here rather than left
        // to `makeFirstResponder`.
        //
        // `responder(in:)` falls back to the widget when it finds no candidate,
        // and the widget is usually an `AppKitHitTestingContainer` -- a plain
        // `NSView` wrapper every widget gets. Handing that to
        // `makeFirstResponder` is asking AppKit to focus a wrapper, and what
        // comes back is not reliably `false`. Refusing here makes the answer
        // this protocol promises -- did it take the focus -- come from the one
        // question that decides it.
        //
        // 在**目標**上檢查 `acceptsFirstResponder`,而不是把這件事留給 `makeFirstResponder`。
        //
        // `responder(in:)` 在找不到候選時會退回 widget 本身,而那個 widget 通常是一個
        // `AppKitHitTestingContainer`——每個 widget 都會被套上的一層單純 `NSView` 包裝。把它交給
        // `makeFirstResponder`,等於要求 AppKit 去聚焦一層包裝,而回來的東西不保證是 `false`。
        // 在此拒絕,才讓本協定所承諾的那個答案——「它有沒有接受焦點」——出自那個真正決定它的問題。
        guard target.acceptsFirstResponder, let window = widget.window else { return false }
        Self.watchFirstResponder(of: window)
        return window.makeFirstResponder(target)
    }

    /// Resigns the focus, if this widget has it.
    ///
    /// Focus goes to the WINDOW rather than to `nil`. `makeFirstResponder(nil)`
    /// leaves a window with no responder at all, which on AppKit means keystrokes
    /// and menu key equivalents stop being routed -- a heavier thing than the
    /// caller asked for. The window is the resting place AppKit itself uses when
    /// a field ends editing.
    ///
    /// 放棄焦點(若這個 widget 持有它)。
    ///
    /// 焦點交還給**視窗**,而不是交給 `nil`。`makeFirstResponder(nil)` 會讓一個視窗完全沒有 responder,
    /// 而在 AppKit 上那意味著按鍵與選單快捷鍵不再被繞送——那比呼叫端所要求的還要重。視窗才是 AppKit
    /// 自己在一個欄位結束編輯時所使用的那個歸位處。
    public func unfocus(_ widget: Widget) {
        guard isFocused(widget), let window = widget.window else { return }
        window.makeFirstResponder(window)
    }

    /// Whether the first responder is this widget or something inside it.
    ///
    /// **`window.firstResponder == widget` is not the test.** When an
    /// `NSTextField` is being edited the first responder is its FIELD EDITOR --
    /// a shared `NSText` the window vends, not the field -- so an identity
    /// comparison reports "not focused" for the one case that matters most.
    /// `NSText.delegate` is the field in that arrangement, which is what the
    /// walk below unwraps.
    ///
    /// first responder 是不是這個 widget、或它裡面的某個東西。
    ///
    /// **判準不是 `window.firstResponder == widget`。** 當一個 `NSTextField` 正在被編輯時,first
    /// responder 是它的 **field editor**——一個由視窗提供的共享 `NSText`,而不是那個欄位本身——因此
    /// 用身分比較,會在**最重要的那個**情況下回報「沒有焦點」。在那種安排下,`NSText.delegate` 就是
    /// 那個欄位,而那正是下面這段走訪所要拆開的東西。
    public func isFocused(_ widget: Widget) -> Bool {
        guard let responder = widget.window?.firstResponder else { return false }
        guard let view = responderView(responder) else { return false }
        return view === widget || view.isDescendant(of: widget)
    }

    /// Reports focus arriving and leaving, for any reason.
    ///
    /// **Observes the WINDOW's first responder rather than the widget**, because
    /// the event being reported is one the widget is not told about: the focus
    /// leaving it. A view learns when it resigns only if it is the one resigning,
    /// and Tab, a click elsewhere and VoiceOver all move the focus without asking
    /// it. The window is the one object that sees every move.
    ///
    /// Keyed by the widget so re-installing replaces rather than accumulates --
    /// this runs from the modifier's commit, so it is called on every frame.
    ///
    /// 回報焦點的抵達與離開,無論原因為何。
    ///
    /// **觀察的是**視窗**的 first responder,而不是那個 widget**,因為要回報的那個事件,正是那個
    /// widget 不會被告知的事件:焦點**離開**它。一個 view 只有在「自己是那個放棄者」時才會知道自己
    /// 放棄了焦點;而 Tab、點到別處、VoiceOver,全都會在不問它的情況下移動焦點。視窗是唯一看得見
    /// 每一次移動的那個物件。
    ///
    /// 以 widget 為鍵,好讓重新安裝是**取代**而不是累加——這段是從 modifier 的 commit 執行的,因此每一幀
    /// 都會被呼叫一次。
    public func setFocusChangeHandler(
        ofWidget widget: Widget,
        to handler: @escaping (Bool) -> Void
    ) {
        // The existing observer keeps its `lastValue`; only the handler is
        // replaced.
        //
        // **Rebuilding it here swallowed changes, and the swallow was silent.**
        // This runs on every frame (from `computeLayout` then; from commit now) -- including
        // the frame a focus change itself triggers. A fresh observer starts with
        // `lastValue` set to the CURRENT state, so if the new frame beats the
        // notification, the observer compares the new value against the new
        // value and reports nothing. Measured on 2026-09-16 with P70: clicking
        // away from the name field left `focused field: name` on screen with the
        // focus ring plainly gone.
        //
        // 既有的 observer 保留它的 `lastValue`;只有 handler 被替換。
        //
        // **在此重建它會吞掉改變,而且吞得無聲無息。** 這段每一幀都會執行(當時從 `computeLayout`,現在從 commit)
        // ——包括「一次焦點改變本身所觸發的那一幀」。一個全新的 observer 會把 `lastValue` 設為
        // **當下**的狀態;因此若那個新的一幀跑在通知之前,該 observer 拿新值與新值相比,什麼都不會
        // 回報。2026-09-16 以 P70 量到:從 name 欄位點開之後,畫面上仍寫著 `focused field: name`,
        // 而焦點環明明已經不見了。
        //
        // **And only while it is the same widget.** The key is an address, and
        // an observer outlives nothing it watches: its widget is weak, so when a
        // widget was freed and a new one took its address, the new widget found
        // the dead one's observer, swapped its handler in, and was never
        // reported -- `check()` stops at a `nil` widget. A mismatch builds a new
        // observer and drops every dead one, the way WinUIBackend+Focus.swift
        // already did.
        // **而且只限同一個 widget。** 鍵是一個位址，而 observer 的 widget 是弱參照：一個 widget 被釋放、
        // 新的 widget 佔用它的位址時，新 widget 找到舊的 observer、換上自己的 handler,卻永遠不會被回報
        // ——`check()` 遇到 `nil` widget 就停。不相符時建一個新的 observer 並清掉所有已死的，與
        // WinUIBackend+Focus.swift 原本的做法相同。
        let key = ObjectIdentifier(widget)
        if let existing = Self.focusObservers[key], existing.widget === widget {
            existing.handler = handler
        } else {
            Self.focusObservers = Self.focusObservers.filter { $0.value.widget != nil }
            Self.focusObservers[key] = FocusObserver(
                widget: widget,
                handler: handler,
                backend: self
            )
        }
        if let window = widget.window {
            Self.watchFirstResponder(of: window)
        }
    }

    /// One observer per watched widget.
    ///
    /// Static because the backend is a value and the observation has to outlive
    /// any one call. Keyed by the widget's identity so the table does not grow
    /// with frames, and an entry counts only while its widget is the one asking:
    /// see ``setFocusChangeHandler(ofWidget:to:)``.
    /// 每一個被觀察的 widget 一個 observer。
    ///
    /// 使用 static,因為 backend 是一個值，而這個觀察必須活得比任何單一次呼叫更久。以 widget 的身分為鍵，
    /// 好讓這張表不會隨著幀數成長；而一個項目只有在它的 widget 就是發問者時才算數：見
    /// ``setFocusChangeHandler(ofWidget:to:)``。
    @MainActor static var focusObservers: [ObjectIdentifier: FocusObserver] = [:]

    /// A window whose `firstResponder` is observed, held weakly with its observation.
    /// 一個 `firstResponder` 正被觀察的視窗(弱參照),連同它的觀察。
    @MainActor
    final class FirstResponderWatch {
        weak var window: NSWindow?
        let observation: NSKeyValueObservation

        init(window: NSWindow, observation: NSKeyValueObservation) {
            self.window = window
            self.observation = observation
        }
    }

    @MainActor static var firstResponderWatches: [ObjectIdentifier: FirstResponderWatch] = [:]
    @MainActor static var focusCheckScheduled = false

    /// Observes this window's first responder, once per window.
    ///
    /// **Key-value observation of `firstResponder`, the event AppKit itself
    /// emits when the focus moves**, for any reason: a click, Tab, VoiceOver,
    /// `makeFirstResponder` from this file. Upstream swift-cross-ui observes the
    /// same key path (786899cf, a1a105aa); this tree keeps its own per-widget
    /// observers and has the window tell them to look.
    ///
    /// A text field hands the first responder on to the window's field editor
    /// straight after taking it, so one click is two changes, the first naming
    /// the field and the second an `NSTextView`. ``isFocused(_:)`` maps the
    /// field editor back to its field, and the look is deferred to the next turn
    /// of the main queue and coalesced, so the observers see where the focus
    /// came to rest rather than the step in between -- and so a change made
    /// during a commit is not reported into the middle of that commit.
    ///
    /// 觀察這個視窗的 first responder,每個視窗一次。
    ///
    /// **對 `firstResponder` 做 key-value observation——焦點移動時 AppKit 自己發出的事件**,無論原因：點擊、
    /// Tab、VoiceOver、本檔的 `makeFirstResponder`。上游 swift-cross-ui 觀察同一個 key path(786899cf、
    /// a1a105aa);本樹保留自己的逐 widget observer,由視窗通知它們去看。
    ///
    /// 文字欄位一取得 first responder 就把它轉交給視窗的 field editor,所以一次點擊是兩次改變：第一次指向
    /// 欄位，第二次指向一個 `NSTextView`。``isFocused(_:)`` 把 field editor 對回它的欄位；而查看延到主佇列的
    /// 下一輪並合併，因此 observer 看到的是焦點停下的位置，而不是中間那一步——也因此 commit 期間造成的
    /// 改變，不會被回報進那次 commit 的中途。
    @MainActor
    static func watchFirstResponder(of window: NSWindow) {
        let key = ObjectIdentifier(window)
        if let watch = firstResponderWatches[key], watch.window === window { return }
        firstResponderWatches = firstResponderWatches.filter { $0.value.window != nil }
        let observation = window.observe(\.firstResponder, options: []) { _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { scheduleFocusCheck() }
            }
        }
        firstResponderWatches[key] = FirstResponderWatch(window: window, observation: observation)
    }

    /// Has every observer look again, once, on the next turn of the main queue.
    /// 讓每個 observer 在主佇列的下一輪再看一次(只一次)。
    @MainActor
    static func scheduleFocusCheck() {
        guard !focusCheckScheduled else { return }
        focusCheckScheduled = true
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                focusCheckScheduled = false
                for observer in focusObservers.values { observer.check() }
            }
        }
    }

    /// One watched widget and the answer it last reported.
    ///
    /// **No notification of its own any more.** It used to observe
    /// `NSWindow.didUpdateNotification`, which every window posts after every
    /// event, so each watched widget re-asked the responder chain on every mouse
    /// move -- and still missed a focus moved from code, which no event follows
    /// (P91, 2026-10-13, patched by an explicit re-check after `focus` and
    /// `unfocus`). The window's `firstResponder` is now observed instead, see
    /// ``watchFirstResponder(of:)``, and that is the one fact both cases change.
    ///
    /// `@MainActor` on the class, so it is `Sendable` and the deferred check
    /// can hold it.
    ///
    /// 一個被觀察的 widget,以及它上一次回報的答案。
    ///
    /// **它不再有自己的通知。** 它原本觀察 `NSWindow.didUpdateNotification`——每個視窗在每個事件之後都會發出
    /// ——因此每個被觀察的 widget 在每次滑鼠移動時都重問一次 responder chain;而由程式移動的焦點後面沒有
    /// 事件，它仍然漏掉(P91,2026-10-13,以 `focus`/`unfocus` 之後的明確重查補上)。現在改為觀察視窗的
    /// `firstResponder`,見 ``watchFirstResponder(of:)``;兩種情形改變的都是這一個事實。
    ///
    /// `@MainActor` 標在類別上，好讓它是 `Sendable`,能被延後的檢查持有。
    @MainActor
    final class FocusObserver {
        private(set) weak var widget: NSView?
        var handler: (Bool) -> Void
        private let backend: AppKitBackend
        private var lastValue: Bool

        init(widget: NSView, handler: @escaping (Bool) -> Void, backend: AppKitBackend) {
            self.widget = widget
            self.handler = handler
            self.backend = backend
            self.lastValue = backend.isFocused(widget)
        }

        fileprivate func check() {
            guard let widget else { return }
            let now = backend.isFocused(widget)
            guard now != lastValue else { return }
            lastValue = now
            handler(now)
        }
    }

    /// The view a responder stands for, unwrapping a field editor.
    /// 一個 responder 所代表的那個 view;若它是 field editor 則予以拆開。
    private func responderView(_ responder: NSResponder) -> NSView? {
        if let text = responder as? NSText, let field = text.delegate as? NSView {
            return field
        }
        return responder as? NSView
    }

    /// The thing inside this widget that can actually take the keyboard.
    ///
    /// The widget itself when it accepts first responder, otherwise the one
    /// descendant that does. `nil` candidates and several candidates both fall
    /// back to the widget, so the call fails visibly through `focus`'s `Bool`
    /// rather than silently focusing something the caller did not name.
    ///
    /// 這個 widget 裡面那個真正拿得到鍵盤的東西。
    ///
    /// 若 widget 自己接受 first responder 就是它,否則是它底下唯一接受的那個後代。沒有候選與有多個
    /// 候選,都退回 widget 本身——如此該呼叫會透過 `focus` 的 `Bool` **明顯地**失敗,而不是靜默地把
    /// 焦點給了一個呼叫端沒有指名的東西。
    private func responder(in widget: NSView) -> NSView {
        if widget.acceptsFirstResponder { return widget }
        return firstResponderCandidate(in: widget) ?? widget
    }

    /// The single descendant that accepts first responder, or `nil`.
    ///
    /// `nil` for none and `nil` for several, the same rule the accessibility
    /// child finder uses and for the same reason: with two candidates there is
    /// no way to tell which was meant, and picking one would move the keyboard
    /// somewhere the caller did not name.
    /// 唯一一個接受 first responder 的後代;若無則為 `nil`。
    ///
    /// 沒有時為 `nil`,有多個時也為 `nil`——與無障礙那個子元件搜尋器所用的是同一條規則,理由也相同:
    /// 有兩個候選時無從判斷指的是哪一個,而挑一個會把鍵盤送到呼叫端沒有指名的地方。
    private func firstResponderCandidate(in view: NSView) -> NSView? {
        // A disabled control's subtree is not searched, and that is not tidying.
        //
        // **`.disabled(true)` does not stop AppKit focusing the control.** It
        // sets `NSCustomButton.isEnabled`, but that wrapper is a plain `NSView`
        // and the search walks straight past it to the inner `NSButton`, which
        // is still enabled and accepts. Measured with P70 on 2026-09-16: a
        // button marked disabled took the keyboard and the app reported
        // `YES (wrong)`. Tab landing on a control that does nothing is a real
        // defect, not a cosmetic one.
        //
        // 一個被停用的控制項,它的子樹不會被搜尋;而這不是在做整理。
        //
        // **`.disabled(true)` 並不會阻止 AppKit 聚焦那個控制項。** 它設定的是
        // `NSCustomButton.isEnabled`,但那層包裝是一個單純的 `NSView`,而這個搜尋會直接越過它、走到
        // 內層那個仍然啟用、而且會接受的 `NSButton`。2026-09-16 以 P70 量到:一顆標記為停用的按鈕
        // 拿走了鍵盤,而 app 回報 `YES (wrong)`。Tab 落在一個什麼都不做的控制項上,是真正的缺陷,
        // 不是外觀問題。
        if let button = view as? NSCustomButton, !button.isEnabled { return nil }
        if let control = view as? NSControl, !control.isEnabled { return nil }

        var found: NSView?
        for subview in view.subviews {
            let candidate =
                subview.acceptsFirstResponder && enabled(subview)
                    ? subview
                    : firstResponderCandidate(in: subview)
            guard let candidate else { continue }
            if found != nil { return nil }
            found = candidate
        }
        return found
    }

    /// Whether this view is a control that is switched on.
    ///
    /// `true` for anything that is not a control, because "enabled" is a
    /// question only a control answers and a plain view declining it would make
    /// every container unfocusable.
    /// 這個 view 是不是一個「處於啟用狀態」的控制項。
    ///
    /// 對任何「不是控制項」的東西回傳 `true`,因為「是否啟用」是只有控制項才回答得了的問題;讓一個
    /// 單純的 view 對它說「否」,會讓每一個容器都變成無法取得焦點。
    private func enabled(_ view: NSView) -> Bool {
        if let button = view as? NSCustomButton { return button.isEnabled }
        if let control = view as? NSControl { return control.isEnabled }
        return true
    }
}
