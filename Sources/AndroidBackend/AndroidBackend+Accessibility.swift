import AndroidKit
import SwiftCrossUI

/// Binding for `SwiftAccessibilityDelegate.kt`.
///
/// Set and clear are separate calls because swift-java maps a Kotlin `String?`
/// parameter to a non-optional Swift `String`; the Kotlin file records why `""`
/// is not an acceptable stand-in for "none".
/// `SwiftAccessibilityDelegate.kt` 的綁定。
///
/// 「設定」與「清除」是兩個不同的呼叫,因為 swift-java 會把 Kotlin 的 `String?` 參數映射成 Swift 的
/// 非 optional `String`;至於為何 `""` 不能用來代替「沒有」,那個 Kotlin 檔裡有記載。
@JavaClass("dev.swiftcrossui.androidbackend.SwiftAccessibilityDelegate")
class SwiftAccessibilityDelegate: JavaObject {
    @JavaMethod
    @_nonoverride convenience init(environment: JNIEnvironment? = nil)

    @JavaMethod
    func setHintText(_ value: String)

    @JavaMethod
    func clearHintText()

    @JavaMethod
    func setStateDescriptionText(_ value: String)

    @JavaMethod
    func clearStateDescriptionText()
}

extension AndroidBackend: BackendFeatures.Accessibility {
    /// Android needs no child-walking, and that is a real difference worth
    /// stating rather than a gap.
    ///
    /// The AppKit and UIKit versions of this file both hunt for the control
    /// inside the widget, because on those platforms a ``Button`` is a wrapper
    /// around the thing the screen reader lands on. Here the widget IS the
    /// control: `createButton(wrapping:)` returns the `CustomButton` itself, a
    /// `ViewGroup`. TalkBack reads a `contentDescription` set on a `ViewGroup`
    /// and announces the group as one node, so setting it on the widget is
    /// setting it on the element.
    ///
    /// Checked in `AndroidBackend+CustomButton.swift:6` rather than assumed --
    /// the same assumption made on AppKit is what P67 was written to catch.
    ///
    /// Android 不需要走訪子元件,而那是一個值得寫明的**真實差異**,不是一個缺口。
    ///
    /// 本檔的 AppKit 與 UIKit 版本都會去尋找 widget 裡面的那個控制項,因為在那些平台上,``Button``
    /// 是一層包裝,包著螢幕閱讀器真正落在其上的東西。在這裡,widget **就是**那個控制項:
    /// `createButton(wrapping:)` 回傳的是 `CustomButton` 本身,一個 `ViewGroup`。TalkBack 會讀取設在
    /// `ViewGroup` 上的 `contentDescription`,並把該群組宣讀為單一節點,因此設在 widget 上就是設在
    /// 那個元素上。
    ///
    /// 這是在 `AndroidBackend+CustomButton.swift:6` 查證過的,而非假設——在 AppKit 上做了同樣的假設,
    /// 正是 P67 當初為了抓出來而寫的東西。
    public func setAccessibilityLabel(ofWidget widget: Widget, to label: String?) {
        widget.setContentDescription(label.map(Self.charSequence(from:)))
    }

    /// Android keeps the hint on the accessibility NODE, not on the view.
    ///
    /// `View.setTooltipText` was the first attempt: one line, no class, and
    /// TalkBack does speak a tooltip. `uiautomator dump` said the node's `hint`
    /// attribute was still EMPTY, so it is not the same field.
    /// `AccessibilityNodeInfo.hintText` is, and a delegate is the only way to
    /// reach it. See `SwiftAccessibilityDelegate.kt`.
    ///
    /// Android 把提示放在無障礙**節點**上,而不是放在 view 上。
    ///
    /// 第一次的做法是 `View.setTooltipText`:一行、不需要類別,而 TalkBack 確實會唸出 tooltip。
    /// `uiautomator dump` 說那個節點的 `hint` 屬性仍然是**空**的,因此它不是同一個欄位。
    /// `AccessibilityNodeInfo.hintText` 才是,而 delegate 是抵達它的唯一途徑。
    /// 見 `SwiftAccessibilityDelegate.kt`。
    public func setAccessibilityHint(ofWidget widget: Widget, to hint: String?) {
        let delegate = delegate(for: widget)
        if let hint {
            delegate.setHintText(hint)
        } else {
            delegate.clearHintText()
        }
    }

    /// Goes through the same delegate as the hint.
    ///
    /// `View.setStateDescription` exists and is the obvious call, and it arrived
    /// in API 30. The delegate reaches the same node field from API 26, and
    /// keeping both properties in one place is what stops a view ending up with
    /// its hint on the node and its value on the view.
    ///
    /// 與提示走同一個 delegate。
    ///
    /// `View.setStateDescription` 確實存在、也是最直觀的呼叫,而它是 API 30 才有的。這個 delegate
    /// 從 API 26 就能抵達同一個節點欄位;而把兩個屬性放在同一個地方,正是「避免一個 view 落得提示在
    /// 節點上、值在 view 上」的做法。
    public func setAccessibilityValue(ofWidget widget: Widget, to value: String?) {
        let delegate = delegate(for: widget)
        if let value {
            delegate.setStateDescriptionText(value)
        } else {
            delegate.clearStateDescriptionText()
        }
    }

    /// This widget's delegate, installing one the first time it is asked for.
    ///
    /// Reused rather than replaced, so setting a hint does not silently drop a
    /// value set a moment earlier -- the two modifiers are separate views and
    /// neither knows about the other.
    /// 這個 widget 的 delegate;第一次被索取時才安裝。
    ///
    /// 重複使用而非replace,如此設定提示才不會靜默地丟掉片刻前設定的值——那兩個 modifier 是各自
    /// 獨立的 view,彼此並不知道對方存在。
    private func delegate(for widget: Widget) -> SwiftAccessibilityDelegate {
        if let existing = widget.getAccessibilityDelegate()?.as(SwiftAccessibilityDelegate.self) {
            return existing
        }
        let delegate = SwiftAccessibilityDelegate(environment: Self.env)
        widget.setAccessibilityDelegate(delegate.as(AndroidKit.View.AccessibilityDelegate.self))
        return delegate
    }

    /// Hides the widget and everything under it.
    ///
    /// `NO_HIDE_DESCENDANTS` rather than `NO`: plain `NO` removes this view from
    /// the tree and leaves its children in it, so a hidden group would still
    /// have its parts announced -- exactly what the protocol says must not
    /// happen.
    ///
    /// 隱藏這個 widget 以及它底下的一切。
    ///
    /// 用 `NO_HIDE_DESCENDANTS` 而非單純的 `NO`:單純的 `NO` 只把這個 view 從樹上移除,把它的子元件
    /// 留在樹上,於是一個被隱藏的群組,它的各個零件仍然會被宣讀——那正是本協定所說不得發生的事。
    ///
    /// **Verifying this needs `uiautomator dump --compressed`, not the plain
    /// dump.** `UiAutomation` sets `FLAG_INCLUDE_NOT_IMPORTANT_VIEWS`, so the
    /// plain dump lists views a screen reader would never reach -- it showed
    /// `decorative` as present and this looked broken for an hour while the flag
    /// was in fact being set on the right container. The compressed dump is the
    /// one that answers the question being asked.
    ///
    /// **要驗證這件事,必須用 `uiautomator dump --compressed`,而不是普通的 dump。**
    /// `UiAutomation` 會設定 `FLAG_INCLUDE_NOT_IMPORTANT_VIEWS`,因此普通的 dump 會列出螢幕閱讀器
    /// 永遠抵達不了的 view——它顯示 `decorative` 存在,於是這看起來壞了一小時,而那個旗標其實一直
    /// 都正確地設在正確的容器上。compressed 的那一份才是回答這個問題的那一份。
    public func setAccessibilityHidden(ofWidget widget: Widget, to hidden: Bool) {
        widget.setImportantForAccessibility(
            hidden
                ? Self.importantForAccessibilityNoHideDescendants
                : Self.importantForAccessibilityAuto
        )
    }

    /// `View.IMPORTANT_FOR_ACCESSIBILITY_AUTO`.
    ///
    /// Spelled out because the constants are not in the generated bindings and
    /// a bare `0` and `4` at the call site would say nothing about which
    /// behaviour was meant.
    /// `View.IMPORTANT_FOR_ACCESSIBILITY_AUTO`。
    ///
    /// 寫成具名常數,因為這些常數不在產生出來的綁定裡;而呼叫處光禿禿的 `0` 與 `4`,說不出所指的
    /// 是哪一種行為。
    private static let importantForAccessibilityAuto: Int32 = 0
    /// `View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS`.
    private static let importantForAccessibilityNoHideDescendants: Int32 = 4
}
