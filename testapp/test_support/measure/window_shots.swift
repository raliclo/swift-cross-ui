// window_shots: captures every on-screen window owned by a process, one PNG
// each, with `screencapture -l` -- so a sheet (an untitled child window) and a
// window covered by other apps are captured as they are, not as the screen
// shows them.
//
//   swiftc -O -o /tmp/window_shots testapp/test_support/measure/window_shots.swift
//   /tmp/window_shots <owner name or pid> <output prefix>
//
// Prints one line per window: id, layer, bounds, title, file.
//
// window_shots:為某個行程擁有的每一個畫面上視窗各拍一張 PNG(`screencapture -l`)——因此 sheet(沒有標題的子視窗)
// 與被其他 app 蓋住的視窗都會照它本身拍下，而不是照螢幕上看到的樣子。每個視窗印一行：id、layer、邊界、標題、檔名。

import CoreGraphics
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write("usage: window_shots <owner name or pid> <output prefix>\n".data(using: .utf8)!)
    exit(2)
}
let owner = arguments[1]
let prefix = arguments[2]
let pid = Int32(owner)

let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
    as? [[String: Any]] ?? []
var count = 0
for info in list {
    let ownerName = info[kCGWindowOwnerName as String] as? String ?? ""
    let ownerPID = info[kCGWindowOwnerPID as String] as? Int32 ?? -1
    guard pid.map({ $0 == ownerPID }) ?? (ownerName == owner) else { continue }
    guard let id = info[kCGWindowNumber as String] as? Int else { continue }
    let layer = info[kCGWindowLayer as String] as? Int ?? 0
    let title = info[kCGWindowName as String] as? String ?? ""
    let bounds = info[kCGWindowBounds as String] as? [String: Double] ?? [:]
    let file = "\(prefix)-\(id).png"
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "-o", "-l", "\(id)", file]
    try? process.run()
    process.waitUntilExit()
    let box = "\(Int(bounds["X"] ?? 0)),\(Int(bounds["Y"] ?? 0)) \(Int(bounds["Width"] ?? 0))x\(Int(bounds["Height"] ?? 0))"
    print("\(id) layer \(layer) \(box) '\(title)' \(process.terminationStatus == 0 ? file : "capture failed")")
    count += 1
}
if count == 0 {
    print("no on-screen window owned by \(owner)")
    exit(1)
}
