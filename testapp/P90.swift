// P90: the wheel date pickers in one region after another (2026-10-10).
//
// A wheel is not the same wheel everywhere. UIDatePicker orders its columns as the region writes a
// date -- August | 24 | 2025 in en_US, 24 | August | 2025 in en_GB, 2025年 | 8月 | 24日 in zh_TW --
// and puts AM/PM before the hours in some (zh, ko) and leaves it out in others (de, fr). P41 only ever
// showed the simulator's own region, so AndroidBackend's wheels were drawn to en_US and en_GB alone.
//
// The buttons set `\.locale` for the three wheels below them: a date, a time, and a date with a time.
// An action file presses one by its text (`taplabel`) and the capture is compared across backends.
//
// Pass: for each region the three wheels show the same columns, in the same order, with the same text
// on every backend that has a wheel style.
//
// P90：一個地區接一個地區地看 wheel 樣式的日期選擇器(2026-10-10)。滾輪並不是到處都一樣:UIDatePicker 依地區書寫日期的
// 方式排欄位——en_US 是 August | 24 | 2025,en_GB 是 24 | August | 2025,zh_TW 是 2025年 | 8月 | 24日——有些地區把
// 上午／下午放在小時之前(zh、ko),有些沒有這一欄(de、fr)。P41 只顯示過模擬器自己的地區，所以 AndroidBackend 的滾輪只照
// en_US 與 en_GB 畫過。按鈕替下方三個滾輪(日期、時間、日期加時間)設定 `\.locale`;動作檔以文字按下其中一個(`taplabel`),
// 擷圖再跨 backend 比對。通過：每個地區的三個滾輪，在每個有 wheel 樣式的 backend 上欄位相同、順序相同、文字相同。

import DefaultBackend
import Foundation
@_spi(Backends) import SwiftCrossUI

@main
struct P90App: App {
    var body: some Scene {
        WindowGroup("P90 wheels by region") {
            #hotReloadable {
                P90View()
            }
        }
        .defaultSize(width: 400, height: 820)
    }
}

struct P90View: View {
    static let regions: [[String]] = [
        ["en_US", "en_GB", "de_DE", "fr_FR", "es_ES", "it_IT"],
        ["nl_NL", "sv_SE", "fi_FI", "pl_PL", "hu_HU", "ru_RU"],
        ["tr_TR", "pt_BR", "zh_TW", "zh_CN", "ja_JP", "ko_KR"],
        ["th_TH", "hi_IN", "he_IL", "ar_SA"],
    ]

    static let start = Date(timeIntervalSince1970: 1_756_000_000)

    @State var region = "en_US"
    @State var date = P90View.start
    @State var time = P90View.start
    @State var both = P90View.start

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("P90: wheels in \(region)")
                .font(.system(size: 13))

            ForEach(P90View.regions, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { name in
                        Button(name) { region = name }
                            .font(.system(size: 13))
                    }
                }
            }

            #if os(macOS)
                Text("The wheel style is unavailable on macOS")
            #else
                DatePicker("", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.wheel)
                DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                DatePicker("", selection: $both, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.wheel)
            #endif
        }
        .environment(\.locale, Locale(identifier: region))
        .padding(8)
    }
}
