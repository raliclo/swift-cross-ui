import AppKit
import SwiftCrossUI

extension AppKitBackend: BackendFeatures.DragGestures,
    BackendFeatures.MagnifyGestures,
    BackendFeatures.RotateGestures
{
    public func createDragGestureTarget(wrapping child: Widget) -> Widget {
        NSContinuousGestureTarget(wrapping: child, kind: .drag)
    }

    public func updateDragGestureTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (DragGestureValue) -> Void,
        onEnd: @escaping (DragGestureValue) -> Void
    ) {
        let target = target as! NSContinuousGestureTarget
        target.isEnabled = environment.isEnabled
        target.onDragChange = onChange
        target.onDragEnd = onEnd
    }

    public func createMagnifyGestureTarget(wrapping child: Widget) -> Widget {
        NSContinuousGestureTarget(wrapping: child, kind: .magnify)
    }

    public func updateMagnifyGestureTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (MagnifyGestureValue) -> Void,
        onEnd: @escaping (MagnifyGestureValue) -> Void
    ) {
        let target = target as! NSContinuousGestureTarget
        target.isEnabled = environment.isEnabled
        target.onMagnifyChange = onChange
        target.onMagnifyEnd = onEnd
    }

    public func createRotateGestureTarget(wrapping child: Widget) -> Widget {
        NSContinuousGestureTarget(wrapping: child, kind: .rotate)
    }

    public func updateRotateGestureTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (RotateGestureValue) -> Void,
        onEnd: @escaping (RotateGestureValue) -> Void
    ) {
        let target = target as! NSContinuousGestureTarget
        target.isEnabled = environment.isEnabled
        target.onRotateChange = onChange
        target.onRotateEnd = onEnd
    }
}

/// One view that hosts whichever recogniser it was asked for.
///
/// **One class for three gestures, because the wrapping is the whole of what
/// they share and it is the fiddly part**: the child is pinned to this view's
/// edges and this view has to stay the same size as the child, which is three
/// identical blocks of constraint code if written out per gesture.
///
/// The recognisers themselves are AppKit's own -- `NSPanGestureRecognizer`,
/// `NSMagnificationGestureRecognizer`, `NSRotationGestureRecognizer` -- and each
/// reports differently, which is where the per-gesture code lives.
///
/// 一個 view，掛載它被要求的那一種辨識器。
///
/// **三種手勢共用一個類別，因為「包裝」就是它們共有的全部，而那正是瑣碎的那一部分**:子節點被釘在
/// 這個 view 的四邊，而這個 view 必須與子節點維持同樣大小——若逐手勢寫出來，那會是三段一模一樣的
/// 約束程式碼。
///
/// 辨識器本身則是 AppKit 自己的——`NSPanGestureRecognizer`、`NSMagnificationGestureRecognizer`、
/// `NSRotationGestureRecognizer`——而它們各自的回報方式不同，逐手勢的程式碼就在那裡。
final class NSContinuousGestureTarget: NSView {
    enum Kind {
        case drag
        case magnify
        case rotate
    }

    var isEnabled = true
    var onDragChange: ((DragGestureValue) -> Void)?
    var onDragEnd: ((DragGestureValue) -> Void)?
    var onMagnifyChange: ((MagnifyGestureValue) -> Void)?
    var onMagnifyEnd: ((MagnifyGestureValue) -> Void)?
    var onRotateChange: ((RotateGestureValue) -> Void)?
    var onRotateEnd: ((RotateGestureValue) -> Void)?

    private var dragStart: NSPoint = .zero

    init(wrapping child: NSView, kind: Kind) {
        super.init(frame: .zero)

        addSubview(child)
        child.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: leadingAnchor),
            child.topAnchor.constraint(equalTo: topAnchor),
        ])

        switch kind {
            case .drag:
                addGestureRecognizer(
                    NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
                )
            case .magnify:
                addGestureRecognizer(
                    NSMagnificationGestureRecognizer(
                        target: self,
                        action: #selector(handleMagnify(_:))
                    )
                )
            case .rotate:
                addGestureRecognizer(
                    NSRotationGestureRecognizer(target: self, action: #selector(handleRotate(_:)))
                )
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// AppKit's y grows upward and every coordinate this package reports grows
    /// downward, so this view is flipped rather than each handler subtracting.
    /// One place to be wrong instead of three.
    /// AppKit 的 y 向上增加，而本套件回報的每一個座標都是向下增加的，因此把這個 view 設為 flipped，
    /// 而不是讓每個 handler 各自去減。錯只會錯在一個地方，而不是三個。
    override var isFlipped: Bool { true }

    @objc private func handlePan(_ recogniser: NSPanGestureRecognizer) {
        guard isEnabled else { return }
        let location = recogniser.location(in: self)
        switch recogniser.state {
            case .began:
                // The press point, worked back from the translation, NOT the
                // location at `.began`.
                //
                // A pan recogniser does not begin until the pointer has moved
                // past its slop threshold, so `location` here is already a few
                // points into the drag. Measured 2026-09-10 on a drag posted
                // from (150, 290) to (230, 320): recording `location` gave a
                // start of (80, 42) where the press was at (70, 38), and every
                // translation was short by exactly that much. `translation(in:)`
                // is measured from the press, so subtracting it recovers the
                // point the recogniser will not tell us directly.
                //
                // 按下的那個點，由 translation 反推而得，**而不是** `.began` 當下的 location。
                //
                // 一個 pan 辨識器要等指標移動超過它的 slop 門檻才會開始，因此此處的 `location` 已經
                // 進入拖曳幾個點了。2026-09-10 量測:一次由 (150, 290) 拖到 (230, 320) 的合成拖曳，
                // 記錄 `location` 得到的起點是 (80, 42)，而實際按下處是 (70, 38)——每一次的 translation
                // 都正好短少那麼多。`translation(in:)` 是從按下處量起的，因此減掉它，就能取回那個
                // 辨識器不會直接告訴我們的點。
                let offset = recogniser.translation(in: self)
                dragStart = NSPoint(x: location.x - offset.x, y: location.y - offset.y)
            case .changed:
                onDragChange?(value(at: location))
            case .ended, .cancelled:
                onDragEnd?(value(at: location))
            default:
                break
        }
    }

    private func value(at location: NSPoint) -> DragGestureValue {
        DragGestureValue(
            startLocation: SIMD2(Double(dragStart.x), Double(dragStart.y)),
            location: SIMD2(Double(location.x), Double(location.y))
        )
    }

    @objc private func handleMagnify(_ recogniser: NSMagnificationGestureRecognizer) {
        guard isEnabled else { return }
        // AppKit's `magnification` is a DELTA from 1 -- 0 means unchanged, 0.5
        // means half again -- while this package reports a factor where 1 means
        // unchanged. The conversion is `1 + magnification`, and getting it
        // backwards produces a picture that shrinks when the fingers spread,
        // which reads as an inverted sign rather than a unit mismatch.
        // AppKit 的 `magnification` 是「相對於 1 的差量」——0 表示未改變、0.5 表示再放大一半——而本套件
        // 回報的是一個「1 表示未改變」的倍率。換算是 `1 + magnification`，而把它弄反會產生「兩指張開
        // 時畫面縮小」的結果——那讀起來像是正負號顛倒，而不像單位不合。
        let magnification = 1 + Double(recogniser.magnification)
        switch recogniser.state {
            case .changed:
                onMagnifyChange?(MagnifyGestureValue(magnification: magnification))
            case .ended, .cancelled:
                onMagnifyEnd?(MagnifyGestureValue(magnification: magnification))
            default:
                break
        }
    }

    @objc private func handleRotate(_ recogniser: NSRotationGestureRecognizer) {
        guard isEnabled else { return }
        // `rotation` is radians, counter-clockwise positive, and this package
        // reports clockwise positive -- hence the negation. AppKit is the only
        // one of the three Apple recognisers here that disagrees with the
        // package's own convention.
        // `rotation` 的單位是弧度、逆時針為正，而本套件回報的是順時針為正——因此取負。在此處的三個
        // Apple 辨識器中，AppKit 這一個是唯一與本套件自身慣例不一致的。
        let radians = -Double(recogniser.rotation)
        switch recogniser.state {
            case .changed:
                onRotateChange?(RotateGestureValue(radians: radians))
            case .ended, .cancelled:
                onRotateEnd?(RotateGestureValue(radians: radians))
            default:
                break
        }
    }
}
