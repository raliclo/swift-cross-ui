import Foundation

/// A button that opens a URL with the system handler.
///
/// Composed from `Button` and the existing `openURL` environment action, so it
/// needs nothing new from any backend -- `BackendFeatures.ExternalURLs` was
/// already there and already implemented. See ``Stepper`` for why this batch
/// was chosen.
///
/// **The label is any view**, as in SwiftUI: `Link(destination:label:)` takes
/// a view builder, and `Link(_:destination:)` is the case where the label is a
/// ``Text``. The label is the label of a ``Button``, which every shipped backend
/// hosts inside its native button (`createButton(wrapping:)`), so a click
/// anywhere on it opens the URL and the button's accessibility name is the
/// label's text, as for any other button.
///
/// Deliberately not styled as a hyperlink either. Blue underlined text that is
/// not obviously pressable is a worse affordance on a desktop toolkit than a
/// plain button, and inventing a link appearance here would mean inventing it
/// five times. A label can still be drawn as one (`Text(...).foregroundColor`
/// inside a `.buttonStyle(.plain)` link).
///
/// 一個以系統處理常式開啟 URL 的按鈕。
///
/// 由 `Button` 與既有的 `openURL` 環境動作組合而成，因此不需要任何 backend 提供新東西——
/// `BackendFeatures.ExternalURLs` 早已存在且早已實作。本批工作為何如此挑選，見 ``Stepper``。
///
/// **標籤可以是任何 view**,與 SwiftUI 相同:`Link(destination:label:)` 接受一個 view builder,而
/// `Link(_:destination:)` 是標籤為 ``Text`` 的特例。標籤就是一顆 ``Button`` 的標籤，每個已發布的 backend 都把它容納在
/// 自己的原生按鈕裡(`createButton(wrapping:)`),因此點擊其上任何位置都會開啟 URL,而按鈕的輔助使用名稱就是標籤的
/// 文字，與其他按鈕相同。
///
/// 同樣刻意不做成超連結樣式。在桌面 toolkit 上，「藍色底線但看不出可按」的文字，其可操作性線索
/// 比一顆普通按鈕更差；而在此處自創一種連結外觀，等於要自創五次。標籤仍然可以畫成那樣(在 `.buttonStyle(.plain)`
/// 的 link 裡放 `Text(...).foregroundColor`)。
public struct Link<Label: View>: View {
    @Environment(\.openURL) private var openURL

    private let label: Label
    private let destination: URL

    /// Creates a link whose label is an arbitrary view.
    ///
    /// - Parameters:
    ///   - destination: The URL to open.
    ///   - label: The view shown on the link.
    ///
    /// 建立一個標籤為任意 view 的連結。
    public init(destination: URL, @ViewBuilder label: () -> Label) {
        self.label = label()
        self.destination = destination
    }

    public var body: some View {
        let openURL = self.openURL
        let destination = self.destination
        let label = self.label
        return Button {
            openURL(destination)
        } label: {
            label
        }
    }
}

extension Link where Label == Text {
    /// Creates a link whose label is a string.
    ///
    /// - Parameters:
    ///   - title: The text shown on the link.
    ///   - destination: The URL to open.
    ///
    /// 建立一個標籤為字串的連結。
    public init(_ title: String, destination: URL) {
        self.label = Text(title)
        self.destination = destination
    }
}
