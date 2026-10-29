import Testing

@_spi(Backends) import SwiftCrossUI

/// The enumeration diff behind `adapterRemoved`, fed the lists a backend would
/// read before and after a change. The keys are the shapes the backends use:
/// DXGI/DXCore LUIDs in hexadecimal and Linux PCI addresses.
/// `adapterRemoved` 背後的列舉比對，餵給它 backend 在變更前後會讀到的清單。鍵值採 backend 實際使用的形式:
/// 十六進位的 DXGI/DXCore LUID 與 Linux 的 PCI 位址。
/// One enumeration fed to the watch. A function, because `#expect` cannot take a
/// mutating call on its operand.
/// 餵給 watch 的一份列舉。寫成函式，因為 `#expect` 的運算元不能是 mutating 呼叫。
private func fire(_ watch: inout GraphicsAdapterRemovalWatch<String>, _ present: [String]) -> Bool {
    watch.update(present: present)
}

@Suite("Graphics adapter removal")
struct GraphicsAdapterRemovalWatchTests {
    @Test("An unchanged list does not fire")
    func unchanged() {
        var watch = GraphicsAdapterRemovalWatch(inUse: "1f2a3")
        #expect(fire(&watch, ["1f2a3", "1f3b0"]) == false)
        #expect(fire(&watch, ["1f2a3", "1f3b0"]) == false)
        #expect(!watch.hasFired)
    }

    @Test("Another adapter added or removed does not fire")
    func otherAdapters() {
        var watch = GraphicsAdapterRemovalWatch(inUse: "0000:01:00.0")
        // An eGPU plugged in, then unplugged, while the boot GPU renders.
        // 插上 eGPU 再拔掉，而繪製的是開機用的 GPU。
        #expect(fire(&watch, ["0000:01:00.0", "0000:3c:00.0"]) == false)
        #expect(fire(&watch, ["0000:01:00.0"]) == false)
    }

    @Test("The adapter in use going away fires once")
    func removal() {
        var watch = GraphicsAdapterRemovalWatch(inUse: "1f3b0")
        #expect(fire(&watch, ["1f2a3"]) == true)
        #expect(watch.hasFired)
        // DXGI signals more than once around one change; it is reported once.
        // DXGI 在一次變更前後會發出不只一次訊號；只回報一次。
        #expect(fire(&watch, ["1f2a3"]) == false)
        #expect(fire(&watch, []) == false)
    }

    @Test("A driver upgrade gives the adapter a new LUID, which counts as removal")
    func driverUpgrade() {
        var watch = GraphicsAdapterRemovalWatch(inUse: "1f3b0")
        #expect(fire(&watch, ["1f2a3", "2c410"]) == true)
    }

    @Test("After a removal the watch follows the adapter now in use")
    func rearm() {
        var watch = GraphicsAdapterRemovalWatch(inUse: "1f3b0")
        #expect(fire(&watch, ["1f2a3"]) == true)
        watch.rearm(inUse: "1f2a3")
        #expect(!watch.hasFired)
        #expect(fire(&watch, ["1f2a3"]) == false)
        #expect(fire(&watch, []) == true)
    }

    @Test("Nothing identified in use never fires")
    func nothingInUse() {
        var watch = GraphicsAdapterRemovalWatch<String>(inUse: nil)
        #expect(fire(&watch, []) == false)
        #expect(fire(&watch, ["1f2a3"]) == false)
    }
}
