import AppKit
import SwiftCrossUI

extension AppKitBackend: BackendFeatures.ScrollGestures {
    public func createScrollGestureTarget(wrapping child: Widget) -> Widget {
        NSScrollGestureTarget(wrapping: child)
    }

    public func updateScrollGestureTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (ScrollGestureValue) -> Void,
        onEnd: @escaping (ScrollGestureValue) -> Void
    ) {
        let target = target as! NSScrollGestureTarget
        target.isEnabled = environment.isEnabled
        target.onChange = onChange
        target.onEnd = onEnd
    }
}

/// A view that receives `scrollWheel(with:)` and reports it.
///
/// **Not a gesture recogniser, because AppKit has no scroll recogniser.** Every
/// other continuous gesture in this backend is an `NS*GestureRecognizer`;
/// scrolling is delivered as an `NSEvent` to the view under the pointer and
/// nowhere else. That is also why this wraps rather than attaches: the wrapper
/// is what sits in the responder chain at the right place.
///
/// 一個會收到 `scrollWheel(with:)` 並把它回報出去的 view。
///
/// **不是手勢辨識器,因為 AppKit 沒有捲動辨識器。** 這個 backend 裡其他每一個連續手勢都是一個
/// `NS*GestureRecognizer`;而捲動是以 `NSEvent` 的形式,送到指標底下的那個 view,除此之外哪裡都不送。
/// 那也是這裡採「包裝」而非「附掛」的理由:那個包裝才是坐在 responder chain 正確位置上的東西。
final class NSScrollGestureTarget: NSView {
    var isEnabled = true
    var onChange: ((ScrollGestureValue) -> Void)?
    var onEnd: ((ScrollGestureValue) -> Void)?

    private var translation = SIMD2<Double>(0, 0)
    private var isScrolling = false

    init(wrapping child: NSView) {
        super.init(frame: .zero)
        addSubview(child)
        child.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: leadingAnchor),
            child.topAnchor.constraint(equalTo: topAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// Flipped for the same reason `NSContinuousGestureTarget` is: this package
    /// reports y growing downward and AppKit's grows upward.
    /// 與 `NSContinuousGestureTarget` 設為 flipped 的理由相同:本套件回報的 y 向下增加,而 AppKit 的向上。
    override var isFlipped: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        guard isEnabled else {
            super.scrollWheel(with: event)
            return
        }

        // **`scrollingDeltaY` is positive when the content should move BACKWARD,
        // which is the opposite of what `ScrollGestureValue` defines, so it is
        // negated.** AppKit's sign follows the physical direction of the fingers
        // or the wheel; this package's follows the content. Both are defensible
        // and they are opposite, which is exactly the kind of thing that must be
        // decided in one place rather than in five backends.
        //
        // `isDirectionInvertedFromDevice` is already folded into the delta by
        // AppKit when the user has "natural scrolling" on, so it must NOT be
        // applied again here -- doing so would make this view the only one on
        // the machine that ignores that preference.
        //
        // **`scrollingDeltaY` 為正時代表內容應該往後移,而那與 `ScrollGestureValue` 的定義相反,
        // 因此此處取負。** AppKit 的符號跟隨的是手指或滾輪的物理方向,本套件的則跟隨內容。兩者都說得通、
        // 而且彼此相反——那正是那種「必須在一個地方決定、而不是在五個 backend 各自決定」的事。
        //
        // 當使用者開啟「自然捲動」時,AppKit 已經把 `isDirectionInvertedFromDevice` 併入那個 delta 了,
        // 因此這裡**不可以**再套用一次——那會讓這個 view 成為整台機器上唯一不理會該偏好的 view。
        let delta = SIMD2<Double>(
            -Double(event.scrollingDeltaX),
            -Double(event.scrollingDeltaY)
        )

        // A wheel notch arrives with `hasPreciseScrollingDeltas == false` and a
        // delta measured in lines rather than points. Multiplied by AppKit's own
        // line height so that a caller applying `delta` directly gets a sane
        // distance from both devices.
        // 一格滾輪送來時 `hasPreciseScrollingDeltas == false`,而它的 delta 是以「行」而非「點」計。
        // 此處乘上 AppKit 自己的行高,好讓一個直接套用 `delta` 的呼叫端,從兩種裝置都得到合理的距離。
        let isPrecise = event.hasPreciseScrollingDeltas
        let scaled = isPrecise ? delta : delta * Self.pointsPerLine

        switch event.phase {
            case .began:
                translation = .zero
                isScrolling = true
            case .ended, .cancelled:
                translation += scaled
                report(delta: scaled, isPrecise: isPrecise, ended: true)
                isScrolling = false
                return
            default:
                break
        }

        // A wheel sends no phases at all -- `event.phase` is empty for every
        // notch -- so a target that only reset on `.began` would accumulate one
        // translation for the life of the view. Each notch is its own scroll.
        // 滾輪完全不送 phase——每一格的 `event.phase` 都是空的——因此一個「只在 `.began` 時重設」的
        // target,會在這個 view 的整個生命週期裡累積出同一個 translation。每一格滾輪自成一次捲動。
        if !isPrecise && !isScrolling {
            translation = .zero
        }

        translation += scaled
        report(delta: scaled, isPrecise: isPrecise, ended: false)

        if !isPrecise {
            report(delta: .zero, isPrecise: isPrecise, ended: true)
        }
    }

    private func report(delta: SIMD2<Double>, isPrecise: Bool, ended: Bool) {
        let value = ScrollGestureValue(
            delta: delta,
            translation: translation,
            isPrecise: isPrecise
        )
        if ended {
            onEnd?(value)
        } else {
            onChange?(value)
        }
    }

    /// What one wheel notch is worth, in points.
    ///
    /// AppKit gives no constant for this. 16 is the value `NSScrollView` uses
    /// for a line when nothing overrides it, checked against the distance a
    /// notch moves a plain document scroll view on this machine on 2026-09-19.
    /// It is a convention, not a law, and it is here rather than in five
    /// backends so that a wheel notch means the same thing everywhere.
    ///
    /// 一格滾輪值多少點。
    ///
    /// AppKit 沒有給這個常數。16 是 `NSScrollView` 在無人覆寫時對「一行」所用的值;2026-09-19 在本機上
    /// 對照過「一格滾輪讓一個普通文件 scroll view 移動多遠」。它是一個慣例、不是法律,而它放在這裡、
    /// 不放在五個 backend 裡,是為了讓一格滾輪在每個地方都代表同一件事。
    private static let pointsPerLine: Double = 16
}
