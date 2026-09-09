import DefaultBackend
import Foundation
import SwiftCrossUI

// P21 input controls, for comparing WinUIBackend against GtkBackend.
//
// The widest uncovered surface. ToggleSwitch, ToggleButton and Checkbox appear
// in no other test app at all, and the rest are only touched incidentally by
// apps aimed at something else.
//
// Every control appears twice, enabled and disabled. Disabled is where backends
// usually part company: one greys the label, another dims the whole widget, a
// third leaves it looking live and simply ignores input. That last case is the
// one worth catching, because it looks correct in a screenshot.
//
// ContentUnavailableView is folded in here rather than given its own app; its
// surface is one view and it would not fill one.
//
// P21 輸入控制項，用於比較 WinUIBackend 與 GtkBackend。
//
// 目前未涵蓋範圍中最廣的一塊。ToggleSwitch、ToggleButton 與 Checkbox 完全沒有出現在任何
// 其他測試 app 中，其餘幾項也只是被以其他目的為主的 app 順帶碰到。
//
// 每個控制項都出現兩次：啟用與停用。停用狀態正是各 backend 最容易分歧之處：有的把標籤變灰、
// 有的讓整個 widget 變暗、也有的外觀完全不變而僅忽略輸入。最後一種最值得抓出來，因為它在
// 截圖上看起來完全正確。
//
// ContentUnavailableView 併入此處而非另闢一支 app；它只有一個視圖，不足以獨立成篇。
//
// Build this file as a standalone app target.

enum P21Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P21] \(message)")

        guard let data = "P21 \(Date()) \(message)\n".data(using: .utf8) else { return }
        // SCUI_DEBUG_EVENTS_DIR when a launcher sets it, so every app's log lands
        // in one place; unset, the launch directory exactly as before. The
        // contract is documented in testapp/test_support/test_common.zsh.
        // 有 SCUI_DEBUG_EVENTS_DIR 時取自該變數，讓每支 app 的 log 集中一處；未設定時仍為啟動
        // 目錄，行為與過去完全相同。該約定記載於 testapp/test_support/test_common.zsh。
        let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
            ?? FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p21-debug-events.log")
        if FileManager.default.fileExists(atPath: url.path),
            let handle = try? FileHandle(forWritingTo: url)
        {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    static func renderComplete() {
        guard !didAnnounceRender else { return }
        didAnnounceRender = true
        write("RENDER COMPLETE -- P21 ready for input control checks")
    }
}

@main
@HotReloadable
struct P21InputControlsApp: App {
    var body: some Scene {
        WindowGroup("P21 input controls") {
            #hotReloadable {
                P21RootView()
            }
        }
        .defaultSize(width: 820, height: 720)
    }
}

struct P21RootView: View {
    @State var toggleState = false
    @State var switchState = true
    @State var buttonToggleState = false
    @State var checkboxState = false
    @State var sliderValue = 0.4
    /// #126's stepped slider. Starts at 0.3, which is NOT on a 0.25 step.
    ///
    /// ~~That is the point: the first commit must pull it to 0.25 before anyone
    /// touches it.~~ **Wrong, and refuted by the capture that was taken to
    /// confirm it** -- the label read `Slider step 0.25 — 0.30`. It was written
    /// from the code that had just been added (`setValue(ofSlider:to:
    /// snapped(value))`) without noticing that the `Text` above reads the STATE,
    /// which that line does not touch. Snapping there would only have made the
    /// printed number and the thumb disagree.
    ///
    /// So 0.3 is the point for the opposite reason: `step:` governs values the
    /// USER produces, and an application's own initial value is left alone. This
    /// starting value shows that, and the assertion is what happens AFTER a
    /// click -- see `actions/win/P21-slider-step.csv`.
    ///
    /// #126 的分段滑桿。初始值為 0.3,**不**落在 0.25 的步進上。
    ///
    /// ~~而這正是重點:第一次 commit 必須在任何人碰它之前把它拉到 0.25。~~
    /// **這是錯的,而且是被「為了確認它而拍的那張擷圖」推翻的**——標籤讀作 `Slider step 0.25 — 0.30`。
    /// 那句話是照著剛加上去的程式碼(`setValue(ofSlider:to: snapped(value))`)寫的,卻沒注意到上方
    /// 的 `Text` 讀的是 **state**,而那一行根本不碰 state。在該處吸附,只會讓印出的數字與把手互相矛盾。
    ///
    /// 因此 0.3 是重點,但理由恰好相反:`step:` 管的是**使用者所產生**的值,而應用程式自己的初始值
    /// 不予變動。這個起始值展示的正是這件事,而斷言在於**點擊之後**發生什麼——見
    /// `actions/win/P21-slider-step.csv`。
    @State var steppedValue = 0.3
    @State var text = "editable"
    @State var secret = "hunter2"
    @State var editorText = "multi-line\ntext"
    @State var clicks = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Split into groups because a ViewBuilder takes at most 20
                // children and this screen has 34. Grouping by control family
                // is also how the sections read.
                // 分組是因為 ViewBuilder 最多接受 20 個子視圖，而本畫面有 34 個。依控制項
                // 類別分組，也正好符合各段落的閱讀方式。
                Text("P21: input controls")
                    .font(.system(size: 20))

                Text("backend -> \(String(describing: DefaultBackend.self))")

                Text(
                    "Each control appears enabled then disabled. Compare both "
                        + "states across backends, and check that a disabled "
                        + "control actually refuses input rather than only looking "
                        + "disabled."
                )

                Divider()

                // Buttons. The click counter is what proves a disabled button
                // refuses input: if the second button raises it, the disable is
                // cosmetic.
                // 按鈕。點擊計數器可證明停用的按鈕確實拒絕輸入：若第二個按鈕會使計數增加，
                // 表示該停用只是外觀上的。
                Group {
                Text("Button — clicks: \(clicks)")
                HStack(spacing: 10) {
                    Button("Enabled") { clicks += 1 }
                    Button("Disabled") { clicks += 1 }
                        .disabled(true)
                }

                Divider()

                Text("Toggle — \(toggleState)")
                HStack(spacing: 10) {
                    Toggle("Enabled", isOn: $toggleState)
                    Toggle("Disabled", isOn: $toggleState).disabled(true)
                }

                Text("ToggleSwitch style — \(switchState)")
                HStack(spacing: 10) {
                    Toggle("Enabled", isOn: $switchState).toggleStyle(.switch)
                    Toggle("Disabled", isOn: $switchState)
                        .toggleStyle(.switch)
                        .disabled(true)
                }

                Text("Toggle button style — \(buttonToggleState)")
                HStack(spacing: 10) {
                    Toggle("Enabled", isOn: $buttonToggleState).toggleStyle(.button)
                    Toggle("Disabled", isOn: $buttonToggleState)
                        .toggleStyle(.button)
                        .disabled(true)
                }

                Text("Checkbox style — \(checkboxState)")
                HStack(spacing: 10) {
                    Toggle("Enabled", isOn: $checkboxState).toggleStyle(.checkbox)
                    Toggle("Disabled", isOn: $checkboxState)
                        .toggleStyle(.checkbox)
                        .disabled(true)
                }

                Divider()

                // `init(value:in:)`. The `minimum:`/`maximum:` form is
                // deprecated and takes an unlabelled first argument, which is
                // what the earlier attempt here got wrong.
                // 使用 `init(value:in:)`。`minimum:`/`maximum:` 的形式已標記淘汰，且其第一個
                // 引數無標籤，先前此處正是寫錯了這一點。
                }

                Group {
                // NESTED Group, and it is load-bearing rather than tidiness.
                //
                // `ViewBuilder.buildBlock` goes up to 19 children (see
                // Builders/ViewBuilder.swift), and the enclosing Group was at
                // exactly 19 before the three stepped-slider views below were
                // added. The twentieth is not reported where it is added:
                // measured 2026-09-10, adding three views here produced
                // `error: extra argument in call` at `ContentUnavailableView`
                // sixty lines further down -- the first child past the limit --
                // and nothing named the slider or the arity. Nesting these six
                // into one child takes the outer block from 22 back to 17.
                //
                // 這個**巢狀 Group 是承重的**,不是為了整齊。
                //
                // `ViewBuilder.buildBlock` 最多支援 19 個子項(見 Builders/ViewBuilder.swift),
                // 而在下方三個分段滑桿的 view 被加入之前,外層 Group 恰好就是 19 個。第二十個**不會**
                // 在它被加入的地方被回報:2026-09-10 實測,在此加入三個 view,產生的是六十行之外
                // `ContentUnavailableView` 處的 `error: extra argument in call`——也就是超過上限後的
                // 第一個子項——而訊息中完全沒有提到滑桿,也沒有提到 arity。把這六個收進一個子項,
                // 外層區塊便由 22 回到 17。
                Group {
                Text("Slider — \(String(format: "%.2f", sliderValue))")
                Slider(value: $sliderValue, in: 0...1)
                Slider(value: $sliderValue, in: 0...1).disabled(true)

                // #126, added 2026-09-10. `step:` and the assertion that goes
                // with it.
                //
                // THE ASSERTION IS THE PRINTED VALUE, not the thumb. A stepped
                // slider looks like a continuous one in a still image -- both
                // draw a thumb somewhere along a track -- so the only thing that
                // can fail visibly is the number, which must be one of 0.00,
                // 0.25, 0.50, 0.75, 1.00 AFTER A CLICK, no matter where the
                // click lands. Any other reading means the step was ignored.
                //
                // "After a click" is not a hedge; it is the feature. Before any
                // input the label reads 0.30, because an initial value belongs
                // to the application and is not rewritten. See `steppedValue`
                // for the prediction that got this backwards and the capture
                // that refuted it.
                //
                // A SEPARATE binding from the two above, deliberately. Sharing
                // `sliderValue` would let the continuous sliders write 0.37 into
                // it and the stepped one would then be blamed for showing it.
                //
                // WHY NO BACKEND CHANGE: `UISlider` has no step API at all, so
                // the value has to be snapped in shared code regardless; doing
                // it there for all five is what makes them agree. See
                // `Slider.step`'s own documentation.
                //
                // #126,2026-09-10 加入。`step:` 以及隨附的斷言。
                //
                // **斷言是那個被印出來的數值,不是把手。** 在一張靜態圖裡,分段滑桿與連續滑桿長得
                // 一樣——兩者都在軌道上某處畫一個把手——因此唯一能夠「看得見地失敗」的是那個數字:
                // 無論拖曳停在哪裡,它都必須是 0.00、0.25、0.50、0.75、1.00 其中之一。
                // 出現任何其他讀數,都代表 step 被忽略了。
                //
                // **刻意使用與上方兩者不同的 binding。** 若共用 `sliderValue`,連續滑桿可以把 0.37
                // 寫進去,而顯示它的責任會被算到分段滑桿頭上。
                //
                // **為何不動 backend**:`UISlider` 根本沒有 step API,因此無論如何值都得在共用程式碼
                // 中吸附;為五個平台都在該處吸附,正是讓它們一致的原因。詳見 `Slider.step` 自己的文件。
                Text("Slider step 0.25 — \(String(format: "%.2f", steppedValue))")
                Slider(value: $steppedValue, in: 0...1, step: 0.25)
                    // LOGGED, because the assertion cannot be a capture here.
                    // P21's window is 848x749 and its content is longer than
                    // that, so these two sliders sit below the fold: a window
                    // capture shows the label above them and neither control.
                    // An on-screen assertion nobody can photograph is not an
                    // assertion, and this is the same lesson as #32 -- the log
                    // line is what an action file can check.
                    //
                    // `initial: false`, the default, so the launch value is not
                    // logged. Only user-produced values are the subject here,
                    // and a line for 0.3 at startup would be the one reading
                    // that could make a broken step look like a working one.
                    //
                    // **改用 log,因為此處的斷言不可能是擷圖。** P21 的視窗為 848x749,而其內容比這更長,
                    // 因此這兩個滑桿位於可視範圍之下:一張視窗擷圖只照得到它們上方的標籤,兩個控制項
                    // 都照不到。**一個沒有人能拍到的畫面斷言不是斷言**,而這與 #32 是同一個教訓
                    // ——log 行才是動作檔檢查得到的東西。
                    //
                    // 使用預設的 `initial: false`,因此啟動時的值不會被記錄。此處的主題只有「使用者
                    // 產生的值」,而一行啟動時的 0.3,正是那種「能讓壞掉的 step 看起來像正常」的讀數。
                    .onChange(of: steppedValue) {
                        P21Diagnostics.write(
                            "stepped slider \(String(format: "%.2f", steppedValue))"
                        )
                    }
                Slider(value: $steppedValue, in: 0...1, step: 0.25).disabled(true)

                // #126's label, added 2026-09-10 with the generic rewrite.
                //
                // THE ASSERTION IS THAT THE FOUR SLIDERS ABOVE STILL COMPILE.
                // `Slider` became `Slider<Label>`, and Swift has no default
                // generic arguments, so every existing `Slider(value:in:)` in
                // the project had to keep working through a constrained
                // extension (`where Label == EmptyView`). This app has four of
                // them; if the constraint were wrong they would fail to infer
                // and the build would stop. The build passing is that half.
                //
                // The visible half is this line: the word "Volume" must appear
                // to the LEFT of a track, and the four above must be unchanged
                // -- no stray gap where an empty label would have been. That is
                // why `hasLabel` exists instead of always wrapping in an HStack.
                //
                // #126 的標籤,2026-09-10 隨泛型改寫一併加入。
                //
                // **斷言是「上面那四個滑桿仍然編譯得過」。** `Slider` 變成了 `Slider<Label>`,
                // 而 Swift 沒有預設泛型引數,因此專案中每一個現有的 `Slider(value:in:)` 都必須
                // 透過受限 extension(`where Label == EmptyView`)繼續運作。本 app 就有四個;
                // 若那個約束寫錯,它們會推論失敗而讓建置停止。**建置通過就是那一半。**
                //
                // 看得見的另一半是這一行:「Volume」這個詞必須出現在軌道的**左邊**,而上方那四個
                // 必須毫無變化——不能出現「空標籤本來會在那裡」所留下的多餘間隙。那正是
                // `hasLabel` 存在、而非一律包進 HStack 的理由。
                Slider("Volume", value: $sliderValue, in: 0...1)
                }

                // The determinate form needs a label; the label-less
                // initialisers are the spinner and one taking a `Progress`.
                // 確定進度的形式需要標籤；無標籤的建構式只有轉圈指示器，以及接受 `Progress`
                // 的那一個。
                Text("ProgressView, same value")
                ProgressView(Text("determinate"), value: sliderValue)
                Text("ProgressView, indeterminate")
                ProgressView()

                Divider()

                Text("TextField — \(text)")
                TextField("Type here", text: $text)
                TextField("Disabled", text: $text).disabled(true)

                Text("SecureField")
                SecureField("Password", text: $secret)

                Text("TextEditor")
                TextEditor(text: $editorText)
                    .frame(height: 70)

                Divider()

                // Every part is a view builder; there is no string convenience.
                // 各部分皆為 view builder，並沒有接受字串的簡便形式。
                Text("ContentUnavailableView")
                ContentUnavailableView {
                    Text("Nothing here")
                } description: {
                    Text("The description line")
                }
                .frame(height: 110)
                }
            }
            .padding(18)
        }
        .onAppear {
            P21Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            P21Diagnostics.renderComplete()
        }
    }
}
