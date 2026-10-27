import AppKit
import DebugFeatures
import Foundation
import SwiftCrossUI

// `#if SCUI_DEBUG`, matching AppKitBackend.swift, because `InputEvent` is not a
// dependency of this target in a release build. Package.swift builds the list as
// `["SwiftCrossUI"] + (debugFeaturesEnabled ? ["InputEvent"] : [])`, so a plain
// `import InputEvent` compiles wherever the flag is on and fails for anyone
// building without it. The condition is the same one that decides the
// dependency, so the two cannot drift apart.
//
// 使用 `#if SCUI_DEBUG`,與 AppKitBackend.swift 一致,因為在 release 建置中 `InputEvent` 並不是
// 本 target 的相依。Package.swift 是以
// `["SwiftCrossUI"] + (debugFeaturesEnabled ? ["InputEvent"] : [])` 建構那份清單的,因此一個沒有
// 條件的 `import InputEvent` 在旗標開啟時編得過,而對任何未開啟它的人則會失敗。
// 此處的條件與「決定該相依是否存在」的是同一個,因此兩者不會漂移開來。
#if SCUI_DEBUG
    import InputEvent
#endif

extension AppKitBackend: BackendFeatures.HitTesting {
    public func setHitTesting(of widget: Widget, to allowsHitTesting: Bool) {
        if allowsHitTesting {
            AppKitHitTestingRegistry.disabledViews.remove(widget)
        } else {
            AppKitHitTestingRegistry.disabledViews.add(widget)
        }
    }
}

/// Keeps hit-testing state outside widgets because a modifier may receive an
/// AppKit control that this backend did not create as a subclass. Weak storage
/// lets removed view trees disappear without a cleanup pass.
///
/// 將 hit-testing 狀態放在 widget 外部，因為 modifier 可能收到 backend 沒有以
/// subclass 建立的 AppKit control。弱引用儲存可讓移除的 view tree 自動消失，
/// 不需要額外清理流程。
@MainActor
private enum AppKitHitTestingRegistry {
    static let disabledViews = NSHashTable<NSView>.weakObjects()

    static func isDisabled(_ view: NSView, through ancestor: NSView) -> Bool {
        var current: NSView? = view
        while let view = current {
            if disabledViews.contains(view) {
                return true
            }
            if view === ancestor {
                break
            }
            current = view.superview
        }
        return false
    }
}

/// A backend-owned container that can skip a disabled topmost sibling.
/// Returning nil after calling `super.hitTest` is insufficient: AppKit would
/// stop searching and never reach a clickable sibling underneath. Searching
/// children from front to back gives disabled overlays pass-through semantics.
///
/// 這是 backend 自己擁有、能略過上層停用 sibling 的 container。只呼叫
/// `super.hitTest` 後回傳 nil 並不足夠：AppKit 會停止搜尋，永遠不會抵達
/// 下方可點擊的 sibling。由前到後搜尋 children，才能讓停用 overlay 穿透。
///
/// `point` arrives in this view's **superview** coordinate space (the header
/// for `hitTest(_:)` says "a point that is in the coordinate system of the
/// receiver's superview"), and `child.hitTest(_:)` wants a point in the
/// *child's* superview space -- which is this view's own space. So exactly one
/// conversion is needed, at the top, and the same converted point then goes to
/// every child unchanged.
///
/// Two wrong versions are easy to write, and each is right only while this
/// container sits at its superview's origin, which is why fixing one error
/// alone makes it fail differently rather than work:
///
///     let childPoint = convert(point, to: child)      // wrong source space
///     child.hitTest(childPoint)                       // wrong argument space
///
/// With that version `hitTest` returned nil for an NSButton and an NSScrollView
/// at their exact centres while a text field still resolved. For the button at
/// frame (114, 212, 52, 27) and point (140, 225): `childPoint` is (26, 13),
/// inside the button's bounds, and then `button.hitTest((26, 13))` reads it as
/// a point in this container's space, compares it against the frame at
/// x 114...166, y 212...239, and correctly answers nil. Passing `point`
/// unconverted to `child.hitTest` instead makes the text field stop resolving
/// too. Commit e25b3a65 once replaced this implementation with the first wrong
/// version; P21's button then reported `clicks: 0` for a click at its centre
/// and P28's counter stayed at 0, while P26's tab strip still worked.
///
/// `point` 抵達時位於本 view 的 **superview** 座標系(`hitTest(_:)` 的標頭寫的是「位於接收者之
/// superview 座標系中的點」),而 `child.hitTest(_:)` 要的是 child 的 superview 座標系——也就是
/// 本 view 自己的座標系。因此只需要在最上方做一次轉換，之後同一個轉換後的點原封不動交給每一個 child。
///
/// 有兩個很容易寫出來的錯誤版本，而每一個都只在本 container 恰好位於其 superview 原點時才對，這正是
/// 「只修其中一個錯誤」會換一種方式壞掉、而非修好的原因(見上方程式片段)。
///
/// 在那個版本下，對 NSButton 與 NSScrollView 的正中心，`hitTest` 回傳 nil，而文字欄位仍可解析。以
/// frame 為 (114, 212, 52, 27) 的按鈕、點 (140, 225) 推算：`childPoint` 為 (26, 13)，落在該按鈕的
/// bounds 內，接著 `button.hitTest((26, 13))` 把它讀作 container 座標系中的點，拿去與位於
/// x 114...166、y 212...239 的 frame 比對，於是正確地回答了 nil。改為把未轉換的 `point` 直接傳給
/// `child.hitTest`,則連文字欄位也無法解析。commit e25b3a65 曾把本實作換成第一個錯誤版本；當時 P21
/// 的按鈕對其中心的點擊回報 `clicks: 0`、P28 的計數器停在 0,而 P26 的分頁列仍然可用。
final class AppKitHitTestingContainer: NSView {
    /// The transform `setGeometricEffect` last gave this container; nil for one that carries no
    /// effect. Setting it starts watching the frame, because a new frame is when AppKit resets the
    /// layer's transform (see `setGeometricEffect`).
    /// `setGeometricEffect` 最後給這個容器的 transform；沒有效果的容器為 nil。設定它會開始監看 frame，
    /// 因為 AppKit 正是在給新 frame 時重設 layer 的 transform(見 `setGeometricEffect`)。
    var geometricEffect: SwiftCrossUI.AffineTransform? {
        didSet {
            guard geometricEffect != nil, !watchesFrame else { return }
            watchesFrame = true
            postsFrameChangedNotifications = true
            // Selector-based, so the registration goes away with the view. The notification rather
            // than `setFrameSize`/`setFrameOrigin`/`layout()`: Auto Layout sets the frame by a path
            // that calls none of the first two, measured 2026-10-10.
            // 以 selector 註冊，view 釋放時一併移除。用通知而不是覆寫 `setFrameSize`／`setFrameOrigin`／
            // `layout()`：Auto Layout 設定 frame 的路徑不經過前兩者(2026-10-10 實測)。
            NotificationCenter.default.addObserver(
                self, selector: #selector(frameDidChange), name: NSView.frameDidChangeNotification,
                object: self)
        }
    }
    private var watchesFrame = false

    /// On the next turn of the main queue, not here: this runs inside AppKit's layout pass, and a
    /// transform assigned inside the pass is overwritten when the pass ends (measured 2026-10-10:
    /// assigned here it read 0,0 a second later; assigned on the next turn it stayed).
    /// 排到 main queue 的下一輪，而不是在這裡：這裡是在 AppKit 的版面流程之內，流程內指派的 transform
    /// 會在流程結束時被覆寫(2026-10-10 實測：在這裡指派，一秒後讀到 0,0；排到下一輪指派則留得住)。
    @objc private func frameDidChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let effect = self.geometricEffect else { return }
            AppKitBackend.applyGeometricEffect(effect, to: self)
        }
    }

    /// Says where a point landed, when the debug features are on.
    ///
    /// A click that resolves to nothing and a click that lands beside a control
    /// produce the same screen: nothing happens. Working out which, from
    /// outside, means scanning a control's edges one run at a time to
    /// recover the shape of a live region, and the geometry dump cannot help
    /// because it lists
    /// `NSTextField`, `NSButton`, `NSButtonTextField` and `NSScroller` and no
    /// containers, so it cannot show what sits above a control or where a hit
    /// test went.
    ///
    /// This reports the point in three spaces and what answered, because the
    /// interesting failures are conversions between them. `frame` is the
    /// child's rect in this container's coordinates, which is what `hitTest`
    /// compares against; printing it beside the point is what distinguishes
    /// "the point is outside the control" from "the control is not where the
    /// dump says".
    ///
    /// **A reported frame is larger than what the control draws, and reading a
    /// defect out of the difference is easy.** Measured on P45's buttons: the
    /// frame is `104x27`, placed at `(-3,-4)` inside a container 20 points tall,
    /// and the responding band is 20 points -- which looks like a control whose
    /// live region is smaller than the control itself. It is not. The drawn
    /// bezel measures 20.0 points on screen, y 472.0..491.5, against a
    /// responding band of y 473..492: the extra seven points are AppKit's own
    /// invisible margin, and the `(-3,-4)` offset exists to put the visible
    /// bezel on the rect the layout asked for. The live region matches what a
    /// user sees.
    ///
    /// **回報的 frame 大於控制項實際畫出的範圍,而從那個差值讀出一個缺陷是很容易的事。**
    /// 於 P45 的按鈕上實測:frame 為 `104x27`、放置於 `(-3,-4)`、位於一個高 20 點的容器中,而回應
    /// 的帶是 20 點——那看起來就像一個「活區小於控制項本身」的控制項。它不是。畫面上的 bezel 量到
    /// 20.0 點高,y 472.0..491.5,而回應帶是 y 473..492:多出來的那七點是 AppKit 自己的不可見邊距,
    /// 而 `(-3,-4)` 這個偏移正是為了讓看得見的 bezel 落在版面所要求的矩形上。活區與使用者所看到的
    /// 東西一致。
    ///
    /// Gated on `DebugFeatures.isEnabled`, so a release build is silent and a
    /// debug build without `--debug` is too. Written to stderr, unbuffered,
    /// which is the stream the action-file lines already use.
    ///
    /// 在 debug 功能開啟時,說出某一點落到了哪裡。
    ///
    /// 「解析到空無一物的點擊」與「落在控制項旁邊的點擊」會產生相同的畫面:什麼都沒發生。要從外部
    /// 分辨兩者,只能一次一輪地掃描控制項的邊緣,才反推出一個活區的形狀;而幾何傾印幫不上忙,
    /// 因為它只列 `NSTextField`、`NSButton`、
    /// `NSButtonTextField` 與 `NSScroller`,不列容器,因此看不出控制項上方壓著什麼,也看不出命中
    /// 測試走到哪裡。
    ///
    /// 此處以三個座標系回報該點以及是誰回應了它,因為有趣的失敗正是發生在它們之間的轉換上。`frame`
    /// 是子元件在本 container 座標系中的矩形,也正是 `hitTest` 用來比對的東西;把它印在該點旁邊,
    /// 才能區分「該點在控制項之外」與「控制項不在傾印所說的位置」。
    ///
    /// 以 `DebugFeatures.isEnabled` 為條件,因此 release 建置是靜默的,未加 `--debug` 的 debug
    /// 建置也是。寫入 stderr、不緩衝,那正是動作檔各行本來就使用的串流。
    private static func report(_ message: String) {
        guard DebugFeatures.isEnabled else { return }
        FileHandle.standardError.write(Data("-hittest: \(message)\n".utf8))
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0, bounds.width > 0, bounds.height > 0 else {
            Self.report(
                "container refused at \(Self.describe(point)) -- "
                    + "hidden=\(isHidden) alpha=\(alphaValue) bounds=\(Self.describe(bounds))"
            )
            return nil
        }

        // No superview means no conversion to make, and `point` is already in
        // the only space there is.
        // 沒有 superview 就沒有轉換可做，此時 `point` 已位於唯一存在的那個座標系。
        var localPoint = superview.map { convert(point, from: $0) } ?? point
        // Through this container's geometric effect: the layer transform moves
        // what is drawn and `convert` reads only the frame, so the point is
        // taken back through the inverse to where the content lies (the effect
        // is top-left origin, y down).
        // 經過此容器的幾何效果:layer 的變換移動畫出的東西，而 `convert` 只讀 frame,所以把點經由反矩陣帶回內容
        // 所在之處(效果以左上角為原點、y 向下)。
        if let effect = geometricEffect, effect != .identity, let inverse = effect.inverted() {
            let down = isFlipped ? localPoint.y : bounds.height - localPoint.y
            let m = inverse.linearTransform
            let t = inverse.translation
            let x = m.x * Double(localPoint.x) + m.y * Double(down) + t.x
            let y = m.z * Double(localPoint.x) + m.w * Double(down) + t.y
            localPoint = NSPoint(x: x, y: isFlipped ? y : Double(bounds.height) - y)
        }
        guard bounds.contains(localPoint) else {
            // A child drawn moved by its own geometric effect can lie outside
            // this container: it is asked too, and answers only for its drawn
            // rectangle. Measured with P108: a card coasted 126 pt along, inside
            // a 40 pt container, could only be picked up at its layout frame.
            // 由自己的幾何效果移動後畫出的子元件，可能位於此容器之外：也詢問它，而它只對自己畫出的矩形回應。以 P108
            // 量到：在 40 點容器中滑行 126 點的卡片，只能在它的版面 frame 上拿起。
            for child in subviews.reversed() {
                guard let moved = child as? AppKitHitTestingContainer,
                    let effect = moved.geometricEffect, effect != .identity,
                    !moved.isHidden, moved.alphaValue > 0,
                    let candidate = moved.hitTest(localPoint),
                    !AppKitHitTestingRegistry.isDisabled(candidate, through: self)
                else { continue }
                return candidate
            }
            Self.report(
                "outside the container: point \(Self.describe(point)) -> local "
                    + "\(Self.describe(localPoint)), bounds \(Self.describe(bounds))"
            )
            return nil
        }

        for child in subviews.reversed() {
            guard !child.isHidden, child.alphaValue > 0 else { continue }
            // No containment check of our own: `hitTest` already answers nil
            // for a point outside the child, and it accounts for the child's
            // own overrides, which a `frame.contains` here would not.
            // 不再自行做 containment 檢查：對落在 child 之外的點，`hitTest` 本來就會回答 nil，
            // 而且它會把 child 自己的覆寫也算進去——那是在此處寫 `frame.contains` 做不到的。
            guard let candidate = child.hitTest(localPoint) else { continue }

            if !AppKitHitTestingRegistry.isDisabled(candidate, through: self) {
                // `actionFileRect` as well as the local frame, because those two
                // answer different questions and a reader needs both. The frame
                // is what `hitTest` compared against, in this container's space;
                // `click` is where an action file must aim, in the space action
                // files are written in. A dump that prints one and labels it the
                // other sends action files outside the control, and a click that
                // lands on nothing raises nothing.
                //
                // 除了本地 frame 之外也印出 `actionFileRect`,因為兩者回答的是不同的問題,而讀者
                // 兩個都需要。frame 是 `hitTest` 用來比對的東西,位於本 container 的座標系;而
                // `click` 是動作檔應該瞄準的位置,位於動作檔所使用的那個座標系。一份「印了其中一個、
                // 卻標上另一個名字」的傾印,會讓動作檔點在控制項外面,而點在空處不會引發任何錯誤。
                var aim = ""
                #if SCUI_DEBUG
                    // The two window origins go out beside the rect, because the
                    // rect alone cannot be written into an action file: a file's
                    // x and y are relative to `origin=frame` or `origin=client`,
                    // and this is absolute. A caller has to subtract one of
                    // them, and the subtraction is where a reader and this
                    // function can silently disagree -- so both are printed and
                    // neither has to be assumed.
                    //
                    // 兩個視窗原點與該矩形一併輸出,因為單憑那個矩形無法寫進動作檔:檔案裡的 x 與 y
                    // 是相對於 `origin=frame` 或 `origin=client` 的,而此處是絕對座標。呼叫端必須
                    // 減去其中之一,而那次相減正是「讀者」與「本函式」可能靜默地各說各話的地方——
                    // 因此兩者都印出來,誰也不必用猜的。
                    // `rect` for the origin and `click` for the centre, each
                    // named. A name is more reliable than a format: a pair of
                    // numbers followed by a size reads as an origin whatever it
                    // is, and an origin used as a click target aims at the
                    // top-left corner, outside the drawn bezel.
                    //
                    // `rect` 表示原點、`click` 表示中心,各自具名。名字比格式可靠:一對數字後面接著尺寸,
                    // 無論它是什麼,讀起來都像原點;而把原點當成點擊目標,瞄準的會是左上角,落在畫出來的
                    // bezel 之外。
                    let rect = AppKitSynthesiser.actionFileRect(of: candidate)
                    aim = " rect \(Int(rect.x.rounded())),\(Int(rect.y.rounded()))"
                        + " size \(Int(rect.width.rounded()))x\(Int(rect.height.rounded()))"
                        + " click \(Int((rect.x + rect.width / 2).rounded()))"
                        + ",\(Int((rect.y + rect.height / 2).rounded()))"
                    if let geometry = try? AppKitSynthesiser().currentWindowGeometry() {
                        aim += " frame-origin \(Int(geometry.frameOrigin.x.rounded()))"
                            + ",\(Int(geometry.frameOrigin.y.rounded()))"
                            + " client-origin \(Int(geometry.clientOrigin.x.rounded()))"
                            + ",\(Int(geometry.clientOrigin.y.rounded()))"
                    }
                #endif
                Self.report(
                    "hit \(type(of: candidate)) at \(Self.describe(localPoint)) "
                        + "in child \(type(of: child)) frame \(Self.describe(child.frame))"
                        + aim
                )
                return candidate
            }
            Self.report(
                "\(type(of: candidate)) answered at \(Self.describe(localPoint)) but "
                    + "allowsHitTesting is off for it"
            )
        }

        // Reached only when no child answered, which is the case a screenshot
        // cannot tell from a control that ignored the press. Every child's
        // frame is listed, because the useful comparison is the point against
        // the rects that were actually tested.
        // 只有在沒有任何 child 回應時才會走到這裡,而那正是螢幕截圖無法與「控制項忽略了該次按下」
        // 區分的情況。此處列出每一個 child 的 frame,因為有用的比較是「該點」對上「實際被測試的
        // 那些矩形」。
        let rects = subviews
            .filter { !$0.isHidden && $0.alphaValue > 0 }
            .map { "\(type(of: $0))\(Self.describe($0.frame))" }
            .joined(separator: " ")
        Self.report(
            "nothing at \(Self.describe(localPoint)) among \(subviews.count) children: \(rects)"
        )
        return nil
    }

    private static func describe(_ point: NSPoint) -> String {
        "(\(Int(point.x.rounded())),\(Int(point.y.rounded())))"
    }

    private static func describe(_ rect: NSRect) -> String {
        "(\(Int(rect.minX.rounded())),\(Int(rect.minY.rounded()))"
            + " \(Int(rect.width.rounded()))x\(Int(rect.height.rounded())))"
    }
}
