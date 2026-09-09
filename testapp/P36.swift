import DefaultBackend
import Foundation
import SwiftCrossUI

// P36 API-shape compatibility: SwiftCrossUI forms beside SwiftUI call-site gaps.

enum P36Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P36] \(message)")
        let data = Data("P36 \(Date()) \(message)\n".utf8)
        // SCUI_DEBUG_EVENTS_DIR when a launcher sets it, so every app's log lands
        // in one place; unset, the launch directory exactly as before. The
        // contract is documented in testapp/test_support/test_common.zsh.
        // 有 SCUI_DEBUG_EVENTS_DIR 時取自該變數，讓每支 app 的 log 集中一處；未設定時仍為啟動
        // 目錄，行為與過去完全相同。該約定記載於 testapp/test_support/test_common.zsh。
        let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
            ?? FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p36-debug-events.log")
        if let handle = try? FileHandle(forWritingTo: url) {
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
        write("RENDER COMPLETE -- P36 ready for API-shape checks")
    }
}

@main
@HotReloadable
struct P36APIShapeApp: App {
    var body: some Scene {
        WindowGroup("P36 API shape compatibility") {
            #hotReloadable {
                P36RootView()
            }
        }
        // 620 -> 700 when the textFieldStyle row was added below. The two extra
        // rows pushed the closing explanatory Text past the old height, and a
        // window that clips its own last line reads as a layout bug in whatever
        // screenshot it appears in.
        // 加入下方的 textFieldStyle 列時由 620 改為 700。多出的兩列把結尾的說明 Text 推出了原本的
        // 高度，而一個把自己最後一行裁掉的視窗，在任何它出現的截圖裡都會被讀成佈局缺陷。
        .defaultSize(width: 820, height: 700)
    }
}

/// A text field style written *outside* SwiftCrossUI, which is the whole point
/// of ``TextFieldStyle`` being an open protocol here.
///
/// SwiftUI's `TextFieldStyle` is closed and empty -- it declares no
/// requirements, so `struct MyStyle: TextFieldStyle` compiles into something
/// nothing will ever call. This one has `makeView`, so this type genuinely
/// draws the field, and its presence in a test app is the check that the
/// protocol is usable from application code rather than only from inside the
/// module.
///
/// **The inner `.textFieldStyle(.plain)` is load-bearing, not decoration.**
/// `TextField`'s body asks the environment for a style and calls its
/// `makeView`. Without the override, the `TextField` built here would find this
/// same style still in the environment and call back into this method, forever.
/// Overriding it to a built-in style is what terminates the recursion, and it is
/// the same shape SwiftUI's own custom-style protocols require.
///
/// 一個寫在 SwiftCrossUI **之外**的文字輸入框樣式——這正是此處 ``TextFieldStyle`` 之所以是開放
/// protocol 的全部意義。
///
/// SwiftUI 的 `TextFieldStyle` 是封閉且空白的——它沒有宣告任何需求，因此
/// `struct MyStyle: TextFieldStyle` 編譯出來的東西永遠不會有人呼叫。此處這個帶有 `makeView`，
/// 所以這個型別是真的在繪製該欄位；而它出現在測試 app 中，正是「此 protocol 從應用程式端可用、
/// 而不只在模組內部可用」的驗證。
///
/// **內層的 `.textFieldStyle(.plain)` 是承重結構，不是裝飾。** `TextField` 的 body 會向 environment
/// 索取一個 style 並呼叫它的 `makeView`。少了那個覆寫，此處建立的 `TextField` 會在 environment 中
/// 找到同一個 style，於是再次呼叫本方法，永無止境。把它覆寫成某個內建 style，才是終止該遞迴的東西。
struct CaretTextFieldStyle: TextFieldStyle {
    func makeView(
        placeholder: String,
        text: Binding<String>,
        environment: EnvironmentValues
    ) -> some View {
        HStack(spacing: 4) {
            Text("\u{25B8}")
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
        }
    }
}

extension TextFieldStyle where Self == CaretTextFieldStyle {
    static var caret: Self { Self() }
}

struct P36RootView: View {
    @State var pickerSelection: String? = "Vanilla"
    /// #124's non-optional selection. NOT `String?`, and that is the assertion:
    /// this only compiles if `init(of:selection: Binding<Value>)` exists, so the
    /// build itself is half the test and the printed line is the other half.
    /// #124 的非 optional selection。型別**不是** `String?`,而那正是斷言:只有在
    /// `init(of:selection: Binding<Value>)` 存在時它才編譯得過,因此**建置本身就是一半的測試**,
    /// 而印出來的那一行是另一半。
    @State var labelledSelection: String = "Vanilla"
    @State var text = "SwiftCrossUI TextField"
    /// Shared on purpose across the five styled fields below: one binding makes
    /// it visible at a glance that all five are live and none is a picture.
    /// 下方五個帶樣式的欄位刻意共用一個 binding：單一 binding 讓「五者皆為實際可用的欄位、沒有一個
    /// 是圖片」這件事一眼可見。
    @State var styledText = ""

    let choices = ["Vanilla", "Chocolate", "Strawberry"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("P36: API-shape compatibility")
                .font(.system(size: 20))
            Text("backend -> \(String(describing: DefaultBackend.self))")

            Text("SwiftCrossUI form that compiles")
                .font(.system(size: 15))
            // NESTED Group, and it is load-bearing. This VStack was at 18
            // children and `ViewBuilder.buildBlock` stops at 19, so the two
            // #124 views below would put it at 20 -- which is not reported where
            // it happens. Measured on P21 the same day: three extra views there
            // produced `error: extra argument in call` at the first child PAST
            // the limit, sixty lines away, naming neither the addition nor the
            // arity. Folding these four into one child leaves 17.
            //
            // 這個**巢狀 Group 是承重的**。本 VStack 原有 18 個子項,而 `ViewBuilder.buildBlock`
            // 止於 19,因此下方兩個 #124 的 view 會讓它變成 20——而那**不會**在發生的地方被回報。
            // 同一天在 P21 上實測:在該處多加三個 view,產生的是**超過上限後第一個子項**處的
            // `error: extra argument in call`,距離六十行之遙,既沒指名新增的東西,也沒提到 arity。
            // 把這四個收進一個子項,便只剩 17。
            Group {
                Picker(of: choices, selection: $pickerSelection)
                Text("Picker selection: \(pickerSelection ?? "nil")")

                // #124, added 2026-09-10. The two initialiser shapes that were
                // missing, exercised together because they are used together.
                //
                // NON-OPTIONAL selection, which is SwiftUI's shape. The one
                // above keeps the optional binding, so this app now shows both
                // and the pair is each other's control: if the optional
                // initialiser had been broken by adding the non-optional one,
                // the line above stops tracking.
                //
                // A LABEL. `Picker` has a `body`, so this is an HStack around
                // what it already returned -- see `Picker.label` for why that is
                // a real claim here and was not for `Slider`.
                //
                // The assertion is the printed value: choosing in either picker
                // must move only its own line.
                //
                // #124,2026-09-10 加入。先前缺少的兩種建構式形狀;放在一起執行,因為它們本來就
                // 會被一起使用。
                //
                // **非 optional 的 selection**,那是 SwiftUI 的形狀。上方那個保留 optional binding,
                // 因此本 app 現在同時展示兩者,而兩者互為對照:若加入非 optional 版時弄壞了 optional
                // 版,上面那一行就會停止跟隨。
                //
                // **一個標籤。** `Picker` 有 `body`,因此這只是在它原本回傳的東西外套一個 HStack
                // ——為何此處這是一項有依據的主張、而在 `Slider` 上不是,見 `Picker.label`。
                //
                // 斷言是那個被印出來的數值:在任一 picker 中選取,都只能移動它自己那一行。
                Picker("Labelled", of: choices, selection: $labelledSelection)
                Text("Labelled selection: \(labelledSelection)")
            }
            Button("String label button") {
                P36Diagnostics.write("button clicked")
            }
            TextField("Prompt text", text: $text)

            // textFieldStyle, added 2026-09-08 with TextFieldStyle itself.
            // Placed below the button rather than above it because
            // actions/win/P36-string-label-button.csv clicks that button by
            // coordinate; anything inserted higher up would move it and the
            // action would click a text field instead.
            //
            // Laid out as one row rather than one field per line so the four
            // borders sit side by side, which is what makes the difference
            // between them legible in a screenshot -- stacked vertically, a
            // plain field just looks like a gap.
            //
            // textFieldStyle，與 TextFieldStyle 本身同於 2026-09-08 加入。
            //
            // 放在按鈕**下方**而非上方，因為 actions/win/P36-string-label-button.csv 是以座標點擊
            // 該按鈕；任何插在更上方的東西都會把它推移，該 action 就會改而點到某個文字輸入框。
            //
            // 排成一列而非一行一個，好讓四個邊框並排；這正是讓它們之間的差異在截圖中可辨識的關鍵
            // ——若垂直堆疊，plain 欄位看起來就只是一段空白。
            Text("textFieldStyle: automatic / plain / roundedBorder / squareBorder / custom")
                .font(.system(size: 13))
            HStack(spacing: 8) {
                TextField("automatic", text: $styledText)
                    .textFieldStyle(.automatic)
                TextField("plain", text: $styledText)
                    .textFieldStyle(.plain)
                TextField("rounded", text: $styledText)
                    .textFieldStyle(.roundedBorder)
                TextField("square", text: $styledText)
                    .textFieldStyle(.squareBorder)
                TextField("caret", text: $styledText)
                    .textFieldStyle(.caret)
            }

            HStack(spacing: 8) {
                Text("Int spacing 8")
                Text("next")
            }
            .padding(8)

            Divider()
            Text("SwiftUI-shaped call sites missing here")
                .font(.system(size: 15))
            // NARROWED 2026-09-10, and this line is the reason to look at the
            // capture rather than only at the build. It read
            // "Picker label/content/tag; non-optional Picker selection; ..."
            // while the two pickers directly above it were, in the same picture,
            // demonstrating a label and a non-optional selection. A screen that
            // says a feature is absent while showing it is worse than one that
            // says nothing -- it is a wrong claim with a picture attached, and
            // this app's whole job is to be that picture. Same defect as #87 and
            // #115, which were both "P33/P34 claim APIs are missing that exist".
            //
            // What is left is the ViewBuilder content and `.tag()`, which are
            // one job and not the same job as the initialisers: they need a
            // `_asPickerOptions` walker mirroring `_asMenuItems`.
            //
            // **2026-09-10 縮減**,而這一行正是「要看擷圖、而不只看建置」的理由。它原本寫著
            // 「Picker label/content/tag; non-optional Picker selection; ...」,而**就在同一張圖裡**,
            // 它正上方的兩個 picker 正在展示一個標籤與一個非 optional 的 selection。
            // **一個一邊展示某功能、一邊聲稱該功能不存在的畫面,比什麼都不說更糟**——那是一項附了
            // 照片的錯誤主張,而這支 app 的全部工作就是當那張照片。這與 #87、#115 是同一個缺陷,
            // 那兩項都是「P33/P34 聲稱某些存在的 API 不存在」。
            //
            // 剩下的是 ViewBuilder content 與 `.tag()`,它們是**同一件工作**,但與那些建構式**不是**
            // 同一件:它們需要一個仿照 `_asMenuItems` 的 `_asPickerOptions` 走訪器。
            Text("Picker content/tag; Button label builder and ButtonRole")
            Text("LocalizedStringKey Text, Text + Text, Image(systemName:), bundle image lookup")
            Text("List without selection, Section, onDelete, swipeActions, TextField axis/prompt/value-format")
            Text("CGFloat geometry such as padding(8.5), cornerRadius(8.5), HStack(spacing: 8.5)")
                .font(.system(size: 13))
        }
        .padding(18)
        .onAppear {
            P36Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            P36Diagnostics.renderComplete()
        }
    }
}
