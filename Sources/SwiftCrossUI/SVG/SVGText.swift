import Foundation

// SVG `<text>` is drawn by the platform's own text engine, not by a font
// bundled here: the user chose that on 2026-10-09 for size (no font file in the
// library) and for every script the platform can show, Chinese included. The
// core asks a backend for a coverage mask of the text and composites it with the
// SVG's own colour, opacity and paint order, so a backend only has to know how
// glyphs look and where they go. The price is that text differs a little from
// platform to platform, since each uses its own fonts.
//
// SVG 的 `<text>` 由平台自己的文字引擎繪製，而不是由打包在這裡的字型繪製：使用者在 2026-10-09 為了
// 大小(程式庫裡不放字型檔)以及平台能顯示的每一種文字(包括中文)而選擇了這種做法。核心向 backend 要一張
// 文字的覆蓋率遮罩，再以 SVG 自己的顏色、不透明度與繪製順序合成，因此 backend 只需知道字形長什麼樣、
// 放在哪裡。代價是文字在各平台之間略有差異，因為每個平台都用自己的字型。

/// Where a text run sits relative to its `x`: `text-anchor`.
/// 一段文字相對於其 `x` 的位置：`text-anchor`。
public enum SVGTextAnchor: String, Sendable, Hashable {
    case start
    case middle
    case end
}

/// One run of SVG text and the font it asks for.
/// 一段 SVG 文字，以及它要求的字型。
public struct SVGTextRun: Sendable, Hashable {
    /// The characters, whitespace already collapsed.
    /// 字元，空白已合併。
    public var text: String
    /// `font-family`, in order of preference, quotes removed. Generic names
    /// (`serif`, `sans-serif`, `monospace`, `cursive`, `fantasy`, `system-ui`)
    /// appear as they are; empty means the platform's default.
    /// `font-family`,依偏好順序、已去除引號。通用名稱原樣出現；空陣列表示平台預設字型。
    public var fontFamilies: [String]
    /// `font-size` in the text's user space.
    /// 文字使用者空間中的 `font-size`。
    public var fontSize: Double
    public var isBold: Bool
    public var isItalic: Bool
    public var anchor: SVGTextAnchor

    public init(
        text: String, fontFamilies: [String], fontSize: Double, isBold: Bool, isItalic: Bool,
        anchor: SVGTextAnchor
    ) {
        self.text = text
        self.fontFamilies = fontFamilies
        self.fontSize = fontSize
        self.isBold = isBold
        self.isItalic = isItalic
        self.anchor = anchor
    }

    /// The first family a platform can be expected to have under some name:
    /// generic names mapped through `generics`, anything else as written.
    /// 平台大致會有的第一個字型家族：通用名稱經 `generics` 對應，其他名稱照寫。
    public func preferredFamilies(generics: [String: String]) -> [String] {
        fontFamilies.map { generics[$0.lowercased()] ?? $0 }
    }
}

/// An affine map `(x, y) -> (a x + c y + tx, b x + d y + ty)`.
/// 仿射映射 `(x, y) -> (a x + c y + tx, b x + d y + ty)`。
public struct SVGTextTransform: Sendable, Hashable {
    public var a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double

    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty
    }
}

/// What a backend draws: one run, as coverage, into a canvas-sized mask.
///
/// Draw `run` with its baseline along the x axis and its anchor point at the
/// origin of text space, y pointing down as in SVG, then map text space to
/// device pixels with `transform`. Return `width * height` bytes, top row first,
/// each the fraction of that pixel the glyphs cover (0...255) -- filled glyphs
/// when `strokeWidth` is nil, their outlines stroked that wide (in text-space
/// units) otherwise. Colour, opacity and paint order are the caller's.
///
/// backend 要畫的東西：一段文字，以覆蓋率的形式，畫進與畫布同大的遮罩。讓 `run` 的基線沿著 x 軸、
/// 錨點位於文字空間原點、y 朝下(與 SVG 相同)，再以 `transform` 把文字空間映射到裝置像素。回傳
/// `width * height` 個位元組、最上面一列在前，每個代表字形覆蓋該像素的比例(0...255)——`strokeWidth`
/// 為 nil 時是填滿的字形，否則是以該寬度(文字空間單位)描邊的外框。顏色、不透明度與繪製順序由呼叫端負責。
public struct SVGTextMaskRequest: Sendable, Hashable {
    public var run: SVGTextRun
    public var transform: SVGTextTransform
    public var width: Int
    public var height: Int
    public var strokeWidth: Double?

    public init(
        run: SVGTextRun, transform: SVGTextTransform, width: Int, height: Int,
        strokeWidth: Double? = nil
    ) {
        self.run = run
        self.transform = transform
        self.width = width
        self.height = height
        self.strokeWidth = strokeWidth
    }
}

/// Draws a text mask; nil when it could not.
/// 繪製文字遮罩；畫不出來時為 nil。
public typealias SVGTextMasker = (SVGTextMaskRequest) -> [UInt8]?

/// A `<text>` element ready to draw.
/// 準備好可繪製的 `<text>` 元素。
struct SVGTextNode: Sendable {
    var run: SVGTextRun
    /// From text space (anchor at the origin, baseline on the x axis) to the
    /// root viewBox space.
    /// 從文字空間(錨點在原點、基線在 x 軸上)到根 viewBox 空間。
    var transform: SVGTransform
    var fill: SVGColor?
    var stroke: SVGColor?
    var strokeWidth: Double
    /// Where the magenta outline goes when no backend draws text, in root
    /// viewBox space.
    /// 沒有 backend 繪製文字時，洋紅色外框的位置(根 viewBox 空間)。
    var corners: [SVGPoint]
}

#if canImport(CoreText)
    import CoreGraphics
    import CoreText

    /// SVG text through Core Text, for AppKitBackend and UIKitBackend.
    ///
    /// Core Text substitutes fonts for characters the chosen one lacks, so
    /// Chinese in a Latin `font-family` still draws.
    ///
    /// 經由 Core Text 繪製 SVG 文字，供 AppKitBackend 與 UIKitBackend 使用。Core Text 會為所選字型缺少
    /// 的字元替換字型，因此在拉丁 `font-family` 中的中文仍會畫出來。
    public enum SVGCoreTextMasker {
        /// What the generic CSS families mean on Apple platforms.
        /// 通用 CSS 字型家族在 Apple 平台上的意義。
        static let generics: [String: String] = [
            "serif": "Times New Roman", "sans-serif": "Helvetica", "monospace": "Courier",
            "cursive": "Snell Roundhand", "fantasy": "Papyrus", "system-ui": ".AppleSystemUIFont",
        ]

        public static func mask(_ request: SVGTextMaskRequest) -> [UInt8]? {
            let width = request.width
            let height = request.height
            guard width > 0, height > 0, !request.run.text.isEmpty, request.run.fontSize > 0 else {
                return nil
            }
            let font = Self.font(for: request.run)
            let attributes: [CFString: Any] = [
                kCTFontAttributeName: font, kCTForegroundColorFromContextAttributeName: true,
            ]
            guard
                let string = CFAttributedStringCreate(
                    nil, request.run.text as CFString, attributes as CFDictionary)
            else { return nil }
            let line = CTLineCreateWithAttributedString(string)
            let advance = CTLineGetTypographicBounds(line, nil, nil, nil)
            let offset: Double
            switch request.run.anchor {
                case .start: offset = 0
                case .middle: offset = advance / 2
                case .end: offset = advance
            }

            var bytes = [UInt8](repeating: 0, count: width * height)
            let drew = bytes.withUnsafeMutableBytes { raw -> Bool in
                guard
                    let context = CGContext(
                        data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                        bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                        bitmapInfo: CGImageAlphaInfo.none.rawValue)
                else { return false }
                context.setShouldAntialias(true)
                context.setShouldSmoothFonts(false)
                // Core Graphics counts rows from the bottom; SVG and the mask from the top.
                // Core Graphics 由下往上數列；SVG 與遮罩由上往下。
                context.translateBy(x: 0, y: CGFloat(height))
                context.scaleBy(x: 1, y: -1)
                let t = request.transform
                context.concatenate(
                    CGAffineTransform(
                        a: t.a, b: t.b, c: t.c, d: t.d, tx: t.tx, ty: t.ty))
                context.translateBy(x: -offset, y: 0)
                // Glyphs are drawn y-up; text space is y-down.
                // 字形以 y 朝上繪製；文字空間是 y 朝下。
                context.scaleBy(x: 1, y: -1)
                context.textPosition = .zero
                context.setFillColor(gray: 1, alpha: 1)
                context.setStrokeColor(gray: 1, alpha: 1)
                if let strokeWidth = request.strokeWidth {
                    context.setTextDrawingMode(.stroke)
                    context.setLineWidth(strokeWidth)
                } else {
                    context.setTextDrawingMode(.fill)
                }
                CTLineDraw(line, context)
                return true
            }
            return drew ? bytes : nil
        }

        static func font(for run: SVGTextRun) -> CTFont {
            let size = CGFloat(run.fontSize)
            var chosen: CTFont?
            for family in run.preferredFamilies(generics: generics) {
                let candidate = CTFontCreateWithName(family as CFString, size, nil)
                let actual = CTFontCopyFamilyName(candidate) as String
                if actual.caseInsensitiveCompare(family) == .orderedSame || family.hasPrefix(".") {
                    chosen = candidate
                    break
                }
            }
            let base = chosen ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
            var traits = CTFontSymbolicTraits()
            if run.isBold { traits.insert(.traitBold) }
            if run.isItalic { traits.insert(.traitItalic) }
            guard !traits.isEmpty else { return base }
            return CTFontCreateCopyWithSymbolicTraits(base, size, nil, traits, traits) ?? base
        }
    }
#endif
