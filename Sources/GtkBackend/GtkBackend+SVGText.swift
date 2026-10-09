import CGtk
import Foundation
@_spi(Backends) import SwiftCrossUI

/// SVG `<text>` through Pango on Cairo: one run, as coverage, in an A8 surface
/// the size of the canvas. Pango (through fontconfig) knows the CSS generic
/// families and substitutes fonts for characters the chosen one lacks.
///
/// 經由 Cairo 上的 Pango 繪製 SVG `<text>`:一段文字，以覆蓋率的形式，畫進與畫布同大的 A8 surface。Pango
/// (透過 fontconfig)認得 CSS 通用字型家族，也會為所選字型缺少的字元替換字型。
extension GtkBackend: BackendFeatures.SVGText {
    public func svgTextMask(_ request: SVGTextMaskRequest) -> [UInt8]? {
        let width = request.width
        let height = request.height
        let run = request.run
        guard width > 0, height > 0, !run.text.isEmpty, run.fontSize > 0 else { return nil }
        guard let surface = cairo_image_surface_create(CAIRO_FORMAT_A8, Int32(width), Int32(height))
        else { return nil }
        defer { cairo_surface_destroy(surface) }
        guard cairo_surface_status(surface) == CAIRO_STATUS_SUCCESS, let cairo = cairo_create(surface)
        else { return nil }
        defer { cairo_destroy(cairo) }

        let t = request.transform
        var matrix = cairo_matrix_t(xx: t.a, yx: t.b, xy: t.c, yy: t.d, x0: t.tx, y0: t.ty)
        cairo_set_matrix(cairo, &matrix)

        guard let layout = pango_cairo_create_layout(cairo) else { return nil }
        defer { g_object_unref(UnsafeMutableRawPointer(layout)) }
        guard let description = pango_font_description_new() else { return nil }
        defer { pango_font_description_free(description) }
        // No font-family: sans-serif, the default Core Text and Android use, so a
        // plain <text> looks alike on every backend.
        // 沒有 font-family 時用 sans-serif,與 Core Text、Android 的預設相同，讓單純的 <text> 在各 backend 上相近。
        let families = (run.fontFamilies.isEmpty
            ? ["sans-serif"] : run.preferredFamilies(generics: ["system-ui": "sans-serif"]))
            .joined(separator: ",")
        if !families.isEmpty {
            pango_font_description_set_family(description, families)
        }
        pango_font_description_set_absolute_size(description, run.fontSize * Double(PANGO_SCALE))
        pango_font_description_set_weight(
            description, run.isBold ? PANGO_WEIGHT_BOLD : PANGO_WEIGHT_NORMAL)
        pango_font_description_set_style(
            description, run.isItalic ? PANGO_STYLE_ITALIC : PANGO_STYLE_NORMAL)
        pango_layout_set_font_description(layout, description)
        pango_layout_set_text(layout, run.text, -1)

        var logical = PangoRectangle()
        pango_layout_get_extents(layout, nil, &logical)
        let advance = Double(logical.width) / Double(PANGO_SCALE)
        let baseline = Double(pango_layout_get_baseline(layout)) / Double(PANGO_SCALE)
        let offset: Double
        switch run.anchor {
            case .start: offset = 0
            case .middle: offset = advance / 2
            case .end: offset = advance
        }
        // Pango draws from the layout's top-left corner; move it so the baseline
        // lies on y = 0 and the anchor on x = 0.
        // Pango 從版面的左上角開始畫；移動它，讓基線落在 y = 0、錨點落在 x = 0。
        cairo_move_to(cairo, -offset, -baseline)
        cairo_set_source_rgba(cairo, 1, 1, 1, 1)
        if let strokeWidth = request.strokeWidth {
            pango_cairo_layout_path(cairo, layout)
            cairo_set_line_width(cairo, strokeWidth)
            cairo_stroke(cairo)
        } else {
            pango_cairo_show_layout(cairo, layout)
        }
        cairo_surface_flush(surface)

        guard let data = cairo_image_surface_get_data(surface) else { return nil }
        let stride = Int(cairo_image_surface_get_stride(surface))
        var bytes = [UInt8](repeating: 0, count: width * height)
        for row in 0..<height {
            for column in 0..<width {
                bytes[row * width + column] = data[row * stride + column]
            }
        }
        return bytes
    }
}
