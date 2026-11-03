import AppKit
@_spi(Backends) import SwiftCrossUI

extension AppKitBackend {
    public func createTapGestureTarget(wrapping child: Widget, gesture _: TapGesture) -> Widget {
        let container = NSView()

        container.addSubview(child)
        child.leadingAnchor.constraint(equalTo: container.leadingAnchor)
            .isActive = true
        child.topAnchor.constraint(equalTo: container.topAnchor)
            .isActive = true
        child.translatesAutoresizingMaskIntoConstraints = false

        let tapGestureTarget = NSCustomTapGestureTarget()
        container.addSubview(tapGestureTarget)
        tapGestureTarget.leadingAnchor.constraint(equalTo: container.leadingAnchor)
            .isActive = true
        tapGestureTarget.topAnchor.constraint(equalTo: container.topAnchor)
            .isActive = true
        tapGestureTarget.trailingAnchor.constraint(equalTo: container.trailingAnchor)
            .isActive = true
        tapGestureTarget.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            .isActive = true
        tapGestureTarget.translatesAutoresizingMaskIntoConstraints = false

        return container
    }

    public func updateTapGestureTarget(
        _ container: Widget,
        gesture: TapGesture,
        environment: EnvironmentValues,
        action: @escaping () -> Void
    ) {
        let tapGestureTarget = container.subviews[1] as! NSCustomTapGestureTarget
        switch (gesture.kind, environment.isEnabled) {
            case (_, false):
                tapGestureTarget.leftClickHandler = nil
                tapGestureTarget.rightClickHandler = nil
                tapGestureTarget.longPressHandler = nil
            case (.primary, true):
                tapGestureTarget.leftClickHandler = action
                tapGestureTarget.rightClickHandler = nil
                tapGestureTarget.longPressHandler = nil
            case (.secondary, true):
                tapGestureTarget.leftClickHandler = nil
                tapGestureTarget.rightClickHandler = action
                tapGestureTarget.longPressHandler = nil
            case (.longPress, true):
                tapGestureTarget.leftClickHandler = nil
                tapGestureTarget.rightClickHandler = nil
                tapGestureTarget.longPressHandler = action
        }
    }

    public func createHoverTarget(wrapping child: Widget) -> Widget {
        let container = NSView()

        container.addSubview(child)
        child.leadingAnchor.constraint(equalTo: container.leadingAnchor)
            .isActive = true
        child.topAnchor.constraint(equalTo: container.topAnchor)
            .isActive = true
        child.translatesAutoresizingMaskIntoConstraints = false

        let hoverGestureTarget = NSCustomHoverTarget()
        container.addSubview(hoverGestureTarget)
        hoverGestureTarget.leadingAnchor.constraint(equalTo: container.leadingAnchor)
            .isActive = true
        hoverGestureTarget.topAnchor.constraint(equalTo: container.topAnchor)
            .isActive = true
        hoverGestureTarget.trailingAnchor.constraint(equalTo: container.trailingAnchor)
            .isActive = true
        hoverGestureTarget.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            .isActive = true
        hoverGestureTarget.translatesAutoresizingMaskIntoConstraints = false

        return container
    }

    public func updateHoverTarget(
        _ container: Widget,
        environment: EnvironmentValues,
        action: @escaping (Bool) -> Void
    ) {
        let hoverGestureTarget = container.subviews[1] as! NSCustomHoverTarget
        hoverGestureTarget.hoverChangesHandler = action
    }
}

final class NSCustomTapGestureTarget: NSView, NSGestureRecognizerDelegate {
    var leftClickHandler: (() -> Void)? {
        didSet {
            if leftClickHandler != nil && leftClickRecognizer == nil {
                let gestureRecognizer = NSClickGestureRecognizer(
                    target: self,
                    action: #selector(leftClick)
                )
                addGestureRecognizer(gestureRecognizer)
                gestureRecognizer.delegate = self
                leftClickRecognizer = gestureRecognizer
            } else if leftClickHandler == nil, let leftClickRecognizer {
                removeGestureRecognizer(leftClickRecognizer)
                self.leftClickRecognizer = nil
            }
        }
    }

    var rightClickHandler: (() -> Void)? {
        didSet {
            if rightClickHandler != nil && rightClickRecognizer == nil {
                let gestureRecognizer = NSClickGestureRecognizer(
                    target: self,
                    action: #selector(rightClick)
                )
                gestureRecognizer.buttonMask = 1 << 1
                addGestureRecognizer(gestureRecognizer)
                rightClickRecognizer = gestureRecognizer
            } else if rightClickHandler == nil, let rightClickRecognizer {
                removeGestureRecognizer(rightClickRecognizer)
                self.rightClickRecognizer = nil
            }
        }
    }

    var longPressHandler: (() -> Void)? {
        didSet {
            if longPressHandler != nil && longPressRecognizer == nil {
                let gestureRecognizer = NSPressGestureRecognizer(
                    target: self,
                    action: #selector(longPress)
                )
                // Both GTK and UIKit default to half a second for long presses
                gestureRecognizer.minimumPressDuration = 0.5
                addGestureRecognizer(gestureRecognizer)
                longPressRecognizer = gestureRecognizer
            } else if longPressHandler == nil, let longPressRecognizer {
                removeGestureRecognizer(longPressRecognizer)
                self.longPressRecognizer = nil
            }
        }
    }

    var leftClickRecognizer: NSClickGestureRecognizer?
    private var rightClickRecognizer: NSClickGestureRecognizer?
    var longPressRecognizer: NSPressGestureRecognizer?

    @objc
    func leftClick() {
        leftClickHandler?()
    }

    @objc
    func rightClick() {
        rightClickHandler?()
    }

    @objc
    func longPress(sender: NSPressGestureRecognizer) {
        // GTK emits the event once as soon as the gesture is recognized.
        // AppKit reports `.began`, then `.changed` for every mouse move while
        // held, then `.ended`. Only `.began` is the long press; reacting to the
        // other states would report a wandering press several times.
        // GTK 在辨識成立時發出一次。AppKit 先報 `.began`,按住移動時每次報 `.changed`,最後 `.ended`。
        // 只有 `.began` 才是長按;對其他狀態也有反應,按住時移動就會回報好幾次。
        if sender.state == .began {
            longPressHandler?()
        }
    }

    // What counts as having something of its own to click. A label is an
    // NSTextField and an image is an NSImageView, both NSControls, yet neither
    // reacts to a click unless it is editable or selectable, so `onTapGesture`
    // on Text or Image still fires.
    // 何謂「自己有可點之物」。標籤是 NSTextField、圖片是 NSImageView,兩者都是 NSControl,但除非可編輯
    // 或可選取，否則都不會回應點擊，所以 Text 或 Image 上的 `onTapGesture` 仍會觸發。
    static func takesOwnClicks(_ view: NSView) -> Bool {
        if !view.gestureRecognizers.isEmpty {
            return true
        }
        switch view {
            case let field as NSTextField:
                return field.isEditable || field.isSelectable
            case let image as NSImageView:
                return image.isEditable
            case let text as NSTextView:
                return text.isEditable || text.isSelectable
            case let control as NSControl:
                return control.isEnabled
            default:
                return false
        }
    }

    // The overlay takes a click only where the wrapped child has nothing of
    // its own to click. Where the child under the pointer is a control, a text
    // view or a view with its own recognisers (a nested tap target), nil sends
    // the click on to it, as SwiftUI lets an inner Button win over an outer
    // `onTapGesture`. With no handler at all (disabled) nothing is taken.
    // 這層覆蓋 view 只在被包住的子 view 自己沒有可點之物的地方接下點擊。指標下方的子 view 若是控制項、
    // 文字 view 或帶有自己辨識器的 view(巢狀的 tap target),回傳 nil 讓點擊交給它，與 SwiftUI 讓
    // 內層 Button 勝過外層 `onTapGesture` 相同。完全沒有 handler(停用)時則什麼都不接。
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !gestureRecognizers.isEmpty, let hit = super.hitTest(point) else {
            return nil
        }
        guard let superview,
            let child = superview.subviews.first(where: { $0 !== self }),
            var below = child.hitTest(point)
        else {
            return hit
        }
        while true {
            if Self.takesOwnClicks(below) {
                return nil
            }
            guard below !== child, let parent = below.superview else { break }
            below = parent
        }
        return hit
    }

    // With both a click and a long-press handler (onTapAndLongPressGesture),
    // the click waits for the press recogniser to fail: released before
    // 0.5 s, the press fails and the click fires at once; held, the press
    // wins and the click never does. A long press is then not also a tap.
    // 同時有點擊與長按 handler 時(onTapAndLongPressGesture),點擊要等長按辨識器失敗:0.5 秒內放開，長按
    // 失敗、點擊立即觸發;按住不放則長按勝出、點擊永不觸發。長按因此不會同時算成點按。
    func gestureRecognizer(
        _ gestureRecognizer: NSGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: NSGestureRecognizer
    ) -> Bool {
        gestureRecognizer === leftClickRecognizer && otherGestureRecognizer === longPressRecognizer
    }
}

final class NSCustomHoverTarget: NSView {
    var hoverChangesHandler: ((Bool) -> Void)? {
        didSet {
            if hoverChangesHandler != nil && trackingArea == nil {
                setNewTrackingArea()
            } else if hoverChangesHandler == nil, let trackingArea {
                removeTrackingArea(trackingArea)
                self.trackingArea = nil
            }
        }
    }

    private var trackingArea: NSTrackingArea?

    // Hover is geometry, not hit testing: the tracking area reports entry and
    // exit whatever `hitTest` answers. Returning nil keeps this overlay out of
    // the click path, so a button or text field inside `onHover` gets its
    // clicks instead of this empty view swallowing them.
    // 懸停看的是幾何範圍，不是點擊測試：不論 `hitTest` 回答什麼，tracking area 都會回報進入與離開。
    // 回傳 nil 讓這層覆蓋 view 不在點擊路徑上，因此 `onHover` 裡的按鈕或文字欄位能收到點擊，
    // 而不是被這個空的 view 吞掉。
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            self.removeTrackingArea(trackingArea)
        }
        setNewTrackingArea()
    }

    override func mouseEntered(with event: NSEvent) {
        hoverChangesHandler?(true)
    }

    override func mouseExited(with event: NSEvent) {
        hoverChangesHandler?(false)
    }

    private func setNewTrackingArea() {
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .activeInKeyWindow,
        ]
        let area = NSTrackingArea(
            rect: self.bounds,
            options: options,
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }
}
