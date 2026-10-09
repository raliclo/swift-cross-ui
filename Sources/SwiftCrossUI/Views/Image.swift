import Foundation
import ImageFormats

/// A view that displays an image.
public struct Image: Sendable {
    /// Whether the image is resizable.
    private var isResizable = false
    /// The source of the image.
    private var source: Source
    /// A fixed pixel size for SVG rasterisation; `nil` rasterises at the
    /// displayed size times the window's scale factor.
    /// SVG 點陣化的固定像素尺寸；`nil` 表示以顯示尺寸乘以視窗縮放比例點陣化。
    private var svgRasterSize: SIMD2<Int>? = nil

    enum Source: Equatable {
        case url(URL, useFileExtension: Bool)
        case image(ImageFormats.Image<RGBA>)
        case symbol(SystemSymbol)
        case svg(SVGDocument)
    }

    /// Creates an image view.
    ///
    /// `png`, `jpg`, `webp` and `svg` are supported. An SVG file is drawn by
    /// ``SVGDocument``, the same pure-Swift renderer on every backend, and is
    /// re-rasterised whenever the displayed size or the window's scale factor
    /// changes, so a `resizable()` SVG stays sharp. Anything in the file the
    /// renderer does not support is logged once and outlined in magenta in
    /// the image; see ``SVGDocument/diagnostics``.
    ///
    /// 建立一個影像 view。支援 `png`、`jpg`、`webp` 與 `svg`。SVG 檔由 ``SVGDocument`` 繪製——
    /// 在每一個 backend 上都是同一套純 Swift 算繪器——並在顯示尺寸或視窗縮放比例改變時重新點陣化，
    /// 因此 `resizable()` 的 SVG 保持清晰。檔案中算繪器不支援的任何內容會記錄一次 log,並在影像中
    /// 以洋紅色框出；見 ``SVGDocument/diagnostics``。
    ///
    /// - Parameters:
    ///   - url: The URL of the file to display.
    ///   - useFileExtension: If `true`, the file extension is used to determine
    ///     the file type, otherwise the first few ('magic') bytes of the file
    ///     are used.
    public init(_ url: URL, useFileExtension: Bool = true) {
        source = .url(url, useFileExtension: useFileExtension)
    }

    /// Displays an image from raw pixel data.
    ///
    /// - Parameter image: The image data to display.
    public init(_ image: ImageFormats.Image<RGBA>) {
        source = .image(image)
    }

    /// Displays an SVG document that has already been parsed, e.g. to read
    /// its ``SVGDocument/diagnostics`` as well. Rasterised like an `.svg` URL.
    ///
    /// 顯示一份已解析的 SVG 文件(例如同時要讀取其 ``SVGDocument/diagnostics`` 時)。點陣化方式與
    /// `.svg` URL 相同。
    public init(_ document: SVGDocument) {
        source = .svg(document)
    }

    /// Rasterises an SVG source at exactly `width` x `height` pixels instead
    /// of at the displayed size; the backend then scales that bitmap to the
    /// view like any other image. No effect on png, jpg or webp.
    ///
    /// 讓 SVG 來源以剛好 `width` x `height` 像素點陣化，而非以顯示尺寸；之後 backend 會像處理其他
    /// 影像一樣把該點陣圖縮放到 view 上。對 png、jpg、webp 沒有作用。
    public func svgRasterSize(width: Int, height: Int) -> Self {
        var image = self
        image.svgRasterSize = SIMD2(max(1, width), max(1, height))
        return image
    }

    /// One of the toolkit's ``SystemSymbol`` values, by name.
    ///
    /// Spelled `systemName` to match SwiftUI, and it accepts both the SF Symbols
    /// name SwiftUI would use and this toolkit's own -- `plus` and `add` are the
    /// same symbol. See ``SystemSymbol/named(_:)``.
    ///
    /// **An unrecognised name draws the name itself**, on every backend, rather
    /// than nothing. That is deliberate and it is the same principle as the
    /// symbol table's fallback column: a typo in a symbol name is a mistake to
    /// be seen, and a view that silently occupies zero points is the one shape
    /// that cannot be seen. It is not resolved against the platform's own symbol
    /// set either, tempting as that is on Apple -- a name that happened to be a
    /// real SF Symbol would then render on macOS and as text everywhere else,
    /// which is worse than being wrong consistently.
    ///
    /// 依名稱指定本工具組 ``SystemSymbol`` 中的一個值。
    ///
    /// 拼寫為 `systemName` 以與 SwiftUI 一致，且它同時接受 SwiftUI 會使用的 SF Symbols 名稱與本工具組
    /// 自身的名稱——`plus` 與 `add` 是同一個符號。見 ``SystemSymbol/named(_:)``。
    ///
    /// **無法辨識的名稱會畫出該名稱本身**，在每一個 backend 上皆然，而不是什麼都不畫。這是刻意的，
    /// 其原則與符號表的退路欄位相同：符號名稱打錯是一個「應該被看見」的錯誤，而一個靜默地佔據零點的
    /// view，正是唯一看不見的形狀。它也不會去比對平台自身的符號集——儘管在 Apple 上那很誘人——因為
    /// 那會讓「碰巧是真實 SF Symbol 的名稱」在 macOS 上畫出圖示、在其他各處畫成文字，而那比「一致地
    /// 錯」更糟。
    public init(systemName: String) {
        source = .symbol(SystemSymbol.named(systemName) ?? .unresolved(systemName))
    }

    /// Makes the image resize to fit the available space.
    public func resizable() -> Self {
        var image = self
        image.isResizable = true
        return image
    }

    init(_ source: Source, resizable: Bool) {
        self.source = source
        self.isResizable = resizable
    }
}

extension Image: View {
    public var body: some View { return EmptyView() }
}

extension Image: TypeSafeView {
    func layoutableChildren<Backend: BaseAppBackend>(
        backend: Backend,
        children: ImageChildren
    ) -> [LayoutSystem.LayoutableChild] {
        []
    }

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> ImageChildren {
        ImageChildren(backend: backend)
    }

    func asWidget<Backend: BaseAppBackend>(
        _ children: ImageChildren,
        backend: Backend
    ) -> Backend.Widget {
        children.container.into()
    }

    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: ImageChildren,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        // A symbol is a glyph at the current font size, so it never enters the
        // decode-and-scale pipeline below and `resizable()` does not apply to
        // it. Its size is whatever the backend says it drew -- which is the
        // fallback string's size whenever the platform could not produce the
        // glyph, and those two are rarely the same width.
        //
        // 符號是「目前字級下的一個字符」，因此它完全不會進入下方的解碼與縮放管線，`resizable()`
        // 對它也不適用。它的尺寸就是 backend 所回報的、它實際畫出來的東西——當平台無法產生該字符
        // 時，那會是退路字串的尺寸，而這兩者的寬度極少相同。
        if case .symbol(let symbol) = source {
            let symbolWidget = children.symbolWidget(backend: backend)
            let size = backend.size(
                ofSymbol: symbol,
                whenDisplayedIn: symbolWidget,
                environment: environment
            )
            return ViewLayoutResult.leafView(size: ViewSize(size))
        }

        let image: ImageFormats.Image<RGBA>?
        if source != children.cachedImageSource {
            children.cachedSVG = nil
            children.svgRasters = []
            switch source {
                case .url(let url, let useFileExtension):
                    // TODO: Propagate these errors somewhere. Maybe even just as trace
                    //   log messages.
                    //
                    // File URLs only. `Data(contentsOf:)` will happily fetch an
                    // `https` URL, synchronously, and this runs inside
                    // `computeLayout` -- so a remote image stalled the whole
                    // interface for the length of the request, on every layout
                    // pass, with no cancellation and no way to show anything
                    // meanwhile. It looked supported, which is worse than not
                    // being supported.
                    //
                    // ``AsyncImage`` is the remote one. It fetches off the
                    // layout path and caches to disk.
                    //
                    // 僅限 file URL。`Data(contentsOf:)` 會毫不猶豫地同步抓取 `https` URL，而
                    // 此處位於 `computeLayout` 之內——因此遠端影像會在每一次 layout pass 中，以
                    // 整個請求的時間長度凍結整個介面，既無法取消，期間也無從顯示任何內容。它看起來
                    // 像是受支援的，而那比不支援更糟。
                    //
                    // 遠端影像請用 ``AsyncImage``：它在 layout 路徑之外抓取，並快取至磁碟。
                    if url.isFileURL, let data = try? Data(contentsOf: url) {
                        let bytes = Array(data)
                        let isSVG =
                            useFileExtension
                            ? url.pathExtension.lowercased() == "svg"
                            : SVGDocument.looksLikeSVG(bytes)
                        if isSVG {
                            image = nil
                            children.cachedSVG = Self.loadSVG(bytes, name: url.lastPathComponent)
                        } else if useFileExtension {
                            image = try? ImageFormats.Image<RGBA>.load(
                                from: bytes,
                                usingFileExtension: url.pathExtension
                            )
                        } else {
                            image = try? ImageFormats.Image<RGBA>.load(from: bytes)
                        }
                    } else {
                        image = nil
                    }
                case .image(let sourceImage):
                    image = sourceImage
                case .svg(let document):
                    image = nil
                    Self.report(document, name: "SVGDocument")
                    children.cachedSVG = document
                // Unreachable: the symbol branch above returned before this
                // switch. Written as `nil` rather than a fatal error because
                // the two arms are separated by twenty lines and a future edit
                // that moves the early return should show up as an empty view,
                // not as a crash in a release build.
                // 不可能到達:上方的符號分支已在此 switch 之前回傳。此處寫成 `nil` 而非致命錯誤,
                // 因為這兩處相隔二十行,而日後若有改動搬動了那個提前回傳,它應該表現為一個空 view,
                // 不是 release 版本中的一次崩潰。
                case .symbol:
                    image = nil
            }

            children.cachedImageSource = source
            children.cachedImage = image
            children.imageChanged = true
        } else {
            image = children.cachedImage
        }

        let size: ViewSize
        if let svg = children.cachedSVG {
            // An SVG's own size is in CSS pixels, which are points here.
            // SVG 自身的尺寸以 CSS 像素計，在此即為點。
            let idealSize = ViewSize(svg.width.rounded(), svg.height.rounded())
            if isResizable {
                size = proposedSize.replacingUnspecifiedDimensions(by: idealSize)
            } else {
                size = idealSize
            }
        } else if let image {
            let idealSize = ViewSize(Double(image.width), Double(image.height))
            if isResizable {
                size = proposedSize.replacingUnspecifiedDimensions(by: idealSize)
            } else {
                size = idealSize
            }
        } else {
            size = .zero
        }

        return ViewLayoutResult.leafView(size: size)
    }

    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: ImageChildren,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        if case .symbol(let symbol) = source {
            let size = layout.size.vector
            let symbolWidget = children.symbolWidget(backend: backend)
            backend.updateSymbolView(symbolWidget, symbol: symbol, environment: environment)
            if children.isContainerEmpty {
                backend.insert(symbolWidget, into: children.container.into(), at: 0)
                backend.setPosition(ofChildAt: 0, in: children.container.into(), to: .zero)
                children.isContainerEmpty = false
            }
            backend.setSize(of: children.container.into(), to: size)
            backend.setSize(of: symbolWidget, to: size)
            return
        }

        let size = layout.size.vector
        if let svg = children.cachedSVG {
            let scale = environment.windowScaleFactor
            let pixels =
                svgRasterSize
                ?? SIMD2(
                    Int((Double(size.x) * scale).rounded()),
                    Int((Double(size.y) * scale).rounded()))
            if pixels.x > 0 && pixels.y > 0 {
                if children.cachedImage == nil || children.svgRasterSize != pixels {
                    children.cachedImage = children.raster(of: svg, pixels: pixels)
                    children.svgRasterSize = pixels
                    children.imageChanged = true
                }
            } else if children.cachedImage != nil {
                children.cachedImage = nil
                children.svgRasterSize = nil
                children.imageChanged = true
            }
        }
        let hasResized = children.cachedImageDisplaySize != size
        children.cachedImageDisplaySize = size
        if children.imageChanged
            || hasResized
            || (backend.requiresImageUpdateOnScaleFactorChange
                && children.lastScaleFactor != environment.windowScaleFactor)
        {
            if let image = children.cachedImage {
                backend.updateImageView(
                    children.imageWidget.into(),
                    rgbaData: image.bytes,
                    width: image.width,
                    height: image.height,
                    targetWidth: size.x,
                    targetHeight: size.y,
                    dataHasChanged: children.imageChanged,
                    environment: environment
                )
                if children.isContainerEmpty {
                    backend.insert(
                        children.imageWidget.into(),
                        into: children.container.into(),
                        at: 0
                    )
                    backend.setPosition(ofChildAt: 0, in: children.container.into(), to: .zero)
                }
                children.isContainerEmpty = false
            } else {
                if !children.isContainerEmpty {
                    backend.removeAllChildren(of: children.container.into())
                }
                children.isContainerEmpty = true
            }
            children.imageChanged = false
            children.lastScaleFactor = environment.windowScaleFactor
        }
        backend.setSize(of: children.container.into(), to: size)
        backend.setSize(of: children.imageWidget.into(), to: size)
    }

    /// Parses SVG bytes; a file that cannot be parsed becomes a visible
    /// placeholder rather than an empty view.
    /// 解析 SVG 位元組；無法解析的檔案會成為看得見的佔位圖，而不是空的 view。
    static func loadSVG(_ bytes: [UInt8], name: String) -> SVGDocument {
        let document: SVGDocument
        do {
            document = try SVGDocument(data: bytes)
        } catch {
            document = SVGDocument.unreadable(error)
        }
        report(document, name: name)
        return document
    }

    /// Logs what the renderer did not draw, once per load.
    /// 記錄算繪器沒有畫出的內容，每次載入一次。
    static func report(_ document: SVGDocument, name: String) {
        guard !document.diagnostics.isEmpty else { return }
        let lines = document.diagnostics.map { "  \($0)" }.joined(separator: "\n")
        logger.warning(
            "SVG \(name): \(document.diagnostics.count) unsupported item(s), outlined in magenta:\n\(lines)"
        )
    }
}

/// Image's persistent storage. Only exposed with the `package` access level
/// in order for backends to implement the `Image.inspect(_:_:)` modifier.
@_spi(Backends) public class ImageChildren: ViewGraphNodeChildren {
    var cachedImageSource: Image.Source? = nil
    var cachedImage: ImageFormats.Image<RGBA>? = nil
    var cachedImageDisplaySize: SIMD2<Int> = .zero
    var container: AnyWidget
    public var imageWidget: AnyWidget
    var imageChanged = false
    var isContainerEmpty = true
    var lastScaleFactor: Double = 1
    /// The parsed SVG when the source is one; `cachedImage` then holds its
    /// raster at `svgRasterSize`.
    /// 來源為 SVG 時的已解析文件；此時 `cachedImage` 存放其在 `svgRasterSize` 下的點陣圖。
    var cachedSVG: SVGDocument? = nil
    var svgRasterSize: SIMD2<Int>? = nil
    /// The last few rasters by pixel size, most recent last, so that a view
    /// going back and forth between sizes (a window being resized, a size
    /// toggle) does not rasterise again.
    /// 依像素尺寸保存的最近幾張點陣圖(最新的在最後),讓在幾個尺寸之間來回切換的 view(調整視窗
    /// 大小、尺寸切換)不必重新點陣化。
    var svgRasters: [(size: SIMD2<Int>, image: ImageFormats.Image<RGBA>)] = []
    static let svgRasterCacheLimit = 4

    func raster(of document: SVGDocument, pixels: SIMD2<Int>) -> ImageFormats.Image<RGBA> {
        if let index = svgRasters.firstIndex(where: { $0.size == pixels }) {
            let entry = svgRasters.remove(at: index)
            svgRasters.append(entry)
            return entry.image
        }
        let image = document.rasterize(width: pixels.x, height: pixels.y)
        svgRasters.append((pixels, image))
        if svgRasters.count > Self.svgRasterCacheLimit {
            svgRasters.removeFirst()
        }
        return image
    }

    /// Created on demand, because most images are not symbols.
    ///
    /// `imageWidget` is created eagerly in `init` and a second eager widget
    /// would double the widget count of every raster image in the tree to serve
    /// the ones that are symbols. `commit` and `computeLayout` both have the
    /// backend in hand, so there is nowhere this needs to be made in advance.
    ///
    /// 依需要建立，因為大多數的 image 並不是符號。
    ///
    /// `imageWidget` 是在 `init` 中積極建立的，而第二個積極建立的 widget 會讓樹中每一張點陣圖的
    /// widget 數量加倍，只為了服務其中屬於符號的那些。`commit` 與 `computeLayout` 手上都有 backend，
    /// 因此此處沒有任何需要提前建立的理由。
    var cachedSymbolWidget: AnyWidget? = nil

    func symbolWidget<Backend: BaseAppBackend>(backend: Backend) -> Backend.Widget {
        if let cachedSymbolWidget {
            return cachedSymbolWidget.into()
        }
        let widget = backend.createSymbolView()
        cachedSymbolWidget = AnyWidget(widget)
        return widget
    }

    init<Backend: BaseAppBackend>(backend: Backend) {
        container = AnyWidget(backend.createContainer())
        imageWidget = AnyWidget(backend.createImageView())
    }

    public var widgets: [AnyWidget] = []
    public var erasedNodes: [ErasedViewGraphNode] = []
}
