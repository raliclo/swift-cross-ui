import CGtk
import GtkCHelpers

/// A ``Fixed`` that does not claim pointer events for itself.
///
/// The layout containers SwiftCrossUI builds -- a stack, a group, either half of
/// an overlay -- draw nothing, and GTK hit testing returns a container for any
/// point none of its children cover. Such a container therefore swallows clicks,
/// drags and scrolls meant for whatever is behind it, which under an overlay is
/// everything beneath it.
///
/// See `gtk_passthrough_fixed.c` for how it is done and why `contains` is the
/// right place. A container that something has made interactive still claims its
/// points, so `.onTapGesture` on a stack keeps working.
///
/// 一個不會為自己攔截指標事件的 ``Fixed``。
///
/// SwiftCrossUI 所建構的版面容器——stack、group、overlay 的任一半——皆不繪製任何內容，而 GTK 的
/// hit testing 對於「沒有任何子元件覆蓋」的位置會回傳該容器本身。這類容器因此會吞掉原本要送給其
/// 後方元件的點擊、拖曳與捲動；而在 overlay 之下，那意味著其下方的一切。
///
/// 實作方式及「為何 `contains` 是正確的著手處」詳見 `gtk_passthrough_fixed.c`。已被賦予互動能力
/// 的容器仍會攔截其範圍內的點，因此 stack 上的 `.onTapGesture` 仍能正常運作。
public class PassthroughFixed: Fixed {
    public override init() {
        super.init(gtk_passthrough_fixed_new())
    }
}
