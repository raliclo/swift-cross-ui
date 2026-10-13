import Foundation
import SwiftCrossUI

extension GtkBackend {
    /// On macOS, makes the framework's application menu the one the menu bar shows first.
    ///
    /// GTK puts a menu of its own in the first place of the bar -- About, Settings…,
    /// Services, Hide, Hide Others, Show All, Quit, from its
    /// `gtkapplication-quartz.ui` -- and the app's menus after it, so an app that
    /// has an application menu showed two, both under the app's name (P92,
    /// 2026-10-14). GTK 4 offers no call to replace its own: `standard_app_menu`
    /// in `gtkapplication-quartz.c` is filled from that resource at start-up and
    /// nothing public sets it.
    ///
    /// So the contents change places instead. The framework's menu, built in the
    /// second place, is handed to the first item as its submenu and the second item
    /// is hidden. Nothing is removed: GTK inserts and removes the bar's items by
    /// position, so the count has to stay what it believes. GTK builds a new bar
    /// each time the menu bar model is set, and this is done again then.
    ///
    /// Through the Objective-C runtime, as `sendToApplication`: GtkBackend does
    /// not link AppKit.
    ///
    /// 在 macOS 上，讓框架的 app 選單成為選單列的第一個。GTK 會在第一格放它自己的選單(About、Settings…、Services、Hide、
    /// Hide Others、Show All、Quit),app 的選單排在後面，所以有 app 選單的 app 會出現兩個同名的選單。GTK 4 沒有公開的呼叫可以
    /// 換掉它自己的那個。所以改成交換內容:把建在第二格的框架選單交給第一格當子選單，再把第二格藏起來。不移除任何項目——GTK 是依
    /// 位置插入與移除選單列項目的，數量必須與它認為的一致。每次設定選單列 model 時 GTK 都會重建，屆時再做一次。
    func adoptApplicationMenuOnMac() {
        #if canImport(Darwin)
            func object(_ target: NSObject, _ selector: String) -> NSObject? {
                target.perform(NSSelectorFromString(selector))?.takeUnretainedValue() as? NSObject
            }
            guard let type = NSClassFromString("NSApplication") as? NSObject.Type,
                  let application = type.perform(NSSelectorFromString("sharedApplication"))?
                  .takeUnretainedValue() as? NSObject,
                  let bar = object(application, "mainMenu"),
                  let items = object(bar, "itemArray") as? [NSObject],
                  items.count >= 2,
                  items[1].value(forKey: "hidden") as? Bool != true,
                  let ours = object(items[1], "submenu")
            else { return }
            _ = items[1].perform(NSSelectorFromString("setSubmenu:"), with: nil)
            _ = items[0].perform(NSSelectorFromString("setSubmenu:"), with: ours)
            items[1].setValue(true, forKey: "hidden")
        #endif
    }
}
