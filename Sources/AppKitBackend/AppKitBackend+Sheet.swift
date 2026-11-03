import AppKit
@_spi(Backends) import SwiftCrossUI

extension AppKitBackend {
    public typealias Sheet = NSCustomSheet

    public func createSheet(content: NSView) -> NSCustomSheet {
        // Initialize with a default contentRect, similar to `createWindow`
        let sheet = NSCustomSheet(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: 400,
                height: 400
            ),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )

        let backgroundView = NSView()
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
        contentView.translatesAutoresizingMaskIntoConstraints = false

        sheet.contentView = contentView
        sheet.backgroundView = backgroundView

        return sheet
    }

    public func updateSheet(
        _ sheet: NSCustomSheet,
        window: NSCustomWindow,
        environment: EnvironmentValues,
        size: SIMD2<Int>,
        onDismiss: @escaping () -> Void,
        cornerRadius: Double?,
        detents: [PresentationDetent],
        dragIndicatorVisibility: Visibility,
        backgroundColor: Color.Resolved?,
        interactiveDismissDisabled: Bool
    ) {
        sheet.setContentSize(NSSize(width: size.x, height: size.y))
        sheet.onDismiss = onDismiss

        let background = sheet.backgroundView!
        sheet.interactiveDismissDisabled = interactiveDismissDisabled

        // Corner radius: the content view's layer is rounded and clipped, and
        // the window behind it made clear and non-opaque so the cut corners show
        // what is under the sheet rather than the window's own background. The
        // background view then carries the colour (the window background when
        // none is asked for), since the window no longer draws one.
        // 圓角：content view 的 layer 設圓角並裁切，其後的視窗設為透明、非不透明，讓被切掉的角露出
        // sheet 底下的東西，而不是視窗自己的背景。背景色改由 background view 負責(未指定時用視窗背景色),
        // 因為視窗不再畫背景。
        if let cornerRadius, cornerRadius > 0 {
            sheet.isOpaque = false
            sheet.backgroundColor = .clear
            sheet.contentView?.wantsLayer = true
            sheet.contentView?.layer?.cornerRadius = CGFloat(cornerRadius)
            sheet.contentView?.layer?.masksToBounds = true
            background.layer?.backgroundColor =
                (backgroundColor?.nsColor ?? .windowBackgroundColor).cgColor
        } else {
            sheet.isOpaque = true
            sheet.backgroundColor = .windowBackgroundColor
            sheet.contentView?.layer?.cornerRadius = 0
            sheet.contentView?.layer?.masksToBounds = false
            background.layer?.backgroundColor = backgroundColor?.nsColor.cgColor
        }
        sheet.invalidateShadow()

        // Detents and the drag indicator are not dropped for convenience: AppKit
        // has no API for either. A sheet is attached with `beginSheet(_:)` at its
        // content size and moves only with its parent; the macOS 27.2 SDK's
        // AppKit headers contain no detent or grabber API for NSWindow sheets
        // (`grep -ri detent` over them finds no sheet API). The one detent a
        // sheet can honour, filling the window, is honoured by SheetModifier,
        // which lays the content out at the window's size before this call.
        // detents 與拖曳指示器並不是為了方便而丟掉:AppKit 兩者都沒有 API。sheet 以 `beginSheet(_:)`
        // 依其內容尺寸附著，只跟著父視窗移動；macOS 27.2 SDK 的 AppKit 標頭裡沒有給 NSWindow sheet 用的
        // detent 或 grabber API(對其 `grep -ri detent` 找不到任何 sheet API)。sheet 能遵守的那一個
        // detent——填滿視窗——由 SheetModifier 遵守，它在這次呼叫之前就以視窗尺寸排版內容。
    }

    public func size(ofSheet sheet: NSCustomSheet) -> SIMD2<Int> {
        guard let size = sheet.contentView?.frame.size else {
            return SIMD2(x: 0, y: 0)
        }
        return SIMD2(x: Int(size.width), y: Int(size.height))
    }

    /// Nothing to lift: an AppKit sheet is exactly the size `updateSheet` gives
    /// it, and a cover is given its window's, so it already covers the window
    /// (P49, p49-macos-final-20261020-225609.png).
    /// 沒有限制可拿掉:AppKit 的 sheet 就是 `updateSheet` 給它的大小，而 cover 拿到的是視窗的大小，所以本來就覆蓋視窗
    /// (P49,p49-macos-final-20261020-225609.png)。
    public func setPresentationFillsWindow(of sheet: NSCustomSheet, window: Window, _ fillsWindow: Bool) {}

    public func presentSheet(_ sheet: NSCustomSheet, window: Window, parentSheet: Sheet?) {
        let parent = parentSheet ?? window
        // beginSheet and beginCriticalSheet should be equivalent here, because we
        // directly present the sheet on top of the top-most sheet. If we were to
        // instead present sheets on top of the root window every time, then
        // beginCriticalSheet would produce the desired behaviour and beginSheet
        // would wait for the parent sheet to finish before presenting the nested sheet.
        parent.beginSheet(sheet)
        parent.nestedSheet = sheet
    }

    /// `onDismiss` runs here as well as on Escape, as in SwiftUI: a sheet
    /// closed by `isPresented = false` notifies too. Each sheet runs its own
    /// `onDismiss` once, after it has left the screen; the recursion reaches the
    /// children. Notifying only the nested children would let a nested-sheet
    /// test pass while the sheet actually dismissed stayed silent.
    /// `onDismiss` 在這裡與按 Escape 時都會執行，與 SwiftUI 相同：以 `isPresented = false` 關閉的 sheet 也會通知。
    /// 每個 sheet 在離開畫面後執行自己的 `onDismiss` 一次;遞迴會走到子 sheet。若只通知巢狀子 sheet,巢狀測試會通過,
    /// 而真正被關閉的那個 sheet 什麼都不說。
    public func dismissSheet(_ sheet: NSCustomSheet, window: Window, parentSheet: Sheet?) {
        let parent = parentSheet ?? window

        // Dismiss nested sheets first
        if let nestedSheet = sheet.nestedSheet {
            dismissSheet(nestedSheet, window: window, parentSheet: sheet)
        }

        parent.endSheet(sheet)
        parent.nestedSheet = nil
        sheet.notifyDismissedOnce()
    }
}

public final class NSCustomSheet: NSCustomWindow, NSWindowDelegate {
    public var onDismiss: (() -> Void)?

    public var interactiveDismissDisabled: Bool = false

    public var backgroundView: NSView?

    /// Set once `onDismiss` has run, so Escape followed by a parent's
    /// programmatic dismissal cannot run it twice.
    /// `onDismiss` 執行過後設定，讓「先按 Escape、之後父 sheet 以程式關閉」不會執行它兩次。
    private var hasNotifiedDismissal = false

    func notifyDismissedOnce() {
        guard !hasNotifiedDismissal else { return }
        hasNotifiedDismissal = true
        onDismiss?()
    }

    @objc override public func cancelOperation(_ sender: Any?) {
        if !interactiveDismissDisabled {
            let parent = sheetParent
            parent?.endSheet(self)
            if let parent = parent as? NSCustomWindow, parent.nestedSheet === self {
                parent.nestedSheet = nil
            }
            notifyDismissedOnce()
        }
    }
}
