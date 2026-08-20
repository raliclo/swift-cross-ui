import Foundation
import InputEvent

/// The `-actionfile` flag: synthesised input, driven from a CSV file.
///
/// The entry point is here rather than in each application because the flag is
/// meant to work in all of them, and because the one thing it has to get right
/// -- replaying only once the window is actually on screen -- is something the
/// backend knows and an application does not.
///
/// The format is documented in `Sources/InputEvent/README.md`.
///
/// `-actionfile` 旗標：以 CSV 檔驅動的合成輸入。
///
/// 進入點放在此處而非各個應用程式中，因為此旗標本就應在全部應用程式中可用；也因為它唯一必須做對的
/// 事——等視窗真正出現在螢幕上之後才重放——是 backend 知道而應用程式不知道的資訊。
///
/// 格式記載於 `Sources/InputEvent/README.md`。
extension GtkBackend {
    /// The file named by `-actionfile`, if the flag was passed.
    static var requestedActionFile: URL? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "-actionfile"),
            index + 1 < arguments.count
        else { return nil }
        return URL(fileURLWithPath: arguments[index + 1])
    }

    /// Replays that file against this process's own window.
    ///
    /// Called from `show(window:)`, and only for the first window shown. An
    /// application with two windows would otherwise replay the file twice, and
    /// the second run would act on the state the first one left behind.
    ///
    /// The delay is because `present()` returning does not mean the window is
    /// mapped, focused and painted. Both injection paths post to whatever is in
    /// front, so replaying too early drives another application entirely --
    /// silently, since neither reports where its events landed.
    ///
    /// 由 `show(window:)` 呼叫，且僅針對第一個顯示的視窗。否則擁有兩個視窗的應用程式會重放該檔
    /// 兩次，而第二次執行所作用的，是第一次所遺留下來的狀態。
    ///
    /// 之所以延遲，是因為 `present()` 返回並不代表視窗已被 map、取得焦點並完成繪製。兩條注入路徑
    /// 都是打到位於前方的任何視窗，因此太早重放會完全驅動到別的應用程式——而且是靜默的，因為兩者
    /// 都不會回報其事件落在何處。
    func replayActionFileIfRequested() {
        guard !hasReplayedActionFile, let file = Self.requestedActionFile else { return }
        hasReplayedActionFile = true

        // Off the main thread, deliberately. A replay is nearly all sleeping --
        // waiting for a subprocess, waiting out a `sleep` row -- and on the main
        // thread that sleep is GTK's too, so the events already posted sit in
        // the queue unprocessed. Measured: a file that opened a menu and then
        // pressed an item reported success and changed nothing, because the
        // popover was never mapped before the second click was posted at it.
        //
        // 刻意不在主執行緒上執行。重放的絕大部分時間都在睡眠——等待子行程、等待某個 `sleep` 列
        // ——而在主執行緒上，那份睡眠同時也是 GTK 的睡眠，於是已投遞的事件只能滯留在佇列中無法被
        // 處理。實測：一個「開啟選單、再按下項目」的檔案回報成功卻毫無變化，因為第二次點擊投遞到
        // popover 位置時，該 popover 從未被 map 出來。
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1) {
            do {
                #if os(Windows)
                let synthesiser = Win32Synthesiser()
                #elseif os(Linux)
                let synthesiser = try XdotoolSynthesiser()
                #else
                throw SynthesiserError.unsupported("-actionfile")
                #endif
                try synthesiser.replayFile(at: file)
                Self.reportActionFile("replayed \(file.lastPathComponent)")
            } catch {
                Self.reportActionFile("failed: \(error)")
            }
        }
    }

    /// Says what happened, on stderr.
    ///
    /// Always, not behind a `--debug` flag. A replay that failed leaves a window
    /// that looks untouched, which is indistinguishable from the application
    /// ignoring the input -- and that is exactly the wrong bug to go looking
    /// for. The line is one per run and only appears when the flag was passed.
    ///
    /// 一律輸出，不受 `--debug` 旗標控制。失敗的重放會留下一個看似未被觸碰的視窗，這與「應用程式
    /// 忽略了輸入」無法區分——而那正是最不該去追查的方向。此訊息每次執行僅一行，且只在有傳入該
    /// 旗標時才會出現。
    private nonisolated static func reportActionFile(_ message: String) {
        FileHandle.standardError.write(Data("-actionfile: \(message)\n".utf8))
    }
}
