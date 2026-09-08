import Gtk
import CGtk
import GtkCHelpers
@_spi(Backends) import SwiftCrossUI

extension GtkBackend {
    public func createSimpleButton() -> Widget {
        return Button()
    }

    public func updateSimpleButton(
        _ button: Widget,
        label: String,
        environment: EnvironmentValues,
        action: @escaping () -> Void
    ) {
        // TODO: Update button label color using environment
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

        return button
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
        button.loadCSS(environment: environment)
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

    init() {
        super.init(gtk_button_new())

        gtk_widget_add_css_class(widgetPointer, "customButton")
    }

    @MainActor
    func loadCSS(environment: EnvironmentValues) {
        let backgroundColor = GtkBackend.controlBackgroundColor(for: environment)
        cssProvider.loadCss(from: """
                button.customButton {
                    min-width: 0px;
                    min-height: 0px;
                    padding: 0px;
                    background: \(CSSProperty.rgba(backgroundColor));
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
            """)
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
