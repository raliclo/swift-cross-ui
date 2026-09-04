extension View {
    /// Presents a set of choices for an action the user is about to take.
    ///
    /// Built on the existing ``BackendFeatures/Alerts`` protocol, which already
    /// supplies exactly what a confirmation dialog needs: a title, a list of
    /// button labels, and the index of the one chosen. **No backend gains a new
    /// requirement from this modifier**, so it works on all five the moment it
    /// compiles -- the same property that decided the order of the parity views
    /// added alongside it. See ``Stepper``.
    ///
    /// Two things differ from ``View/alert(_:isPresented:actions:)``, and both
    /// are real rather than cosmetic:
    ///
    /// - **A Cancel action is added** unless the caller already supplied one.
    ///   SwiftUI does the same, and for a good reason: a dialog asking whether
    ///   to delete something must have a way out that is not "delete".
    /// - **`titleVisibility` is honoured** by passing an empty title through to
    ///   the backend, not by ignoring the parameter. `.automatic` shows the
    ///   title, matching SwiftUI on macOS, where a titled dialog is the norm.
    ///
    /// **What this is not:** an iOS-style action sheet sliding up from the
    /// bottom edge. Each backend renders it as its own modal question dialog,
    /// which is the desktop-native form of the same thing. If a genuine action
    /// sheet is ever wanted, it needs a backend protocol of its own.
    ///
    /// 呈現一組選項，供使用者決定即將採取的動作。
    ///
    /// 建構於既有的 ``BackendFeatures/Alerts`` protocol 之上，而該 protocol 恰好已提供確認對話框
    /// 所需的一切：一個標題、一串按鈕標籤，以及被選中者的索引。**沒有任何 backend 因這個 modifier
    /// 而多出新的要求**，因此它一旦編譯通過就在五個 backend 上同時成立——這正是與它一同新增的那批
    /// parity view 之所以被排在前面的性質。見 ``Stepper``。
    ///
    /// 它與 ``View/alert(_:isPresented:actions:)`` 有兩點不同，且兩點都是實質差異而非外觀差異：
    ///
    /// - **會補上一個 Cancel 動作**，除非呼叫端已自行提供。SwiftUI 也這麼做，且理由充分：一個
    ///   詢問「是否要刪除」的對話框，必須有一條不是「刪除」的退路。
    /// - **`titleVisibility` 確實被遵守**——做法是把空標題傳給 backend，而不是忽略該參數。
    ///   `.automatic` 會顯示標題，對應 macOS 上的 SwiftUI 行為，在該平台上帶標題的對話框才是常態。
    ///
    /// **它不是**由底部滑上來的 iOS 式 action sheet。各 backend 會以自己的模態提問對話框呈現它，
    /// 那是同一件事在桌面上的原生形式。若日後真的需要 action sheet，那需要屬於它自己的 backend
    /// protocol。
    ///
    /// - Parameters:
    ///   - title: The question being asked.
    ///   - isPresented: A binding controlling whether the dialog is presented.
    ///   - titleVisibility: Whether to show `title`. `.hidden` passes an empty
    ///     title to the backend.
    ///   - actions: The choices offered.
    public func confirmationDialog(
        _ title: String,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility = .automatic,
        @AlertActionsBuilder actions: () -> [AlertAction]
    ) -> some View {
        let shownTitle: String
        if case .hidden = titleVisibility {
            shownTitle = ""
        } else {
            shownTitle = title
        }

        return AlertModifierView(
            child: self,
            title: shownTitle,
            isPresented: isPresented,
            actions: ConfirmationDialogCancel.appendingCancel(to: actions())
        )
    }
}

/// Adds the implicit Cancel action, and knows when not to.
///
/// Split out rather than inlined so the "already has one" test has a name and a
/// single home. Adding a second Cancel is not a cosmetic fault -- the backend
/// reports a chosen action by INDEX, so two buttons with the same label are two
/// different outcomes that read identically to the user.
///
/// 負責補上隱含的 Cancel 動作，並知道何時不該補。
///
/// 拆出來而非內聯，是為了讓「已經有一個了」這項判斷有名字、也只有一處。多加一個 Cancel 不是外觀
/// 上的瑕疵——backend 是以**索引**回報被選中的動作，因此兩顆標籤相同的按鈕代表兩個不同的結果，
/// 而在使用者眼中它們一模一樣。
enum ConfirmationDialogCancel {
    /// Labels treated as an existing way out.
    ///
    /// Compared case-insensitively, because a caller writing `Button("cancel")`
    /// means the same thing as `Button("Cancel")`. Not localised, which is a
    /// real limit: a dialog whose only escape is labelled `取消` still gets a
    /// second, English Cancel appended. That is deliberate over the
    /// alternative -- guessing that the last action is the escape hatch would
    /// silently swallow a genuine third choice.
    ///
    /// 被視為「已有退路」的標籤。
    ///
    /// 比對時忽略大小寫，因為寫 `Button("cancel")` 的呼叫端與寫 `Button("Cancel")` 的呼叫端
    /// 意思相同。此處不做在地化，而那是一項實在的限制：一個唯一退路標為「取消」的對話框，仍會被
    /// 補上第二顆英文的 Cancel。這是刻意選擇，優於另一種做法——若改為猜測「最後一個動作就是退路」，
    /// 會靜默吞掉一個真正的第三選項。
    static let recognisedLabels = ["cancel", "no", "dismiss", "close"]

    static func appendingCancel(to actions: [AlertAction]) -> [AlertAction] {
        let hasCancel = actions.contains { action in
            recognisedLabels.contains(action.label.lowercased())
        }
        guard !hasCancel else { return actions }
        return actions + [AlertAction(label: "Cancel", action: {})]
    }
}
