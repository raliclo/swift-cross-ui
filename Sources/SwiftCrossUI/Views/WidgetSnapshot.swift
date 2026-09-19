import Foundation

/// The pixels a widget drew, plus enough to write them to a file.
///
/// 一個 widget 所畫出的像素,外加「把它們寫成檔案」所需的東西。
public struct WidgetSnapshot: Equatable, Sendable {
    /// Width in pixels.
    /// 寬度,單位為像素。
    public var width: Int
    /// Height in pixels.
    /// 高度,單位為像素。
    public var height: Int
    /// Rows of RGBA8 pixels, concatenated -- the same layout ``Image`` hands to
    /// ``BackendFeatures/Images/updateImageView(_:rgbaData:width:height:targetWidth:targetHeight:dataHasChanged:environment:)``.
    /// 逐列串接的 RGBA8 像素——與 ``Image`` 交給 backend 的是同一種排列。
    public var rgbaData: [UInt8]

    public init(width: Int, height: Int, rgbaData: [UInt8]) {
        self.width = width
        self.height = height
        self.rgbaData = rgbaData
    }

    /// The pixel at `(x, y)`, or `nil` outside the image.
    ///
    /// Provided because the useful assertion about a snapshot is almost never
    /// "these two images are identical" -- two Metal drivers need not round the
    /// same way, and P72's own notes say so. It is "this pixel is the colour
    /// that face is painted", which needs one pixel and no image comparison at
    /// all.
    ///
    /// `(x, y)` 位置的像素;超出影像範圍則為 `nil`。
    ///
    /// 之所以提供它,是因為對一張快照而言,有用的斷言幾乎從來不是「這兩張影像完全相同」——兩個 Metal
    /// 驅動沒有義務以相同方式捨入,而 P72 自己的註記就這麼寫。有用的斷言是「這個像素就是那一面所塗的
    /// 顏色」,而那只需要一個像素,完全不需要比對影像。
    public func pixel(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let i = (y * width + x) * 4
        guard i + 3 < rgbaData.count else { return nil }
        return (rgbaData[i], rgbaData[i + 1], rgbaData[i + 2], rgbaData[i + 3])
    }

    /// How many distinct colours the snapshot contains, capped at `limit`.
    ///
    /// **The cheapest test that a render actually happened.** A view that drew
    /// nothing gives 1 -- one background colour, or one black. A cube with six
    /// faces and a directional light gives many. Counting up to a limit rather
    /// than exhaustively keeps a 1020x720 snapshot from building a set of three
    /// quarters of a million entries to answer a question that "more than four"
    /// settles.
    ///
    /// 這張快照裡有幾種不同的顏色,上限為 `limit`。
    ///
    /// **那是「算繪真的發生過」最便宜的檢驗。** 一個什麼都沒畫的 view 會給出 1——一種背景色,或一片黑。
    /// 一個有六個面、被一盞方向光照著的立方體會給出很多。數到上限就停、而不是全部數完,是為了不讓一張
    /// 1020x720 的快照為了回答一個「大於四」就能結案的問題,而建出一個七十幾萬筆的集合。
    public func distinctColourCount(limit: Int = 64) -> Int {
        var seen: Set<UInt32> = []
        var i = 0
        while i + 3 < rgbaData.count {
            let key =
                UInt32(rgbaData[i]) << 24 | UInt32(rgbaData[i + 1]) << 16
                    | UInt32(rgbaData[i + 2]) << 8 | UInt32(rgbaData[i + 3])
            seen.insert(key)
            if seen.count >= limit { return seen.count }
            i += 4
        }
        return seen.count
    }

    /// Encodes the snapshot as a PNG.
    ///
    /// **Uncompressed, and that is a deliberate trade rather than an oversight.**
    /// The deflate stream is written as stored blocks, which is a valid deflate
    /// stream that every PNG reader accepts and which needs no zlib: about
    /// eighty lines of CRC-32 and Adler-32 instead of a C dependency that five
    /// backends -- one of them Android, one of them Windows -- would each have to
    /// resolve. A 1020x720 snapshot lands around 2.9 MB. These files exist to be
    /// looked at once and deleted, so size is the cheap axis; a build that fails
    /// to link zlib on one platform is not.
    ///
    /// 把這張快照編碼成 PNG。
    ///
    /// **未壓縮,而那是刻意的取捨,不是疏漏。** deflate 串流是以 stored block 寫出的——那是一個合法的
    /// deflate 串流,每一個 PNG 讀取器都接受,而且**不需要 zlib**:大約八十行的 CRC-32 與 Adler-32,
    /// 換掉一個「五個 backend(其中一個是 Android、一個是 Windows)各自都要想辦法解析」的 C 相依。
    /// 一張 1020x720 的快照大約 2.9 MB。這些檔案的用途是被看一次然後刪掉,因此檔案大小是便宜的那一軸;
    /// 而「在某個平台上連不起 zlib 的建置」不是。
    public func pngData() -> Data {
        var raw = Data()
        raw.reserveCapacity(height * (1 + width * 4))
        for y in 0..<height {
            // Filter byte 0 (None) per scanline. PNG requires one, and None is
            // the right one here: the filters exist to help compression, and
            // nothing is compressing this.
            // 每一條掃描線前面一個 filter 位元組 0(None)。PNG 要求要有一個,而此處 None 是對的:
            // filter 的用途是幫助壓縮,而這裡沒有任何東西在壓縮。
            raw.append(0)
            let start = y * width * 4
            raw.append(contentsOf: rgbaData[start..<min(start + width * 4, rgbaData.count)])
        }

        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        var ihdr = Data()
        ihdr.append(bigEndian: UInt32(width))
        ihdr.append(bigEndian: UInt32(height))
        ihdr.append(contentsOf: [8, 6, 0, 0, 0]) // 8-bit, RGBA, deflate, no filter, no interlace
        png.append(chunk: "IHDR", ihdr)
        png.append(chunk: "IDAT", zlibStored(raw))
        png.append(chunk: "IEND", Data())
        return png
    }
}

/// A zlib stream whose deflate blocks are all stored (uncompressed).
/// 一個 zlib 串流,其 deflate 區塊全部是 stored(未壓縮)。
private func zlibStored(_ raw: Data) -> Data {
    // 0x78 0x01: deflate, 32K window, no preset dictionary, fastest level. The
    // two bytes must satisfy (CMF << 8 | FLG) % 31 == 0 or a reader rejects the
    // stream -- 0x7801 does.
    // 0x78 0x01:deflate、32K 視窗、無預設字典、最快等級。這兩個位元組必須滿足
    // (CMF << 8 | FLG) % 31 == 0,否則讀取器會拒絕整個串流——0x7801 滿足。
    var out = Data([0x78, 0x01])
    let blockSize = 65535
    var offset = 0
    repeat {
        let count = min(blockSize, raw.count - offset)
        let isLast = offset + count >= raw.count
        out.append(isLast ? 1 : 0)
        out.append(littleEndian16: UInt16(count))
        out.append(littleEndian16: UInt16(count) ^ 0xFFFF)
        out.append(raw[raw.startIndex + offset..<raw.startIndex + offset + count])
        offset += count
    } while offset < raw.count
    out.append(bigEndian: adler32(raw))
    return out
}

private func adler32(_ data: Data) -> UInt32 {
    var a: UInt32 = 1
    var b: UInt32 = 0
    for byte in data {
        a = (a + UInt32(byte)) % 65521
        b = (b + a) % 65521
    }
    return (b << 16) | a
}

private let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
    var c = UInt32(i)
    for _ in 0..<8 {
        c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1
    }
    return c
}

private func crc32(_ data: Data) -> UInt32 {
    var c: UInt32 = 0xFFFF_FFFF
    for byte in data {
        c = crcTable[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8)
    }
    return c ^ 0xFFFF_FFFF
}

extension Data {
    fileprivate mutating func append(bigEndian value: UInt32) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }

    fileprivate mutating func append(littleEndian16 value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    /// A PNG chunk: length, type, payload, then a CRC over the TYPE AND THE
    /// PAYLOAD -- not over the length. Including the length is the classic
    /// mistake here, and it produces a file that every reader rejects with
    /// "CRC error" rather than one that half-works.
    /// 一個 PNG chunk:長度、型別、內容,然後是一個涵蓋**型別與內容**的 CRC——**不含長度**。把長度也算
    /// 進去是此處的經典錯誤,而它產生的是一個「每個讀取器都以 CRC error 拒絕」的檔案,不是一個半能用的檔案。
    fileprivate mutating func append(chunk type: String, _ payload: Data) {
        append(bigEndian: UInt32(payload.count))
        var body = Data(type.utf8)
        body.append(payload)
        append(body)
        append(bigEndian: crc32(body))
    }
}
