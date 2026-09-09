import DefaultBackend
import Foundation
import SwiftCrossUI

// P33 missing views: compileable approximations beside the missing SwiftUI names.

enum P33Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P33] \(message)")
        let data = Data("P33 \(Date()) \(message)\n".utf8)
        // SCUI_DEBUG_EVENTS_DIR when a launcher sets it, so every app's log lands
        // in one place; unset, the launch directory exactly as before. The
        // contract is documented in testapp/test_support/test_common.zsh.
        // 有 SCUI_DEBUG_EVENTS_DIR 時取自該變數，讓每支 app 的 log 集中一處；未設定時仍為啟動
        // 目錄，行為與過去完全相同。該約定記載於 testapp/test_support/test_common.zsh。
        let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
            ?? FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p33-debug-events.log")
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
        // ~~"RENDER COMPLETE -- P33 ready for missing-view checks"~~ -- the
        // THIRD place in this file that outlived what it described. The screen
        // text and the .onAppear line were corrected on 2026-09-09; this one
        // and the window title were not, so the app announced itself ready for
        // "missing-view checks" one line above stating that nothing is missing.
        //
        // Found by grepping this file for the word rather than by re-reading
        // the diff. A correction that fixes the instances it happens to be
        // looking at is how a claim survives being corrected -- see the same
        // pattern below the "Nothing on this list" Text, where the replacement
        // text was itself false.
        //
        // ~~「RENDER COMPLETE -- P33 ready for missing-view checks」~~——本檔中**第三處**活得比它所
        // 描述的事實還久的地方。畫面文字與 .onAppear 那一行已於 2026-09-09 更正,而這一行與視窗標題
        // 沒有,於是這支 app 一邊聲明「沒有東西缺席」,一邊宣告自己「已準備好進行缺失 view 的檢查」。
        //
        // 它是靠對本檔 grep 那個字找出來的,不是靠重讀 diff。**一次只修好「自己剛好在看的那幾處」的
        // 更正,正是一個主張得以在被更正之後繼續存活的方式**——同樣的樣式見下方「Nothing on this
        // list」那個 Text,那裡連替換文字本身都是假的。
        write("RENDER COMPLETE -- P33 approximations ready")
    }
}

@main
@HotReloadable
struct P33MissingViewsApp: App {
    var body: some Scene {
        // ~~"P33 missing views"~~. THE WINDOW TITLE IS NOT DECORATION HERE:
        // `test_support/test_P33.zsh` exports it as `TEST_TITLE` and
        // `screenshot.zsh -w` finds the window by it, so both were changed in
        // one edit. VERIFIED 2026-09-09 with the app confirmed running first:
        // the new title captures from priority 1 (wincap), the old title fails.
        //
        // ~~"Changing one without the other does not fail -- wincap finds
        // nothing and the script falls back to a DESKTOP capture"~~ was written
        // here in the same edit and is FALSE; see the correction in
        // test_P33.zsh, which records what the tool actually does. A guess
        // about a tool, written into a change about stale claims.
        //
        // ~~「P33 missing views」~~。**此處的視窗標題不是裝飾**:
        // `test_support/test_P33.zsh` 會把它匯出為 `TEST_TITLE`,而 `screenshot.zsh -w` 是靠它找到
        // 視窗的,因此兩者已在同一次編輯中一併更改。**2026-09-09 驗證**(且先確認 app 確實在跑):
        // 新標題可由 priority 1(wincap)擷取,舊標題則失敗。
        //
        // ~~「只改其中一邊不會失敗——wincap 只是找不到東西,腳本便退回**桌面**擷取」~~ 這句話就寫在
        // 同一次編輯裡,而它是**假的**;更正記於 test_P33.zsh,那裡寫著該工具實際的行為。
        // 一項關於工具的臆測,被寫進了一次以「過期主張」為主題的改動裡。
        WindowGroup("P33 hand-built approximations") {
            #hotReloadable {
                P33RootView()
            }
        }
        .defaultSize(width: 820, height: 620)
    }
}

struct P33RootView: View {
    @State var stepperValue = 0
    @State var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("P33: hand-built approximations")
                .font(.system(size: 20))
            Text("backend -> \(String(describing: DefaultBackend.self))")
            // These two lines were a list of nine missing names until 2026-09-04,
            // when seven of them were implemented. They are now the record of
            // what P33 was FOR, and the two that are still absent. P46 exercises
            // the real views; P33 keeps the hand-built shapes beside them so the
            // approximation and the implementation can be compared.
            //
            // The wording was NOT trimmed to fit. Every string here is a
            // different length from what it replaced, so P33-hide-details.csv's
            // measured coordinates had to be re-measured in the same change --
            // shortening a wrapped line lifts everything below it, and a click
            // that then lands on empty space raises nothing and still reports a
            // pass.
            //
            // 這兩行在 2026-09-04 之前是一份「九個缺失名稱」的清單，當天其中七個被實作了。它們現在
            // 記錄的是 P33 當初的用途，以及仍然缺席的那兩個。P46 演練真正的 view；P33 則保留手工搭出
            // 的形狀放在旁邊，使近似做法與實作可以互相對照。
            //
            // 措辭**並未**為了遷就版面而修剪。此處每個字串的長度都與被取代者不同，因此
            // P33-hide-details.csv 的量測座標必須在同一次改動中重新量測——縮短一行換行文字會把它
            // 下方的一切往上抬，而屆時落在空白處的點擊不會引發任何東西，卻仍會回報通過。
            Text("Hand-built shapes, kept for comparison. The real views now exist -- see P46.")

            // ~~"Still missing: Label(systemImage:) and ColorPicker. Both need
            // backend work, not composition."~~ -- BOTH EXIST. Re-checked
            // 2026-09-09, one at a time, with a control (`VStack` found,
            // `ZZZNotARealType` absent, so the search itself works):
            //   ColorPicker            Views/ColorPicker.swift, landed e6165e8a
            //   Label(_:systemImage:)  Views/Label.swift:143, a real
            //                          `public init(_ title: String, systemImage: String)`,
            //                          not a doc comment -- Label.swift's own
            //                          prose still opens "deliberately absent",
            //                          which is why the init was checked and
            //                          not the file
            //
            // THE LIST ABOVE WAS ALREADY CORRECTED ONCE, and that is the part
            // worth keeping. On 2026-09-04 it went from nine names to two,
            // because seven had been implemented. Those two then went stale
            // within FOUR DAYS. Correcting a list does not make it
            // self-maintaining; it resets the clock. The only version of this
            // line that cannot go stale is one that does not enumerate, which
            // is what it now says -- P46 exercises the real views and will fail
            // if one of them disappears, whereas this Text could only ever be
            // checked by a human who happened to doubt it.
            //
            // ~~「Still missing: Label(systemImage:) and ColorPicker.」~~——**兩個都存在**。
            // 2026-09-09 逐一重新查證,並附對照組(`VStack` 找得到、`ZZZNotARealType` 不存在,
            // 證明搜尋本身有效):`ColorPicker` 位於 Views/ColorPicker.swift(e6165e8a 落地);
            // `Label(_:systemImage:)` 位於 Views/Label.swift:143,是一個真正的
            // `public init(_ title: String, systemImage: String)`,而非文件註解——`Label.swift`
            // 自己的說明文字開頭仍寫著「刻意不提供」,這正是去查那個 init、而不是查那個檔案的理由。
            //
            // **上面那份清單已經被修正過一次了**,而那才是值得留下來的部分。2026-09-04 它從九個名字
            // 縮成兩個,因為其中七個已被實作;那兩個接著在**四天內**過期。**修正一份清單並不會讓它
            // 從此自我維護,只是把碼表歸零。** 這一行唯一不會過期的版本,是不去列舉的版本——也就是
            // 它現在的樣子。P46 演練真正的 view,少了任何一個它就會失敗;而這個 Text 從來只能靠
            // 一個剛好起疑的人去查證。
            // THE FIRST DRAFT OF THE REPLACEMENT SAID "P46 drives the real
            // views", AND THAT WAS ALSO FALSE. Caught before it shipped only
            // because the replacement was checked with the same method as the
            // thing it replaced. Measured 2026-09-09 (`grep -ln` per name over
            // `testapp/P*.swift`, control: `ZZZNotAReal` matched nothing):
            //
            //   Stepper, DisclosureGroup, LabeledContent, Gauge, Link   P46
            //   ColorPicker                                             P48
            //   Label(_:systemImage:)                                   P47, P51, P53
            //
            // P46 drives five of the nine. The two this correction is about are
            // the two P46 does NOT touch -- so a pointer at P46 would have been
            // wrong precisely where a reader would follow it. That is why the
            // line on screen now points nowhere: line 81 above already says
            // "see P46", and one soft pointer is enough. A map that is right
            // today belongs in a comment, where nobody is shown it as fact.
            //
            // Note what this table does and does not say. It says these files
            // REFERENCE those views; it does not say any of them has been run
            // and observed on this backend. Those are different claims, and
            // conflating them is what ScrollViewReader cost on 2026-09-09.
            //
            // **替換文字的初稿寫的是「P46 drives the real views」,而那同樣是假的。** 之所以在它上線
            // 前被抓到,只是因為我用「查證被替換者」的同一套方法去查了替換者。2026-09-09 實測
            // (對 `testapp/P*.swift` 逐名 `grep -ln`,對照組 `ZZZNotAReal` 零命中):P46 驅動
            // Stepper、DisclosureGroup、LabeledContent、Gauge、Link;`ColorPicker` 是 **P48**;
            // `Label(_:systemImage:)` 是 **P47、P51、P53**。
            //
            // P46 只驅動九個裡的五個,而本次更正所針對的那兩個,正是 P46 **沒有**碰到的兩個——因此
            // 一個指向 P46 的指路,會剛好在讀者真的會照著走的地方出錯。這就是畫面上那一行現在不指路的
            // 原因:上方第 81 行已經寫了「see P46」,一個軟性指路就夠了。**一張今天正確的地圖屬於註解,
            // 那裡不會有人把它當成事實看待。**
            //
            // 另請注意這張表說了什麼、沒說什麼。它說的是這些檔案**引用**了那些 view;它**沒有**說其中
            // 任何一個曾在這個 backend 上被執行並觀察過。那是兩種不同的主張,而把兩者混為一談,正是
            // ScrollViewReader 在 2026-09-09 付出的代價。
            Text("Nothing on this list is missing any more.")
                .font(.system(size: 13))

            Divider()
            Text("Stepper approximation")
            HStack(spacing: 8) {
                Button("-") { stepperValue -= 1 }
                Text("value \(stepperValue)")
                Button("+") { stepperValue += 1 }
            }

            Text("DisclosureGroup approximation")
            Button(expanded ? "Hide details" : "Show details") {
                expanded.toggle()
                // Names the new value, so an action file has something better
                // than a picture to check. Added 2026-09-04: the Windows action
                // file for this button had to rest on the capture alone, and an
                // unchanged log after a click is then expected rather than
                // evidence -- the two are indistinguishable without this line.
                // 指出新的值，使動作檔有比截圖更可靠的東西可以檢查。2026-09-04 新增：此按鈕的
                // Windows 動作檔原本只能依靠擷圖，而在那種情況下「點擊後 log 沒有變化」是預期
                // 行為而非證據——少了這一行，兩者無從分辨。
                P33Diagnostics.write("details expanded=\(expanded)")
            }
            if expanded {
                Text("Details are plain conditional content, not a DisclosureGroup.")
            }

            Text("LabeledContent approximation")
            HStack(spacing: 12) {
                Text("Label")
                Text("Value")
            }
        }
        .padding(18)
        .onAppear {
            P33Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            // A log line is a claim like any other, and this one was false from
            // the moment the seven views landed. It is inside .onAppear rather
            // than on screen, which is exactly why it would have gone on being
            // read as current: nothing shows it to anyone until they grep.
            //
            // ~~"still missing Label(systemImage:) ColorPicker -- the other
            // seven are implemented, see P46"~~ was the SECOND version of this
            // line and it lasted four days, 2026-09-04 to 2026-09-09. It was
            // written BY the correction that removed seven stale names, which
            // is the whole point: the fix and the next stale claim were the
            // same edit. This version names no view, so there is nothing left
            // in it to go out of date.
            //
            // 一行 log 與其他任何陳述一樣是一項主張，而這一行自那七個 view 落地的那一刻起就是假的。
            // 它位於 .onAppear 之內而非畫面上，這正是它會被繼續當成現況讀下去的原因：在有人 grep
            // 之前，沒有任何東西會把它呈現給任何人。
            //
            // ~~「still missing Label(systemImage:) ColorPicker」~~ 是這一行的**第二版**，存活了四天
            // (2026-09-04 至 2026-09-09)。它是**由那次「移除七個過期名稱」的修正本身寫下的**——而
            // 那正是重點:**修正,與下一個過期主張,是同一次編輯。** 這一版不指名任何 view,因此它裡面
            // 已經沒有東西可以過期。
            // AND THE THIRD VERSION WAS WRONG TOO, in the same way and in the
            // same edit. ~~"all nine approximated views now exist upstream --
            // P46 drives the real ones"~~ was written on 2026-09-09 by the
            // change that removed the false claim from the SCREEN, and it
            // carried that claim's replacement -- "P46 drives the real ones" --
            // which is false: P46 drives five of the nine, and neither of the
            // two this correction was about. The screen text was fixed and this
            // line was left holding the discarded sentence.
            //
            // It survived a build, a `strings` check and a replay. The replay
            // even PRINTED it, into the very log this file is verified by, and
            // it read as a pass because the assertion under test was
            // `details expanded=false` on the line below. **A log line nobody
            // asserts on is not evidence; it is unverified text that happens to
            // be near evidence.**
            //
            // So this line no longer describes the world. It names the app and
            // nothing else, and the driver map lives in the comment above the
            // Text, where it is not shown to anyone as fact.
            //
            // **而第三版同樣是錯的**——錯法相同,而且就發生在同一次編輯裡。
            // ~~「all nine approximated views now exist upstream -- P46 drives the real ones」~~
            // 是 2026-09-09 那次「把假宣稱從**畫面**上移除」的改動所寫下的,它帶著那句宣稱的替換文字
            // 「P46 drives the real ones」——而那是假的:P46 驅動九個裡的五個,且**不包含**本次更正所
            // 針對的那兩個。畫面上的文字被修好了,而這一行留著那句被丟棄的句子。
            //
            // 它通過了一次建置、一次 `strings` 檢查、以及一次重放。重放甚至把它**印了出來**,印進了
            // 本檔賴以驗證的那份 log 裡,而它讀起來像通過——因為受測的斷言是下一行的
            // `details expanded=false`。**一行沒有人對它下斷言的 log,不是證據;它只是碰巧落在證據
            // 旁邊的未驗證文字。**
            //
            // 因此這一行不再描述世界。它只指出這是哪一支 app,別無其他;而那張對照表放在 Text 上方的
            // 註解裡,那裡不會有人把它當成事實看待。
            P33Diagnostics.write("P33 approximations rendered")
            P33Diagnostics.renderComplete()
        }
    }
}
