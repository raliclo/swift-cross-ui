import AndroidKit
import AndroidView
@_spi(Backends) import SwiftCrossUI
import SwiftJava

/// A row of buttons above the content.
///
/// **Not `android.widget.Toolbar`, and that was measured rather than assumed.**
/// The first implementation re-bound that class as a `ViewGroup` subclass and
/// populated it through `getMenu()`. It compiled, the APK built, and the app
/// died on launch:
///
///     Fatal error: 'try!' expression unexpectedly raised an error:
///     java.lang.ClassNotFoundException: Didn't find class
///     "android.widget.Toolbar" on path: DexPathList[...]
///
/// The class is not reachable from the app's class loader on this image, so the
/// only way that route could report success is by never being run. A row built
/// from `LinearLayout` and `Button` uses the two classes this backend already
/// creates for every app, which is why it can be verified today.
///
/// What is given up is the overflow: a real toolbar collapses items it cannot
/// fit into a "..." menu, and this row lets them run off the edge instead. The
/// row is inside the same horizontal space as the content and P53 declares
/// three items, so nothing overflows in practice -- but it is a difference, and
/// stating it here is cheaper than someone finding it with twenty items.
///
/// 一列位於內容上方的按鈕。
///
/// **不是 `android.widget.Toolbar`,而這是實測出來的、不是假設的。** 最初的實作把該類別重新綁定為
/// `ViewGroup` 的子類別,並透過 `getMenu()` 填入內容。它編譯過了、APK 也建起來了,而 app 一啟動就死:
///
///     Fatal error: 'try!' expression unexpectedly raised an error:
///     java.lang.ClassNotFoundException: Didn't find class
///     "android.widget.Toolbar" on path: DexPathList[...]
///
/// 在這個映像上,該類別從 app 的 class loader 觸及不到,因此那條路線唯一能回報成功的方式,就是永遠
/// 不被執行。以 `LinearLayout` 與 `Button` 組成的一列,用的是本 backend 每支 app 都會建立的那兩個
/// 類別,這正是它今天就驗得起來的原因。
///
/// 放棄掉的是 overflow:真正的工具列會把塞不下的項目收進「⋯」選單,而這一列則會讓它們跑出邊緣。
/// 這一列與內容位於同一段水平空間中,而 P53 宣告三個項目,因此實務上不會溢出——但那是一項差異,
/// 在此說明的代價,低於某個人拿二十個項目去發現它。
extension AndroidBackend: BackendFeatures.Toolbars {
    public func setToolbar(
        ofWindow window: Window,
        to items: [SwiftCrossUI.ToolbarItem],
        title: String?
    ) {
        guard let stack = Self.rootStack else { return }
        setNavigationTitle(title, in: stack)

        guard !items.isEmpty else {
            if let bar = Self.toolbar {
                stack.removeView(bar)
                Self.toolbar = nil
            }
            return
        }

        let bar: AndroidKit.LinearLayout
        if let existing = Self.toolbar {
            bar = existing
            bar.removeAllViews()
        } else {
            bar = AndroidKit.LinearLayout(Self.activity, environment: Self.env)
            bar.setOrientation(try! JavaClass<AndroidKit.LinearLayout>().HORIZONTAL)
            let matchParent = try! JavaClass<AndroidKit.ViewGroup.LayoutParams>().MATCH_PARENT
            let wrapContent = try! JavaClass<AndroidKit.ViewGroup.LayoutParams>().WRAP_CONTENT
            // Index 0: above the scroll host, which `setChild(ofWindow:to:)` put
            // in at weight 1. Appending instead would put the row under the
            // content and off the bottom of a full-height scroll view, where it
            // renders correctly and is never on screen.
            // 索引 0:位於 scroll host 之上,而後者是 `setChild(ofWindow:to:)` 以 weight 1 放進去的。
            // 若改用附加,這一列會落在內容之下、被推出滿高捲動視圖的底端之外——它會正確地繪製出來,
            // 但永遠不會出現在畫面上。
            stack.addView(
                bar,
                0,
                AndroidKit.LinearLayout.LayoutParams(
                    matchParent,
                    wrapContent,
                    environment: Self.env
                )
                .as(AndroidKit.ViewGroup.LayoutParams.self)
            )
            Self.toolbar = bar
        }

        // Ordered rather than placed. Android's action area is one region, so
        // `leading` and `trailing` cannot be opposite ends of anything -- what
        // survives the mapping is the sequence, and this is the sequence the
        // other backends put their items in.
        // 這裡是「排序」而非「配置」。Android 的動作區只有一塊,因此 `leading` 與 `trailing` 不可能是
        // 任何東西的兩端——在這個對應中存活下來的是順序,而這正是其他 backend 擺放其項目的順序。
        for item in items.sorted(by: { Self.order(of: $0.placement) < Self.order(of: $1.placement) })
        {
            let button = AndroidKit.Button(Self.activity, environment: Self.env)
            button.setText(Self.charSequence(from: item.label))
            button.setAllCaps(false)
            button.setEnabled(item.isEnabled)
            let action = item.action
            button.setOnClickListener(
                ViewOnClickListener(action: { action() }, environment: Self.env)
                    .as(AndroidView.View.OnClickListener.self)
            )
            bar.addView(button)
        }
    }

    private static func order(of placement: SwiftCrossUI.ToolbarItem.Placement) -> Int {
        switch placement {
            case .leading: 0
            case .automatic: 1
            case .primary: 2
            case .trailing: 3
        }
    }

    /// The heading `.navigationTitle` asked for, as a row above the content.
    ///
    /// A `TextView` in the root stack rather than an ActionBar. This backend's
    /// activity has no ActionBar to set a title on -- `setTitle(ofWindow:to:)`
    /// was an empty `TODO(stackotter)` for exactly that reason -- and the root
    /// stack is where `.toolbar` and `.refreshable` already put their rows, so
    /// a third one costs nothing new.
    ///
    /// Index 0, so a title sits above a toolbar row rather than beside it. That
    /// is the order Android's own app bar uses, and it is also the order that
    /// survives one of the two being removed.
    ///
    /// `.navigationTitle` 所要求的標題,以一列的形式置於內容之上。
    ///
    /// 使用 root stack 中的一個 `TextView`,而不是 ActionBar。本 backend 的 activity 沒有可供設定標題的
    /// ActionBar——`setTitle(ofWindow:to:)` 之所以是一個空的 `TODO(stackotter)`,正是這個原因——而
    /// root stack 已經是 `.toolbar` 與 `.refreshable` 擺放它們那幾列的地方,因此第三列不會多付出任何代價。
    ///
    /// 放在索引 0,好讓標題位於工具列那一列**之上**而非其旁。那是 Android 自家 app bar 所採用的順序,
    /// 也是「兩者之一被移除時仍然成立」的順序。
    private func setNavigationTitle(_ title: String?, in stack: AndroidKit.LinearLayout) {
        let existing = Self.navigationTitleView(in: stack)
        guard let title, !title.isEmpty else {
            if let existing { stack.removeView(existing) }
            return
        }

        if let existing {
            existing.setText(Self.charSequence(from: title))
            return
        }

        let label = AndroidKit.TextView(Self.activity, environment: Self.env)
        label.setText(Self.charSequence(from: title))
        label.setTag(JavaString(Self.navigationTitleTag, environment: Self.env)
            .as(JavaObject.self))
        stack.addView(label, 0)
    }

    /// Found by tag, not by position or by text.
    ///
    /// Position moves as the toolbar and refresh rows come and go, and text is
    /// the title itself -- searching for it would fail the moment the title
    /// changed, which is the only time this lookup runs.
    ///
    /// 以 tag 尋找,而不是以位置或以文字。
    ///
    /// 位置會隨著工具列與 refresh 那兩列的來去而改變,而文字就是標題本身——以它搜尋,會在標題改變的
    /// 那一刻失效,而那正是這個查找唯一會執行的時機。
    private static let navigationTitleTag = "scui.navigationTitle"

    private static func navigationTitleView(
        in stack: AndroidKit.LinearLayout
    ) -> AndroidKit.TextView? {
        for index in 0..<stack.getChildCount() {
            guard let child = stack.getChildAt(index),
                let label = child.as(AndroidKit.TextView.self),
                label.getTag()?.toString() == navigationTitleTag
            else { continue }
            return label
        }
        return nil
    }
}
