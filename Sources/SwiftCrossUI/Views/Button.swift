/// A control that initiates an action.
public struct Button<Label: View> {
    public typealias Content = TupleView1<Label>
    /// The label to show on the button.
    @_spi(Backends) public var label: () -> Label
    /// The action to be performed when the button is clicked.
    @_spi(Backends) public var action: @MainActor @Sendable () -> Void
    /// What the button is for, when that changes how it should look.
    ///
    /// Kept across upstream's move to arbitrary view labels (#590). `width` went
    /// with that change -- `_buttonWidth` is now a frame on the label -- but
    /// `role` is orthogonal to what the label is, and nothing about a generic
    /// label makes a destructive button less destructive.
    ///
    /// 這個按鈕是做什麼用的——當它會改變外觀時。
    ///
    /// 在 upstream 改為任意 view label(#590)之後保留。`width` 隨那次改動一併移除
    /// ——`_buttonWidth` 現在是套在 label 上的一個 frame——但 `role` 與「label 是什麼」正交,
    /// 而「label 是泛型的」這件事不會讓一個破壞性按鈕變得比較不破壞性。
    @_spi(Backends) public var role: ButtonRole?

    /// Whether the button is currently held down.
    ///
    /// **This is what makes ``ButtonStyleConfiguration/isPressed`` more than a
    /// constant.** The backend reports transitions through
    /// ``BackendFeatures/ButtonPressState``, the handler writes them here, and
    /// because this is a `@State` the write reaches ``ViewGraphNode`` the way
    /// every other state change does: `forEachField` observed this property's
    /// publisher when the node was created (`ViewGraphNode.swift:135`), so
    /// `didChange.send()` schedules `bottomUpUpdate()`, which re-enters
    /// ``computeLayout(_:children:proposedSize:environment:backend:)`` on this
    /// same value and rebuilds the configuration from the new flag. Nothing
    /// about the path is button-specific, which is the point -- a press is an
    /// ordinary state change and gets the ordinary re-render.
    ///
    /// Private, and not exposed as a binding. A style reads it from its
    /// configuration; nothing else has any business knowing.
    ///
    /// 按鈕目前是否被按住。
    ///
    /// **這正是讓 ``ButtonStyleConfiguration/isPressed`` 不只是一個常數的東西。** backend 透過
    /// ``BackendFeatures/ButtonPressState`` 回報狀態轉換，handler 把它寫進這裡；而因為這是一個
    /// `@State`，該次寫入抵達 ``ViewGraphNode`` 的路徑，與其他任何狀態改變完全相同：節點建立時
    /// `forEachField` 已經觀察了本屬性的 publisher（`ViewGraphNode.swift:135`），因此
    /// `didChange.send()` 會排入 `bottomUpUpdate()`，後者在同一個值上重新進入
    /// ``computeLayout(_:children:proposedSize:environment:backend:)``，並依新的旗標重建
    /// configuration。這條路徑沒有任何按鈕專屬之處，而那正是重點——按下就是一次普通的狀態改變，
    /// 得到的也是普通的重新繪製。
    ///
    /// 宣告為 private，也不對外提供 binding。樣式從自己的 configuration 讀取它；除此之外沒有任何東西
    /// 需要知道。
    @State private var isPressed = false

    /// Creates a button that displays a text label.
    ///
    /// - Parameters:
    ///   - label: The label to show on the button.
    ///   - action: The action to be performed when the button is clicked.
    public init(
        _ label: String,
        action: @escaping @MainActor @Sendable () -> Void = {}
    ) where Label == TupleView1<Text> {
        self.label = { TupleView1(Text(label)) }
        self.action = action
    }

    /// Creates a button that displays a custom view as label.
    ///
    /// - Parameters:
    ///   - label: The label to show on the button.
    ///   - action: The action to be performed when the button is clicked.
    @MainActor
    public init (
        action: @escaping @MainActor @Sendable () -> Void = {},
        @ViewBuilder label: @escaping @MainActor @Sendable () -> Label
    ) {
        self.label = label
        self.action = action
    }

    /// Creates a button with a role, which platforms may render differently.
    ///
    /// SwiftUI spells this `Button(_:role:action:)` and this matches. Separate
    /// from the string initialiser above rather than a defaulted parameter,
    /// because a default would change that one's signature for no benefit.
    ///
    /// Constrained to a `Text` label like its sibling: a role is about what
    /// pressing the button does, and every platform that renders one differently
    /// does so by restyling text. A role on an arbitrary view label has no
    /// agreed meaning, so it is not offered rather than being offered and
    /// ignored.
    ///
    /// 建立一個帶有 role 的按鈕,各平台可能會以不同方式繪製它。
    ///
    /// SwiftUI 中寫作 `Button(_:role:action:)`,此處與之一致。之所以獨立於上方的字串建構式而非加上
    /// 預設參數,是因為預設值會改動那一個的簽名,卻換不到任何好處。
    ///
    /// 與其兄弟一樣限定為 `Text` label:role 講的是「按下去會做什麼」,而每一個會據此改變繪製方式的
    /// 平台,都是透過重新設定文字樣式來做到的。role 套在任意 view label 上並沒有公認的意義,因此
    /// 此處不提供它——而不是提供了卻忽略它。
    public init(
        _ label: String,
        role: ButtonRole?,
        action: @escaping @MainActor @Sendable () -> Void = {}
    ) where Label == TupleView1<Text> {
        self.label = { TupleView1(Text(label)) }
        self.role = role
        self.action = action
    }

    private struct ConstrainedButtonLabel<ConstrainedLabel: View>: View {
        @Environment(\.buttonPadding.x) var horizontalPadding

        var content: ConstrainedLabel
        var width: Int?

        var body: some View {
            content.ifLet(width) { view, width in
                view.frame(width: Double(width - horizontalPadding))
            }
        }
    }

    @MainActor
    @available(
        *,
        deprecated,
        message: "Use @ViewBuilder init of Button instead and apply a frame modifier to the label."
    )
    public func _buttonWidth(_ width: Int?) -> Button<some View> {
        return Button<TupleView1<ConstrainedButtonLabel<TupleView1<Label>>>>(
            action: action,
            label: { ConstrainedButtonLabel(content: body, width: width) }
        )
    }
}

@MainActor
extension Button: TypeSafeView {
    /// The label, unstyled.
    ///
    /// **This is no longer what gets rendered, and that is deliberate.** The
    /// rendered child is ``styledLabel(in:)``, which is either this or a custom
    /// ``ButtonStyle``'s body. `body` stays the bare label because two callers
    /// read it as one: ``_asMenuItems`` and `Menu.resolve(item:)`, which reaches
    /// through it as `button.body.view0.view0.string` to pull the title out of a
    /// `Button<TupleView1<Text>>`. Pushing a style between them and the `Text`
    /// would break a menu item for a style a menu cannot draw anyway.
    ///
    /// 未套用樣式的 label。
    ///
    /// **它已不再是被繪製的東西，而這是刻意的。** 實際被繪製的子節點是 ``styledLabel(in:)``——它要麼
    /// 就是這個，要麼是某個自訂 ``ButtonStyle`` 的 body。`body` 之所以維持為純粹的 label，是因為有兩個
    /// 呼叫端把它當作 label 在讀：``_asMenuItems`` 與 `Menu.resolve(item:)`，後者以
    /// `button.body.view0.view0.string` 穿過它，從 `Button<TupleView1<Text>>` 取出標題。若在它們與
    /// `Text` 之間插入一個樣式，就會為了一個選單根本畫不出來的樣式而弄壞一個選單項目。
    public var body: TupleView1<Label> {
        label()
    }

    /// **``AnyView`` rather than `Label`, since 2026-09-08.**
    ///
    /// A custom ``ButtonStyle``'s `Body` is an associated type reached through
    /// an existential, so its concrete type is not knowable here and the child
    /// has to be erased. `Children` is a static associated type and cannot be
    /// `Label` on the days nobody applies a style, so the erasure is
    /// unconditional.
    ///
    /// **The cost, stated rather than left to be found.** ``AnyView/asWidget(_:backend:)``
    /// creates a container, so every button in every application now has one
    /// more widget between it and its label. That was weighed against the
    /// alternative of ``Button`` not supporting `ButtonStyle` at all, and
    /// against ``Label``, which took the same cost for the same reason when
    /// ``LabelStyle`` landed. It buys the thing `AnyView` is for here: when a
    /// style's body changes shape between updates,
    /// ``AnyView/computeLayout(_:children:proposedSize:environment:backend:)``
    /// notices the type mismatch and rebuilds the child node instead of
    /// silently rendering the old one.
    ///
    /// **自 2026-09-08 起為 ``AnyView``，而非 `Label`。**
    ///
    /// 自訂 ``ButtonStyle`` 的 `Body` 是透過 existential 取得的關聯型別，其具體型別在此處無從得知，
    /// 因此子節點必須被抹除型別。`Children` 是靜態的關聯型別，不可能「在沒有人套用樣式的日子裡」是
    /// `Label`，所以這個抹除是無條件的。
    ///
    /// **代價在此明說，而不是留給人去發現。** ``AnyView/asWidget(_:backend:)`` 會建立一個容器，因此
    /// 現在每個應用程式中的每一顆按鈕，與其 label 之間都多了一層 widget。這是與「``Button`` 乾脆完全
    /// 不支援 `ButtonStyle`」相權衡的結果；``Label`` 在 ``LabelStyle`` 落地時也基於相同理由付出了相同
    /// 代價。它換到的正是 `AnyView` 在此處的用途：當某個樣式的 body 在兩次更新之間改變了形狀，
    /// ``AnyView/computeLayout(_:children:proposedSize:environment:backend:)`` 會察覺型別不符並重建
    /// 子節點，而不是默默地繼續繪製舊的那一個。
    typealias Children = TupleViewChildren1<AnyView>

    /// The view actually placed inside the platform's button widget.
    ///
    /// Without a custom style this is the label and nothing else, so the
    /// platform draws the button exactly as it did before ``ButtonStyle``
    /// existed. With one, it is the style's body, and the label is handed to it
    /// through the configuration for the style to place where it likes.
    ///
    /// 真正被放進平台按鈕 widget 內的 view。
    ///
    /// 在沒有自訂樣式時，它就是 label 本身，別無其他，因此平台繪製按鈕的方式與 ``ButtonStyle`` 出現
    /// 之前完全相同。有自訂樣式時，它是該樣式的 body，而 label 則經由 configuration 交給樣式，由樣式
    /// 自行決定要放在哪裡。
    func styledLabel(in environment: EnvironmentValues) -> AnyView {
        guard let style = environment.customButtonStyle else {
            return AnyView(label())
        }

        return AnyView(
            style.makeBody(
                configuration: ButtonStyleConfiguration(
                    label: label(),
                    isPressed: isPressed,
                    role: role
                )
            )
        )
    }

    /// The environment the platform button is updated with.
    ///
    /// **A custom style forces ``EnvironmentValues/buttonStyle`` to `.plain`.**
    /// Without that the backend keeps drawing its own bordered chrome, and the
    /// style's body renders on top of a border the application did not ask for
    /// and cannot remove -- the button would look like two buttons. `.plain` is
    /// also the style every backend gives zero ``BackendFeatures/ViewLabelButtons/buttonPadding(in:)``
    /// for, so the style's own padding is the only padding, which is what a
    /// style author writing `configuration.label.padding(8)` expects.
    ///
    /// This is why ``EnvironmentValues/customButtonStyle`` is a separate entry
    /// rather than a case of ``EnvironmentValues/buttonStyle``: the two values
    /// are live at the same time and say different things.
    ///
    /// 用來更新平台按鈕的 environment。
    ///
    /// **自訂樣式會把 ``EnvironmentValues/buttonStyle`` 強制設為 `.plain`。** 若不這麼做，backend 仍會
    /// 畫出它自己的外框，而樣式的 body 就疊在一個應用程式沒有要求、也無法移除的邊框之上——那顆按鈕會
    /// 看起來像兩顆按鈕。`.plain` 同時也是所有 backend 都給予零
    /// ``BackendFeatures/ViewLabelButtons/buttonPadding(in:)`` 的樣式，因此樣式自身的 padding 就是
    /// 唯一的 padding，而那正是一位寫下 `configuration.label.padding(8)` 的樣式作者所預期的。
    ///
    /// 這也正是 ``EnvironmentValues/customButtonStyle`` 之所以是獨立 entry、而非
    /// ``EnvironmentValues/buttonStyle`` 之一個 case 的原因：兩個值同時有效，且陳述的是不同的事。
    func buttonEnvironment(from environment: EnvironmentValues) -> EnvironmentValues {
        guard environment.customButtonStyle != nil else {
            return environment
        }
        // Spelled out rather than `.plain`: `with` infers its `T` from the key
        // path *and* the value at once, and naming the type keeps that inference
        // off the critical path of a line every styled button runs.
        // 完整寫出型別而非只寫 `.plain`：`with` 的 `T` 是同時由 key path 與該值推導出來的，明確指名
        // 型別可讓這條「每一顆套用樣式的按鈕都會執行」的敘述不必倚賴那次推導。
        return environment.with(\.buttonStyle, PrimitiveButtonStyle.plain)
    }

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> Children {
        Children(
            styledLabel(in: environment),
            backend: backend,
            snapshots: snapshots,
            environment: environment
        )
    }

    func asWidget<Backend: BaseAppBackend>(
        _ children: Children,
        backend: Backend
    ) -> Backend.Widget {
        backend.createButton(wrapping: children.child0.widget.into())
    }

    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        // A distinct name rather than shadowing the parameter, so that a later
        // reader cannot use the unadjusted `environment` by accident: below this
        // line every use has to be the adjusted one.
        // 使用不同的名稱而非遮蔽參數，以免日後的讀者不小心用到未經調整的 `environment`：
        // 在這一行以下，每一處都必須用調整過的那一個。
        let styleEnvironment = buttonEnvironment(from: environment)
        let buttonPadding = backend.buttonPadding(in: styleEnvironment)
        let childEnvironment = backend.computeButtonLabelEnvironment(from: styleEnvironment)

        var childProposal = proposedSize
        if let proposedWidth = proposedSize.width {
            childProposal.width = max(proposedWidth - Double(buttonPadding.x), 0)
        }
        // **The height is NOT proposed to the label, and that is what stops a
        // button from being squeezed to a three-pixel bar.**
        //
        // A proposal of zero height reached the label, the label answered with
        // nothing, and the button's minimum size became its padding. That
        // number is not academic: a window opens at
        // `max(minimumWindowSize, proposedWindowSize)`, so a page whose minimum
        // is computed from squeezed buttons opens at a height where the buttons
        // are squeezed. Measured with P50 on AppKit 2026-09-17: the window came
        // up 780x825, section 2's three buttons were three-pixel bars with no
        // legible text while every `Text` around them rendered, and the
        // instrumented window pass reported `minimum (82, 797)` -- about 150
        // points short of the height the same content needs to draw.
        //
        // A button's height is its label's height plus padding on every backend
        // here; none of them stretch or compress one vertically. Letting the
        // label answer with its own height is therefore not a new policy, it is
        // the one the widgets already have.
        //
        // **高度不會被提議給標籤,而這正是「按鈕不會被壓成三像素長條」的原因。**
        //
        // 一個高度為零的提議抵達了標籤,標籤以「什麼都沒有」作答,於是這顆按鈕的最小尺寸變成只剩 padding。
        // 那個數字不是紙上談兵:視窗會以 `max(minimumWindowSize, proposedWindowSize)` 開啟,因此一頁
        // 「最小尺寸是由被壓扁的按鈕算出來的」內容,就會在「按鈕被壓扁」的那個高度開啟。2026-09-17 於
        // AppKit 上以 P50 實測:視窗以 780x825 開啟,第 2 區塊的三顆按鈕是三像素高、文字無法辨讀的長條,
        // 而周圍每一個 `Text` 都正常;加了儀器的視窗流程回報 `minimum (82, 797)`——比同一份內容真正需要
        // 的高度少了約 150 點。
        //
        // 在此處的每一個 backend 上,一顆按鈕的高度都是「標籤高度加上 padding」;沒有任何一個會把按鈕
        // 垂直拉伸或壓縮。因此讓標籤以它自己的高度作答,並不是一項新政策,而是那些 widget 本來就有的行為。
        //
        // **Except where the window cannot grow, and there the old behaviour is
        // the right one.** All of the above is about a minimum size the window
        // will be opened at; on iOS and Android the window is the screen and a
        // minimum is not a request anybody can grant. Measured 2026-09-18:
        // after the width half of this landed, P5 on an iPhone went from three
        // alert buttons that wrapped to two lines each and fitted inside the
        // 440-point window, to three one-line labels in a row wider than the
        // window, cut off at both ends. Nothing had asked for a wider window
        // because nothing could.
        //
        // So a fixed-size window keeps the proposal it always had: the button
        // may be compressed, its label wraps, and the content stays on screen.
        // The flag comes from the window layer rather than from a check on the
        // operating system -- the question is whether THIS window can grow, and
        // `WindowReference` already asks the backend exactly that.
        //
        // **除了「視窗長不大」的情況,而在那裡,舊行為才是對的。** 以上這一切講的都是「視窗將據以開啟的
        // 最小尺寸」;在 iOS 與 Android 上,視窗就是螢幕,而最小尺寸不是任何人給得起的要求。
        // 2026-09-18 實測:寬度那一半落地之後,iPhone 上的 P5 從「三顆 alert 按鈕各自折成兩行、
        // 整排放得進 440 點視窗」,變成「三個一行的標籤排成一列、比視窗更寬、兩端被切掉」。
        // 沒有任何東西要求過更寬的視窗,因為沒有任何東西要得起。
        //
        // 因此固定大小的視窗維持它一直以來的提議:按鈕可以被壓縮、它的標籤會折行、內容留在畫面上。
        // 這個旗標來自視窗層而不是對作業系統的判斷——要問的是「**這個**視窗能不能長大」,
        // 而 `WindowReference` 本來就正在問 backend 這件事。
        if environment.windowSizeIsFixed {
            if let proposedHeight = proposedSize.height {
                childProposal.height = max(proposedHeight - Double(buttonPadding.y), 0)
            }
        } else {
            childProposal.height = nil
        }

        // **And no WIDTH either, when the width proposed is zero.** That probe is
        // the window asking for a minimum size, and a button's minimum is its
        // label at its ideal width plus padding -- not its label squeezed into
        // no width at all.
        //
        // Without this, the line above lands the layout system in the case
        // `Text`'s own documentation calls out: with no height limit, a text view
        // proposed zero width puts one WORD (or, at width 1, one CHARACTER) per
        // line, and that height becomes the window's minimum. Measured
        // 2026-09-18 on Windows, where windows open at
        // `max(minimumWindowSize, proposedWindowSize)`: 8 of the 23 apps in
        // `testapp/measurements/window-sizes-winui-sta-20260917.csv2` opened far
        // taller than before, P50 at 782x2198 against 782x918 -- and P50's five
        // button labels hold 110 characters, which at ~20 points a line is the
        // 1280 points it grew by. GTK was the same: P50 808x1005 -> 808x1228.
        //
        // With the width probe left unproposed, every one of those heights is
        // back where it was, on both Windows backends, and the collapse this
        // change set out to fix stays fixed: at a zero proposal a button now
        // reports one line plus padding rather than padding alone.
        //
        // What it does change is minimum WIDTH, and that is the honest half: a
        // window can no longer be narrower than its widest button. P5 measured
        // 482x412 -> 526x412 on WinUI and 508x448 -> 582x448 on GTK. Heights on
        // both: unchanged.
        //
        // **當被提議的寬度為零時,連寬度也不提議。** 那次探詢是視窗在問最小尺寸,而一顆按鈕的最小尺寸,是
        // 「標籤在其理想寬度下的大小加上 padding」——不是「標籤被擠進零寬度」。
        //
        // 少了這一步,上一行就會把版面系統帶進 `Text` 自己的文件所點名的那個情況:在沒有高度限制時,被提議
        // 零寬度的文字會一行放一個**單詞**(在寬度 1 時是一個**字元**),而那個高度會變成視窗的最小高度。
        // 2026-09-18 於 Windows 實測(該處視窗以 `max(minimumWindowSize, proposedWindowSize)` 開啟):
        // `testapp/measurements/window-sizes-winui-sta-20260917.csv2` 中 23 支 app 有 8 支開得遠高於先前,
        // P50 為 782x2198 對上 782x918——而 P50 的五個按鈕標籤共 110 個字元,以每行約 20 點計,正是它多出來的
        // 1280 點。GTK 相同:P50 808x1005 → 808x1228。
        //
        // 把寬度那一側留為「未提議」之後,上述每一個高度在兩個 Windows backend 上都回到原值,而這次改動原本
        // 要修的塌陷依然是修好的:在零提議下,按鈕現在回報的是「一行加上 padding」,而不是只有 padding。
        //
        // 真正改變的是最小**寬度**,而那是誠實的另一半:視窗不再能比它最寬的按鈕更窄。P5 在 WinUI 上量到
        // 482x412 → 526x412,在 GTK 上 508x448 → 582x448;兩者的高度都沒有變。
        //
        // Not on a window that cannot grow: see the note above on
        // `windowSizeIsFixed`. There the point of the probe is reversed -- the
        // layout needs to know how small this button CAN be, because nothing
        // is going to widen the screen for it.
        // 在長不大的視窗上不適用:見上方關於 `windowSizeIsFixed` 的說明。在那裡這次探詢的用意是相反的
        // ——版面要知道的是這顆按鈕**能縮到多小**,因為不會有人為了它把螢幕變寬。
        if proposedSize.width == 0 && !environment.windowSizeIsFixed {
            childProposal.width = nil
        }

        // `styledLabel(in:)` rather than `body.view0`: it is rebuilt from the
        // current `isPressed` on every pass, so a press that came in since the
        // last layout produces a new configuration and a fresh `makeBody`
        // result here. That is the whole delivery mechanism -- there is no
        // separate "tell the style it was pressed" call anywhere.
        // 此處用 `styledLabel(in:)` 而非 `body.view0`：它會在每一趟都依當前的 `isPressed` 重新建構，
        // 因此自上次排版以來發生的按壓，會在此處產生新的 configuration 與新的 `makeBody` 結果。
        // 這就是全部的傳遞機制——別處並沒有另一個「通知樣式它被按下了」的呼叫。
        let childResult = children.child0.computeLayout(
            with: styledLabel(in: styleEnvironment),
            proposedSize: childProposal,
            environment: childEnvironment
        )

        backend.updateButton(
            widget,
            // The role rides in on the environment rather than as a parameter,
            // so that adding it does not change `updateButton`'s signature and
            // break every backend at once. Written unconditionally, including
            // the nil case, because a widget is reused across updates and a
            // button that stops being destructive has to stop looking it.
            // role 是搭著 environment 傳入，而非作為參數，如此新增它便不會改動 `updateButton` 的
            // 簽名、一次弄壞所有 backend。此處無條件寫入（包含 nil 的情況），因為 widget 會在多次
            // 更新之間被重複使用，而一個不再具有破壞性的按鈕也必須不再看起來具有破壞性。
            environment: styleEnvironment.with(\.buttonRole, role),
            action: action
        )

        // Buttons should always be set to label size + padding.
        // The backend representation of a button is expected not to have a minSize.
        let size = SIMD2(
            Int(childResult.size.width) + buttonPadding.x,
            Int(childResult.size.height) + buttonPadding.y
        )

        return ViewLayoutResult.leafView(size: ViewSize(size))
    }

    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        _ = children.child0.commit()
        backend.setSize(of: widget, to: layout.size.vector)
        installPressHandler(widget, backend: backend)
    }

    /// Installs the handler that keeps ``isPressed`` in step with the platform.
    ///
    /// In `commit` rather than `computeLayout`, matching `OnHoverModifier`:
    /// layout runs repeatedly during probing passes, commit runs once per
    /// update, and the handler only needs to exist by the time the user can
    /// touch the widget.
    ///
    /// **The cast is soft, and only for backends outside the shipped five.**
    /// ``BackendFeatures/ButtonPressState`` is in ``FullAppBackend`` and in each
    /// shipped backend's feature list, so `GtkBackend`, `WinUIBackend`,
    /// `AppKitBackend`, `UIKitBackend` and `AndroidBackend` all take the branch
    /// that installs. `DummyBackend`, `CursesBackend`, `LVGLBackend` and
    /// `QtBackend` do not conform, and for those -- and only those -- the
    /// project's rules allow degrading. `@CastBackend` is not used here for
    /// exactly that reason: it expands to a `fatalError`, and every button in
    /// every application goes through this line.
    ///
    /// The nested generic function opens the existential so that `B.Widget` is a
    /// real type; that is the same shape `@CastBackend` expands to, written out
    /// because the guard has to fall through instead of trapping.
    ///
    /// The handler drops writes that would not change the value. A press
    /// schedules a re-render, the re-render commits, and committing reinstalls
    /// the handler -- so an unconditional write would publish a change on every
    /// commit and the update loop would never settle.
    ///
    /// 安裝那個讓 ``isPressed`` 與平台保持同步的 handler。
    ///
    /// 放在 `commit` 而非 `computeLayout`，與 `OnHoverModifier` 一致：排版在探測階段會重複執行，而
    /// commit 每次更新只執行一次，且 handler 只需要在使用者能碰到該 widget 之前存在即可。
    ///
    /// **這個轉型是柔性的，而且只為了那五個已發布 backend 以外的對象。**
    /// ``BackendFeatures/ButtonPressState`` 已列入 ``FullAppBackend`` 以及每一個已發布 backend 的
    /// feature 清單，因此 `GtkBackend`、`WinUIBackend`、`AppKitBackend`、`UIKitBackend` 與
    /// `AndroidBackend` 全都會走到安裝的那一支。`DummyBackend`、`CursesBackend`、`LVGLBackend` 與
    /// `QtBackend` 不 conform，而本專案的規則正是只允許對這些——也僅限這些——降級。此處不使用
    /// `@CastBackend`，理由恰恰在此：它會展開為 `fatalError`，而每個應用程式中的每一顆按鈕都會經過
    /// 這一行。
    ///
    /// 巢狀的泛型函式用來開啟 existential，好讓 `B.Widget` 是一個真正的型別；這與 `@CastBackend` 展開
    /// 出來的形狀相同，之所以手寫，是因為此處的 guard 必須放行而非中止。
    ///
    /// handler 會丟棄不會改變數值的寫入。一次按壓排入一次重繪，重繪會 commit，而 commit 會重新安裝
    /// handler——因此若無條件寫入，每次 commit 都會發布一次變更，更新迴圈將永遠不會停下來。
    private func installPressHandler<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        backend: Backend
    ) {
        guard
            let pressReportingBackend = backend
                as? any BaseAppBackend & BackendFeatures.ButtonPressState
        else {
            return
        }

        let isPressedState = _isPressed

        func install<PressBackend: BaseAppBackend & BackendFeatures.ButtonPressState>(
            _ backend: PressBackend
        ) {
            backend.updateButtonPressHandler(widget as! PressBackend.Widget) { pressed in
                guard isPressedState.wrappedValue != pressed else { return }
                isPressedState.wrappedValue = pressed
            }
        }

        install(pressReportingBackend)
    }

    public var _asMenuItems: [MenuItem] {
        if let self = self as? Button<TupleView1<Text>> {
            return [.button(self)]
        } else {
            // TODO(stackotter): Figure out a better fallback for non-text buttons in menus
            return body._asMenuItems
        }
    }
}
