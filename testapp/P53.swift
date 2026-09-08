import DefaultBackend
import Foundation
import SwiftCrossUI

// P53 is the first picture of `ColorPicker` in which the control is ABOVE THE
// FOLD, and the first that writes a log line a `# expect:` marker can assert.
//
// THE BRIEF FOR THIS FILE WAS WRONG ABOUT ONE THING, AND THE WRONG PART IS
// WRITTEN DOWN HERE RATHER THAN QUIETLY FIXED. It said no test app draws
// `ColorPicker` at all. It does:
//
//     grep -l ColorPicker testapp/P*.swift    -> P33.swift, P48.swift
//
// P33's hit is prose (line 83 lists ColorPicker as "still missing"), but P48's
// is a real call -- `ColorPicker("Accent", selection: $chosen)`, added by
// e6165e8a, the same commit that added the view. So this is not the first USE.
// What it is the first of is a use that can be photographed and asserted, and
// the difference is the whole reason the file exists:
//
// (No line number for that call ON PURPOSE: it sat at P48:121 when this file
// was written and had moved to P48:157 an hour later, because P48 was being
// edited at the same time. Find it with
// `grep -n 'ColorPicker(' testapp/P48.swift`, which cannot go stale.)
//
//   - P48 puts the ColorPicker last, as section 4 of a 820x720 window whose
//     first three sections are grids. P51's action file records what that costs
//     for the section below the fold in ITS app, "having watched it happen to
//     P48 first". A control drawn under the window's bottom edge is a control
//     nobody has seen.
//   - P48Diagnostics.write is `print` only -- no file, unlike every other app in
//     this suite -- so P48 leaves nothing on disk to assert against, and there
//     is no `testapp/actions/win/P48-*.csv`.
//
// So the evidence that `ColorPicker` DRAWS on Windows is, before this file,
// exactly the evidence P51's header complains about for its own six views: it
// compiled, and it broke nothing.
//
// P53 是 `ColorPicker` 第一次被畫在**折線之上**的圖，也是第一次寫出「`# expect:` 標記能夠斷言的
// log 行」的一支。
//
// **本檔的任務說明有一處是錯的，而錯的部分寫在這裡，不是被悄悄修掉。** 它說沒有任何測試 app 會畫
// `ColorPicker`。實際上有：
//
//     grep -l ColorPicker testapp/P*.swift    -> P33.swift、P48.swift
//
// P33 的命中是散文（第 83 行把 ColorPicker 列為「仍然缺席」），但 P48 的是真正的呼叫——
// `ColorPicker("Accent", selection: $chosen)`，由 e6165e8a 加入，正是加入該 view 的同一個 commit。
// 因此這並不是第一次**使用**。它是第一次「能被拍照、也能被斷言」的使用，而這個差別正是本檔存在的
// 全部理由：
//
// （**刻意不寫該呼叫的行號**：本檔寫成時它在 P48:121，一小時後已移到 P48:157，因為 P48 當時正被
// 同時編輯。請用 `grep -n 'ColorPicker(' testapp/P48.swift` 找它，那是不會過期的。）
//
//   - P48 把 ColorPicker 放在最後，作為一個 820x720 視窗的第 4 節，而前三節都是格線。P51 的動作檔
//     記錄了「某一節落在折線之下」在**它自己**的 app 中的代價，並註明那是「先在 P48 身上看過」。
//     被畫在視窗底緣之下的控制項，就是沒有人看過的控制項。
//   - P48Diagnostics.write 只有 `print`——不寫檔，與本套件中其他每一支 app 都不同——因此 P48 在
//     磁碟上不留任何可供斷言之物，也因此沒有 `testapp/actions/win/P48-*.csv`。
//
// 所以在本檔之前，「`ColorPicker` 在 Windows 上會畫出東西」的證據，恰好就是 P51 檔頭所抱怨的那種
// 證據：它編譯過了，而且沒有弄壞東西。
//
// ---------------------------------------------------------------------------
// WHAT IS ON SCREEN, AND WHAT IS DELIBERATELY NOT
// 畫面上有什麼，以及什麼是刻意不在畫面上的
// ---------------------------------------------------------------------------
//
// NOTHING IS BELOW THE FOLD, and the height was ARITHMETIC, not a feeling. The
// first draft of this file claimed "roughly 470 points" for a layout that added
// up to about 666, which is 46 points OVER the 620 window it also claimed would
// hold it -- i.e. the draft shipped P48's exact defect while its header boasted
// of avoiding it. Every string on screen costs about 15 points at size 11 and
// every VStack gap costs its spacing, so a bilingual caption pair is 30 points
// and eight of them are a quarter of the window. The count, by section:
//
//     title 26 + backend 22 + 2 captions 30                        =  78
//     section 1: heading 20 + 4 captions 60 + row 34 + 2 captions 30
//                + 8 gaps at 6                                     = 192
//     section 2: heading 20 + buttons 34 + readout 22 + 2 captions 30
//                + 5 gaps at 6                                     = 136
//     root: 5 gaps at 12 + padding 16 top and bottom               =  92
//                                                            total ~ 498
//
// The window is 760x660, so about 160 points of slack absorbs the error in
// those per-line estimates. What made it fit was cutting each bilingual caption
// pair from four lines to two; the long form of every one of them is in this
// header, where it costs nothing.
//
// The Windows frame adds chrome, and the amount is re-derivable rather than
// guessed: P46 records `defaultSize(860, 700)` capturing as an 888x729 frame
// and P51 records `defaultSize(920, 860)` capturing as 948x889 -- +28 wide and
// +29 tall in both, so this window's frame should be about 788x689. A
// ScrollView is present for phone-sized windows, exactly as in P51, and is not
// a substitute for the size.
//
// THE THREE CHANNEL SLIDERS ARE BEHIND A CLICK, AND THAT CANNOT BE CHANGED FROM
// HERE. `ColorPicker.isEditing` is `@State private var isEditing = false`
// (ColorPicker.swift:44) with no initialiser parameter and no binding, so an
// expanded picker is unreachable from outside the type. A freshly launched
// app's screenshot can therefore NEVER contain the sliders. This is not the
// below-the-fold failure wearing a different hat -- scrolling will not reveal
// them, and neither will a taller window -- so the caption on screen states it
// as the expected initial picture rather than leaving a reader to wonder where
// the three sliders in `ColorPicker.swift:70-72` went.
//
// **折線之下沒有任何東西，而這個高度是算出來的，不是感覺出來的。** 本檔的初稿為一份實際加總約 666
// 點的版面宣稱「約 470 點」，比它同時宣稱裝得下的 620 點視窗超出 46 點——也就是說，那份初稿一邊在
// 檔頭自誇避開了 P48 的缺陷，一邊原封不動地犯了它。畫面上每個 size 11 的字串約佔 15 點，每個
// VStack 間隙佔它的 spacing，因此一組雙語說明就是 30 點，八組就是四分之一個視窗。逐節計數見上，
// 合計約 498 點。
//
// 視窗為 760x660，因此約 160 點的餘裕可以吸收上述每行估計值的誤差。讓它裝得下的做法，是把每一組
// 雙語說明從四行砍成兩行；它們每一句的長篇版本都在本檔頭裡，而那裡不用付版面的錢。
//
// Windows 的視窗會加上外框，而其數值是可重新推導的、不是猜的：P46 記錄 `defaultSize(860, 700)`
// 擷到 888x729 的 frame，P51 記錄 `defaultSize(920, 860)` 擷到 948x889——兩者都是寬 +28、高 +29，
// 因此本視窗的 frame 應約為 788x689。ScrollView 是為手機尺寸的視窗而在，與 P51 完全相同，且不能
// 替代尺寸本身。
//
// **三個通道 slider 藏在一次點擊之後，而這一點無法從本檔改變。**
// `ColorPicker.isEditing` 是 `@State private var isEditing = false`（ColorPicker.swift:44），
// 既無初始化參數也無 binding，因此「展開狀態」在該型別之外是抵達不了的。剛啟動的 app，其截圖因此
// **永遠不可能**含有那些 slider。這不是「折線之下」那個失敗換了張臉——捲動不會讓它們出現，把視窗加高
// 也不會——所以畫面上的說明文字把它陳述為預期的初始畫面，而不是留給讀者去納悶
// `ColorPicker.swift:70-72` 的那三個 slider 到哪去了。
//
// ---------------------------------------------------------------------------
// HOW A READER TELLS A PASS FROM A FAILURE
// 讀者如何區分通過與失敗
// ---------------------------------------------------------------------------
//
// The starting colour is PURE MAGENTA, `Color(red: 1, green: 0, blue: 1)`, and
// it is chosen to be a colour no default can be mistaken for. A colour well
// that fails to fill draws the window background; one that falls back to an
// uninitialised value draws black, white or grey; one that resolves the wrong
// channel draws red or blue. Magenta is none of those, and it is not a system
// accent on either Windows backend. P48 seeded `(0.85, 0.45, 0.20)` for the
// same reason -- "none of the primaries" -- but an orange-brown is close enough
// to a titlebar tint to argue about, and magenta is not.
//
// PASS, at launch:
//   1. A row reading `Accent` then a MAGENTA rectangle then an `Edit` button.
//   2. Immediately right of it, a second MAGENTA rectangle captioned
//      `reference`. The two must be the SAME colour and the SAME size.
//   3. `app sees  R 1.00   G 0.00   B 1.00` under them.
//
// FAILURE MODES, each a different picture:
//   - BOTH rectangles missing or window-coloured -> the failure is in
//     `Color`-as-a-view or `BackendFeatures.Colors`, NOT in ColorPicker. The
//     reference swatch is a plain `Color(...).frame().cornerRadius()`, the same
//     four calls `ColorPickerSwatch` makes (ColorPicker.swift:134-142), so if
//     the hand-written one is also blank the fault is underneath both.
//   - PICKER's rectangle missing, reference present -> the fault IS in
//     `ColorPickerSwatch`. This is the split the two-swatch layout exists for;
//     one swatch alone cannot make it.
//   - Either rectangle drawn in the WRONG colour -> read the numbers beneath.
//     A swatch that disagrees with `app sees` means the well and the binding
//     disagree; a swatch that AGREES with a wrong `app sees` means the binding
//     itself is wrong. An empty box and a wrong-coloured box are both failures,
//     and neither can be read as success, because the caption names the colour.
//   - `Edit` button missing -> the `HStack` in `ColorPicker.body` lost a child.
//   - Rectangles present but the `app sees` line absent -> the regression
//     b0e9f852 fixed has returned; see the note on ``P53Readout``.
//
// SHOWING THE SELECTION CHANGE, not only the initial value. The four preset
// buttons write `chosen` directly, and the reference swatch does NOT follow
// them. So one press of `R 1.00` must turn the picker's swatch red while the
// reference stays magenta -- which proves the well is live rather than a static
// decoration, a thing the launch screenshot alone cannot say. The numbers under
// it change with it, and they are printed to two decimals ON PURPOSE: that is
// the same `%.2f` `ColorPickerChannel` prints beside each slider
// (ColorPicker.swift:159), so once `Edit` is pressed the two readings must
// match digit for digit.
//
// 起始顏色是**純洋紅** `Color(red: 1, green: 0, blue: 1)`，選它是因為沒有任何預設值會被誤認成它。
// 一個填不出顏色的色塊會畫成視窗背景；退回未初始化值的會畫成黑、白或灰；解析錯通道的會畫成紅或藍。
// 洋紅都不是這些，也不是兩個 Windows backend 任何一者的系統強調色。P48 以相同的理由選了
// `(0.85, 0.45, 0.20)`——「不是任何一個原色」——但橘褐色與標題列的色調近到可以爭論，洋紅則不會。
//
// 啟動時的**通過**畫面：
//   1. 一列讀作 `Accent`，接著一個**洋紅**矩形，接著一個 `Edit` 按鈕。
//   2. 緊鄰其右，第二個標註為 `reference` 的**洋紅**矩形。兩者的顏色與尺寸都必須**相同**。
//   3. 其下一行 `app sees  R 1.00   G 0.00   B 1.00`。
//
// 各種失敗形式，每一種都是不同的圖：
//   - **兩個**矩形都不見或都是視窗底色 -> 失敗在「`Color` 作為 view」或 `BackendFeatures.Colors`，
//     **不在** ColorPicker。參考色塊是單純的 `Color(...).frame().cornerRadius()`，與
//     `ColorPickerSwatch`（ColorPicker.swift:134-142）所做的是同樣四個呼叫；若手寫的那個也是空白，
//     問題就在兩者底下。
//   - 選擇器的矩形不見、參考色塊在 -> 失敗**就在** `ColorPickerSwatch`。兩個色塊的版面正是為了做出
//     這個切分而存在；單一個色塊做不到。
//   - 任一矩形畫成**錯的顏色** -> 請讀下方的數字。色塊與 `app sees` 不一致，代表色塊與 binding
//     不一致；色塊與一個**錯的** `app sees` 一致，則代表 binding 本身就錯了。空盒子與顏色錯的盒子
//     都是失敗，兩者都不能被讀成成功，因為說明文字已經指名了顏色。
//   - `Edit` 按鈕不見 -> `ColorPicker.body` 中的 `HStack` 掉了一個子節點。
//   - 矩形都在，但 `app sees` 那一行不見 -> b0e9f852 所修正的那個回歸又回來了；見 ``P53Readout``。
//
// **呈現選取值的改變**，而不只是初始值。四個預設按鈕直接寫入 `chosen`，而參考色塊**不會**跟著改變。
// 因此按一次 `R 1.00`，選擇器的色塊必須變紅、參考色塊必須維持洋紅——這證明了那個色塊是活的，而不是
// 一片靜態裝飾，而這是單憑啟動截圖說不出來的事。其下的數字也隨之改變，且**刻意**印到小數兩位：那與
// `ColorPickerChannel` 印在每個 slider 旁邊的 `%.2f`（ColorPicker.swift:159）是同一個格式，因此
// 一旦按下 `Edit`，兩處讀數必須逐位相符。
//
// ---------------------------------------------------------------------------
// NO ACTION FILE SHIPS WITH THIS APP, AND THAT IS THE HONEST ANSWER, NOT A GAP
// 本 app 不隨附動作檔，而那是誠實的答案，不是一個缺口
// ---------------------------------------------------------------------------
//
// Every one of the 44 files in `testapp/actions/win` states where its
// coordinates were measured -- a named capture, its pixel size, the display
// scale, `origin=frame`. None of them admits to an unmeasured coordinate:
//
//     grep -ln 'UNMEASURED\|estimated\|provisional' testapp/actions/win/*.csv
//         -> no output
//
// This app has never been built or launched, so a file written now could only
// carry arithmetic dressed as a measurement, and a replay whose click lands on
// empty space fails in the shape of the app being broken. Writing the first
// unmeasured file into that directory would cost more than the file is worth.
//
// THE RECIPE, for whoever takes the first capture. Two files are worth having,
// and the log lines they assert already exist:
//
//   P53-preset-red.csv     click "R 1.00"; the picker's swatch must turn red
//                          while the reference stays magenta.
//                          `# expect: log-contains colour now r=1.00 g=0.00 b=0.00`
//                          `preset red` is written BEFORE the assignment and
//                          `colour now ...` after it, so if only the first
//                          appears the click arrived and the binding did not
//                          propagate -- which is a finding, not a miss.
//
//   P53-edit-then-slider.csv  click "Edit" to reveal the three channel sliders,
//                          then click partway along the G track. GTK4's
//                          `gtk-primary-button-warps-slider` defaults TRUE, so a
//                          click jumps the value; WinUI may need
//                          mouseDown/move/mouseUp instead -- there is no `drag`
//                          verb, InputAction.swift has only move, click,
//                          doubleClick, mouseDown, mouseUp, key*, scroll, sleep.
//                          Assert on `colour now `, and read the exact value off
//                          the capture rather than predicting it.
//
// Build it with the flag or the replay is compiled out and the failure is
// silent, exactly as P0's file records:
//     SCUI_DEBUG=1 zsh testapp/compile.zsh -gtk4 P53
//
// `testapp/actions/win` 中的 44 個檔案，每一個都載明其座標的量測出處——具名的擷圖、像素尺寸、
// 顯示縮放、`origin=frame`。沒有任何一個承認自己用的是未經量測的座標（grep 見上，無輸出）。
//
// 本 app 從未被建置或啟動過，因此現在寫出來的檔案只可能帶著「打扮成量測結果的算術」，而一次點擊
// 落在空白處的重放，其失敗形狀與「app 壞掉了」一模一樣。把該目錄中第一個未經量測的檔案寫進去，
// 代價高於這個檔案的價值。
//
// 上方是給「拍到第一張擷圖的人」的作法：兩個檔案值得做，而它們要斷言的 log 行都已經存在。
//
// ---------------------------------------------------------------------------
// WHAT `ColorPicker` NEEDS FROM A BACKEND: nothing that Gtk or WinUI lacks
// `ColorPicker` 對 backend 的需求：沒有一項是 Gtk 或 WinUI 缺少的
// ---------------------------------------------------------------------------
//
// There is no `BackendFeatures.ColorPickers` protocol and this view does not
// need one. It is composed from `HStack`, `Text`, `Button`, `Slider` and a
// filled rectangle, and its own header says so. Tracing what that reaches:
//
//   - `Slider` and `Button` are in `BackendFeatures.Controls`, which is part of
//     `BaseAppBackend` (BaseAppBackend.swift:15-19). Every shipped backend
//     conforms by definition; there is nothing optional to check.
//   - the swatch's fill goes through `@CastBackend<BackendFeatures.Colors>`
//     (Color.swift:70, :86) and its rounding through
//     `@CastBackend<BackendFeatures.CornerRadius>`
//     (CornerRadiusModifier.swift:23, :54). Those two ARE optional, and a
//     `@CastBackend` on a non-conforming backend expands to `fatalError` --
//     the process dies at first render rather than degrading, which is what
//     happened to `.popover` on four backends on 2026-09-08.
//
// Both are declared on both Windows backends, so neither can fire here:
//
//     grep -n 'BackendFeatures.Colors\|BackendFeatures.CornerRadius' \
//         Sources/GtkBackend/GtkBackend.swift Sources/WinUIBackend/WinUIBackend.swift
//     GtkBackend.swift:33:    BackendFeatures.CornerRadius,
//     GtkBackend.swift:40:    BackendFeatures.Colors,
//     WinUIBackend.swift:114:    BackendFeatures.CornerRadius,
//     WinUIBackend.swift:120:    BackendFeatures.Colors,
//
// So a blank swatch on Windows is a rendering defect, not a missing
// conformance, and this app must not be read as reporting one.
//
// 並不存在 `BackendFeatures.ColorPickers` 這個 protocol，而本 view 也不需要。它由 `HStack`、`Text`、
// `Button`、`Slider` 與一個填色矩形組合而成，其自身的檔頭也是這麼說的。追一下它實際觸及了什麼：
//
//   - `Slider` 與 `Button` 位於 `BackendFeatures.Controls`，而它是 `BaseAppBackend` 的一部分
//     （BaseAppBackend.swift:15-19）。每個已發布的 backend 依定義都會符合；沒有選配項需要檢查。
//   - 色塊的填色走 `@CastBackend<BackendFeatures.Colors>`（Color.swift:70、:86），其圓角走
//     `@CastBackend<BackendFeatures.CornerRadius>`（CornerRadiusModifier.swift:23、:54）。這兩者
//     **是**選配的，而 `@CastBackend` 在不符合的 backend 上會展開為 `fatalError`——行程會在第一次
//     算繪時終止而非降級，2026-09-08 的 `.popover` 就是這樣一次弄倒四個 backend 的。
//
// 兩者在兩個 Windows backend 上都有宣告，因此此處誰都不會觸發（grep 見上）。
// 所以在 Windows 上看到空白色塊，那是算繪缺陷，不是缺少 conformance，本 app 不可被讀成在回報後者。

enum P53Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P53] \(message)")
        let data = Data("P53 \(Date()) \(message)\n".utf8)
        // SCUI_DEBUG_EVENTS_DIR when a launcher sets it, so every app's log lands
        // in one place; unset, the launch directory. Same contract as P51, which
        // documents it against testapp/test_support/test_common.zsh.
        // 有 SCUI_DEBUG_EVENTS_DIR 時取自該變數，讓每支 app 的 log 集中一處；未設定時為啟動目錄。
        // 與 P51 相同的約定，該檔記載其出處為 testapp/test_support/test_common.zsh。
        let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
            ?? FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p53-debug-events.log")
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
        write("render complete -- colorpicker drawn collapsed")
    }
}

@main
@HotReloadable
struct P53ColorPickerApp: App {
    var body: some Scene {
        WindowGroup("P53 colour picker") {
            #hotReloadable {
                P53RootView()
            }
        }
        // See the header for the per-section count: ~498 points of content in
        // one column, ~160 points of slack. Do not shrink it to make a capture
        // tidier; the whole complaint against P48's ColorPicker is that it was
        // drawn where nobody could see it. If a caption is added, add the points
        // to the header's sum in the same edit -- the first draft of this file
        // is what happens when that is skipped.
        // 逐節計數見檔頭：單欄約 498 點的內容，約 160 點餘裕。請勿為了讓擷圖好看而縮小它；對 P48 的
        // ColorPicker 的整個指控，就是它被畫在沒有人看得到的地方。若新增一行說明文字，請在同一次
        // 編輯中把點數加進檔頭的總和——本檔的初稿就是跳過這一步的下場。
        .defaultSize(width: 760, height: 660)
    }
}

struct P53RootView: View {
    /// Pure magenta. See the header for why this specific colour and not a
    /// default: no failure mode of a colour well produces magenta by accident.
    /// 純洋紅。為何是這個顏色而不是某個預設值，見檔頭：色塊的任何一種失敗形式，都不會意外產生洋紅。
    @State var chosen = Color(red: 1.0, green: 0.0, blue: 1.0)

    /// The colour the reference swatch is fixed at, and the colour ``chosen``
    /// starts at. One constant, so "the two swatches must match at launch" is
    /// true by construction and a mismatch is therefore a real finding rather
    /// than two literals that drifted apart in an edit.
    /// 參考色塊固定顯示的顏色，也是 ``chosen`` 的起始值。只有一個常數，因此「啟動時兩個色塊必須相同」
    /// 是由構造保證的，於是不相同就是一項真正的發現，而不是兩個字面值在某次編輯中走散了。
    static let magenta = Color(red: 1.0, green: 0.0, blue: 1.0)

    /// Needed because ``P53Components/line(for:in:)`` cannot resolve a colour
    /// without one, and `EnvironmentValues` has no public initialiser to fake
    /// one with -- its only accessible init is
    /// `@_spi(Backends) public init<Backend: BaseAppBackend>(backend:)`
    /// (EnvironmentValues.swift:236). So the environment has to come from a
    /// view, and the log-writing closures below capture it from here.
    /// 之所以需要它，是因為 ``P53Components/line(for:in:)`` 沒有它就無法解析一個顏色，而
    /// `EnvironmentValues` 沒有可用來偽造一個的公開初始化器——它唯一可觸及的 init 是
    /// `@_spi(Backends) public init<Backend: BaseAppBackend>(backend:)`
    /// （EnvironmentValues.swift:236）。因此 environment 必須來自一個 view，而下方負責寫 log 的
    /// closure 就是從這裡捕獲它的。
    @Environment(\.self) var environment

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("P53: ColorPicker")
                    .font(.system(size: 19))
                Text("backend -> \(String(describing: DefaultBackend.self))")
                // Two lines, not four. Every string on this screen costs about
                // 15 points and the fold is the one failure this app exists to
                // avoid, so the long form of this stays in the header comment
                // where it is free. Cutting the English/中文 pair to one line
                // each is what brought the content back under the window.
                // 兩行，不是四行。本畫面上每一個字串約佔 15 點，而「折線」正是本 app 存在所要避免的
                // 那一種失敗，因此長篇版本留在檔頭註解中——那裡不用付版面的錢。把英文／中文各砍成
                // 一行，正是把內容拉回視窗之內的做法。
                Text("First capture of ColorPicker above the fold. P48 calls it below its window edge.")
                    .font(.system(size: 11))
                Text("ColorPicker 首次被畫在折線之上。P48 的呼叫落在它自己的視窗邊緣之下。")
                    .font(.system(size: 11))

                P53PickerSection(chosen: $chosen)
                P53PresetSection(chosen: $chosen)
            }
            .padding(16)
        }
        // Fires for a preset button AND for a drag on one of the picker's own
        // channel sliders, which is the only way a slider drag becomes
        // assertable: `ColorPicker` calls nothing of ours when its sliders move,
        // it only writes the binding. Watching the binding is watching the
        // sliders.
        // 預設按鈕會觸發它，選擇器自身通道 slider 的拖曳也會——而那是「slider 拖曳成為可斷言之事」的
        // 唯一途徑：`ColorPicker` 的 slider 移動時不會呼叫我們的任何東西，它只會寫入 binding。
        // 盯著 binding，就是盯著那些 slider。
        .onChange(of: chosen) {
            P53Diagnostics.write("colour now \(P53Components.line(for: chosen, in: environment))")
        }
        .onAppear {
            P53Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            P53Diagnostics.write("start colour \(P53Components.line(for: chosen, in: environment))")
            P53Diagnostics.renderComplete()
        }
    }
}

/// The control itself, and a hand-written swatch beside it holding the starting
/// colour.
///
/// The two rectangles are the point of this section. They are built the same way
/// -- `ColorPickerSwatch` is `color.frame(width: 28, height: 18).cornerRadius(4)`
/// (ColorPicker.swift:134-142) and the reference below is those same four calls
/// -- so if the picker's is blank and this one is not, the fault is in
/// `ColorPickerSwatch`; if both are blank it is underneath both, in
/// `Color`-as-a-view. A single swatch cannot distinguish those, which is why
/// there are two.
///
/// 控制項本身，以及緊鄰其旁、持有起始顏色的一個手寫色塊。
///
/// 這兩個矩形正是本節的重點。它們以同樣的方式構成——`ColorPickerSwatch` 是
/// `color.frame(width: 28, height: 18).cornerRadius(4)`（ColorPicker.swift:134-142），而下方的
/// 參考色塊就是同樣那四個呼叫——因此若選擇器的是空白而這一個不是，問題就在 `ColorPickerSwatch`；
/// 若兩個都空白，問題就在兩者底下的「`Color` 作為 view」。單一個色塊分不出這兩者，這就是為何有兩個。
struct P53PickerSection: View {
    @Binding var chosen: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("1. ColorPicker -- expect: label, MAGENTA well, Edit button")
                .font(.system(size: 15))
            Text("At launch both swatches MUST be magenta, same colour and size. Press a preset")
                .font(.system(size: 11))
            Text("below: only the LEFT one may change. That is what proves the well is live.")
                .font(.system(size: 11))
            Text("啟動時兩個色塊都必須是洋紅，同色同尺寸。按下方任一預設鍵後，只有左邊那個可以改變")
                .font(.system(size: 11))
            Text("——那正是色塊為活的證明。")
                .font(.system(size: 11))

            HStack(spacing: 24) {
                // The subject. `ColorPicker(_:selection:)` -- the `Label == Text`
                // overload at ColorPicker.swift:114, which is SwiftUI's spelling
                // and the same call P48 makes.
                // 受測對象。`ColorPicker(_:selection:)`——位於 ColorPicker.swift:114 的
                // `Label == Text` 多載，即 SwiftUI 的寫法，也是 P48 所用的同一個呼叫。
                ColorPicker("Accent", selection: $chosen)

                HStack(spacing: 8) {
                    P53RootView.magenta
                        .frame(width: 28, height: 18)
                        .cornerRadius(4)
                    Text("reference, always magenta")
                        .font(.system(size: 11))
                }
            }

            Text("No R/G/B sliders yet is EXPECTED: isEditing is @State private, so press Edit.")
                .font(.system(size: 11))
            // No `**` markup in an on-screen string: `Text` renders literally
            // here, so asterisks meant as emphasis draw as asterisks. Emphasis
            // belongs in the comments, where it is Markdown that DocC reads.
            // 畫面上的字串不使用 `**` 標記：此處的 `Text` 是照字面繪製的，因此用來強調的星號會被畫成
            // 星號。強調屬於註解，那裡的 Markdown 才會被 DocC 讀取。
            Text("尚未出現 R/G/B slider 是預期的：isEditing 是 @State private，請按 Edit。")
                .font(.system(size: 11))
        }
    }
}

/// Four buttons that write the binding, and the readout that must follow them.
///
/// These exist because a launch screenshot shows a value, not a mechanism: a
/// swatch hard-coded to magenta and a swatch bound to a magenta state look
/// identical. Pressing `R 1.00` separates them in one frame.
///
/// They also give this app something a `# expect: log-contains` marker can
/// assert. Counted 2026-09-08: 20 of the 44 files in `testapp/actions/win`
/// carry one. Re-derive rather than repeat, because the number moves --
/// `testapp/plan/action-file-expectations.md` still says 19, which was true
/// when it was written and was already wrong the same day:
///
///     ls testapp/actions/win/*.csv | wc -l                      -> 44
///     grep -l '^# expect:' testapp/actions/win/*.csv | wc -l    -> 20
///
/// The reason the rest carry none is that their app writes nothing but startup
/// lines, which
/// prove a launch rather than a click. `colour now r=1.00 g=0.00 b=0.00`
/// appears in no other circumstance.
///
/// 四個會寫入 binding 的按鈕，以及必須跟著它們變動的讀數。
///
/// 它們之所以存在，是因為啟動截圖顯示的是一個值，不是一套機制：一個寫死為洋紅的色塊，與一個綁定到
/// 洋紅狀態的色塊，看起來完全相同。按一下 `R 1.00`，一個畫面就把兩者分開了。
///
/// 它們同時也給了這支 app 一件 `# expect: log-contains` 標記能斷言的事。`testapp/actions/win` 的
/// 44 個檔案中有 20 個帶有該標記（2026-09-08 實計）。請**重新推導而非照抄**，因為這個數字會變動——
/// `testapp/plan/action-file-expectations.md` 至今仍寫 19，那在它被寫下時為真，而在同一天就已經
/// 是錯的（重新推導的指令見上）。其餘沒有標記的理由是它們的 app 除了啟動訊息之外什麼都不寫，而
/// 啟動訊息證明的是啟動，不是點擊。
/// `colour now r=1.00 g=0.00 b=0.00` 在任何其他情況下都不會出現。
struct P53PresetSection: View {
    @Binding var chosen: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("2. Presets -- each writes the binding and logs one line")
                .font(.system(size: 15))

            HStack(spacing: 8) {
                Button("R 1.00") {
                    P53Diagnostics.write("preset red")
                    chosen = Color(red: 1.0, green: 0.0, blue: 0.0)
                }
                Button("G 1.00") {
                    P53Diagnostics.write("preset green")
                    chosen = Color(red: 0.0, green: 1.0, blue: 0.0)
                }
                Button("B 1.00") {
                    P53Diagnostics.write("preset blue")
                    chosen = Color(red: 0.0, green: 0.0, blue: 1.0)
                }
                Button("reset magenta") {
                    P53Diagnostics.write("preset magenta")
                    chosen = P53RootView.magenta
                }
            }

            P53Readout(color: chosen)

            Text("Two decimals, like the %.2f beside each slider: after Edit the two must match.")
                .font(.system(size: 11))
            Text("小數兩位，與每個 slider 旁的 %.2f 相同：按下 Edit 後，兩處讀數必須相符。")
                .font(.system(size: 11))
        }
    }
}

/// Formats a `Color`'s components identically for the screen and for the log.
///
/// One formatter, used by both, so `# expect: log-contains colour now r=1.00
/// g=0.00 b=0.00` and the line a reader sees in the capture cannot disagree
/// about rounding. Two copies of a format string is how a marker starts
/// matching nothing after somebody changes a `%.2f` to a `%.3f`.
///
/// `Float` is converted to `Double` explicitly rather than left to `CVarArg`.
/// Swift promotes it either way; writing it out means the call does not depend
/// on remembering that.
///
/// 以完全相同的方式格式化一個 `Color` 的分量，供畫面與 log 共用。
///
/// 只有一個格式化器、兩處共用，因此 `# expect: log-contains colour now r=1.00 g=0.00 b=0.00`
/// 與讀者在擷圖中看到的那一行，不可能在進位上產生分歧。同一個格式字串存兩份，正是「某人把 `%.2f`
/// 改成 `%.3f` 之後，標記從此什麼都比對不到」的起點。
///
/// `Float` 明確轉成 `Double`，而非交給 `CVarArg` 處理。Swift 兩種寫法都會提升，寫出來只是讓這個
/// 呼叫不必依賴「記得這件事」。
enum P53Components {
    static func line(for color: Color, in environment: EnvironmentValues) -> String {
        // Resolved through the environment, exactly as `ColorPicker.channel`
        // does (ColorPicker.swift:96) -- a `.system` or `.adaptive` colour has
        // no red until an environment says which one applies. Every colour THIS
        // app can hold is a plain `.rgb` (the four presets, and the `.rgb` that
        // the channel setter writes at ColorPicker.swift:100-105) and `.rgb`
        // resolves to itself, so the environment cannot change these numbers
        // here. It is threaded through anyway rather than faked, because
        // `EnvironmentValues` has no public initialiser to fake one with.
        //
        // 透過 environment 解析，與 `ColorPicker.channel` 的做法完全相同（ColorPicker.swift:96）
        // ——一個 `.system` 或 `.adaptive` 顏色，在有 environment 說明何者適用之前並沒有「紅色」
        // 這個值。**本** app 可能持有的每一個顏色都是單純的 `.rgb`（四個預設值，以及通道 setter
        // 在 ColorPicker.swift:100-105 所寫入的 `.rgb`），而 `.rgb` 解析成它自己，因此在此
        // environment 不可能改變這些數字。仍然把它一路傳進來而不偽造，是因為 `EnvironmentValues`
        // 根本沒有可用來偽造一個的公開初始化器。
        let resolved = color.resolve(in: environment)
        return String(
            format: "r=%.2f g=%.2f b=%.2f",
            Double(resolved.red),
            Double(resolved.green),
            Double(resolved.blue)
        )
    }
}

/// The chosen colour's components, in text, beside the swatch.
///
/// This is the check that the binding reaches the APP and not only the control.
/// A `ColorPicker` that edited a copy would move its own sliders and leave this
/// line where it was, and from inside the control those two are the same
/// picture. P48 makes the same point in its own `ColorPickerReadout`.
///
/// **No explicit `return` in this body, and that is deliberate.** P48's readout
/// keeps one AS A REGRESSION TEST: until b0e9f852 an explicit `return` opted the
/// body out of `@ViewBuilder`, `Content` became `Text` rather than
/// `TupleView1<Text>`, and the view rendered nothing at all while compiling and
/// running cleanly. P48 is where that trap is watched. Repeating it here would
/// mean a returned framework bug takes out this app's readout as well, and then
/// P53 reports a `ColorPicker` fault that is not one. The `let` lives in
/// ``P53Components`` instead, so this body stays a plain builder expression.
///
/// 所選顏色的各分量，以文字呈現在色塊旁邊。
///
/// 這是「binding 抵達了 **app**，而不只是抵達了控制項」的檢查。一個「編輯的是副本」的 `ColorPicker`
/// 會移動它自己的 slider，卻讓這一行原封不動——而從控制項內部看，那兩者是同一幅畫面。P48 在它自己的
/// `ColorPickerReadout` 中提出的是同一個論點。
///
/// **本 body 中沒有顯式 `return`，而這是刻意的。** P48 的讀數**刻意保留**一個作為回歸測試：在
/// b0e9f852 之前，顯式 `return` 會讓 body 跳出 `@ViewBuilder`，`Content` 成為 `Text` 而非
/// `TupleView1<Text>`，於是該 view 完全不會被畫出來，卻編得過也跑得動。盯著那個陷阱的地方是 P48。
/// 在此重複它，會讓「該框架 bug 一旦回歸，本 app 的讀數也一併消失」，屆時 P53 會回報一個並不存在的
/// `ColorPicker` 缺陷。那個 `let` 改放在 ``P53Components`` 裡，好讓本 body 維持為單純的 builder
/// 運算式。
struct P53Readout: View {
    let color: Color

    @Environment(\.self) var environment

    var body: some View {
        Text("app sees  \(P53Components.line(for: color, in: environment))")
    }
}
