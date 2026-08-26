// The whole file is behind SCUI_DEBUG. Not a runtime check: without it,
// `InputEvent` is not a dependency of this target at all, so the import below
// would not resolve. See Sources/DebugFeatures/README.md for why the switch is
// in the manifest rather than here.
// 整個檔案位於 SCUI_DEBUG 之下。這不是執行期檢查：若未定義它，`InputEvent` 根本不是本 target 的
// 依賴，因此下方的 import 無法解析。該開關為何置於 manifest 而非此處，詳見
// Sources/DebugFeatures/README.md。
#if SCUI_DEBUG

import AppKit
import Foundation
import InputEvent

/// The `-actionfile` flag: synthesised input, driven from a CSV file.
///
/// The AppKitBackend half of what `GtkBackend/ActionFileReplay.swift` does, and
/// deliberately the same shape: same flag, same format, same one-line report on
/// stderr. A file that drives P0 on Linux drives P0 here.
///
/// The format is documented in `Sources/InputEvent/README.md`.
///
/// `-actionfile` 旗標：以 CSV 檔驅動的合成輸入。
///
/// 這是 `GtkBackend/ActionFileReplay.swift` 的 AppKitBackend 對應版本，且刻意採取相同形狀：相同的
/// 旗標、相同的格式、相同的 stderr 單行回報。一個能在 Linux 上驅動 P0 的檔案，在此同樣能驅動 P0。
extension AppKitBackend {
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
    /// The delay is shorter than GtkBackend's and for a different reason. There
    /// it exists because both injection paths post to whatever is in front, so
    /// replaying before the window is mapped and focused drives another
    /// application entirely. ``AppKitSynthesiser`` addresses this process's own
    /// window by number, so that failure cannot happen here; the wait is only
    /// for the window to have a content view laid out, so that a click computed
    /// from its geometry lands where the file meant.
    ///
    /// 由 `show(window:)` 呼叫，且僅針對第一個顯示的視窗。否則擁有兩個視窗的應用程式會重放該檔
    /// 兩次，而第二次執行所作用的，是第一次所遺留下來的狀態。
    ///
    /// 此處的延遲比 GtkBackend 短，理由也不同。在那邊，延遲的存在是因為兩條注入路徑都會投遞至位於
    /// 前方的任何視窗，因此在視窗被 map 並取得焦點之前重放，會完全驅動到別的應用程式。
    /// ``AppKitSynthesiser`` 依編號定址本行程自身的視窗，故此種失敗在此不可能發生；此處等待的只是
    /// 視窗的 content view 完成佈局，好讓依其幾何算出的點擊落在檔案所指之處。
    func replayActionFileIfRequested() {
        guard !AppKitBackend.hasReplayedActionFile, let file = Self.requestedActionFile else {
            return
        }
        AppKitBackend.hasReplayedActionFile = true

        // Off the main thread, deliberately. A replay is nearly all sleeping --
        // waiting out a `sleep` row -- and on the main thread that sleep is
        // AppKit's too, so the events already posted sit in the queue
        // unprocessed. AppKitSynthesiser hops back to the main queue for each
        // individual post, which is the smallest arrangement that keeps the
        // sleeping off the UI thread while still touching AppKit legally.
        //
        // 刻意不在主執行緒上執行。重放的絕大部分時間都在睡眠——等待某個 `sleep` 列——而在主執行緒
        // 上，那份睡眠同時也是 AppKit 的睡眠，於是已投遞的事件只能滯留在佇列中無法被處理。
        // AppKitSynthesiser 會為每一次個別投遞跳回主佇列，這是「讓睡眠遠離 UI 執行緒」與「合法地
        // 觸碰 AppKit」兩者兼顧的最小安排。
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1) {
            do {
                try AppKitSynthesiser().replayFile(at: file)
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

#endif
