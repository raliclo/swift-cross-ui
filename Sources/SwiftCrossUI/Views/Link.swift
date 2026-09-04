import Foundation

/// A button that opens a URL with the system handler.
///
/// Composed from `Button` and the existing `openURL` environment action, so it
/// needs nothing new from any backend -- `BackendFeatures.ExternalURLs` was
/// already there and already implemented. See ``Stepper`` for why this batch
/// was chosen.
///
/// **Takes a String, not a view label, and that is a limit rather than a
/// choice.** SwiftUI's `Link` accepts any label. `Button` here does not -- its
/// own source says "a temporary button width solution until arbitrary labels
/// are supported" -- so a `Link<Label: View>` would have to fake it. The first
/// version of this file did, with an empty `Button("")` under `.overlay(label)`,
/// and that is worse than the limit it hides: this tree already recorded
/// `.overlay` swallowing pointer events (task #24), so the fake would have
/// produced a link that looks right and cannot be clicked. When `Button` gains
/// arbitrary labels, widen this in the same change.
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
/// **接受 String 而非 view 標籤，這是限制而非選擇。** SwiftUI 的 `Link` 接受任何標籤，但此處的
/// `Button` 不接受——它自己的原始碼寫著「a temporary button width solution until arbitrary
/// labels are supported」——因此 `Link<Label: View>` 只能造假。本檔的第一個版本就這麼做了：
/// 一個空的 `Button("")` 疊上 `.overlay(label)`。**那比它所掩蓋的限制更糟**：這棵樹已經記錄過
/// `.overlay` 會吞掉指標事件（任務 #24），所以那個假貨會產出一個「看起來正確、卻按不下去」的連結。
/// 待 `Button` 支援任意標籤時，請在同一次改動中一併放寬此處。
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
