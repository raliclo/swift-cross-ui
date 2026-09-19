import SwiftCrossUI
import UIKit

extension UIKitBackend: BackendFeatures.ScrollGestures {
    public func createScrollGestureTarget(wrapping child: Widget) -> Widget {
        ScrollGestureWidget(child: child)
    }

    public func updateScrollGestureTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (ScrollGestureValue) -> Void,
        onEnd: @escaping (ScrollGestureValue) -> Void
    ) {
        let target = target as! ScrollGestureWidget
        target.isEnabled = environment.isEnabled
        target.onChange = onChange
        target.onEnd = onEnd
    }
}

/// Scrolling on iOS, which has no scroll wheel and two ways to produce one
/// anyway.
///
/// **A pan recogniser with `allowedScrollTypesMask`, not a `UIScrollView`.** A
/// scroll view would move the content itself, which is the thing
/// ``BackendFeatures/ScrollGestures`` exists NOT to do -- the whole point is a
/// view that draws its own content and wants the numbers. `UIPanGestureRecognizer`
/// gained `allowedScrollTypesMask` in iOS 13.4 precisely so a pan can also
/// receive indirect scrolls: a trackpad two-finger scroll or a mouse wheel on
/// iPadOS, and the same on a simulator driven from a Mac.
///
/// **Touch scrolling and indirect scrolling both arrive here, and they are not
/// the same thing.** A finger dragging on glass is `.direct`; a trackpad is
/// `.continuous`; a wheel is `.discrete`. Only the last of those is reported as
/// not precise, because only it arrives in notches -- see ``ScrollGestureValue``
/// for why a caller needs to know.
///
/// iOS 上的捲動:它沒有滾輪,而且仍然有兩種方式產生捲動。
///
/// **用的是帶 `allowedScrollTypesMask` 的 pan 辨識器,不是 `UIScrollView`。** scroll view 會自己去移動
/// 內容,而那正是 ``BackendFeatures/ScrollGestures`` 存在的目的所**排除**的——重點就在於一個「自己畫自己
/// 內容、而且要那些數字」的 view。`UIPanGestureRecognizer` 在 iOS 13.4 取得 `allowedScrollTypesMask`,
/// 正是為了讓一個 pan 也能收到間接捲動:iPadOS 上的觸控板兩指捲動或滑鼠滾輪,以及從 Mac 驅動的模擬器上
/// 的同樣操作。
///
/// **觸控捲動與間接捲動都會送到這裡,而它們不是同一回事。** 手指在玻璃上拖曳是 `.direct`;觸控板是
/// `.continuous`;滾輪是 `.discrete`。其中只有最後一種會被回報為「非精密」,因為只有它是一格一格來的
/// ——呼叫端為何需要知道,見 ``ScrollGestureValue``。
final class ScrollGestureWidget: ContainerWidget {
    var isEnabled = true
    var onChange: ((ScrollGestureValue) -> Void)?
    var onEnd: ((ScrollGestureValue) -> Void)?

    private var lastTranslation: CGPoint = .zero

    override init(child: some WidgetProtocol) {
        super.init(child: child)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleScroll(_:)))
        // **One finger, not two, and the first version had it wrong.** Two
        // fingers is the macOS trackpad idea of a scroll; on a touch screen a
        // scroll view scrolls with one finger, and that is what a person does.
        // This tree's own iOS runner agrees without having been consulted: it
        // turns a `scroll` row into a one-finger `press(forDuration:thenDragTo:)`,
        // so a two-finger requirement meant every scroll row in an iOS action
        // file was delivered and silently ignored -- the app reported nothing
        // and nothing reported why.
        //
        // The cost is that `.onScrollGesture` and `.onDragGesture` cannot both
        // be useful on the same view here. That is already the framework's
        // position: `onDragGesture`'s own documentation says a caller attaches
        // one gesture per view and no more, because there is no recogniser
        // graph to arbitrate between two.
        //
        // **一指,不是兩指,而第一版寫錯了。** 兩指是 macOS 觸控板對「捲動」的想法;在觸控螢幕上,
        // 一個 scroll view 是用**一**指捲動的,而人也是那樣做的。這棵樹自己的 iOS runner 在沒有被徵詢的
        // 情況下也同意這一點:它把一列 `scroll` 轉成一次一指的 `press(forDuration:thenDragTo:)`——
        // 因此「最少兩指」的要求,等於讓 iOS 動作檔裡的每一列 scroll 都被送達、然後被靜默忽略:
        // app 什麼都沒回報,而也沒有任何東西回報為什麼。
        //
        // 代價是 `.onScrollGesture` 與 `.onDragGesture` 在此無法同時在同一個 view 上發揮作用。那本來
        // 就是這個框架的立場:`onDragGesture` 自己的文件寫著「呼叫端每個 view 掛一個手勢,不能更多」,
        // 因為這裡沒有一張辨識器的圖可以在兩者之間仲裁。
        pan.minimumNumberOfTouches = 1
        pan.allowedScrollTypesMask = .all
        child.view.addGestureRecognizer(pan)
    }

    @objc
    private func handleScroll(_ recogniser: UIPanGestureRecognizer) {
        guard isEnabled else { return }

        let total = recogniser.translation(in: recogniser.view)
        // **The recogniser's translation is cumulative, so the per-event delta
        // is a subtraction.** Reporting the cumulative value as `delta` would
        // make a caller that adds up deltas accelerate quadratically, which
        // reads as "scrolling is too fast" rather than as an arithmetic error.
        // **辨識器的 translation 是累計值,因此逐事件的差量要用減的。** 把累計值當成 `delta` 回報,
        // 會讓一個「把 delta 累加起來」的呼叫端以平方加速——那讀起來像「捲動太快」,而不像一個算術錯誤。
        let step = CGPoint(
            x: total.x - lastTranslation.x,
            y: total.y - lastTranslation.y
        )

        // Negated for the same reason AppKit's is: a pan's translation follows
        // the fingers and `ScrollGestureValue` follows the content.
        // 取負的理由與 AppKit 那邊相同:一個 pan 的 translation 跟隨手指,而 `ScrollGestureValue` 跟隨內容。
        let delta = SIMD2<Double>(-Double(step.x), -Double(step.y))
        let translation = SIMD2<Double>(-Double(total.x), -Double(total.y))
        // **Always precise on UIKit, because UIKit does not say.**
        // `UIPanGestureRecognizer` gained `allowedScrollTypesMask` in iOS 13.4
        // so a pan can receive indirect scrolls, and it gained no way to read
        // back which kind arrived: there is no `scrollType` on the recogniser
        // (checked -- it is a compile error), and the `UIEvent` that carries
        // `.scroll` is never handed to the action method. So a notched wheel on
        // an iPad with a mouse is reported here as precise, and a caller that
        // smooths notches will not smooth those.
        //
        // Stated rather than quietly defaulted, because a caller reading
        // `isPrecise == true` would otherwise believe UIKit had told it so.
        // AppKit does tell -- `NSEvent.hasPreciseScrollingDeltas` -- and that
        // asymmetry is the kind of thing worth knowing before relying on the
        // field.
        //
        // **在 UIKit 上一律為 precise,因為 UIKit 不說。** `UIPanGestureRecognizer` 在 iOS 13.4 取得了
        // `allowedScrollTypesMask`(讓一個 pan 能收到間接捲動),卻沒有取得任何「讀回它收到的是哪一種」
        // 的方式:辨識器上沒有 `scrollType`(查證過——那是一個編譯錯誤),而承載 `.scroll` 的那個 `UIEvent`
        // 從來不會被交給 action 方法。因此在一台接了滑鼠的 iPad 上,一格滾輪在此會被回報為 precise,
        // 而一個會平滑化「段落」的呼叫端不會去平滑它們。
        //
        // 此處明說而不是靜默採用預設值,否則一個讀到 `isPrecise == true` 的呼叫端,會以為那是 UIKit 說的。
        // AppKit 是會說的(`NSEvent.hasPreciseScrollingDeltas`),而那個不對稱,正是在倚賴這個欄位之前
        // 值得先知道的事。
        let isPrecise = true

        switch recogniser.state {
            case .began:
                lastTranslation = .zero
                onChange?(
                    ScrollGestureValue(
                        delta: .zero,
                        translation: .zero,
                        isPrecise: isPrecise
                    )
                )
            case .changed:
                lastTranslation = total
                onChange?(
                    ScrollGestureValue(
                        delta: delta,
                        translation: translation,
                        isPrecise: isPrecise
                    )
                )
            case .ended, .cancelled, .failed:
                lastTranslation = .zero
                onEnd?(
                    ScrollGestureValue(
                        delta: delta,
                        translation: translation,
                        isPrecise: isPrecise
                    )
                )
            default:
                break
        }
    }
}
