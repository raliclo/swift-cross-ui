// The declaration lives in gtk_helpers.h; see the note there for why it is not
// in a header of its own.
// 宣告位於 gtk_helpers.h；不另立標頭檔的理由記於該處。
#include "gtk_helpers.h"

#define GTK_TYPE_PASSTHROUGH_DRAWING_AREA (gtk_passthrough_drawing_area_get_type())

// Spelled out for the same reason as in gtk_passthrough_fixed.c: G_DEFINE_TYPE
// generates the get_type function but not the checking macros, and this type's
// struct is deliberately private to this file.
// 手動定義，理由與 gtk_passthrough_fixed.c 相同：G_DEFINE_TYPE 只產生 get_type 函式，不產生
// 型別檢查巨集，而此型別的 struct 刻意只存在於本檔案內。
#define GTK_IS_PASSTHROUGH_DRAWING_AREA(obj) \
    (G_TYPE_CHECK_INSTANCE_TYPE((obj), GTK_TYPE_PASSTHROUGH_DRAWING_AREA))

typedef struct _GtkPassthroughDrawingArea {
    GtkDrawingArea parent_instance;

    // Whether this path paints a visible fill. False for a stroke-only path --
    // a border is the common one -- whose interior is empty.
    // 此路徑是否繪製了看得見的填色。對「只有描邊」的路徑為 false——邊框是最常見的一種——其內部
    // 是空的。
    gboolean opaque;
} GtkPassthroughDrawingArea;

typedef struct _GtkPassthroughDrawingAreaClass {
    GtkDrawingAreaClass parent_class;
} GtkPassthroughDrawingAreaClass;

G_DEFINE_TYPE(
    GtkPassthroughDrawingArea, gtk_passthrough_drawing_area, GTK_TYPE_DRAWING_AREA
)

// Claims a point only if this path fills something, or if something has made it
// interactive.
//
// WHY THIS EXISTS, measured 2026-09-10. `.border(color, width:)` is
// `overlay { Rectangle().inset(by:).stroke(...) }` -- an overlaid path, drawn by
// a GtkDrawingArea covering the whole view. A plain GtkDrawingArea claims every
// point in its allocation, so the border took every click meant for what it
// surrounds.
//
// It was found through task #111, "a click inside a popover does nothing".
// `gtk_widget_pick` on the popover, at seven of eight points down its centre
// line, returned:
//
//     GtkDrawingArea < GtkPassthroughFixed x7 < GtkPopoverContent < GtkPopover
//
// No GtkButton anywhere in the chain. The input had arrived at the popover and
// crossed into its content; it stopped at the decoration. Nothing about that was
// specific to popovers -- P50's panel is simply the only place in the test suite
// where a border wraps buttons.
//
// The same rule as gtk_passthrough_fixed_contains, for the same reason stated
// there: judge by whether anything made the widget interactive, not by what it
// is. A shape carrying `.onTapGesture` has a controller and keeps its whole area
// clickable.
//
// WHAT THIS DOES NOT CLAIM. `opaque` is the fill's visibility, not the fill's
// SHAPE, so a filled circle claims its bounding box rather than the disc. That
// is a real divergence from SwiftUI, which hit-tests the filled region. The
// exact version needs the path replayed into a scratch context and
// `cairo_in_fill` asked at hit time; it is not written, and this comment is here
// so nobody reads the current behaviour as the intended one. The same trade is
// already made for colour rectangles by gtk_passthrough_fixed_set_opaque.
//
// 只有在此路徑填了東西、或有什麼賦予它互動能力時，才攔截該點。
//
// **本檔為何存在，2026-09-10 實測。** `.border(color, width:)` 是
// `overlay { Rectangle().inset(by:).stroke(...) }`——一個疊加其上的路徑，由一個覆蓋整個 view 的
// GtkDrawingArea 繪製。而一般的 GtkDrawingArea 會攔截其配置範圍內的每一個點，因此邊框把每一次
// 原本要給它所包圍之物的點擊都拿走了。
//
// 它是循著任務 #111（「在 popover 內點擊沒有反應」）找到的。對 popover 呼叫 `gtk_widget_pick`，
// 沿中心線八個點中的七個回傳（見上方英文區塊）：鏈上**沒有任何 GtkButton**。輸入已經抵達 popover
// 並跨進了它的內容，它是停在**裝飾**上的。這一切與 popover 毫無關係——P50 的面板只不過是整個測試
// 套件中唯一「邊框包住按鈕」的地方。
//
// 判準與 gtk_passthrough_fixed_contains 相同，理由也記在該處：依據「是否有什麼賦予它互動能力」
// 判斷，而非依據「它是什麼」。帶有 `.onTapGesture` 的形狀有 controller，其整個範圍仍可點擊。
//
// **本檔不主張的事。** `opaque` 是填色的**可見性**，不是填色的**形狀**，因此一個填實的圓形攔截的
// 是它的外接矩形，而不是那個圓面。這是與 SwiftUI 之間一項真實的分歧——SwiftUI 命中測試的是填色
// 區域。精確的版本需要在命中時把路徑重放進一個暫存 context 並詢問 `cairo_in_fill`；那尚未寫出，
// 而這段註解存在的目的，是不讓任何人把目前的行為讀成「原本就打算這樣」。同樣的取捨，
// gtk_passthrough_fixed_set_opaque 早已為色塊做過一次。
static gboolean gtk_passthrough_drawing_area_contains(
    GtkWidget *widget, double x, double y
) {
    GtkPassthroughDrawingArea *self = (GtkPassthroughDrawingArea *)widget;

    if (!self->opaque) {
        GListModel *controllers = gtk_widget_observe_controllers(widget);
        guint count = g_list_model_get_n_items(controllers);
        g_object_unref(controllers);

        if (count == 0) {
            return FALSE;
        }
    }

    return GTK_WIDGET_CLASS(gtk_passthrough_drawing_area_parent_class)
        ->contains(widget, x, y);
}

void gtk_passthrough_drawing_area_set_opaque(GtkWidget *widget, gboolean opaque) {
    if (widget == NULL || !GTK_IS_PASSTHROUGH_DRAWING_AREA(widget)) {
        return;
    }
    ((GtkPassthroughDrawingArea *)widget)->opaque = opaque;
}

static void gtk_passthrough_drawing_area_class_init(
    GtkPassthroughDrawingAreaClass *klass
) {
    GTK_WIDGET_CLASS(klass)->contains = gtk_passthrough_drawing_area_contains;
}

static void gtk_passthrough_drawing_area_init(GtkPassthroughDrawingArea *self) {
    (void)self;
}

GtkWidget *gtk_passthrough_drawing_area_new(void) {
    return g_object_new(GTK_TYPE_PASSTHROUGH_DRAWING_AREA, NULL);
}
