import DefaultBackend
import Foundation
import SwiftCrossUI

// P29 visual fidelity: output that is wrong with no diagnostic at all.
//
// Every other Pn checks something a log could in principle report. These cannot
// be: the app does not crash, nothing is logged, and each case looks like a
// plausible rendering until it is put beside the backend that gets it right. A
// screenshot is the only instrument.
//
// P29 視覺保真度：輸出錯誤、卻完全沒有任何診斷訊息的情況。
//
// 其他每一個 Pn 檢查的都是「日誌原則上有可能回報」的事。這些則不然：app 不會崩潰、什麼也不會被
// 記錄，而每一個案例在被擺到「做對的那個 backend」旁邊之前，看起來都像是合理的繪製結果。截圖是
// 唯一的量測工具。
//
// Build this file as a standalone app target.

enum P29Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func renderComplete() {
        guard isEnabled, !didAnnounceRender else { return }
        didAnnounceRender = true
        print("[P29] RENDER COMPLETE -- compare against the other backend by screenshot")
    }
}

@main
@HotReloadable
struct P29VisualFidelityApp: App {
    var body: some Scene {
        WindowGroup("P29 visual fidelity") {
            #hotReloadable {
                P29RootView()
            }
        }
        .defaultSize(width: 720, height: 560)
    }
}

struct P29RootView: View {
    @State var editorText = "Type here if this is not disabled"
    @State var enabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("P29: visual fidelity")
                .font(.system(size: 20))

            Text("backend -> \(String(describing: DefaultBackend.self))")

            // 1. Indeterminate progress. A bar with no value must animate; one
            //    filled to 0% and never moving reads as "stuck", which is a
            //    different message from "working". The determinate bar beside it
            //    is the control -- if both look identical, the indeterminate one
            //    is not indeterminate.
            //
            //    Note the spelling: `ProgressView()` with no arguments is a
            //    *spinner*, not a bar, so it cannot show this. The indeterminate
            //    bar is `ProgressView(_:value:)` with a nil value, which is the
            //    only route to a bar with nothing to report.
            //
            //    不確定進度。沒有值的 bar 必須有動畫；一條填到 0% 且從不移動的 bar 會被讀成
            //    「卡住」，那與「進行中」是不同的訊息。旁邊的確定進度 bar 為對照組——若兩者看起來
            //    相同，代表那個「不確定」的並不是不確定。
            //
            //    注意寫法：不帶參數的 `ProgressView()` 是 *spinner* 而非 bar，因此無法呈現此項。
            //    不確定進度的 bar 是 value 為 nil 的 `ProgressView(_:value:)`，那是「一條無事可報
            //    的 bar」的唯一途徑。
            Text("1. Indeterminate vs determinate progress bar")
                .font(.system(size: 15))
            HStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text("indeterminate bar").font(.system(size: 12))
                    ProgressView("", value: Double?.none)
                        .frame(width: 220)
                }
                VStack(spacing: 4) {
                    Text("determinate 40%").font(.system(size: 12))
                    ProgressView(value: 0.4)
                        .frame(width: 220)
                }
                VStack(spacing: 4) {
                    Text("spinner").font(.system(size: 12))
                    ProgressView()
                }
            }

            // 2. Rounded clipping. The orange block is larger than its frame, so
            //    the corners are where the clip shows: a rectangular clip leaves
            //    square orange corners poking out under the rounded border.
            //    圓角裁切。橘色方塊大於其 frame，因此四角正是裁切現形之處：矩形裁切會在圓角邊框
            //    之下留下方形的橘色角。
            Text("2. cornerRadius clips to the rounded shape")
                .font(.system(size: 15))
            ZStack {
                Color(red: 0.20, green: 0.45, blue: 0.85)
                Color(red: 0.95, green: 0.55, blue: 0.15)
                    .frame(width: 260, height: 160)
            }
            .frame(width: 200, height: 120)
            .cornerRadius(24)

            // 3. TextEditor and .disabled. Every other control greys out and
            //    refuses input; this one used to stay editable while looking the
            //    same, so the only way to tell was to type into it.
            //    TextEditor 與 .disabled。其他每個控制項都會變灰並拒絕輸入；唯獨這個先前仍可編輯
            //    而外觀不變，因此唯一的判別方式是實際去輸入。
            Text("3. TextEditor honours .disabled")
                .font(.system(size: 15))
            // A note for anyone testing this on Windows, because it cost an hour
            // here: a GTK app is single-instance by application ID, so if an
            // earlier run is still alive the next launch hands its request to
            // that instance and exits 0 with no window and no output. It looks
            // exactly like a launch failure, and it invalidates bisection -- two
            // separate "findings" in this app's history turned out to be leftover
            // processes rather than anything in the code. Kill leftovers first.
            //
            // 給在 Windows 上測試此項的人一則提醒，因為它在此處耗掉了一小時：GTK app 以
            // application ID 實施單一實例，因此若先前的執行仍存活，下一次啟動會把請求交給該實例，
            // 並以結束碼 0 退出，沒有視窗也沒有輸出。它看起來與啟動失敗一模一樣，而且會使二分法
            // 失效——此 app 歷史上兩則各自獨立的「發現」，最後都證實是殘留的行程而非程式碼問題。
            // 請先清除殘留行程。
            HStack(spacing: 12) {
                TextEditor(text: $editorText)
                    .frame(width: 300, height: 60)
                    .disabled(!enabled)
                Button(enabled ? "Disable it" : "Enable it") {
                    enabled.toggle()
                }
            }
            Text("Editor is \(enabled ? "enabled" : "disabled") -- try typing in it")
        }
        .padding(18)
        .onAppear {
            P29Diagnostics.renderComplete()
        }
    }
}
