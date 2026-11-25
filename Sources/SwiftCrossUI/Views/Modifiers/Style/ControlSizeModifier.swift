extension View {
    /// Sets the size of the controls within this view.
    ///
    /// Inherited through the environment, as SwiftUI's is: every button,
    /// stepper, toggle, slider, picker, text field, secure field and progress view beneath
    /// this modifier takes the size, until a nearer `controlSize(_:)` replaces
    /// it. Text and other views that are not controls are left alone.
    ///
    /// Every case changes the size on every backend, by the same factor
    /// (``ControlSize/scale``): a button's label font and padding are scaled,
    /// so its text stays sharp and the platform bezel is drawn at the new size;
    /// a control drawn entirely by the platform is laid out at its regular size
    /// and drawn scaled about its top-left corner through the backend's
    /// geometric effect, which on each backend moves hit testing with it.
    ///
    /// 設定此 view 之內控制項的尺寸。
    ///
    /// 與 SwiftUI 相同，經由 environment 繼承：此 modifier 之下的每個按鈕、stepper、toggle、slider、picker、
    /// 文字欄位、安全文字欄位與進度指示都採用這個尺寸，直到更近的 `controlSize(_:)` 取代它。文字與其他不是控制項的 view 不受影響。
    ///
    /// 每一個 case 在每個 backend 上都會以同一個倍率(``ControlSize/scale``)改變尺寸：按鈕的標籤字型與 padding
    /// 被縮放，因此文字保持清晰、平台外框以新尺寸繪製；完全由平台繪製的控制項以 regular 尺寸排版，再經由 backend 的
    /// 幾何效果以左上角為原點縮放畫出，而在每個 backend 上 hit testing 都跟著它移動。
    public func controlSize(_ controlSize: ControlSize) -> some View {
        EnvironmentModifier(self) { environment in
            environment.with(\.controlSize, controlSize)
        }
    }

    /// Draws this native control at the environment's ``ControlSize``.
    ///
    /// For a control whose content the platform draws (a switch, a slider, a
    /// text field), where SwiftCrossUI has no label of its own to resize.
    ///
    /// 以 environment 的 ``ControlSize`` 畫出這個原生控制項。用於內容由平台繪製的控制項(switch、slider、
    /// 文字欄位)，那裡 SwiftCrossUI 沒有自己的標籤可以調整大小。
    func scaledToControlSize() -> some View {
        ControlSizeScaler(body: TupleView1(self))
    }
}

extension EnvironmentValues {
    /// This environment with its font scaled by ``controlSize``, for the label
    /// of a control whose label is a SwiftCrossUI view (``Button`` and a
    /// view-label toggle).
    ///
    /// Through the font overlay, so a label that sets its own font is scaled
    /// too, as SwiftUI scales a `.font(.title)` label in a small button.
    ///
    /// 依 ``controlSize`` 縮放字型後的 environment,用於標籤是 SwiftCrossUI view 的控制項(``Button`` 與
    /// view 標籤的 toggle)。經由字型 overlay,因此自己設定字型的標籤也會被縮放，與 SwiftUI 在小按鈕中縮放
    /// `.font(.title)` 標籤相同。
    var scalingFontToControlSize: EnvironmentValues {
        let scale = controlSize.scale
        guard scale != 1 else { return self }
        return self
            .with(\.fontOverlay.pointSizeScaleFactor, fontOverlay.pointSizeScaleFactor * scale)
            .with(\.fontOverlay.lineHeightScaleFactor, fontOverlay.lineHeightScaleFactor * scale)
    }

    /// A button's or toggle's padding scaled by ``controlSize``, rounded to
    /// whole points.
    ///
    /// 依 ``controlSize`` 縮放、四捨五入到整數點的按鈕或 toggle padding。
    func scalingPaddingToControlSize(_ padding: SIMD2<Int>) -> SIMD2<Int> {
        let scale = controlSize.scale
        guard scale != 1 else { return padding }
        return SIMD2(
            Int((Double(padding.x) * scale).rounded()),
            Int((Double(padding.y) * scale).rounded())
        )
    }
}

/// The children of a ``ControlSizeScaler``, and whether its widget is a
/// geometric-effect container around the control.
///
/// ``ControlSizeScaler`` 的 children,以及它的 widget 是否為包住控制項的幾何效果容器。
final class ControlSizeScalerChildren<Content: View>: TupleViewChildren1<Content> {
    var isWrapped = false
    /// Whether a scale was last applied to the control's own widget; see
    /// `commit`. / 上一次是否把倍率直接套在控制項自己的 widget 上；見 `commit`。
    var scaledDirectly = false
}

/// Lays a native control out at its regular size and draws it at the
/// environment's control size.
///
/// The control is proposed the space divided by the scale, and the size it
/// chooses is reported multiplied by it, so neighbours make room for the
/// scaled control and a slider or text field given a width still fills exactly
/// that width. The control's widget keeps its regular size inside a geometric
/// effect container, which draws it scaled about the top-left corner: a
/// `CATransform3D` on AppKit, a `CGAffineTransform` on UIKit, a GSK transform
/// on GTK, a `RenderTransform` on WinUI and a scale on the Android view. Each
/// of those backends hit-tests through the transform, so the whole drawn
/// control answers clicks and touches.
///
/// **The container exists only where the size is not `.regular` when the
/// control is created.** A container changes which widget an outer modifier
/// such as `accessibilityLabel` lands on, so at `.regular` -- every control in
/// every application that never calls `controlSize(_:)` -- the control's own
/// widget is used and nothing about it changes. A control created at
/// `.regular` whose size changes later is scaled through its own widget
/// instead.
///
/// 以 regular 尺寸排版一個原生控制項，再以 environment 的控制項尺寸畫出它。
///
/// 提議給控制項的空間除以倍率，它選定的尺寸再乘以倍率回報，因此鄰居會為縮放後的控制項讓出空間，而被給定寬度的
/// slider 或文字欄位仍然恰好填滿那個寬度。控制項的 widget 在幾何效果容器裡維持 regular 尺寸，由容器以左上角為原點
/// 縮放畫出:AppKit 上是 `CATransform3D`,UIKit 上是 `CGAffineTransform`,GTK 上是 GSK transform,WinUI 上是
/// `RenderTransform`,Android 上是 view 的 scale。這些 backend 都經由該變換做 hit testing,因此整個畫出的控制項
/// 都會回應點擊與觸控。
///
/// **只有在控制項建立時尺寸不是 `.regular`,才會有這個容器。** 容器會改變外層 modifier(例如
/// `accessibilityLabel`)落在哪個 widget 上，因此在 `.regular` 時——也就是所有從未呼叫 `controlSize(_:)`
/// 的應用程式中的每個控制項——使用的是控制項自己的 widget,它的一切都不變。在 `.regular` 建立、之後才改變尺寸的
/// 控制項，改由它自己的 widget 縮放。
struct ControlSizeScaler<Content: View>: TypeSafeView {
    typealias Children = ControlSizeScalerChildren<Content>

    var body: TupleView1<Content>

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> Children {
        let children = Children(
            body.view0,
            backend: backend,
            snapshots: snapshots,
            environment: environment
        )
        children.isWrapped = environment.controlSize != .regular
        return children
    }

    func asWidget<Backend: BaseAppBackend>(
        _ children: Children,
        backend: Backend
    ) -> Backend.Widget {
        let control: Backend.Widget = children.child0.widget.into()
        guard children.isWrapped,
            let container = GeometricEffectWidgets.wrap(control, backend: backend)
        else {
            children.isWrapped = false
            return control
        }
        return container
    }

    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        let scale = Self.scale(in: environment, backend: backend)
        var controlProposal = proposedSize
        controlProposal.width = proposedSize.width.map { $0 / scale }
        controlProposal.height = proposedSize.height.map { $0 / scale }

        let controlResult = children.child0.computeLayout(
            with: body.view0,
            proposedSize: controlProposal,
            environment: environment
        )
        return ViewLayoutResult(
            size: ViewSize(
                controlResult.size.width * scale,
                controlResult.size.height * scale
            ),
            childResults: [controlResult],
            participateInStackLayoutsWhenEmpty: controlResult.participateInStackLayoutsWhenEmpty
        )
    }

    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        let controlSize = children.child0.commit().size
        let scale = Self.scale(in: environment, backend: backend)
        let transform = AffineTransform(
            linearTransform: SIMD4(x: scale, y: 0, z: 0, w: scale),
            translation: .zero
        )

        if children.isWrapped {
            // The container is the control's regular size; the transform
            // draws it over the scaled rectangle the parent placed it in.
            // 容器是控制項的 regular 尺寸；變換把它畫滿父層放置它的那個縮放後矩形。
            backend.setSize(of: widget, to: controlSize.vector)
            GeometricEffectWidgets.setter(for: widget, backend: backend)?(transform)
        } else if scale != 1 || children.scaledDirectly {
            // Created at `.regular`, so there is no container: the control's
            // own widget carries the transform. Reset to identity when the size
            // returns to `.regular`.
            // 建立時是 `.regular`,所以沒有容器：由控制項自己的 widget 承載變換。尺寸回到 `.regular`
            // 時重設為單位變換。
            GeometricEffectWidgets.setter(for: widget, backend: backend)?(transform)
            children.scaledDirectly = scale != 1
        }
    }

    /// The scale to lay out with: 1 on a backend without geometric effects,
    /// which cannot draw the control scaled and so must not size it scaled.
    /// All five shipped backends have them.
    ///
    /// 排版所用的倍率：在沒有幾何效果的 backend 上為 1——它畫不出縮放後的控制項，因此也不能以縮放後的尺寸排版。
    /// 五個已發布的 backend 都有幾何效果。
    private static func scale<Backend: BaseAppBackend>(
        in environment: EnvironmentValues,
        backend: Backend
    ) -> Double {
        guard backend is any BackendFeatures.GeometricEffects else { return 1 }
        return environment.controlSize.scale
    }
}

/// A style's view as ``AnyView``, drawn at the control size when the style is
/// a built-in one whose view is the backend's own control. A custom style is
/// left as it is: it can read ``EnvironmentValues/controlSize`` and size itself.
///
/// 把 style 的 view 包成 ``AnyView``;style 是內建的、其 view 為 backend 自身的控制項時，以控制項尺寸繪製。
/// 自訂 style 原樣保留：它可以讀取 ``EnvironmentValues/controlSize`` 自行決定尺寸。
@MainActor
func controlSizedStyleBody(_ body: any View, isBuiltin: Bool) -> AnyView {
    guard isBuiltin else { return AnyView(body) }
    func scaled<Control: View>(_ control: Control) -> AnyView {
        AnyView(control.scaledToControlSize())
    }
    return scaled(body)
}
