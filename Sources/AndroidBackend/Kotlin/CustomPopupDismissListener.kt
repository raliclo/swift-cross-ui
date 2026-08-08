package dev.swiftcrossui.androidbackend

import android.widget.PopupWindow

/**
 * Reports a popup's dismissal back to Swift.
 *
 * A PopupWindow is dismissed by touching outside it, and nothing in the view tree hears that.
 * Without this, the modifier's isPresented stays true, the next press is a no-op because it is
 * already "presented", and the popover never comes back.
 *
 * 把 popup 的關閉回報給 Swift。
 *
 * PopupWindow 是靠觸碰它以外的地方來關閉的,而 view 樹中沒有任何東西會聽到這件事。少了它,modifier 的 isPresented
 * 會維持為真,下一次按下不會有作用——因為它「已經呈現了」——而該 popover 再也不會回來。
 */
class CustomPopupDismissListener(private val action: SwiftAction) : PopupWindow.OnDismissListener {
    override fun onDismiss() {
        action.call()
    }
}
