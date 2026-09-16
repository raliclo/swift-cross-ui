/// Tracks, and moves, which view the keyboard is talking to.
///
/// ```swift
/// @FocusState var focused: Bool
///
/// TextField("Name", text: $name)
///     .focused($focused)
/// Button("Jump to name") { focused = true }
/// ```
///
/// With several fields, give it an optional enum instead and name the field
/// each view stands for:
///
/// ```swift
/// enum Field { case name, email }
/// @FocusState var field: Field?
///
/// TextField("Name", text: $name).focused($field, equals: .name)
/// TextField("Email", text: $email).focused($field, equals: .email)
/// ```
///
/// **It is read as well as written, and the reading half is the hard one.**
/// Writing to it moves the focus; that much a plain ``State`` plus a method call
/// could do. The focus also moves for reasons the app did not cause -- Tab, a
/// click elsewhere, a screen reader, Android's directional pad -- and this
/// property is written back when that happens. Without that half it would be
/// correct only until the user touched anything, which is worse than not having
/// it: a value that is usually right invites code that trusts it.
///
/// **Built on ``State`` rather than beside it.** The storage, the change
/// publisher and the view-graph update are identical needs, and a second copy of
/// `StateImpl` would be a second copy to drift.
///
/// 追蹤——並移動——鍵盤正在對哪一個 view 說話。
///
/// **它是被讀的,也是被寫的;而「讀」的那一半才是難的那一半。** 寫入它會移動焦點,那一半用一個普通的
/// ``State`` 加一次方法呼叫就做得到。焦點也會因為 app 沒有造成的原因而移動——Tab、點到別的地方、
/// 螢幕閱讀器、Android 的方向鍵——而這個屬性會在那時被寫回。少了那一半,它只在「使用者什麼都沒碰」時
/// 是對的,而那比沒有它更糟:一個「通常是對的」值,會招來信任它的程式碼。
///
/// **建立在 ``State`` 之上,而不是與它並列。** 儲存、變更發佈與 view graph 更新是完全相同的需求,
/// 而再抄一份 `StateImpl` 就是再抄一份會漂移的東西。
@propertyWrapper
public struct FocusState<Value: Hashable>: ObservableProperty {
    private let state: State<Value>

    public var didChange: Publisher { state.didChange }

    public var wrappedValue: Value {
        get { state.wrappedValue }
        nonmutating set { state.wrappedValue = newValue }
    }

    /// The handle ``View/focused(_:)`` takes.
    ///
    /// A distinct type rather than a plain ``Binding``, so that `.focused($x)`
    /// cannot be handed a binding to some unrelated `Bool`. The modifier does
    /// something a binding alone does not describe -- it asks the backend to
    /// move the keyboard -- and the type is what says so at the call site.
    ///
    /// ``View/focused(_:)`` 所接受的把手。
    ///
    /// 使用一個獨立的型別而非單純的 ``Binding``,如此 `.focused($x)` 就不可能被餵進一個指向某個無關
    /// `Bool` 的 binding。這個 modifier 做的事不是一個 binding 本身所能描述的——它請求 backend 去
    /// 移動鍵盤——而這個型別就是在呼叫處說出這件事的東西。
    public var projectedValue: FocusState<Value>.Binding {
        Binding(value: state.projectedValue)
    }

    public struct Binding {
        let value: SwiftCrossUI.Binding<Value>
    }

    public init(wrappedValue initialValue: Value) {
        state = State(wrappedValue: initialValue)
    }

    public func update(with environment: EnvironmentValues, previousValue: FocusState<Value>?) {
        state.update(with: environment, previousValue: previousValue?.state)
    }
}

extension FocusState {
    /// `@FocusState var field: Field?` with no initial value: nothing focused.
    /// `@FocusState var field: Field?`,不給初始值:什麼都沒有焦點。
    public init() where Value: ExpressibleByNilLiteral {
        self.init(wrappedValue: nil)
    }

    /// `@FocusState var focused: Bool` with no initial value: not focused.
    ///
    /// Spelled out rather than left to the caller, because `@FocusState var
    /// focused = false` reads as a starting position someone chose, and this one
    /// is not a choice -- a view that has not been focused yet is the only
    /// possible starting state.
    /// `@FocusState var focused: Bool`,不給初始值:沒有焦點。
    ///
    /// 明確寫出來、而不是留給呼叫端,因為 `@FocusState var focused = false` 讀起來像是某人挑的一個
    /// 起始位置;而這一個不是選擇——一個尚未取得焦點的 view,是唯一可能的起始狀態。
    public init() where Value == Bool {
        self.init(wrappedValue: false)
    }
}

extension View {
    /// Binds this view's focus to a `Bool`.
    ///
    /// Setting the property to `true` asks the backend to focus this view;
    /// `false` asks it to give the focus up. The property is written back when
    /// the focus moves for any other reason.
    ///
    /// 把這個 view 的焦點綁定到一個 `Bool`。
    ///
    /// 把該屬性設為 `true`,是請 backend 讓這個 view 取得焦點;設為 `false`,是請它放棄焦點。
    /// 當焦點因為其他任何原因而移動時,該屬性會被寫回。
    public func focused(_ binding: FocusState<Bool>.Binding) -> some View {
        FocusModifier(
            body: TupleView1(self),
            isFocused: focusProjection(binding.value, equals: true, unfocused: false)
        )
    }

    /// Binds this view's focus to one case of a value.
    ///
    /// The property holds which view is focused, or `nil` for none. Setting it
    /// to `value` focuses this view; the view writes `nil` back when it loses
    /// the focus, and writes `value` when it gains it.
    ///
    /// **`nil` on losing, rather than leaving the old value**: a property that
    /// still named a field after the user clicked away would report a focus that
    /// is not there, and that is exactly the reading half this type exists for.
    ///
    /// 把這個 view 的焦點綁定到某個值的其中一個 case。
    ///
    /// 該屬性持有的是「哪一個 view 有焦點」,沒有時為 `nil`。把它設為 `value` 會讓這個 view 取得焦點;
    /// 當這個 view 失去焦點時它會寫回 `nil`,取得時則寫回 `value`。
    ///
    /// **失去焦點時寫 `nil`,而不是留著舊值**:一個「在使用者點開之後仍然指名某個欄位」的屬性,回報的
    /// 是一個並不存在的焦點——而那恰好就是這個型別存在的理由(讀的那一半)。
    public func focused<V: Hashable>(
        _ binding: FocusState<V?>.Binding,
        equals value: V
    ) -> some View {
        FocusModifier(
            body: TupleView1(self),
            isFocused: focusProjection(binding.value, equals: value, unfocused: nil)
        )
    }
}

/// Projects a focus binding down to the `Bool` the modifier works in.
///
/// A free function rather than two copies inside the two `focused` overloads,
/// which differ only in what "unfocused" is spelled as -- `false` for the `Bool`
/// form, `nil` for the optional form.
/// 把一個 focus binding 投影成 modifier 實際運作的那個 `Bool`。
///
/// 使用一個自由函式,而不是在兩個 `focused` 多載裡各抄一份;那兩者的唯一差別,是「沒有焦點」怎麼寫
/// ——`Bool` 形式是 `false`,optional 形式是 `nil`。
func focusProjection<Value: Hashable>(
    _ binding: Binding<Value>,
    equals focusedValue: Value,
    unfocused: Value
) -> Binding<Bool> {
    Binding(
        get: { binding.wrappedValue == focusedValue },
        set: { binding.wrappedValue = $0 ? focusedValue : unfocused }
    )
}

/// Asks the backend to focus its child, and reports back when the focus moves.
///
/// **Passes the child through rather than wrapping it**, the same as
/// ``AccessibilityModifier``: there is nothing to draw and nothing to intercept,
/// and an extra container would be one more widget in every form this is used
/// on.
///
/// 請 backend 讓它的子元件取得焦點,並在焦點移動時回報。
///
/// **直接把子元件傳遞出去而不是包住它**,與 ``AccessibilityModifier`` 相同:這裡沒有東西要畫、也沒有
/// 東西要攔截,而多一層容器,就是在每一張用到它的表單裡多一個 widget。
struct FocusModifier<Content: View>: TypeSafeView {
    typealias Children = TupleView1<Content>.Children

    var body: TupleView1<Content>
    var isFocused: Binding<Bool>

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

    /// Installs the handler and reconciles the binding against the backend.
    ///
    /// In `computeLayout` for the reason ``AccessibilityModifier`` records: this
    /// is the pass that runs for every view on every frame, and a passthrough
    /// modifier's later passes are not guaranteed to.
    ///
    /// **Only a DISAGREEMENT is acted on, and only in one direction per frame.**
    /// The binding says what the app wants and `isFocused` says what the
    /// platform has; writing both every frame would have the modifier fight the
    /// user, stealing the focus back a frame after they clicked away.
    ///
    /// 在 `computeLayout` 裡,理由與 ``AccessibilityModifier`` 所記載的相同:這是「每一幀對每一個
    /// view 都會跑」的那個階段,而直通型 modifier 的後段階段並不保證會執行。
    ///
    /// **只有在兩者「不一致」時才動作,而且每一幀只往一個方向動。** binding 說的是 app 想要什麼,
    /// `isFocused` 說的是平台目前是什麼;每一幀都兩邊都寫,會讓這個 modifier 與使用者對打——在他們
    /// 點開之後的下一幀又把焦點搶回來。
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
        // `fatalError`. The five backends convert one at a time, and taking an
        // app down because the keyboard could not be moved would be far worse
        // than the keyboard not moving.
        // 使用 conformance 檢查,而不是 `@CastBackend`——後者會展開成 `fatalError`。五個 backend 是
        // 一次轉一個的,而「因為移動不了鍵盤就把 app 拖垮」會遠比「鍵盤沒有移動」更糟。
        guard let focusable = backend as? any BackendFeatures.FocusableViews else {
            logger.warnOnce("\(type(of: backend)) does not support focus")
            return result
        }

        func apply<B: BackendFeatures.FocusableViews>(_ backend: B) {
            let widget = widget as! B.Widget
            let binding = isFocused
            backend.setFocusChangeHandler(ofWidget: widget) { focused in
                // Guarded so the write is a change. The handler fires on both
                // edges and on some platforms fires again for a focus the app
                // asked for, which would otherwise be a state write -- and a
                // view-graph update -- on every click.
                // 加上守衛,讓寫入必定是一次**改變**。這個 handler 兩個邊緣都會觸發,而在某些平台上,
                // 連「app 自己要求的那次取得焦點」也會再觸發一次;否則那會變成每次點擊都寫入狀態
                // ——並觸發一次 view graph 更新。
                if binding.wrappedValue != focused {
                    binding.wrappedValue = focused
                }
            }

            let wanted = binding.wrappedValue
            guard wanted != backend.isFocused(widget) else { return }
            if wanted {
                // A refusal is left in the binding rather than papered over. On
                // Android a view in touch mode legitimately declines, and a
                // property that said `true` while the keyboard was elsewhere
                // would be the exact lie this type exists to prevent.
                // 被拒絕時就把結果留在 binding 裡,而不是粉飾過去。在 Android 上,touch mode 中的
                // view 會正當地拒絕;而一個「鍵盤在別處、它卻說 `true`」的屬性,正是這個型別所要
                // 防止的那種謊言。
                if !backend.focus(widget) {
                    binding.wrappedValue = false
                }
            } else {
                backend.unfocus(widget)
            }
        }
        apply(focusable)
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
