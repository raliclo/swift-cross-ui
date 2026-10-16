import Gtk
import CGtk
import GtkCHelpers
@_spi(Backends) import SwiftCrossUI

extension GtkBackend {
    /// A click on a button, toggle, switch or checkbox leaves keyboard focus
    /// where it was, as AppKit and UIKit controls do; Tab still reaches it.
    ///
    /// GTK's default moves focus to the clicked control. P70's "ask both for
    /// focus" click then took focus off the name field (focused field: none,
    /// 4 changes heard instead of 3), and P72's plain Up after a click on
    /// "Check again" went to GTK's focus navigation instead of the mesh view's
    /// onKeyPress (keys: 1, high 2.30 instead of 2 and 2.40) -- the 2026-10-16
    /// gtk4 sweep on macOS.
    ///
    /// 點擊按鈕、toggle、switch 或 checkbox 時，鍵盤焦點留在原處，與 AppKit、UIKit 的控制項相同;Tab 仍然能到達它。
    /// GTK 預設會把焦點移到被點的控制項。P70 的「ask both for focus」因此把焦點從 name 欄拿走(focused field: none,
    /// 聽到 4 次而非 3 次),P72 點「Check again」之後的 Up 被 GTK 的焦點導覽吃掉，沒有送到 mesh view 的 onKeyPress
    /// (keys: 1、high 2.30,應為 2 與 2.40)——2026-10-16 macOS 上的 gtk4 sweep。
    static func withoutFocusOnClick<W: Widget>(_ widget: W) -> W {
        gtk_widget_set_focus_on_click(widget.widgetPointer, 0)
        return widget
    }
    public func createSimpleButton() -> Widget {
        return Self.withoutFocusOnClick(Button())
    }

    public func updateSimpleButton(
        _ button: Widget,
        label: String,
        environment: EnvironmentValues,
        action: @escaping () -> Void
    ) {
        // The label colour comes from `cssProperties` below, whose `color` the
        // button's label inherits. Measured on GtkBackend (macOS, 2026-10-07):
        // Menu labels drew red, blue, orange from a parent, and a disabled green
        // dimmed. 標籤顏色來自下方 `cssProperties` 的 `color`,按鈕的標籤會繼承它。實測見上。
        let button = button as! Gtk.Button
        button.sensitive = environment.isEnabled
        button.label = label
        button.clicked = { _ in action() }

        // GTK's own class for a destructive action, so the button gets whatever
        // the current theme uses to warn -- red on Adwaita -- rather than a
        // colour this backend picked. `.cancel` gets nothing: GTK has no class
        // for it and inventing one would be this backend's opinion rather than
        // the platform's.
        //
        // Removed as well as added. The widget is reused across updates, so a
        // button that stops being destructive has to stop looking destructive;
        // only adding would make the styling a one-way door.
        //
        // CARRIED ACROSS 2026-09-08, when upstream's #590 moved this method into
        // this file. Upstream's `updateSimpleButton` does not have this block,
        // and taking the new file wholesale would have deleted the role styling
        // without failing anything -- a button would simply have stopped turning
        // red. It surfaced only because both copies existed at once and the
        // redeclaration would not compile.
        //
        // 使用 GTK 自有的「破壞性動作」樣式類別，如此該按鈕便會採用當前主題用來示警的樣式——在
        // Adwaita 上是紅色——而非由本 backend 自行挑選的顏色。`.cancel` 則不套用任何東西：GTK 沒有
        // 對應的類別，而自行發明一個，那會是本 backend 的主張而非平台的主張。
        //
        // 此處會「移除」而不只是「加入」。widget 會在多次更新之間被重複使用，因此一個不再具有破壞性
        // 的按鈕，也必須不再看起來具有破壞性；只加不移會讓這個樣式變成一扇單向門。
        //
        // 於 2026-09-08 一併搬移過來，當時 upstream 的 #590 把本方法移進了這個檔案。upstream 版的
        // `updateSimpleButton` 沒有這一段，而直接整份採用新檔會在不讓任何東西失敗的情況下刪掉這項
        // role 樣式：按鈕只會單純不再變紅。它之所以被發現，只是因為兩份副本同時存在，而重複宣告編不過。
        if environment.buttonRole == .destructive {
            gtk_widget_add_css_class(button.widgetPointer, "destructive-action")
        } else {
            gtk_widget_remove_css_class(button.widgetPointer, "destructive-action")
        }

        button.css.clear()
        button.css.set(
            properties: cssProperties(
                for: environment,
                isControl: true,
                // Stand aside for a role, so GTK's own class can paint it. See
                // the note in cssProperties: this backend's provider outranks
                // the theme, so styling the button and adding a style class at
                // the same time means the class loses silently.
                // 為 role 讓路，使 GTK 自己的類別能夠繪製它。詳見 cssProperties 中的說明：本
                // backend 的 provider 位階高於主題，因此「同時樣式化按鈕又加上樣式類別」會讓該類別
                // 靜默落敗。
                deferToThemeStyleClass: environment.buttonRole == .destructive
            )
        )
    }

    public func createButton(wrapping widget: Widget) -> Widget {
        let button = GtkCustomButton()
        gtk_button_set_child(button.widgetPointer.cast(), widget.widgetPointer)

        widget.horizontalAlignment = .center
        widget.verticalAlignment = .center

        return Self.withoutFocusOnClick(button)
    }

    public func updateButton(
        _ button: Widget,
        environment: EnvironmentValues,
        action: @escaping () -> Void
    ) {
        let button = button as! GtkCustomButton
        button.clicked = { _ in action() }
        button.buttonStyle = environment.resolvedButtonStyle.kind
        button.sensitive = environment.isEnabled
        // GTK's own class for a destructive action, as `updateSimpleButton`
        // does for a Menu: the theme's warning style -- red on Adwaita -- not a
        // colour of ours. Removed as well as added, since the widget is reused.
        // Until 2026-10-07 only the Menu path read the role, so
        // `Button("Delete", role: .destructive)` drew like any other button.
        // GTK 自有的破壞性動作類別，與 `updateSimpleButton` 對 Menu 的做法相同：用主題的警示樣式(Adwaita 上是紅色),
        // 而不是我們的顏色。有加也有移除，因為 widget 會被重複使用。2026-10-07 之前只有 Menu 路徑讀取 role,
        // 因此 `Button("Delete", role: .destructive)` 畫得與其他按鈕無異。
        // A colour the application set wins, as on AppKit: the class fills the
        // button red, and P82's "blue set" drew blue on red (2026-10-16).
        // 應用程式設定的顏色優先，與 AppKit 相同：該類別會把按鈕填成紅色,P82 的「blue set」成了紅底藍字(2026-10-16)。
        if environment.buttonRole == .destructive, environment.foregroundColor == nil {
            gtk_widget_add_css_class(button.widgetPointer, "destructive-action")
        } else {
            gtk_widget_remove_css_class(button.widgetPointer, "destructive-action")
        }
        button.loadCSS(environment: environment)
    }

    /// For a borderless or plain destructive button only: the colour the theme
    /// gives a `.flat.destructive-action` button's text, read from an unshown
    /// probe button so it follows the theme and its variant rather than a
    /// value of ours. A bordered one returns nil: the class paints it, red
    /// with white text, and the label inherits that. Without this a borderless
    /// one drew grey (P82 on GtkBackend, found by the Mac session on
    /// 2026-10-07) -- the core gives a desktop borderless label a dimmed
    /// suggested colour, which outranks the colour inherited from the class.
    /// 僅限無框或 plain 的危險按鈕：主題賦予 `.flat.destructive-action` 按鈕文字的顏色，從一顆不顯示的探針按鈕讀取，
    /// 因此跟隨主題及其變體，而非我們自己的值。bordered 的回傳 nil:class 會把它畫成紅底白字，標籤會繼承。少了這個，
    /// 無框的會是灰字(P82,GtkBackend,Mac session 於 2026-10-07 發現)——core 給桌面無框標籤一個淡化的建議色，
    /// 位階高於從 class 繼承來的顏色。
    public func destructiveButtonLabelColor(
        in environment: EnvironmentValues
    ) -> SwiftCrossUI.Color? {
        guard environment.resolvedButtonStyle.kind != .bordered else { return nil }
        let probe = Gtk.Button()
        gtk_widget_add_css_class(probe.widgetPointer, "flat")
        gtk_widget_add_css_class(probe.widgetPointer, "destructive-action")
        // Inside a throwaway window: GTK resolves theme CSS only for a widget with a
        // root (see `readAmbientColorScheme`), so a loose probe read the light
        // variant's dark red, which P82 drew on the dark background (2026-10-16).
        // 放在一個暫時性視窗裡:GTK 只為有 root 的 widget 解析主題 CSS(見 `readAmbientColorScheme`),
        // 游離的探針讀到的是淺色變體的深紅色,P82 把它畫在深色背景上(2026-10-16)。
        let probeWindow = Gtk.Window()
        probeWindow.setChild(probe)
        let colour = probe.getColor()
        probeWindow.destroy()
        return SwiftCrossUI.Color(
            red: Double(colour.red), green: Double(colour.green),
            blue: Double(colour.blue), opacity: Double(colour.alpha)
        )
    }

    public func buttonPadding(in environment: EnvironmentValues) -> SIMD2<Int> {
        switch environment.resolvedButtonStyle.kind {
            case .bordered: measureBorderedButtonPadding()
            case .plain, .borderless: SIMD2<Int>(0, 0)
        }
    }

    public func defaultButtonStyle() -> PrimitiveButtonStyle {
        .bordered
    }

    func measureBorderedButtonPadding() -> SIMD2<Int> {
        if let borderedButtonPadding { return borderedButtonPadding }

        // Use root environment for consistency.
        let rootEnvironment = computeRootEnvironment(
            defaultEnvironment: EnvironmentValues(backend: self)
        )

        // The test string needs to be long enough to be bigger than minSize.
        let testString = "Teststring"
        let dummyButton = Button()
        dummyButton.label = testString
        dummyButton.css.clear()
        dummyButton.css.set(properties: cssProperties(for: rootEnvironment, isControl: true))

        let textView = CustomLabel(string: testString)
        textView.css.clear()
        // css needs to be set, otherwise text measures way too big.
        textView.css.set(properties: cssProperties(for: rootEnvironment))
        let textSize = size(
            of: testString,
            whenDisplayedIn: textView,
            proposedWidth: nil,
            proposedHeight: nil,
            environment: rootEnvironment
        )

        let buttonSize = naturalSize(of: dummyButton)

        let result = SIMD2(
            Int(buttonSize.x - textSize.x),
            Int(buttonSize.y - textSize.y)
        )

        borderedButtonPadding = result
        return result
    }
}

fileprivate final class GtkCustomButton: Gtk.Button {
    fileprivate var buttonStyle: PrimitiveButtonStyle.Kind = .bordered {
        willSet {
            buttonStyle.removeClass(from: self)
        }
        didSet {
            buttonStyle.setClass(on: self)
        }
    }

    /// The button's own rules, from `loadCSS(environment:)`.
    /// 按鈕自己的規則，來自 `loadCSS(environment:)`。
    private var baseCSS = ""

    /// Both rule sets in the one provider: the button's, then the app's `css`
    /// under `button.customButton.<class>` -- more specific than every rule
    /// above that sets a background, and later than the equally specific
    /// `.flat` one, so what the app asked for wins.
    /// 兩組規則放在同一個 provider:先是按鈕的，再是 app 的 `css`,選擇器為 `button.customButton.<class>`——
    /// 比上方所有設定背景的規則更具體，且排在同樣具體的 `.flat` 規則之後，因此 app 所要求的勝出。
    override func reloadCSS() {
        cssProvider.loadCss(from: baseCSS + "\nbutton.customButton" + css.stringRepresentation)
    }

    init() {
        super.init(gtk_button_new())

        gtk_widget_add_css_class(widgetPointer, "customButton")
    }

    @MainActor
    func loadCSS(environment: EnvironmentValues) {
        // The button's own rules and the app's `css` share one provider, and
        // `loadCss` replaces what a provider holds. Until 2026-10-06 each update
        // replaced the other, so `.inspect { button.css.set(...) }` lost to the
        // next `updateButton` -- AdvancedCustomizationExample's red `+` stayed
        // grey on GtkBackend. `reloadCSS` below writes both.
        // 按鈕自己的規則與 app 的 `css` 共用一個 provider,而 `loadCss` 會取代 provider 的內容。2026-10-06
        // 之前兩者每次更新都互相取代，所以 `.inspect { button.css.set(...) }` 輸給下一次 `updateButton`——
        // AdvancedCustomizationExample 的紅色 `+` 在 GtkBackend 上一直是灰的。下方的 `reloadCSS` 兩者都寫。
        let backgroundColor = GtkBackend.controlBackgroundColor(for: environment)
        // No background of ours on a destructive button: this provider outranks
        // the theme, so a background here would silently beat the
        // `destructive-action` class `updateButton` adds -- the trap
        // `cssProperties(deferToThemeStyleClass:)` documents for the Menu button.
        // A destructive button with a colour of the app's gets no class (see
        // `updateButton`), so it keeps the ordinary background.
        // 帶有 app 指定顏色的危險按鈕不加該類別(見 `updateButton`),因此保留一般背景。
        // 破壞性按鈕上不寫我們自己的背景：本 provider 位階高於主題，在此寫背景會靜默壓過 `updateButton`
        // 加上的 `destructive-action` 類別——即 `cssProperties(deferToThemeStyleClass:)` 為 Menu 按鈕記載的陷阱。
        let backgroundRule =
            environment.buttonRole == .destructive && environment.foregroundColor == nil
            ? "" : "background: \(CSSProperty.rgba(backgroundColor));"
        baseCSS = """
                button.customButton {
                    min-width: 0px;
                    min-height: 0px;
                    padding: 0px;
                    \(backgroundRule)
                    border: none;
                    box-shadow: none;
                }

                button.customButton.flat:active,
                button.customButton.flat.keyboard-activating {
                    opacity: 0.80;
                }

                button.customButton.flat {
                    background: transparent;
                }

                button.customButton.flat:focus {
                    border-radius: 0px;
                }

                button.customButton.flat:disabled {
                    opacity: 0.5;
                }
            """
        // Scoped to THIS button. The provider is installed for the whole
        // display, so a bare `button.customButton` rule from any one button
        // reached every other: a plain button's grey background painted the
        // destructive one beside it, which kept its white `destructive-action`
        // text on a grey that was never its own (P2, WSLg and Windows GTK,
        // 2026-10-07). The app's `css` was already scoped by its class.
        // 限定在**這一顆**按鈕。provider 安裝在整個 display 上，因此任何一顆按鈕的 `button.customButton` 規則都會套到其他按鈕：
        // 一顆普通按鈕的灰色背景畫到了旁邊的破壞性按鈕上，後者保有 `destructive-action` 的白字，底色卻不是自己的
        // (P2,WSLg 與 Windows GTK,2026-10-07)。app 的 `css` 早已用它的類別限定範圍。
        baseCSS = baseCSS.replacingOccurrences(
            of: "button.customButton", with: "button.customButton.\(customCSSClass)"
        )
        reloadCSS()
        // Why 50% disabled opacity was chosen:
        // https://gnome.pages.gitlab.gnome.org/libadwaita/doc/main/css-variables.html#opacity
        // (switch to the variable when we have adwaita)

        // Why 80% for active(pressed) was chosen:
        // A pressed SwiftUI .plain button looks visually the same as
        // a not pressed one at 0.8 opacity.
    }
}

extension PrimitiveButtonStyle.Kind {
    fileprivate func setClass(on button: GtkCustomButton) {
        if let cssClass {
            gtk_widget_add_css_class(button.widgetPointer, cssClass)
        }
    }

    fileprivate func removeClass(from button: GtkCustomButton) {
        if let cssClass {
            gtk_widget_remove_css_class(button.widgetPointer, cssClass)
        }
    }

    var cssClass: String? {
        switch self {
            case .bordered: nil
            case .plain, .borderless: "flat"
        }
    }
}
