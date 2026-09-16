package dev.swiftcrossui.androidbackend

import android.view.View
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Carries the accessibility properties Android keeps on the NODE rather than on the view.
 *
 * **`View.setTooltipText` was tried first and does not do this.** It is one line, needs no class,
 * and TalkBack does speak a tooltip -- so it looked like the cheap correct answer. Measured on
 * 2026-09-16 with `adb shell uiautomator dump`: the node's `hint` attribute came back EMPTY on a
 * button carrying `.accessibilityHint("Removes the file permanently")`. A tooltip is a tooltip;
 * `AccessibilityNodeInfo.hintText` is a different field, and only a delegate can reach it.
 *
 * The delegate holds data and nothing else -- no callback into Swift, no listener. Two strings and
 * an override that copies them onto the node. That matters for what it rules out: there is no
 * lifetime question, no thread question, and nothing to leak.
 *
 * `stateDescription` rides along rather than staying on `View.setStateDescription`, because that
 * one arrived in API 30 and this reaches the same field from API 26. One place for both also means
 * a view cannot end up with its hint on the node and its value on the view.
 *
 * 承載 Android 放在**節點**上、而非放在 view 上的那些無障礙屬性。
 *
 * **先試過 `View.setTooltipText`,而它做不到這件事。** 它只有一行、不需要任何類別,而且 TalkBack 確實
 * 會唸出 tooltip——所以它看起來像是既便宜又正確的答案。2026-09-16 以 `adb shell uiautomator dump`
 * 量測:一顆帶著 `.accessibilityHint("Removes the file permanently")` 的按鈕,其節點的 `hint` 屬性回報
 * 為**空**。tooltip 就是 tooltip;`AccessibilityNodeInfo.hintText` 是另一個欄位,而只有 delegate 能
 * 抵達它。
 *
 * 這個 delegate 只持有資料,別的都不做——沒有回呼進 Swift、沒有 listener。兩個字串,加上一個把它們
 * 複製到節點上的 override。這一點的重要性在於它排除了什麼:沒有生命週期問題、沒有執行緒問題,也沒有
 * 任何東西會洩漏。
 *
 * `stateDescription` 搭這班車,而不是留在 `View.setStateDescription` 上,因為後者是 API 30 才有的,
 * 而這條路從 API 26 就能抵達同一個欄位。兩者放在同一個地方,也意味著一個 view 不會落得「提示在節點上、
 * 值在 view 上」。
 */
class SwiftAccessibilityDelegate : View.AccessibilityDelegate() {
    private var hint: String? = null
    private var stateDescription: String? = null

    // Set and clear as separate methods, rather than one taking a nullable string.
    //
    // swift-java maps a Kotlin `String?` parameter to a non-optional Swift `String`, so a single
    // setter could only express "no hint" as `""` -- and an empty hint is a legitimate request
    // that means something else: a node a screen reader announces as having none, as opposed to
    // one the platform may still derive a hint for. Two methods keep the two answers apart.
    //
    // 「設定」與「清除」寫成兩個方法,而不是一個接受 nullable 字串的方法。
    //
    // swift-java 會把 Kotlin 的 `String?` 參數映射成 Swift 的非 optional `String`,因此單一個 setter
    // 只能用 `""` 來表達「沒有提示」——而「空提示」是一個正當的要求,而且意思不同:那是一個「螢幕
    // 閱讀器會宣告為沒有提示」的節點,相對於「平台仍可能為它推導出一個提示」的節點。兩個方法讓這兩個
    // 答案不會混為一談。
    fun setHintText(value: String) { hint = value }

    fun clearHintText() { hint = null }

    fun setStateDescriptionText(value: String) { stateDescription = value }

    fun clearStateDescriptionText() { stateDescription = null }

    override fun onInitializeAccessibilityNodeInfo(host: View, info: AccessibilityNodeInfo) {
        super.onInitializeAccessibilityNodeInfo(host, info)
        // Written only when non-null. Assigning null unconditionally would clear whatever the
        // platform had derived, turning "this modifier was not used" into "this node has no hint",
        // and those are different answers.
        // 只在非 null 時寫入。無條件指派 null 會清掉平台本來推導出的東西,把「沒有用到這個 modifier」
        // 變成「這個節點沒有提示」——而那是兩個不同的答案。
        hint?.let { info.hintText = it }
        stateDescription?.let { info.stateDescription = it }
    }
}
