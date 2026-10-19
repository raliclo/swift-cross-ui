import SwiftCrossUI
import WinUI

extension WinUIBackend: BackendFeatures.WidgetGeometry {
    /// Sums the positions SwiftCrossUI gave each Canvas child on the way up to
    /// the window's root, as GtkBackend sums its GtkFixed positions, walking
    /// the parent links ``WinUIParentLinks`` keeps rather than WinUI's tree.
    ///
    /// **WinUI's tree cannot answer while the framework asks.** Traced on P63
    /// (2026-10-19): the reader's Canvas had been inserted into its parent
    /// Canvas, and the root set as the window's child, before the first
    /// question, yet `parent` was nil, `VisualTreeHelper.getParent` nil and
    /// `xamlRoot` nil -- at the commit, at the framework's retry on the next
    /// main-queue turn, and again after HotReloadableView took the tree out
    /// and put it back. Two seconds later all three answered. They describe
    /// the LIVE tree, which an element joins when it loads, after the commits
    /// that ask. `transformToVisual` needs that tree too, so P63 read global
    /// x=0 y=0 and named x=0 y=0 with its marker at about (37, 316) DIPs, with
    /// `updateLayout()` or without. `Canvas.Left`/`Canvas.Top` hold from the
    /// moment `setPosition` sets them, and the links from the moment `insert`
    /// runs.
    ///
    /// At the top of the links: the window's root adds its offset in the
    /// window (the menu and toolbar rows) once WinUI has laid it out, and
    /// nothing before. Any other top -- an element placed by something other
    /// than `insert` -- adds its offset through WinUI if it is in the live
    /// tree, and is "not in a window yet" (nil) if it is not.
    ///
    /// 沿途加總 SwiftCrossUI 交給每個 Canvas 子元件的位置，一路到視窗的 root，與 GtkBackend 加總其
    /// GtkFixed 位置的做法相同；往上走的是 ``WinUIParentLinks`` 記下的父子連結，而不是 WinUI 的樹。
    ///
    /// **框架詢問時，WinUI 的樹答不出來。** 在 P63 上追蹤(2026-10-19):reader 的 Canvas 在第一次詢問
    /// 之前就已插入其父 Canvas，root 也已設為視窗的子元件，但 `parent` 是 nil、`VisualTreeHelper.getParent`
    /// 是 nil、`xamlRoot` 也是 nil——在 commit 時、在框架於下一輪主佇列的重試時，以及 HotReloadableView
    /// 把整棵樹拿下再放回之後都一樣。兩秒後三者都有答案。它們描述的是 **live tree**，元素要在載入時才
    /// 加入，晚於提出詢問的那些 commit。`transformToVisual` 也需要那棵樹，因此 P63 讀到 global x=0 y=0
    /// 與 named x=0 y=0，而其標記約在 (37, 316) DIP——有沒有 `updateLayout()` 都一樣。
    /// `Canvas.Left`/`Canvas.Top` 在 `setPosition` 設定的當下就成立，連結則在 `insert` 執行的當下就成立。
    ///
    /// 走到連結頂端時：視窗的 root 在 WinUI 排好它之後加上它在視窗中的位移(選單列與工具列兩列)，
    /// 之前則為零。其他任何頂端——不是經由 `insert` 放上的元素——若已在 live tree 中就經由 WinUI 加上
    /// 其位移，否則就是「尚未位於任何視窗中」(nil)。
    public func originInWindow(ofWidget widget: Widget) -> SIMD2<Int>? {
        var x = 0.0
        var y = 0.0
        var node: WinUI.FrameworkElement = widget
        var hops = 0
        while let parent = WinUIParentLinks.parent(of: node), hops < 512 {
            x += WinUI.Canvas.getLeft(node)
            y += WinUI.Canvas.getTop(node)
            node = parent
            hops += 1
        }

        let isWindowRoot = WinUIParentLinks.isWindowRoot(node)
        if let root = node.xamlRoot?.content, node.actualWidth > 0,
            let transform = try? node.transformToVisual(root),
            let point = try? transform.transformPoint(.init(x: 0, y: 0))
        {
            // Both calls throw when the two are not in one visual tree; that
            // is "not laid out yet" here.
            // 兩者在不位於同一棵 visual tree 時都會 throw;此處那代表「尚未排版」。
            x += Double(point.x)
            y += Double(point.y)
        } else if !isWindowRoot {
            return nil
        }
        return SIMD2(Int(x.rounded()), Int(y.rounded()))
    }
}

/// Which container each widget was inserted into, and which widgets are a
/// window's root, as SwiftCrossUI set them -- see `originInWindow(ofWidget:)`
/// for why WinUI's own `parent` cannot be asked.
///
/// Keyed by object identity, and each entry holds both ends weakly and is
/// trusted only while its child is still the object asked about, so a
/// recycled identifier cannot answer for a new widget. `insert` overwrites
/// the entry when a widget moves; a widget taken out and never put back keeps
/// a stale entry, which nothing asks about because nothing draws it.
///
/// 記錄每個 widget 被插入到哪個容器、以及哪些 widget 是視窗的 root，皆依 SwiftCrossUI 的設定——
/// 為何不能去問 WinUI 自己的 `parent`，見 `originInWindow(ofWidget:)`。
///
/// 以物件識別為鍵，每筆以弱參照持有兩端，且只在其 child 仍是被詢問的那個物件時才採信，因此被回收
/// 再利用的識別碼不會替新的 widget 作答。widget 移動時 `insert` 會覆寫該筆;被拿下而從未放回的 widget
/// 會留下過期的一筆，但沒有東西會問它，因為沒有東西畫它。
@MainActor
enum WinUIParentLinks {
    private final class Link {
        weak var child: WinUI.FrameworkElement?
        weak var parent: WinUI.FrameworkElement?

        init(child: WinUI.FrameworkElement, parent: WinUI.FrameworkElement) {
            self.child = child
            self.parent = parent
        }
    }

    private final class Root {
        weak var element: WinUI.FrameworkElement?

        init(_ element: WinUI.FrameworkElement) {
            self.element = element
        }
    }

    private static var links: [ObjectIdentifier: Link] = [:]
    private static var roots: [ObjectIdentifier: Root] = [:]

    static func record(child: WinUI.FrameworkElement, in parent: WinUI.FrameworkElement) {
        links[ObjectIdentifier(child)] = Link(child: child, parent: parent)
    }

    static func recordWindowRoot(_ element: WinUI.FrameworkElement) {
        links[ObjectIdentifier(element)] = nil
        roots[ObjectIdentifier(element)] = Root(element)
    }

    static func parent(of element: WinUI.FrameworkElement) -> WinUI.FrameworkElement? {
        guard let link = links[ObjectIdentifier(element)], link.child === element else {
            return nil
        }
        return link.parent
    }

    static func isWindowRoot(_ element: WinUI.FrameworkElement) -> Bool {
        roots[ObjectIdentifier(element)]?.element === element
    }
}
