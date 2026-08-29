// Captures one window with PrintWindow(PW_RENDERFULLCONTENT) and writes a BMP.
//
//   wincap.exe "<title substring>" <out.bmp>
//
// Exit codes, which are the interface: 0 captured and the image has content,
// 1 no visible window matched, 2 bad arguments, 3 captured but the image is
// entirely black.
//
// Why it exists. screenshot.zsh captures windows with ffmpeg's gdigrab, which
// is GDI/BitBlt, and BitBlt needs a redirection surface to copy from. Two kinds
// of window here do not have one:
//
//   - GTK on Windows with Direct Composition enabled (`-GPU 2`). GDK creates
//     the toplevel with WS_EX_NOREDIRECTIONBITMAP; measured 2026-08-29 as
//     exstyle 0x00200000, against 0x00000100 for a window that captures fine.
//     The style cannot be removed afterwards -- SetWindowLongPtrW returns 0
//     with GetLastError 87, ERROR_INVALID_PARAMETER.
//   - A WSLg window seen from the Windows side, which is WS_EX_LAYERED
//     (0x00080100). gdigrab given the exact title finds it and copies nothing:
//     45 non-black pixels out of 155,775 sampled.
//
// This is not a property of Direct Composition or of D3D. P6 presents a D3D11
// composition swapchain and gdigrab captures its window perfectly, because its
// HWND keeps its redirection surface. What matters is the window, not what
// draws into it.
//
// PW_RENDERFULLCONTENT asks DWM to render the window instead of copying a
// surface, which is the documented route for exactly this case. Measured: 93.0%
// non-black for the DComp GTK window, 92.6% for the WSLg one, both showing the
// complete window.
//
// The black-pixel count is the point, not a nicety. PrintWindow returns TRUE
// while producing an entirely black bitmap -- the same failure gdigrab has
// above -- so a caller reading only the exit status would be told an empty
// image was a success. Exit 3 exists for that.
//
// 以 PrintWindow(PW_RENDERFULLCONTENT) 擷取單一視窗並寫出 BMP。
//
// 結束碼即為它的介面：0 成功且影像有內容、1 找不到符合的可見視窗、2 參數錯誤、
// 3 擷取到了但影像整片全黑。
//
// 存在的理由。screenshot.zsh 以 ffmpeg 的 gdigrab 擷取視窗，那是 GDI/BitBlt，而 BitBlt 需要
// 有 redirection surface 可供複製。此處有兩種視窗沒有：
//
//   - 啟用 Direct Composition 的 Windows GTK（`-GPU 2`）。GDK 以
//     WS_EX_NOREDIRECTIONBITMAP 建立頂層視窗；2026-08-29 實測 exstyle 為 0x00200000，
//     而可正常擷取的視窗為 0x00000100。該樣式建立後無法移除——SetWindowLongPtrW 回傳 0，
//     GetLastError 為 87（ERROR_INVALID_PARAMETER）。
//   - 從 Windows 這側看到的 WSLg 視窗，其樣式為 WS_EX_LAYERED（0x00080100）。即使給
//     gdigrab 完全正確的標題，它找得到卻什麼也複製不到：取樣的 155,775 個像素中僅 45 個非黑。
//
// 這並非 Direct Composition 或 D3D 的性質。P6 呈現的是 D3D11 的 composition swapchain，
// gdigrab 卻能完美擷取其視窗，因為它的 HWND 保有 redirection surface。決定成敗的是「視窗」，
// 不是「誰在往裡面畫」。
//
// PW_RENDERFULLCONTENT 要求 DWM 重新繪製該視窗，而非複製既有表面，正是為這種情況所設計的
// 途徑。實測：DComp 的 GTK 視窗非黑像素達 93.0%，WSLg 視窗為 92.6%，兩者都完整呈現視窗。
//
// 黑色像素計數才是重點，不是附加品。PrintWindow 會在產出全黑點陣圖的同時回傳 TRUE——與上文
// gdigrab 的失敗形態相同——因此只讀結束碼的呼叫端會把空白影像當成成功。結束碼 3 就是為此存在。

import Foundation
import WinSDK

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: wincap.exe <title substring> <out.bmp>")
    exit(2)
}
let needle = args[1].lowercased()
let outPath = args[2]

// Matching is a case-insensitive SUBSTRING, deliberately, because the exact
// title is not always what the caller knows. WSLg appends " (Ubuntu)" and, when
// its GPU path is degraded, prepends "[WARN:COPY MODE] " -- so the window the
// caller asked for by app name is neither of those strings. gdigrab matches
// exactly and fails on precisely that.
// 比對刻意採用「不分大小寫的子字串」，因為呼叫端未必知道確切標題。WSLg 會附加
// 「 (Ubuntu)」，而當其 GPU 路徑降級時還會前置「[WARN:COPY MODE] 」——於是呼叫端以 app
// 名稱指定的那個視窗，兩種字串都不是。gdigrab 採精確比對，正是敗在這一點。
var target: HWND?
func title(of hwnd: HWND) -> String {
    var buffer = [WCHAR](repeating: 0, count: 512)
    guard GetWindowTextW(hwnd, &buffer, 512) > 0 else { return "" }
    return String(decodingCString: buffer, as: UTF16.self)
}
let finder: @convention(c) (HWND?, LPARAM) -> WindowsBool = { hwnd, _ in
    guard let hwnd, IsWindowVisible(hwnd), target == nil else { return true }
    let name = title(of: hwnd)
    if !name.isEmpty, name.lowercased().contains(needle) {
        target = hwnd
        print("window: \(name)")
        return false
    }
    return true
}
_ = EnumWindows(finder, 0)

guard let hwnd = target else {
    print("no visible window matched \"\(needle)\"")
    exit(1)
}

var rect = RECT()
GetWindowRect(hwnd, &rect)
let width = Int(rect.right - rect.left)
let height = Int(rect.bottom - rect.top)
guard width > 0, height > 0 else {
    print("window has no area")
    exit(1)
}

// Reported so a caller can see WHY a capture failed rather than only that it
// did. 0x00200000 is WS_EX_NOREDIRECTIONBITMAP and 0x00080000 is WS_EX_LAYERED;
// either explains a black gdigrab capture, and neither is visible from ffmpeg.
// 一併回報，讓呼叫端看得到擷取「為何」失敗，而不只是「失敗了」。0x00200000 是
// WS_EX_NOREDIRECTIONBITMAP，0x00080000 是 WS_EX_LAYERED；兩者都能解釋 gdigrab 拍出全黑，
// 而從 ffmpeg 一側都看不見。
let ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE)
let exHex = String(UInt64(bitPattern: Int64(ex)), radix: 16)
print("size: \(width)x\(height)  exstyle: 0x\(exHex)")

let screenDC = GetDC(nil)
let memDC = CreateCompatibleDC(screenDC)
var info = BITMAPINFO()
info.bmiHeader.biSize = DWORD(MemoryLayout<BITMAPINFOHEADER>.size)
info.bmiHeader.biWidth = LONG(width)
info.bmiHeader.biHeight = LONG(-height)     // top-down
info.bmiHeader.biPlanes = 1
info.bmiHeader.biBitCount = 32
info.bmiHeader.biCompression = DWORD(BI_RGB)

var bits: UnsafeMutableRawPointer?
guard let dib = CreateDIBSection(memDC, &info, UINT(DIB_RGB_COLORS), &bits, nil, 0),
      let pixels = bits else {
    print("CreateDIBSection failed")
    exit(1)
}
let old = SelectObject(memDC, dib)

// PW_RENDERFULLCONTENT is 0x00000002. Not every SDK mapping exposes it as a
// constant, so it is written out rather than assumed present.
// PW_RENDERFULLCONTENT 為 0x00000002。並非每一種 SDK 映射都會將它提供為常數，因此直接寫出
// 數值，而不假設它存在。
let ok = PrintWindow(hwnd, memDC, UINT(0x0000_0002))

let buffer = pixels.bindMemory(to: UInt8.self, capacity: width * height * 4)
var nonBlack = 0
for index in stride(from: 0, to: width * height * 4, by: 4) {
    if buffer[index] > 8 || buffer[index + 1] > 8 || buffer[index + 2] > 8 { nonBlack += 1 }
}
let tenths = nonBlack * 1000 / (width * height)
print("PrintWindow: \(ok)  non-black: \(nonBlack)/\(width * height) (\(tenths / 10).\(tenths % 10)%)")

// BMP, because it needs no encoder: a 14-byte file header, the 40-byte info
// header already built above, then the rows bottom-up. The caller converts to
// PNG with the ffmpeg it already depends on.
// 選用 BMP，因為它不需要任何編碼器：14 位元組的檔頭、上方已建好的 40 位元組資訊標頭，
// 接著是由下而上的各列像素。呼叫端再以它本來就依賴的 ffmpeg 轉為 PNG。
let rowBytes = width * 4
let pixelBytes = rowBytes * height
var file = [UInt8]()
file.reserveCapacity(54 + pixelBytes)
func append32(_ value: UInt32) { for shift in [0, 8, 16, 24] { file.append(UInt8((value >> UInt32(shift)) & 0xFF)) } }
func append16(_ value: UInt16) { file.append(UInt8(value & 0xFF)); file.append(UInt8(value >> 8)) }
file.append(0x42); file.append(0x4D)                  // "BM"
append32(UInt32(54 + pixelBytes)); append32(0); append32(54)
append32(40); append32(UInt32(width)); append32(UInt32(height))
append16(1); append16(32); append32(0); append32(UInt32(pixelBytes))
append32(2835); append32(2835); append32(0); append32(0)
for row in stride(from: height - 1, through: 0, by: -1) {
    let start = row * rowBytes
    file.append(contentsOf: UnsafeBufferPointer(start: buffer + start, count: rowBytes))
}

SelectObject(memDC, old)
DeleteObject(dib)
DeleteDC(memDC)
ReleaseDC(nil, screenDC)

do {
    try Data(file).write(to: URL(fileURLWithPath: outPath))
} catch {
    print("write failed: \(outPath)")
    exit(1)
}
print("wrote \(outPath)")
exit(nonBlack > 0 ? 0 : 3)
