import Foundation
import ImageFormats

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
    /// **This was eighty hand-written lines until 2026-09-19, and the argument
    /// for them did not survive being checked.** The note here used to say that
    /// writing the deflate stream as stored blocks avoided "a zlib dependency
    /// that five backends would each have to resolve". PNG does require a zlib
    /// STREAM -- the format defines IDAT that way -- but not the zlib LIBRARY,
    /// because stored blocks are valid deflate. That part was right. What was
    /// wrong was the premise: `SwiftCrossUI` already depends on `ImageFormats`
    /// unconditionally, for every platform and every build, and `ImageFormats`
    /// already links libpng and zlib. The dependency being avoided was already
    /// present, so the whole trade was paying file size for nothing -- and the
    /// size it was paying was not the "about 4x" the old note guessed either.
    /// Measured on P72's snapshot, 2026-09-19: 326,728 bytes stored against
    /// 1,416 through libpng, a factor of 231. A flat-shaded cube is nearly all
    /// runs of one colour, which is the case deflate is best at.
    ///
    /// The hand-written encoder did produce valid files -- python's `zlib` and
    /// `sips` both read one. It was correct and pointless, which is a harder
    /// thing to notice than a defect.
    ///
    /// 把這張快照編碼成 PNG。
    ///
    /// **在 2026-09-19 之前,這裡是八十行手寫的程式,而支持它們的那個論證經不起查證。** 此處的註解原本
    /// 寫著:把 deflate 串流寫成 stored block,可以避開「一個五個 backend 各自都要解決的 zlib 相依」。
    /// PNG 確實需要一個 zlib **串流**(格式就是這樣定義 IDAT 的),但不需要 zlib **函式庫**——因為
    /// stored block 本來就是合法的 deflate。那一半是對的。錯的是前提:`SwiftCrossUI` 本來就**無條件**
    /// 相依 `ImageFormats`(每個平台、每種建置都一樣),而 `ImageFormats` 本來就連結了 libpng 與 zlib。
    /// 那個被「避開」的相依,原本就已經在了;於是整個取捨等於白白付出檔案大小——而且付出的量,也不是舊註解
    /// 所猜的「大約四倍」。2026-09-19 以 P72 的快照實測:stored 是 326,728 位元組,經 libpng 是 1,416,
    /// 相差 231 倍。一個平面著色的立方體幾乎全是同色的連續段,而那正是 deflate 最擅長的情況。
    ///
    /// 那個手寫的編碼器確實產生得出合法檔案——python 的 `zlib` 與 `sips` 都讀得進去。它是**正確而無用的**,
    /// 而那比一個缺陷更難被察覺。
    public func pngData() throws -> Data {
        let image = ImageFormats.Image<RGBA>(
            width: width,
            height: height,
            bytes: rgbaData
        )
        return Data(try image.encodeToPNG())
    }
}
