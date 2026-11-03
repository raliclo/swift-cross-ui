@_spi(Backends) import SwiftCrossUI
import UWP
import WinUI
import WindowsFoundation
import CWinRT
import WinSDK

// swiftlint:disable force_try

extension WinUIBackend: BackendFeatures.Sheets {
    /// A `ContentDialog` plus the bookkeeping WinUI does not do for us.
    ///
    /// There is deliberately no flag recording whether a dismissal was
    /// programmatic: SwiftUI runs `onDismiss:` when the presentation ends
    /// however it ended, so `sheet(isPresented:onDismiss:)` fires on both
    /// paths (the same rule as `Popover`, `6ec976b2`). `isHidingByCode` is not
    /// that flag: it only lets this backend's own hides past the
    /// `interactiveDismissDisabled` veto, and `onDismiss` ignores it.
    ///
    /// 一個 `ContentDialog`，外加 WinUI 不會替我們做的記帳工作。
    ///
    /// 刻意不設旗標記錄某次關閉是否為程式發起：無論 presentation 以何種方式結束,SwiftUI 都會執行
    /// `onDismiss:`,因此 `sheet(isPresented:onDismiss:)` 在兩條路上都會觸發(與 `Popover` 相同的規則,
    /// `6ec976b2`)。`isHidingByCode` 不是那種旗標：它只讓本 backend 自己的隱藏通過
    /// `interactiveDismissDisabled` 的否決,`onDismiss` 不看它。
    public class Sheet: ContentDialog {
        var dismissHandler: (() -> Void)?
        /// What Back does while this sheet is up, set by
        /// `setBackNavigationHandler(ofSheet:to:)`. 此 sheet 開著時返回所做的事。
        var backNavigationHandler: (@MainActor () -> Bool)?
        var nestedSheet: Sheet?
        weak var parentSheet: Sheet?
        weak var window: Window?
        var isSuspendedForNestedSheet = false
        var pendingNestedPresentation: Sheet?
        /// Whether a `showAsync` promise is outstanding for this sheet.
        ///
        /// It is what tells `dismissSheet` whether `hide()` will produce a
        /// completion at all, and therefore whether the completion will run the
        /// dismiss handler or whether `dismissSheet` must. A parent suspended to
        /// make room for a nested sheet is exactly that case: it was hidden by
        /// `presentSheet`, its promise has already completed, and hiding it
        /// again notifies nobody.
        ///
        /// 本 sheet 是否有一個尚未完成的 `showAsync` promise。
        ///
        /// 它是 `dismissSheet` 用來判斷「`hide()` 究竟會不會產生一次完成」的依據，也因此決定了該由完成
        /// 處理來執行 dismiss handler，還是必須由 `dismissSheet` 自己來執行。為了讓出空間給巢狀 sheet
        /// 而被暫停的 parent 正是後者：它已經被 `presentSheet` 隱藏，其 promise 早已完成，再隱藏它一次
        /// 不會通知任何人。
        var isPresenting = false
        /// `interactiveDismissDisabled` from the last `updateSheet`: Escape
        /// and WinUI's own dismissal are refused while it is set.
        /// 最近一次 `updateSheet` 的 `interactiveDismissDisabled`:設定時拒絕 Escape 與 WinUI 自己的關閉。
        var interactiveDismissDisabled = false
        /// Set before every `hide()` this backend makes, cleared by the
        /// completion, so the `closing` handler can tell code from the user.
        /// 本 backend 每次 `hide()` 之前設定，由完成處理清除，讓 `closing` handler 分得出程式與使用者。
        var isHidingByCode = false
        /// Hidden so an alert can be shown (WinUI shows one ContentDialog at a
        /// time); `pendingAlert` is shown from this sheet's completion.
        /// 為了顯示 alert 而隱藏(WinUI 一次只顯示一個 ContentDialog);`pendingAlert` 由本 sheet 的完成處理顯示。
        var isSuspendedForAlert = false
        var pendingAlert: Alert?
        /// Set once the dismiss handler has run; such a sheet is never shown again.
        /// dismiss handler 執行過後設定;這樣的 sheet 不會再顯示。
        var isDismissed = false
        /// Set by `setPresentationFillsWindow`. 由 `setPresentationFillsWindow` 設定。
        var fillsWindow = false
    }

    public func createSheet(content: Widget) -> Sheet {
        let sheet = Sheet()
        sheet.content = content

        // When all buttons are unlabelled, WinUI hides the actions section of
        // the dialog automatically.
        sheet.primaryButtonText = ""
        sheet.secondaryButtonText = ""
        sheet.closeButtonText = ""

        // Sometimes the sheet will have its own default escape key handling,
        // and sometimes it won't. This accelerator is for the cases where it
        // doesn't. It's not exactly clear what determines whether this
        // accelerator is required, but from some testing it seems that sheets
        // without interactive content don't have escape key handling by default
        // (e.g. sheets with only text).
        let accelerator = WinUI.KeyboardAccelerator()
        accelerator.key = .escape
        accelerator.invoked.addHandler { [weak sheet] _, _ in
            guard let sheet, !sheet.interactiveDismissDisabled else { return }
            do {
                try sheet.hide()
            } catch {
                logger.warning("WinUIBackend: Escape could not hide the sheet -- \(error)")
            }
        }
        sheet.keyboardAccelerators.append(accelerator)
        // WinUI's own Escape handling (and any other dismissal it starts) goes
        // through `Closing`, which is where `interactiveDismissDisabled` is
        // honoured; this backend's own hides set `isHidingByCode` and pass.
        // WinUI 自己的 Escape 處理(以及它發起的其他關閉)都經過 `Closing`,`interactiveDismissDisabled`
        // 就在那裡生效;本 backend 自己的隱藏會設定 `isHidingByCode` 而通過。
        sheet.closing.addHandler { [weak sheet] _, args in
            guard let sheet, let args else { return }
            if sheet.interactiveDismissDisabled && !sheet.isHidingByCode {
                args.cancel = true
            }
        }
        sheet.keyboardAcceleratorPlacementMode = .hidden
        // Alt+Left, the Back key and the mouse's back button pop a stack in the
        // sheet; see WinUIBackend+BackNavigation.swift.
        // Alt+Left、返回鍵與滑鼠返回鍵彈出 sheet 中的堆疊；見 WinUIBackend+BackNavigation.swift。
        WinUIBackNavigation.install(on: sheet, name: "sheet") { [weak sheet] in sheet?.window }

        // The top portion of a ContentDialog (the dialog portion) is an
        // overlay with its own background color. We hide the action portion
        // of the dialog to use it as a sheet, so we remove the overlay
        // background and simply use the dialog's background property to
        // control the background color of the sheet.
        _ = sheet.resources.insert("ContentDialogTopOverlay", nil)
        _ = sheet.resources.insert("ContentDialogSeparatorBorderBrush", nil)
        _ = sheet.resources.insert("ContentDialogMaxWidth", 1000000 as Double)
        _ = sheet.resources.insert("ContentDialogMinWidth", 0 as Double)
        _ = sheet.resources.insert("ContentDialogMaxHeight", 1000000 as Double)
        _ = sheet.resources.insert("ContentDialogMinHeight", 0 as Double)

        return sheet
    }

    public func updateSheet(
        _ sheet: Sheet,
        window: Window,
        environment: EnvironmentValues,
        size: SIMD2<Int>,
        onDismiss: @escaping () -> Void,
        cornerRadius: Double?,
        detents _: [PresentationDetent],
        dragIndicatorVisibility _: SwiftCrossUI.Visibility,
        backgroundColor: SwiftCrossUI.Color.Resolved?,
        interactiveDismissDisabled: Bool
    ) {
        // A cover takes the whole XamlRoot -- menu bar and toolbar rows too --
        // because the dialog overlays all of it. 覆蓋整個 XamlRoot(連選單列與工具列那幾列),因為 dialog 蓋在它們全部之上。
        if sheet.fillsWindow, let root = window.content.xamlRoot {
            sheet.width = max(Double(size.x), Double(root.size.width))
            sheet.height = max(Double(size.y), Double(root.size.height))
        } else {
            sheet.width = Double(size.x)
            sheet.height = Double(size.y)
        }
        sheet.dismissHandler = onDismiss
        sheet.interactiveDismissDisabled = interactiveDismissDisabled

        if let cornerRadius {
            sheet.cornerRadius = CornerRadius(
                topLeft: cornerRadius,
                topRight: cornerRadius,
                bottomRight: cornerRadius,
                bottomLeft: cornerRadius
            )
        } else {
            // Back to the theme's `OverlayCornerRadius`. 回到主題的 `OverlayCornerRadius`。
            _ = try? sheet.clearValue(WinUI.Control.cornerRadiusProperty)
        }

        if let backgroundColor {
            sheet.background = WinUI.SolidColorBrush(backgroundColor.uwpColor)
        } else {
            try! sheet.clearValue(Sheet.backgroundProperty)
        }

        sheet.requestedTheme = switch environment.colorScheme {
            case .light: .light
            case .dark: .dark
        }
    }

    /// `createSheet` already lifts ContentDialogMaxWidth and MaxHeight to 1e6;
    /// a cover also asks WinUI for a full-size dialog (`FullSizeDesired`) and is
    /// sized to its window's XamlRoot by `updateSheet`, which is called next.
    /// `createSheet` 已把 ContentDialog 的最大寬高拿到 1e6;cover 還會向 WinUI 要求全尺寸 dialog
    /// (`FullSizeDesired`),並由接著呼叫的 `updateSheet` 依視窗的 XamlRoot 決定大小。
    public func setPresentationFillsWindow(of sheet: Sheet, window: Window, _ fillsWindow: Bool) {
        sheet.fillsWindow = fillsWindow
        sheet.fullSizeDesired = fillsWindow
    }

    public func presentSheet(
        _ sheet: Sheet,
        window: Window,
        parentSheet: Sheet?
    ) {
        sheet.window = window
        sheet.parentSheet = parentSheet

        if let parentSheet, parentSheet.isPresenting {
            parentSheet.nestedSheet = sheet
            parentSheet.pendingNestedPresentation = sheet
            parentSheet.isSuspendedForNestedSheet = true
            parentSheet.isHidingByCode = true
            do {
                try parentSheet.hide()
            } catch {
                print("Error: \(error)")
                parentSheet.isSuspendedForNestedSheet = false
                parentSheet.pendingNestedPresentation = nil
                parentSheet.isHidingByCode = false
                presentSheetNow(sheet, window: window)
            }
            return
        }

        // A parent that is not on screen -- suspended for an alert, or itself
        // waiting for one -- has no hide to wait for; the child closing still
        // brings it back through `parentSheet`.
        // 不在螢幕上的 parent(為 alert 暫停，或自己也在等 alert)沒有隱藏可等;子 sheet 關閉時仍會經由
        // `parentSheet` 把它帶回來。
        parentSheet?.nestedSheet = sheet
        presentSheetNow(sheet, window: window)
    }

    func presentSheetNow(_ sheet: Sheet, window: Window) {
        guard !sheet.isDismissed else { return }
        if window.currentAlert != nil {
            // An alert holds the window's one ContentDialog: the sheet waits,
            // and `presentSheets(afterAlertsIn:suspended:)` shows it when the
            // alert stack closes, so `isPresented` is not left true for a sheet
            // that never appeared.
            // alert 佔著視窗唯一的 ContentDialog:sheet 等待，由 `presentSheets(afterAlertsIn:suspended:)`
            // 在 alert 堆疊關閉時顯示，因此不會留下一個 `isPresented` 為 true 卻從未出現的 sheet。
            sheet.window = window
            window.sheetsWaitingForAlerts.append(sheet)
            return
        }
        sheet.xamlRoot = window.content.xamlRoot
        sheet.window = window
        sheet.isPresenting = true
        // The window ignores Back while this sheet is up; see
        // WinUIBackend+BackNavigation.swift. sheet 開著時視窗忽略返回；見 WinUIBackend+BackNavigation.swift。
        window.presentedSheet = sheet
        do {
            let promise = try sheet.showAsync()!
            promise.completed = { [weak self, weak sheet, weak window] _, status in
                guard let self, let sheet, status == .completed else {
                    return
                }

                sheet.isPresenting = false
                sheet.isHidingByCode = false

                // An alert asked for this sheet's room; it is shown last, once
                // whatever else this completion does has been decided.
                // 有 alert 要求本 sheet 讓出位置;它在本完成處理決定好其他事情之後才顯示。
                let pendingAlert = sheet.pendingAlert
                sheet.pendingAlert = nil
                let wasSuspendedForAlert = sheet.isSuspendedForAlert
                sheet.isSuspendedForAlert = false

                if sheet.isSuspendedForNestedSheet {
                    sheet.isSuspendedForNestedSheet = false
                    if
                        let nestedSheet = sheet.pendingNestedPresentation,
                        let window = sheet.window ?? window
                    {
                        sheet.pendingNestedPresentation = nil
                        // Queued behind the alert if one is pending. 若有 alert 待顯示，就排在它後面。
                        self.presentSheetNow(nestedSheet, window: window)
                    }
                    pendingAlert?.showAttached()
                    return
                }

                if wasSuspendedForAlert {
                    // Comes back when the alert stack closes. alert 堆疊關閉時回來。
                    pendingAlert?.showAttached()
                    return
                }

                // A nested sheet closing restores its parent. `parentSheet` is
                // cleared by `dismissSheet` when the parent is going away too,
                // which is what keeps a dismissed chain from putting its own
                // root back on screen.
                // 巢狀 sheet 關閉時會讓其 parent 復原。當 parent 本身也要一併消失時，
                // `dismissSheet` 會清掉 `parentSheet`，那正是「已被關閉的整條鏈不會把自己的根重新
                // 放回畫面上」的原因。
                if let parentSheet = sheet.parentSheet {
                    parentSheet.nestedSheet = nil
                    sheet.parentSheet = nil

                    if let pendingAlert {
                        // The alert goes up first; the parent returns after it.
                        // alert 先上去;parent 在它之後回來。
                        pendingAlert.suspendedSheet = parentSheet
                    } else if let window = parentSheet.window ?? window {
                        self.presentSheetNow(parentSheet, window: window)
                    }
                }

                // Unconditional: the completion arrives for a `hide()` whoever
                // called it, including the programmatic path `SheetModifier`
                // uses, and the caller's callback has to run there too (#104).
                //
                // It cannot fire twice for one dismissal. Every closed sheet has
                // exactly one completed `showAsync` promise, this is the only
                // handler on it, and `dismissSheet` only runs the callback
                // itself for a sheet with no promise outstanding (`isPresenting
                // == false`) -- so the two callers are mutually exclusive by
                // construction, and `notifyDismissed` makes it once even if that
                // reasoning is ever broken by a later change. On the framework
                // side, `SheetModifier.commit`'s programmatic branch is only
                // entered when `isPresented` is already false and nils
                // `children.sheet` immediately, so it does not re-enter either.
                //
                // 無條件執行：無論是誰呼叫 `hide()`,完成處理都會送達——包括 `SheetModifier` 所使用的程式化
                // 那條路——而呼叫端的回呼在那裡也必須執行(#104)。
                //
                // 它不可能為同一次關閉觸發兩次。每一個被關閉的 sheet 恰好有一個已完成的 `showAsync`
                // promise，其上只有這一個 handler，而 `dismissSheet` 只有在 sheet 沒有未完成的 promise
                // 時（`isPresenting == false`）才會自行執行該 handler——因此這兩個呼叫端在構造上互斥。
                // 在框架那一側，`SheetModifier.commit` 的程式化分支只有在 `isPresented` 已經為 false
                // 時才會進入，並隨即把 `children.sheet` 設為 nil，所以它也不會重入。而即使日後有變更
                // 打破了上述推理，`notifyDismissed` 仍能保證它只執行一次。
                self.notifyDismissed(sheet)
                pendingAlert?.showAttached()
            }
        } catch {
            // WinUI only allows a single ContentDialog per XamlRoot. Nested
            // sheets suspend their parent before presenting; any error that
            // still reaches this point should be visible without crashing the
            // process.
            print("Error: \(error)")
            sheet.isPresenting = false
        }
    }

    /// The programmatic path: `SheetModifier` calling in because `isPresented`
    /// went false.
    ///
    /// 程式化的那條路：`SheetModifier` 因 `isPresented` 轉為 false 而呼叫進來。
    public func dismissSheet(_ sheet: Sheet, window: Window, parentSheet: Sheet?) {
        if let nestedSheet = sheet.nestedSheet {
            sheet.nestedSheet = nil
            // The child is going down with its parent, so it must not bring the
            // parent back. `presentSheetNow`'s completion re-presents
            // `sheet.parentSheet` when a nested sheet closes -- right when the
            // USER closed the child, wrong here, where the parent is being
            // dismissed as well and would be put straight back on screen.
            // 這個子 sheet 是跟著它的 parent 一起消失的，因此它不該把 parent 帶回來。
            // `presentSheetNow` 的完成處理會在巢狀 sheet 關閉時重新呈現 `sheet.parentSheet`
            // ——在**使用者**關閉子 sheet 時那是對的，在此處則是錯的，因為此處 parent 本身也正在被
            // 關閉，那樣做會把它直接放回畫面上。
            nestedSheet.parentSheet = nil
            dismissSheet(nestedSheet, window: window, parentSheet: nil)
            // No `nestedSheet.dismissHandler?()` here: the child's own
            // completion runs the handler, and calling it here as well would
            // fire it twice.
            // 此處不呼叫 `nestedSheet.dismissHandler?()`:子 sheet 自身的完成處理會執行該 handler,
            // 若此處再呼叫一次就會重複觸發。
        }

        sheet.isSuspendedForNestedSheet = false
        sheet.pendingNestedPresentation = nil
        // `pendingAlert` is kept: the completion still shows it.
        // `pendingAlert` 保留：完成處理仍會顯示它。
        sheet.isSuspendedForAlert = false
        parentSheet?.nestedSheet = nil

        guard sheet.isPresenting else {
            // Nothing to hide, so nothing will complete, so nothing else will
            // ever run the handler. This is the suspended parent of a nested
            // sheet: `presentSheet` hid it to make room for its child, its
            // `showAsync` promise completed at that moment, and `hide()` on a
            // `ContentDialog` that is not showing is a no-op. Without this
            // branch, dismissing a sheet that has a child open would notify the
            // child and stay silent about the sheet itself.
            //
            // 沒有東西可隱藏，就不會有任何完成，也就不會有別的東西去執行那個 handler。這說的是巢狀
            // sheet 那個被暫停的 parent：`presentSheet` 為了讓出空間給子 sheet 而隱藏了它，它的
            // `showAsync` promise 在那一刻就已完成，而對一個並未顯示的 `ContentDialog` 呼叫 `hide()`
            // 是一次空操作。少了這個分支，關閉一個開著子 sheet 的 sheet 會通知子 sheet，卻對該 sheet
            // 自身保持沉默。
            notifyDismissed(sheet)
            return
        }

        sheet.isHidingByCode = true
        do {
            try sheet.hide()
        } catch {
            print("Error: \(error)")
            sheet.isHidingByCode = false
            // The completion will not arrive for a `hide()` that threw, and the
            // caller is still owed its callback.
            // 對一個擲出錯誤的 `hide()` 而言，完成處理不會送達，而呼叫端仍然應當拿到它的回呼。
            notifyDismissed(sheet)
        }
    }

    /// Runs a sheet's dismiss handler, at most once per sheet.
    ///
    /// The handler is taken before it is called, so the two places that reach
    /// this -- the `showAsync` completion and `dismissSheet` -- cannot between
    /// them notify twice for one dismissal. They are already mutually exclusive
    /// (`dismissSheet` only calls in when no promise is outstanding, or when
    /// `hide()` threw and no completion will arrive), and this is what keeps
    /// that true if either side is edited later.
    ///
    /// Clearing the handler is safe because a dismissed sheet is never reused.
    /// `SheetModifier.commit` nils `sheetContentNode` alongside `sheet`, so
    /// nothing calls `updateSheet` on this object again, and the next
    /// presentation goes through `createSheet` for a new one. A sheet that is
    /// merely SUSPENDED for a nested child is not dismissed and does not pass
    /// through here, so it keeps its handler for when it is restored.
    ///
    /// 執行一個 sheet 的 dismiss handler，每個 sheet 至多一次。
    ///
    /// handler 在被呼叫之前就先被取走，因此抵達此處的兩個地方——`showAsync` 的完成處理，以及
    /// `dismissSheet`——合起來也不可能為同一次關閉通知兩次。它們本來就互斥（`dismissSheet` 只在沒有
    /// 未完成的 promise 時、或在 `hide()` 擲出錯誤而完成處理不會送達時才會呼叫進來），而此處是為了在
    /// 日後任一側被修改時，仍能維持這件事為真。
    ///
    /// 清掉 handler 是安全的，因為已被關閉的 sheet 不會被重複使用。`SheetModifier.commit` 會把
    /// `sheetContentNode` 與 `sheet` 一併設為 nil，因此不會再有東西對這個物件呼叫 `updateSheet`，
    /// 而下一次呈現會經由 `createSheet` 造出一個新的。僅僅因為巢狀子 sheet 而被**暫停**的 sheet 並未
    /// 被關閉，也不會經過此處，因此它會保留自己的 handler，以待復原之時。
    private func notifyDismissed(_ sheet: Sheet) {
        sheet.isDismissed = true
        guard let handler = sheet.dismissHandler else {
            return
        }
        sheet.dismissHandler = nil
        handler()
    }

    /// Hides a presenting sheet so `alert` can have the window's one
    /// ContentDialog; the sheet's completion shows the alert. Returns false if
    /// the hide failed, and the caller shows the alert itself.
    /// 隱藏一個正在呈現的 sheet,讓 `alert` 取得視窗唯一的 ContentDialog;sheet 的完成處理會顯示 alert。
    /// 隱藏失敗時回傳 false,由呼叫端自己顯示 alert。
    func suspendSheet(_ sheet: Sheet, for alert: Alert) -> Bool {
        sheet.isSuspendedForAlert = true
        sheet.pendingAlert = alert
        sheet.isHidingByCode = true
        do {
            try sheet.hide()
            return true
        } catch {
            print("Error: \(error)")
            sheet.isSuspendedForAlert = false
            sheet.pendingAlert = nil
            sheet.isHidingByCode = false
            return false
        }
    }

    /// Called when a window's alert stack has closed. A sheet asked for while
    /// the alerts were up is shown -- the latest, since an earlier one is its
    /// parent and returns when it closes -- and otherwise the sheet the first
    /// alert suspended comes back. Dismissed sheets are skipped.
    /// 視窗的 alert 堆疊關閉時呼叫。顯示 alert 開著期間被要求的 sheet(最新的那個，因為較早的是它的
    /// parent,會在它關閉時回來);沒有的話，第一個 alert 暫停的 sheet 回來。已關閉的 sheet 略過。
    func presentSheets(afterAlertsIn window: Window, suspended: Sheet?) {
        let waiting = window.sheetsWaitingForAlerts.filter { !$0.isDismissed }
        window.sheetsWaitingForAlerts = []
        if let sheet = waiting.last {
            presentSheetNow(sheet, window: sheet.window ?? window)
        } else if let suspended, !suspended.isDismissed {
            presentSheetNow(suspended, window: suspended.window ?? window)
        }
    }

    /// The size the sheet's content was laid out at, else the size
    /// `updateSheet` gave the dialog.
    /// sheet 內容實際排版的尺寸;沒有的話，是 `updateSheet` 給 dialog 的尺寸。
    public func size(ofSheet sheet: Sheet) -> SIMD2<Int> {
        if let content = sheet.content as? WinUI.FrameworkElement,
            content.actualWidth > 0, content.actualHeight > 0
        {
            return SIMD2(
                Int(content.actualWidth.rounded(.towardZero)),
                Int(content.actualHeight.rounded(.towardZero))
            )
        }
        let width = sheet.width.isFinite ? sheet.width : 0
        let height = sheet.height.isFinite ? sheet.height : 0
        return SIMD2(Int(width.rounded(.towardZero)), Int(height.rounded(.towardZero)))
    }
}
