import DefaultBackend
import Foundation
import SwiftCrossUI

// P50 is the picture of the two view features that landed on 2026-09-08 and
// that nothing else in the P-suite draws: `.popover(isPresented:attachmentEdge:
// onDismiss:content:)` and `.navigationTitle(_:)`.
//
// Before this file, `grep -l 'navigationTitle\|\.popover(' testapp/P*.swift`
// returned NOTHING. Both features are therefore in the state P51's header
// describes: committed, compiling, and with no evidence that they put anything
// on a screen. `.onHover` took the process down on AndroidBackend on the same
// day and no P-app used it, so the suite could not have found it however many
// times it ran.
//
// HOW TO READ THE SCREENSHOT. Both features are settled by the picture alone,
// and neither is settled by the app agreeing with itself:
//
//   1. `.navigationTitle` writes the WINDOW TITLE -- there is no in-window bar
//      involved. So the capture must include the window FRAME, not just its
//      client area. Compare two things: the text in the title bar, and the
//      boxed line in the window that reads "TITLE BAR MUST READ". They must be
//      the same string. The scene's own title is
//      "P50 SCENE DEFAULT -- navigationTitle did NOT apply", so a failure spells
//      itself out in the title bar rather than needing to be deduced.
//   2. A popover is a floating panel. Success puts the words "PANEL ALPHA" or
//      "PANEL BETA" on the screen -- words that appear nowhere else in this app,
//      the buttons that open them deliberately say something different. A
//      backend that does not implement `BackendFeatures.Popovers` renders the
//      anchor UNMODIFIED (it warns once and returns; it does not abort), so the
//      failure picture is the window unchanged after a click. If the anchor
//      button had been labelled with the panel's own words, those two pictures
//      would be nearly the same one.
//
// The window is 780 x 700 and holds two sections, which is a reaction to P51 --
// its last section fell off the bottom and could not be captured. The content
// is SIZED to fit and has not yet been MEASURED fitting: at the time of writing
// no build of this file had run. The check is one line, so do it rather than
// believe this sentence: capture the window and confirm the last line of
// section 2, "關閉按鈕記下的是 'closed programmatically' ...", is visible. If it
// is not, raise `.defaultSize`'s height; nothing here should be behind a scroll.
//
// P50 是 2026-09-08 落地、而且 P-suite 中沒有別的東西會畫出來的那兩項 view 功能的圖：
// `.popover(isPresented:attachmentEdge:onDismiss:content:)` 與 `.navigationTitle(_:)`。
//
// 在本檔之前，`grep -l 'navigationTitle\|\.popover(' testapp/P*.swift` 什麼都沒回傳。因此這兩項
// 功能都處於 P51 檔頭所描述的狀態：已提交、能編譯，而且沒有任何證據顯示它們會在畫面上放出東西。
// `.onHover` 在同一天讓 AndroidBackend 上的行程終止，而沒有任何 P-app 用到它，所以這套測試無論
// 跑幾次都不可能找到它。
//
// 如何讀這張截圖。兩項功能都僅由圖片判定，而不是由 app 自己與自己一致來判定：
//
//   1. `.navigationTitle` 寫入的是**視窗標題**——過程中不存在任何視窗內的標題列。因此擷取範圍必須
//      包含視窗**外框**，而不只是內容區。請比對兩樣東西：標題列上的文字，以及視窗內那行標示著
//      「TITLE BAR MUST READ」的方框文字。兩者必須是同一個字串。scene 自身的標題是
//      「P50 SCENE DEFAULT -- navigationTitle did NOT apply」，因此失敗會在標題列上把自己說出來，
//      不需要推論。
//   2. popover 是一塊浮動面板。成功時會讓「PANEL ALPHA」或「PANEL BETA」出現在畫面上——這些字在
//      本 app 的其他任何地方都不會出現，開啟它們的按鈕刻意寫的是別的字。未實作
//      `BackendFeatures.Popovers` 的 backend 會**原樣**繪製錨點（它警告一次然後返回，不會中止），
//      因此失敗的畫面就是「點下去之後視窗毫無變化」。若錨點按鈕當初用了面板自己的字，這兩張圖
//      就會幾乎是同一張。
//
// 視窗為 780 x 700，內含兩個區塊，這是針對 P51 的反應——它最後一個區塊掉出視窗底部，無法被擷取。
// 內容是依「放得下」來**設定尺寸**的，但尚未被**量測**過確實放得下：撰寫本檔時，本檔尚未經過任何
// 一次建置。這項檢查只有一行，所以請去做，而不要相信這句話：擷取視窗，確認第 2 區塊的最後一行
// 「關閉按鈕記下的是 'closed programmatically' ……」是看得見的。若看不見，請調高 `.defaultSize`
// 的高度；此處不應有任何東西被藏在捲動之後。

enum P50Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P50] \(message)")
        let data = Data("P50 \(Date()) \(message)\n".utf8)
        // SCUI_DEBUG_EVENTS_DIR when a launcher sets it, so every app's log lands
        // in one place; unset, the launch directory exactly as before. The
        // contract is documented in testapp/test_support/test_common.zsh.
        // 有 SCUI_DEBUG_EVENTS_DIR 時取自該變數，讓每支 app 的 log 集中一處；未設定時仍為啟動
        // 目錄，行為與過去完全相同。該約定記載於 testapp/test_support/test_common.zsh。
        let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
            ?? FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p50-debug-events.log")
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
        write("render complete -- p50 ready for popover and title checks")
    }
}

@main
@HotReloadable
struct P50PopoverTitleApp: App {
    var body: some Scene {
        // The scene title is written as an ACCUSATION on purpose. `WindowGroup`'s
        // title is the fallback `WindowReference` uses when the content sets no
        // `navigationTitle` preference (`WindowReference.swift`, the single
        // application point: `preferences.navigationTitle ?? scene.title`). If
        // the preference never arrives, or arrives and is then overwritten, this
        // sentence is what the title bar says -- which is the whole failure
        // report, in the place the reader is already looking.
        //
        // scene 的標題刻意寫成一句**指控**。`WindowGroup` 的標題，是內容未設定 `navigationTitle`
        // preference 時 `WindowReference` 所採用的後備值（見 `WindowReference.swift` 中唯一的套用
        // 點：`preferences.navigationTitle ?? scene.title`）。若該 preference 從未送達、或送達後
        // 又被覆寫，標題列上寫的就是這句話——那就是完整的失敗報告，而且就在讀者本來就在看的位置。
        WindowGroup("P50 SCENE DEFAULT -- navigationTitle did NOT apply") {
            #hotReloadable {
                P50RootView()
            }
        }
        // Sized to hold everything at once. No ScrollView here, unlike P51: a
        // popover is anchored to a widget, and a scrolled anchor and its popover
        // are two things that can disagree about where they are. The content is
        // kept short instead.
        // 尺寸設定為一次容納全部內容。此處與 P51 不同，沒有 ScrollView：popover 錨定在某個 widget
        // 上，而一個被捲動的錨點與它的 popover，是兩個可能對「自己在哪裡」意見不合的東西。改為把
        // 內容維持得夠短。
        .defaultSize(width: 780, height: 700)
    }
}

struct P50RootView: View {
    /// The string handed to ``View/navigationTitle(_:)``, and the string the
    /// window's title bar must therefore show. Two values, not one, because a
    /// title that is only ever set once cannot distinguish "the preference was
    /// applied" from "the preference was applied once and then lost".
    /// 交給 ``View/navigationTitle(_:)`` 的字串，也因此是視窗標題列必須顯示的字串。之所以有兩個值
    /// 而不是一個，是因為一個只被設定過一次的標題，無法區分「該 preference 被套用了」與「該
    /// preference 被套用了一次、之後又弄丟了」。
    @State var windowTitle = P50Titles.a

    @State var isAlphaPresented = false
    @State var isBetaPresented = false

    /// Incremented by a button INSIDE a popover. See ``P50PopoverSection``.
    /// 由 popover **內部**的按鈕遞增。見 ``P50PopoverSection``。
    @State var panelCounter = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("P50: .popover(isPresented:attachmentEdge:onDismiss:) and .navigationTitle")
                .font(.system(size: 17))
            Text("backend -> \(String(describing: DefaultBackend.self))")
                .font(.system(size: 12))
            Text("Both landed 2026-09-08. No other P-app draws either, so this picture is the")
                .font(.system(size: 12))
            Text("whole of the evidence that they render. Capture the WINDOW FRAME, not just")
                .font(.system(size: 12))
            Text("the content -- half of this test is in the title bar.")
                .font(.system(size: 12))
            Text("兩者皆於 2026-09-08 落地。沒有別的 P-app 會畫出它們，因此這張圖就是它們能繪製的全部證據。")
                .font(.system(size: 12))
            Text("請擷取視窗**外框**而非僅內容區——本測試有一半在標題列上。")
                .font(.system(size: 12))

            P50TitleSection(windowTitle: $windowTitle)

            P50PopoverSection(
                isAlphaPresented: $isAlphaPresented,
                isBetaPresented: $isBetaPresented,
                panelCounter: $panelCounter
            )
        }
        .padding(16)
        .onAppear {
            P50Diagnostics.renderComplete()
        }
        // Outermost on purpose. A preference travels UP the view graph
        // (`PreferenceValues.swift`), so this has to sit above everything whose
        // preferences it must win against -- and `WindowReference` reads it from
        // the final content result of the whole window.
        // 刻意放在最外層。preference 是沿著 view graph **向上**傳遞的（見 `PreferenceValues.swift`），
        // 因此它必須位於所有「它必須勝過其 preference」的東西之上——而 `WindowReference` 是從整個
        // 視窗的最終內容結果中讀取它。
        .navigationTitle(windowTitle)
    }
}

/// The two titles, named once so the mirror label in the window and the value
/// given to the modifier cannot drift apart.
///
/// Both begin with `P50 TITLE`, which the scene's own title does not, so the
/// three strings a title bar can hold here are distinguishable at a glance and
/// at any capture scale.
///
/// 兩個標題，只命名一次，如此視窗內的對照標籤與交給 modifier 的值就不會彼此漂移。
///
/// 兩者都以 `P50 TITLE` 開頭，而 scene 自身的標題不是，因此此處標題列可能呈現的三個字串，在一眼
/// 之下、在任何擷取比例下都是可區分的。
enum P50Titles {
    static let a = "P50 TITLE A -- set by navigationTitle"
    static let b = "P50 TITLE B -- changed at runtime"
}

// MARK: - 1. navigationTitle

/// The window title, and a copy of it drawn inside the window to compare it
/// against.
///
/// **Why the copy exists.** `.navigationTitle` has no in-window rendering at
/// all -- `NavigationTitleModifier.swift` states that plainly, and states that
/// it does not retitle `NavigationStack`'s back bar either. The only place its
/// effect appears is the platform title bar, which a reader of a screenshot
/// cannot check against the source they do not have. The boxed line below is
/// that source, on screen, next to the thing it describes.
///
/// **Why there is a button that CHANGES it.** `WindowReference` used to set the
/// window title from the scene on every pass that carried a new scene, and from
/// the preference on every pass that did not, so a `.navigationTitle` would
/// appear and then be overwritten on the next resize. That was fixed on
/// 2026-09-08 by removing the scene's write and caching the last applied title
/// (`lastAppliedWindowTitle`). An initial value proves nothing about that bug:
/// it is the SECOND title, set after the window already exists, that exercises
/// the path the fix was for. Press "Show title B", then resize the window, and
/// the bar must still read title B.
///
/// 視窗標題，以及一份畫在視窗內、供人與之比對的副本。
///
/// **副本為何存在。** `.navigationTitle` 完全沒有視窗內的繪製——`NavigationTitleModifier.swift`
/// 把這點說得很白，並且也說明它不會替 `NavigationStack` 的返回列改標題。它的效果唯一會出現的地方
/// 是平台的標題列，而看截圖的人無法拿他手上沒有的原始碼去比對。下方那行方框文字就是那份原始碼，
/// 畫在畫面上，就在它所描述的東西旁邊。
///
/// **為何要有一個會**改變**它的按鈕。** `WindowReference` 過去在任何帶有新 scene 的計算中由 scene
/// 寫入視窗標題，在其餘每一次計算中則由 preference 寫入，因此 `.navigationTitle` 會先出現、再於
/// 下一次縮放時被覆蓋。此問題已於 2026-09-08 修正：移除 scene 的寫入，並快取最後一次套用的標題
/// （`lastAppliedWindowTitle`）。初始值對那個 bug 什麼都證明不了：真正演練該修正所針對之路徑的，
/// 是**第二個**標題——在視窗已經存在之後才設定的那一個。按下「Show title B」，接著縮放視窗，
/// 標題列必須仍然讀作 title B。
struct P50TitleSection: View {
    @Binding var windowTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("1. .navigationTitle -- the assertion is the WINDOW TITLE BAR")
                .font(.system(size: 15))

            VStack(alignment: .leading, spacing: 4) {
                Text("TITLE BAR MUST READ:")
                    .font(.system(size: 11))
                Text(windowTitle)
                    .font(.system(size: 14))
            }
            .padding(8)
            .border(Color.green, width: 2)

            Text("Title bar says 'P50 SCENE DEFAULT ...' instead = the preference never arrived.")
                .font(.system(size: 11))
            Text("Press B, then RESIZE the window: the bar must still say B, not the scene title.")
                .font(.system(size: 11))
            Text("標題列若寫的是「P50 SCENE DEFAULT ...」＝該 preference 從未送達。")
                .font(.system(size: 11))
            Text("按下 B 之後**縮放**視窗：標題列必須仍是 B，而不是 scene 的標題。")
                .font(.system(size: 11))

            HStack(spacing: 10) {
                Button("Show title A") {
                    windowTitle = P50Titles.a
                    P50Diagnostics.write("title changed to a")
                }
                Button("Show title B") {
                    windowTitle = P50Titles.b
                    P50Diagnostics.write("title changed to b")
                }
            }
        }
    }
}

// MARK: - 2. popover

/// Two popovers, two `attachmentEdge` values, and one anchor column placed where
/// both edges have room.
///
/// **The anchors are at the LEFT of the window and in its upper half, and that
/// is a placement decision, not a layout accident.** `GtkBackend+Popovers.swift`
/// maps `attachmentEdge` onto `GtkPopover.position` and says GTK still flips
/// that side when the requested one would leave the monitor -- deliberately, and
/// the other four backends' positioners do the same. So an unexpected side is
/// NOT automatically a bug: it is a bug only if there was room on the side that
/// was asked for. Anchoring at the left with the window's width to the right,
/// and above the window's midline with height below, is what removes the excuse.
///
/// **The trigger buttons and the panels do not share any words.** The buttons
/// say "Open the first panel" / "Open the second panel"; the panels say "PANEL
/// ALPHA" / "PANEL BETA", which appear nowhere else in this app. On a backend
/// with no `BackendFeatures.Popovers` conformance the modifier warns once and
/// draws the anchor unmodified, so failure is "the window did not change" -- and
/// that has to be plainly different from success in a still image.
///
/// **The counter is inside the panel on purpose.** It is the one thing here that
/// `BackendFeatures.PopoverMenus` could not have done: a menu carries a
/// `ResolvedMenu` of labels and toggles and cannot hold a `Widget`, which is the
/// reason `Popovers` had to be a protocol of its own (see `Popovers.swift`). A
/// panel whose number climbs when its own button is pressed is a live widget
/// inside a popover, not a picture of one.
///
/// 兩個 popover、兩個 `attachmentEdge` 值，以及一欄放在「兩個方向都有空間」之處的錨點。
///
/// **錨點位於視窗的左側、且在上半部，那是一項位置決策，不是版面上的意外。**
/// `GtkBackend+Popovers.swift` 把 `attachmentEdge` 對應到 `GtkPopover.position`，並且說明：當所
/// 請求的一側會超出螢幕時，GTK 仍會翻轉它——那是刻意的，其餘四個 backend 的定位器也是這麼做。
/// 因此出現在意料之外的一側**不會**自動就是 bug：只有在所請求的那一側本來就有空間時，它才是 bug。
/// 把錨點放在左側、右方留有整個視窗的寬度，並放在視窗中線之上、下方留有高度，正是為了拿掉那個藉口。
///
/// **觸發按鈕與面板不共用任何字詞。** 按鈕寫的是「Open the first panel」／「Open the second
/// panel」；面板寫的是「PANEL ALPHA」／「PANEL BETA」，而這些字在本 app 的其他任何地方都不會出現。
/// 在未 conform `BackendFeatures.Popovers` 的 backend 上，該 modifier 會警告一次並原樣繪製錨點，
/// 因此失敗就是「視窗沒有變化」——而那在一張靜態圖裡必須與成功明顯不同。
///
/// **計數器刻意放在面板內部。** 它是此處唯一一件 `BackendFeatures.PopoverMenus` 做不到的事：選單
/// 承載的是由標籤與開關構成的 `ResolvedMenu`，無法容納 `Widget`，而那正是 `Popovers` 必須自成一個
/// protocol 的理由（見 `Popovers.swift`）。一塊「按下自己的按鈕、數字就往上跳」的面板，是 popover
/// 裡活著的 widget，不是它的一張照片。
struct P50PopoverSection: View {
    @Binding var isAlphaPresented: Bool
    @Binding var isBetaPresented: Bool
    @Binding var panelCounter: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("2. .popover -- two attachmentEdge values, two separate panels")
                .font(.system(size: 15))
            Text("Success = a floating panel reading PANEL ALPHA or PANEL BETA. Those two")
                .font(.system(size: 11))
            Text("phrases appear nowhere else here, so no click and no panel = failure.")
                .font(.system(size: 11))
            Text("A side other than the one asked for is only a bug if that side had room:")
                .font(.system(size: 11))
            Text("every backend flips a popover that would leave the monitor. Expected.")
                .font(.system(size: 11))
            Text("成功＝出現一塊寫著 PANEL ALPHA 或 PANEL BETA 的浮動面板。這兩個詞在此處別無他處出現，")
                .font(.system(size: 11))
            Text("因此「點了卻沒有面板」就是失敗。出現在非所請求的一側，只有在該側原本有空間時才是 bug：")
                .font(.system(size: 11))
            Text("任何 backend 都會翻轉一個會跑出螢幕的 popover。那是預期行為。")
                .font(.system(size: 11))

            // Anchors in a left-aligned column, not spread across the width. The
            // .trailing popover needs the window's width to its right and the
            // .bottom one needs height below; a row of buttons centred in the
            // window gives neither.
            // 錨點排成一欄且靠左對齊，而非橫跨整個寬度。.trailing 的 popover 需要它右方有整個視窗的
            // 寬度，.bottom 的則需要下方有高度；一排置中於視窗的按鈕兩者都給不了。
            VStack(alignment: .leading, spacing: 10) {
                Button("Open the first panel (attachmentEdge .bottom)") {
                    isAlphaPresented = true
                    P50Diagnostics.write("popover alpha shown")
                }
                .popover(
                    isPresented: $isAlphaPresented,
                    attachmentEdge: .bottom,
                    onDismiss: {
                        // Reached only for a USER dismissal -- clicking away or
                        // pressing escape. `dismissPopover(_:)` must not call
                        // this, per `Popovers.swift`, and GtkBackend keeps that
                        // apart with an `isProgrammaticDismissal` flag. The two
                        // log lines below are therefore an assertion about the
                        // contract, not two names for one event.
                        // 只有**使用者**造成的關閉才會走到這裡——在別處點擊或按下 escape。依
                        // `Popovers.swift` 的規定，`dismissPopover(_:)` 不得呼叫它，而 GtkBackend
                        // 以 `isProgrammaticDismissal` 旗標將兩者分開。因此下方那兩行 log 是對該
                        // 約定的斷言，而不是同一件事的兩個名字。
                        P50Diagnostics.write("popover alpha dismissed")
                    }
                ) {
                    P50Panel(
                        name: "PANEL ALPHA",
                        logName: "alpha",
                        edgeDescription: "asked for .bottom (below the button)",
                        accent: Color.blue,
                        counter: $panelCounter,
                        isPresented: $isAlphaPresented
                    )
                }

                Button("Open the second panel (attachmentEdge .trailing)") {
                    isBetaPresented = true
                    P50Diagnostics.write("popover beta shown")
                }
                .popover(
                    isPresented: $isBetaPresented,
                    attachmentEdge: .trailing,
                    onDismiss: {
                        P50Diagnostics.write("popover beta dismissed")
                    }
                ) {
                    P50Panel(
                        name: "PANEL BETA",
                        logName: "beta",
                        edgeDescription: "asked for .trailing (right of the button)",
                        accent: Color.orange,
                        counter: $panelCounter,
                        isPresented: $isBetaPresented
                    )
                }
            }

            Text("panel button presses so far: \(panelCounter)")
                .font(.system(size: 11))
            Text("Click outside an open panel to light-dismiss it: that path, and only that")
                .font(.system(size: 11))
            Text("path, logs 'popover ... dismissed'. The panel's own close button logs")
                .font(.system(size: 11))
            Text("'closed programmatically' instead, because onDismiss must not fire for it.")
                .font(.system(size: 11))
            Text("在開啟的面板之外點擊即可關閉它：只有那條路徑會記下 'popover ... dismissed'。面板自己的")
                .font(.system(size: 11))
            Text("關閉按鈕記下的是 'closed programmatically'，因為 onDismiss 不得為它觸發。")
                .font(.system(size: 11))
        }
    }
}

/// The content of one popover: a name that exists nowhere else, the edge that
/// was requested, a live button, and a programmatic close.
///
/// The counter it increments lives on ``P50RootView``, not here, and that is
/// what makes the press visible outside the panel too: the section's
/// "panel button presses so far" line moves at the same time, so a reader who
/// dismissed the popover before looking can still see that its button worked.
///
/// 一個 popover 的內容：一個別處不存在的名稱、被請求的邊、一個活的按鈕，以及一個程式化的關閉。
///
/// 它所遞增的計數器住在 ``P50RootView`` 上而不在此處，而這正是讓那一次按壓在面板之外也看得見的
/// 原因：該區塊的「panel button presses so far」那一行會同時變動，因此即使讀者在查看之前就關掉了
/// popover，仍然能看出它的按鈕確實有作用。
///
/// The close button drives the `isPresented` binding directly rather than
/// calling a closure this view was handed. `Button`'s action is declared
/// `@escaping @MainActor @Sendable () -> Void` (`Views/Button.swift:17`), and a
/// plain stored `() -> Void` property does not convert to that; a binding
/// mutated from inside an inline closure is the shape the rest of the P-suite
/// already compiles with (see `P51ControlGroupSection`).
///
/// 關閉按鈕直接驅動 `isPresented` binding，而不是呼叫一個由外部交給本 view 的 closure。`Button`
/// 的 action 宣告為 `@escaping @MainActor @Sendable () -> Void`（`Views/Button.swift:17`），而一個
/// 普通的、被儲存起來的 `() -> Void` 屬性無法轉換成它；「在行內 closure 中變動一個 binding」才是
/// P-suite 其餘部分已經能編譯的寫法（見 `P51ControlGroupSection`）。
struct P50Panel: View {
    var name: String
    /// The short, stable word used in the log line. Lower case and separate from
    /// `name` so the assertable string never changes when the on-screen wording
    /// does.
    /// 用於 log 行的簡短穩定字詞。小寫，並與 `name` 分開，如此當畫面上的措辭改變時，可被斷言的
    /// 字串不會跟著變。
    var logName: String
    var edgeDescription: String
    var accent: Color
    @Binding var counter: Int
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(.system(size: 16))
            Text(edgeDescription)
                .font(.system(size: 11))
            Text("A menu could not hold this button. A popover can.")
                .font(.system(size: 11))
            Text("選單放不下這顆按鈕，popover 可以。")
                .font(.system(size: 11))
            Button("press me (\(counter))") {
                counter += 1
                P50Diagnostics.write("popover counter \(counter)")
            }
            Button("close this panel") {
                isPresented = false
                P50Diagnostics.write("popover \(logName) closed programmatically")
            }
        }
        .padding(10)
        .border(accent, width: 2)
    }
}
