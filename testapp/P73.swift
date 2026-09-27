import DefaultBackend
import Foundation
import SwiftCrossUI

// P73: a publish that lands while the view graph is still being built.
//
// **The crash this app exists for** is `ViewGraphNode.swift:13` -- `_widget!` on a
// nil widget -- reported by the SoftPCB session on 2026-09-27 and first recorded on
// 2026-09-08 as "an empty ForEach that is not the last child". It was never the
// ForEach. `OnAppearModifier` runs its action inside `asWidget`, which a node calls
// AFTER creating its children and BEFORE assigning its own widget. If that action
// spins the run loop -- `Process.waitUntilExit()` does, and a model that checks a
// toolchain on appear is exactly the code that calls it -- then any publish already
// queued on the main queue is delivered in the middle of the node's construction. A
// child that observes the model resizes, `onResize` climbs to the half-built node,
// and its layout reads a widget that does not exist yet.
//
// That is why SoftPCB saw it depend on timing: a job that finished at once published
// while the run loop was still spinning, and one that slept 0.5 s first published
// after construction had finished.
//
// **Two modes, from the same binary, so the control is the same program:**
//
//   (default) or --spin   the onAppear action starts a job that publishes via
//                         DispatchQueue.main.async at once, then spins the run
//                         loop for 0.2 s the way waitUntilExit does
//   --no-spin             the same job and no spin; must never crash
//
// Pass: the window shows `report: done` and the process is still alive. Fail, before
// the fix: exit 133 (SIGTRAP) at ViewGraphNode.swift:13 with no window.
//
// **Why an app and not a unit test.** A unit test with DummyBackend was written and
// deleted on 2026-09-27: it passed with the fix AND without it. Printing from the
// child's body showed why -- every update arrived AFTER the spin, never during it.
// In the test process the nested run loop does not drain the main queue, so the
// timing this crash needs cannot happen there; in an AppKit app it happens 10 times
// in 10. A test that passes either way would say the fix is covered when nothing
// covers it, so this app and actions/mac/P73-publish-during-build.csv are the check.
//
// **為什麼是一支 app、而不是單元測試。**2026-09-27 寫過一個用 DummyBackend 的單元測試,然後刪掉了:
// 它在有修正與沒有修正時都會通過。在子節點的 body 裡印出訊息,就看得出原因——每一次更新都在轉動**之後**
// 才抵達,從來不在轉動期間。在測試行程裡,巢狀的 run loop 不會清空主佇列,所以這個崩潰所需要的時序在那裡
// 不可能發生;在 AppKit app 裡,10 次發生 10 次。一個怎樣都會通過的測試,會宣稱這個修正有被涵蓋,而實際上
// 什麼都沒有涵蓋它,因此擔任檢查的是這支 app 與 actions/mac/P73-publish-during-build.csv。
//
// P73:一次在 view graph 還在建構時抵達的發布。
//
// **這支 app 為之存在的崩潰**是 `ViewGraphNode.swift:13`——對 nil widget 做 `_widget!`——由 SoftPCB
// session 於 2026-09-27 回報,並在 2026-09-08 首次被記為「一個不是最後一個子節點的空 ForEach」。它從來
// 不是 ForEach。`OnAppearModifier` 在 `asWidget` 裡執行它的動作,而節點是在**建好子節點之後、指派自己的
// widget 之前**呼叫 `asWidget` 的。若那個動作轉了 run loop——`Process.waitUntilExit()` 就會,而一個在
// appear 時檢查工具鏈的 model 正是會呼叫它的程式——那麼任何已經排在主佇列上的發布,都會在節點建構的
// 中途被送達。觀察該 model 的子節點改變尺寸,`onResize` 爬到那個建到一半的節點,而它的排版讀到一個還不
// 存在的 widget。
//
// 那正是 SoftPCB 看到它取決於時序的原因:立刻完成的工作,在 run loop 還在轉時就發布了;先睡 0.5 秒的工作,
// 則在建構結束之後才發布。
//
// **同一個執行檔的兩種模式,讓對照組就是同一支程式:**預設或 `--spin` 會轉 run loop;`--no-spin` 不轉,
// 而且永遠不可以崩潰。通過:視窗顯示 `report: done`,行程仍然活著。修正前的失敗:以 133(SIGTRAP)結束於
// ViewGraphNode.swift:13,沒有視窗。

final class P73Model: SwiftCrossUI.ObservableObject {
    @SwiftCrossUI.Published var report = "pending"
    @SwiftCrossUI.Published var isRunning = false

    /// Starts a job that is finished before it starts, and publishes the result the
    /// way SoftPCB's ToolchainModel does: from a background queue, via the main queue.
    /// 啟動一個「還沒開始就已經結束」的工作,並以 SoftPCB 的 ToolchainModel 的方式發布結果:
    /// 從背景佇列、經由主佇列。
    func start() {
        isRunning = true
        DispatchQueue.global().async {
            DispatchQueue.main.async {
                self.report = "done -- published while the graph may still be building"
                self.isRunning = false
                P73Diagnostics.write("PUBLISHED report")
            }
        }
    }
}

enum P73Diagnostics {
    static func write(_ message: String) {
        print("[P73] \(message)")
        fflush(stdout)
    }
}

@main
@HotReloadable
struct P73PublishDuringBuildApp: App {
    var body: some Scene {
        WindowGroup("P73 publish during build") {
            #hotReloadable {
                P73RootView()
            }
        }
        .defaultSize(width: 560, height: 360)
    }
}

struct P73RootView: View {
    @StateObject var model = P73Model()

    var spins: Bool { !CommandLine.arguments.contains("--no-spin") }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("P73: a publish that lands while the view graph is being built")
            Text("mode: \(spins ? "spin (the run loop turns inside onAppear)" : "no-spin (control)")")
            P73ReportView(model: model)
        }
        .padding(16)
        .onAppear {
            P73Diagnostics.write("APPEAR -- starting the job, spin=\(spins)")
            model.start()
            if spins {
                // What Process.waitUntilExit() does on the main thread: run the run loop
                // until the child exits. Anything queued on the main queue runs here.
                // Process.waitUntilExit() 在主執行緒上做的事:轉 run loop 直到子行程結束。
                // 任何排在主佇列上的東西都會在這裡執行。
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            }
            P73Diagnostics.write("APPEAR returned")
        }
    }
}

/// The observer whose resize climbs to the half-built node. Its text grows from
/// "pending" to a long sentence, so the publish changes its size -- a publish that
/// changed nothing would commit in place and never reach the parent.
/// 其尺寸改變會爬到那個建到一半的節點的觀察者。它的文字從「pending」長成一整句,所以發布會改變它的尺寸
/// ——一次什麼都沒改變的發布會就地 commit,永遠不會碰到父節點。
struct P73ReportView: View {
    @ObservedObject var model: P73Model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("report: \(model.report)")
            Text("running: \(model.isRunning ? "yes" : "no")")
        }
    }
}
