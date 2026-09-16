extension View {
    /// Sets the name a screen reader reads for this view.
    ///
    /// Use it when what is on screen is not what should be spoken: a button
    /// showing only an X, an image whose meaning is not its file name, a count
    /// that reads as a bare number out of context.
    ///
    /// 設定螢幕閱讀器為這個 view 讀出的名稱。
    ///
    /// 當「螢幕上的東西」不等於「應該被唸出來的東西」時使用:一個只顯示 X 的按鈕、一張其意義不在
    /// 檔名裡的圖片、一個脫離脈絡後只剩數字的計數。
    public func accessibilityLabel(_ label: String?) -> some View {
        AccessibilityModifier(body: TupleView1(self), attribute: .label(label))
    }

    /// Describes what activating this view will do.
    ///
    /// A screen reader may be configured to skip hints, so a hint must never
    /// carry something the user cannot do without -- that belongs in the label.
    ///
    /// 說明啟動這個 view 會做什麼。
    ///
    /// 螢幕閱讀器可能被設定為跳過提示,因此提示裡絕不能放「使用者非知道不可」的東西——那屬於標籤。
    public func accessibilityHint(_ hint: String?) -> some View {
        AccessibilityModifier(body: TupleView1(self), attribute: .hint(hint))
    }

    /// Sets this view's spoken content, when that differs from its label.
    ///
    /// 設定這個 view 被唸出的內容,當它與標籤不同時。
    public func accessibilityValue(_ value: String?) -> some View {
        AccessibilityModifier(body: TupleView1(self), attribute: .value(value))
    }

    /// Hides this view, and everything inside it, from a screen reader.
    ///
    /// It stays visible. This is for content that is decorative or that repeats
    /// something already spoken.
    ///
    /// 把這個 view、連同它裡面的一切,從螢幕閱讀器隱藏起來。
    ///
    /// 它在視覺上仍然存在。這是給裝飾性的、或重複了已被唸出之內容的東西使用的。
    public func accessibilityHidden(_ hidden: Bool = true) -> some View {
        AccessibilityModifier(body: TupleView1(self), attribute: .hidden(hidden))
    }
}

/// Which accessibility property one ``AccessibilityModifier`` carries.
///
/// **One modifier type with four cases, rather than four modifier types.** The
/// four differ only in which setter they call, and four near-identical structs
/// would be four places for the passthrough to drift apart. The enum is also
/// what keeps `nil` meaningful: a case that is absent from a chain is never
/// written at all, so `.accessibilityLabel("Close")` alone cannot clear a hint
/// set further in.
///
/// 一個 ``AccessibilityModifier`` 帶的是哪一個無障礙屬性。
///
/// **一個 modifier 型別配四個 case,而不是四個 modifier 型別。** 這四者只差在呼叫哪一個 setter,
/// 而四個近乎相同的 struct 就是四個「直通邏輯可能各自漂移」的地方。這個 enum 也是「`nil` 仍然有
/// 意義」的關鍵:一個沒有出現在鏈上的 case 從頭到尾都不會被寫入,因此單獨的
/// `.accessibilityLabel("Close")` 不可能清掉更內層設定的提示。
enum AccessibilityAttribute {
    case label(String?)
    case hint(String?)
    case value(String?)
    case hidden(Bool)
}

/// Applies one accessibility property to its child's own widget.
///
/// **Passes the child through rather than wrapping it**, for the reason
/// ``IdentifiedViewModifier`` records: there is nothing to draw and nothing to
/// intercept. Wrapping would be worse than merely wasteful here -- an extra
/// container is an extra node in the accessibility tree, and the property would
/// land on the wrapper while the screen reader reads the child inside it.
///
/// 把一個無障礙屬性套用到它的子元件**自己**的 widget 上。
///
/// **直接把子元件傳遞出去而不是包住它**,理由與 ``IdentifiedViewModifier`` 所記載的相同:這裡沒有
/// 東西要畫、也沒有東西要攔截。而在此處,包一層會比「只是浪費」更糟——多一個容器就是無障礙樹裡多一個
/// 節點,屬性會落在那個外層上,而螢幕閱讀器讀的是它裡面的子元件。
struct AccessibilityModifier<Content: View>: TypeSafeView {
    typealias Children = TupleView1<Content>.Children

    var body: TupleView1<Content>
    var attribute: AccessibilityAttribute

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> Children {
        body.children(backend: backend, snapshots: snapshots, environment: environment)
    }

    func asWidget<Backend: BaseAppBackend>(
        _ children: Children,
        backend: Backend
    ) -> Backend.Widget {
        children.child0.widget.into()
    }

    /// Applies the property here rather than in ``commit``, because this is the
    /// pass the thing being overridden runs in.
    ///
    /// `Button` calls `updateButton` -- and through it AppKit's
    /// `refreshAccessibilityLabel`, which derives a name from the button's own
    /// text -- from its `computeLayout`. Writing the override in `commit` put it
    /// after that within a frame and before the NEXT frame's layout, so the
    /// derived name won and the modifier looked like it had never run. Measured
    /// on 2026-09-16: `ax_dump` reported `desc='X'` on a button carrying
    /// `.accessibilityLabel("Close")`, while the commit itself had run 15 times.
    ///
    /// Ordering inside this method matters for the same reason: the child lays
    /// out first, deriving whatever it derives, and the override lands on top.
    ///
    /// 在此套用這個屬性,而不是在 ``commit`` 裡,因為「被覆寫的那個東西」正是在這個階段執行的。
    ///
    /// `Button` 從它的 `computeLayout` 呼叫 `updateButton`——並經由它呼叫 AppKit 的
    /// `refreshAccessibilityLabel`,那會從按鈕自己的文字推導出一個名字。把覆寫寫在 `commit` 裡,
    /// 會讓它落在「同一幀的推導之後、下一幀的 layout 之前」,於是推導出的名字獲勝,而那個 modifier
    /// 看起來就像從未執行過。2026-09-16 量到:`ax_dump` 在一顆帶著 `.accessibilityLabel("Close")`
    /// 的按鈕上回報 `desc='X'`,而那個 commit 本身已經跑了 15 次。
    ///
    /// 本方法**內部**的順序基於同樣的理由而重要:子元件先排版、推導出它要推導的東西,然後覆寫蓋上去。
    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        let result = children.child0.computeLayout(
            with: body.view0,
            proposedSize: proposedSize,
            environment: environment
        )

        // A conformance check rather than `@CastBackend`, which expands to
        // `fatalError`. The five backends convert one at a time -- the same
        // arrangement `ScrollingLists` and `LazyListRows` are under -- and
        // taking an app down because a label could not be set would be far
        // worse than the label being missing.
        //
        // But it warns, and that is not decoration. A wrong or absent screen
        // reader label is invisible to everyone who is not using a screen
        // reader, including whoever wrote it, so silence here is the one
        // outcome that would never be reported.
        //
        // 使用 conformance 檢查,而不是 `@CastBackend`——後者會展開成 `fatalError`。五個 backend
        // 是一次轉一個的(與 `ScrollingLists`、`LazyListRows` 相同的安排),而「因為設不了一個標籤
        // 就把 app 拖垮」會遠比「標籤不見了」更糟。
        //
        // 但它會警告,而那不是裝飾。一個錯誤或缺失的螢幕閱讀器標籤,對每一個沒在用螢幕閱讀器的人
        // 都是隱形的——包括寫下它的那個人——因此在此保持沉默,是唯一一種永遠不會被回報的結果。
        guard let accessible = backend as? any BackendFeatures.Accessibility else {
            logger.warnOnce(
                "\(type(of: backend)) does not support accessibility properties"
            )
            return result
        }

        func apply<B: BackendFeatures.Accessibility>(_ backend: B) {
            let widget = widget as! B.Widget
            switch attribute {
                case .label(let label):
                    backend.setAccessibilityLabel(ofWidget: widget, to: label)
                case .hint(let hint):
                    backend.setAccessibilityHint(ofWidget: widget, to: hint)
                case .value(let value):
                    backend.setAccessibilityValue(ofWidget: widget, to: value)
                case .hidden(let hidden):
                    backend.setAccessibilityHidden(ofWidget: widget, to: hidden)
            }
        }
        apply(accessible)
        return result
    }

    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        _ = children.child0.commit()
    }
}
