/// The four built-in label styles.
///
/// One file rather than four, as ``AutomaticDatePickerStyle`` and its siblings
/// are, because each is a handful of lines and they are worth reading side by
/// side: the whole set is three arrangements of the same two views.
///
/// The `where Self == …` extensions are what make `.labelStyle(.iconOnly)` read
/// the way it does in SwiftUI. A style of the author's own is possible for the
/// same reason it is on the other four style protocols -- `struct MyStyle:
/// LabelStyle` compiles.
///
/// 四個內建的 label style。
///
/// 採用一個檔案而非四個，與 ``AutomaticDatePickerStyle`` 及其同伴相同，因為每一個都只有寥寥數行，
/// 而且值得並排閱讀：整組東西不過是同樣兩個 view 的三種排法。
///
/// `where Self == …` 這些 extension，正是讓 `.labelStyle(.iconOnly)` 讀起來與 SwiftUI 一致的東西。
/// 而作者能寫出自己的 style，理由與其他四個 style protocol 相同——`struct MyStyle: LabelStyle`
/// 編得過。

/// A label style that shows both the title and the icon.
///
/// **This is ``Label``'s body as it stood before ``LabelStyle`` existed**, moved
/// rather than rewritten: the `HStack(spacing: 6)`, the icon first and the title
/// second. Nothing that renders a label today changes appearance, because this
/// is the same expression reached by the same default.
///
/// 同時顯示標題與圖示的 label 樣式。
///
/// **這就是 ``LabelStyle`` 出現之前 ``Label`` 的 body**，是搬移而非重寫：同樣的
/// `HStack(spacing: 6)`、同樣是圖示在前、標題在後。今日任何一個 label 的外觀都不會改變，因為這是
/// 由同一個預設值抵達的同一個表達式。
public struct TitleAndIconLabelStyle: LabelStyle {
    public nonisolated init() {}

    public func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
            configuration.title
        }
    }
}

extension LabelStyle where Self == TitleAndIconLabelStyle {
    /// A label style that shows both the title and the icon.
    public static nonisolated var titleAndIcon: Self { Self() }
}

/// A label style that adapts to the current context.
///
/// The context-dependent behaviour SwiftUI gives `.automatic` -- icon-only
/// inside a toolbar, for instance -- has no equivalent here, and this is not a
/// stand-in waiting for one. ``Label``'s own note has said since it was written
/// that the title-and-icon layout *is* the correct default rather than a
/// placeholder for one, and that is what this renders.
///
/// It renders it by calling ``TitleAndIconLabelStyle`` rather than repeating its
/// body. Two copies of `HStack(spacing: 6)` would be two things that can drift,
/// and the drift would be silent: `.automatic` and `.titleAndIcon` would simply
/// stop matching, with nothing to say so.
///
/// 隨當前情境調整的 label 樣式。
///
/// SwiftUI 賦予 `.automatic` 的情境相依行為——例如在 toolbar 中只顯示圖示——在此並無對應物，而這並
/// 不是一個等待被填上的替代品。``Label`` 自身的說明從寫下的那天起就表明：「標題加圖示」的版面**就是**
/// 正確的預設值，而不是預設值的佔位符；此處繪製的正是它。
///
/// 它是透過呼叫 ``TitleAndIconLabelStyle`` 來繪製，而不是把它的 body 抄一遍。兩份
/// `HStack(spacing: 6)` 就是兩個會各自漂移的東西，而那種漂移是無聲的：`.automatic` 與
/// `.titleAndIcon` 會就這樣不再一致，卻沒有任何東西會出聲。
public struct DefaultLabelStyle: LabelStyle {
    public nonisolated init() {}

    public func makeBody(configuration: Configuration) -> some View {
        TitleAndIconLabelStyle().makeBody(configuration: configuration)
    }
}

extension LabelStyle where Self == DefaultLabelStyle {
    /// A label style that adapts to the current context.
    ///
    /// Named `automatic` after SwiftUI, on a type named `Default` after
    /// SwiftUI's own `DefaultLabelStyle`. ``DefaultPickerStyle`` is spelled the
    /// same way for the same reason.
    /// 依 SwiftUI 命名為 `automatic`，而型別則依 SwiftUI 自己的 `DefaultLabelStyle` 命名為
    /// `Default`。``DefaultPickerStyle`` 基於相同理由採用相同拼法。
    public static nonisolated var automatic: Self { Self() }
}

/// A label style that shows only the title.
///
/// The icon is not drawn at all rather than drawn transparently, so it occupies
/// no space and costs no widget.
/// 圖示是「完全不繪製」，而非「以透明方式繪製」，因此它不佔空間，也不耗費任何 widget。
public struct TitleOnlyLabelStyle: LabelStyle {
    public nonisolated init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.title
    }
}

extension LabelStyle where Self == TitleOnlyLabelStyle {
    /// A label style that shows only the title.
    public static nonisolated var titleOnly: Self { Self() }
}

/// A label style that shows only the icon.
///
/// The title is not drawn at all. Note that this hides text from anything
/// reading the rendered tree, so it suits a control whose meaning the icon
/// already carries.
/// 標題完全不繪製。請留意這會讓文字對「讀取已繪製樹狀結構」的任何東西隱藏，因此它適用於「圖示本身
/// 已經承載了意義」的控制項。
public struct IconOnlyLabelStyle: LabelStyle {
    public nonisolated init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.icon
    }
}

extension LabelStyle where Self == IconOnlyLabelStyle {
    /// A label style that shows only the icon.
    public static nonisolated var iconOnly: Self { Self() }
}
