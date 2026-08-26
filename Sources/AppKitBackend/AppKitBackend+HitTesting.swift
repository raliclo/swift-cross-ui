import SwiftCrossUI

extension AppKitBackend: BackendFeatures.HitTesting {
    /// Does nothing, deliberately, and this file exists to say so.
    ///
    /// `allowsHitTesting(false)` therefore has no effect on macOS: the view
    /// stays clickable. That is the wrong behaviour and it is still the right
    /// choice, because the alternative is worse. Not conforming does not make
    /// the modifier degrade — `@CastBackend` expands to `fatalError`, so an app
    /// that merely *mentions* `allowsHitTesting` dies during layout. The
    /// protocol's own documentation settles it: "A backend that cannot express
    /// this should do nothing. Ignoring it leaves the view interactive when it
    /// was asked not to be, which is visible and reportable; refusing to draw it
    /// would not be."
    ///
    /// Why it cannot be implemented as the protocol is shaped. `Widget` is a
    /// bare `NSView`, and `setHitTesting(of:to:)` is handed whatever view the
    /// content produced — an `NSButton`, an `NSTextField`, a container this
    /// backend never made. AppKit has no `isUserInteractionEnabled`; the only
    /// way out of hit testing is overriding `hitTest(_:)`, which requires having
    /// created that view as a subclass. `AllowsHitTestingModifier` deliberately
    /// adds no wrapper of its own ("the flag goes on the content's widget"), so
    /// there is no backend-created view in the path to interpose one on.
    ///
    /// A design that would work, recorded so the next person does not re-derive
    /// it: put the override on the container instead of on the marked view.
    /// `createContainer()` is this backend's own `NSView`, so it can be a
    /// subclass overriding `hitTest(_:)`; `setHitTesting` records the widget in
    /// a weak-keyed side table (`NSMapTable`) rather than touching it; the
    /// container takes `super.hitTest`'s result and walks up to itself,
    /// returning nil if any view on that path is in the table. That gives the
    /// subtree-wide semantics the protocol specifies, costs O(depth) per hit
    /// test, and never touches a view this backend did not create.
    ///
    /// It is not written here because this machine has no macOS toolchain — it
    /// is Windows and WSL — so it would ship as code that has never been through
    /// a compiler. A hit-testing mechanism that is subtly wrong shows up as
    /// clicks occasionally passing through the wrong view, which is among the
    /// hardest things to trace back to its cause. An empty method body cannot be
    /// subtly wrong.
    public func setHitTesting(of widget: Widget, to allowsHitTesting: Bool) {}
}
