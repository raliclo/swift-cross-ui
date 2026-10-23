import AndroidKit

extension AndroidBackend {
    /// The display density, read through JNI once and kept until the
    /// configuration changes (`configurationDidChange` clears it).
    ///
    /// Each read was three JNI calls -- `getResources`, `getDisplayMetrics` and
    /// the `density` field -- each looking its method up by name, and checked by
    /// CheckJNI in the debuggable APKs the tests install. Setting a widget's
    /// position or size reads it, so a first layout of many widgets read it
    /// hundreds of times: P96's 33 tiles held the main thread long enough after
    /// RENDER COMPLETE that its first animations got no frame (2026-10-24).
    ///
    /// 顯示密度：經由 JNI 讀一次後保留，直到設定變更(`configurationDidChange` 會清掉)。每次讀取原本是三個 JNI 呼叫
    ///——`getResources`、`getDisplayMetrics` 與 `density` 欄位——每個都以名稱查找方法，在測試安裝的可除錯 APK 中還要
    /// 經過 CheckJNI。設定 widget 的位置或大小都會讀它，所以許多 widget 的第一次排版要讀上數百次:P96 的 33 格在
    /// RENDER COMPLETE 之後佔住主執行緒，久到它最初的動畫收不到任何一幀(2026-10-24)。
    nonisolated(unsafe) static var cachedDensity: Float?

    /// The cached density, or `read()` the first time and after a configuration change.
    /// 快取的密度；第一次與設定變更之後則呼叫 `read()`。
    static func density(_ read: () -> Float) -> Float {
        if let cachedDensity { return cachedDensity }
        let value = read()
        cachedDensity = value
        return value
    }
}
