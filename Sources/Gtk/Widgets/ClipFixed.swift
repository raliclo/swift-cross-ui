import CGtk
import GtkCHelpers

/// A ``Fixed`` that clips its children to its own size request.
///
/// The container SwiftCrossUI's `clipped()` wraps content in. A plain GtkFixed
/// measures to the bounding box of its children, so a child larger than the
/// frame makes the container get allocated the child's size and `overflow:
/// hidden` then clips to nothing useful. This one measures to its size request,
/// so the allocation is the frame and the oversized child is cut to it.
///
/// See `gtk_clip_fixed.c` for the measure and snapshot overrides.
///
/// 一個會將子元件裁切至「自身 size request」的 ``Fixed``。
///
/// SwiftCrossUI 的 `clipped()` 用來包裹內容的容器。一般 GtkFixed 會 measure 成其子元件的外接框,
/// 因此比框更大的子元件會使容器被 allocate 成子元件的尺寸,`overflow: hidden` 便裁不出有用的結果。
/// 此容器改為 measure 成其 size request,使 allocation 即為該框,超框的子元件因而被裁切至該框。
///
/// measure 與 snapshot 的覆寫詳見 `gtk_clip_fixed.c`。
public class ClipFixed: Fixed {
    public override init() {
        super.init(scui_clip_fixed_new())
    }
}
