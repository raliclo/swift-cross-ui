package dev.swiftcrossui.androidbackend

import android.widget.PopupWindow

/// Bridges `PopupWindow.OnDismissListener` to a Swift closure.
///
/// A Kotlin class rather than a `@JavaImplementation` on the Swift side, for the
/// same reason as `CustomMenuItemClickListener`: implementing a Java interface
/// needs a Java class, and swift-java cannot conjure one at runtime.
///
/// 把 `PopupWindow.OnDismissListener` 橋接到一個 Swift closure。
///
/// 之所以寫成 Kotlin 類別、而非在 Swift 端用 `@JavaImplementation`，理由與
/// `CustomMenuItemClickListener` 相同：實作一個 Java interface 需要一個 Java 類別，而 swift-java
/// 無法在執行期憑空造出一個。
class CustomPopupDismissListener(private val action: SwiftAction) :
    PopupWindow.OnDismissListener {
    override fun onDismiss() {
        action.call()
    }
}
