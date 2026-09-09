# AppBackend refactor

Changes to the `AppBackend` protocol

> Note: See [the relevant PR](https://github.com/moreSwift/swift-cross-ui/pull/513) for more info.

There was recently a _massive_ refactoring of the equally massive `AppBackend` protocol. Here's a
comprehensive-ish list of changes:

> Important: Re-checked 2026-09-09. Everything below describes the state of the tree at the time of
> PR #513, and the per-backend conformance list further down had drifted badly since. The rows that
> were wrong are struck through and corrected in place rather than deleted, because the shape of the
> error is the useful part: every stale row said a backend *lacked* a feature, and in every case the
> feature had since landed. A claim of absence is the one that ages worst, because implementing the
> thing does not make anyone reopen the document that said it was missing.

- The `AppBackend` protocol has been split up into ~~three dozen or so~~ smaller protocols, all
  organized within a ``BackendFeatures`` namespace enum.
  - Corrected 2026-09-09: it is **59** protocols now, plus 8 grouping typealiases, so "nearly five
    dozen" rather than three. Regenerate with
    `grep -rhoE "public protocol [A-Za-z]+" Sources/SwiftCrossUI/Backend/BackendFeatures/ Sources/SwiftCrossUI/Backend/BackendFeatures.swift | sort -u | wc -l`
    and
    `grep -rhoE "public typealias [A-Za-z]+" Sources/SwiftCrossUI/Backend/BackendFeatures/ | sort -u | wc -l`.
  - There are three core, "top-level" protocols (actually typealiases for protocol compositions)
    that backend developers need to worry about:
    - ``BackendFeatures/Core`` contains the bare minimum needed for a SCUI app to launch without
      crashing immediately. (This one's a true `protocol`, not a typealias.)
    - ``BaseAppBackend`` extends `Core` with most UI controls, containers, and noninteractive views.
      This is the protocol that the ``App/Backend`` associated type requires.
    - ``FullAppBackend`` contains everything the original protocol had, including all of `Base` as
      well as URL handling, revealing files, the global menu, file dialogs, alerts, sheets, corner
      radii, web views, tables, gestures, menus, paths, colors, tooltips, date pickers, and some
      windowing functionality.
      - Added 2026-09-09: the composition has since grown three more members that this sentence
        never mentioned -- ``BackendFeatures/Popovers``, ``BackendFeatures/Gradients`` and
        ``BackendFeatures/ButtonPressState``. See the typealias itself in
        `Sources/SwiftCrossUI/Backend/FullAppBackend.swift`, which also carries a long note about
        why adding a member here does *not* make the other four backends conform.
      - All of these features are now **optional** for backends to implement.
      - For ``BackendFeatures/RevealFiles``, the `canRevealFiles` property has been removed in favor
        of simply not conforming to the protocol if revealing files isn't supported.
  - All of the protocols below these are described in the doc comments for the new wrapper types and
    grouping typealiases.
- Code in the SwiftCrossUI target has been updated to use `BaseAppBackend` instead of just
  `AppBackend`. Backend instances are dynamically casted to additional protocols as needed.
  - A new internal macro, `CastBackend`, was added to simplify the task of casting backends. It has
    the following signature:

    ```swift
    @attached(body)
    internal macro CastBackend<NewBackend>(
        backendGenericName: String? = nil,
        returnsWidget: Bool = false
    )
    ```

    It currently only works correctly within implementations of `View` methods, but since that's
    where most of the boilerplate resides, this macro should still be a huge help.
- The backends themselves have been updated for the new organization. Here are the backend protocols
  each backend conforms to:
  - ``BaseAppBackend``: all backends
    - ~~`BackendFeatures/Toggles` is stubbed for UIKitBackend on all platforms;~~
      ``BackendFeatures/Sliders`` is stubbed for UIKitBackend on tvOS.

      Corrected 2026-09-09: there is no `Toggles` protocol, and there is no evidence in the tree
      that there ever was one under that name after the split. What exists is three separate
      protocols -- ``BackendFeatures/ToggleButtons``, ``BackendFeatures/Switches`` and
      ``BackendFeatures/Checkboxes`` -- all three of which are members of the
      ``BackendFeatures/Controls`` composition
      (`Sources/SwiftCrossUI/Backend/BackendFeatures/Controls/Controls.swift:18`). Since `Controls`
      is part of ``BaseAppBackend``, every backend conforms to all three.

      The struck-through reference above has been demoted from a DocC link to a plain code span on
      purpose. Left in double-backtick form it would be an unresolvable link, and DocC would warn on
      every docs build from now on for a name we already know is wrong -- noise attached to a
      question that is already answered. It is worth knowing why the original went unnoticed for
      so long, though: this catalog is built without `--warnings-as-errors`, so an unresolvable
      symbol link never failed anything. It rendered as ordinary text, and a reader had no way to
      distinguish "this protocol exists and DocC linked it" from "this protocol does not exist".
  - ~~``BackendFeatures/ApplicationMenus``: all backends except UIKitBackend (except for Mac Catalyst
    where it _is_ implemented)~~ -- corrected 2026-09-09 to: AppKitBackend, GtkBackend, WinUIBackend
    and UIKitBackend. UIKitBackend now conforms outright
    (`Sources/UIKitBackend/UIKitBackend+Menu.swift:137`), so the Catalyst carve-out no longer
    applies. AndroidBackend does *not* conform.
  - ~~``BackendFeatures/ExternalURLs``: all backends~~ -- corrected 2026-09-09 to: all backends
    except AndroidBackend. The row was written before AndroidBackend existed, which is the other way
    a "all backends" claim goes stale: not because a feature was removed, but because the set of
    backends grew underneath it.
  - ~~``BackendFeatures/IncomingURLs``: all backends~~ -- corrected 2026-09-09 to: all backends
    except AndroidBackend, for the same reason as `ExternalURLs` above.
  - ~~``BackendFeatures/RevealFiles``: all backends except UIKitBackend and WinUIBackend~~ --
    corrected 2026-09-09 to: AppKitBackend, GtkBackend and WinUIBackend. WinUIBackend gained it on
    2026-09-02 (`Sources/WinUIBackend/WinUIBackend+RevealFiles.swift:4`); UIKitBackend and
    AndroidBackend still lack it.
  - ``BackendFeatures/FileOpenDialogs``: all backends except UIKitBackend on tvOS
  - ~~``BackendFeatures/FileSaveDialogs``: all backends except UIKitBackend~~ -- corrected
    2026-09-09 to: all backends except UIKitBackend and AndroidBackend. Both of those declare only
    `FileOpenDialogs`; the ``BackendFeatures/FileDialogs`` typealias that the other three use is
    `FileOpenDialogs & FileSaveDialogs`
    (`Sources/SwiftCrossUI/Backend/BackendFeatures/FileDialogs/FileDialogs.swift:3`).
  - ``BackendFeatures/Alerts``: all backends
  - ~~``BackendFeatures/Sheets``: all backends except WinUIBackend and Gtk3Backend~~ -- corrected
    2026-09-09 to: **all five backends**. WinUIBackend gained sheets on 2026-09-08
    (`Sources/WinUIBackend/WinUIBackend+Sheets.swift:10`) and AndroidBackend has them too
    (`Sources/AndroidBackend/AndroidBackend+Sheets.swift:4`). There is also no `Gtk3Backend`
    anywhere in `Sources/`; the only surviving Gtk backend is the Gtk 4 one.
  - ~~``BackendFeatures/CornerRadius``: all backends (but janky on Gtk3Backend)~~ -- the claim
    itself still holds for all five backends, but the parenthetical was corrected 2026-09-09: there
    is no `Gtk3Backend` target in `Sources/`, so the caveat describes a backend that no longer
    exists.
  - ~~``BackendFeatures/WebViews``: AppKitBackend and UIKitBackend only~~ -- corrected 2026-09-09
    to: **all five backends**. This is the single most misleading row in the original list, because
    "Apple platforms only" got copied out of here into <doc:Examples> and into the project's issue
    tracking. GtkBackend gained a real WebKitGTK-backed implementation on 2026-09-04
    (`Sources/GtkBackend/GtkBackend+WebView.swift`, 131 lines), WinUIBackend on
    `Sources/WinUIBackend/WinUIBackend+WebView.swift:6` (108 lines), and AndroidBackend on
    `Sources/AndroidBackend/AndroidBackend+WebViews.swift:5`.
  - ~~``BackendFeatures/Tables``: AppKitBackend only~~ -- corrected 2026-09-09 to: **all five
    backends**. GtkBackend declares it on its class (`Sources/GtkBackend/GtkBackend.swift:37`),
    WinUIBackend at `Sources/WinUIBackend/WinUIBackend+Tables.swift:13`, UIKitBackend at
    `Sources/UIKitBackend/UIKitBackend+Tables.swift:133`, and AndroidBackend at
    `Sources/AndroidBackend/AndroidBackend+Tables.swift:24`.
  - ``BackendFeatures/TapGestures``: all backends
  - ``BackendFeatures/HoverGestures``: all backends except UIKitBackend on tvOS
  - ``BackendFeatures/MenuButtons``: all backends except UIKitBackend before iOS 14 / Mac Catalyst 14 / tvOS 17
    - Still true as of 2026-09-09, but only indirectly, and it is worth writing down how: no backend
      names `MenuButtons` in a conformance clause any more. They get it by refinement, because both
      ``BackendFeatures/AttachedMenus`` and ``BackendFeatures/PopoverMenus`` inherit from it
      (`Sources/SwiftCrossUI/Backend/BackendFeatures/Menus.swift:9`, `:48`, `:69`). A grep for
      `MenuButtons` across the backend targets returns nothing, which looks exactly like the feature
      having been dropped.
  - ``BackendFeatures/Paths``: all backends
  - ``BackendFeatures/Tooltips``: all backends
  - ``BackendFeatures/Colors``: all backends
  - ~~``BackendFeatures/DatePickers``: all backends except Gtk3Backend, and UIKitBackend on tvOS~~ --
    corrected 2026-09-09: the `Gtk3Backend` exclusion names a target that does not exist. All five
    current backends conform; the tvOS carve-out for UIKitBackend stands.
  - ``BackendFeatures/WindowClosing``: all backends except UIKitBackend
    - Still true as of 2026-09-09, with AndroidBackend added to the exclusion: it declares neither
      `WindowClosing` nor the ``BackendFeatures/Windowing`` typealias that supplies it.
  - ~~``BackendFeatures/WindowBehaviors``: all backends~~ -- corrected 2026-09-09 to: all backends
    except AndroidBackend. UIKitBackend does conform
    (`Sources/UIKitBackend/UIKitBackend+Window.swift:256`).

- Note: The list above was re-measured on 2026-09-09 against the five shipped backends. To regenerate
  it, note that conformances are declared in two different places and a grep for only one of them
  will silently under-report: AppKitBackend gets most of its features from the ``FullAppBackend``
  composition on its class declaration (`Sources/AppKitBackend/AppKitBackend.swift:22`), GtkBackend,
  WinUIBackend and UIKitBackend list theirs individually on their class declarations
  (`GtkBackend.swift:24`, `WinUIBackend.swift:108`, `UIKitBackend.swift:15`), and AndroidBackend
  declares ``BaseAppBackend`` on its class (`AndroidBackend.swift:134`) and everything else as
  separate `extension AndroidBackend: BackendFeatures.X` files. So both
  `grep -rhoE "extension \w+Backend: BackendFeatures\.[A-Za-z]+" Sources/` and a read of the five
  class declarations are needed.

## Random Extras
A fun side effect of all this that stackotter noticed is that people can now implement missing
backend features _in user code_ -- ~~e.g. if someone needs sheets in WinUI, they could simply
declare `extension WinUIBackend: BackendFeatures.Sheets` in their app.~~

The mechanism still works; only the example has expired. Corrected 2026-09-09: sheets in WinUI are
no longer missing, and the line of code offered here as something a user might write in their own
app is now literally in the repository, at
`Sources/WinUIBackend/WinUIBackend+Sheets.swift:10`, as of 2026-09-08. Written out in user code
today it would be a duplicate conformance and would not compile. Pick a feature that a backend
genuinely lacks if you need a live example -- as of this re-check, `RevealFiles` on UIKitBackend or
AndroidBackend would do.

Of course, we'd want to encourage people to upstream such code into the main project, but this is
still a useful thing for people to be able to do. It'd also slightly reduce the (admittedly not
large at all) barrier to entry for contributing to SCUI as well as third-party backend projects.
