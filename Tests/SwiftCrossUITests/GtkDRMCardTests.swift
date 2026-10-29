// How GtkBackend reads the GPUs /sys/class/drm lists on Linux, and the
// DRI_PRIME name it writes for one, checked against a fake sysfs tree. A real
// switch needs a Linux machine with two GPUs (queue.md row 23); this pins the
// parsing and the spelling, which WSL cannot reach because its /sys/class/drm
// holds only vgem.
// GtkBackend 如何讀 Linux 上 /sys/class/drm 列出的 GPU,以及為其中一張寫出的 DRI_PRIME 名稱，以一棵假的
// sysfs 目錄樹檢查。真正切換需要一台有兩張 GPU 的 Linux 機器(queue.md 第 23 列);這裡釘住的是解析與拼法，
// 而 WSL 碰不到它們，因為 WSL 的 /sys/class/drm 只有 vgem。
#if canImport(GtkBackend) && os(Linux)
    import Foundation
    import Testing
    @testable import GtkBackend

    @Suite("GtkBackend DRM cards")
    struct GtkDRMCardTests {
        /// Writes card directories the way the kernel lays them out: a device
        /// directory with uevent, boot_vga and removable, plus a connector entry
        /// (card1-HDMI-A-1) that is not a card.
        /// 依核心的版面寫出顯示卡目錄:device 目錄裡有 uevent、boot_vga 與 removable,再加一個不是顯示卡的接頭項目
        /// (card1-HDMI-A-1)。
        func makeTree() throws -> String {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("scui-drm-\(UUID().uuidString)").path
            func card(_ name: String, driver: String, slot: String, id: String, boot: String) throws {
                let device = "\(root)/\(name)/device"
                try FileManager.default.createDirectory(atPath: device, withIntermediateDirectories: true)
                try "DRIVER=\(driver)\nPCI_ID=\(id)\nPCI_SLOT_NAME=\(slot)\n"
                    .write(toFile: "\(device)/uevent", atomically: true, encoding: .utf8)
                try "\(boot)\n".write(toFile: "\(device)/boot_vga", atomically: true, encoding: .utf8)
                try "fixed\n".write(toFile: "\(device)/removable", atomically: true, encoding: .utf8)
            }
            // card0 is the discrete card and NOT the boot GPU, so the order has to
            // come from boot_vga rather than the name.
            // card0 是獨顯且不是開機 GPU,所以順序必須來自 boot_vga 而不是名稱。
            try card("card0", driver: "nvidia", slot: "0000:01:00.0", id: "10DE:28E0", boot: "0")
            try card("card1", driver: "amdgpu", slot: "0000:05:00.0", id: "1002:15BF", boot: "1")
            try card("card2", driver: "vgem", slot: "vgem", id: "", boot: "0")
            try FileManager.default.createDirectory(
                atPath: "\(root)/card1-HDMI-A-1", withIntermediateDirectories: true)
            return root
        }

        @Test("the boot GPU comes first; connectors and vgem are skipped")
        @MainActor func listing() throws {
            let root = try makeTree()
            defer { try? FileManager.default.removeItem(atPath: root) }
            let cards = GtkBackend.drmCards(root: root)
            #expect(cards.map(\.busID) == ["0000:05:00.0", "0000:01:00.0"])
            #expect(cards.map(\.driver) == ["amdgpu", "nvidia"])
            #expect(cards.map(\.isBootVGA) == [true, false])
            #expect(cards.map(\.adapter.isLowPower) == [true, false])
            #expect(cards[0].adapter.name == "amdgpu 1002:15BF (0000:05:00.0)")
        }

        @Test("one card alone is not low power")
        @MainActor func single() throws {
            let root = try makeTree()
            defer { try? FileManager.default.removeItem(atPath: root) }
            try FileManager.default.removeItem(atPath: "\(root)/card0")
            let cards = GtkBackend.drmCards(root: root)
            #expect(cards.count == 1)
            #expect(cards.first?.adapter.isLowPower == false)
        }

        @Test("DRI_PRIME spells a bus ID as Mesa takes it")
        @MainActor func prime() {
            #expect(GtkBackend.primeName(busID: "0000:03:00.0") == "pci-0000_03_00_0")
        }
    }
#endif
