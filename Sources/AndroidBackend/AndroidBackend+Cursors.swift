import AndroidKit
import SwiftJava

@_spi(Backends) import SwiftCrossUI

/// `.cursor(_:)` on Android.
///
/// **A phone has no pointer and this is still not dead code.** Android has run
/// on devices with a mouse since Chromebooks got the Play Store, and since
/// Android 10 on a phone in desktop mode or with a Bluetooth mouse attached; the
/// emulator delivers one too. `PointerIcon` exists precisely for that hardware,
/// and on a device with no pointer `setPointerIcon` is recorded and never
/// resolved -- which is what ``View/cursor(_:)`` documents as "does nothing on a
/// device with no pointer".
///
/// **The target is the child itself, not a wrapper, and Android's resolution
/// order is why that works.** `ViewGroup.onResolvePointerIcon` hit-tests down to
/// the child under the pointer, asks it first, and falls back to its own icon
/// when the child has none. So an icon set on a container covers every
/// descendant that has not claimed one, which is exactly the region AppKit gets
/// from a tracking area. A wrapper view would add a layout level for nothing.
///
/// Android 上的 `.cursor(_:)`。
///
/// **手機沒有指標,而這仍然不是死程式碼。** 自從 Chromebook 能裝 Play Store 之後,Android 就跑在帶滑鼠的
/// 裝置上;Android 10 之後,桌面模式或接上藍牙滑鼠的手機也有;模擬器同樣會送出指標。`PointerIcon`
/// 正是為那些硬體而存在;而在沒有指標的裝置上,`setPointerIcon` 只是被記錄下來、永遠不會被解析
/// ——那正是 ``View/cursor(_:)`` 所載明的「在沒有指標的裝置上不做任何事」。
///
/// **目標就是子 view 本身、而不是一層包裝,而 Android 的解析順序正是它可行的理由。**
/// `ViewGroup.onResolvePointerIcon` 會往下 hit-test 到指標底下的那個子 view、先問它,當那個子 view
/// 沒有自己的圖示時才退回自己的。因此設在容器上的圖示,會覆蓋每一個未曾認領圖示的後代——那恰好就是
/// AppKit 從 tracking area 得到的那塊區域。多包一層 view 只會白白多一級排版。
///
/// **VERIFIED a different way on 2026-09-22, and Android is the platform that allows it.**
/// (The day before, this file said NOT VERIFIED and offered only that the conformance was taken:
/// `CursorDegradation`'s warning had stopped appearing in logcat while the ones for `Mesh3DViews`,
/// `ScrollGestures` and `KeyEvents` were still there. True, and not an answer about the cursor.)
/// `View.onResolvePointerIcon(MotionEvent, pointerIndex)` is public, and it is the method Android
/// itself calls to decide. `ViewGroup`'s implementation hit-tests down to the child under the
/// coordinates, asks it, and only then falls back to its own icon -- so posting an
/// ACTION_HOVER_MOVE from SOURCE_MOUSE and reading the answer tests the REGION as well as the
/// shape, with no pointer device anywhere. `actions/android/P72-cursor.csv` reports
/// `cursor at (190, 259) is crosshair` over the mesh view and `none` over the title text, `none`
/// being the null that means "no view here claims an icon" -- which is what confinement looks
/// like. What remains unproved is only the drawing: given a pointer, this resolution is what draws
/// it, and this AVD has no pointer to draw.
///
/// UIKit has no equivalent. There is no "which pointer style would you show at this point" query
/// on iOS: the whole decision lives in the app-supplied `UIPointerInteractionDelegate`, so there
/// is nothing to ask and nothing to compare against. That asymmetry is why Android's cursor row
/// in the coverage matrix can move and UIKit's cannot.
///
/// **2026-09-22 以另一種方式驗證了,而 Android 是允許這麼做的那個平台。**
/// (前一天,本檔寫的是「未驗證」,能提出的只有「這個 conformance 有被採用」:`CursorDegradation`
/// 的警告已從 logcat 消失,而 `Mesh3DViews`、`ScrollGestures`、`KeyEvents` 的警告仍在。那是真的,
/// 但不是一個關於**游標**的答案。)
/// `View.onResolvePointerIcon(MotionEvent, pointerIndex)` 是公開的,而那正是 Android **自己**用來
/// 決定的方法。`ViewGroup` 的實作會往下 hit-test 到座標底下的子 view、問它,之後才退回自己的圖示
/// ——因此投遞一個來自 SOURCE_MOUSE 的 ACTION_HOVER_MOVE 並讀取答案,同時檢驗了**區域**與形狀,
/// 而且完全不需要指標裝置。`actions/android/P72-cursor.csv` 回報:mesh view 上是
/// `cursor at (190, 259) is crosshair`,標題文字上是 `none`——而 `none` 就是那個代表
/// 「此處沒有任何 view 認領圖示」的 null,也正是「被侷限」的樣子。仍未被證明的只剩**繪製**:
/// 有了指標,畫出它的就是這一次解析;而這個 AVD 沒有指標可畫。
///
/// UIKit 沒有對應的東西。iOS 上沒有「你在這一點會顯示哪一種指標樣式」的查詢:整個決定都住在由 app
/// 提供的 `UIPointerInteractionDelegate` 裡,因此沒有東西可問、也沒有東西可比對。那個不對稱,正是
/// Android 的游標那一列在涵蓋矩陣裡動得了、而 UIKit 那一列動不了的原因。
///
extension AndroidBackend: BackendFeatures.Cursors {
    public func createCursorTarget(wrapping child: Widget) -> Widget {
        child
    }

    public func updateCursorTarget(
        _ target: Widget,
        cursor: Cursor,
        environment: EnvironmentValues
    ) {
        target.setPointerIcon(Self.pointerIcon(for: cursor))
    }

    /// **Every case is a real system icon; none of them is a near-miss.**
    /// `TYPE_NO_DROP` is the barred circle Android shows for a rejected drag,
    /// which is the same drawing as AppKit's `operationNotAllowed` and GTK's
    /// `not-allowed`. The two resize arrows are the double-headed ones, not
    /// `TYPE_ALL_SCROLL`. `TYPE_DEFAULT` is deliberately unused: it means "let
    /// the parent decide", and an explicit arrow is what ``Cursor/arrow`` asks
    /// for.
    ///
    /// **每一個 case 都對應一個真正的系統圖示,沒有一個是「差不多的那個」。** `TYPE_NO_DROP` 是 Android
    /// 在拖放被拒絕時顯示的禁止圈,與 AppKit 的 `operationNotAllowed`、GTK 的 `not-allowed` 是同一個
    /// 畫法。兩個縮放箭頭用的是雙向箭頭,不是 `TYPE_ALL_SCROLL`。`TYPE_DEFAULT` 是刻意不用的:
    /// 它的意思是「交給上層決定」,而 ``Cursor/arrow`` 要的是一個明確的箭頭。
    private static func pointerIcon(for cursor: Cursor) -> PointerIcon? {
        let iconClass = try! JavaClass<PointerIcon>()
        let type =
            switch cursor {
                case .arrow: iconClass.TYPE_ARROW
                case .pointingHand: iconClass.TYPE_HAND
                case .crosshair: iconClass.TYPE_CROSSHAIR
                case .text: iconClass.TYPE_TEXT
                case .resizeHorizontal: iconClass.TYPE_HORIZONTAL_DOUBLE_ARROW
                case .resizeVertical: iconClass.TYPE_VERTICAL_DOUBLE_ARROW
                case .notAllowed: iconClass.TYPE_NO_DROP
            }
        return iconClass.getSystemIcon(activity, type)
    }
}
