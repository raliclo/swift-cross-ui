@_spi(Backends) import SwiftCrossUI
import WinUI
import WindowsFoundation

extension WinUIBackend: BackendFeatures.Clipping {
    public func createClippedContainer() -> Widget {
        ClippedCanvas()
    }
}

extension WinUIBackend: BackendFeatures.HitTesting {
    /// Subtree-wide, as the protocol requires, and for free: XAML propagates
    /// `isHitTestVisible` down the visual tree, so a child cannot opt back in.
    /// That is the same rule SwiftUI applies, so nothing extra is needed to
    /// match it here.
    public func setHitTesting(of widget: Widget, to allowsHitTesting: Bool) {
        widget.isHitTestVisible = allowsHitTesting
    }
}

/// A `Canvas` that clips its children to its own bounds.
///
/// A plain `Canvas` does not clip: `UIElement.clip` is nil by default and XAML
/// happily draws a child past its parent's edge. The clip has to be an explicit
/// `RectangleGeometry`, and because that geometry holds a fixed rect rather than
/// tracking the element, it has to be rebuilt whenever the element is resized.
///
/// `sizeChanged` is used rather than piggy-backing on the backend's
/// `setSize(of:to:)` because the two are not the same event. `setSize` records
/// the *requested* size on `width`/`height`; the rect that must be clipped is
/// the size XAML actually laid the element out at, which is what `sizeChanged`
/// reports. Clipping to the requested size would leave a one-pixel bleed
/// wherever layout rounded differently.
///
/// The clip is left nil until the first size arrives rather than starting as an
/// empty rect. An empty rect clips everything, so if the event never fired the
/// content would vanish; leaving it nil means the worst case is a child that
/// overflows, which is what a backend without clipping does anyway.
final class ClippedCanvas: WinUI.Canvas {
    override init() {
        super.init()

        sizeChanged.addHandler { [weak self] _, args in
            guard let self, let size = args?.newSize else { return }
            let geometry = self.clip ?? RectangleGeometry()
            geometry.rect = Rect(x: 0, y: 0, width: size.width, height: size.height)
            self.clip = geometry
        }
    }
}
