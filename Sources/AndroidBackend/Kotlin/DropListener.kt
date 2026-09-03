package dev.swiftcrossui.androidbackend

import android.app.Activity
import android.content.ClipDescription
import android.view.DragEvent
import android.view.View

/**
 * `onDrop(of:isTargeted:perform:)` on Android.
 *
 * `BackendFeatures.DragAndDrop` has a default implementation that returns the
 * child unwrapped and ignores the request, so a backend can conform without
 * accepting anything. Conforming that way would have stopped P25 dying at
 * launch and left it unable to receive a drop, which is the shape this
 * repository's rules exist to prevent: the report would say "supported" and
 * nothing would arrive.
 *
 * **The return value of `ACTION_DRAG_STARTED` is the whole contract.** A view
 * that returns false there is not offered the drag again -- no ENTERED, no
 * DROP -- so the accepted-type check has to happen at the start of the gesture
 * and not at the end of it. `acceptedTypes` is set from Swift before the
 * listener is attached for that reason.
 *
 * `requestDragAndDropPermissions` on drop, because a URI from another app is
 * not readable without it. Skipping it produces the failure that looks like an
 * empty drop: the item arrives, its URI is present, and opening it fails.
 *
 * Android 上的 `onDrop(of:isTargeted:perform:)`。
 *
 * `BackendFeatures.DragAndDrop` 具備一個預設實作：它原封不動地回傳子元件並忽略請求，因此一個
 * backend 可以在「什麼都不接受」的情況下宣稱符合該 conformance。以那種方式符合，確實能讓 P25 不再
 * 在啟動時死掉，卻會讓它無法接收任何 drop——而那正是本倉庫的規則所要防止的形狀：報告會寫著
 * 「已支援」，而什麼都不會抵達。
 *
 * **`ACTION_DRAG_STARTED` 的回傳值就是整份契約。** 在該事件回傳 false 的 view 不會再被提供這次
 * 拖曳——沒有 ENTERED、沒有 DROP——因此「接受哪些型別」的檢查必須發生在手勢的**開始**，而不是
 * 結束。`acceptedTypes` 之所以在附加此 listener 之前就由 Swift 設定好，原因即在此。
 *
 * drop 時呼叫 `requestDragAndDropPermissions`，因為來自其他 app 的 URI 若不如此便無法讀取。
 * 略過它會產生一種「看起來像空白 drop」的失敗：項目抵達了、它的 URI 也在，然後開啟失敗。
 */
class DropListener(val activity: Activity) : View.OnDragListener {
    var hoverAction: SwiftAction? = null
    var dropAction: SwiftAction? = null

    /** Newline-separated MIME types, set from Swift. */
    var acceptedTypes: String = ""

    /** Whether the pointer is currently inside this target. */
    var isHovering = false
        private set

    /** Newline-separated, and parallel to [droppedValues]. */
    var droppedTypes: String = ""
        private set

    /** Newline-separated: a URI where the item had one, otherwise its text. */
    var droppedValues: String = ""
        private set

    /** Set from Swift inside [dropAction], read as this listener's answer. */
    var dropAccepted = false

    private fun accepts(description: ClipDescription?): Boolean {
        if (description == null) {
            return false
        }
        val wanted = acceptedTypes.split("\n").filter { it.isNotEmpty() }
        return wanted.any { description.hasMimeType(it) }
    }

    private fun setHovering(hovering: Boolean) {
        if (isHovering == hovering) {
            return
        }
        isHovering = hovering
        hoverAction?.call()
    }

    override fun onDrag(view: View, event: DragEvent): Boolean {
        when (event.action) {
            DragEvent.ACTION_DRAG_STARTED -> return accepts(event.clipDescription)

            DragEvent.ACTION_DRAG_ENTERED -> setHovering(true)

            DragEvent.ACTION_DRAG_EXITED -> setHovering(false)

            DragEvent.ACTION_DRAG_ENDED -> setHovering(false)

            DragEvent.ACTION_DROP -> {
                setHovering(false)
                return handleDrop(event)
            }
        }
        return true
    }

    private fun handleDrop(event: DragEvent): Boolean {
        // Before the ClipData is read, not after. The permission is what makes
        // another app's URI openable, and it is scoped to this event.
        //
        // 在讀取 ClipData 之前，而非之後。這道權限正是讓另一個 app 的 URI 得以開啟的東西，
        // 而它的作用範圍僅限於這一次事件。
        activity.requestDragAndDropPermissions(event)

        val clip = event.clipData ?: return false
        val types = mutableListOf<String>()
        val values = mutableListOf<String>()

        for (i in 0..<clip.itemCount) {
            val item = clip.getItemAt(i)
            val uri = item.uri
            if (uri != null) {
                types.add(ClipDescription.MIMETYPE_TEXT_URILIST)
                values.add(uri.toString())
                continue
            }
            val text = item.text
            if (text != null) {
                types.add(ClipDescription.MIMETYPE_TEXT_PLAIN)
                values.add(text.toString())
            }
        }

        if (values.isEmpty()) {
            return false
        }

        droppedTypes = types.joinToString("\n")
        droppedValues = values.joinToString("\n")

        // Synchronous. `SwiftAction.call` runs the Swift closure before it
        // returns, so the flag that closure sets is this method's answer.
        // 同步。`SwiftAction.call` 會在返回之前執行該 Swift closure，因此該 closure 所設定的旗標
        // 就是本方法的答案。
        dropAccepted = false
        dropAction?.call()
        return dropAccepted
    }
}
