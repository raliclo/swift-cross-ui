import CGtk
import Gtk

#if os(macOS)
    import CoreText
    import Foundation
#endif

extension GtkBackend {
    /// Scales the runs a label draws in Apple Color Emoji so that each emoji
    /// is drawn at the size CoreText, and so AppKitBackend, draws it.
    ///
    /// Pango on macOS draws Apple Color Emoji at 1.25 times the font size at
    /// every size (measured with pango-view at 13, 16, 20, 24, 32 and 40: the
    /// blue square of U+1F17F is 16, 20, 25, 30, 40 and 50 wide). CoreText
    /// draws it larger than the font size only below 24 and by less: 16.25,
    /// 20, 22, 24, 32 and 40. P103's circles therefore had a 25 pt emoji on
    /// GTK beside a 22 pt one on AppKit, both at 20 pt. Each run in that font
    /// gets a Pango scale of CoreText's ink width over Pango's for its first
    /// glyph at the label's font size, so the two match at any size. `size` is
    /// that size in points, which GTK draws as as many pixels.
    ///
    /// Only the label's own attributes are changed, so a copy of the label's
    /// layout -- which `Pango(likeLabel:)` and the measuring helpers use --
    /// measures the scaled runs. Elsewhere Pango has no Apple Color Emoji and
    /// this does nothing.
    ///
    /// 把 label 以 Apple Color Emoji 繪製的 run 縮放，使每個 emoji 以 CoreText(也就是 AppKitBackend)
    /// 繪製的大小畫出。macOS 上的 Pango 在每一種字級都把 Apple Color Emoji 畫成字級的 1.25 倍(以 pango-view
    /// 在 13、16、20、24、32、40 實測:U+1F17F 的藍色方塊寬 16、20、25、30、40、50)。CoreText 只在 24 以下
    /// 把它畫得比字級大，而且大得較少:16.25、20、22、24、32、40。因此 P103 的圓圈在 GTK 上是 25 pt 的 emoji,
    /// AppKit 上是 22 pt,兩者都是 20 pt 字級。以該字型繪製的每個 run 取一個 Pango 縮放值：在 label 的字級下，
    /// 第一個字形 CoreText 的 ink 寬除以 Pango 的 ink 寬，所以兩者在任何字級都相符。`size` 是 label 字型的點數，GTK 把它畫成同樣多的像素。
    /// 只改 label 自己的屬性，所以 label layout 的複本——`Pango(likeLabel:)` 與量測輔助函式所用的——量到的是
    /// 縮放後的 run。其他平台的 Pango 沒有 Apple Color Emoji,這裡什麼也不做。
    func scaleColourEmoji(in label: CustomLabel, text: String, size: Double) {
        #if os(macOS)
            let hadAttributes = gtk_label_get_attributes(label.opaquePointer) != nil
            guard text.unicodeScalars.contains(where: { $0.value > 0x7F && $0.properties.isEmoji })
            else {
                if hadAttributes { gtk_label_set_attributes(label.opaquePointer, nil) }
                return
            }
            if hadAttributes { gtk_label_set_attributes(label.opaquePointer, nil) }
            guard let layout = gtk_label_get_layout(label.opaquePointer),
                let iter = pango_layout_get_iter(layout)
            else { return }
            defer { pango_layout_iter_free(iter) }

            let attributes = pango_attr_list_new()!
            defer { pango_attr_list_unref(attributes) }
            let bytes = Array(text.utf8)
            var scaled = false
            repeat {
                guard let run = pango_layout_iter_get_run_readonly(iter),
                    let item = run.pointee.item, let font = item.pointee.analysis.font,
                    let glyphs = run.pointee.glyphs, glyphs.pointee.num_glyphs > 0,
                    let description = pango_font_describe(font)
                else { continue }
                defer { pango_font_description_free(description) }
                guard let family = pango_font_description_get_family(description),
                    String(cString: family) == "Apple Color Emoji"
                else { continue }

                var ink = PangoRectangle()
                pango_font_get_glyph_extents(font, glyphs.pointee.glyphs[0].glyph, &ink, nil)
                let pangoInk = Double(ink.width) / Double(PANGO_SCALE)
                let start = Int(item.pointee.offset)
                let end = start + Int(item.pointee.length)
                guard size > 0, pangoInk > 0, start >= 0, end <= bytes.count,
                    let runText = String(bytes: bytes[start..<end], encoding: .utf8),
                    let first = runText.first
                else { continue }

                let ctFont = CTFontCreateWithName("AppleColorEmoji" as CFString, size, nil)
                let string = NSAttributedString(
                    string: String(first),
                    attributes: [NSAttributedString.Key(kCTFontAttributeName as String): ctFont]
                )
                let coreTextInk = CTLineGetImageBounds(CTLineCreateWithAttributedString(string), nil)
                guard coreTextInk.width > 0 else { continue }

                let attribute = pango_attr_scale_new(coreTextInk.width / pangoInk)!
                attribute.pointee.start_index = guint(start)
                attribute.pointee.end_index = guint(end)
                pango_attr_list_insert(attributes, attribute)
                scaled = true
            } while pango_layout_iter_next_run(iter) != 0

            if scaled {
                gtk_label_set_attributes(label.opaquePointer, attributes)
            }
        #endif
    }
}
