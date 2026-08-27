import DefaultBackend
import Foundation
import SwiftCrossUI

// P40 geometric effects: offset, rotation, scale and an arbitrary matrix.
//
// The second half of the visual-effects parity gap, added 2026-08-27 with
// BackendFeatures.GeometricEffects. P39 covers the compositing half.
//
// Two mistakes are specifically what this app is shaped to catch, because both
// are invisible under the obvious test:
//
//   * A TRANSPOSED matrix. Scaling matrices are symmetric, so a backend that
//     writes its 2x2 in the wrong order scales perfectly and rotates wrongly.
//     Every rotation cell here is asymmetric for that reason -- the label sits
//     off-centre, so a mirrored or transposed result reads differently from a
//     correct one.
//   * A DOUBLE-APPLIED anchor. SwiftCrossUI bakes the anchor into the matrix,
//     so a backend that also applies its own default origin rotates about the
//     centre twice. The "rotate 30 topLeading" cell is the one that shows it:
//     with the anchor honoured it pivots about its own top-left corner and
//     swings down-right; with the anchor applied twice it stays centred.
//
// Layout is deliberately unchanged by all of this -- that is SwiftUI's rule and
// the reason these are effects and not layout. Each cell keeps a fixed slot, so
// a transformed tile is expected to spill outside its slot and may overlap its
// neighbour. Overlap is correct here. A cell that pushes its neighbours aside is
// the defect.
//
// P40 幾何效果：offset、旋轉、縮放，以及任意矩陣。
//
// 視覺效果落差的後半部，於 2026-08-27 與 BackendFeatures.GeometricEffects 一同加入。前半部
//（合成效果）由 P39 涵蓋。
//
// 本 app 的形狀是專為兩種錯誤而設計的，因為兩者在最顯而易見的測試下都看不出來：
//
//   * 矩陣被轉置。縮放矩陣是對稱的，因此把 2x2 順序寫錯的 backend 縮放完全正常、旋轉卻是錯的。
//     此處每個旋轉格子都刻意不對稱——標籤偏離中心，如此鏡射或轉置的結果就會與正確結果不同。
//   * 錨點被套用兩次。SwiftCrossUI 已把錨點併入矩陣，因此若 backend 又套用自己的預設原點，就會
//     繞著中心旋轉兩次。「rotate 30 topLeading」那一格正是顯示此問題的格子：錨點被正確遵守時，
//     它會繞自己的左上角旋轉、向右下擺動；被套用兩次時，它則會維持置中。
//
// 上述所有效果都刻意不改變版面——那是 SwiftUI 的規則，也正是它們屬於「效果」而非「版面」的理由。
// 每個格子都保有固定的位置，因此被變換過的方塊預期會溢出其格位，甚至與鄰居重疊。此處重疊是正確
// 的；會把鄰居推開的格子才是缺陷。
//
//     zsh testapp/run.zsh P40
//
// Build this file as a standalone app target.

@main
@HotReloadable
struct P40GeometricEffectsApp: App {
    var body: some Scene {
        WindowGroup("P40 geometric effects") {
            #hotReloadable {
                P40RootView()
            }
        }
        .defaultSize(width: 900, height: 640)
    }
}

struct P40RootView: View {
    static let samples: [(String, GeometricEffect)] = [
        ("none (control)", .identity),
        ("offset x40 y20", GeometricEffect(translation: SIMD2(40, 20))),
        ("scale 0.6", GeometricEffect(scale: SIMD2(0.6, 0.6))),
        ("scale x1.6 y0.7", GeometricEffect(scale: SIMD2(1.6, 0.7))),
        ("rotate 30 centre", GeometricEffect(rotation: .degrees(30))),
        (
            "rotate 30 topLeading",
            GeometricEffect(rotation: .degrees(30), anchor: UnitPoint(x: 0, y: 0))
        ),
        // A shear, which none of the named modifiers can express. It is here to
        // prove the matrix reaches the backend intact rather than being rebuilt
        // from scale and rotation on the way.
        // 一個剪切變換，是所有具名 modifier 都無法表達的。它的作用是證明矩陣原封不動抵達 backend，
        // 而非在途中由 scale 與 rotation 重新組合而成。
        (
            "shear (matrix)",
            GeometricEffect(
                matrix: AffineTransform(
                    linearTransform: SIMD4(x: 1, y: 0.4, z: 0, w: 1),
                    translation: .zero
                )
            )
        ),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("P40: geometric effects")
                .font(.system(size: 20))

            Text("backend -> \(String(describing: DefaultBackend.self))")

            Text("Tiles may spill outside their slot and overlap. Neighbours moving aside is the bug.")

            VStack(alignment: .leading, spacing: 30) {
                P40Row(samples: Array(Self.samples[0..<3]))
                P40Row(samples: Array(Self.samples[3..<5]))
                P40Row(samples: Array(Self.samples[5..<7]))

                // A bare Text under the same rotation, with no Color views and
                // no nested containers inside the transformed subtree. It
                // narrows what a rendering failure means: if the tiles above
                // fail and this one does not, the backend can transform a leaf
                // and not a subtree, which is a different problem from not
                // being able to transform at all.
                //
                // 同樣旋轉之下的一段純 Text，其被變換的子樹中既無 Color view、也無巢狀容器。它可
                // 縮小「繪製失敗」的意涵：若上方各方塊失敗而此處沒有，代表該 backend 能變換單一
                // 葉節點卻不能變換子樹——那與「完全無法變換」是不同的問題。
                HStack(spacing: 40) {
                    VStack(spacing: 4) {
                        Text("bare text, rotate 30")
                            .font(.system(size: 12))
                        Text("Hamburgefonstiv")
                            .font(.system(size: 18))
                            .rotationEffect(.degrees(30))
                    }
                    .frame(width: 260, height: 90)

                    VStack(spacing: 4) {
                        Text("bare text, offset only")
                            .font(.system(size: 12))
                        Text("Hamburgefonstiv")
                            .font(.system(size: 18))
                            .offset(x: 20, y: 6)
                    }
                    .frame(width: 260, height: 90)
                }
            }
        }
        .padding(18)
    }
}

struct P40Row: View {
    var samples: [(String, GeometricEffect)]

    var body: some View {
        HStack(spacing: 40) {
            ForEach(samples, id: \.0) { sample in
                P40Cell(label: sample.0, effect: sample.1)
            }
        }
    }
}

struct P40Cell: View {
    var label: String
    var effect: GeometricEffect

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 12))

            // Asymmetric on both axes on purpose. A centred square tells you
            // nothing about whether a transform was transposed or mirrored --
            // it looks identical either way. The stripe down one side and the
            // text pinned to the top give the tile a distinguishable
            // orientation.
            // 刻意在兩個軸上都不對稱。一個置中的正方形無法告訴你變換是否被轉置或鏡射——兩種情況
            // 看起來完全相同。單側的色條與固定於頂端的文字，賦予這個方塊可辨識的方向性。
            HStack(spacing: 0) {
                Color.orange
                    .frame(width: 14, height: 80)

                VStack(spacing: 0) {
                    Text("TOP")
                        .font(.system(size: 13))
                    Color.blue
                        .frame(width: 90, height: 58)
                }
            }
            .geometricEffect(effect)
        }
        .frame(width: 180, height: 120)
    }
}
