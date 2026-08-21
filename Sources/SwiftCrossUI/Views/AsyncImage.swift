import Foundation
import ImageFormats

/// The current state of an ``AsyncImage`` load.
///
/// Top-level and non-generic, as in SwiftUI: it says nothing about what the
/// view is built from, so putting it inside the generic would have forced every
/// caller to spell out `AsyncImage<TupleView1<Image>, Text>.Phase` -- a type
/// nobody writes on purpose, and one that changes if a closure gains a view.
///
/// `failure` carries the error rather than collapsing to "no image", so a
/// caller can tell "not finished" from "will never finish". A spinner that
/// never stops is the usual result of losing that distinction.
///
/// ``AsyncImage`` 載入的目前狀態。
///
/// 如同 SwiftUI，此型別置於頂層且不帶泛型：它並不描述該 view 由什麼組成，若放進泛型內部，會迫使
/// 每個呼叫端寫出 `AsyncImage<TupleView1<Image>, Text>.Phase`——那是沒有人會刻意寫的型別，而且只要
/// 某個 closure 多了一個 view，它就會改變。
///
/// `failure` 攜帶錯誤而非退化為「沒有影像」，如此呼叫端才能區分「尚未完成」與「永遠不會完成」。
/// 失去這項區別，通常的結果就是一個永遠停不下來的轉圈動畫。
public enum AsyncImagePhase {
    case empty
    case success(Image)
    case failure(any Error)

    /// The loaded image, or `nil` while loading or after a failure.
    public var image: Image? {
        if case .success(let image) = self { return image }
        return nil
    }

    /// The error, or `nil` unless the load failed.
    public var error: (any Error)? {
        if case .failure(let error) = self { return error }
        return nil
    }
}

/// Loads and displays an image from a URL, without blocking the interface.
///
/// The counterpart to ``Image``, which reads a file synchronously while the
/// layout is being computed. That is fine for a file and wrong for a network
/// resource: a slow server would stall the whole interface, with no way to
/// cancel it and nothing to show in the meantime.
///
/// Built from ``View/task(id:priority:_:)`` and `@State` rather than from a
/// backend method. There is no widget here a toolkit could provide -- the work
/// is a fetch and a decode, and both are the same on every platform, so every
/// backend gets this at once.
///
/// Fetching goes through ``AppCache``, so a URL already on disk and confirmed
/// current with the server is not downloaded again. With no `appCache`
/// directory beside the executable the cache is off and this is a plain fetch.
///
/// 從 URL 載入並顯示影像，且不阻塞介面。
///
/// 它是 ``Image`` 的對應物——後者在計算版面時同步讀取檔案。對檔案而言這沒問題，對網路資源則是錯的：
/// 緩慢的伺服器會使整個介面停頓，既無法取消，期間也沒有任何東西可顯示。
///
/// 以 ``View/task(id:priority:_:)`` 與 `@State` 組成，而非透過 backend 方法。此處沒有任何 toolkit
/// 能提供的 widget——所做的事就是抓取與解碼，兩者在每個平台上都相同，因此所有 backend 一次獲得。
///
/// 抓取經由 ``AppCache``，因此已在磁碟上且經伺服器確認為最新的 URL 不會被重複下載。若執行檔旁沒有
/// `appCache` 目錄，快取即為關閉，此處便是一次單純的抓取。
public struct AsyncImage<Content: View>: View {
    var url: URL?
    var content: (AsyncImagePhase) -> Content

    @State private var phase = AsyncImagePhase.empty

    /// Creates an image that loads from `url`, handing every state to
    /// `content`.
    ///
    /// - Parameters:
    ///   - url: The URL to load from. A `nil` URL never loads, matching
    ///     SwiftUI, so a value that is not ready yet needs no branch at the
    ///     call site.
    ///   - content: Builds the view for the current phase.
    public init(
        url: URL?,
        @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
    ) {
        self.url = url
        self.content = content
    }

    public var body: some View {
        content(phase)
            // Keyed on the URL so a changed URL cancels the load in flight and
            // starts the new one. Without the key the first URL would win and
            // the view would show the wrong image for the rest of its life.
            // 以 URL 作為 key，因此 URL 變更時會取消進行中的載入並開啟新的載入。若無此 key，第一個
            // URL 將勝出，該 view 在其餘生中都會顯示錯誤的影像。
            .task(id: url) {
                guard let url else { return }
                phase = .empty
                do {
                    let data = try await AppCache.shared.data(for: url)
                    phase = .success(
                        Image(try ImageFormats.Image<RGBA>.load(from: Array(data)))
                    )
                } catch {
                    phase = .failure(error)
                }
            }
    }
}

extension AsyncImage {
    /// Creates an image that loads from `url`, showing `placeholder` until it
    /// arrives.
    ///
    /// The placeholder takes no argument, as in SwiftUI. Use
    /// ``init(url:content:)`` when the failure needs to look different from the
    /// wait.
    ///
    /// 從 `url` 載入影像，在其抵達之前顯示 `placeholder`。
    ///
    /// 如同 SwiftUI，placeholder 不帶參數。若「失敗」需要與「等待」呈現不同外觀，請改用
    /// ``init(url:content:)``。
    /// The generic is spelled from the outside in, because a `ViewBuilder`
    /// wraps at every level: the `if`/`else` becomes an `EitherView` of the two
    /// branches, each branch is itself wrapped, and the whole closure result is
    /// wrapped once more. Writing `EitherView<I, P>` -- the shape one would
    /// expect -- does not compile, and the error names the real type, which is
    /// how this was arrived at rather than guessed.
    ///
    /// 此泛型由外而內逐層寫出，因為 `ViewBuilder` 在每一層都會包裝：`if`/`else` 成為兩個分支的
    /// `EitherView`，每個分支自身再被包裝一次，而整個 closure 的結果又被包裝一次。寫成一般人會
    /// 預期的 `EitherView<I, P>` 無法通過編譯，而編譯錯誤會直接指出真正的型別——此處的寫法即由此
    /// 得來，而非猜測。
    public init<I: View, P: View>(
        url: URL?,
        @ViewBuilder content imageContent: @escaping (Image) -> I,
        @ViewBuilder placeholder: @escaping () -> P
    ) where Content == TupleView1<EitherView<TupleView1<I>, TupleView1<P>>> {
        self.init(url: url) { phase in
            if let image = phase.image {
                imageContent(image)
            } else {
                placeholder()
            }
        }
    }
}
