extension EnvironmentValues {
    /// What the nearest ``View/focusEffectDisabled(_:)`` above said: `true`
    /// hides the focus ring, `false` shows it again, `nil` when no view said
    /// anything.
    ///
    /// **Three states, not a `Bool`**: an explicit `false` has to reach the
    /// backend so that `.focusEffectDisabled(false)` inside a disabled subtree
    /// brings one control's ring back, and an untouched app must not cost a
    /// backend call per view. ``ViewGraphNode`` reads it at commit.
    ///
    /// 上方最近的 ``View/focusEffectDisabled(_:)`` 說了什麼:`true` 隱藏焦點環,`false` 重新顯示，沒有任何 view
    /// 說過時為 `nil`。**三種狀態而不是 `Bool`**:明確的 `false` 必須送到 backend,在被停用的子樹內寫
    /// `.focusEffectDisabled(false)` 才能把單一控制項的焦點環開回來;而沒用到它的 app 不可以每個 view 都多一次 backend 呼叫。
    @Entry var focusEffectDisabledSetting: Bool? = nil

    /// Whether views here draw their focus ring, as SwiftUI names it.
    /// 此處的 view 是否畫出焦點環;名稱與 SwiftUI 相同。
    public var isFocusEffectEnabled: Bool {
        focusEffectDisabledSetting != true
    }
}

extension View {
    /// Hides the focus ring of the controls in this view.
    ///
    /// ```swift
    /// VStack {
    ///     TextField("Name", text: $name)
    ///     Button("Save") { save() }
    /// }
    /// .focusEffectDisabled()
    /// ```
    ///
    /// The controls still take the focus, Tab still reaches them and
    /// `.focused` still moves the focus to them; only the ring is not drawn.
    /// It applies to every control in the subtree, including ones added later,
    /// and `.focusEffectDisabled(false)` further in turns the ring back on for
    /// the views under it. The same signature as SwiftUI.
    ///
    /// 隱藏這個 view 裡控制項的焦點環。控制項照樣取得焦點,Tab 照樣到得了,`.focused` 照樣能把焦點移給它們;
    /// 只是不畫焦點環。它作用於子樹中的每個控制項(包括之後才加入的),而更內層的 `.focusEffectDisabled(false)`
    /// 會替其下的 view 把焦點環開回來。簽章與 SwiftUI 相同。
    public func focusEffectDisabled(_ disabled: Bool = true) -> some View {
        EnvironmentModifier(self) { environment in
            environment.with(\.focusEffectDisabledSetting, disabled)
        }
    }

    /// Keeps the keyboard focus out of this view and everything in it.
    ///
    /// ```swift
    /// TextField("Name", text: $name)
    /// HStack {
    ///     TextField("Locked", text: $locked)
    ///     Button("Help") { showHelp() }
    /// }
    /// .focusDisabled()
    /// TextField("Email", text: $email)  // Tab from Name lands here
    /// ```
    ///
    /// Tab and Shift-Tab step over the whole subtree, pressing a control in it
    /// does not focus it, and `.focused` on a view in it is refused and written
    /// back as not focused. Buttons still act on a press; a text field in it
    /// cannot be typed into. If the subtree holds the focus when it becomes
    /// disabled, the focus leaves it.
    ///
    /// **Not `.focusable(false)`.** That one is about a single view that is not
    /// a control (``View/focusable(_:)``); this one closes a subtree of
    /// controls. SwiftUI has no modifier for this -- the closest is applying
    /// `.focusable(false)` to each control -- so the name says what it does
    /// rather than borrowing one. Upstream SwiftCrossUI spells it
    /// `.focusable(.disabled)`, which would overload the name develop already
    /// gives to the single-view feature.
    ///
    /// 讓鍵盤焦點進不了這個 view 及其中的一切。Tab 與 Shift-Tab 跨過整個子樹，按下其中的控制項不會讓它取得焦點，
    /// 對其中的 view 用 `.focused` 會被拒絕並寫回未聚焦。按鈕被按下仍會動作;其中的文字欄位則無法輸入。若子樹在被停用時
    /// 持有焦點，焦點會離開它。**不是 `.focusable(false)`**:那個是針對單一個非控制項的 view(``View/focusable(_:)``),
    /// 這個關上的是一整個控制項的子樹。SwiftUI 沒有這樣的 modifier(最接近的是對每個控制項套 `.focusable(false)`),
    /// 所以名稱直接說出它做的事，不借用別的名字。上游 SwiftCrossUI 寫成 `.focusable(.disabled)`,那會讓 develop
    /// 已經給了單一 view 功能的名稱多出一個多載。
    public func focusDisabled(_ disabled: Bool = true) -> some View {
        FocusDisabledModifier(self, isDisabled: disabled)
    }
}

/// The container `.focusDisabled` puts around its view.
///
/// Always a container, whether `isDisabled` is true or not, so that toggling
/// it does not replace the widget and lose the state inside.
///
/// `.focusDisabled` 放在 view 外面的容器。不論 `isDisabled` 真假都是容器，切換時才不會換掉 widget、丟失裡面的狀態。
struct FocusDisabledModifier<Child: View>: TypeSafeView {
    var body: TupleView1<Child>
    var isDisabled: Bool

    init(_ child: Child, isDisabled: Bool) {
        body = TupleView1(child)
        self.isDisabled = isDisabled
    }

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> TupleViewChildren1<Child> {
        body.children(backend: backend, snapshots: snapshots, environment: environment)
    }

    func asWidget<Backend: BaseAppBackend>(
        _ children: TupleViewChildren1<Child>,
        backend: Backend
    ) -> Backend.Widget {
        let container = backend.createContainer()
        backend.insert(children.child0.widget.into(), into: container, at: 0)
        return container
    }

    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: TupleViewChildren1<Child>,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        let childResult = children.child0.computeLayout(
            with: body.view0,
            proposedSize: proposedSize,
            environment: environment
        )
        return ViewLayoutResult(size: childResult.size, childResults: [childResult])
    }

    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: TupleViewChildren1<Child>,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        _ = children.child0.commit()
        backend.setPosition(ofChildAt: 0, in: widget, to: .zero)
        backend.setSize(of: widget, to: layout.size.vector)

        // A conformance check rather than `@CastBackend`, which expands to
        // `fatalError`. Every shipped backend conforms except WinUIBackend, whose
        // conformance is owed (2026-11-24); until then the subtree stays
        // focusable there and the log says so once.
        // 使用 conformance 檢查而不是 `@CastBackend`(後者展開成 `fatalError`)。除了 WinUIBackend 之外，每個已發布的
        // backend 都已 conform;WinUIBackend 的 conformance 尚欠(2026-11-24),在那之前子樹在該處仍可聚焦，log 會說一次。
        guard let containers = backend as? any BackendFeatures.FocusDisabledContainers else {
            logger.warnOnce(
                """
                \(Backend.self) does not implement BackendFeatures.FocusDisabledContainers, \
                so .focusDisabled leaves its subtree focusable on this backend
                """
            )
            return
        }
        func mark<B: BackendFeatures.FocusDisabledContainers>(_ backend: B) {
            backend.setFocusDisabled(isDisabled, onContainer: widget as! B.Widget)
        }
        mark(containers)
    }
}

/// Hands each view-graph node's ``EnvironmentValues/focusEffectDisabledSetting``
/// to the backend, once per change.
///
/// Per node rather than in the modifier, because the ring belongs to the
/// controls in the subtree and only their own nodes know their widgets -- a
/// container walking its descendants once would miss every control that
/// appears later.
///
/// 把每個 view graph 節點的 ``EnvironmentValues/focusEffectDisabledSetting`` 交給 backend,每次改變一次。
/// 放在每個節點而不是 modifier 裡，因為焦點環屬於子樹中的控制項，只有它們自己的節點知道自己的 widget——容器只走一次
/// 子孫，會漏掉之後才出現的每個控制項。
@MainActor
enum FocusEffectApplication {
    static func apply<Backend: BaseAppBackend>(
        _ setting: Bool?,
        applied: inout Bool?,
        to widget: Backend.Widget,
        backend: Backend
    ) {
        guard setting != applied else { return }
        applied = setting
        guard let effects = backend as? any BackendFeatures.FocusEffects else {
            logger.warnOnce(
                """
                \(Backend.self) does not implement BackendFeatures.FocusEffects, \
                so .focusEffectDisabled leaves the focus ring drawn on this backend
                """
            )
            return
        }
        func set<B: BackendFeatures.FocusEffects>(_ backend: B) {
            backend.setFocusEffectDisabled(setting ?? false, on: widget as! B.Widget)
        }
        set(effects)
    }
}
