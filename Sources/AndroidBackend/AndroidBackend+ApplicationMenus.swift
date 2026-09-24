import AndroidKit
import SwiftCrossUI

@JavaClass(
    "dev.swiftcrossui.androidbackend.SwiftUnhandledKeyListener",
    implements: AndroidKit.View.OnUnhandledKeyEventListener.self
)
class SwiftUnhandledKeyListener: JavaObject {
    @JavaMethod
    @_nonoverride convenience init(_ id: Int32, environment: JNIEnvironment? = nil)
}

@JavaImplementation("dev.swiftcrossui.androidbackend.SwiftUnhandledKeyListener")
extension SwiftUnhandledKeyListener {
    @JavaMethod
    func swiftUnhandledKey(_ id: Int32, _ unicodeChar: Int32, _ metaState: Int32) -> Bool {
        ApplicationShortcuts.handle(id: id, unicodeChar: unicodeChar, metaState: metaState)
    }
}

/// The shortcuts a `CommandMenu` contributes, and the key that fires one.
///
/// A JNI native method carries no captured state, so the table lives here and
/// the listener carries a key into it -- the same arrangement `LazyListProviders`
/// and `FocusHandlers` use.
///
/// `nonisolated(unsafe)` for the reason those give: every access is on the
/// Android main thread -- registration from the scene graph, delivery from a
/// view callback -- and the type is not reachable from anywhere else.
///
/// 一個 `CommandMenu` 所貢獻的快捷鍵,以及觸發其中之一的那個按鍵。
///
/// 一個 JNI native method 不帶任何被捕捉的狀態,因此這張表住在這裡,而那個 listener 帶著一把進入它的
/// 鍵——與 `LazyListProviders`、`FocusHandlers` 是同一種安排。
///
/// `nonisolated(unsafe)` 的理由與那兩者所給的相同:每一次存取都在 Android 主執行緒上——註冊來自
/// scene graph,送達來自一次 view 回呼——而這個型別在別處無從觸及。
enum ApplicationShortcuts {
    struct Entry {
        let shortcut: KeyboardShortcut
        let action: @MainActor () -> Void
    }

    nonisolated(unsafe) private static var tables: [Int32: [Entry]] = [:]
    nonisolated(unsafe) private static var nextID: Int32 = 1

    /// Replaces the table for this id, issuing one the first time.
    ///
    /// REPLACES rather than appends, because `setApplicationMenu` is called on
    /// every scene-graph refresh and each call describes the whole menu. Adding
    /// would leave every earlier generation's closures live, capturing state
    /// that has since been replaced -- the same hazard `MenuShortcutActions`
    /// records on UIKit.
    ///
    /// **取代**而非追加,因為 `setApplicationMenu` 在每一次 scene graph 更新時都會被呼叫,而每一次
    /// 呼叫描述的都是**整個**選單。用追加,會讓先前每一代的 closure 全部留著、捕捉著早已被替換的狀態
    /// ——與 `MenuShortcutActions` 在 UIKit 上所記載的是同一個風險。
    static func setTable(_ entries: [Entry], reusing existing: Int32?) -> Int32 {
        let id = existing ?? nextID
        if existing == nil { nextID += 1 }
        tables[id] = entries
        return id
    }

    /// Runs the first entry whose shortcut matches, and says whether one did.
    ///
    /// The `Bool` is not decoration: it is what the listener returns to Android,
    /// and answering `true` for a key nothing matched would swallow that key
    /// from everything downstream.
    ///
    /// 執行第一個相符的項目,並說出是否有相符。
    ///
    /// 那個 `Bool` 不是裝飾:它是這個 listener 回報給 Android 的東西,而對一個沒有任何東西相符的按鍵
    /// 回答 `true`,會把那個按鍵從下游的一切手中吞掉。
    static func handle(id: Int32, unicodeChar: Int32, metaState: Int32) -> Bool {
        guard
            let entries = tables[id],
            let scalar = Unicode.Scalar(UInt32(max(0, unicodeChar))),
            scalar.value != 0
        else { return false }

        let character = Character(scalar)
        for entry in entries where matches(entry.shortcut, character, metaState) {
            MainActor.assumeIsolated { entry.action() }
            return true
        }
        return false
    }

    /// Whether this key press is the shortcut.
    ///
    /// **The modifier comparison is exact, not "contains".** A menu with both
    /// Ctrl-S and Ctrl-Shift-S would otherwise have Ctrl-Shift-S fire the plain
    /// one too, because the plain one's modifiers are a subset of what is held.
    /// Exactness is also what makes a shortcut that asks for no modifier stay
    /// out of the way of ordinary typing.
    ///
    /// 這次按鍵是不是那個快捷鍵。
    ///
    /// **修飾鍵的比較是「完全相等」,不是「包含」。** 否則,一個同時有 Ctrl-S 與 Ctrl-Shift-S 的選單,
    /// 在按下 Ctrl-Shift-S 時會**連帶**觸發那個單純的 Ctrl-S——因為後者的修飾鍵是「當下按著的那些」的
    /// 子集。而「完全相等」也正是讓「不要求任何修飾鍵的快捷鍵」不去妨礙一般打字的原因。
    private static func matches(
        _ shortcut: KeyboardShortcut,
        _ character: Character,
        _ metaState: Int32
    ) -> Bool {
        guard
            String(character).lowercased() == String(shortcut.key.character).lowercased()
        else { return false }
        // The modifier mapping is duplicated from `AndroidBackend.keyModifiers`
        // rather than called, because that one is `@MainActor` (it sits on the
        // backend) and this runs from a JNI callback that is not isolated.
        // Hopping to the main actor to read three constants would make the
        // answer arrive after the listener had already returned.
        // 這段修飾鍵映射是從 `AndroidBackend.keyModifiers` **複製**過來、而不是呼叫它——因為那一個是
        // `@MainActor` 的(它掛在 backend 上),而這裡是從一個未被隔離的 JNI 回呼執行的。為了讀三個
        // 常數而跳到 main actor,會讓答案在這個 listener 已經回傳之後才抵達。
        var wanted: Int32 = 0
        if shortcut.modifiers.contains(.command) { wanted |= 0x1000 }
        if shortcut.modifiers.contains(.control) { wanted |= 0x1000 }
        if shortcut.modifiers.contains(.shift) { wanted |= 0x1 }
        if shortcut.modifiers.contains(.option) { wanted |= 0x2 }
        return wanted == meaningfulMeta(metaState)
    }

    /// The meta bits this comparison cares about.
    ///
    /// Android's `metaState` also carries CAPS_LOCK, NUM_LOCK, SCROLL_LOCK and
    /// the left/right variants of each modifier. Comparing the raw value would
    /// make every shortcut stop working the moment Caps Lock was on, and would
    /// distinguish left Ctrl from right Ctrl -- neither of which any caller
    /// asked for.
    ///
    /// 這個比較在意的那些 meta 位元。
    ///
    /// Android 的 `metaState` 同時帶著 CAPS_LOCK、NUM_LOCK、SCROLL_LOCK,以及每個修飾鍵的左右變體。
    /// 拿原始值去比,會讓每一個快捷鍵在 Caps Lock 一開啟的瞬間全部失效,而且會把左 Ctrl 與右 Ctrl
    /// 分開看待——這兩件事都不是任何呼叫者所要求的。
    private static func meaningfulMeta(_ metaState: Int32) -> Int32 {
        /// `KeyEvent.META_CTRL_ON`, `META_SHIFT_ON`, `META_ALT_ON`.
        let interesting: Int32 = 0x1000 | 0x1 | 0x2
        return metaState & interesting
    }
}

extension AndroidBackend: BackendFeatures.ApplicationMenus {
    /// Registers a `CommandMenu`'s shortcuts. There is no menu to draw.
    ///
    /// **This replaces a commented-out stub carrying upstream's own TODO** --
    /// "Register app menu items as shortcuts when we support keyboard
    /// shortcuts" -- which is exactly what this does now that they are
    /// supported.
    ///
    /// **Android has no application menu, and that is the platform's answer
    /// rather than a gap this leaves open.** An app's global actions live in a
    /// toolbar overflow or a navigation drawer, and both belong to the app's own
    /// layout: drawing one here would put a bar into every SwiftCrossUI app on
    /// Android whether it declared `.commands` or not. What survives the
    /// translation is the shortcut, and an attached hardware keyboard is what
    /// reaches it.
    ///
    /// **The whole tree is flattened, submenus included.** A shortcut is global
    /// to the app on every platform -- on macOS it fires whether or not its
    /// menu is open, and nesting is presentation. Keeping the hierarchy here
    /// would mean deciding which nesting level a key belongs to, a question the
    /// other four backends never have to answer.
    ///
    /// 登記一個 `CommandMenu` 的快捷鍵。這裡沒有選單可畫。
    ///
    /// **這取代了一個帶著上游 TODO 的註解掉的樁**——「Register app menu items as shortcuts when we
    /// support keyboard shortcuts」——而既然快捷鍵現在支援了,這正是它所做的事。
    ///
    /// **Android 沒有應用程式選單,而那是這個平台的答案,不是這裡留下的一個缺口。** 一個 app 的全域
    /// 動作住在 toolbar 溢位選單或側邊抽屜裡,而兩者都屬於 app 自己的版面:在此畫一個出來,等於替
    /// Android 上**每一支** SwiftCrossUI app 都加上一條橫槓,無論它有沒有宣告 `.commands`。在這次翻譯
    /// 中存活下來的是快捷鍵,而接上的實體鍵盤就是抵達它的方式。
    ///
    /// **整棵樹會被攤平,子選單也是。** 快捷鍵在每一個平台上都是 app 全域的——在 macOS 上,它無論那個
    /// 選單有沒有打開都會觸發,而巢狀只是呈現方式。在此保留階層,等於得去決定「某個按鍵屬於哪一層」,
    /// 而那是其餘四個 backend 從來不必回答的問題。
    public func setApplicationMenu(
        _ submenus: [ResolvedMenu.Submenu],
        environment: EnvironmentValues
    ) {
        var entries: [ApplicationShortcuts.Entry] = []
        for submenu in submenus {
            collect(submenu.content.items, into: &entries, environment: environment)
        }

        let id = ApplicationShortcuts.setTable(entries, reusing: Self.applicationShortcutID)

        // **The content view is attached on every call, the decor listener only on the first, and
        // that asymmetry is a bug this file had for one build.**
        //
        // `setApplicationMenu` runs from the scene graph, which reaches it BEFORE the window's
        // content view exists on the first pass -- so a one-shot install left
        // `Self.shortcutHost` nil for the life of the app and the action-file path never worked.
        // The symptom was the one this whole change exists to remove: a replay that completes
        // with the counters at zero. The decor listener must still be added once, because
        // `addOnUnhandledKeyEventListener` appends and a listener per refresh would run every
        // action as many times as the scene graph had been rebuilt; `setShortcutListener`
        // replaces, so calling it every time is free.
        //
        // **content view 每次呼叫都掛,decor 的 listener 只掛第一次;而那個不對稱,是本檔有過一個版本的臭蟲。**
        //
        // `setApplicationMenu` 由場景圖呼叫,而它在第一輪抵達此處時,視窗的 content view 還不存在
        // ——因此「只裝一次」會讓 `Self.shortcutHost` 在這支 app 的餘生都是 nil,動作檔那條路從來沒有通過。
        // 症狀正是這整個改動所要消除的那一個:一次「跑完而計數器是零」的重放。decor 的 listener 仍然只能
        // 加一次,因為 `addOnUnhandledKeyEventListener` 是**附加**的,每次刷新加一個會讓每個動作執行
        // 「場景圖被重建過幾次」那麼多次;而 `setShortcutListener` 是**替換**,因此每次都呼叫不花什麼。
        let listener = SwiftUnhandledKeyListener(id, environment: Self.env)
        // **And the same listener on the content view, which is the half an action file can
        // reach.** The decor listener is what a real keyboard uses; it runs from `ViewRootImpl`,
        // above anything an application can post to, so a replay never reaches it --
        // measured on 2026-09-23, P71's counters at 0/0/0 while `adb shell input keycombination`
        // fired the same keys. `ShortcutHostLayout` consults the table at the same moment, after
        // the hierarchy has declined, one level lower. Whichever sees the key first answers, and
        // the content view is always first, so nothing fires twice.
        //
        // **而同一個 listener 也掛在 content view 上,那正是動作檔抵達得了的那一半。** decor 上的那個
        // 是真鍵盤走的路;它由 `ViewRootImpl` 執行,位於任何應用程式投遞得到的層級之上,因此一次重放
        // 永遠到不了它——2026-09-23 實測:P71 的計數器停在 0/0/0,而同樣那些按鍵用
        // `adb shell input keycombination` 就觸發了。`ShortcutHostLayout` 在同一個時刻查那張表
        // ——階層都拒絕之後——只是低一層。誰先看到那個按鍵誰回答,而 content view 永遠先看到,
        // 因此不會有東西觸發兩次。
        Self.applicationShortcutListener = listener
        Self.shortcutHost?.setShortcutListener(listener)

        guard Self.applicationShortcutID == nil else { return }
        Self.applicationShortcutID = id

        // Added once, to the activity's content view.
        //
        // Adding it on every call would attach a new listener per scene-graph
        // refresh while every previous one stayed on the view, so a single key
        // press would run its action as many times as there had been refreshes.
        // The table behind the id is replaced above instead, which is the part
        // that actually changes.
        //
        // 只加一次,加在 activity 的 content view 上。
        //
        // 每次呼叫都加,會在每一次 scene graph 更新時掛上一個新的 listener,而先前每一個都還留在那個
        // view 上——於是單獨一次按鍵,會把它的動作執行「更新過幾次」那麼多遍。改為在上方**取代**那個 id
        // 背後的表,而那才是真正會變的部分。
        Self.activity.getWindow()?.getDecorView()?
            .addOnUnhandledKeyEventListener(
                listener.as(AndroidKit.View.OnUnhandledKeyEventListener.self)
            )

    }

    /// Walks the items, keeping only those that carry both a shortcut and an
    /// action.
    ///
    /// A disabled item has a `nil` action and is skipped, so its key stays
    /// available to whatever else wants it rather than being swallowed by an
    /// entry that would do nothing. P71 asserts exactly this.
    ///
    /// 走訪那些項目,只保留「同時帶有快捷鍵與動作」的那些。
    ///
    /// 一個被停用的項目其 action 為 `nil`,會被跳過;如此它的按鍵仍然留給其他想要它的東西,而不是被一個
    /// 「什麼都不會做」的項目吞掉。P71 斷言的正是這件事。
    private func collect(
        _ items: [ResolvedMenu.Item],
        into entries: inout [ApplicationShortcuts.Entry],
        environment: EnvironmentValues
    ) {
        for item in items {
            switch item {
                case .button(let label, let action):
                    _ = label
                    guard let action, let shortcut = environment.keyboardShortcut,
                          environment.isEnabled
                    else { continue }
                    entries.append(.init(shortcut: shortcut, action: action))
                case .submenu(let submenu):
                    collect(submenu.content.items, into: &entries, environment: environment)
                case .modifiedEnvironment(let item, let modification):
                    collect([item], into: &entries, environment: modification(environment))
                case .toggle, .separator:
                    continue
            }
        }
    }

    nonisolated(unsafe) static var applicationShortcutID: Int32?
}
