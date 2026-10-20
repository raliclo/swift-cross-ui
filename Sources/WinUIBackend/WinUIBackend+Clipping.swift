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
            self.clipToBounds(width: Double(size.width), height: Double(size.height))
        }
    }

    /// Also called from `setSize(of:to:)`: SizeChanged alone never set the clip
    /// in P17-DOE's column B, whose orange block spilled past the box on WinUI
    /// while GTK clipped it (2026-10-20) -- the same silence P95's mesh view met.
    /// 也由 `setSize(of:to:)` 呼叫：單靠 SizeChanged 時,P17-DOE 的 B 欄從未設定 clip,橘色區塊在 WinUI 上溢出外框，
    /// 而 GTK 有裁切(2026-10-20)——與 P95 的 mesh view 遇到的是同一種沉默。
    func clipToBounds(width: Double, height: Double) {
        let geometry = clip ?? RectangleGeometry()
        geometry.rect = Rect(x: 0, y: 0, width: Float(width), height: Float(height))
        clip = geometry
    }
}
