/// The compositing effects applied to a view's rendered output.
///
/// One value rather than one backend method per effect, because that is the
/// shape backends want. SwiftUI composes these (`.saturation(0).brightness(0.2)`)
/// and every backend has to turn the combination into a single thing: GTK into
/// one CSS `filter` string, AppKit into one `CIFilter` chain, WinUI into one
/// composition effect graph. Handing a backend the effects one at a time would
/// make each of them keep its own record and recombine, which is the same work
/// done once here.
///
/// Nesting is what composes them, not this type: `.opacity(0.5).opacity(0.5)`
/// wraps twice and multiplies to 0.25, which is SwiftUI's behaviour and comes
/// out of the view tree for free.
///
/// Geometric effects -- `rotationEffect`, `scaleEffect`, `offset` -- are
/// deliberately not here. They change where a view is drawn rather than what its
/// pixels look like, they interact with hit testing, and on GTK they are a
/// different mechanism entirely. Grouping them with these would force every
/// backend to handle both to support either.
///
/// 套用於某個 view 繪製結果的合成效果。
///
/// 此處採用「單一值」而非「每種效果一個 backend 方法」，因為那才是 backend 想要的形狀。SwiftUI 會
/// 把這些效果組合起來（`.saturation(0).brightness(0.2)`），而每個 backend 都必須把組合後的結果轉成
/// 單一的東西：GTK 轉成一條 CSS `filter` 字串、AppKit 轉成一條 `CIFilter` 鏈、WinUI 轉成一張合成
/// 效果圖。若逐一把效果交給 backend，等於要求每個 backend 各自記錄並重新組合，那與在此處做一次是
/// 同樣的工作。
///
/// 真正負責組合的是巢狀結構而非本型別：`.opacity(0.5).opacity(0.5)` 會包兩層並相乘為 0.25，這正是
/// SwiftUI 的行為，且由 view tree 自然得出、無須額外處理。
///
/// 幾何類效果——`rotationEffect`、`scaleEffect`、`offset`——刻意不放在此處。它們改變的是「view 被
/// 畫在哪裡」而非「它的像素長什麼樣」，會與 hit testing 互相影響，且在 GTK 上是完全不同的機制。
/// 若與這些效果混為一談，將迫使每個 backend 為了支援其中一種而必須兩種都處理。
public struct VisualEffect: Equatable, Sendable {
    /// How opaque the view is, from 0 (invisible) to 1 (unchanged).
    /// view 的不透明度，0 為完全不可見，1 為不做任何改變。
    public var opacity: Double

    /// The radius of a Gaussian blur, in points. 0 leaves the view sharp.
    /// 高斯模糊的半徑（單位為點）。0 表示不模糊。
    public var blurRadius: Double

    /// Colour intensity. 0 is fully desaturated, 1 is unchanged, above 1
    /// oversaturates.
    /// 色彩濃度。0 為完全去飽和、1 為不改變、大於 1 則過飽和。
    public var saturation: Double

    /// An additive lightening, where 0 is unchanged.
    ///
    /// Additive rather than multiplicative because that is SwiftUI's
    /// `.brightness(_:)`, whose documentation defines it as adding to each
    /// colour channel. CSS `filter: brightness()` is multiplicative and centred
    /// on 1, so a backend using CSS has to convert rather than pass this
    /// through.
    ///
    /// 加法式的提亮，0 表示不改變。
    ///
    /// 之所以是加法而非乘法，是因為 SwiftUI 的 `.brightness(_:)` 即是如此定義——其文件說明它是
    /// 「加到每個色彩通道上」。CSS 的 `filter: brightness()` 則是以 1 為中心的乘法，因此使用 CSS 的
    /// backend 必須自行換算，不能直接傳遞。
    public var brightness: Double

    /// Contrast, where 1 is unchanged and 0 flattens the view to grey.
    /// 對比度，1 為不改變，0 會把 view 壓平為灰色。
    public var contrast: Double

    /// How far the view is pushed towards grey, from 0 (unchanged) to 1.
    /// view 被推向灰階的程度，0 為不改變、1 為完全灰階。
    public var grayscale: Double

    /// How far the hues are rotated around the colour wheel.
    /// 色相繞色輪旋轉的角度。
    public var hueRotation: Angle

    public init(
        opacity: Double = 1,
        blurRadius: Double = 0,
        saturation: Double = 1,
        brightness: Double = 0,
        contrast: Double = 1,
        grayscale: Double = 0,
        hueRotation: Angle = .zero
    ) {
        self.opacity = opacity
        self.blurRadius = blurRadius
        self.saturation = saturation
        self.brightness = brightness
        self.contrast = contrast
        self.grayscale = grayscale
        self.hueRotation = hueRotation
    }

    /// The effect that changes nothing.
    /// 不造成任何改變的效果。
    public static let identity = VisualEffect()

    /// Whether this effect would leave the view untouched.
    ///
    /// Worth checking before doing any work: a backend can skip installing a
    /// filter entirely, and a view that sets one effect gets the other six as
    /// their neutral values rather than as instructions.
    ///
    /// 此效果是否會讓 view 維持原樣。
    ///
    /// 值得在動工前先檢查：backend 可以完全略過安裝 filter 的步驟，而只設定了一種效果的 view，其餘
    /// 六項會是中性值而非指令。
    public var isIdentity: Bool { self == .identity }
}
