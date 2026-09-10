/// A proxy for querying a view's geometry. See ``GeometryReader``.
public struct GeometryProxy {
    /// The size proposed to the view by its parent. In the context of
    /// ``GeometryReader``, this is the size that the ``GeometryReader``
    /// will take on (to prevent feedback loops).
    public var size: ViewSize

    /// Where this view's top-leading corner sits in its window, or `nil` before
    /// it has been placed in one.
    ///
    /// Not public: what a caller wants is ``frame(in:)``, and an origin without
    /// a coordinate space attached is a number waiting to be misread.
    ///
    /// 這個 view 的左上角在它的視窗中的位置；在它被放進某個視窗之前為 `nil`。
    ///
    /// 不對外公開:呼叫端要的是 ``frame(in:)``，而一個沒有附帶座標系的原點，是一個等著被誤讀的數字。
    var originInWindow: SIMD2<Int>?

    /// The origins of the named coordinate spaces this view sits inside.
    /// 這個 view 所位於的那些具名座標系的原點。
    var namedOrigins: [String: SIMD2<Int>]

    init(
        size: ViewSize,
        originInWindow: SIMD2<Int>? = nil,
        namedOrigins: [String: SIMD2<Int>] = [:]
    ) {
        self.size = size
        self.originInWindow = originInWindow
        self.namedOrigins = namedOrigins
    }

    /// This view's frame, in the given space.
    ///
    /// ```swift
    /// GeometryReader { proxy in
    ///     Text("\(proxy.frame(in: .global).x)")
    /// }
    /// ```
    ///
    /// **The size is always exact; the origin is only as current as the last
    /// time this view was placed.** A view is laid out before it is positioned,
    /// so on the very first pass there is no origin yet and every space answers
    /// as ``CoordinateSpace/local`` does. ``GeometryReader`` asks for another
    /// pass when it learns an origin it did not have, so this settles on the
    /// second one rather than staying wrong.
    ///
    /// 這個 view 的 frame，以指定的座標系表示。
    ///
    /// **尺寸永遠是精確的；原點則只反映「這個 view 最後一次被放置」的狀態。** 一個 view 會在被定位
    /// 之前先被排版，因此在最初那一輪根本還沒有原點，此時每一種座標系的答案都與
    /// ``CoordinateSpace/local`` 相同。``GeometryReader`` 在得知一個它先前沒有的原點時會要求再排一輪，
    /// 因此這件事會在第二輪收斂，而不是一直錯下去。
    public func frame(in space: CoordinateSpace) -> Path.Rect {
        let origin: SIMD2<Int>
        switch space {
            case .local:
                origin = .zero
            case .global:
                origin = originInWindow ?? .zero
            case .named(let name):
                if let space = namedOrigins[name], let mine = originInWindow {
                    origin = mine &- space
                } else {
                    // Unresolved: window coordinates, which is a visible wrong
                    // answer rather than a plausible one. See `CoordinateSpace`.
                    // 解析不到:改用視窗座標——那是一個**看得出來**的錯誤答案，而不是一個說得通的。
                    origin = originInWindow ?? .zero
                }
        }
        return Path.Rect(
            origin: SIMD2(Double(origin.x), Double(origin.y)),
            size: SIMD2(size.width, size.height)
        )
    }
}
