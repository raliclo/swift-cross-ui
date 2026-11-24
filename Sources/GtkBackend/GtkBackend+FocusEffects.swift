import CGtk
import Gtk
import SwiftCrossUI

extension GtkBackend: BackendFeatures.FocusEffects, BackendFeatures.FocusDisabledContainers {
    /// The CSS class whose rule draws no outline, which is how GTK themes draw
    /// the focus ring (`:focus-visible`, and `:focus-within` on an entry).
    /// 規則不畫 outline 的 CSS class;GTK 主題正是以 outline 畫焦點環(`:focus-visible`,entry 則是 `:focus-within`)。
    static let noFocusEffectClass = "scui-no-focus-effect"

    /// The class on the widget and on the widgets it is made of -- the `text`
    /// inside an `entry`, the `check` inside a `checkbutton` -- stopping at a
    /// widget another node was given, as on AppKit.
    ///
    /// A class on each widget rather than one descendant rule
    /// (`.scui-no-focus-effect *`): a descendant rule would also reach a
    /// control further in that said `.focusEffectDisabled(false)`, and CSS has
    /// no way to put a theme outline back once a rule removed it.
    ///
    /// 把 class 加在 widget 及組成它的 widget 上(`entry` 裡的 `text`、`checkbutton` 裡的 `check`),與 AppKit 相同，在
    /// 已交給另一個節點的 widget 停下。每個 widget 各自加 class,而不是一條後代規則(`.scui-no-focus-effect *`):後代規則
    /// 也會作用到更內層、說了 `.focusEffectDisabled(false)` 的控制項，而一旦規則移除了主題的 outline,CSS 沒有辦法把它放回去。
    public func setFocusEffectDisabled(_ disabled: Bool, on widget: Widget) {
        Self.installFocusEffectCSS()
        let pointer = widget.widgetPointer
        g_object_set_data(Self.gObject(pointer), Self.focusEffectNodeKey, pointer)
        applyFocusEffect(disabled, to: pointer, isRoot: true)
    }

    private func applyFocusEffect(
        _ disabled: Bool,
        to pointer: UnsafeMutablePointer<GtkWidget>,
        isRoot: Bool
    ) {
        if !isRoot, g_object_get_data(Self.gObject(pointer), Self.focusEffectNodeKey) != nil {
            return
        }
        if disabled {
            gtk_widget_add_css_class(pointer, Self.noFocusEffectClass)
        } else {
            gtk_widget_remove_css_class(pointer, Self.noFocusEffectClass)
        }
        var child = gtk_widget_get_first_child(pointer)
        while let current = child {
            applyFocusEffect(disabled, to: current, isRoot: false)
            child = gtk_widget_get_next_sibling(current)
        }
    }

    /// Whether `pointer` is under `.focusEffectDisabled`; a `.focusable()`
    /// target asks before it shows the ring it draws itself.
    /// `pointer` 是否在 `.focusEffectDisabled` 之下;`.focusable()` target 在顯示自己畫的焦點環之前會先問。
    static func isFocusEffectDisabled(_ pointer: UnsafeMutablePointer<GtkWidget>) -> Bool {
        gtk_widget_has_css_class(pointer, noFocusEffectClass) != 0
    }

    private static let focusEffectNodeKey = "scui-focus-effect-node"
    nonisolated(unsafe) private static var focusEffectCSS: CSSProvider?

    /// One display-wide provider, installed on first use. Application
    /// priority, above the theme, so the rule wins whatever the theme selector
    /// specificity: GTK orders by provider priority first.
    /// 一個 display 範圍的 provider,第一次用到時安裝。application 優先序，高於主題，所以不論主題選擇器的特定性如何，
    /// 這條規則都會勝出:GTK 先依 provider 優先序排序。
    private static func installFocusEffectCSS() {
        guard focusEffectCSS == nil else { return }
        let provider = CSSProvider()
        provider.loadCss(
            from: """
                .\(noFocusEffectClass),
                .\(noFocusEffectClass):focus,
                .\(noFocusEffectClass):focus-visible,
                .\(noFocusEffectClass):focus-within {
                    outline-style: none;
                    outline-color: transparent;
                }
                """
        )
        focusEffectCSS = provider
    }

    private static func gObject(_ pointer: UnsafeMutablePointer<GtkWidget>)
        -> UnsafeMutablePointer<CGtk.GObject>
    {
        UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CGtk.GObject.self)
    }

    /// `can-focus = false` on the container, which GTK applies to the
    /// container and to everything in it: Tab (`gtk_widget_child_focus`)
    /// skips it, and a widget inside cannot grab the focus.
    ///
    /// The container is this backend's passthrough container, which takes no
    /// focus of its own, so `can-focus = true` when unmarked is what it had.
    ///
    /// 在容器上設 `can-focus = false`,GTK 把它套用到容器及其中的一切:Tab(`gtk_widget_child_focus`)跳過它，其中的
    /// widget 無法取得焦點。這個容器是本 backend 的 passthrough 容器，自己不取焦點，所以取消標記時的 `can-focus = true`
    /// 就是它原本的值。
    public func setFocusDisabled(_ disabled: Bool, onContainer container: Widget) {
        let pointer = container.widgetPointer
        gtk_widget_set_can_focus(pointer, disabled ? 0 : 1)
        guard disabled, let root = gtk_widget_get_root(pointer) else { return }
        let window = UnsafeMutableRawPointer(root).assumingMemoryBound(to: GtkWindow.self)
        guard var current = gtk_window_get_focus(window) else { return }
        while true {
            if current == pointer {
                gtk_window_set_focus(window, nil)
                return
            }
            guard let parent = gtk_widget_get_parent(current) else { return }
            current = parent
        }
    }

    /// Shows the focus ring after a focus the app asked for.
    ///
    /// GTK draws the ring only while the window's `focus-visible` is set, and
    /// sets it for a keyboard focus change, not for `gtk_widget_grab_focus`;
    /// without this a `.focused` request moved the focus with no ring, unlike
    /// AppKit. Synchronous, on the widget that has just taken the focus: no
    /// idle callback holding a widget pointer that nothing keeps alive.
    ///
    /// 在 app 要求的聚焦之後顯示焦點環。GTK 只在視窗的 `focus-visible` 設定時畫焦點環，而它只在鍵盤造成的焦點變化時設定，
    /// `gtk_widget_grab_focus` 不會;少了這一步,`.focused` 要求移動了焦點卻沒有焦點環，與 AppKit 不同。同步執行，對象是剛
    /// 取得焦點的 widget:沒有一個持有「沒人保持其存活的 widget 指標」的 idle callback。
    static func showFocusRing(after pointer: UnsafeMutablePointer<GtkWidget>) {
        guard let root = gtk_widget_get_root(pointer) else { return }
        let window = UnsafeMutableRawPointer(root).assumingMemoryBound(to: GtkWindow.self)
        gtk_window_set_focus_visible(window, 1)
    }
}
