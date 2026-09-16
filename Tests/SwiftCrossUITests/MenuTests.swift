import Testing

import DummyBackend
@testable @_spi(Backends) import SwiftCrossUI

@Suite("Menu tests")
struct MenuTests {
    @MainActor
    @Test(
        "Ensure buttons encode to menu items correctly",
        .bug("https://github.com/moreSwift/swift-cross-ui/issues/747")
    )
    func buttonMenuItemEncoding() throws {
        let labels = [
            "Button1",
            "Button2"
        ]
        let view = Menu("Menu") {
            Button(labels[0]) {}
            Button(action: {}) {
                Text(labels[1])
            }
        }

        let node = ViewGraphHelpers.committedNode(for: view)

        let button = try #require(node.widget as? DummyBackend.SimpleButton)
        let menu = try #require(button.menu)
        for (i, item) in menu.content.items.enumerated() {
            switch item {
                case .button(let label, let action, let shortcut):
                    #expect(label == labels[i])
                    #expect(action != nil)
                    // Nothing in this view asked for one, so a shortcut here
                    // would mean the resolver invented it -- which is the only
                    // way `nil` can be wrong.
                    // 這個 view 裡沒有任何東西要求快捷鍵,因此此處若出現一個,代表那個 resolver 憑空
                    // 造了它——而那是 `nil` 唯一可能出錯的方式。
                    #expect(shortcut == nil)
                default:
                    Issue.record("Expected button, got \(item)")
            }
        }
    }
}

extension MenuTests {
    /// `.keyboardShortcut` reaches the resolved item, and stops at the one it
    /// is written on.
    ///
    /// **The second button is the half worth having.** A modifier that attached
    /// its shortcut to every item in the menu would pass any test that only
    /// looked at the item it was written on, and would then give two menu
    /// entries the same key -- which the platform resolves by picking one,
    /// silently.
    ///
    /// `.keyboardShortcut` 會抵達被解析出的那個項目,並且**只到它被寫在的那一個為止**。
    ///
    /// **第二顆按鈕才是值得擁有的那一半。** 一個「把快捷鍵掛到選單裡每一個項目」的 modifier,會通過
    /// 任何「只看它被寫在其上的那個項目」的測試;而它接著會讓兩個選單項目共用同一個按鍵——那件事平台
    /// 會靜默地挑一個來解決。
    @MainActor
    @Test func keyboardShortcutReachesTheResolvedItem() throws {
        let view = Menu("Menu") {
            Button("Save") {}
                .keyboardShortcut("s")
            Button("Plain") {}
        }

        let node = ViewGraphHelpers.committedNode(for: view)
        let button = try #require(node.widget as? DummyBackend.SimpleButton)
        let menu = try #require(button.menu)

        guard case .button(let savedLabel, _, let saved) = menu.content.items[0] else {
            Issue.record("Expected a button, got \(menu.content.items[0])")
            return
        }
        #expect(savedLabel == "Save")
        #expect(saved == KeyboardShortcut("s"))

        guard case .button(let plainLabel, _, let plain) = menu.content.items[1] else {
            Issue.record("Expected a button, got \(menu.content.items[1])")
            return
        }
        #expect(plainLabel == "Plain")
        #expect(plain == nil)
    }
}
