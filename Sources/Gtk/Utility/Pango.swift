import CGtk

public class Pango {
    private var pangoContext: OpaquePointer
    /// The label's own layout, copied, when measuring for a label.
    /// 為 label 量測時，複製來的 label 自己的 layout。
    private var template: OpaquePointer?

    /// Create a default pango instance with default context.
    /// Create a pango context for a specific
    public init(for widget: Widget) {
        pangoContext = gtk_widget_create_pango_context(widget.widgetPointer)
    }

    /// Measures as `label` draws: through a copy of its own layout, which
    /// carries the attributes GTK puts on a label from its CSS and the label's
    /// context. A context made with `gtk_widget_create_pango_context` has
    /// neither, and on macOS it measured a Chinese line 12 px tall that the
    /// label drew 14 px tall, so two measured lines did not fit and the label
    /// drew one with an ellipsis -- P52's zhTW caption (2026-10-18, English
    /// was 13 px both ways).
    /// 以 `label` 繪製的方式量測：經由它自己 layout 的複本，其中帶著 GTK 依 CSS 放在 label 上的屬性與 label 的
    /// context。以 `gtk_widget_create_pango_context` 建立的 context 兩者皆無；在 macOS 上它把一行中文量成 12 px,
    /// label 卻畫成 14 px,於是量好的兩行放不下，label 只畫一行並加上刪節號——P52 的中文說明(2026-10-18,英文兩邊都是 13 px)。
    public init(likeLabel label: Widget) {
        let layout = pango_layout_copy(gtk_label_get_layout(OpaquePointer(label.widgetPointer)))!
        template = layout
        pangoContext = pango_layout_get_context(layout)
        g_object_ref(UnsafeMutableRawPointer(pangoContext))
    }

    deinit {
        if let template {
            g_object_unref(UnsafeMutableRawPointer(template))
        }
        g_object_unref(UnsafeMutableRawPointer(pangoContext))
    }

    /// Gets the size of the given text in pixels using the default font. If supplied, `proposedWidth`
    /// acts as a suggested width. The text will attempt to take up less than or equal to the proposed
    /// width but if the text wrapping strategy doesn't allow the text to become as small as required
    /// than it may take up more the proposed width.
    ///
    /// Uses the `PANGO_WRAP_WORD_CHAR` text wrapping mode.
    public func getTextSize(
        _ text: String,
        ellipsize: EllipsizeMode,
        proposedWidth: Double? = nil,
        proposedHeight: Double? = nil
    ) -> (width: Int, height: Int) {
        let layout = template.map { pango_layout_copy($0)! } ?? pango_layout_new(pangoContext)!
        pango_layout_set_text(layout, text, Int32(text.utf8.count))
        // A copied layout keeps the label's width and height; unset unless proposed.
        // 複製的 layout 保留 label 的寬與高;沒有提議時取消。
        pango_layout_set_width(layout, -1)
        pango_layout_set_height(layout, -1)
        pango_layout_set_wrap(layout, PANGO_WRAP_WORD_CHAR)
        pango_layout_set_ellipsize(layout, ellipsize.toGtk())

        if let proposedWidth {
            pango_layout_set_width(
                layout,
                Int32((proposedWidth * Double(PANGO_SCALE)).rounded(.towardZero))
            )
        }
        if let proposedHeight {
            pango_layout_set_height(
                layout,
                Int32((proposedHeight * Double(PANGO_SCALE)).rounded(.towardZero))
            )
        }

        // Rounded UP from Pango units, not to the nearest pixel as
        // `pango_layout_get_pixel_size` does. The width comes back as the
        // label's allocation, and a line that filled 1910.6 px of a 1911 px
        // proposal was given 1910: the label re-wrapped one more line than was
        // measured and ellipsized the last one. Chinese breaks between any two
        // characters, so its lines fill the width to within a fraction of a
        // pixel and it hit this where English (with slack at each line end)
        // did not -- P52's zhTW caption on GtkBackend (2026-10-18).
        // 由 Pango 單位無條件進位，而不是像 `pango_layout_get_pixel_size` 那樣四捨五入到最近的像素。寬度會
        // 成為 label 的配置寬度，一行在 1911 px 的提議中填了 1910.6 px,卻只拿到 1910:label 因此比量測時多
        // 換一行，並把最後一行截成刪節號。中文在任兩字之間都能斷行，每行填滿寬度到不足一像素，所以中文碰上了，
        // 而行尾有空白餘裕的英文沒有——GtkBackend 上 P52 的中文說明(2026-10-18)。
        var logical = PangoRectangle()
        pango_layout_get_extents(layout, nil, &logical)
        var height = Double(logical.height)

        // Room for Pango's own guess. A label given this height as its layout
        // height (CustomLabel) is ellipsized by Pango, which decides whether the
        // FIRST line is the last by asking for two lines of the empty-line height
        // -- the font's metrics -- before any line exists. Chinese lines on
        // macOS are 12 px against 13 px metrics, so two measured lines (24 px)
        // failed that test and the label drew one line and an ellipsis (P52's
        // zhTW caption, 2026-10-18). Later lines are judged by the line before
        // them, so only two lines' worth is needed.
        // 留給 Pango 自己的估算。以此高度作為 layout 高度的 label(CustomLabel)由 Pango 截斷，而 Pango 判斷「第一行
        // 是否就是最後一行」時，在任何一行存在之前，用空行高度——也就是字型 metrics——估算兩行。macOS 上中文一行 12 px、
        // metrics 13 px,量好的兩行(24 px)因此沒通過，label 只畫一行加刪節號(P52 的中文說明,2026-10-18)。之後的行
        // 以前一行判斷，所以只需要兩行的份量。
        if pango_layout_get_line_count(layout) >= 2 {
            let empty = template.map { pango_layout_copy($0)! } ?? pango_layout_new(pangoContext)!
            pango_layout_set_text(empty, "", 0)
            pango_layout_set_width(empty, -1)
            pango_layout_set_height(empty, -1)
            var emptyLogical = PangoRectangle()
            pango_layout_get_extents(empty, nil, &emptyLogical)
            g_object_unref(UnsafeMutableRawPointer(empty))
            height = max(height, 2 * Double(emptyLogical.height))
        }

        g_object_unref(UnsafeMutableRawPointer(layout))

        let scale = Double(PANGO_SCALE)
        return (
            Int((Double(logical.width) / scale).rounded(.up)),
            Int((height / scale).rounded(.up))
        )
    }
}
