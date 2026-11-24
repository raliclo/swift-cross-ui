import Testing

@testable @_spi(Backends) import SwiftCrossUI

/// blendMode(_:): what the modifier hands a backend, and how a blend mode combines
/// and animates. How it looks is P132's screenshot; the backends' tables are keyed
/// by the cases' declaration order, which is pinned here.
///
/// blendMode(_:):modifier 交給 backend 的內容，以及混合模式如何組合與動畫。外觀由 P132 的截圖檢查；各 backend
/// 的對照表以各 case 的宣告順序為鍵，該順序在此固定。
@MainActor
@Suite("Blend mode")
struct BlendModeTests {
    @Test("The modifier carries the mode in a VisualEffect, and normal is the identity")
    func modifierCarriesTheMode() throws {
        let view = Color.red.blendMode(.multiply)
        let modifier = try #require(view as? VisualEffectModifier<Color>)
        #expect(modifier.effect.blendMode == .multiply)
        #expect(!modifier.effect.isIdentity)
        #expect(VisualEffect(blendMode: .normal).isIdentity)
        #expect(VisualEffect.identity.blendMode == .normal)
    }

    @Test("Declaration order, which AndroidBackend's and GtkBackend's tables follow")
    func declarationOrder() {
        let names = BlendMode.allCases.map { "\($0)" }
        #expect(names == [
            "normal", "multiply", "screen", "overlay", "darken", "lighten",
            "colorDodge", "colorBurn", "softLight", "hardLight", "difference",
            "exclusion", "hue", "saturation", "color", "luminosity", "sourceAtop",
            "destinationOver", "destinationOut", "plusDarker", "plusLighter",
        ])
    }

    @Test("Combined transitions: a non-normal mode wins over normal")
    func combined() {
        let multiply = AnyTransition.Effects(visual: VisualEffect(blendMode: .multiply))
        let plain = AnyTransition.Effects(visual: VisualEffect(opacity: 0.5))
        #expect(multiply.combined(with: plain).visual.blendMode == .multiply)
        #expect(plain.combined(with: multiply).visual.blendMode == .multiply)
        let screen = AnyTransition.Effects(visual: VisualEffect(blendMode: .screen))
        #expect(multiply.combined(with: screen).visual.blendMode == .screen)
    }

    @Test("A blend mode does not interpolate: it is the end's at once")
    func interpolation() {
        let start = VisualEffect(opacity: 0, blendMode: .normal)
        let end = VisualEffect(opacity: 1, blendMode: .difference)
        let quarter = VisualEffect.interpolated(from: start, to: end, progress: 0.25)
        #expect(quarter.blendMode == .difference)
        #expect(quarter.opacity == 0.25)
    }
}
