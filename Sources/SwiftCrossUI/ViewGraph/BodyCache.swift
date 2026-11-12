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

/// The body a node's `children` evaluated, handed to the same node's `asWidget`.
///
/// **Not the environment, because `asWidget` takes none.** A node is created by
/// calling `view.children(...)` and then `view.asWidget(...)`; the default
/// implementations of both evaluated `body`, so every node built its view's body
/// twice before laying anything out (Swift-Cross-UI-M4's AppKit trace of P2,
/// 2026-11-12: `defaultChildren`, then `defaultAsWidget`, both from
/// `ViewGraphNode.init`). The node sets this around its `asWidget` call and the
/// default implementation takes it once; an owner of another type ignores it.
///
/// 節點的 `children` 求值出的 body,交給同一個節點的 `asWidget`。
///
/// **不經由 environment,因為 `asWidget` 不接受 environment。** 建立節點時先呼叫 `view.children(...)` 再呼叫
/// `view.asWidget(...)`;兩者的預設實作都會求值 `body`,所以每個節點在排版之前就把它 view 的 body 建了兩次
/// (Swift-Cross-UI-M4 於 2026-11-12 追蹤 AppKit 上的 P2:`defaultChildren` 接著 `defaultAsWidget`,都來自
/// `ViewGraphNode.init`)。節點在呼叫 `asWidget` 前後設定它，預設實作只取用一次；型別不同的擁有者不會理它。
@MainActor
enum BodyHandoff {
    private static var pending: CachedBody?

    /// Runs `create` with `body` offered to the default `asWidget` of `owner`.
    static func offering<Result>(
        _ body: Any?,
        to owner: ObjectIdentifier,
        _ create: () -> Result
    ) -> Result {
        let previous = pending
        pending = body.map { CachedBody(owner: owner, body: $0) }
        defer { pending = previous }
        return create()
    }

    /// The offered body if it is for `View`, removed so nothing below reuses it.
    static func take<V: View>(for _: V.Type) -> V.Content? {
        guard let offered = pending, offered.owner == ObjectIdentifier(V.self),
            let body = offered.body as? V.Content
        else { return nil }
        pending = nil
        return body
    }
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
