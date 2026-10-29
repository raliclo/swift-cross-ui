import Foundation
import WinUI

#if canImport(InputEvent)
    import InputEvent

    extension WinUIBackend {
        /// Answers `taplabel` for this backend: where the first shown text equal
        /// to the label is, as the middle of it in points from the window's
        /// client origin. Win32Synthesiser then clicks there.
        ///
        /// What is searched, in order: the open popups of the window's XamlRoot,
        /// newest first (a sheet is a ContentDialog, a popover a flyout; both
        /// live there and sit above the content), then the window content.
        /// What matches: a TextBlock or TextBox whose text equals the label. A
        /// Button showing a string draws it with a TextBlock in its template,
        /// which the visual-tree walk reaches, so buttons need no case of their
        /// own. Collapsed or zero-sized elements are skipped.
        ///
        /// Points, not pixels: XAML lays out in DIPs from the top-left of the
        /// content, and this backend does not extend content into the title
        /// bar, so the content's origin is the Win32 client origin. The
        /// synthesiser scales points by GetDpiForWindow, as it does for every
        /// `client` row.
        ///
        /// 為本 backend 回答 `taplabel`:第一段顯示中、文字等於該標籤者在哪裡，以它的中心、距視窗 client 原點的點數
        /// 表示。Win32Synthesiser 接著在那裡點擊。
        ///
        /// 搜尋順序：先找視窗 XamlRoot 中開著的 popup,由新到舊(sheet 是 ContentDialog、popover 是 flyout,兩者都
        /// 住在那裡，並蓋在內容之上),再找視窗內容。比對對象：文字等於標籤的 TextBlock 或 TextBox。顯示字串的
        /// Button 是用其範本裡的 TextBlock 畫出文字，visual tree 走得到，所以按鈕不需另外處理。collapsed 或
        /// 尺寸為零的元素會被略過。
        ///
        /// 用點數而非像素:XAML 以 DIP 從內容左上角排版，而本 backend 沒有把內容延伸進標題列，因此內容的原點就是
        /// Win32 的 client 原點。合成器會依 GetDpiForWindow 換算點數，與每一列 `client` 相同。
        func installLabelLocator(for window: Window) {
            nonisolated(unsafe) let window = window
            ActionFileReplay.locateLabel = { [weak self] label in
                guard let self else { return nil }
                let done = DispatchSemaphore(value: 0)
                nonisolated(unsafe) var place: (x: Double, y: Double)?
                self.runInMainThread {
                    defer { done.signal() }
                    guard let root = window.content, let xamlRoot = root.xamlRoot else {
                        return
                    }
                    func find(_ element: WinUI.DependencyObject) -> WinUI.FrameworkElement? {
                        if let shown = element as? WinUI.UIElement, shown.visibility != .visible {
                            return nil
                        }
                        if let block = element as? WinUI.TextBlock,
                            block.actualWidth > 0, block.text == label
                        {
                            return block
                        }
                        if let box = element as? WinUI.TextBox,
                            box.actualWidth > 0, box.text == label
                        {
                            return box
                        }
                        let count = VisualTreeHelper.getChildrenCount(element)
                        for index in 0..<count {
                            // Not `as? UIElement`: inside a ContentDialog one template node projects
                            // only as DependencyObject and skipping it dropped the whole sheet
                            // (P114-sheet-back on 2026-10-29).
                            // 不用 `as? UIElement`:ContentDialog 裡範本的某個節點只投影為 DependencyObject;
                            // 跳過它就漏掉整個 sheet(2026-10-29 的 P114-sheet-back)。
                            guard let child = VisualTreeHelper.getChild(element, index) else { continue }
                            if let found = find(child) { return found }
                        }
                        return nil
                    }
                    var searched: [WinUI.UIElement] = []
                    if let popups = VisualTreeHelper.getOpenPopupsForXamlRoot(xamlRoot) {
                        for index in (0..<popups.size).reversed() {
                            if let popup = popups.getAt(index), let child = popup.child {
                                searched.append(child)
                            }
                        }
                    }
                    searched.append(root)
                    for scope in searched {
                        guard let found = find(scope),
                            let transform = try? found.transformToVisual(root),
                            let corner = try? transform.transformPoint(.init(x: 0, y: 0))
                        else { continue }
                        place = (
                            x: Double(corner.x) + found.actualWidth / 2,
                            y: Double(corner.y) + found.actualHeight / 2
                        )
                        return
                    }
                }
                done.wait()
                return place
            }
        }
    }
#endif
