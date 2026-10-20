// P112: RadialGradient radii are points, as in SwiftUI, in a shape fill and in text.
//
// Until 2026-10-20 a RadialGradient used as a shape style (`.fill(RadialGradient(...))`,
// `.foregroundStyle` on Text) took its radii as units of the shape's shorter side on
// every backend, so `endRadius: 40` covered 3200 pt of an 80 pt square. SwiftUI reads
// them as points -- the same value it uses for a RadialGradient view.
//
// Three shapes of different sizes, each filled with the same gradient: solid red to
// 20 pt from the centre, then red to blue by 40 pt, blue beyond. Under the text, the
// same gradient on a 48 pt word.
//
// Pass: in every shape the solid red disc is 40 pt across (2 x 20) and centred, and
// blue starts 40 pt from the centre, whatever the shape's size. Radii read as units
// of the shorter side paint each shape entirely red.
//
// Second row (2026-10-20, AngularGradient as a shape style, new that day): red,
// green, blue, red round a full turn from three o'clock, clockwise, in a 160x80
// rectangle and a 100x100 circle; the same circle with startAngle 90 (the red starts
// at six o'clock); and red to blue over startAngle 0 ... endAngle 180 in a 100x100
// square, blue from nine o'clock round to three. Pass: 25 pt from each centre the
// colour at the angle is the stop there -- red at 0, green at 120, blue at 240 degrees
// (each turned by 90 in the third) -- and the partial one is purple at 90, blue at 270.
//
// P112:RadialGradient 的半徑以點為單位(同 SwiftUI),用在形狀填色與文字上皆然。2026-10-20 之前，作為形狀樣式
// 的 RadialGradient 在每個 backend 上都把半徑當成「形狀較短邊」的倍數，`endRadius: 40` 在 80 pt 的方塊上等於
// 3200 pt。三個大小不同的形狀填同一個漸層：距中心 20 pt 內純紅，40 pt 處漸變為藍，之外是藍。通過：每個形狀中的
// 純紅圓盤直徑都是 40 pt 且置中，藍色從距中心 40 pt 開始，與形狀大小無關。以較短邊為單位時，每個形狀會全紅。

import DefaultBackend
import SwiftCrossUI

@MainActor let p112Gradient = RadialGradient(
    colors: [Color(red: 1, green: 0, blue: 0), Color(red: 1, green: 0, blue: 0), Color(red: 0, green: 0, blue: 1)],
    center: .center,
    startRadius: 0,
    endRadius: 40
)

@MainActor let p112Angular = AngularGradient(
    colors: [
        Color(red: 1, green: 0, blue: 0), Color(red: 0, green: 1, blue: 0), Color(red: 0, green: 0, blue: 1),
        Color(red: 1, green: 0, blue: 0),
    ],
    center: .center
)
@main
struct P112App: App {
    var body: some Scene {
        WindowGroup("P112 radial radii") {
            #hotReloadable {
                P112View()
            }
        }
        .defaultSize(width: 700, height: 520)
    }
}

struct P112View: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("P112: RadialGradient radii in points (red disc 40 pt across in each)")
            HStack(alignment: .top, spacing: 40) {
                Rectangle()
                    .fill(p112Gradient)
                    .frame(width: 80, height: 80)
                Rectangle()
                    .fill(p112Gradient)
                    .frame(width: 240, height: 120)
                Circle()
                    .fill(p112Gradient)
                    .frame(width: 120, height: 120)
            }
            HStack(alignment: .top, spacing: 40) {
                Rectangle()
                    .fill(p112Angular)
                    .frame(width: 160, height: 80)
                Circle()
                    .fill(p112Angular)
                    .frame(width: 100, height: 100)
            }
            HStack(alignment: .top, spacing: 40) {
                Circle()
                    .fill(AngularGradient(gradient: p112Angular.gradient, center: .center, angle: .degrees(90)))
                    .frame(width: 100, height: 100)
                Rectangle()
                    .fill(
                        AngularGradient(
                            colors: [Color(red: 1, green: 0, blue: 0), Color(red: 0, green: 0, blue: 1)],
                            center: .center, startAngle: .zero, endAngle: .degrees(180)
                        )
                    )
                    .frame(width: 100, height: 100)
            }
            HStack(spacing: 40) {
                Text("RADIAL")
                    .font(.system(size: 48))
                    .foregroundStyle(p112Gradient)
                Text("ANGULAR")
                    .font(.system(size: 48))
                    .foregroundStyle(p112Angular)
            }
        }
        .padding(20)
    }
}
