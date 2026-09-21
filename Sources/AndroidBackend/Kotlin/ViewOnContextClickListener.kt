package dev.swiftcrossui.androidbackend

import android.view.View

/// The mouse/stylus half of a context menu. `ViewOnLongClickListener` is the
/// touch half; Android keeps them on two separate listener slots, which is why
/// there are two classes rather than one.
class ViewOnContextClickListener(private val action: SwiftAction) : View.OnContextClickListener {
    override fun onContextClick(view: View): Boolean {
        action.call()
        return true
    }
}
