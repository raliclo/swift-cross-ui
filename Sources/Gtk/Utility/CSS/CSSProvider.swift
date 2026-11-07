import CGtk
import GtkCHelpers

/// Swift representation of a Gtk CSS provider
public class CSSProvider {
    var pointer: UnsafeMutablePointer<GtkCssProvider>
    var display: OpaquePointer

    public init(
        forDisplay display: OpaquePointer = gdk_display_get_default(),
        priority: UInt32 = UInt32(GTK_STYLE_PROVIDER_PRIORITY_APPLICATION)
    ) {
        pointer = gtk_css_provider_new()
        self.display = display
        gtk_style_context_add_provider_for_display(display, OpaquePointer(pointer), priority)
    }

    deinit {
        gtk_style_context_remove_provider_for_display(display, OpaquePointer(pointer))
        // The display took its own reference when the provider was added; this
        // one, from `gtk_css_provider_new`, is ours to drop.
        // display 在加入 provider 時取得了自己的參考;這一個來自 `gtk_css_provider_new`,由我們釋放。
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
