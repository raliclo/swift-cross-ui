extension BackendFeatures {
    /// Backend methods for choosing which graphics adapter renders.
    ///
    /// The rules live in ``GraphicsAdapterSelection`` and are shared: the
    /// numbering, the fallback to the system default and then to software, and
    /// what to report. A backend supplies only the two things that genuinely
    /// differ — which adapters exist, and how to select one.
    ///
    /// A backend that cannot select an adapter should still conform, return the
    /// adapters it can see and answer ``applyAdapter(_:)`` with
    /// ``AdapterOutcome/unavailable(reason:)``. Declining to conform is not a
    /// graceful degradation: ``CastBackend`` turns a missing conformance into
    /// `fatalError`, so an application that passed `-GPU 2` would abort rather
    /// than run on the adapter it already had.
    ///
    /// 用於選擇「由哪張繪圖介面卡負責繪製」的 backend 方法。
    ///
    /// 規則本身位於 ``GraphicsAdapterSelection`` 且為共用：編號方式、「先退回系統預設、再退回軟體」
    /// 的退路，以及該回報什麼。backend 只提供真正因平台而異的兩件事——有哪些介面卡，以及如何選定
    /// 其中一張。
    ///
    /// 無法選擇介面卡的 backend 仍應宣告 conformance，回傳它看得到的介面卡，並以
    /// ``AdapterOutcome/unavailable(reason:)`` 回應 ``applyAdapter(_:)``。此處「不宣告
    /// conformance」並非優雅降級：``CastBackend`` 會把缺少的 conformance 轉為 `fatalError`，
    /// 因此傳了 `-GPU 2` 的應用程式會直接中止，而不是繼續使用它原本就拿到的那張卡。
    @MainActor
    public protocol GraphicsAdapters: Core {
        /// Every adapter the platform reports, in the platform's own order.
        ///
        /// The order matters: ``GraphicsAdapterSelection/systemDefault`` takes
        /// the first, so a backend should return them in the order the platform
        /// would itself prefer.
        ///
        /// 平台所回報的每一張介面卡，依平台自身的順序。
        ///
        /// 順序是有意義的：``GraphicsAdapterSelection/systemDefault`` 取的是第一張，因此 backend
        /// 應以「平台自己會偏好的順序」回傳它們。
        var availableAdapters: [GraphicsAdapter] { get }

        /// Selects an adapter, or explains why it could not.
        ///
        /// Called once, before anything renders. It is allowed not to return:
        /// on Windows the adapter is fixed when the process is created, so
        /// honouring a request there means restarting.
        ///
        /// 選定一張介面卡，或說明為何辦不到。
        ///
        /// 在任何繪製發生之前呼叫一次。它**允許不返回**：在 Windows 上，介面卡是在行程建立時就
        /// 被固定的，因此在該平台遵從一項要求即意味著重新啟動。
        func applyAdapter(_ resolution: GraphicsAdapterResolution) -> AdapterOutcome

        /// Called when the adapter in use disappears.
        ///
        /// The one thing an external GPU adds that nothing else does — it can be
        /// unplugged mid-run. Every desktop platform has this and each signals
        /// it differently, which is why it is here rather than in one backend.
        ///
        /// This is also the reason the protocol exists now rather than later:
        /// selection can be retrofitted, but a renderer written to assume a
        /// permanent device has to be rewritten rather than extended.
        ///
        /// 當使用中的介面卡消失時呼叫。
        ///
        /// 這是外接 GPU 獨有、其他情況都沒有的一件事——它可能在執行途中被拔除。每個桌面平台都有
        /// 這個現象，而各自的訊號都不同，這正是它該放在此處而非某一個 backend 裡的原因。
        ///
        /// 這也是「協定現在就該存在、而非以後再說」的理由：選擇機制可以事後補上，但一個假設裝置
        /// 永久存在的 renderer，只能重寫，不能擴充。
        var adapterRemoved: (() -> Void)? { get set }
    }

    /// What a backend did with an adapter request.
    /// backend 對某項介面卡要求所採取的行動。
    public enum AdapterOutcome: Sendable {
        /// In use now; nothing further is needed.
        /// 現已生效，無須其他動作。
        case applied

        /// Already what was in use, so nothing was changed.
        /// 原本就是使用中的那一張，因此未做任何變更。
        case alreadyActive

        /// The platform can only honour this from a fresh process.
        ///
        /// Windows fixes an OpenGL process's adapter when the process is
        /// created, so the value is written and the application has to start
        /// again. macOS does not need this — Metal chooses at runtime — which
        /// is why the difference is expressed here rather than assumed away.
        ///
        /// 該平台只能在「全新的行程」中遵從此項要求。
        ///
        /// Windows 是在行程建立時固定 OpenGL 行程的介面卡，因此該值會被寫入，而應用程式必須重新
        /// 啟動。macOS 不需要這樣——Metal 是在執行期選擇的——這正是此差異必須在此處被明確表達、
        /// 而非被當作不存在的原因。
        case needsRestart(reason: String)

        /// Not possible here, with a reason worth printing.
        /// 在此處無法辦到，並附上值得輸出的原因。
        case unavailable(reason: String)
    }
}
