import CGtk
import GtkCHelpers

/// Swift representation of a Gtk CSS provider
public class CSSProvider {
    /// Where a provider is installed. / provider 安裝在哪裡。
    public enum Scope {
        /// Every widget on the display: for rules that reach other widgets, such
        /// as a descendant (`.class label`, `contents modelbutton`).
        /// display 上的每個 widget:給會作用到其他 widget 的規則，例如後代選擇器(`.class label`、`contents modelbutton`)。
        case display
        /// One widget's own CSS node. See `init(forWidget:priority:)`.
        /// 單一 widget 自己的 CSS 節點。見 `init(forWidget:priority:)`。
        case widget
    }

    var pointer: UnsafeMutablePointer<GtkCssProvider>
    var display: OpaquePointer
    /// The widget's style context, for a provider installed for one widget.
    /// 只為一個 widget 安裝的 provider 所用的該 widget 的 style context。
    var widgetContext: UnsafeMutablePointer<GtkStyleContext>?

    public init(
        forDisplay display: OpaquePointer = gdk_display_get_default(),
        priority: UInt32 = UInt32(GTK_STYLE_PROVIDER_PRIORITY_APPLICATION)
    ) {
        pointer = gtk_css_provider_new()
        self.display = display
        gtk_style_context_add_provider_for_display(display, OpaquePointer(pointer), priority)
    }

    /// A provider for one widget alone. Its rules match only that widget's own
    /// CSS node, so they must not name a descendant.
    ///
    /// Why it exists: a display-wide provider per widget made every widget's
    /// style lookup scan the provider of every other widget, and every load
    /// restyle all of them. Turning a page of new rows in P116 on Windows GTK
    /// grew with the square of the row count: 5, 10, 20 and 40 rows took about
    /// 220, 579, 1969 and 8766 ms per turn (2026-11-13).
    ///
    /// 只給一個 widget 的 provider。它的規則只比對該 widget 自己的 CSS 節點，所以不可指名後代。存在的理由：每個 widget 一個
    /// display 範圍的 provider,會讓每個 widget 查樣式時掃過其他每個 widget 的 provider,而每次載入都讓所有 widget 重套樣式。
    /// Windows GTK 上 P116 換成新列的翻頁時間隨列數平方成長:5、10、20、40 列各約 220、579、1969、8766 毫秒(2026-11-13)。
    public init(
        forWidget widget: UnsafeMutablePointer<GtkWidget>,
        priority: UInt32 = UInt32(GTK_STYLE_PROVIDER_PRIORITY_APPLICATION)
    ) {
        pointer = gtk_css_provider_new()
        display = gdk_display_get_default()
        widgetContext = scui_widget_add_own_css_provider(widget, pointer, priority)
    }

    deinit {
        if let widgetContext {
            scui_style_context_remove_own_css_provider(widgetContext, pointer)
        } else {
            gtk_style_context_remove_provider_for_display(display, OpaquePointer(pointer))
        }
        // The display or the style context took its own reference when the
        // provider was added; this one, from `gtk_css_provider_new`, is ours to drop.
        // display 或 style context 在加入 provider 時取得了自己的參考;這一個來自 `gtk_css_provider_new`,由我們釋放。
        g_object_unref(pointer)
    }

    /// Loads data into css_provider.
    ///
    /// This clears any previously loaded information.
    ///
    /// Deprecated since: 4.12
    public func loadCss(from data: String) {
        // TODO: Connect to parsing-error signal to log parsing errors.
        // The length is in bytes: `data.count` counts Characters, which is
        // short for any non-ASCII text (a CJK font name, an emoji), and GTK
        // then parses a truncated stylesheet.
        // 長度以位元組計:`data.count` 算的是 Character,遇到任何非 ASCII 文字(中日韓字型名稱、emoji)
        // 都會偏短，GTK 便會解析一份被截斷的樣式表。
        scui_css_provider_load(pointer, data, gssize(data.utf8.count))
    }
}
