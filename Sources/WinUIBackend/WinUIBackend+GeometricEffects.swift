import Foundation
@_spi(Backends) import SwiftCrossUI
import WinUI
import WindowsFoundation

extension WinUIBackend: BackendFeatures.GeometricEffects {
    public func createGeometricEffectContainer(wrapping child: Widget) -> Widget {
        let container = createContainer()
        insert(child, into: container, at: 0)
        return container
    }

    // `SwiftCrossUI.AffineTransform` in full: Foundation exports a type of the
    // same name, and this file imports both.
    public func setGeometricEffect(
        _ transform: SwiftCrossUI.AffineTransform,
        ofWidget widget: Widget
    ) {
        guard transform != .identity else {
            widget.renderTransform = nil
            return
        }

        // WinUI's Matrix is the transpose of AffineTransform's, which the
        // AffineTransform documentation says outright -- m12 takes the value
        // stored at row 0 column 1. Same trap as the GTK backend's CSS matrix:
        // getting it backwards is invisible under pure scaling and wrong under
        // rotation.
        let matrix = WinUI.Matrix(
            m11: transform.linearTransform.x,
            m12: transform.linearTransform.z,
            m21: transform.linearTransform.y,
            m22: transform.linearTransform.w,
            offsetX: transform.translation.x,
            offsetY: transform.translation.y
        )

        let renderTransform = MatrixTransform()
        renderTransform.matrix = matrix
        widget.renderTransform = renderTransform

        // The anchor is already in the matrix, so the element must not apply its
        // own. RenderTransformOrigin defaults to (0, 0), which is what is wanted,
        // but it is set explicitly because a container reused from elsewhere
        // could carry a different one.
        widget.renderTransformOrigin = WindowsFoundation.Point(x: 0, y: 0)
    }
}
