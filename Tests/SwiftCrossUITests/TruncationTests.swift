import Testing

@testable import SwiftCrossUI

/// Text's own truncation, used for truncationMode(.head) and (.middle) on every
/// backend: the longest form with an ellipsis at the chosen place that still fits.
/// Text 自己的截斷，供每個 backend 的 truncationMode(.head) 與 (.middle) 使用：在指定位置加上刪節號、
/// 且仍放得下的最長形式。
struct TruncationTests {
    let sentence = "A sentence too long for its frame"

    /// Fits when it is at most ten characters. / 不超過十個字元時放得下。
    func fitsTen(_ text: String) -> Bool {
        text.count <= 10
    }

    @Test("Head keeps the end of the text after an ellipsis")
    func head() {
        let result = Text.truncated(sentence, mode: .head, fits: fitsTen)
        #expect(result == "…its frame")
    }

    @Test("Middle keeps both ends around an ellipsis")
    func middle() {
        let result = Text.truncated(sentence, mode: .middle, fits: fitsTen)
        #expect(result == "A sen…rame")
    }

    @Test("Tail keeps the start of the text before an ellipsis")
    func tail() {
        let result = Text.truncated(sentence, mode: .tail, fits: fitsTen)
        #expect(result == "A sentenc…")
    }

    @Test("Nothing fits: only the ellipsis is left")
    func nothingFits() {
        let result = Text.truncated(sentence, mode: .middle) { $0.count <= 1 }
        #expect(result == "…")
    }
}
