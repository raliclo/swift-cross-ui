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
/// **What was verified on 2026-09-21, and what was not.** VERIFIED: the
/// conformance is taken and the call runs. Before this file, `CursorDegradation`
/// logged `AndroidBackend does not implement BackendFeatures.Cursors` on every
/// launch of P72; after it that line is gone from logcat while the warnings for
/// `Mesh3DViews`, `ScrollGestures` and `KeyEvents` are still there, and
/// `try! JavaClass<PointerIcon>()` would have trapped had the class or the
/// static fields been missing. NOT VERIFIED: the shape the pointer takes. The
/// AVD has no pointer device at all -- `dumpsys input`'s Event Hub lists
/// `gpio-keys` and twelve `virtio_input_multi_touch_*` and nothing else,
/// `MousePointerControllers` is empty, and three attempts to register a virtual
/// mouse through `uinput` (as root and as shell) produced no device. With no
/// `PointerController` there is no sprite to draw and nothing to photograph.
/// Seeing the crosshair needs an Android device or emulator with a real mouse.
///
/// **2026-09-21 驗證了什麼、沒驗證什麼。** **已驗證**:這個 conformance 有被採用,而且那次呼叫真的執行了。
/// 在本檔存在之前,`CursorDegradation` 會在 P72 每次啟動時印出
/// `AndroidBackend does not implement BackendFeatures.Cursors`;在本檔之後,logcat 裡那一行消失了,
/// 而 `Mesh3DViews`、`ScrollGestures`、`KeyEvents` 的警告仍在;而且若該類別或那些靜態欄位不存在,
/// `try! JavaClass<PointerIcon>()` 早就會 trap。**未驗證**:指標實際呈現的形狀。這個 AVD 根本沒有指標裝置
/// ——`dumpsys input` 的 Event Hub 只列出 `gpio-keys` 與十二個 `virtio_input_multi_touch_*`,
/// `MousePointerControllers` 是空的,而三次以 `uinput`(root 與 shell 各試)註冊虛擬滑鼠都沒有產生裝置。
/// 沒有 `PointerController` 就沒有 sprite 可畫,也就沒有東西可拍。要看到那個十字,需要一台帶真滑鼠的
/// Android 裝置或模擬器。
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
