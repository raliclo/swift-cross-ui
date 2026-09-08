extension View {
    /// Sets the style for buttons within this view to one of the built-in
    /// appearances.
    ///
    /// This is the overload upstream's #590 shipped, with its parameter renamed
    /// from `ButtonStyle` to ``PrimitiveButtonStyle``; `.buttonStyle(.bordered)`
    /// and `.buttonStyle(nil)` are unchanged at the call site.
    ///
    /// **How this coexists with the generic overload below.** Neither call is
    /// ambiguous, because the two parameter types share no values.
    /// `.bordered` resolves only against ``PrimitiveButtonStyle``, which is where
    /// the static member lives; ``ButtonStyle`` has no `.bordered`, so the
    /// generic overload cannot bind `S` and drops out. A conforming type has the
    /// opposite problem with this overload. And `nil` reaches only this one,
    /// since `S` cannot be inferred from it. SwiftUI splits the same pair the
    /// same way, except that its first half is generic over
    /// `PrimitiveButtonStyle` the *protocol*; here that half is a closed set of
    /// three, so it takes the value directly.
    ///
    /// 將此 view 之內按鈕的樣式，設為其中一種內建外觀。
    ///
    /// 這是 upstream #590 所提供的那一版，只是把參數型別由 `ButtonStyle` 更名為
    /// ``PrimitiveButtonStyle``；在呼叫端，`.buttonStyle(.bordered)` 與 `.buttonStyle(nil)` 完全不變。
    ///
    /// **它如何與下方的泛型版本共存。** 兩種呼叫都不會有歧義，因為這兩個參數型別沒有共通的值。
    /// `.bordered` 只解析得到 ``PrimitiveButtonStyle``（靜態成員在那裡）；``ButtonStyle`` 沒有
    /// `.bordered`，因此泛型版本無法推導出 `S`，自然出局。而一個 conformer 對本版本則是相反的處境。
    /// 至於 `nil`，只有本版本收得到，因為由它推導不出 `S`。SwiftUI 對這一組拆法相同，差別只在於它的
    /// 前半是泛型於 `PrimitiveButtonStyle` 這個 **protocol**；在此處那一半是一個三元的封閉集合，
    /// 因此直接接受值本身。
    public func buttonStyle(_ style: PrimitiveButtonStyle?) -> some View {
        EnvironmentModifier(self) { environment in
            environment.with(\.buttonStyle, style)
        }
    }

    /// Sets the style for buttons within this view to a style that draws itself.
    ///
    /// The style is stored type-erased, in
    /// ``EnvironmentValues/customButtonStyle``, as `(any ButtonStyle)?`.
    /// ``EnvironmentValues`` is not generic and cannot become generic over every
    /// style an application might write, so a concrete `S` has to lose its type
    /// somewhere; storing `any ButtonStyle` erases it once, at the point the
    /// modifier is applied, rather than at every read. ``LabelStyle`` is stored
    /// the same way (`any LabelStyle`), and ``Label`` calls `makeBody` straight
    /// off the existential -- the associated `Body` comes back as `any View`,
    /// which is exactly what ``Button`` needs to hand to ``AnyView``.
    ///
    /// Propagated through the environment, so the innermost `.buttonStyle(_:)`
    /// wins, as with every other style modifier here.
    ///
    /// The two entries are separate rather than one enum with two cases: they
    /// answer different questions. ``EnvironmentValues/buttonStyle`` is read by
    /// every backend on every button update, and a custom style has no answer
    /// for it -- so ``Button`` supplies `.plain` instead, which is what makes the
    /// platform stop drawing its own chrome underneath a style that draws its
    /// own.
    ///
    /// 將此 view 之內按鈕的樣式，設為一個自行繪製的樣式。
    ///
    /// 該樣式以型別抹除的形式存放於 ``EnvironmentValues/customButtonStyle``，型別為
    /// `(any ButtonStyle)?`。``EnvironmentValues`` 並非泛型，也不可能泛型於應用程式可能寫出的每一種
    /// 樣式，因此具體的 `S` 必須在某處失去其型別；存成 `any ButtonStyle` 是在「套用 modifier」這一點
    /// 抹除一次，而不是在每次讀取時抹除。``LabelStyle`` 採用相同做法（`any LabelStyle`），而 ``Label``
    /// 直接在該 existential 上呼叫 `makeBody`——關聯型別 `Body` 會以 `any View` 回來，而那正是
    /// ``Button`` 要交給 ``AnyView`` 的東西。
    ///
    /// 透過 environment 傳遞，因此最內層的 `.buttonStyle(_:)` 勝出，與此處其他樣式 modifier 一致。
    ///
    /// 兩個 entry 是分開的，而不是一個帶兩個 case 的 enum：它們回答的是不同的問題。
    /// ``EnvironmentValues/buttonStyle`` 是每個 backend 在每次更新按鈕時都會讀的，而自訂樣式對它沒有
    /// 答案——因此 ``Button`` 改為提供 `.plain`，這正是讓平台停止在「自行繪製的樣式」底下畫出自身
    /// 外框的原因。
    ///
    /// ## See Also
    ///
    /// - ``ButtonStyle``
    /// - ``ButtonStyleConfiguration``
    public func buttonStyle<S: ButtonStyle>(_ style: S) -> some View {
        EnvironmentModifier(self) { environment in
            environment.with(\.customButtonStyle, style as any ButtonStyle)
        }
    }
}
