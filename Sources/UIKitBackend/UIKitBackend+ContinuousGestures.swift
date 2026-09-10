import SwiftCrossUI
import UIKit

extension UIKitBackend: BackendFeatures.DragGestures,
    BackendFeatures.MagnifyGestures,
    BackendFeatures.RotateGestures
{
    public func createDragGestureTarget(wrapping child: Widget) -> Widget {
        ContinuousGestureWidget(child: child, kind: .drag)
    }

    public func updateDragGestureTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (DragGestureValue) -> Void,
        onEnd: @escaping (DragGestureValue) -> Void
    ) {
        let target = target as! ContinuousGestureWidget
        target.isEnabled = environment.isEnabled
        target.onDragChange = onChange
        target.onDragEnd = onEnd
    }

    public func createMagnifyGestureTarget(wrapping child: Widget) -> Widget {
        ContinuousGestureWidget(child: child, kind: .magnify)
    }

    public func updateMagnifyGestureTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (MagnifyGestureValue) -> Void,
        onEnd: @escaping (MagnifyGestureValue) -> Void
    ) {
        let target = target as! ContinuousGestureWidget
        target.isEnabled = environment.isEnabled
        target.onMagnifyChange = onChange
        target.onMagnifyEnd = onEnd
    }

    public func createRotateGestureTarget(wrapping child: Widget) -> Widget {
        ContinuousGestureWidget(child: child, kind: .rotate)
    }

    public func updateRotateGestureTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (RotateGestureValue) -> Void,
        onEnd: @escaping (RotateGestureValue) -> Void
    ) {
        let target = target as! ContinuousGestureWidget
        target.isEnabled = environment.isEnabled
        target.onRotateChange = onChange
        target.onRotateEnd = onEnd
    }
}

/// Hosts one of UIKit's three continuous recognisers.
///
/// The recogniser goes on `child.view`, matching what ``TappableWidget`` does:
/// a `ContainerWidget` is a view controller, and its own view is not the one
/// the child's pixels are in.
///
/// 掛載 UIKit 三種連續辨識器之一。
///
/// 辨識器加在 `child.view` 上，與 ``TappableWidget`` 的做法一致:一個 `ContainerWidget` 是一個
/// view controller，而它自己的 view 並不是子節點像素所在的那一個。
final class ContinuousGestureWidget: ContainerWidget {
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

    private var dragStart: CGPoint = .zero

    init(child: some WidgetProtocol, kind: Kind) {
        super.init(child: child)

        switch kind {
            case .drag:
                child.view.addGestureRecognizer(
                    UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
                )
            case .magnify:
                child.view.addGestureRecognizer(
                    UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
                )
            case .rotate:
                child.view.addGestureRecognizer(
                    UIRotationGestureRecognizer(target: self, action: #selector(handleRotate(_:)))
                )
        }
    }

    @objc private func handlePan(_ recogniser: UIPanGestureRecognizer) {
        guard isEnabled else { return }
        let location = recogniser.location(in: child.view)
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
                let offset = recogniser.translation(in: child.view)
                dragStart = CGPoint(x: location.x - offset.x, y: location.y - offset.y)
            case .changed:
                onDragChange?(value(at: location))
            case .ended, .cancelled:
                onDragEnd?(value(at: location))
            default:
                break
        }
    }

    private func value(at location: CGPoint) -> DragGestureValue {
        DragGestureValue(
            startLocation: SIMD2(Double(dragStart.x), Double(dragStart.y)),
            location: SIMD2(Double(location.x), Double(location.y))
        )
    }

    @objc private func handlePinch(_ recogniser: UIPinchGestureRecognizer) {
        guard isEnabled else { return }
        // `scale` is ALREADY a factor where 1 means unchanged, unlike AppKit's
        // `magnification`, which is a delta from 1. The two Apple platforms
        // disagree about this and the difference is invisible at rest: both read
        // as "no change" when nothing is happening, and they diverge only once
        // the fingers move.
        // `scale` **本來就**是一個「1 表示未改變」的倍率，這與 AppKit 的 `magnification`(相對於 1 的
        // 差量)不同。兩個 Apple 平台在這件事上並不一致，而這個差別在靜止時看不出來:什麼都沒發生時
        // 兩者都讀作「沒有改變」，只有在手指開始移動之後才會分歧。
        let magnification = Double(recogniser.scale)
        switch recogniser.state {
            case .changed:
                onMagnifyChange?(MagnifyGestureValue(magnification: magnification))
            case .ended, .cancelled:
                onMagnifyEnd?(MagnifyGestureValue(magnification: magnification))
            default:
                break
        }
    }

    @objc private func handleRotate(_ recogniser: UIRotationGestureRecognizer) {
        guard isEnabled else { return }
        // Clockwise positive already, unlike AppKit's. No negation here, and
        // that asymmetry between two Apple backends is the reason each of these
        // three handlers says which convention it found rather than assuming a
        // shared one.
        // 本來就是順時針為正，與 AppKit 不同。此處不取負;而「兩個 Apple backend 之間的這種不對稱」，
        // 正是這三個 handler 各自寫明「它遇到的是哪一種慣例」、而不是假設有一套共通慣例的原因。
        let radians = Double(recogniser.rotation)
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
