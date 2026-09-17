package dev.swiftcrossui.androidbackend

import android.app.Activity
import android.widget.PopupWindow

/// A `PopupWindow` that remembers which side of its anchor it was asked for.
///
/// **The field is here because a `PopupWindow` has nowhere to put it.** #109's
/// preference is set on the popover object before the popover is shown, and
/// `PopupWindow` -- unlike `GtkPopover.position` or `Flyout.placement` -- has no
/// property for a placement at all: the side is decided by the arguments to
/// `showAsDropDown`, which are spent at presentation time. Keeping it on a
/// subclass gives the Swift side one object to set it on and one to read it
/// from, rather than a table keyed by something with no stable identity across
/// the JNI boundary.
///
/// The edge is an `Int` rather than an enum because `SwiftAction` and every
/// other bridge in this backend carries primitives; `AndroidBackend+Popover.swift`
/// holds the only mapping.
///
/// 一個會記住「它被要求出現在錨點哪一側」的 `PopupWindow`。
///
/// **這個欄位放在此處,是因為 `PopupWindow` 沒有地方可以放它。** #109 的偏好是在 popover 被顯示之前
/// 設在 popover 物件上的,而 `PopupWindow`——不同於 `GtkPopover.position` 或 `Flyout.placement`
/// ——根本沒有任何表示位置的屬性:那一側是由 `showAsDropDown` 的引數決定的,而那些引數要到呈現時才花掉。
/// 把它放在一個子類別上,讓 Swift 那側有一個物件可設、也有一個物件可讀,而不必維護一張「以某個跨越 JNI
/// 邊界後並不穩定的東西為鍵」的表。
///
/// 這個邊是 `Int` 而不是 enum,因為 `SwiftAction` 與本 backend 的每一個橋接都只帶原生型別;
/// 唯一的對應表在 `AndroidBackend+Popover.swift` 裡。
class CustomPopupWindow(activity: Activity) : PopupWindow(activity) {
    companion object {
        const val EDGE_PLATFORM = 0
        const val EDGE_TOP = 1
        const val EDGE_BOTTOM = 2
        const val EDGE_LEADING = 3
        const val EDGE_TRAILING = 4
    }

    var preferredEdge: Int = EDGE_PLATFORM
}
