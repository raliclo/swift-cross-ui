/// The text field shapes a backend can be asked for directly.
///
/// The fourth of these, after ``BackendPickerStyle``, ``BackendDatePickerStyle``
/// and ``BackendToggleStyle``, and the first that had no predecessor at all:
/// `TextFieldStyle` did not exist in this package in any form, so unlike
/// `ToggleStyle` -- which was already a struct with a nested
/// `@_spi(Backends) enum Style` -- there was no existing split between "what an
/// application writes" and "what a backend implements" to inherit.
///
/// The four cases are SwiftUI's set: `automatic`, `plain`, `roundedBorder`, and
/// `squareBorder` (which SwiftUI marks macOS-only). They are all available on
/// every backend here, because a square-bordered field is a border with no
/// corner radius and every one of the five can express that -- see the per-case
/// notes below.
///
/// Unlike ``BackendToggleStyle``, no case is served by its own opt-in backend
/// feature. All four are drawn by the *same* widget, the one
/// ``BackendFeatures/TextFields/createTextField()`` already returns, with
/// different border properties set on it. That is why this needs no new backend
/// method and cannot leave a backend behind: a backend that has text fields at
/// all has all four shapes.
///
/// ## How `automatic` resolves
///
/// `automatic` means **"leave the platform's own text field appearance
/// alone"**, not "pick one of the other three". It is deliberately not defined
/// as an alias, because the five platforms do not agree on what a bare text
/// field looks like and flattening that disagreement would make every field on
/// some platform look foreign:
///
/// | Backend | What `automatic` leaves in place |
/// | --- | --- |
/// | `GtkBackend` | A framed `GtkEntry` -- `has-frame` is `TRUE` by default -- with the theme's own corner radius. |
/// | `WinUIBackend` | A `TextBox` with its theme `BorderThickness` and the WinUI resource corner radius. |
/// | `AppKitBackend` | A bezeled `NSTextField`; `NSTextField`'s default `bezelStyle` is `.squareBezel`. |
/// | `UIKitBackend` | `UITextField.borderStyle == .none`, which is what a bare SwiftUI `TextField` looks like on iOS. |
/// | `AndroidBackend` | The `EditText`'s platform background drawable -- the Material underline, not a box. |
///
/// So `automatic` on macOS looks like `squareBorder` and on iOS looks like
/// `plain`, and that is the point: each is that platform's convention. An
/// application that wants the *same* shape everywhere names the shape.
///
/// ## `automatic` 如何解析
///
/// `automatic` 的意思是**「保持平台自身的文字輸入框外觀不變」**，而不是「在其餘三者中挑一個」。
/// 刻意不把它定義為某個 case 的別名，因為五個平台對「一個未加修飾的文字輸入框長什麼樣」並無共識；
/// 把這個歧異抹平，只會讓某些平台上的每一個輸入框看起來都很陌生。
///
/// 因此 `automatic` 在 macOS 上看起來像 `squareBorder`，在 iOS 上看起來像 `plain`——而這正是重點：
/// 兩者各自是該平台的慣例。若應用程式希望在所有平台上得到**相同**的外形，就指名該外形。
public enum BackendTextFieldStyle: Sendable, Hashable {
    /// The platform's own text field appearance, left untouched.
    ///
    /// See the type's documentation for what that is on each backend. This is
    /// the default, and a backend must treat it as "restore whatever
    /// `createTextField()` produced" rather than as a no-op -- a field can be
    /// re-committed with a different style, so the borderless case has to be
    /// undoable.
    ///
    /// 平台自身的文字輸入框外觀，維持原樣。
    ///
    /// backend 必須把它當成「還原 `createTextField()` 原本產生的樣子」，而不是「什麼都不做」——
    /// 同一個 widget 可能以不同的 style 被重新 commit，因此無框的情形必須是可還原的。
    case automatic

    /// No border, no bezel, and no background of the control's own.
    ///
    /// The text still draws, and the field is still editable and focusable;
    /// only the chrome goes away. Used for a field embedded in something that
    /// draws its own container -- a toolbar, a list row, a custom card.
    ///
    /// 沒有邊框、沒有 bezel，也沒有控制項自身的背景。文字照樣繪製，欄位照樣可編輯、可取得焦點，
    /// 消失的只有外框裝飾。適用於嵌在「自己會畫容器」之物件中的欄位。
    case plain

    /// A border with rounded corners.
    case roundedBorder

    /// A border with square corners.
    ///
    /// SwiftUI marks its `squareBorder` macOS-only. It is offered on all five
    /// backends here because the restriction is SwiftUI's, not the platforms':
    /// a square border is a rounded border with a corner radius of zero, and
    /// every backend in this package can set a corner radius -- see the
    /// implementations for the specific property each one uses.
    ///
    /// SwiftUI 將它的 `squareBorder` 標為僅限 macOS。此處五個 backend 全部提供，因為那項限制是
    /// SwiftUI 的、而非各平台的：方角邊框就是圓角半徑為零的圓角邊框，而本套件中的每一個 backend
    /// 都能設定圓角半徑。
    case squareBorder
}
