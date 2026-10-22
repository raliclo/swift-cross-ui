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
        // No `destructive-action` class here: it fills the whole button red with
        // white text, where AppKit keeps the ordinary bezel and draws only the
        // label red. The red reaches the label through
        // `destructiveButtonLabelColor`, so a disabled one dims and an app's
        // colour wins, as on AppKit (P82).
        // 此處不加 `destructive-action` 類別：它會把整顆按鈕填成紅底白字，而 AppKit 保留一般外框、只把標籤畫成紅色。
        // 紅色經由 `destructiveButtonLabelColor` 送到標籤，因此停用時會變淡、app 指定的顏色優先，與 AppKit 相同(P82)。
        button.loadCSS(environment: environment)
    }

    /// The system red, as AppKitBackend returns: a destructive button keeps the
    /// ordinary bezel and only its label turns red, and a disabled one dims that
    /// red the way the core dims any coloured label
    /// (`suggestedForegroundColor.opacity(0.3)`). `resolveAdaptiveColor` picks
    /// GNOME's Red 3 (#E01B24) on light and Red 2 (#ED333B) on dark.
    ///
    /// Until 2026-10-23 this read the colour from an unshown probe button with
    /// the theme's `.flat.destructive-action` class. On Windows and under WSLg the
    /// probe answered the light variant's dark red even in dark mode, and P82's
    /// "destructive, bordered" was dark red on a dark grey bezel, hard to read
    /// beside AppKit's bright system red on the same bezel.
    ///
    /// 系統紅色，與 AppKitBackend 回傳的相同：危險按鈕保留一般外框，只有標籤變紅；停用時，core 會像對任何有顏色的標籤一樣
    /// 把這個紅色變淡(`suggestedForegroundColor.opacity(0.3)`)。`resolveAdaptiveColor` 在淺色選 GNOME 的 Red 3(#E01B24),
    /// 深色選 Red 2(#ED333B)。
    ///
    /// 2026-10-23 之前，這裡從一顆不顯示、帶主題 `.flat.destructive-action` 類別的探針按鈕讀顏色。在 Windows 與 WSLg 上，
    /// 即使是深色模式，探針回答的仍是淺色變體的深紅，P82 的「destructive, bordered」成了深灰外框上的深紅字，與 AppKit 在同樣
    /// 外框上的亮系統紅相比難以閱讀。
    public func destructiveButtonLabelColor(
        in environment: EnvironmentValues
    ) -> SwiftCrossUI.Color? {
        .system(.red)
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
        // Every button, destructive or not, gets the ordinary background: a
        // destructive one is marked by its label's colour alone, as AppKit
        // draws it (see `destructiveButtonLabelColor`).
        // 每顆按鈕，無論是否為危險按鈕，都用一般背景：危險按鈕只以標籤顏色標示，與 AppKit 相同(見 `destructiveButtonLabelColor`)。
        let backgroundRule = "background: \(CSSProperty.rgba(backgroundColor));"
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
