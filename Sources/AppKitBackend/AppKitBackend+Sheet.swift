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
        background.layer?.backgroundColor = backgroundColor?.nsColor.cgColor
        sheet.interactiveDismissDisabled = interactiveDismissDisabled

        // - dragIndicatorVisibility is only for mobile so we ignore it
        // - detents are only for mobile so we ignore them
        // - cornerRadius isn't supported by macOS so we ignore it
    }

    public func size(ofSheet sheet: NSCustomSheet) -> SIMD2<Int> {
        guard let size = sheet.contentView?.frame.size else {
            return SIMD2(x: 0, y: 0)
        }
        return SIMD2(x: Int(size.width), y: Int(size.height))
    }

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
    /// closed by `isPresented = false` notifies too. Until 2026-10-20 only the
    /// nested children of a dismissed sheet were told, so a nested-sheet test
    /// passed while the sheet actually dismissed stayed silent (todo.md, "Six
    /// divergences", item 1). Each sheet now runs its own `onDismiss` once, after
    /// it has left the screen; the recursion reaches the children.
    /// `onDismiss` 在這裡與按 Escape 時都會執行，與 SwiftUI 相同：以 `isPresented = false` 關閉的 sheet 也會通知。
    /// 2026-10-20 之前只有被關閉之 sheet 的巢狀子 sheet 會收到通知，所以巢狀測試會通過，而真正被關閉的那個 sheet
    /// 什麼都沒說(todo.md「六項分歧」第 1 項)。現在每個 sheet 在離開畫面後執行自己的 `onDismiss` 一次;遞迴會走到子 sheet。
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
