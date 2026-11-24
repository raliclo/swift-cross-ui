import Foundation

// Badges are drawn by SwiftCrossUI itself, not by each backend's native badge
// API, because neither container that shows one is native in this fork:
// ``TabView`` builds its tab strip out of ``Button``s, and a ``List`` row is a
// SwiftCrossUI view hosted inside the native list's cell. A native badge needs a
// native item to attach to -- `UITabBarItem.badgeValue`, a WinUI `InfoBadge`
// inside a `NavigationViewItem`, Android's `BadgeDrawable` on a bottom
// navigation item -- and none of those items exist here. The pill below is made
// of a `Text`, a `Color` and a `cornerRadius`, which every backend already draws
// (AppKit, UIKit, GTK, WinUI and Android alike), so the badge looks the same on
// all five and needs no per-backend code to stay correct.
//
// 徽章由 SwiftCrossUI 自行繪製，而不是交給各 backend 的原生徽章 API,因為在這個 fork 中，會顯示徽章的
// 兩種容器都不是原生的:``TabView`` 的分頁列由 ``Button`` 組成，而 ``List`` 的每一列是放在原生清單
// cell 裡的 SwiftCrossUI view。原生徽章需要一個可附著的原生項目——`UITabBarItem.badgeValue`、
// WinUI `NavigationViewItem` 裡的 `InfoBadge`、Android bottom navigation 項目上的
// `BadgeDrawable`——而這些項目在此都不存在。下方的膠囊由 `Text`、`Color` 與 `cornerRadius` 組成，
// 五個 backend(AppKit、UIKit、GTK、WinUI、Android)都已能繪製，因此徽章在五者上外觀一致，也不需要
// 任何 per-backend 程式碼來維持正確。

/// How badge values become the text a badge shows.
/// 徽章的值如何轉為徽章上顯示的文字。
enum Badge {
    /// A count's label: `nil` for zero, which hides the badge, as in SwiftUI.
    /// Negative counts are shown, also as in SwiftUI.
    ///
    /// 數字的標籤：零回傳 `nil`,即隱藏徽章，與 SwiftUI 相同。負數照樣顯示，同樣與 SwiftUI 一致。
    static func label(for count: Int) -> Text? {
        count == 0 ? nil : Text(String(count))
    }

    /// A string's label: `nil` for `nil` or an empty string, which hides the
    /// badge rather than drawing an empty pill.
    ///
    /// 字串的標籤:`nil` 或空字串回傳 `nil`,隱藏徽章而不是畫出一顆空的膠囊。
    static func label<S: StringProtocol>(for string: S?) -> Text? {
        guard let string, !string.isEmpty else { return nil }
        return Text(String(string))
    }
}

extension EnvironmentValues {
    /// Set by ``List`` on the environment of each of its rows, so that a
    /// `badge(_:)` written on the row's content knows to draw at
    /// the row's trailing edge. Outside a list row a badge draws nothing, as in
    /// SwiftUI.
    ///
    /// 由 ``List`` 設定於其每一列的環境中，使寫在該列內容上的 `badge(_:)` 知道要畫在
    /// 該列的尾端。不在清單列之中時，徽章不畫任何東西，與 SwiftUI 相同。
    @Entry var isListRowContent: Bool = false
}

extension View {
    /// Shows a count at the trailing edge of a ``List`` row. Zero hides it.
    ///
    /// SwiftUI shows a view's badge in two places: on a tab item and in a list
    /// row. In this fork a tab's badge goes on the ``Tab`` itself (see
    /// `Tab.badge(_:)`), because a tab is a value written beside its
    /// content; this modifier covers list rows. Anywhere else it has no visible
    /// effect, as in SwiftUI.
    ///
    /// 在 ``List`` 列的尾端顯示一個數字；零會隱藏它。
    ///
    /// SwiftUI 會在兩處顯示 view 的徽章：分頁項目與清單列。在這個 fork 中，分頁的徽章寫在 ``Tab``
    /// 本身(見 `Tab.badge(_:)`),因為分頁是寫在內容旁邊的值；此 modifier 處理清單列。在其他
    /// 地方不會有可見效果，與 SwiftUI 相同。
    ///
    /// - Parameter count: The number to show; `0` hides the badge.
    public func badge(_ count: Int) -> some View {
        BadgeModifierView(content: self, label: Badge.label(for: count))
    }

    /// Shows a text at the trailing edge of a ``List`` row. `nil` hides it.
    ///
    /// 在 ``List`` 列的尾端顯示一段文字；`nil` 會隱藏它。
    ///
    /// - Parameter label: The text to show, keeping its own styling; `nil`
    ///   hides the badge.
    public func badge(_ label: Text?) -> some View {
        BadgeModifierView(content: self, label: label)
    }

    /// Shows a string at the trailing edge of a ``List`` row. An empty string
    /// hides it.
    ///
    /// 在 ``List`` 列的尾端顯示一個字串；空字串會隱藏它。
    ///
    /// - Parameter key: The string to show.
    public func badge(_ key: String) -> some View {
        BadgeModifierView(content: self, label: Badge.label(for: key))
    }

    /// Shows a string at the trailing edge of a ``List`` row. `nil` or an
    /// empty string hides it.
    ///
    /// 在 ``List`` 列的尾端顯示一個字串;`nil` 或空字串會隱藏它。
    ///
    /// - Parameter label: The string to show; `nil` hides the badge.
    @_disfavoredOverload
    public func badge<S: StringProtocol>(_ label: S?) -> some View {
        BadgeModifierView(content: self, label: Badge.label(for: label))
    }
}

/// A view with a badge, which it draws only inside a list row.
///
/// Inside a row the content is followed by a flexible space and the pill, so
/// the pill sits at the row's trailing edge however short the content is.
/// Outside one the content is returned unchanged, so the badge cannot move or
/// resize anything where SwiftUI would not show it.
///
/// 帶有徽章的 view,只在清單列之中才畫出徽章。
///
/// 在列之中，內容後面接一段可伸縮的空白，再接膠囊，因此不論內容多短，膠囊都位於列的尾端。在列之外則
/// 原樣回傳內容，因此在 SwiftUI 不會顯示徽章的地方，徽章不會移動或改變任何東西的大小。
struct BadgeModifierView<Content: View>: View {
    var content: Content
    var label: Text?

    @Environment(\.isListRowContent) var isListRowContent

    var body: some View {
        if isListRowContent, let label {
            HStack(spacing: 8) {
                content
                Spacer()
                BadgePill(label: label, background: .gray)
            }
        } else {
            content
        }
    }
}

/// The pill a badge is drawn as: white caption text on a rounded colour.
///
/// The background is a `Color` with a `cornerRadius` rather than a `Capsule`
/// shape: both draw on all five shipped backends, but only the former also
/// draws on `DummyBackend`, which the unit tests lay views out on. The radius
/// is half the pill's height at caption size, so the ends are round.
///
/// 徽章所畫成的膠囊：圓角色塊上的白色 caption 文字。
///
/// 背景是帶 `cornerRadius` 的 `Color`,而不是 `Capsule` 形狀：兩者在五個已發布的 backend 上都能繪製,
/// 但只有前者也能在單元測試用來排版的 `DummyBackend` 上繪製。半徑取 caption 字級下膠囊高度的一半，
/// 因此兩端是圓的。
struct BadgePill: View {
    var label: Text
    var background: Color

    var body: some View {
        label
            .font(.caption)
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .fixedSize()
            .background(background.cornerRadius(8))
    }
}
