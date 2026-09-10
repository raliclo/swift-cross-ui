//
//  Copyright © 2015 Tomas Linhart. All rights reserved.
//

import CGtk

open class Window: Widget {
    public var child: Widget?

    public convenience init() {
        self.init(gtk_window_new())
        registerSignals()
    }

    @GObjectProperty(named: "title") public var title: String?
    @GObjectProperty(named: "resizable") public var resizable: Bool
    @GObjectProperty(named: "deletable") public var deletable: Bool
    @GObjectProperty(named: "modal") public var isModal: Bool
    @GObjectProperty(named: "decorated") public var isDecorated: Bool
    @GObjectProperty(named: "destroy-with-parent") public var destroyWithParent: Bool

    public var isActive: Bool {
        gtk_window_is_active(castedPointer()).toBool()
    }

    public var isMaximized: Bool {
        gtk_window_is_maximized(castedPointer()).toBool()
    }

    public var isFullscreen: Bool {
        gtk_window_is_fullscreen(castedPointer()).toBool()
    }

    /// Asks the window manager to maximize the window. It is a request, not a
    /// command: the window manager may ignore it, and it does not take effect
    /// synchronously, so ``isMaximized`` can still be false immediately after.
    public func maximize() {
        gtk_window_maximize(castedPointer())
    }

    public func unmaximize() {
        gtk_window_unmaximize(castedPointer())
    }

    public func setTransient(for other: Window) {
        gtk_window_set_transient_for(castedPointer(), other.castedPointer())
    }

    /// The window must not be used after destruction.
    public func destroy() {
        gtk_window_destroy(castedPointer())
    }

    public var defaultSize: Size {
        get {
            var width: gint = 0
            var height: gint = 0
            gtk_window_get_default_size(castedPointer(), &width, &height)

            return Size(width: Int(width), height: Int(height))
        }
        set(size) {
            gtk_window_set_default_size(castedPointer(), gint(size.width), gint(size.height))
        }
    }

    public var size: Size {
        get {
            // TODO: The default size is the current size of the window unless we're
            //   in full screen. But we can't simply use the widget size, cause that
            //   doesn't work before the first proper update or something like that.
            defaultSize
        }
        set {
            // We set the 'default size' here because setting the size of the window
            // actually sets the window's minimum size. Whereas the 'default size' is
            // just the current size of the window, except when the window is in full
            // screen, in which case the 'default size' is the size that the window
            // should return to when it leaves full screen.
            defaultSize = newValue
        }
    }

    public func setMinimumSize(to minimumSize: Size) {
        gtk_widget_set_size_request(
            castedPointer(),
            gint(minimumSize.width),
            gint(minimumSize.height)
        )
    }

    public func setChild(_ child: Widget) {
        self.child?.parentWidget = nil
        self.child = child
        gtk_window_set_child(castedPointer(), child.widgetPointer)
        child.parentWidget = self
    }

    public func removeChild() {
        gtk_window_set_child(castedPointer(), nil)
        child?.parentWidget = nil
        child = nil
    }

    public func getChild() -> Widget? {
        return child
    }

    /// The natural height of this window's titlebar widget, or nil when it has
    /// none.
    ///
    /// The point of asking is that `gtk_widget_measure` answers WITHOUT a size
    /// allocation, so a caller can know what the decoration will cost before the
    /// window is mapped -- which is the only way to size a window correctly on
    /// the first layout pass rather than correcting it on the second.
    ///
    /// nil is a real answer, not a failure: `gtk_window_get_titlebar` returns
    /// NULL when nothing has called `gtk_window_set_titlebar`, and GTK then
    /// draws whatever decoration the platform gives. There is no widget to
    /// measure in that case and the caller has to fall back to measuring after
    /// the fact.
    ///
    /// 本視窗 titlebar widget 的自然高度；若沒有 titlebar 則為 nil。
    ///
    /// 之所以問這件事，是因為 `gtk_widget_measure` **不需要 size allocation** 就能回答，
    /// 因此呼叫端可以在視窗被 map 之前就知道裝飾的成本——而那是「第一次版面計算就把視窗開對」
    /// 的唯一途徑，否則就只能在第二次計算時修正。
    ///
    /// nil 是一個真正的答案，不是失敗：未曾呼叫 `gtk_window_set_titlebar` 時
    /// `gtk_window_get_titlebar` 會回傳 NULL，此時 GTK 畫的是平台給的裝飾。那種情況下沒有
    /// widget 可量，呼叫端只能退回事後量測。
    /// Gives the window a titlebar widget of our own, so its height becomes
    /// measurable before the window is mapped.
    ///
    /// This exists because of what ``titlebarNaturalHeight`` cannot answer.
    /// `gtk_window_get_titlebar` returns NULL until something calls
    /// `gtk_window_set_titlebar`, and GTK's own default decoration is not a
    /// widget anyone can query -- so the height that
    /// `gtk_window_set_default_size` will silently spend is unknowable, and the
    /// window opens 39px short and corrects on the second layout pass. See
    /// `bugs/Gtk4-bugs.md` section 5.
    ///
    /// ~~A `GtkHeaderBar` is the same widget GTK would have created for
    /// itself, so this is not adding decoration -- it is taking ownership of
    /// the decoration that was already there.~~ **MEASURED AND FALSE,
    /// 2026-09-04.** On P16 asking for 900x600, GTK's own decoration costs
    /// **39px** and a `GtkHeaderBar` installed here measures **47** -- the
    /// window becomes 8px taller, so this DOES add decoration.
    ///
    /// A second claim was made here and withdrawn within the hour: that the
    /// header bar also caused `Gtk-CRITICAL: Allocation width too small`. It
    /// did not. That warning appears eight times on a DEFAULT run too, byte for
    /// byte, and counting them before and after is what showed it -- 8 and 8.
    /// Blaming a new symptom on the change you just made is the easiest
    /// mistake available when the change is fresh.
    ///
    /// Kept rather than deleted because the sentence was the reason to expect
    /// this to be free, and it was wrong in the direction that matters: the
    /// cost is permanent chrome on every window, paid to fix a shortfall of
    /// similar size.
    ///
    /// ~~`GtkHeaderBar` 正是 GTK 原本會自行建立的那個 widget，因此這並不是「加上裝飾」，而是接管
    /// 本來就存在的那份裝飾。~~ **2026-09-04 實測，此說為假。** 在 P16 要求 900x600 的情況下，
    /// GTK 自身的裝飾為 **39px**，而此處裝上的 `GtkHeaderBar` 量得 **47**——視窗因此高了 8px，
    /// 所以這**確實是**加上裝飾。它同時帶來 header bar 自己的最小寬度，在同一次執行中產生了
    /// `Gtk-CRITICAL: Allocation width too small. Tried to allocate 679x480,
    /// but GtkPassthroughFixed needs at least 680x480`。
    ///
    /// 保留而不刪除，因為那句話正是「以為這件事免費」的來源，而它錯在最要緊的方向：代價是每一個
    /// 視窗上永久多出的裝飾，用來換掉一個尺寸相近的短少。
    ///
    /// NOT called by default. Owning the titlebar means owning its appearance,
    /// and that is a visible change to every window this backend opens; it is a
    /// decision rather than a patch. Wired to `SCUI_DEBUG_DECORATION=2` so the
    /// question can be measured before it is decided.
    ///
    /// 為視窗裝上一個我們自己的 titlebar widget，使其高度在視窗 map 之前即可量測。
    ///
    /// 它之所以存在，是因為 ``titlebarNaturalHeight`` 回答不了的那件事。在有東西呼叫
    /// `gtk_window_set_titlebar` 之前，`gtk_window_get_titlebar` 一律回傳 NULL，而 GTK 自己的
    /// 預設裝飾並不是任何人能查詢的 widget——於是 `gtk_window_set_default_size` 將會默默花掉的
    /// 那段高度無從得知，視窗因而少開 39px，並在第二次版面計算時修正。見
    /// `bugs/Gtk4-bugs.md` 第 5 節。
    ///
    /// `GtkHeaderBar` 正是 GTK 原本會自行建立的那個 widget，因此這並不是「加上裝飾」——而是
    /// **接管本來就存在的那份裝飾**，以換取能夠量測它。
    ///
    /// **預設不會被呼叫。** 接管 titlebar 等於接管它的外觀，那是對本 backend 所開之每一個視窗的
    /// 可見改動；它是一項決策，不是一個補丁。此處接到 `SCUI_DEBUG_DECORATION=2`，好讓這個問題
    /// 能在被決定之前先被量測。
    public func installMeasurableTitlebar() {
        gtk_window_set_titlebar(castedPointer(), gtk_header_bar_new())
    }

    /// Replaces the titlebar with a `GtkHeaderBar` holding the given widgets,
    /// or restores GTK's own decoration when both lists are empty.
    ///
    /// This lives here rather than in `GtkBackend` because every raw GTK call in
    /// this project does. `castedPointer()` is internal to this module, and the
    /// first attempt at the toolbar called it from `GtkBackend+Toolbar.swift` and
    /// got `'castedPointer' is inaccessible due to 'internal' protection level`
    /// -- which was the compiler pointing at the layering, not an obstacle to
    /// work around with a wider access level.
    ///
    /// Restoring is `nil`, not an empty header bar. An empty bar would still be
    /// a titlebar: it keeps its height (47px measured, against GTK's own 39 --
    /// see ``installMeasurableTitlebar()``) and shows an empty strip.
    ///
    /// 以一個裝著給定 widget 的 `GtkHeaderBar` 取代 titlebar；當兩份清單皆為空時，則恢復 GTK 自己的
    /// 裝飾。
    ///
    /// 它放在這裡而不是 `GtkBackend`，因為本專案所有的原始 GTK 呼叫都放在這裡。`castedPointer()`
    /// 對本模組而言是 internal，而工具列的第一次嘗試正是從 `GtkBackend+Toolbar.swift` 呼叫它，得到
    /// `'castedPointer' is inaccessible due to 'internal' protection level`——那是編譯器在指出分層，
    /// 而不是一個「把存取層級放寬就能繞過」的障礙。
    ///
    /// 恢復時傳的是 `nil`，而不是一個空的 header bar。空的 bar 仍然是一個 titlebar：它保有自己的高度
    /// （實測 47px，相對於 GTK 自身的 39——見 ``installMeasurableTitlebar()``），並顯示成一條空白橫條。
    public func setHeaderBar(leading: [Widget], trailing: [Widget]) {
        guard !leading.isEmpty || !trailing.isEmpty else {
            gtk_window_set_titlebar(castedPointer(), nil)
            return
        }

        let headerBar = gtk_header_bar_new()

        // `GtkHeaderBar` is an opaque type in the generated bindings while
        // `gtk_header_bar_new` returns a `GtkWidget *`, so each pack call needs
        // the cast even though it is the same object.
        // 在產生的綁定中 `GtkHeaderBar` 是 opaque 型別，而 `gtk_header_bar_new` 回傳的是
        // `GtkWidget *`，因此即使指的是同一個物件，每次 pack 呼叫都需要這個轉換。
        let bar = OpaquePointer(headerBar)

        // `parentWidget` is assigned, not just packed, and that assignment is
        // what makes the buttons work.
        //
        // MEASURED 2026-09-08. The first version packed `widget.widgetPointer`
        // and stopped there. Every button drew correctly, highlighted on hover,
        // and did nothing at all when pressed -- P53's counters stayed at 0 and
        // "last pressed" stayed "(none)". The cause is that this wrapper
        // connects its GTK signals in ``Widget/didMoveToParent()``, which only
        // runs from `parentWidget`'s `didSet`; packing the raw pointer bypasses
        // it, so `Button.clicked` is stored and the "clicked" signal is never
        // connected. Nothing errors -- the closure simply has no caller.
        //
        // Distinguishing that from "the click never reached the titlebar" took a
        // control: an action file clicking the window's own close button, which
        // is a widget on this same header bar. It closed the window in 5s
        // against an 8s hold, so clicks do arrive and the fault was here.
        //
        // The reference is weak, so this does not keep the button alive --
        // `GtkBackend.toolbarButtons` does, and that is why it exists.
        //
        // 此處是「指派 `parentWidget`」而非只是 pack，而正是那個指派讓按鈕能運作。
        //
        // 2026-09-08 實測。第一版只 pack 了 `widget.widgetPointer` 就停手。每個按鈕都畫得正確、滑過去
        // 也有高亮，按下去卻毫無反應——P53 的計數器停在 0、「last pressed」停在「(none)」。原因在於本
        // wrapper 是在 ``Widget/didMoveToParent()`` 中連接 GTK 訊號的，而該方法只會由 `parentWidget`
        // 的 `didSet` 觸發；直接 pack 原始指標會繞過它，於是 `Button.clicked` 只是被存了起來，
        // 「clicked」訊號從未被連接。沒有任何東西報錯——那個 closure 只是沒有呼叫者。
        //
        // 要把它與「點擊根本沒抵達 titlebar」區分開來，需要一個對照：一個點擊視窗自身關閉鈕的動作檔，
        // 而該鈕正是這條 header bar 上的 widget。它在 8 秒停留的情況下 5 秒就關掉了視窗，因此點擊確實
        // 抵達得了，故障在此處。
        //
        // 該參照是 weak 的，因此這並不會讓按鈕存活——存活是靠 `GtkBackend.toolbarButtons`，那也正是
        // 它存在的理由。
        for widget in leading {
            gtk_header_bar_pack_start(bar, widget.widgetPointer)
            widget.parentWidget = self
        }
        for widget in trailing {
            gtk_header_bar_pack_end(bar, widget.widgetPointer)
            widget.parentWidget = self
        }

        gtk_window_set_titlebar(castedPointer(), headerBar)
    }

    /// Every direct child of the window widget, with its type name and the
    /// height it measures at, BEFORE anything is presented.
    ///
    /// `gtk_window_get_titlebar` answers only for a titlebar this program
    /// installed with `gtk_window_set_titlebar`. Under client-side decorations
    /// -- which is what GTK4 uses on Windows -- GTK builds its own titlebar and
    /// that call returns NULL, so `titlebarNaturalHeight` is nil and the
    /// allowance computed from it is zero. The decoration is still a widget; it
    /// is just one this program did not create. Walking the children finds it
    /// without taking the decoration over, which is what made option (3)
    /// expensive.
    ///
    /// Returns type name and natural height per child, in tree order.
    ///
    /// 視窗 widget 的**每一個直接子項**,連同它的型別名稱與量得的高度,**在任何東西被 present
    /// 之前**取得。
    ///
    /// `gtk_window_get_titlebar` 只會回答「由本程式以 `gtk_window_set_titlebar` 裝上的」那一條
    /// titlebar。在 client-side decorations 之下——那正是 GTK4 於 Windows 所採用的方式——GTK 會
    /// 建立**它自己的** titlebar,而該呼叫回傳 NULL,於是 `titlebarNaturalHeight` 為 nil、
    /// 由它算出的 allowance 為零。**那條裝飾仍然是一個 widget,只是不是本程式建立的那一個。**
    /// 遍歷子項就能找到它,而**不必接管裝飾**——後者正是方案 (3) 昂貴的原因。
    public var childMeasurements: [(typeName: String, naturalHeight: Int)] {
        var results: [(String, Int)] = []
        var child = gtk_widget_get_first_child(castedPointer())
        while let current = child {
            // `G_OBJECT_TYPE_NAME` is a C macro and Swift cannot see it, so the
            // type is read out of the GTypeInstance by hand. `g_type_name` is a
            // real function and is reachable.
            // `G_OBJECT_TYPE_NAME` 是一個 C 巨集,Swift 看不到它,因此此處手動從 GTypeInstance
            // 讀出型別。`g_type_name` 是真正的函式,構得著。
            let instance = UnsafeRawPointer(current)
                .assumingMemoryBound(to: GTypeInstance.self)
            let gtype = instance.pointee.g_class.pointee.g_type
            let typeName = String(cString: g_type_name(gtype))
            var minimum: gint = 0
            var natural: gint = 0
            var minimumBaseline: gint = 0
            var naturalBaseline: gint = 0
            gtk_widget_measure(
                current,
                GTK_ORIENTATION_VERTICAL,
                -1,
                &minimum,
                &natural,
                &minimumBaseline,
                &naturalBaseline
            )
            results.append((typeName, Int(natural)))
            child = gtk_widget_get_next_sibling(current)
        }
        return results
    }

    /// The height a client-side-decoration header bar takes, measured from a
    /// throwaway `GtkHeaderBar` rather than from the window's own.
    ///
    /// **Why this exists.** #79: an app asking for 620x420 gets 620x381 of
    /// content, the missing 39 being the header bar, because
    /// `gtk_window_set_default_size` sizes the WINDOW and under CSD the header
    /// is inside it. The obvious fix -- add the header's height to the request
    /// -- needed that height before the first `present`, and it was not
    /// available: measured 2026-09-10, the window's children are `GtkBox=0`
    /// before present and `GtkCustomRootWidget=341 GtkHeaderBar=39` after map.
    /// GTK does not build the header until the window is realised, so there is
    /// nothing to ask.
    ///
    /// **But a header bar does not have to be THAT header bar to be measured.**
    /// The 39 is what the theme gives any `GtkHeaderBar`, so one built here,
    /// measured, and dropped answers the same question without the window
    /// existing yet -- and without taking the decoration over, which is what
    /// made the other route expensive.
    ///
    /// Returns nil if the widget cannot be created at all, so a caller can tell
    /// "no decoration" from "measured zero".
    ///
    /// 一條 client-side-decoration header bar 所佔的高度,量自一條**用完即丟**的
    /// `GtkHeaderBar`,而不是量視窗自己的那一條。
    ///
    /// **它為何存在。** #79:一個要求 620x420 的 app 拿到的是 620x381 的內容,少掉的 39 就是
    /// header bar——因為 `gtk_window_set_default_size` 設定的是**視窗**,而在 CSD 之下 header
    /// 位於視窗**之內**。顯而易見的修法(把 header 的高度加進請求)需要在第一次 `present`
    /// **之前**取得該高度,而那取不到:2026-09-10 實測,視窗的子項在 present 前是 `GtkBox=0`、
    /// 在 map 後是 `GtkCustomRootWidget=341 GtkHeaderBar=39`。**GTK 在視窗 realize 之前根本不會
    /// 建立那條 header**,因此沒有東西可問。
    ///
    /// **但一條 header bar 不必是「那一條」才量得。** 那個 39 是主題給予**任何**
    /// `GtkHeaderBar` 的高度,因此在此處建一條、量它、再丟掉,就能在視窗尚不存在的情況下回答
    /// 同一個問題——而且**不必接管裝飾**,後者正是另一條路線昂貴的原因。
    ///
    /// 若該 widget 根本建不出來則回傳 nil,好讓呼叫端能區分「沒有裝飾」與「量到零」。
    /// **MEASURED 2026-09-10: a bare `GtkHeaderBar` gives 47, not the 39 the
    /// window's own header takes.** The first version of this returned that 47
    /// and would have over-corrected by 8px, which is the same class of error
    /// as the 39 it was meant to fix. Kept as a parameter so the three variants
    /// can be compared in one run rather than argued about:
    ///
    /// - `.bare` — `gtk_header_bar_new()` and nothing else. 47.
    /// - `.withTitlebarClass` — plus the `titlebar` CSS class, which is what
    ///   `gtk_window_set_titlebar` adds. A header bar's height comes from the
    ///   theme, and the theme selects on that class.
    /// - `.insideAWindow` — put in a real (never presented) `GtkWindow` via
    ///   `set_titlebar`, which is the only variant with the full CSS node path
    ///   the real one has.
    ///
    /// **2026-09-10 實測:一條「光禿的」`GtkHeaderBar` 量得 47,而不是視窗自己那條所佔的 39。**
    /// 本方法的第一版就是回傳那個 47,那會**過度修正 8px**——與它原本要修的那個 39 屬於同一類錯誤。
    /// 此處保留為參數,好讓三種變體能在**同一次執行中**互相對照,而不是拿來爭論。
    public enum HeaderBarProbeKind {
        case bare
        case withTitlebarClass
        case insideAWindow
    }

    public static func probeHeaderBarHeight(_ kind: HeaderBarProbeKind) -> Int? {
        guard let probe = gtk_header_bar_new() else { return nil }
        // Sink the floating reference so the widget is owned here, then release
        // it. Without the sink, `g_object_unref` on a floating reference warns.
        // 先 sink 掉那個 floating reference,讓此處持有該 widget,再釋放它。
        // 少了這次 sink,對一個 floating reference 呼叫 `g_object_unref` 會發出警告。
        g_object_ref_sink(probe)
        defer { g_object_unref(probe) }

        var host: UnsafeMutablePointer<GtkWindow>?
        switch kind {
            case .bare:
                break
            case .withTitlebarClass:
                gtk_widget_add_css_class(probe, "titlebar")
            case .insideAWindow:
                // Never presented, so it costs no window on screen. It is
                // destroyed at the end, and the probe goes with it -- which is
                // why the unref above is balanced by the ref_sink and not by a
                // second release here.
                // 從不 present,因此螢幕上不會多出任何視窗。它會在最後被銷毀,而那條 probe 也
                // 隨之而去——這也正是上方那次 unref 由 ref_sink 配對、而非在此處再釋放一次的原因。
                // `gtk_window_new` returns a GtkWidget*; the titlebar and
                // destroy calls both want GtkWindow*. Rebinding through a raw
                // pointer is the same widening every other cast in this file
                // does, and GTK guarantees the layout because GtkWindow starts
                // with its GtkWidget.
                // `gtk_window_new` 回傳的是 GtkWidget*,而 titlebar 與 destroy 兩個呼叫要的都是
                // GtkWindow*。經由 raw pointer 重新繫結,與本檔中其他每一次轉型是同一種放寬,
                // 而 GTK 保證了記憶體佈局,因為 GtkWindow 的開頭就是它的 GtkWidget。
                host = gtk_window_new().map {
                    UnsafeMutableRawPointer($0).assumingMemoryBound(to: GtkWindow.self)
                }
                if let host {
                    gtk_window_set_titlebar(host, probe)
                    // Realize, do NOT present. Measured 2026-09-10: an
                    // unrealized header bar measures 47 and the one in a live
                    // window is 39, and `.insideAWindow` alone still gave 47 --
                    // so the difference is realization, not the CSS context.
                    // `gtk_widget_realize` creates the surface without ever
                    // putting a window on screen.
                    // **Realize,但不要 present。** 2026-09-10 實測:一條未 realize 的 header bar
                    // 量得 47,而活在視窗中的那條是 39,且**單靠 `.insideAWindow` 仍然得到 47**
                    // ——因此差別在於 **realize**,不在 CSS context。`gtk_widget_realize` 會建立
                    // surface,而完全不需要讓任何視窗出現在螢幕上。
                    gtk_widget_realize(
                        UnsafeMutableRawPointer(host)
                            .assumingMemoryBound(to: GtkWidget.self)
                    )
                }
        }
        defer {
            if let host {
                gtk_window_destroy(host)
            }
        }

        var minimum: gint = 0
        var natural: gint = 0
        var minimumBaseline: gint = 0
        var naturalBaseline: gint = 0
        gtk_widget_measure(
            probe,
            GTK_ORIENTATION_VERTICAL,
            -1,
            &minimum,
            &natural,
            &minimumBaseline,
            &naturalBaseline
        )
        // MINIMUM, not natural. Measured 2026-09-10 across three variants and
        // with the host window realized: natural is 47 every time, and the
        // header GTK actually lays out is 39. Adding 47 overshot by exactly 8
        // (`shortfall 0x-8`), which is 47 - 39. GTK gives its own header bar the
        // minimum, not the natural, so the minimum is the number that predicts
        // the layout.
        //
        // The natural is still measured, above, because asking for both costs
        // nothing and a future theme that lays the header out at its natural
        // height would show up as a fresh non-zero shortfall rather than as
        // silence.
        //
        // **取 minimum,不是 natural。** 2026-09-10 在三種變體之下、且 host 視窗已 realize 的
        // 情況下實測:natural **每次都是 47**,而 GTK 實際排版出來的 header 是 **39**。
        // 加 47 恰好超出 8(`shortfall 0x-8`),而 8 正是 47 − 39。**GTK 給它自己的 header bar
        // 的是 minimum、不是 natural**,因此 minimum 才是能預測版面的那個數字。
        //
        // 上方仍然把 natural 一併量了出來,因為兩個一起問不花任何代價;而若日後有某個主題改以
        // natural 高度來排版 header,那會表現為一個**全新的非零 shortfall**,而不是一片沉默。
        return Int(minimum)
    }

    public var titlebarNaturalHeight: Int? {
        guard let titlebar = gtk_window_get_titlebar(castedPointer()) else {
            return nil
        }
        var minimum: gint = 0
        var natural: gint = 0
        var minimumBaseline: gint = 0
        var naturalBaseline: gint = 0
        gtk_widget_measure(
            titlebar,
            GTK_ORIENTATION_VERTICAL,
            -1,
            &minimum,
            &natural,
            &minimumBaseline,
            &naturalBaseline
        )
        return Int(natural)
    }

    public func present() {
        gtk_window_present(castedPointer())
    }

    public func close() {
        gtk_window_close(castedPointer())
    }

    public func setEscapeKeyPressedHandler(to handler: (() -> Void)?) {
        escapeKeyPressed = handler

        guard escapeKeyEventController == nil else { return }

        let keyEventController = EventControllerKey()
        keyEventController.keyPressed = { [weak self] _, keyval, _, _ in
            // Returning true stops the key propagating, which is the point of
            // handling it: before the generated signal could return a value
            // (#594) Escape was handled here *and* passed on to everything below.
            // Anything else returns false so it carries on as normal.
            // 回傳 true 會停止該按鍵繼續傳播，而這正是「處理它」的意義：在產生的 signal 能夠回傳值
            // （#594）之前，Escape 會在此被處理，同時仍被往下傳給其他所有元件。其餘按鍵回傳 false，
            // 使其照常繼續傳播。
            guard keyval == GDK_KEY_Escape else { return false }
            self?.escapeKeyPressed?()
            return true
        }
        escapeKeyEventController = keyEventController
        addEventController(keyEventController)
    }

    open override func registerSignals() {
        addSignal(name: "close-request") { [weak self] () in
            guard let self else { return }
            self.onCloseRequest?(self)
        }
        addSignal(name: "destroy") { [weak self] () in
            guard let self else { return }
            self.onDestroy?(self)
        }
        addSignal(name: "notify::scale-factor") { [weak self] () in
            guard let self else { return }
            self.onScaleFactorChange?(self)
        }
    }

    private var escapeKeyEventController: EventControllerKey?
    public var onCloseRequest: ((Window) -> Void)?
    public var onDestroy: ((Window) -> Void)?

    /// Fires when GTK changes the scale factor it lays this window out at.
    ///
    /// The property rather than a display or monitor signal: GTK's scale factor
    /// is the buffer scale it actually used, an integer by design, not the
    /// fraction a display advertises. Watching the display would fire on changes
    /// GTK did not act on and miss the moment it did.
    ///
    /// Public because a backend cannot reach `addSignal`, which is internal to
    /// this module -- registering the signal has to happen in here.
    ///
    /// 當 GTK 改變它為此視窗排版所用的 scale factor 時觸發。
    ///
    /// 監聽的是該屬性，而非顯示器或螢幕的訊號：GTK 的 scale factor 是它實際使用的 buffer
    /// scale，依設計為整數，而非顯示器所宣稱的小數。改為監聽顯示器，會在 GTK 並未據以動作的變化
    /// 上觸發，卻錯過它真正動作的那一刻。
    ///
    /// 之所以公開，是因為 backend 取用不到對本模組為 internal 的 `addSignal`——註冊訊號這件事
    /// 必須發生在這裡。
    public var onScaleFactorChange: ((Window) -> Void)?
    public var escapeKeyPressed: (() -> Void)?
}

final class ValueBox<T> {
    let value: T
    init(value: T) {
        self.value = value
    }
}
