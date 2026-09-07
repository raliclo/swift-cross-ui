/// The symbols this toolkit can draw on every backend, and what each one is
/// called there.
///
/// Generated from `testapp/plan/symbol-table-v1.md`, which is the source of
/// truth and carries the evidence for every value. Regenerate with the command
/// recorded in that document's "Regeneration commands" section rather than
/// editing this file: a value typed here has no citation behind it, and the
/// point of the table is that each one was grepped out of a downloaded file.
///
/// **Five fields, none optional, and that is the design.** A symbol that cannot
/// be expressed on one backend is not in this list, so "supported everywhere
/// except X" has no way to be written down. `textFallback` is the field that
/// makes that possible: it is what a backend draws when the platform cannot
/// produce the glyph, which is not a rare case -- GTK 4 ships 138 icons and the
/// desktop theme supplies the rest, and Segoe Fluent Icons is absent from
/// Windows 10 by default. Without a fallback both render nothing, silently.
///
/// 本工具組能在每一個 backend 上畫出的符號，以及它們在各處的名稱。
///
/// 由 `testapp/plan/symbol-table-v1.md` 產生，該文件是真實來源，並記載每一個值的證據。請以該文件
/// 「Regeneration commands」一節所記的指令重新產生，而不要直接編輯本檔：在此手動輸入的值沒有任何
/// 引證，而那張表的意義正在於每一個值都是從下載回來的檔案中 grep 出來的。
///
/// **五個欄位，沒有一個是 optional，而那正是設計本身。** 一個無法在某個 backend 上表達的符號不會
/// 出現在這份清單中，因此「除了 X 之外都支援」根本無從寫下。`textFallback` 是讓這件事成立的欄位：
/// 當平台無法產生該字符時，backend 畫的就是它——而那並非罕見情況：GTK 4 只內建 138 個圖示、其餘由
/// 桌面主題提供，而 Windows 10 預設沒有 Segoe Fluent Icons。少了退路，兩者都會靜默地畫出空白。
public struct SystemSymbol: Sendable, Hashable {
    /// The name this toolkit uses, and the key callers look up.
    /// 本工具組所使用的名稱，也是呼叫端查找時使用的鍵。
    public let name: String

    /// The SF Symbols name, for AppKit and UIKit.
    /// SF Symbols 的名稱，供 AppKit 與 UIKit 使用。
    public let sfSymbol: String

    /// The freedesktop icon name, **without** the `-symbolic` suffix.
    ///
    /// GtkBackend appends it. Measured 2026-09-07 against GTK 4.22.4: of these
    /// 36 names, 0 resolve plain and 15 resolve with the suffix, because GTK 4
    /// ships the symbolic family and not the legacy full-colour set. Storing the
    /// stem keeps this column comparable with the specification it was derived
    /// from and puts the platform detail in the backend that knows it.
    ///
    /// freedesktop 的圖示名稱，**不含** `-symbolic` 後綴。
    ///
    /// 由 GtkBackend 自行附加。2026-09-07 對 GTK 4.22.4 實測：這 36 個名稱中，純名稱 0 個解析成功，
    /// 加上該後綴則有 15 個——因為 GTK 4 出貨的是 symbolic 家族，而非舊有的全彩集。此處保存字根，
    /// 可讓本欄與其所依據的規格保持可比對，並把平台細節留給知道它的那個 backend。
    public let gtkIconName: String

    /// The Segoe Fluent Icons code point, for WinUIBackend.
    /// Segoe Fluent Icons 的碼位，供 WinUIBackend 使用。
    public let segoeScalar: UInt32

    /// The AndroidKit `R.drawable` name, for AndroidBackend.
    /// AndroidKit 的 `R.drawable` 名稱，供 AndroidBackend 使用。
    public let androidDrawable: String

    /// What to draw when the platform cannot produce the glyph.
    ///
    /// Never empty. A backend that finds its icon missing draws this instead of
    /// nothing, so a missing symbol is visible rather than silent.
    ///
    /// 當平台無法產生該字符時所要畫的東西。
    ///
    /// 永不為空。找不到圖示的 backend 會改畫它而非什麼都不畫，使缺失的符號是看得見的，而不是靜默的。
    public let textFallback: String

    public init(
        name: String,
        sfSymbol: String,
        gtkIconName: String,
        segoeScalar: UInt32,
        androidDrawable: String,
        textFallback: String
    ) {
        self.name = name
        self.sfSymbol = sfSymbol
        self.gtkIconName = gtkIconName
        self.segoeScalar = segoeScalar
        self.androidDrawable = androidDrawable
        self.textFallback = textFallback
    }

    /// The Segoe glyph as a string, or the fallback if the code point is not a
    /// scalar. Every value in the table is, so the fallback is unreachable and
    /// present only because `Unicode.Scalar(_:)` is failable.
    /// Segoe 字符的字串形式；若該碼位不是合法的 scalar 則回傳退路。表中每個值都是合法的，因此該退路
    /// 不可能被觸及，此處存在僅因為 `Unicode.Scalar(_:)` 是 failable 的。
    public var segoeGlyph: String {
        Unicode.Scalar(segoeScalar).map { String(Character($0)) } ?? textFallback
    }
}

extension SystemSymbol {
    /// Looked up by the name a caller passes to `Image(systemName:)`.
    ///
    /// Both the toolkit's own name and the SF Symbols name resolve, because
    /// SwiftUI spells this with an SF name -- `Image(systemName: "plus")` --
    /// and code moved across from SwiftUI should keep working. `add` and `plus`
    /// are the same row.
    ///
    /// 依呼叫端傳給 `Image(systemName:)` 的名稱查找。
    ///
    /// 本工具組自身的名稱與 SF Symbols 的名稱都能解析，因為 SwiftUI 是以 SF 名稱書寫的
    /// ——`Image(systemName: "plus")`——而從 SwiftUI 搬過來的程式碼應該仍然可用。`add` 與 `plus`
    /// 指的是同一列。
    public static func named(_ name: String) -> SystemSymbol? {
        byName[name]
    }

    private static let byName: [String: SystemSymbol] = {
        var table: [String: SystemSymbol] = [:]
        for symbol in all {
            table[symbol.name] = symbol
            table[symbol.sfSymbol] = symbol
        }
        return table
    }()

    /// A name that is not in the table, carried so it can be drawn as itself.
    ///
    /// Every platform field is empty, which is the same state a backend already
    /// has to handle: it asks its platform for the icon, the platform says no,
    /// and it draws ``textFallback`` -- here, the name that was asked for. So an
    /// unrecognised name needs no separate path through any backend, and it
    /// looks the same on all of them.
    ///
    /// 一個不在表中的名稱，被包起來以便將它自身畫出來。
    ///
    /// 其每一個平台欄位都是空的，而那正是 backend 本來就必須處理的狀態：它向自己的平台索取圖示、
    /// 平台回答沒有，於是它畫出 ``textFallback``——在此即為當初被索取的那個名稱。因此一個無法辨識的
    /// 名稱不需要在任何 backend 中另闢路徑，而且它在所有 backend 上看起來都一樣。
    public static func unresolved(_ name: String) -> SystemSymbol {
        SystemSymbol(
            name: name,
            sfSymbol: "",
            gtkIconName: "",
            segoeScalar: 0,
            androidDrawable: "",
            textFallback: name
        )
    }
}
