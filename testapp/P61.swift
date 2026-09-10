import DefaultBackend
import Foundation
import SwiftCrossUI

// P61: does Slider.onEditingChanged report a DRAG, and only a drag?
//
// The number was checked, not guessed: `ls testapp` gives P50..P60, and nothing
// under testapp/plan or matrix_coverage mentions P61.
//
// **THE COUNTER IS THE ASSERTION, AND THE BUTTON IS THE CONTROL.** A slider that
// reports editing correctly and one that reports it on every value change draw
// the same picture while a finger is on them -- both say "editing: YES". They
// differ on the two cases nobody watches:
//
//   the drag           one begin and one end, however many values it produced
//   the code path      NO begin and NO end, because nobody edited anything
//
// So this app counts the transitions and offers a button that moves the slider
// from code. Press it and the value changes while both counts stay put; that is
// the half a screenshot of a drag cannot show.
//
// WHY IT CANNOT BE DERIVED FROM THE VALUE, which is the reason the backends each
// report it separately rather than the framework inferring it: a value that stops
// arriving is indistinguishable from a user who paused mid-drag, and a slider
// driven from code changes value with nobody touching it. Both mistakes produce a
// plausible number and no error.
//
// P61:`Slider.onEditingChanged` 回報的是不是「一次拖曳」,而且只有拖曳?
//
// 這個編號是查過的,不是猜的:`ls testapp` 給出 P50..P60,而 testapp/plan 與 matrix_coverage 底下
// 都沒有提到 P61。
//
// **那個計數器是判定,而那顆按鈕是對照組。** 一個「正確回報編輯」的滑桿,與一個「每次值變就回報」的
// 滑桿,在手指壓著它時畫出來的是同一張圖——兩者都說「editing: YES」。它們的差別在兩個沒有人盯著的
// 情況:一次拖曳應該只有**一次開始、一次結束**,無論它產生了多少個值;而由程式驅動的那條路應該
// **完全沒有**開始與結束,因為沒有人編輯任何東西。
//
// 因此這支 app 計數那些轉換,並提供一顆「從程式移動滑桿」的按鈕。按下它,數值會變而兩個計數都不動;
// 那正是「一張拖曳的截圖」顯示不出來的另一半。
//
// 為什麼它無法由數值推導——而那正是各 backend 分別回報、而非由框架推斷的理由:一個「不再送來的值」
// 與「使用者在拖曳途中停手」無從分辨,而一個由程式驅動的滑桿會在沒有人碰它的情況下改變數值。
// 這兩種錯誤都會產生一個看起來合理的數字,而且不會有任何錯誤訊息。

enum P61Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P61] \(message)")

        guard let data = "P61 \(Date()) \(message)\n".data(using: .utf8) else { return }
        // `NSHomeDirectory()` before the working directory on iOS, where the
        // working directory is a read-only "/" and the write fails silently --
        // the trap P60 hit on 2026-09-10.
        // 在 iOS 上先用 `NSHomeDirectory()` 再用工作目錄：那裡的工作目錄是唯讀的「/」，寫入會靜默
        // 失敗——正是 P60 於 2026-09-10 踩到的陷阱。
        let directory =
            ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
            ?? {
                #if os(iOS) || os(tvOS)
                    return NSHomeDirectory() + "/Documents"
                #else
                    return FileManager.default.currentDirectoryPath
                #endif
            }()
        let url = URL(fileURLWithPath: directory)
            .appendingPathComponent("p61-debug-events.log")
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
        write("RENDER COMPLETE -- P61 ready for editing-changed checks")
    }
}

@main
@HotReloadable
struct P61SliderEditingApp: App {
    var body: some Scene {
        WindowGroup("P61 slider onEditingChanged") {
            #hotReloadable {
                P61RootView()
            }
        }
        .defaultSize(width: 620, height: 420)
    }
}

struct P61RootView: View {
    @State var value = 0.5
    @State var isEditing = false
    @State var beganCount = 0
    @State var endedCount = 0
    /// How many values arrived, so a reader can see that many values still make
    /// one edit.
    /// 有多少個數值抵達，好讓讀者看見「許多個數值仍然只構成一次編輯」。
    @State var valueCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("P61: Slider.onEditingChanged")
                .font(.system(size: 20))
            Text("backend -> \(String(describing: DefaultBackend.self))")

            Text("value: \(String(format: "%.2f", value))")
            Text("editing: \(isEditing ? "YES" : "no")")
            Text("began: \(beganCount)   ended: \(endedCount)   values seen: \(valueCount)")

            // **`.onEditingChanged` BEFORE `.frame`, and the order is not a
            // style choice.** It is declared on `Slider`, not on `View`, so
            // anything that erases the type first -- `.frame` returns
            // `some View` -- takes it out of reach: *"value of type 'some View'
            // has no member 'onEditingChanged'"*. That is a compiler error
            // rather than a silent one, which is why this is a note and not a
            // defect, but it is the first thing a reader will get wrong.
            // **`.onEditingChanged` 放在 `.frame` 之前，而這個順序不是風格選擇。** 它宣告在
            // `Slider` 上、不在 `View` 上，因此任何先抹除型別的東西——`.frame` 回傳的是
            // `some View`——都會讓它構不著：*「value of type 'some View' has no member
            // 'onEditingChanged'」*。那是一個編譯錯誤而非靜默錯誤，這也是它在此處只是一則註記、
            // 而非一項缺陷的原因；但它會是讀者第一個弄錯的地方。
            Slider(value: $value, in: 0...1)
                .onEditingChanged { editing in
                    if editing {
                        beganCount += 1
                    } else {
                        endedCount += 1
                    }
                    isEditing = editing
                    P61Diagnostics.write(
                        "editing \(editing ? "began" : "ended") "
                            + "began=\(beganCount) ended=\(endedCount) values=\(valueCount)"
                    )
                }
                .frame(width: 320)

            // The control. A slider moved from code must NOT report an edit, and
            // that is the half a drag cannot demonstrate: a backend that fired
            // onEditingChanged from its value handler would look correct for
            // every drag and wrong only here.
            // 對照組。一個由程式移動的滑桿**不得**回報編輯，而那正是拖曳所展示不了的另一半：一個
            // 「從數值 handler 觸發 onEditingChanged」的 backend，在每一次拖曳中看起來都正確，
            // 只有在這裡才會出錯。
            Button("move it from code (+0.1)") {
                value = min(1, value + 0.1)
                P61Diagnostics.write(
                    "moved from code to \(String(format: "%.2f", value)) "
                        + "-- began and ended must NOT change"
                )
            }

            Button("reset counts") {
                beganCount = 0
                endedCount = 0
                valueCount = 0
                P61Diagnostics.write("counts reset")
            }

            Text(
                "Expected: one drag = began 1, ended 1, however many values it produced. "
                    + "Pressing the code button changes the value and leaves both counts alone."
            )
            Text(
                "預期:一次拖曳 = began 1、ended 1,無論它產生了多少個數值。按下那顆「從程式移動」的"
                    + "按鈕會改變數值,而兩個計數都不動。"
            )
        }
        .padding(16)
        .onChange(of: value) {
            valueCount += 1
        }
        .onAppear {
            P61Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            P61Diagnostics.renderComplete()
        }
    }
}
