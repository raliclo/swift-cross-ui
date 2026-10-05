import Foundation
import Testing
@testable import SwiftCrossUI

@Suite("UpdateTimings")
struct UpdateTimingsTests {
    @Test("an empty run says count=0 rather than inventing numbers")
    func empty() {
        #expect(UpdateTimings.summary(of: []) == "update-stats: count=0")
    }

    @Test("median, p95 and max are read from the sorted durations")
    func ranks() {
        // 1 ms .. 100 ms: median is the 50.5th of 100 -> index 50 (51 ms), p95 index 94 (95 ms).
        let sorted = (1...100).map { Double($0) / 1000 }
        #expect(
            UpdateTimings.summary(of: sorted)
                == "update-stats: count=100 median_ms=51.0 p95_ms=95.0 max_ms=100.0"
        )
    }

    @Test("one sample is its own median, p95 and max")
    func single() {
        #expect(
            UpdateTimings.summary(of: [0.0042])
                == "update-stats: count=1 median_ms=4.2 p95_ms=4.2 max_ms=4.2"
        )
    }
}
