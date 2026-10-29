/// Decides, from successive adapter enumerations, when the adapter in use has
/// gone: the part of ``BackendFeatures/GraphicsAdapters/adapterRemoved`` that
/// is the same on every platform.
///
/// Each platform signals differently that its adapters may have changed --
/// DXGI's adapters-changed event, a stale DXCore list, a kernel uevent, a Metal
/// device notification -- and none of those signals says which adapter went.
/// A backend therefore records a stable key for the adapter it renders on (a
/// LUID on Windows and WSL, a PCI address on Linux, a registry ID on macOS),
/// lists the keys again whenever its platform signals, and asks this type
/// whether the one in use is still among them. An adapter that is added, or a
/// different one that is removed, does not count.
///
/// It fires once per adapter: after a removal the backend re-arms it with the
/// adapter it renders on now, so the next removal is reported too and the same
/// one is not reported twice.
///
/// 從一次又一次的介面卡列舉，判斷使用中的介面卡何時消失：這是
/// ``BackendFeatures/GraphicsAdapters/adapterRemoved`` 在每個平台上都相同的那一部分。
///
/// 每個平台以不同方式通知「介面卡可能變了」——DXGI 的 adapters-changed 事件、變成 stale 的 DXCore 清單、核心的
/// uevent、Metal 的裝置通知——而這些訊號都不會說是哪一張不見了。因此 backend 記下它繪製所用介面卡的穩定鍵值
/// (Windows 與 WSL 上是 LUID、Linux 上是 PCI 位址、macOS 上是 registry ID),每當平台發出訊號就重新列出鍵值，並問
/// 這個型別使用中的那一張是否還在其中。新增的介面卡，或被移除的是另一張，都不算數。
///
/// 每張介面卡只觸發一次：移除之後 backend 以它現在繪製所用的介面卡重新設定，於是下一次移除也會回報，而同一次不會
/// 回報兩次。
@_spi(Backends)
public struct GraphicsAdapterRemovalWatch<Key: Hashable & Sendable>: Sendable {
    /// The adapter in use, or `nil` when nothing removable is in use (software
    /// rendering, or no adapter could be identified); then nothing fires until
    /// ``update(present:adopting:)`` finds one in use.
    /// 使用中的介面卡；沒有可移除的介面卡在使用中時(軟體繪製，或認不出任何介面卡)為 `nil`,直到 ``update(present:adopting:)`` 找到使用中的介面卡之前都不會觸發。
    public private(set) var inUse: Key?

    /// Whether ``update(present:)`` has reported the current ``inUse`` gone.
    /// ``update(present:)`` 是否已回報目前的 ``inUse`` 消失。
    public private(set) var hasFired = false

    public init(inUse: Key?) {
        self.inUse = inUse
    }

    /// Takes a fresh enumeration and returns `true` exactly once: the first
    /// time the adapter in use is not in it.
    ///
    /// While nothing is in use, `adopting` is asked for the adapter in use now
    /// and the watch follows it from this enumeration on. Without that, a watch
    /// re-armed while the list was empty -- a driver reset that left only the
    /// software adapter -- or started that way stayed at `nil` for good, and
    /// the adapter that came back was never reported when it went (review,
    /// 2026-10-29). It is required, not defaulted, so a backend cannot leave it
    /// out by accident.
    ///
    /// 接受一份新的列舉，只回傳一次 `true`:使用中的介面卡第一次不在其中的時候。
    ///
    /// 沒有介面卡在使用中時，會向 `adopting` 詢問現在使用中的介面卡，並從這次列舉起監看它。少了這一步，一個在
    /// 清單為空時重新設定(驅動程式重設後只剩軟體介面卡)或以此狀態啟動的監看會永遠停在 `nil`,回來的那張介面卡
    /// 之後消失時也不會回報(審查,2026-10-29)。此參數為必填而非預設值，讓 backend 不會不小心漏掉。
    public mutating func update(
        present: some Sequence<Key>, adopting candidate: @autoclosure () -> Key?
    ) -> Bool {
        guard let inUse else {
            rearm(inUse: candidate())
            return false
        }
        guard !hasFired else { return false }
        if present.contains(inUse) { return false }
        hasFired = true
        return true
    }

    /// Starts watching the adapter now in use, after a removal was reported.
    /// 回報過一次移除之後，改為監看現在使用中的介面卡。
    public mutating func rearm(inUse: Key?) {
        self.inUse = inUse
        hasFired = false
    }
}
