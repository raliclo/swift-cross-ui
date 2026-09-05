// Minimises every visible top-level window whose title contains a substring.
//
//   winmin.exe "<title substring>"        minimise matching windows
//   winmin.exe --list                     every visible window: HWND, title, flags
//   winmin.exe --clear                    minimise every titled window that is up
//   winmin.exe --restore                  undo --clear
//   winmin.exe --help
//
// Exit codes, which are the interface: 0 at least one window was acted on,
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
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).prefix(10) {
            print(line.hasPrefix("// ") ? String(line.dropFirst(3)) : String(line.dropFirst(2)))
        }
    }
    exit(0)
}

guard let needle = arguments.first, !needle.isEmpty else {
    FileHandle.standardError.write(
        Data("winmin: needs a window title substring, or --list/--clear/--restore\n".utf8)
    )
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
    // The HWND and the minimised flag are both printed, and neither is
    // decoration. A replay that misses reports the HWND it hit --
    // `hitRoot=0x...` -- and without the handle here there is no way to turn
    // that number into a name except by guessing, which cost two wrong guesses
    // on 2026-09-05. IsIconic matters because a MINIMISED window is still
    // "visible" to IsWindowVisible and still appears in this list; a list that
    // did not say so reads as "minimising did nothing".
    //
    // HWND 與「是否最小化」兩者都會印出，且都不是裝飾。一次落空的重放會回報它所命中的 HWND
    // ——`hitRoot=0x...`——而若此處不列出 handle，就只能用猜的把那個數字對回名稱，而這在
    // 2026-09-05 已經猜錯兩次。IsIconic 之所以重要：**被最小化的視窗對 IsWindowVisible 而言
    // 仍然「可見」**，因此仍會出現在本清單中；一份不標示這件事的清單，讀起來就像「最小化沒有作用」。
    let foreground = GetForegroundWindow()
    for window in collector.windows {
        let name = title(of: window)
        if name.isEmpty { continue }
        let handle = UInt(bitPattern: Int(bitPattern: window))
        var flags: [String] = []
        if IsIconic(window) { flags.append("minimised") }
        if window == foreground { flags.append("FOREGROUND") }
        let suffix = flags.isEmpty ? "" : "  [\(flags.joined(separator: ", "))]"
        print(String(format: "0x%016llx  %@%@", UInt64(handle), name, suffix))
    }
    exit(0)
}

if needle == "--restore" {
    // Undoes --clear. Present because --clear is a large, uninvited change to
    // someone else's desktop, and a tool that can make that change without
    // being able to undo it should not have been written.
    //
    // SW_RESTORE, not SW_SHOW: restore returns a window to whatever it was
    // before it was minimised, maximised or normal, which is the only thing
    // here that knows which of those it should be.
    //
    // 還原 --clear 所做的事。之所以存在，是因為 --clear 是對「別人的桌面」所做的、未經邀請的
    // 大幅改動，而一個能造成該改動卻無法復原它的工具，本就不該被寫出來。
    //
    // 使用 SW_RESTORE 而非 SW_SHOW：restore 會讓視窗回到它被最小化之前的狀態——無論當時是一般
    // 還是最大化——而在此處，只有它知道那該是哪一種。
    var restored = 0
    for window in collector.windows where IsIconic(window) && !title(of: window).isEmpty {
        _ = ShowWindow(window, SW_RESTORE)
        restored += 1
    }
    print("restored \(restored) window(s)")
    exit(restored > 0 ? 0 : 1)
}

if needle == "--clear" {
    // Minimises everything that is up, which is what a synthesised replay
    // actually needs and what minimising one window at a time cannot deliver.
    //
    // Foreground here is a stack, not a single obstruction. Minimising the
    // front window promotes the next one, and on 2026-09-05 that produced four
    // rounds -- Windows Settings, a Codex window, VS Code, the terminal, then LM
    // Studio -- each of which looked like "the" blocker until it was gone. A
    // sweep cannot be run against a desktop that has to be cleared one layer per
    // attempt.
    //
    // Untitled windows are skipped, because that is what tool windows, tray
    // hosts and the desktop itself look like from here, and minimising those
    // achieves nothing while risking something.
    //
    // 一次把所有開著的視窗最小化——那才是合成重放真正需要的，也是「一次收一個視窗」做不到的事。
    //
    // 此處的前景是一個**堆疊**，不是單一障礙物。把最前面的視窗最小化，只會讓下一個遞補上來；
    // 2026-09-05 因此連續出現四輪——Windows「設定」、一個 Codex 視窗、VS Code、終端機，然後是
    // LM Studio——每一個在被移開之前，看起來都像是「那個」阻礙者。一輪 sweep 無法在「每嘗試一次
    // 才能清掉一層」的桌面上進行。
    //
    // 無標題的視窗會被略過：從此處看去，工具視窗、系統匣宿主與桌面本身都是那副樣子，把它們
    // 最小化毫無所得，卻有可能造成損害。
    var cleared = 0
    for window in collector.windows {
        if title(of: window).isEmpty { continue }
        if IsIconic(window) { continue }
        _ = SendMessageW(window, UINT(WM_SYSCOMMAND), WPARAM(0xF020), 0)
        cleared += 1
    }
    print("cleared \(cleared) window(s)")
    exit(cleared > 0 ? 0 : 1)
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
