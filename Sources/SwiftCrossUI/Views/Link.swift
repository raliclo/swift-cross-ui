import Foundation

/// A button that opens a URL with the system handler.
///
/// Composed from `Button` and the existing `openURL` environment action, so it
/// needs nothing new from any backend -- `BackendFeatures.ExternalURLs` was
/// already there and already implemented. See ``Stepper`` for why this batch
/// was chosen.
///
/// **Takes a String, not a view label.** SwiftUI's `Link` accepts any label.
/// ``Button`` takes arbitrary view labels, so a `Link<Label: View>` can be
/// built on it directly; until then this offers only the string form.
///
/// Deliberately not styled as a hyperlink either. Blue underlined text that is
/// not obviously pressable is a worse affordance on a desktop toolkit than a
/// plain button, and inventing a link appearance here would mean inventing it
/// five times.
///
/// 一個以系統處理常式開啟 URL 的按鈕。
///
/// 由 `Button` 與既有的 `openURL` 環境動作組合而成，因此不需要任何 backend 提供新東西——
/// `BackendFeatures.ExternalURLs` 早已存在且早已實作。本批工作為何如此挑選，見 ``Stepper``。
///
/// **接受 String 而非 view 標籤。** SwiftUI 的 `Link` 接受任何標籤。``Button`` 已支援任意 view
/// 標籤，因此 `Link<Label: View>` 可以直接建立在它之上；在那之前，此處只提供字串形式。
///
/// 同樣刻意不做成超連結樣式。在桌面 toolkit 上，「藍色底線但看不出可按」的文字，其可操作性線索
/// 比一顆普通按鈕更差；而在此處自創一種連結外觀，等於要自創五次。
public struct Link: View {
    @Environment(\.openURL) private var openURL

    private let title: String
    private let destination: URL

    public init(_ title: String, destination: URL) {
        self.title = title
        self.destination = destination
    }

    public var body: some View {
        Button(title) {
            openURL(destination)
        }
    }
}
