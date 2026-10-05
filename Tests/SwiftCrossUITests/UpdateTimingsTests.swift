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

    @Test("the first update is reported on its own and left out of rest_median_ms")
    func firstApart() {
        // A slow first update (83 ms) then 2, 3, 4 ms: the overall median moves up to
        // 4 ms, the rest's stays at 3 ms.
        let sorted = [0.002, 0.003, 0.004, 0.083]
        #expect(
            UpdateTimings.summary(of: sorted, first: 0.083)
                == "update-stats: count=4 median_ms=4.0 p95_ms=83.0 max_ms=83.0 "
                + "first_ms=83.0 rest_median_ms=3.0"
        )
    }

    @Test("a single update has a first_ms but no rest to take a median of")
    func firstOnly() {
        #expect(
            UpdateTimings.summary(of: [0.083], first: 0.083)
                == "update-stats: count=1 median_ms=83.0 p95_ms=83.0 max_ms=83.0 first_ms=83.0"
        )
    }
}
