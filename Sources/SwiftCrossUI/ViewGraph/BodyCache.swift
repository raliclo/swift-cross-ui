import Foundation

/// A slot a node hands its own view's default layout, which records the body it
/// evaluated there.
///
/// **Owned by one view type, and that is what keeps it from being misused.** The
/// environment is inherited, so a view that does not use the default layout (a
/// `VStack`, a `Text`) passes it on unconsumed. A descendant of a different type
/// then sees an owner that is not itself and leaves the slot alone. The default
/// implementations also clear it before going below the view it was meant for.
///
/// 節點交給它自己的 view 的預設排版的一個欄位,由預設排版記下它在那裡求值的 body。
///
/// **只屬於一個 view 型別,而那正是它不會被誤用的原因。**environment 會被繼承,所以不使用預設排版的 view
/// (`VStack`、`Text`)會把它原封不動往下傳;型別不同的後代看到擁有者不是自己,就不會碰它。預設實作在往它所屬的
/// view 之下傳之前,也會清掉它。
final class BodyCapture {
    let owner: ObjectIdentifier
    var body: Any?

    init(owner: ObjectIdentifier) {
        self.owner = owner
    }
}

/// A body a node kept from its last full update, for its own view type.
/// 節點從它上一次完整更新所保存的 body,只給它自己的 view 型別使用。
struct CachedBody {
    let owner: ObjectIdentifier
    let body: Any
}

extension View {
    /// The body to lay out or commit: the one the node kept, when the environment
    /// carries it for this view type; otherwise `body`, evaluated and recorded for
    /// the node.
    ///
    /// 要排版或 commit 的 body:environment 帶著、且屬於這個 view 型別時,用節點保存的那一個;否則求值 `body`,
    /// 並為節點記下它。
    func resolvedBody(_ environment: EnvironmentValues) -> Content {
        let me = ObjectIdentifier(Self.self)
        if let cached = environment.cachedBody, cached.owner == me,
            let body = cached.body as? Content
        {
            return body
        }
        let body = self.body
        if let capture = environment.bodyCapture, capture.owner == me {
            capture.body = body
        }
        return body
    }
}
