import Testing

@testable import SwiftCrossUI

/// ``GeometryProxy/frame(in:)``'s arithmetic, at the level where it is decided.
///
/// The backends are what actually answer "where is this widget", and P63 is
/// what checks their answers against pixels. These check the part that is the
/// same on all five: which origin each space subtracts, and what happens when
/// there is no origin to subtract.
///
/// ``GeometryProxy/frame(in:)`` 的算式，測在它被決定的那個層級。
///
/// 真正回答「這個 widget 在哪」的是那些 backend，而對著像素檢查它們答案的是 P63。此處檢查的是
/// 五個 backend 上都相同的那一部分:每一種座標系減去的是哪一個原點，以及在沒有原點可減時會怎樣。
@MainActor
@Suite("GeometryProxy.frame(in:)")
struct GeometryProxyTests {
    @Test("local is always the origin, whatever the view knows about itself")
    func localIsAlwaysZero() {
        let proxy = GeometryProxy(
            size: ViewSize(220, 60),
            originInWindow: SIMD2(92, 287),
            namedOrigins: ["box": SIMD2(68, 256)]
        )
        let frame = proxy.frame(in: .local)
        #expect(frame.x == 0 && frame.y == 0)
        #expect(frame.width == 220 && frame.height == 60)
    }

    @Test("global is the window origin, unchanged")
    func globalIsTheWindowOrigin() {
        let proxy = GeometryProxy(size: ViewSize(220, 60), originInWindow: SIMD2(92, 287))
        let frame = proxy.frame(in: .global)
        #expect(frame.x == 92 && frame.y == 287)
    }

    @Test("named subtracts the named space's own origin")
    func namedIsRelativeToItsSpace() {
        // The numbers are P63's, measured against pixels on 2026-09-10: the
        // reader at (92, 287) inside a box whose corner is at (68, 256).
        // 這些數字取自 P63，於 2026-09-10 對著像素量得:一個位於 (92, 287) 的 reader，其所在盒子的
        // 角落位於 (68, 256)。
        let proxy = GeometryProxy(
            size: ViewSize(260, 90),
            originInWindow: SIMD2(92, 287),
            namedOrigins: ["box": SIMD2(68, 256)]
        )
        let frame = proxy.frame(in: .named("box"))
        #expect(frame.x == 24 && frame.y == 31)
    }

    @Test("An unknown name answers in window coordinates, not zero")
    func unknownNameFallsBackToGlobal() {
        // Zero would look like a view parked in the corner. Window coordinates
        // are a wrong answer somebody can SEE, which is the difference this
        // choice is about.
        // 零看起來會像一個停在角落的 view。視窗座標則是一個**看得見**的錯誤答案，而這正是這個選擇
        // 所關乎的差別。
        let proxy = GeometryProxy(
            size: ViewSize(260, 90),
            originInWindow: SIMD2(92, 287),
            namedOrigins: ["box": SIMD2(68, 256)]
        )
        let frame = proxy.frame(in: .named("typo"))
        #expect(frame.x == 92 && frame.y == 287)
    }

    @Test("Before it is placed, every space answers as local does")
    func noOriginYet() {
        let proxy = GeometryProxy(size: ViewSize(260, 90), originInWindow: nil)
        for space in [CoordinateSpace.local, .global, .named("box")] {
            let frame = proxy.frame(in: space)
            #expect(frame.x == 0 && frame.y == 0, "\(space) before placement")
            #expect(frame.width == 260, "the SIZE is known even then")
        }
    }
}
