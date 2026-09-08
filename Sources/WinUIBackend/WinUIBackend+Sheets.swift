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
    /// A field used to live here -- `isProgrammaticDismissal`, recording which
    /// path a `showAsync` completion came from so that `dismissSheet` could
    /// suppress the caller's `onDismiss:`. It is gone, for the same reason the
    /// identical flag left `Popover` in `6ec976b2`: SwiftUI runs `onDismiss:`
    /// when the presentation ends however it ended, and keeping the flag meant
    /// `sheet(isPresented:onDismiss:)` fired on one of its two paths. The
    /// asymmetry it produced was visible from inside this file --
    /// `dismissSheet` had to call `nestedSheet.dismissHandler?()` by hand,
    /// because the suppressed completion would not -- so a nested sheet got its
    /// callback while the sheet the caller actually dismissed did not.
    ///
    /// 一個 `ContentDialog`，外加 WinUI 不會替我們做的記帳工作。
    ///
    /// 此處原本有一個欄位——`isProgrammaticDismissal`，用來記錄某次 `showAsync` 完成是從哪一條路來的，
    /// 好讓 `dismissSheet` 能壓住呼叫端的 `onDismiss:`。它已經被移除，理由與同一個旗標在 `6ec976b2`
    /// 離開 `Popover` 時完全相同：無論 presentation 以何種方式結束，SwiftUI 都會執行 `onDismiss:`，
    /// 而保留該旗標意味著 `sheet(isPresented:onDismiss:)` 只在它兩條路中的其中一條上觸發。它所造成的
    /// 偏差在本檔案內部就看得見——`dismissSheet` 必須手動呼叫 `nestedSheet.dismissHandler?()`，因為
    /// 被壓住的完成處理不會呼叫它——於是巢狀 sheet 拿得到回呼，而呼叫端真正關閉的那個 sheet 拿不到。
    public class Sheet: ContentDialog {
        var dismissHandler: (() -> Void)?
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
            guard let sheet else { return }
            try! sheet.hide()
        }
        sheet.keyboardAccelerators.append(accelerator)
        sheet.keyboardAcceleratorPlacementMode = .hidden

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
        sheet.width = Double(size.x)
        sheet.height = Double(size.y)
        sheet.dismissHandler = onDismiss

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

    public func presentSheet(
        _ sheet: Sheet,
        window: Window,
        parentSheet: Sheet?
    ) {
        sheet.window = window
        sheet.parentSheet = parentSheet

        if let parentSheet {
            parentSheet.nestedSheet = sheet
            parentSheet.pendingNestedPresentation = sheet
            parentSheet.isSuspendedForNestedSheet = true
            do {
                try parentSheet.hide()
            } catch {
                print("Error: \(error)")
                presentSheetNow(sheet, window: window)
            }
            return
        }

        presentSheetNow(sheet, window: window)
    }

    private func presentSheetNow(_ sheet: Sheet, window: Window) {
        sheet.xamlRoot = window.content.xamlRoot
        sheet.window = window
        sheet.isPresenting = true
        do {
            let promise = try sheet.showAsync()!
            promise.completed = { [weak self, weak sheet, weak window] _, status in
                guard let self, let sheet, status == .completed else {
                    return
                }

                sheet.isPresenting = false

                if sheet.isSuspendedForNestedSheet {
                    sheet.isSuspendedForNestedSheet = false
                    if
                        let nestedSheet = sheet.pendingNestedPresentation,
                        let window = sheet.window ?? window
                    {
                        sheet.pendingNestedPresentation = nil
                        self.presentSheetNow(nestedSheet, window: window)
                    }
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

                    if let window = parentSheet.window ?? window {
                        self.presentSheetNow(parentSheet, window: window)
                    }
                }

                // Unconditional. There used to be a
                // `guard !wasProgrammaticDismissal else { return }` here, and it
                // was the whole of issue #104 on this backend: the completion
                // arrives for a `hide()` whoever called it, so the callback was
                // reachable the entire time and was being thrown away on the one
                // path `SheetModifier` uses. Deleting the guard is the fix.
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
                // 無條件執行。此處原本有一個 `guard !wasProgrammaticDismissal else { return }`，
                // 而它就是 issue #104 在本 backend 上的全部：無論是誰呼叫 `hide()`，完成處理都會送達，
                // 因此該回呼從頭到尾都抵達得了，只是在 `SheetModifier` 所使用的那唯一一條路上被丟棄。
                // 刪掉那個 guard 就是修正。
                //
                // 它不可能為同一次關閉觸發兩次。每一個被關閉的 sheet 恰好有一個已完成的 `showAsync`
                // promise，其上只有這一個 handler，而 `dismissSheet` 只有在 sheet 沒有未完成的 promise
                // 時（`isPresenting == false`）才會自行執行該 handler——因此這兩個呼叫端在構造上互斥。
                // 在框架那一側，`SheetModifier.commit` 的程式化分支只有在 `isPresented` 已經為 false
                // 時才會進入，並隨即把 `children.sheet` 設為 nil，所以它也不會重入。而即使日後有變更
                // 打破了上述推理，`notifyDismissed` 仍能保證它只執行一次。
                self.notifyDismissed(sheet)
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
            // No `nestedSheet.dismissHandler?()` here any more. It was needed
            // only because the child's own completion was suppressed by
            // `isProgrammaticDismissal`; with that flag gone the completion runs
            // the handler itself, and calling it here as well would be the
            // double fire the fix has to avoid.
            // 此處不再有 `nestedSheet.dismissHandler?()`。它之所以曾經必要，只是因為子 sheet 自身的
            // 完成處理被 `isProgrammaticDismissal` 壓住了；該旗標消失後，完成處理會自行執行該
            // handler，而若此處再呼叫一次，正好就是本次修正必須避免的重複觸發。
        }

        sheet.isSuspendedForNestedSheet = false
        sheet.pendingNestedPresentation = nil
        parentSheet?.nestedSheet = nil

        guard sheet.isPresenting else {
            // Nothing to hide, so nothing will complete, so nothing else will
            // ever run the handler. This is the suspended parent of a nested
            // sheet: `presentSheet` hid it to make room for its child, its
            // `showAsync` promise completed at that moment, and `hide()` on a
            // `ContentDialog` that is not showing is a no-op. Without this
            // branch, dismissing a sheet that has a child open would notify the
            // child and stay silent about the sheet itself -- which is the
            // original bug wearing a different hat.
            //
            // 沒有東西可隱藏，就不會有任何完成，也就不會有別的東西去執行那個 handler。這說的是巢狀
            // sheet 那個被暫停的 parent：`presentSheet` 為了讓出空間給子 sheet 而隱藏了它，它的
            // `showAsync` promise 在那一刻就已完成，而對一個並未顯示的 `ContentDialog` 呼叫 `hide()`
            // 是一次空操作。少了這個分支，關閉一個開著子 sheet 的 sheet 會通知子 sheet，卻對該 sheet
            // 自身保持沉默——那正是同一個 bug 換了頂帽子。
            notifyDismissed(sheet)
            return
        }

        do {
            try sheet.hide()
        } catch {
            print("Error: \(error)")
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
        guard let handler = sheet.dismissHandler else {
            return
        }
        sheet.dismissHandler = nil
        handler()
    }

    public func size(ofSheet sheet: Sheet) -> SIMD2<Int> {
        .zero
    }
}
