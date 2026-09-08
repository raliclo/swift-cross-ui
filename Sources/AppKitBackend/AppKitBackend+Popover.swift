import AppKit
@_spi(Backends) import SwiftCrossUI

/// `.popover` for macOS, built on `NSPopover`.
///
/// `NSPopover` rather than a borderless `NSWindow`. A popover on macOS has a
/// beak that points at its anchor, a vibrant background, and a transient
/// behaviour that closes it on the next click anywhere else -- all three come
/// with `NSPopover` and none of them come with a window. `show(relativeTo:of:preferredEdge:)`
/// also takes the anchor view directly, which is the parameter
/// ``BackendFeatures/Popovers`` exists to carry.
///
/// Note that this is a different mechanism from `AppKitBackend+Menus.swift`,
/// which uses `NSMenu.popUp(positioning:at:in:)`. An `NSMenu` holds
/// `NSMenuItem`s and cannot hold an `NSView` hierarchy, so it could not have
/// been reused here.
///
/// 為 macOS 實作的 `.popover`，建構於 `NSPopover` 之上。
///
/// 選 `NSPopover` 而非無邊框的 `NSWindow`。macOS 上的 popover 有指向錨點的尖角、帶有材質感的背景，
/// 以及「下一次在別處點擊即關閉」的 transient 行為——這三者都隨 `NSPopover` 而來，也都不隨視窗而來。
/// `show(relativeTo:of:preferredEdge:)` 同樣直接接受錨點 view，而那正是
/// ``BackendFeatures/Popovers`` 之所以存在所要承載的參數。
///
/// 請注意這與 `AppKitBackend+Menus.swift` 是不同的機制，後者使用
/// `NSMenu.popUp(positioning:at:in:)`。`NSMenu` 裝的是 `NSMenuItem`，無法裝載 `NSView` 階層，
/// 因此無法在此重複使用。
extension AppKitBackend: BackendFeatures.Popovers {
    public func createPopover(content: NSView) -> NSCustomPopover {
        NSCustomPopover(content: content)
    }

    public func updatePopover(
        _ popover: NSCustomPopover,
        environment: EnvironmentValues,
        size: SIMD2<Int>,
        attachmentEdge: Edge,
        backgroundColor: SwiftCrossUI.Color.Resolved?,
        onDismiss: @escaping () -> Void
    ) {
        popover.onDismiss = onDismiss
        popover.contentSize = NSSize(width: size.x, height: size.y)
        popover.appearance = environment.colorScheme.nsAppearance

        // `preferredEdge` is read in the anchor view's own coordinate space, and
        // the backend's container views are not flipped -- `isFlipped` is
        // overridden only by the two gradient views in
        // `AppKitBackend+Gradient.swift`, and positions are expressed through
        // `topAnchor` constraints rather than through frames. So `minY` really
        // is the bottom of the anchor on screen.
        //
        // A popover placed with `preferredEdge` still flips itself when the
        // requested side would leave the screen; that is `NSPopover`'s own
        // behaviour and it is the wanted one.
        //
        // `preferredEdge` 是在錨點 view 自身的座標空間中解讀的，而本 backend 的容器 view 並未翻轉
        // ——`isFlipped` 只在 `AppKitBackend+Gradient.swift` 的兩個漸層 view 中被覆寫，且位置是透過
        // `topAnchor` 約束而非透過 frame 表達。因此 `minY` 確實就是錨點在螢幕上的下緣。
        //
        // 以 `preferredEdge` 擺放的 popover，在所請求的一側會超出螢幕時仍會自行翻轉；那是
        // `NSPopover` 自身的行為，也正是我們要的行為。
        popover.preferredEdge = switch attachmentEdge {
            case .top: .maxY
            case .bottom: .minY
            case .leading: .minX
            case .trailing: .maxX
        }

        popover.backgroundView.layer?.backgroundColor = backgroundColor?.nsColor.cgColor
    }

    public func showPopover(
        _ popover: NSCustomPopover,
        relativeTo widget: NSView,
        window: NSCustomWindow
    ) {
        popover.show(
            relativeTo: widget.bounds,
            of: widget,
            preferredEdge: popover.preferredEdge
        )
    }

    public func dismissPopover(_ popover: NSCustomPopover) {
        popover.isProgrammaticDismissal = true
        // `close()` rather than `performClose(_:)`. The latter is documented as
        // behaving "as if the user had closed it", which routes through
        // `popoverShouldClose(_:)` and is exactly the meaning this call does not
        // have -- the binding has already decided.
        // 使用 `close()` 而非 `performClose(_:)`。後者的文件說明是「彷彿使用者關閉了它」，會經過
        // `popoverShouldClose(_:)`，而那正是此次呼叫**不**具有的語意——binding 早已做出決定。
        popover.close()
    }
}

/// An `NSPopover` that remembers the three things `NSPopover` does not.
///
/// - Its content's background view, so a `presentationBackground` has somewhere
///   to land. `NSPopover` styles its own frame and offers no background colour.
/// - The edge it was configured with, so `showPopover` and `updatePopover` agree
///   without the backend holding a side table.
/// - Whether the close in flight was programmatic. `popoverDidClose(_:)` fires
///   for both, and the ``BackendFeatures/Popovers`` contract says `onDismiss` is
///   for user-driven dismissals only.
///
/// 一個會記住三件 `NSPopover` 不記得之事的 `NSPopover`。
///
/// - 其內容的背景 view，讓 `presentationBackground` 有地方可落。`NSPopover` 只為自己的外框設定樣式，
///   並未提供背景顏色。
/// - 它被設定的那個邊，使 `showPopover` 與 `updatePopover` 無需 backend 另外維護一張對照表即可一致。
/// - 進行中的這次關閉是否為程式所觸發。`popoverDidClose(_:)` 在兩種情況下都會觸發，而
///   ``BackendFeatures/Popovers`` 的約定是 `onDismiss` 只對應使用者主動的關閉。
public final class NSCustomPopover: NSPopover, NSPopoverDelegate {
    public var onDismiss: (() -> Void)?
    public var isProgrammaticDismissal = false
    public let backgroundView: NSView
    var preferredEdge: NSRectEdge = .minY

    init(content: NSView) {
        backgroundView = NSView()
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.wantsLayer = true

        let contentView = NSView()
        contentView.addSubview(backgroundView)
        contentView.addSubview(content)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: content.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            contentView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            contentView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: backgroundView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            contentView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),
            contentView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
        ])

        let controller = NSViewController()
        controller.view = contentView

        super.init()

        contentViewController = controller
        // Light dismiss, which is what a popover is. `.applicationDefined` would
        // leave it open until something closed it, and the modifier's binding is
        // not something the user can reach from inside a popover they cannot
        // click out of.
        // 點擊外部即關閉，那正是 popover 的定義。`.applicationDefined` 會讓它一直開著直到有東西關閉
        // 它，而使用者從一個無法點擊外部離開的 popover 之內，是搆不到該 modifier 的 binding 的。
        behavior = .transient
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used for this popover")
    }

    public func popoverDidClose(_ notification: Notification) {
        let wasProgrammatic = isProgrammaticDismissal
        isProgrammaticDismissal = false
        guard !wasProgrammatic else { return }
        onDismiss?()
    }
}
