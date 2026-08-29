/// A graphics adapter a backend can render with.
///
/// Deliberately a small, comparable description rather than a handle: the
/// resolution rules below are shared by every platform, and they only need to
/// tell adapters apart, not to draw with them.
///
/// 某個 backend 可用來繪製的繪圖介面卡。
///
/// 刻意設計成「小而可比較的描述」而非「控制代碼」：下方的解析規則為所有平台共用，而它們只需要
/// 分辨介面卡，並不需要用它來繪圖。
public struct GraphicsAdapter: Sendable, Hashable {
    /// What the platform calls it, for reporting.
    /// 平台對它的稱呼，用於輸出報告。
    public var name: String

    /// Whether it can be unplugged while the application runs.
    ///
    /// The one property an external GPU has that nothing else does, and the
    /// reason ``BackendFeatures/GraphicsAdapters/adapterRemoved`` exists.
    ///
    /// 它是否可能在應用程式執行期間被拔除。
    ///
    /// 這是外接 GPU 獨有、其他情況都沒有的性質，也正是
    /// ``BackendFeatures/GraphicsAdapters/adapterRemoved`` 存在的理由。
    public var isRemovable: Bool

    /// Whether the platform considers it the power-saving choice.
    /// 平台是否將它視為省電的選擇。
    public var isLowPower: Bool

    public init(name: String, isRemovable: Bool = false, isLowPower: Bool = false) {
        self.name = name
        self.isRemovable = isRemovable
        self.isLowPower = isLowPower
    }
}

/// Which adapter an application is asking for, as the number `-GPU N` carries.
///
/// `0` and `1` are policies; `2` and above are an ordinal **within the external
/// adapters**, not an index into a raw device list. That distinction is the
/// whole design. A raw index renumbers whenever hardware is plugged in or a
/// display wakes, so `-GPU 2` would quietly mean a different card tomorrow with
/// nothing to notice; an ordinal within "the external ones" is stable while
/// that set is, and `0` and `1` never move at all.
///
/// The scale matches Windows' own `GpuPreference` for `0`, `1` and `2`, which
/// is not a coincidence to be tidied away — it is what lets the same number
/// mean the same thing in the flag and in the registry value Windows reads.
///
/// 應用程式所要求的介面卡，即 `-GPU N` 所帶的數字。
///
/// `0` 與 `1` 是政策；`2` 以上是**外接介面卡之內**的序數，而非原始裝置清單的索引。這個區別正是
/// 整個設計的重點。原始索引會在插拔硬體或顯示器喚醒時重新編號，於是 `-GPU 2` 明天就會悄悄指向
/// 另一張卡，而且沒有任何東西會提醒你；「外接者之中的第 n 張」這個序數，在該集合不變時保持穩定，
/// 而 `0` 與 `1` 則永遠不動。
///
/// 此刻度在 `0`、`1`、`2` 上與 Windows 自己的 `GpuPreference` 一致，這並非可以順手「整理掉」的
/// 巧合——正是它讓同一個數字在旗標中與在 Windows 實際讀取的登錄檔值中意義相同。
public enum GraphicsAdapterSelection: Sendable, Hashable {
    /// Render in software; do not ask for a GPU at all.
    /// 以軟體繪製；完全不要求 GPU。
    case software

    /// Whatever the platform would choose on its own.
    /// 平台自行選擇的結果。
    case systemDefault

    /// The `ordinal`-th external adapter, counting from 1.
    /// 第 `ordinal` 張外接介面卡，由 1 起算。
    case external(ordinal: Int)

    /// Reads the number as `-GPU` spells it.
    /// 依 `-GPU` 的寫法讀取該數字。
    public init(number: Int) {
        switch number {
            case ..<0, 0: self = .software
            case 1: self = .systemDefault
            default: self = .external(ordinal: number - 1)
        }
    }

    /// The number that selects this, so reporting can echo what was asked for.
    /// 用以選取本項的數字，使輸出報告能回述使用者所要求的內容。
    public var number: Int {
        switch self {
            case .software: 0
            case .systemDefault: 1
            case .external(let ordinal): ordinal + 1
        }
    }
}

/// What resolving a selection against the adapters actually present produced.
///
/// Carries the fallback, rather than only the answer, because a selection that
/// silently resolved to something other than what was asked for is the failure
/// this whole feature exists to prevent. A caller that reports
/// ``requested`` and ``adapter`` together cannot hide it.
///
/// 將某個選擇對「實際存在的介面卡」解析之後的結果。
///
/// 它同時帶著「退路」而不只是「答案」，因為「悄悄解析成別的東西」正是整個功能存在所要防止的
/// 失敗。只要呼叫端同時回報 ``requested`` 與 ``adapter``，就不可能把它藏起來。
public struct GraphicsAdapterResolution: Sendable {
    /// What was asked for.
    /// 使用者所要求的。
    public var requested: GraphicsAdapterSelection

    /// What it resolved to, after any fallback.
    /// 經過任何退路之後，實際解析到的結果。
    public var resolved: GraphicsAdapterSelection

    /// The adapter chosen, or `nil` for software.
    /// 選定的介面卡；若為軟體繪製則為 `nil`。
    public var adapter: GraphicsAdapter?

    /// Why it fell back, in one line, or `nil` when it did not.
    /// 退路的原因，一行文字；若未發生退路則為 `nil`。
    public var fellBackBecause: String?

    /// Whether the request was honoured exactly.
    /// 該要求是否被完全遵從。
    public var isExact: Bool { fellBackBecause == nil }
}

extension GraphicsAdapterSelection {
    /// Chooses an adapter, falling back to the system default and then to
    /// software.
    ///
    /// Defined once, here, rather than in each backend: the rule is the same
    /// everywhere and only the *lookup* differs. A backend that implemented its
    /// own chain would be a second place for it to drift.
    ///
    /// 選出一張介面卡；不成則退回系統預設，再不成則退回軟體繪製。
    ///
    /// 此規則只在此處定義一次，而非由各 backend 各自實作：規則到處都相同，不同的只有**查詢**
    /// 方式。若某個 backend 自行實作一套退路鏈，那就是讓它產生分歧的第二個地方。
    public func resolve(among adapters: [GraphicsAdapter]) -> GraphicsAdapterResolution {
        func software(_ reason: String?) -> GraphicsAdapterResolution {
            GraphicsAdapterResolution(
                requested: self, resolved: .software, adapter: nil, fellBackBecause: reason
            )
        }

        switch self {
            case .software:
                return software(nil)

            case .systemDefault:
                guard let first = adapters.first else {
                    return software("no graphics adapter is available")
                }
                return GraphicsAdapterResolution(
                    requested: self, resolved: .systemDefault, adapter: first,
                    fellBackBecause: nil
                )

            case .external(let ordinal):
                let external = adapters.filter(\.isRemovable)
                if ordinal >= 1, ordinal <= external.count {
                    return GraphicsAdapterResolution(
                        requested: self, resolved: self, adapter: external[ordinal - 1],
                        fellBackBecause: nil
                    )
                }
                // No external adapter at that position. Fall back to the system
                // default, which is the highest-performing thing available, and
                // say why -- rather than silently picking the nearest card.
                // 該位置上沒有外接介面卡。退回系統預設（即現有中效能最高者）並說明原因，
                // 而不是默默挑一張最接近的卡。
                let reason =
                    external.isEmpty
                    ? "no external adapter is attached"
                    : "only \(external.count) external adapter(s) are attached"
                guard let first = adapters.first else {
                    return software("\(reason), and no adapter at all is available")
                }
                return GraphicsAdapterResolution(
                    requested: self, resolved: .systemDefault, adapter: first,
                    fellBackBecause: reason
                )
        }
    }
}
