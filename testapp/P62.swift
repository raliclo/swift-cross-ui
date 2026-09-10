import DefaultBackend
import Foundation
import SwiftCrossUI

// P62: does DocumentGroup give each document its own window and its own value?
//
// The number was checked, not guessed: `ls testapp` gives P50..P61, and nothing
// under testapp/plan or matrix_coverage mentions P62.
//
// **ONE WINDOW PROVES NOTHING, WHICH IS WHY THIS APP OPENS A SECOND.** A
// DocumentGroup that gave every window the same document would look correct for
// as long as only one is open -- type in it and the text appears, save it and
// the text is there. It goes wrong only when a second document exists, and then
// it goes wrong silently: two windows showing one value, where an edit in
// either appears in both.
//
// So the assertion is a COMPARISON: press "new document", type something
// different in each window, and the two must disagree. Both windows are
// photographed at once.
//
// WHAT IS NOT COVERED, said here rather than discovered: autosave, versions, the
// unsaved-changes prompt, and reopening last session's documents. `DocumentGroup`
// does not do those yet and its own documentation says so.
//
// P62:`DocumentGroup` 有沒有讓每份文件擁有自己的視窗與自己的值?
//
// 這個編號是查過的,不是猜的:`ls testapp` 給出 P50..P61,而 testapp/plan 與 matrix_coverage 底下
// 都沒有提到 P62。
//
// **一個視窗什麼都證明不了,這正是這支 app 會開第二個視窗的原因。** 一個「讓每個視窗共用同一份文件」的
// DocumentGroup,在只開一個視窗時看起來完全正確——在裡面打字,文字出現;存檔,文字也在。它只有在
// 第二份文件存在時才會出錯,而且是靜默地出錯:兩個視窗顯示同一個值,在任一邊編輯都會出現在兩邊。
//
// 因此判定是一次**比較**:按下「new document」、在兩個視窗各打不同的字,兩者必須不同。兩個視窗會被
// 同時拍下。
//
// 未涵蓋的部分,在此說明而非留給人發現:自動儲存、版本、未儲存提示,以及重開上次工作階段的文件。
// `DocumentGroup` 尚未做這些,而它自己的文件也是這麼寫的。

enum P62Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P62] \(message)")

        guard let data = "P62 \(Date()) \(message)\n".data(using: .utf8) else { return }
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
            .appendingPathComponent("p62-debug-events.log")
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
        write("RENDER COMPLETE -- P62 ready for document checks")
    }
}

/// A plain-text document, which is the smallest thing that can be wrong.
///
/// `init(data:)` decodes rather than throwing on invalid UTF-8, because
/// `String(decoding:as:)` replaces bad bytes and a text editor that refused to
/// open a file with one stray byte would be worse than one that shows it. The
/// throwing half of `FileDocument` still matters -- it is what a format with a
/// header would use -- and this document is simply not that.
///
/// 一份純文字文件，那是「能出錯的最小單位」。
///
/// `init(data:)` 選擇解碼而非在遇到無效 UTF-8 時 throw，因為 `String(decoding:as:)` 會替換掉壞掉的
/// 位元組，而一個「因為一個雜散位元組就拒絕開檔」的文字編輯器，會比一個把它顯示出來的更糟。
/// `FileDocument` 會 throw 的那一半仍然重要——那是「帶有檔頭的格式」會用到的——而這份文件單純不是那種。
struct P62TextFile: FileDocument {
    static let readableContentTypes = [ContentType.plainText]

    var text: String

    init() {
        text = ""
    }

    init(data: Data) throws {
        text = String(decoding: data, as: UTF8.self)
    }

    func data() throws -> Data {
        Data(text.utf8)
    }
}

@main
@HotReloadable
struct P62DocumentApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: P62TextFile()) { document in
            #hotReloadable {
                P62EditorView(document: document)
            }
        }
    }
}

struct P62EditorView: View {
    @Binding var document: P62TextFile

    @Environment(\.newDocument) var newDocument

    /// A per-window label, so a capture of two windows says which is which.
    ///
    /// A `@State` initialised from a counter rather than a value passed in: the
    /// editor closure receives only the document binding, so there is nothing
    /// to pass, and two windows built from the same closure would otherwise be
    /// indistinguishable in a screenshot.
    /// 一個逐視窗的標籤，好讓「同時拍下兩個視窗」的擷圖能說出誰是誰。
    ///
    /// 使用由計數器初始化的 `@State`，而非由外部傳入的值：那個編輯器 closure 只收到 document
    /// binding，沒有東西可傳；而兩個由同一個 closure 建出來的視窗，否則在截圖裡無從分辨。
    @State var windowNumber = P62EditorView.nextWindowNumber()

    nonisolated(unsafe) static var windowCounter = 0
    static func nextWindowNumber() -> Int {
        windowCounter += 1
        return windowCounter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("P62 document window \(windowNumber)")
                .font(.system(size: 18))
            Text("backend -> \(String(describing: DefaultBackend.self))")

            Text("this document's text: \(document.text.isEmpty ? "(empty)" : document.text)")

            HStack(spacing: 8) {
                Button("type A") { append("A") }
                Button("type B") { append("B") }
                Button("clear") {
                    document.text = ""
                    P62Diagnostics.write("window \(windowNumber) cleared")
                }
            }

            Button("new document") {
                newDocument()
                P62Diagnostics.write("window \(windowNumber) asked for a new document")
            }

            Text(
                "Expected: a second window shows (empty) while this one keeps its text. "
                    + "Both showing the same text means every window shares one document, "
                    + "which looks correct until a second one exists."
            )
            Text(
                "預期:第二個視窗顯示 (empty),而這一個保有它的文字。兩者顯示相同文字,代表每個視窗共用"
                    + "同一份文件——而那在第二個視窗出現之前看起來都是正確的。"
            )
        }
        .padding(16)
        .onAppear {
            P62Diagnostics.write("window \(windowNumber) appeared")
            P62Diagnostics.renderComplete()
        }
    }

    func append(_ letter: String) {
        document.text += letter
        P62Diagnostics.write("window \(windowNumber) text is now '\(document.text)'")
    }
}
