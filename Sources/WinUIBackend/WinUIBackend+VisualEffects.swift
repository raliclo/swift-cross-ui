import Foundation
@_spi(Backends) import SwiftCrossUI
import WinUI

extension WinUIBackend: BackendFeatures.VisualEffects {
    public func createVisualEffectContainer(wrapping child: Widget) -> Widget {
        // A real container, not `child` returned unmodified the way
        // `createCornerRadiusContainer` does. Composition here comes from
        // nesting: `.opacity(0.5).opacity(0.5)` must be 0.25, and returning the
        // child would have both modifiers write to the same element, leaving
        // 0.5. A corner radius is idempotent so it can share; an effect is not.
        let container = createContainer()
        insert(child, into: container, at: 0)
        return container
    }

    public func setVisualEffect(_ effect: VisualEffect, ofWidget widget: Widget) {
        widget.opacity = effect.opacity

        // Everything else needs a Microsoft.UI.Composition effect graph, which
        // this backend does not build yet. Reported rather than dropped: a
        // silent no-op here is indistinguishable from the effect being applied
        // and having no visible result, and that ambiguity is the whole subject
        // of testapp/gtk-silent-noops.md.
        //
        // Conforming with a partial implementation is deliberate. Declining to
        // conform would not degrade gracefully -- @CastBackend turns a missing
        // conformance into fatalError, so `.opacity(_:)` would abort every app
        // on the default Windows backend rather than render un-blurred.
        var unsupported: [String] = []
        if effect.blurRadius != 0 { unsupported.append("blur") }
        if effect.saturation != 1 { unsupported.append("saturation") }
        if effect.brightness != 0 { unsupported.append("brightness") }
        if effect.contrast != 1 { unsupported.append("contrast") }
        if effect.grayscale != 0 { unsupported.append("grayscale") }
        if effect.hueRotation != .zero { unsupported.append("hueRotation") }

        if !unsupported.isEmpty {
            logger.warning(
                """
                WinUIBackend applied opacity but not \(unsupported.joined(separator: ", ")); \
                these need a Microsoft.UI.Composition effect graph, which is not built yet
                """
            )
        }
    }
}
