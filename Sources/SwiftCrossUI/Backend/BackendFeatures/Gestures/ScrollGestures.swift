/// What a scroll reports.
///
/// **The sign is defined here, once, because it is the field every platform
/// disagrees about.** `delta.y` is positive when the user asked to move
/// FORWARD through the content -- down a page, further into a list -- which is
/// the direction a scroll view's offset increases. `delta.x` is positive
/// moving right through the content. A backend whose platform reports the
/// opposite sign flips it; a backend whose platform has a "natural scrolling"
/// preference honours that preference before it gets here, because the user set
/// it for the whole machine and an application second-guessing it is an
/// application that feels broken.
///
/// **No momentum flag, for the reason ``DragGestureValue`` gives about
/// velocity.** macOS delivers momentum events after the fingers lift, Android
/// delivers a fling through a different callback entirely, GTK has kinetic
/// scrolling as a property of the scrolled window rather than of the event, and
/// a plain wheel has no momentum at all. A field that means four things is
/// worse than one that is absent. Momentum events, where a platform delivers
/// them, arrive as ordinary changes -- so a caller must not use these to decide
/// how hard a flick was.
///
/// 一次捲動所回報的東西。
///
/// **正負號在此一次定義清楚,因為那正是每個平台各說各話的那個欄位。** `delta.y` 為正,表示使用者要求
/// **往內容的前方移動**——往下一頁、往清單更深處——也就是一個 scroll view 的 offset 增加的方向。
/// `delta.x` 為正表示往內容的右方移動。平台回報相反符號的 backend 要自行翻轉;平台帶有「自然捲動」
/// 偏好設定的 backend,要在送到這裡之前就遵守該偏好——因為那是使用者為**整台機器**設定的,而一個去
/// 猜疑它的應用程式,用起來就是壞的。
///
/// **沒有 momentum 旗標,理由與 ``DragGestureValue`` 對速度所說的相同。** macOS 會在手指離開後送出
/// momentum 事件;Android 的 fling 走的是完全不同的 callback;GTK 的動能捲動是 scrolled window 的屬性、
/// 不是事件的屬性;而一個單純的滾輪根本沒有動能。一個意思有四種的欄位,比一個不存在的欄位更糟。
/// 在有送 momentum 的平台上,那些事件會以一般的變更送達——因此呼叫端**不可以**用這些來判斷一次甩動有多用力。
public struct ScrollGestureValue: Equatable, Sendable {
    /// How far to move since the previous event, in points.
    /// 相對於上一個事件要移動多少,單位為點。
    public var delta: SIMD2<Double>

    /// The sum of every `delta` since this scroll began.
    ///
    /// Accumulated by the backend rather than by the caller, for the reason
    /// ``MagnifyGestureValue`` records: a wheel notch and a trackpad glide are
    /// different units on every platform, and only the backend knows which it
    /// just received.
    ///
    /// 自這次捲動開始以來每一個 `delta` 的總和。
    ///
    /// 由 backend 而非呼叫端累計,理由 ``MagnifyGestureValue`` 已經記過:一格滾輪與一次觸控板滑移,
    /// 在每個平台上都是不同的單位,而只有 backend 知道它剛剛收到的是哪一種。
    public var translation: SIMD2<Double>

    /// `true` for a trackpad or a touch surface, `false` for a notched wheel.
    ///
    /// **Not cosmetic: the two need different code.** A precise device sends
    /// many small deltas and a caller can apply them directly. A wheel sends
    /// one large delta per notch, and a caller that applies it directly makes
    /// a view that jumps. The flag is the only way to tell them apart, because
    /// the magnitude alone cannot -- a slow trackpad glide and a wheel notch
    /// can be the same number of points.
    ///
    /// 觸控板或觸控表面為 `true`,有段落感的滾輪為 `false`。
    ///
    /// **這不是裝飾性的:兩者需要不同的處理。** 精密裝置會送出許多個小差量,呼叫端可以直接套用。
    /// 滾輪則是每一格送一個大的差量,而直接套用它的呼叫端,做出來的 view 會**跳**。這個旗標是唯一
    /// 分辨得出兩者的方式——因為光看大小是分不出來的:一次緩慢的觸控板滑移與一格滾輪,可以是同樣的點數。
    public var isPrecise: Bool

    public init(delta: SIMD2<Double>, translation: SIMD2<Double>, isPrecise: Bool) {
        self.delta = delta
        self.translation = translation
        self.isPrecise = isPrecise
    }
}

extension BackendFeatures {
    /// A scroll wheel, a trackpad two-finger scroll, or a touch surface's
    /// equivalent, delivered to a view rather than to a scroll container.
    ///
    /// **``ScrollContainers`` is not this, and the difference is who decides
    /// what moves.** A scroll container is handed content and moves it itself;
    /// the application never sees an event. This hands the event over and moves
    /// nothing, which is what a view that draws its own content needs -- a
    /// canvas that zooms, a board that pans, a timeline that scrubs. SoftPCB's
    /// `plan.md` §10.7 lists it as gap 2 and says so plainly: *no scroll API.
    /// `NSDisabledScrollView.scrollWheel` is a workaround for NSTableView
    /// widths and unrelated to this.*
    ///
    /// **Conformance-checked, not `@CastBackend`.** The other continuous
    /// gestures use the macro, which expands to `fatalError`, and they can
    /// because every shipped backend implements them. This one lands on AppKit
    /// and UIKit first, so three backends would meet that `fatalError` on the
    /// day it arrived -- the cost `CLAUDE.md` records from 2026-09-02. A view
    /// with no conformance renders its content and reports no scrolls, and says
    /// so once. That is a schedule, not a policy: the five shipped backends owe
    /// this.
    ///
    /// 一個滾輪、一次觸控板兩指捲動,或觸控表面的對應動作——送到一個 **view**,而不是送到一個捲動容器。
    ///
    /// **``ScrollContainers`` 不是這個,差別在於「由誰決定什麼會動」。** 一個捲動容器收下內容、自己去
    /// 移動它,應用程式從頭到尾看不到任何事件。這個則是把事件交出去、自己什麼都不移動——而那正是一個
    /// 「自己畫自己內容」的 view 所需要的:一塊會縮放的畫布、一張會平移的板子、一條會刷動的時間軸。
    /// SoftPCB 的 `plan.md` §10.7 把它列為第 2 項缺口,並寫得很清楚:*無捲動 API。
    /// `NSDisabledScrollView.scrollWheel` 只是 NSTableView 寬度的變通,與此無關。*
    ///
    /// **採 conformance 檢查,而不是 `@CastBackend`。** 其他幾個連續手勢用的是那個 macro(它展開為
    /// `fatalError`),而它們可以那樣做,是因為每個已發布的 backend 都實作了它們。這一個先落在 AppKit 與
    /// UIKit,因此落地當天會有三個 backend 撞上那個 `fatalError`——那正是 `CLAUDE.md` 記載的 2026-09-02
    /// 的代價。沒有 conformance 的情況下,那個 view 會照常繪製它的內容、不回報任何捲動,並且說一次。
    /// 那是一份時程,不是一項政策:五個已發布的 backend 都欠這一項。
    @MainActor
    public protocol ScrollGestures: Core {
        func createScrollGestureTarget(wrapping child: Widget) -> Widget

        func updateScrollGestureTarget(
            _ target: Widget,
            environment: EnvironmentValues,
            onChange: @escaping (ScrollGestureValue) -> Void,
            onEnd: @escaping (ScrollGestureValue) -> Void
        )
    }
}
