import SwiftCrossUI
import UIKit

/// **Still not driven on 2026-09-22, and the reason is now precise rather than "no pointer".**
///
/// Two things are needed and this host has neither. A pointer device: the iPhone simulator has
/// none, `xcrun simctl ui` has no pointer option, and the Simulator's "Send Pointer to Device"
/// is a menu item with no preference key found. And a way to ask the platform what it WOULD show:
/// Android has one -- `View.onResolvePointerIcon`, which is how
/// `AndroidBackend+Cursors.swift` got verified with no pointer at all -- and iOS does not. There
/// is no query on `UIPointerInteraction`; the entire decision lives in the delegate below, so
/// calling it would be this file asking itself.
///
/// So the honest state is: the mapping is here, the interaction is installed, and nothing has
/// exercised iPadOS's side of it. What would: an iPad (or an iPad simulator with Send Pointer to
/// Device switched on by hand), the pointer moved over the mesh view, and
/// `xcrun simctl io <device> screenshot` -- iPadOS draws its own pointer into the frame buffer, so
/// unlike macOS a plain capture would contain it.
///
/// **2026-09-22 仍未被驅動,而理由現在是精確的、不再只是「沒有指標」。**
///
/// 需要兩樣東西,而這台主機兩樣都沒有。其一是**指標裝置**:iPhone 模擬器沒有,`xcrun simctl ui` 沒有
/// 指標選項,而 Simulator 的「Send Pointer to Device」是一個選單項目、找不到對應的偏好設定鍵。
/// 其二是**向平台詢問「你會顯示什麼」的方法**:Android 有——`View.onResolvePointerIcon`,
/// `AndroidBackend+Cursors.swift` 正是靠它在完全沒有指標的情況下完成驗證——而 iOS 沒有。
/// `UIPointerInteraction` 上沒有任何查詢;整個決定都住在下面那個 delegate 裡,因此去呼叫它,
/// 等於本檔在問它自己。
///
/// 因此誠實的狀態是:對照表在這裡、interaction 有裝上,而 iPadOS 那一側沒有任何東西驗證過。
/// 什麼能驗:一台 iPad(或一台由人手動開啟 Send Pointer to Device 的 iPad 模擬器),把指標移到
/// mesh view 上,然後 `xcrun simctl io <device> screenshot`——iPadOS 會把它自己的指標畫進 frame
/// buffer,因此與 macOS 不同,一張普通的擷圖就會含有它。
extension UIKitBackend: BackendFeatures.Cursors {
    public func createCursorTarget(wrapping child: Widget) -> Widget {
        CursorWidget(child: child)
    }

    public func updateCursorTarget(
        _ target: Widget,
        cursor: Cursor,
        environment: EnvironmentValues
    ) {
        let target = target as! CursorWidget
        target.cursor = cursor
    }
}

/// The pointer over a view on iPadOS.
///
/// **UIKit has no cursor set, and that is the whole difficulty.** AppKit,
/// GTK, WinUI and Android all hand you a named system cursor -- crosshair,
/// I-beam, resize, not-allowed. iPadOS instead has a pointer that MORPHS: a
/// `UIPointerStyle` is an effect over a view plus a shape, and the shapes on
/// offer are a beam, a rounded rectangle and an arbitrary `UIBezierPath`. There
/// is no `UIPointerShape.crosshair`. Checked rather than assumed: the shape
/// cases in the iOS 27 SDK are `path`, `roundedRect`, `beam`, `verticalBeam`
/// and `horizontalBeam`.
///
/// So each case maps to the nearest thing iPadOS actually has, and the ones that
/// are drawn are drawn rather than quietly turned into a rectangle:
///
/// | ``Cursor``          | iPadOS |
/// | --- | --- |
/// | `arrow`             | no style: the system pointer |
/// | `pointingHand`      | `.highlight` effect, which is what iPadOS does over a control |
/// | `text`              | `.verticalBeam`, the shape iPadOS uses over text |
/// | `crosshair`         | a drawn path |
/// | `resizeHorizontal`  | a drawn path |
/// | `resizeVertical`    | a drawn path |
/// | `notAllowed`        | a drawn path |
///
/// **On iPhone this does nothing, and that is correct.** There is no pointer to
/// shape. `UIPointerInteraction` is inert without a pointing device, so the
/// modifier costs nothing and needs no branch in the caller.
///
/// iPadOS 上一個 view 上方的指標。
///
/// **UIKit 沒有游標集合,而那正是全部的難處。** AppKit、GTK、WinUI 與 Android 都交給你一個具名的系統
/// 游標——十字、I 形、縮放、禁止。iPadOS 給的則是一個會**變形**的指標:一個 `UIPointerStyle` 是
/// 「一個作用在 view 上的效果」加上「一個形狀」,而可用的形狀只有 beam、圓角矩形,以及任意的
/// `UIBezierPath`。**沒有** `UIPointerShape.crosshair`。這是查證過、不是假設的:iOS 27 SDK 裡的形狀
/// case 是 `path`、`roundedRect`、`beam`、`verticalBeam`、`horizontalBeam`。
///
/// 因此每個 case 都對應到 iPadOS 真正有的最接近之物;而需要用畫的,就真的用畫的,而不是靜默地變成
/// 一個矩形(對應表見上方英文區塊)。
///
/// **在 iPhone 上這什麼也不做,而那是對的。** 那裡沒有指標可以塑形。`UIPointerInteraction` 在沒有
/// 指向裝置時是惰性的,因此這個 modifier 不花任何成本,呼叫端也不需要為它分支。
final class CursorWidget: ContainerWidget {
    var cursor: Cursor = .arrow

    override init(child: some WidgetProtocol) {
        super.init(child: child)
        // On `view`, not on `self`: a `ContainerWidget` is a view controller,
        // not a view, and an interaction belongs to the view.
        // 加在 `view` 上而不是 `self` 上:`ContainerWidget` 是一個 view controller、不是 view,
        // 而 interaction 屬於 view。
        view.addInteraction(UIPointerInteraction(delegate: self))
    }
}

extension CursorWidget: UIPointerInteractionDelegate {
    func pointerInteraction(
        _ interaction: UIPointerInteraction,
        styleFor region: UIPointerRegion
    ) -> UIPointerStyle? {
        let targeted = UITargetedPreview(view: view)
        switch cursor {
            case .arrow:
                return nil
            case .pointingHand:
                return UIPointerStyle(effect: .highlight(targeted))
            case .text:
                return UIPointerStyle(
                    shape: .verticalBeam(length: 24),
                    constrainedAxes: []
                )
            case .crosshair:
                return UIPointerStyle(shape: .path(Self.crosshairPath()))
            case .resizeHorizontal:
                return UIPointerStyle(shape: .path(Self.arrowsPath(horizontal: true)))
            case .resizeVertical:
                return UIPointerStyle(shape: .path(Self.arrowsPath(horizontal: false)))
            case .notAllowed:
                return UIPointerStyle(shape: .path(Self.notAllowedPath()))
        }
    }

    /// The shapes, drawn around the origin because `UIPointerShape.path` centres
    /// the path on the pointer. A path drawn from (0,0) outward is offset by
    /// half its size, which looks like a cursor with a wrong hotspot rather than
    /// like a drawing mistake.
    /// 這些形狀以原點為中心繪製,因為 `UIPointerShape.path` 會把路徑對齊到指標中心。一條由 (0,0) 向外
    /// 畫出的路徑會偏移它自身的一半——那看起來像「熱點不對的游標」,而不像一個繪圖錯誤。
    private static func crosshairPath() -> UIBezierPath {
        let arm: CGFloat = 9
        let thickness: CGFloat = 1.5
        let path = UIBezierPath(
            rect: CGRect(x: -arm, y: -thickness / 2, width: arm * 2, height: thickness)
        )
        path.append(
            UIBezierPath(
                rect: CGRect(x: -thickness / 2, y: -arm, width: thickness, height: arm * 2)
            )
        )
        return path
    }

    private static func arrowsPath(horizontal: Bool) -> UIBezierPath {
        let long: CGFloat = 9
        let head: CGFloat = 4
        let thickness: CGFloat = 1.5
        let path = UIBezierPath()
        if horizontal {
            path.append(
                UIBezierPath(
                    rect: CGRect(x: -long, y: -thickness / 2, width: long * 2, height: thickness)
                )
            )
            for direction in [CGFloat(-1), 1] {
                path.move(to: CGPoint(x: long * direction, y: 0))
                path.addLine(to: CGPoint(x: (long - head) * direction, y: -head))
                path.addLine(to: CGPoint(x: (long - head) * direction, y: head))
                path.close()
            }
        } else {
            path.append(
                UIBezierPath(
                    rect: CGRect(x: -thickness / 2, y: -long, width: thickness, height: long * 2)
                )
            )
            for direction in [CGFloat(-1), 1] {
                path.move(to: CGPoint(x: 0, y: long * direction))
                path.addLine(to: CGPoint(x: -head, y: (long - head) * direction))
                path.addLine(to: CGPoint(x: head, y: (long - head) * direction))
                path.close()
            }
        }
        return path
    }

    private static func notAllowedPath() -> UIBezierPath {
        let radius: CGFloat = 8
        let path = UIBezierPath(
            ovalIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)
        )
        path.append(
            UIBezierPath(
                ovalIn: CGRect(
                    x: -radius + 2,
                    y: -radius + 2,
                    width: (radius - 2) * 2,
                    height: (radius - 2) * 2
                )
            )
        )
        path.usesEvenOddFillRule = true
        let bar = UIBezierPath()
        let reach = radius * 0.62
        bar.move(to: CGPoint(x: -reach, y: reach))
        bar.addLine(to: CGPoint(x: reach, y: -reach))
        bar.lineWidth = 2
        path.append(bar.cgPath.copy(
            strokingWithWidth: 2,
            lineCap: .butt,
            lineJoin: .miter,
            miterLimit: 10
        ).asBezierPath)
        return path
    }
}

extension CGPath {
    fileprivate var asBezierPath: UIBezierPath { UIBezierPath(cgPath: self) }
}
