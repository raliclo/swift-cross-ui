import CGtk
import Gtk
import SwiftCrossUI

extension GtkBackend: BackendFeatures.WidgetGeometry {
    /// Asks GTK, through the C function this module already calls elsewhere.
    ///
    /// **`gtk_widget_compute_point`, not a generated binding.** The generated
    /// Swift has no wrapper for it, and that does not mean it is unavailable:
    /// this module imports `CGtk` and calls C symbols directly throughout --
    /// `gtk_widget_measure`, `gtk_widget_add_tick_callback`, and this very
    /// function at `Sources/Gtk/Widgets/ScrolledWindow.swift:131`. It has been
    /// in GTK since 4.0, which matters because this backend builds against
    /// < 4.10.
    ///
    /// The target is the widget's root, so the result is in WINDOW coordinates,
    /// which is what ``SwiftCrossUI/CoordinateSpace/global`` asks for.
    ///
    /// **NOT COMPILED HERE (2026-09-10).** This machine has no GTK, so this is
    /// written from the shape of the call already in `ScrolledWindow.swift` and
    /// needs a build on the machine that has one. The specific things to check:
    /// that `graphene_point_t` is visible through `CGtk` here as it is there,
    /// and that `gtk_widget_get_root` returns a `GtkRoot` that takes the
    /// `GtkWidget*` cast.
    ///
    /// 去問 GTK，透過本模組在別處早已呼叫的那個 C 函式。
    ///
    /// **用 `gtk_widget_compute_point`，而不是產生出來的 binding。** 產生出來的 Swift 沒有它的包裝，
    /// 而那並不代表它不可用:本模組 `import CGtk`，而且到處直接呼叫 C 符號——`gtk_widget_measure`、
    /// `gtk_widget_add_tick_callback`，以及這個函式本身(`Sources/Gtk/Widgets/ScrolledWindow.swift:131`)。
    /// 它自 GTK 4.0 就存在，而這一點很重要，因為本 backend 是對著 < 4.10 建置的。
    ///
    /// 目標取該 widget 的 root，因此結果是**視窗**座標——那正是
    /// ``SwiftCrossUI/CoordinateSpace/global`` 所要的。
    ///
    /// **此處未編譯(2026-09-10)。** 這台機器沒有 GTK，因此本檔是依 `ScrolledWindow.swift` 中既有的
    /// 呼叫形狀寫成的，需要在有 GTK 的機器上建置一次。唯一要查的是:`graphene_point_t` 在此處是否
    /// 一如它在 `ScrolledWindow.swift` 中那樣經由 `CGtk` 可見;本檔其餘每一個呼叫，該檔都已經在做。
    public func originInWindow(ofWidget widget: Widget) -> SIMD2<Int>? {
        let pointer = widget.widgetPointer

        // Walk to the topmost widget with `gtk_widget_get_parent` rather than
        // casting what `gtk_widget_get_root` returns.
        //
        // `gtk_widget_get_root` gives a `GtkRoot*`, which is an INTERFACE, and
        // turning that into the `GtkWidget*` this call wants is the one step
        // here nobody on this machine can check. The parent walk needs no cast:
        // both functions take and return `GtkWidget*`, and the top of the walk
        // IS the window, which is the frame of reference wanted.
        //
        // 以 `gtk_widget_get_parent` 往上走到最頂層，而不是去轉型 `gtk_widget_get_root` 的回傳值。
        //
        // `gtk_widget_get_root` 給的是 `GtkRoot*`，那是一個**介面**，而把它變成這個呼叫所要的
        // `GtkWidget*`，是此處唯一一個在這台機器上沒有人查得了的步驟。往上走則不需要任何轉型:
        // 這兩個函式收的與回的都是 `GtkWidget*`，而走到頂端的那一個**就是**視窗，也正是此處所要的
        // 參考座標系。
        var top = pointer
        var hops = 0
        while let parent = gtk_widget_get_parent(top), hops < 128 {
            top = parent
            hops += 1
        }
        guard hops > 0 else {
            // No parent at all: not in a window yet.
            // 完全沒有父節點:尚未位於任何視窗中。
            return nil
        }

        // Summed from the positions SwiftCrossUI gave each GtkFixed, which hold
        // the moment they are set, rather than from GTK's allocations, which
        // arrive on a later frame: asked during the update, `compute_point` read
        // every widget at 0,0 and P63's global and named spaces both said x=0
        // y=0 (2026-10-16). An ancestor that is not a GtkFixed (a scrolled
        // window's viewport, the window itself) contributes its offset once GTK
        // has allocated it, and nothing before.
        // 由 SwiftCrossUI 交給每個 GtkFixed 的位置加總而得，那些位置一設定就成立；而不是取自 GTK 的配置，
        // 配置要到之後的影格才到：在更新期間詢問時,`compute_point` 把每個 widget 都讀成 0,0,P63 的 global
        // 與具名座標空間都顯示 x=0 y=0(2026-10-16)。不是 GtkFixed 的祖先(捲動視窗的 viewport、視窗本身)
        // 在 GTK 配置它之後才貢獻其位移，之前則為零。
        var x = 0.0
        var y = 0.0
        var child = pointer
        while let parent = gtk_widget_get_parent(child) {
            if g_type_check_instance_is_a(
                UnsafeMutablePointer(OpaquePointer(parent)), gtk_fixed_get_type()) != 0
            {
                // The child's transform, not `gtk_fixed_get_child_position`: on GTK
                // 4.24 that returns 0,0 after a `gtk_fixed_move` to (10, 20) while the
                // transform holds the translation (measured in C, 2026-10-16).
                // 取子元件的 transform,而不是 `gtk_fixed_get_child_position`:在 GTK 4.24 上，
                // `gtk_fixed_move` 到 (10, 20) 之後後者回傳 0,0,transform 則保有該位移(以 C 實測,2026-10-16)。
                var childX: Float = 0
                var childY: Float = 0
                parent.withMemoryRebound(to: GtkFixed.self, capacity: 1) { fixed in
                    if let transform = gtk_fixed_get_child_transform(fixed, child) {
                        gsk_transform_to_translate(transform, &childX, &childY)
                    }
                }
                x += Double(childX)
                y += Double(childY)
            } else if gtk_widget_get_width(parent) > 0 {
                var source = graphene_point_t(x: 0, y: 0)
                var result = graphene_point_t(x: 0, y: 0)
                if gtk_widget_compute_point(child, parent, &source, &result) != 0 {
                    x += Double(result.x)
                    y += Double(result.y)
                }
            }
            child = parent
        }
        return SIMD2(Int(x.rounded()), Int(y.rounded()))
    }
}
