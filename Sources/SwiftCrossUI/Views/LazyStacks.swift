/// A vertical stack for use inside a `ScrollView`.
///
/// **It is not lazy yet, and the name is the only place that says otherwise.**
/// Read this before using it in place of ``VStack``:
///
/// - **What is the same as SwiftUI:** the layout. `LazyVStack` and `VStack`
///   arrange children identically once every child exists, so any picture this
///   draws is the picture SwiftUI draws.
/// - **What differs:** SwiftUI creates a child only as it approaches the
///   viewport. This creates all of them up front. For a thousand rows that is a
///   thousand backend widgets instead of a screenful, and every child's
///   `onAppear` fires at once rather than on scroll. Code that hangs a network
///   request off `onAppear` therefore issues all of them immediately.
/// - **Why it exists anyway:** SwiftUI source that says `LazyVStack` should
///   compile and should look right, which is parity task #34. An eager stack is
///   the correct picture and the wrong performance; refusing to compile is
///   neither.
///
/// Real laziness needs the container to know which children are near the
/// viewport, which means `ScrollView` reporting its scroll offset and visible
/// rect back into the layout pass. That is a change to the layout system, not to
/// this file, and it is tracked separately.
///
/// 一個供 `ScrollView` 內部使用的垂直堆疊。
///
/// **它目前並不惰性，而全專案只有它的名字暗示相反的事。** 在拿它取代 ``VStack`` 之前請先讀這段：
///
/// - **與 SwiftUI 相同之處：** 版面。一旦所有子項都存在，`LazyVStack` 與 `VStack` 的排列方式
///   完全相同，因此它畫出來的畫面就是 SwiftUI 畫出來的畫面。
/// - **相異之處：** SwiftUI 只在子項接近可視區時才建立它。此處則一次全部建立。一千列就是一千個
///   backend widget，而非一個畫面的量；而且每個子項的 `onAppear` 會同時觸發，而不是隨捲動觸發。
///   把網路請求掛在 `onAppear` 上的程式碼，因此會一口氣全部送出。
/// - **為何仍然提供：** 寫著 `LazyVStack` 的 SwiftUI 原始碼應該編得過、也應該看起來正確，那正是
///   parity 任務 #34。一個積極求值的堆疊是「畫面正確、效能不對」；拒絕編譯則兩者皆非。
///
/// 真正的惰性需要容器知道哪些子項接近可視區，也就是要由 `ScrollView` 把捲動位移與可視矩形回報進
/// 版面計算流程。那是對版面系統的改動，而不是對這個檔案的改動，並另行追蹤。
public struct LazyVStack<Content: View>: View {
    private let content: Content
    private let alignment: HorizontalAlignment
    private let spacing: Int?

    public init(
        alignment: HorizontalAlignment = .center,
        spacing: Int? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: alignment, spacing: spacing) {
            content
        }
    }
}

/// A horizontal stack for use inside a `ScrollView`.
///
/// The horizontal counterpart of ``LazyVStack``, and not lazy for the same
/// reason. Read that type's note; every word of it applies here with the axes
/// swapped.
///
/// 一個供 `ScrollView` 內部使用的水平堆疊。
///
/// ``LazyVStack`` 的水平對應版本，且基於同樣的理由同樣不是惰性的。請讀該型別的說明；其中每一句
/// 在此都成立，只是把軸向對調。
public struct LazyHStack<Content: View>: View {
    private let content: Content
    private let alignment: VerticalAlignment
    private let spacing: Int?

    public init(
        alignment: VerticalAlignment = .center,
        spacing: Int? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        HStack(alignment: alignment, spacing: spacing) {
            content
        }
    }
}
