import DebugFeatures
import UIKit

@_spi(Backends) import SwiftCrossUI

/// Two answers to "the content is wider than the phone", and a way to see both.
///
/// The test apps in this tree are drawn at desktop widths. P10's three columns
/// with 24pt spacing and a 200pt block come to over 600 points; an iPhone's
/// safe area is 393. Measured on the simulator 2026-09-02, fourteen of the
/// forty-six apps overflowed horizontally and were clipped at both edges.
///
/// That is not a wrong answer from the layout system — SwiftUI overflows too
/// when a fixed-width child cannot fit — but on a phone, content you cannot
/// reach is content you cannot test. So the root child is hosted in a scroll
/// view, and the mode decides what the scroll view is asked to do:
///
/// - **actualView** (the default): the content keeps its natural size and the
///   scroll view scrolls to reach it. Nothing is resized, so anything measured
///   from a screenshot is measured at the size the app asked for.
/// - **rwdView**: the content is scaled down until it fits the width, and there
///   is nothing to scroll. Everything is visible at once and everything is
///   smaller, text included.
///
/// **rwdView scales; it does not reflow.** A true responsive layout would
/// re-propose a narrower width and let each container lay out again, which is
/// shared layout-system work affecting all five backends. This is a transform
/// on the finished layout — honest about what it is, and the reason the button
/// says `rwdView` rather than `responsive`.
///
/// The button is a debug affordance and is gated on ``DebugFeatures/isEnabled``
/// so that a release build has no floating control over its content. It is
/// draggable because a fixed one would sit over whatever it was placed over,
/// and the whole point is to see the content underneath.
///
/// 對「內容比手機寬」的兩個答案，以及一個能同時看見兩者的方式。
///
/// 本樹中的測試 app 是以桌面寬度繪製的。P10 的三欄加 24pt 間距、內含 200pt 方塊，合計超過 600 點；
/// 而 iPhone 的安全區域是 393。2026-09-02 於模擬器上實測，四十六支 app 中有十四支水平溢出並在左右
/// 兩側被裁切。
///
/// 那並不是版面系統給出的錯誤答案——當固定寬度的子元件放不下時，SwiftUI 同樣會溢出——但在手機上，
/// 「碰不到的內容」就是「測不到的內容」。因此根子元件被放進一個捲動視圖中，而模式決定該捲動視圖
/// 被要求做什麼：
///
/// - **actualView**（預設）：內容保持其自然尺寸，由捲動視圖捲動以觸及。沒有任何東西被縮放，因此
///   從螢幕截圖上量到的一切，都是在 app 所要求的尺寸下量到的。
/// - **rwdView**：內容被縮小直到塞進寬度，因而沒有東西可捲。所有內容一次可見，而所有內容都變小了，
///   文字亦然。
///
/// **rwdView 是縮放，不是重新排版。** 真正的響應式版面會重新提出一個較窄的寬度、讓每個容器重新排版，
/// 那屬於共用版面系統的工作，會同時影響五個 backend。此處是對「已完成的版面」施加變換——對自己是
/// 什麼保持誠實，這也是該按鈕標示為 `rwdView` 而非 `responsive` 的理由。
///
/// 該按鈕是 debug 用的輔助功能，以 ``DebugFeatures/isEnabled`` 為條件，使 release 建置的內容之上
/// 不會浮著一個控制項。它可拖曳，因為固定位置的按鈕必然會遮住它所在之處的東西，而這件事的全部意義
/// 正是要看見它下方的內容。
final class RootScrollHost: UIScrollView {
    enum Mode {
        case actualView
        case rwdView

        var next: Mode { self == .actualView ? .rwdView : .actualView }

        var title: String {
            switch self {
                case .actualView: "actualView"
                case .rwdView: "rwdView"
            }
        }
    }

    private(set) var mode: Mode = .actualView
    private weak var content: UIView?

    /// The full bounding box, negative coordinates included.
    ///
    /// The first version returned only a size, taking the largest
    /// `minX + width`. That misses everything laid out to the *left* of the
    /// origin, and content wider than its container is centred, so half the
    /// overflow is at negative x. Measured on the simulator: P10 rendered
    /// identically before and after the scroll view was introduced, because the
    /// extent it reported was the container's own width and there was nothing
    /// to scroll to.
    ///
    /// A scroll view cannot reach negative coordinates, so the caller shifts
    /// the content by `-origin` and scrolls the positive box that leaves.
    ///
    /// 完整的外接矩形，包含負座標。
    ///
    /// 第一版只回傳尺寸，取的是最大的 `minX + width`。那會漏掉所有排在原點**左側**的東西；而比容器
    /// 寬的內容是置中的，因此有一半的溢出位於負 x。模擬器上實測：引入捲動視圖前後，P10 的算繪完全
    /// 相同，因為它回報的範圍就是容器自身的寬度，沒有任何東西可捲。
    ///
    /// 捲動視圖無法觸及負座標，因此呼叫端會把內容平移 `-origin`，再捲動所剩下的那個正座標矩形。
    private func contentBounds(of view: UIView) -> CGRect {
        // A container's own frame is not content, and counting it is what made
        // this shift things that were already in view.
        //
        // Measured on P17, 2026-09-08: the box came out at origin (-241, -45)
        // size 872x889 in a 390-wide host, and the leftmost extent was a
        // `BaseViewWidget` at x = -241 -- exactly (390 - 872) / 2, an 872-wide
        // container centred. Its left 241 points draw nothing; the text inside
        // it starts further in, at x = 0 on screen. Shifting by -box.minX then
        // moved that text from 0 to 241, and the window showed 241 points of
        // blank followed by clipped content.
        //
        // So a view that draws nothing contributes only its children. A view
        // that draws contributes its own bounds as well, which is what keeps a
        // label, an image or a filled shape reachable when it overflows.
        //
        // 容器自身的框不是內容,而把它算進去,正是使本位移推動「原本已經在畫面內」之物的原因。
        //
        // 2026-09-08 於 P17 上實測:在 390 寬的 host 中,box 算出來是 origin (-241, -45)、
        // size 872x889,而最左的延伸是一個位於 x = -241 的 `BaseViewWidget`——恰好是
        // (390 - 872) / 2,也就是一個 872 寬的容器被置中。它左側的 241 點什麼都不畫;其內部的文字
        // 從更右邊開始,在螢幕上正好是 x = 0。接著以 -box.minX 位移,就把那些文字從 0 推到了 241,
        // 於是視窗顯示出 241 點的空白,後面接著被裁切的內容。
        //
        // 因此,一個什麼都不畫的 view 只貢獻它的子節點。一個會畫東西的 view 則額外貢獻它自己的框,
        // 而那正是「當一個標籤、圖片或填色形狀溢出時仍然構得到」的保證。
        var box = draws(view) ? CGRect(origin: .zero, size: view.bounds.size) : .null
        for subview in view.subviews where !subview.isHidden {
            let sub = contentBounds(of: subview).offsetBy(
                dx: subview.frame.minX,
                dy: subview.frame.minY
            )
            box = box.isNull ? sub : (sub.isNull ? box : box.union(sub))
        }
        // A view with no drawing and no children still occupies space in a
        // stack, and returning `.null` upward would make its parent forget it.
        // 一個既不繪製、也沒有子節點的 view,在 stack 中仍然佔據空間;若向上回傳 `.null`,
        // 它的父層就會忘記它的存在。
        return box.isNull ? CGRect(origin: .zero, size: view.bounds.size) : box
    }

    /// Whether this view puts anything on screen itself, as opposed to only
    /// positioning children.
    ///
    /// Deliberately conservative: anything that is not a plain, transparent
    /// container counts as drawing. Being wrong in that direction leaves the
    /// old behaviour -- content shifted further than necessary, which is
    /// visible -- while being wrong the other way would make real content
    /// unreachable, which is not.
    ///
    /// 這個 view 自己是否會在畫面上放置任何東西,而不只是為子節點定位。
    ///
    /// 刻意保守:凡不是「單純且透明的容器」者,一律視為會繪製。往這個方向判斷錯了,結果是維持舊行為
    /// ——內容被推得比必要更遠,而那是看得見的;往另一個方向錯了,則會讓真實內容變得構不到,而那不是。
    private func draws(_ view: UIView) -> Bool {
        if view.layer.contents != nil { return true }
        if let colour = view.backgroundColor, colour.cgColor.alpha > 0 { return true }
        // `BaseViewWidget` is this backend's plain container; everything else
        // -- labels, images, controls, and any UIKit view a backend wraps --
        // is assumed to draw.
        // `BaseViewWidget` 是本 backend 的單純容器;其餘一切——標籤、圖片、控制項,以及任何被 backend
        // 包裝的 UIKit view——都假定會繪製。
        return !(view is BaseViewWidget)
    }

    func host(_ view: UIView) {
        content = view
        addSubview(view)
    }

    func setMode(_ newMode: Mode) {
        mode = newMode
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let content else { return }

        // Measured with the transform cleared, or the measurement includes the
        // previous scale and the content shrinks a little further on every
        // layout pass.
        // 量測前先清除 transform，否則量到的會包含上一次的縮放，內容會在每一次版面計算中又縮小一些。
        content.transform = .identity
        content.frame.origin = .zero
        // **Lay the content out FIRST, or the box is measured from frames that are not
        // there yet.** A layout pass runs top-down, so this method runs before the
        // content resolves the constraints SwiftCrossUI set on its children; without
        // this line the first pass measured an empty box -- (0, 0, 0, 0) for P0,
        // (0, 0, 428, 926) for P72 -- and the real one was only seen when something
        // else happened to request another pass, usually the first touch. That was the
        // jump under the first tap, and it is also why P30's left overflow stayed out
        // of reach: the shift that brings it into view was computed from a box that
        // did not contain it.
        // **先讓內容排版,否則 box 量的是還不存在的 frame。**一輪排版由上往下,因此本方法在內容解出
        // SwiftCrossUI 對其子 view 設下的約束**之前**就執行;少了這一行,第一輪量到的是空的 box——P0 是
        // (0, 0, 0, 0)、P72 是 (0, 0, 428, 926)——真正的 box 要等別的東西碰巧再要求一輪排版才看得到,
        // 通常是第一次觸控。那就是第一次點擊底下的跳動,也是 P30 左側溢出一直構不到的原因:把它帶進畫面的
        // 平移,是從一個不包含它的 box 算出來的。
        content.layoutIfNeeded()
        let box = contentBounds(of: content)

        switch mode {
            case .actualView:
                // Shifted so content overflowing to the LEFT or TOP lands at the
                // scroll view's origin. Without this the overflow to the left
                // is unreachable however large contentSize is.
                //
                // **Only a negative extent is shifted, and until 2026-09-27 a
                // positive one was too -- that was iOS's "only the first
                // interaction lands".** The first layout pass runs before the
                // content's children are placed, so the box starts at (0, 0)
                // and nothing moves. `UIScrollView` lays out again on the first
                // touch; by then P72's box starts at (26, 30), and shifting by
                // that moved the whole column 26 points left and 30 up, under
                // the first tap. Every later row aimed at the launch-time layout
                // and missed. Content already on screen needs no shift to be
                // reachable, so it no longer gets one, and the two passes agree.
                //
                // 平移，使溢出到**左側或上方**的內容落在捲動視圖的原點。少了這一步，無論 contentSize
                // 多大，左側的溢出都無法觸及。
                //
                // **只平移負的延伸;2026-09-27 之前正的也會被平移——那正是 iOS「只有第一次互動生效」。**
                // 第一次版面計算發生在內容的子 view 排好之前,因此 box 從 (0, 0) 開始,什麼都不動。
                // `UIScrollView` 會在第一次觸控時再算一次版面;那時 P72 的 box 從 (26, 30) 開始,
                // 按它平移就把整欄往左推 26 點、往上推 30 點——就在第一次點擊的底下。其後每一列瞄準的都是
                // 啟動時的版面,全部落空。已經在畫面內的內容不需要平移也構得到,所以不再平移它,
                // 兩次版面計算的結果也就一致了。
                let shift = CGPoint(x: max(-box.minX, 0), y: max(-box.minY, 0))
                content.frame.origin = shift
                contentSize = CGSize(width: box.maxX + shift.x, height: box.maxY + shift.y)
                isScrollEnabled = contentSize.width > bounds.width
                    || contentSize.height > bounds.height
            case .rwdView:
                let scale = box.width > bounds.width && bounds.width > 0
                    ? bounds.width / box.width
                    : 1
                content.transform = CGAffineTransform(scaleX: scale, y: scale)
                // After the transform, not before: scaling is about the centre,
                // so the frame moves and the origin has to be set again.
                // 在 transform 之後而非之前：縮放是繞中心進行的，frame 會移動，因此原點必須重新設定。
                content.frame.origin = CGPoint(x: -box.minX * scale, y: -box.minY * scale)
                contentSize = CGSize(width: bounds.width, height: box.height * scale)
                isScrollEnabled = box.height * scale > bounds.height
        }
    }
}

/// The floating control that switches between the two, draggable so it can be
/// moved off whatever it is covering.
///
/// 在兩者之間切換的浮動控制項，可拖曳，以便從它所遮蓋的東西上移開。
final class ViewModeButton: UIButton {
    private var onToggle: ((RootScrollHost.Mode) -> Void)?
    private var mode: RootScrollHost.Mode = .actualView

    static func make(
        initial: RootScrollHost.Mode,
        onToggle: @escaping (RootScrollHost.Mode) -> Void
    ) -> ViewModeButton {
        // An explicit size, and `.custom` rather than `.system`.
        //
        // On iOS 15 and later a `.system` button is configuration-backed:
        // `contentEdgeInsets` is deprecated and ignored, and `sizeToFit()`
        // measured through the configuration rather than the title. Measured on
        // the simulator: the button was in the view hierarchy -- its symbols are
        // in the binary and the install path runs -- and nothing was visible,
        // which is what a zero-sized button looks like.
        //
        // A fixed size is honest for a debug control whose two titles are known
        // and short.
        //
        // 明確的尺寸，並使用 `.custom` 而非 `.system`。
        //
        // 在 iOS 15 之後，`.system` 按鈕是以 configuration 為基礎的：`contentEdgeInsets` 已棄用且
        // 被忽略，而 `sizeToFit()` 量的是 configuration 而非標題。模擬器上實測：按鈕確實在 view
        // 階層中——其符號存在於執行檔中、安裝路徑也有執行——卻什麼都看不到，而那正是一個尺寸為零的
        // 按鈕的樣子。
        //
        // 對一個「兩個標題都已知且簡短」的 debug 控制項而言，固定尺寸是誠實的做法。
        let button = ViewModeButton(type: .custom)
        button.mode = initial
        button.onToggle = onToggle
        button.setTitle(initial.title, for: .normal)
        button.setTitleColor(.label, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        button.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.9)
        button.layer.borderColor = UIColor.separator.cgColor
        button.layer.borderWidth = 1
        button.layer.cornerRadius = 6
        button.bounds = CGRect(x: 0, y: 0, width: 92, height: 28)
        button.addTarget(button, action: #selector(tapped), for: .touchUpInside)
        button.addGestureRecognizer(
            UIPanGestureRecognizer(target: button, action: #selector(dragged))
        )
        return button
    }

    @objc private func tapped() {
        mode = mode.next
        setTitle(mode.title, for: .normal)
        onToggle?(mode)
    }

    @objc private func dragged(_ gesture: UIPanGestureRecognizer) {
        guard let superview else { return }
        let translation = gesture.translation(in: superview)
        center = CGPoint(x: center.x + translation.x, y: center.y + translation.y)
        gesture.setTranslation(.zero, in: superview)

        // Kept on screen. A button dragged past the edge cannot be dragged
        // back, and it is the only way to change the mode.
        // 保持在畫面內。被拖出邊界的按鈕就拖不回來了，而它是改變模式的唯一途徑。
        let half = bounds.size
        center.x = min(max(center.x, half.width / 2), superview.bounds.width - half.width / 2)
        center.y = min(max(center.y, half.height / 2), superview.bounds.height - half.height / 2)
    }
}
