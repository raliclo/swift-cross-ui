import Testing

@testable @_spi(Backends) import SwiftCrossUI

/// Pins the condition under which a stack complains about running out of space.
///
/// **The report used to fire when nothing had run out.** A child offered zero is
/// normal whenever there is simply nothing left over -- a `Spacer` with no slack
/// takes zero, correctly -- and the message nonetheless said "ran out of space"
/// and named the `Spacer` as the starved child. Reported 2026-09-10 from P44:
/// *"9 children were offered 643 and took 643 ... firstStarvedChild=Spacer"*,
/// where offered and took are equal.
///
/// These tests exist because that fix is one comparison and is easy to lose.
/// Deleting the guard makes the first test fail; weakening it into "never
/// report" makes the second fail.
///
/// 釘住「一個 stack 在什麼條件下才會抱怨空間不足」。
///
/// **這則回報過去會在什麼都沒有不夠用時發出。** 只要單純沒有剩餘,一個子元件被分到零就是正常的
/// ——沒有餘裕的 `Spacer` 正確地拿到零——而那則訊息卻仍然說「ran out of space」,並指名該 `Spacer`
/// 為挨餓者。2026-09-10 由 P44 回報:*「9 children were offered 643 and took 643 …
/// firstStarvedChild=Spacer」*,其中 offered 與 took 相等。
///
/// 這些測試之所以存在,是因為那項修正只是一個比較式,很容易被弄丟。刪掉那個守衛會讓第一個測試失敗;
/// 把它弱化成「永不回報」則會讓第二個測試失敗。
@MainActor
@Suite("Stack overflow reporting")
struct StackOverflowReportTests {
    /// A stack that used exactly what it was offered has not run out of space.
    /// 一個「用掉的正好等於被給的」的 stack，並沒有空間不足。
    @Test("a child offered zero is not reported when the stack fits")
    func fittingStackIsNotReported() {
        // The numbers from the P44 report, unchanged.
        // 直接採用 P44 那份回報中的數字，未經更動。
        #expect(
            !StackOverflowReport.wouldReport(
                proposedLength: 643,
                usedLength: 643,
                starvedChild: "Spacer"
            )
        )
    }

    /// The case the report was written for still reports.
    ///
    /// Four columns offered 350 while needing 528, the fourth `Text` offered
    /// zero and wrapping one character per line -- the situation recorded beside
    /// the `share == 0` site in `LayoutSystem`.
    /// 這則回報原本要抓的情況仍然會被回報。四欄在需要 528 點時只被提議 350 點，第四個 `Text` 被提議
    /// 零寬、每行一個字——即 `LayoutSystem` 中 `share == 0` 那一處旁邊所記載的情況。
    @Test("a child offered zero IS reported when the stack overflowed")
    func overflowingStackIsReported() {
        #expect(
            StackOverflowReport.wouldReport(
                proposedLength: 350,
                usedLength: 528,
                starvedChild: "Text"
            )
        )
    }

    /// No starved child, no report, however badly the stack overflowed.
    ///
    /// A stack whose children each took more than their share is a layout the
    /// app asked for, and the existing guard says so; this pins that the new
    /// comparison did not replace it.
    /// 沒有挨餓的子元件就不回報，無論該 stack 溢出得多嚴重。
    ///
    /// 一個「每個子元件都拿得比自己那份多」的 stack，是 app 自己要求的版面，而既有的守衛正是這麼說的；
    /// 此處釘住的是「新加的比較並沒有取代它」。
    @Test("no report without a starved child")
    func noStarvedChildIsNotReported() {
        #expect(
            !StackOverflowReport.wouldReport(
                proposedLength: 350,
                usedLength: 528,
                starvedChild: nil
            )
        )
    }
}
