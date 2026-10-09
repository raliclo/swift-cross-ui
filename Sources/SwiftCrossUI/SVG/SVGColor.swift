import Foundation

/// An sRGB colour with straight (not premultiplied) alpha, components 0...1.
///
/// sRGB 顏色，alpha 未預乘，分量為 0...1。
struct SVGColor: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    /// Drawn wherever the renderer meets something it cannot paint, such as a
    /// gradient with no fallback colour. Chosen because it occurs in almost no
    /// real drawing, so it reads as "something is wrong here".
    ///
    /// 算繪器遇到無法繪製的東西(例如沒有後備顏色的漸層)時所使用的顏色。選它是因為它幾乎不會
    /// 出現在真實圖面中，因此看起來就是「這裡出了問題」。
    static let unsupportedMarker = SVGColor(red: 1, green: 0, blue: 1)

    /// Parses a CSS colour: a keyword, `#rgb`, `#rgba`, `#rrggbb`,
    /// `#rrggbbaa`, `rgb()`/`rgba()` and `hsl()`/`hsla()` in comma or space
    /// syntax. `currentColor` and `none` are handled by the caller.
    ///
    /// 解析 CSS 顏色：關鍵字、`#rgb`、`#rgba`、`#rrggbb`、`#rrggbbaa`,以及逗號或空白語法的
    /// `rgb()`/`rgba()` 與 `hsl()`/`hsla()`。`currentColor` 與 `none` 由呼叫端處理。
    static func parse(_ text: String) -> SVGColor? {
        let value = text.trimmingCharacters(in: .whitespaces).lowercased()
        if value.hasPrefix("#") {
            let hex = Array(value.dropFirst())
            guard hex.allSatisfy(\.isHexDigit) else { return nil }
            func component(_ characters: ArraySlice<Character>) -> Double {
                var string = String(characters)
                if string.count == 1 { string += string }
                return Double(Int(string, radix: 16)!) / 255
            }
            switch hex.count {
                case 3, 4:
                    return SVGColor(
                        red: component(hex[0..<1]), green: component(hex[1..<2]),
                        blue: component(hex[2..<3]),
                        alpha: hex.count == 4 ? component(hex[3..<4]) : 1)
                case 6, 8:
                    return SVGColor(
                        red: component(hex[0..<2]), green: component(hex[2..<4]),
                        blue: component(hex[4..<6]),
                        alpha: hex.count == 8 ? component(hex[6..<8]) : 1)
                default:
                    return nil
            }
        }
        if value.hasPrefix("rgb") || value.hasPrefix("hsl") {
            guard let open = value.firstIndex(of: "("), let close = value.lastIndex(of: ")"),
                open < close
            else { return nil }
            let inner = value[value.index(after: open)..<close]
            let parts =
                inner
                .replacingOccurrences(of: "/", with: " ")
                .split(whereSeparator: { $0 == "," || $0 == " " })
                .map(String.init)
            guard parts.count == 3 || parts.count == 4 else { return nil }
            func alpha(_ part: String) -> Double? {
                if part.hasSuffix("%") {
                    return Double(part.dropLast()).map { $0 / 100 }
                }
                return Double(part)
            }
            let alphaValue = parts.count == 4 ? alpha(parts[3]) : 1
            guard let alphaValue else { return nil }
            if value.hasPrefix("rgb") {
                func channel(_ part: String) -> Double? {
                    if part.hasSuffix("%") {
                        return Double(part.dropLast()).map { $0 / 100 }
                    }
                    return Double(part).map { $0 / 255 }
                }
                guard let r = channel(parts[0]), let g = channel(parts[1]), let b = channel(parts[2])
                else { return nil }
                return SVGColor(red: r, green: g, blue: b, alpha: alphaValue).clamped()
            }
            let hueText = parts[0].hasSuffix("deg") ? String(parts[0].dropLast(3)) : parts[0]
            guard let hue = Double(hueText),
                let saturation = Double(parts[1].replacingOccurrences(of: "%", with: "")),
                let lightness = Double(parts[2].replacingOccurrences(of: "%", with: ""))
            else { return nil }
            return fromHSL(hue: hue, saturation: saturation / 100, lightness: lightness / 100)
                .with(alpha: alphaValue).clamped()
        }
        if value == "transparent" {
            return SVGColor(red: 0, green: 0, blue: 0, alpha: 0)
        }
        guard let rgb = namedColors[value] else { return nil }
        return SVGColor(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255)
    }

    func with(alpha: Double) -> SVGColor {
        var copy = self
        copy.alpha = alpha
        return copy
    }

    func clamped() -> SVGColor {
        func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }
        return SVGColor(red: clamp(red), green: clamp(green), blue: clamp(blue), alpha: clamp(alpha))
    }

    private static func fromHSL(hue: Double, saturation: Double, lightness: Double) -> SVGColor {
        let h = ((hue.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
            / 360
        let s = min(max(saturation, 0), 1)
        let l = min(max(lightness, 0), 1)
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        func hueToRGB(_ tIn: Double) -> Double {
            var t = tIn
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 0.5 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        return SVGColor(red: hueToRGB(h + 1.0 / 3), green: hueToRGB(h), blue: hueToRGB(h - 1.0 / 3))
    }

    /// The 147 CSS colour keywords.
    /// 147 個 CSS 顏色關鍵字。
    static let namedColors: [String: UInt32] = [
        "aliceblue": 0xF0F8FF, "antiquewhite": 0xFAEBD7, "aqua": 0x00FFFF,
        "aquamarine": 0x7FFFD4, "azure": 0xF0FFFF, "beige": 0xF5F5DC, "bisque": 0xFFE4C4,
        "black": 0x000000, "blanchedalmond": 0xFFEBCD, "blue": 0x0000FF,
        "blueviolet": 0x8A2BE2, "brown": 0xA52A2A, "burlywood": 0xDEB887,
        "cadetblue": 0x5F9EA0, "chartreuse": 0x7FFF00, "chocolate": 0xD2691E,
        "coral": 0xFF7F50, "cornflowerblue": 0x6495ED, "cornsilk": 0xFFF8DC,
        "crimson": 0xDC143C, "cyan": 0x00FFFF, "darkblue": 0x00008B, "darkcyan": 0x008B8B,
        "darkgoldenrod": 0xB8860B, "darkgray": 0xA9A9A9, "darkgreen": 0x006400,
        "darkgrey": 0xA9A9A9, "darkkhaki": 0xBDB76B, "darkmagenta": 0x8B008B,
        "darkolivegreen": 0x556B2F, "darkorange": 0xFF8C00, "darkorchid": 0x9932CC,
        "darkred": 0x8B0000, "darksalmon": 0xE9967A, "darkseagreen": 0x8FBC8F,
        "darkslateblue": 0x483D8B, "darkslategray": 0x2F4F4F, "darkslategrey": 0x2F4F4F,
        "darkturquoise": 0x00CED1, "darkviolet": 0x9400D3, "deeppink": 0xFF1493,
        "deepskyblue": 0x00BFFF, "dimgray": 0x696969, "dimgrey": 0x696969,
        "dodgerblue": 0x1E90FF, "firebrick": 0xB22222, "floralwhite": 0xFFFAF0,
        "forestgreen": 0x228B22, "fuchsia": 0xFF00FF, "gainsboro": 0xDCDCDC,
        "ghostwhite": 0xF8F8FF, "gold": 0xFFD700, "goldenrod": 0xDAA520, "gray": 0x808080,
        "grey": 0x808080, "green": 0x008000, "greenyellow": 0xADFF2F, "honeydew": 0xF0FFF0,
        "hotpink": 0xFF69B4, "indianred": 0xCD5C5C, "indigo": 0x4B0082, "ivory": 0xFFFFF0,
        "khaki": 0xF0E68C, "lavender": 0xE6E6FA, "lavenderblush": 0xFFF0F5,
        "lawngreen": 0x7CFC00, "lemonchiffon": 0xFFFACD, "lightblue": 0xADD8E6,
        "lightcoral": 0xF08080, "lightcyan": 0xE0FFFF, "lightgoldenrodyellow": 0xFAFAD2,
        "lightgray": 0xD3D3D3, "lightgreen": 0x90EE90, "lightgrey": 0xD3D3D3,
        "lightpink": 0xFFB6C1, "lightsalmon": 0xFFA07A, "lightseagreen": 0x20B2AA,
        "lightskyblue": 0x87CEFA, "lightslategray": 0x778899, "lightslategrey": 0x778899,
        "lightsteelblue": 0xB0C4DE, "lightyellow": 0xFFFFE0, "lime": 0x00FF00,
        "limegreen": 0x32CD32, "linen": 0xFAF0E6, "magenta": 0xFF00FF, "maroon": 0x800000,
        "mediumaquamarine": 0x66CDAA, "mediumblue": 0x0000CD, "mediumorchid": 0xBA55D3,
        "mediumpurple": 0x9370DB, "mediumseagreen": 0x3CB371, "mediumslateblue": 0x7B68EE,
        "mediumspringgreen": 0x00FA9A, "mediumturquoise": 0x48D1CC,
        "mediumvioletred": 0xC71585, "midnightblue": 0x191970, "mintcream": 0xF5FFFA,
        "mistyrose": 0xFFE4E1, "moccasin": 0xFFE4B5, "navajowhite": 0xFFDEAD,
        "navy": 0x000080, "oldlace": 0xFDF5E6, "olive": 0x808000, "olivedrab": 0x6B8E23,
        "orange": 0xFFA500, "orangered": 0xFF4500, "orchid": 0xDA70D6,
        "palegoldenrod": 0xEEE8AA, "palegreen": 0x98FB98, "paleturquoise": 0xAFEEEE,
        "palevioletred": 0xDB7093, "papayawhip": 0xFFEFD5, "peachpuff": 0xFFDAB9,
        "peru": 0xCD853F, "pink": 0xFFC0CB, "plum": 0xDDA0DD, "powderblue": 0xB0E0E6,
        "purple": 0x800080, "rebeccapurple": 0x663399, "red": 0xFF0000,
        "rosybrown": 0xBC8F8F, "royalblue": 0x4169E1, "saddlebrown": 0x8B4513,
        "salmon": 0xFA8072, "sandybrown": 0xF4A460, "seagreen": 0x2E8B57,
        "seashell": 0xFFF5EE, "sienna": 0xA0522D, "silver": 0xC0C0C0, "skyblue": 0x87CEEB,
        "slateblue": 0x6A5ACD, "slategray": 0x708090, "slategrey": 0x708090, "snow": 0xFFFAFA,
        "springgreen": 0x00FF7F, "steelblue": 0x4682B4, "tan": 0xD2B48C, "teal": 0x008080,
        "thistle": 0xD8BFD8, "tomato": 0xFF6347, "turquoise": 0x40E0D0, "violet": 0xEE82EE,
        "wheat": 0xF5DEB3, "white": 0xFFFFFF, "whitesmoke": 0xF5F5F5, "yellow": 0xFFFF00,
        "yellowgreen": 0x9ACD32,
    ]
}
