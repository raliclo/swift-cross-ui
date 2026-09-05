// Minimises every visible top-level window whose title contains a substring.
//
//   winmin.exe "<title substring>"        minimise matching windows
//   winmin.exe --list                     print every visible window title
//   winmin.exe --help
//
// Exit codes, which are the interface: 0 at least one window was minimised,
// 1 nothing matched, 2 bad arguments.
//
// WHY IT EXISTS. Synthesised replays need the app under test in front, and
// Windows will not let an arbitrary process call SetForegroundWindow -- see the
// measurement in Sources/InputEvent/Win32Synthesiser.swift, which is why the
// replay pins the window topmost instead and warns when it never took the
// foreground. A maximised window belonging to something else defeats both: the
// clicks land on it, and the run reports a failure that belongs to the desktop
// rather than to the code. That happened three times on 2026-09-05 -- Windows
// Settings, then a full-screen Codex window -- and cost a wrong diagnosis
// recorded in mistakes.csv2.
//
// This does the one thing that fixes it without touching what the other window
// contains: it minimises. Not close, not kill. A window that is minimised can
// be restored by whoever owns it; a window that is closed cannot.
//
// WM_SYSCOMMAND/SC_MINIMIZE rather than ShowWindow(SW_MINIMIZE), because the
// former is what the window's own minimise button sends. Some frameworks --
// Electron among them, which is what the window that prompted this is built on
// -- track their own window state and ignore a ShowWindow they did not expect.
//
// 將所有「標題含指定子字串」的可見 top-level 視窗最小化。
//
// 結束碼即為其介面：0 至少最小化了一個視窗、1 沒有相符者、2 引數錯誤。
//
// 為何存在。合成重放需要受測 app 位於前方，而 Windows 不允許任意行程呼叫 SetForegroundWindow
// ——見 Sources/InputEvent/Win32Synthesiser.swift 中的量測，那也是重放改為「將視窗釘為 topmost」
// 並在始終未取得前景時發出警告的原因。一個屬於別人的最大化視窗會同時擊敗這兩者：點擊落在它身上，
// 而該次執行回報的失敗屬於桌面，而非屬於程式碼。這在 2026-09-05 發生了三次——先是 Windows
// 「設定」，接著是全螢幕的 Codex 視窗——並造成一次錯誤診斷，記於 mistakes.csv2。
//
// 本工具只做那件足以解決問題、又不觸碰另一個視窗內容的事：最小化。不是關閉，也不是強制結束。
// 被最小化的視窗，其擁有者可以自行還原；被關閉的視窗則不能。
//
// 使用 WM_SYSCOMMAND/SC_MINIMIZE 而非 ShowWindow(SW_MINIMIZE)，因為前者正是該視窗自己的
// 最小化按鈕所送出的訊息。某些框架——包括促成本工具誕生的那個視窗所使用的 Electron——會自行
// 追蹤視窗狀態，並忽略它們並未預期的 ShowWindow 呼叫。

import Foundation
import WinSDK

func title(of hwnd: HWND) -> String {
    var buffer = [WCHAR](repeating: 0, count: 512)
    guard GetWindowTextW(hwnd, &buffer, 512) > 0 else { return "" }
    return String(decodingCString: buffer, as: UTF16.self)
}

final class Collector {
    var windows: [HWND] = []
}

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.first == "--help" || arguments.first == "-h" {
    // The header is the documentation; print it rather than keep a second copy
    // that can disagree with it.
    // 標頭即說明文件；直接印出它，而不是另存一份可能與它互相矛盾的副本。
    let source = URL(fileURLWithPath: #filePath)
    if let text = try? String(contentsOf: source, encoding: .utf8) {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).prefix(9) {
            print(line.hasPrefix("// ") ? String(line.dropFirst(3)) : String(line.dropFirst(2)))
        }
    }
    exit(0)
}

guard let needle = arguments.first, !needle.isEmpty else {
    FileHandle.standardError.write(Data("winmin: needs a window title substring, or --list\n".utf8))
    exit(2)
}

let collector = Collector()
let enumerator: @convention(c) (HWND?, LPARAM) -> WindowsBool = { hwnd, lParam in
    guard let hwnd, IsWindowVisible(hwnd) else { return true }
    let collector = Unmanaged<Collector>.fromOpaque(
        UnsafeRawPointer(bitPattern: Int(lParam))!
    ).takeUnretainedValue()
    collector.windows.append(hwnd)
    return true
}
let pointer = Unmanaged.passUnretained(collector).toOpaque()
_ = EnumWindows(enumerator, LPARAM(Int(bitPattern: pointer)))

if needle == "--list" {
    for window in collector.windows {
        let name = title(of: window)
        if !name.isEmpty { print(name) }
    }
    exit(0)
}

var minimised = 0
for window in collector.windows where title(of: window).contains(needle) {
    // 0xF020 is SC_MINIMIZE. Sent, not posted, so the call returns after the
    // window has handled it and a caller can act on the result immediately.
    // 0xF020 即 SC_MINIMIZE。採用 send 而非 post，使呼叫在該視窗處理完畢後才返回，
    // 呼叫端因而可以立即依據結果採取行動。
    _ = SendMessageW(window, UINT(WM_SYSCOMMAND), WPARAM(0xF020), 0)
    print("minimised: \(title(of: window))")
    minimised += 1
}

exit(minimised > 0 ? 0 : 1)
