/// A shape that has style information attached to it, including color and
/// stroke style.
public protocol StyledShape: Shape {
    /// The shape's stroke color.
    var strokeColor: Color? { get }
    /// The shape's fill color.
    var fillColor: Color? { get }
    /// The shape's stroke style.
    var strokeStyle: StrokeStyle? { get }
    /// A fill that is not a flat colour, if one was given.
    ///
    /// Defaulted to `nil` so that adding it did not have to touch every
    /// conformer. When it is set it wins over ``fillColor``, which stays for
    /// the flat case and for backends that cannot paint this.
    /// 若曾指定非平面色的填充，即為此值。
    /// 預設為 `nil`，使得新增它不必更動每一個 conformer。有值時它優先於 ``fillColor``——後者
    /// 保留給平面色的情況，以及無法繪製此填充的 backend 使用。
    var fillStyleOverride: ResolvedFillStyle? { get }
    /// A stroke that is not a flat colour, if one was given.
    /// 若曾指定非平面色的描邊，即為此值。
    var strokeStyleOverride: ResolvedFillStyle? { get }
}

extension StyledShape {
    public var fillStyleOverride: ResolvedFillStyle? { nil }
    public var strokeStyleOverride: ResolvedFillStyle? { nil }
}

struct StyledShapeImpl<Base: Shape>: Sendable {
    var base: Base
    var strokeColor: Color?
    var fillColor: Color?
    var strokeStyle: StrokeStyle?
    var fillStyleOverride: ResolvedFillStyle?
    var strokeStyleOverride: ResolvedFillStyle?

    init(
        base: Base,
        strokeColor: Color? = nil,
        fillColor: Color? = nil,
        strokeStyle: StrokeStyle? = nil,
        fillStyleOverride: ResolvedFillStyle? = nil,
        strokeStyleOverride: ResolvedFillStyle? = nil
    ) {
        self.base = base

        if let styledBase = base as? any StyledShape {
            self.strokeColor = strokeColor ?? styledBase.strokeColor
            self.fillColor = fillColor ?? styledBase.fillColor
            self.strokeStyle = strokeStyle ?? styledBase.strokeStyle
            self.fillStyleOverride = fillStyleOverride ?? styledBase.fillStyleOverride
            self.strokeStyleOverride = strokeStyleOverride ?? styledBase.strokeStyleOverride
        } else {
            self.strokeColor = strokeColor
            self.fillColor = fillColor
            self.strokeStyle = strokeStyle
            self.fillStyleOverride = fillStyleOverride
            self.strokeStyleOverride = strokeStyleOverride
        }
    }
}

extension StyledShapeImpl: StyledShape {
    func path(in bounds: Path.Rect) -> Path {
        return base.path(in: bounds)
    }

    func size(fitting proposal: ProposedViewSize) -> ViewSize {
        return base.size(fitting: proposal)
    }
}

extension Shape {
    public func fill(_ color: Color) -> some StyledShape {
        StyledShapeImpl(base: self, fillColor: color)
    }

    public func stroke(_ color: Color, style: StrokeStyle? = nil) -> some StyledShape {
        StyledShapeImpl(base: self, strokeColor: color, strokeStyle: style)
    }

    /// Fills the shape with a gradient, clipped to the shape.
    ///
    /// Overloads rather than a `ShapeStyle` protocol: the protocol is #31 and
    /// should arrive once something concrete is behind it, the way
    /// `DatePickerStyle` and `ListStyle` became protocols only after they did
    /// something.
    ///
    /// The points are in the shape's own unit space, which is what distinguishes
    /// this from the gradient *views* -- those fill a rectangle they own and
    /// cannot be clipped to a circle.
    ///
    /// 以漸層填充此形狀，並裁切至形狀範圍。
    ///
    /// 使用多載而非 `ShapeStyle` protocol：該 protocol 是 #31，應在其後有具體實作之後才引入
    /// ——正如 `DatePickerStyle` 與 `ListStyle` 都是在真的做了事之後才成為 protocol。
    ///
    /// 這些點位於形狀自身的單位空間中，這正是它與漸層**視圖**的區別——後者填滿的是它自己擁有
    /// 的矩形，無法被裁進一個圓形。
    public func fill(
        _ gradient: Gradient,
        from startPoint: UnitPoint = .top,
        to endPoint: UnitPoint = .bottom
    ) -> some StyledShape {
        StyledShapeImpl(
            base: self,
            fillStyleOverride: .linearGradient(
                gradient,
                startPoint: startPoint,
                endPoint: endPoint
            )
        )
    }

    public func fill(
        _ gradient: Gradient,
        center: UnitPoint,
        startRadius: Double,
        endRadius: Double
    ) -> some StyledShape {
        StyledShapeImpl(
            base: self,
            fillStyleOverride: .radialGradient(
                gradient,
                center: center,
                startRadius: startRadius,
                endRadius: endRadius
            )
        )
    }

    /// Strokes the shape with a gradient, clipped to the stroke.
    ///
    /// Clipped to the **stroke**, which is the part a backend is most likely to
    /// get wrong in a way that looks deliberate: clipping to the fill region
    /// instead gives a shape filled with a gradient where an outline was asked
    /// for. P43's fourth shape exists to catch exactly that -- a gradient ring
    /// whose middle must stay empty.
    ///
    /// 以漸層描邊此形狀，並裁切至描邊範圍。
    ///
    /// 裁切至**描邊**，而這正是 backend 最可能「錯得像是刻意為之」的地方：若改為裁切至填充區域，
    /// 得到的會是一個填滿漸層的形狀，而非所要求的輪廓。P43 的第四個形狀就是為了抓出這件事——
    /// 一個中間必須保持空白的漸層環。
    public func stroke(
        _ gradient: Gradient,
        from startPoint: UnitPoint = .top,
        to endPoint: UnitPoint = .bottom,
        style: StrokeStyle? = nil
    ) -> some StyledShape {
        StyledShapeImpl(
            base: self,
            strokeStyle: style,
            strokeStyleOverride: .linearGradient(
                gradient,
                startPoint: startPoint,
                endPoint: endPoint
            )
        )
    }
}

extension StyledShape {
    @MainActor
    public func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: any ViewGraphNodeChildren,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        let size = size(fitting: proposedSize)
        return ViewLayoutResult.leafView(size: size)
    }

    @MainActor
    @CastBackend<BackendFeatures.Paths>(backendGenericName: "NewBackend")
    public func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: any ViewGraphNodeChildren,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        let bounds = Path.Rect(
            x: 0.0,
            y: 0.0,
            width: layout.size.width,
            height: layout.size.height
        )
        let path = path(in: bounds)

        let storage = children as! ShapeStorage
        let pointsChanged = storage.oldPath?.actions != path.actions
        storage.oldPath = path

        let backendPath = storage.backendPath as! NewBackend.Path
        backend.updatePath(
            backendPath,
            path,
            bounds: bounds,
            pointsChanged: pointsChanged,
            environment: environment
        )

        backend.setSize(of: widget, to: layout.size.vector)
        // Always the style-taking call, even for a flat colour. A backend that
        // has not opted in gets the default, which unwraps straight back to the
        // two-colour method, so the flat path is unchanged; routing flat fills
        // down a second code path would be the thing most likely to break them.
        // 一律走接收樣式的那個呼叫，即使是平面色。尚未加入的 backend 會取得預設實作，而它會直接
        // 解回兩色的方法，因此平面色路徑毫無改變；若讓平面填充改走第二條程式碼路徑，那才是最可能
        // 弄壞它們的做法。
        backend.renderPath(
            backendPath,
            container: widget,
            strokeStyle: strokeStyleOverride
                ?? .color((strokeColor ?? .clear).resolve(in: environment)),
            fillStyle: fillStyleOverride
                ?? .color((fillColor ?? .clear).resolve(in: environment)),
            overrideStrokeStyle: strokeStyle,
            environment: environment
        )
    }
}
