import Foundation
@_spi(Backends) import SwiftCrossUI
import WinUIInterop

/// SVG `<text>` through DirectWrite and Direct2D: one run, as coverage, drawn by
/// `scui_svg_text_mask` in WinUIInterop's svg_text_mask.cpp. DirectWrite brings
/// the system's font fallback for characters the chosen family lacks.
///
/// 經由 DirectWrite 與 Direct2D 繪製 SVG `<text>`:一段文字，以覆蓋率的形式，由 WinUIInterop 的
/// svg_text_mask.cpp 中的 `scui_svg_text_mask` 畫出。DirectWrite 會為所選字型缺少的字元套用系統的字型替代。
extension WinUIBackend: BackendFeatures.SVGText {
    /// What the generic CSS families mean on Windows. Arial for sans-serif and
    /// Courier New for monospace because they share Helvetica's and Courier's
    /// metrics, the faces AppKit uses, so a plain `<text>` lays out alike.
    /// 通用 CSS 字型家族在 Windows 上的意義。sans-serif 用 Arial、monospace 用 Courier New,因為它們與 AppKit
    /// 所用的 Helvetica、Courier 度量相同，讓單純的 `<text>` 排版相近。
    static let svgGenericFamilies: [String: String] = [
        "serif": "Times New Roman", "sans-serif": "Arial", "monospace": "Courier New",
        "cursive": "Comic Sans MS", "fantasy": "Impact", "system-ui": "Segoe UI",
    ]

    public func svgTextMask(_ request: SVGTextMaskRequest) -> [UInt8]? {
        let width = request.width
        let height = request.height
        let run = request.run
        guard width > 0, height > 0, !run.text.isEmpty, run.fontSize > 0 else { return nil }
        let families = (run.fontFamilies.isEmpty
            ? ["Arial"] : run.preferredFamilies(generics: Self.svgGenericFamilies))
            .joined(separator: ",")
        let anchor: Int32
        switch run.anchor {
            case .start: anchor = 0
            case .middle: anchor = 1
            case .end: anchor = 2
        }
        let t = request.transform
        let text = Array(run.text.utf16)
        let familyUnits = Array(families.utf16) + [0]
        var bytes = [UInt8](repeating: 0, count: width * height)
        let drew = text.withUnsafeBufferPointer { textBuffer in
            familyUnits.withUnsafeBufferPointer { familyBuffer in
                bytes.withUnsafeMutableBufferPointer { out in
                    scui_svg_text_mask(
                        textBuffer.baseAddress, Int32(textBuffer.count), familyBuffer.baseAddress,
                        run.fontSize, run.isBold ? 1 : 0, run.isItalic ? 1 : 0, anchor,
                        t.a, t.b, t.c, t.d, t.tx, t.ty, request.strokeWidth ?? 0,
                        Int32(width), Int32(height), out.baseAddress)
                }
            }
        }
        return drew != 0 ? bytes : nil
    }
}
