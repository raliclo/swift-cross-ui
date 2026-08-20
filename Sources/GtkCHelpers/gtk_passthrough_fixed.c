// The declaration lives in gtk_helpers.h; see the note there for why it is not
// in a header of its own.
// 宣告位於 gtk_helpers.h；不另立標頭檔的理由記於該處。
#include "gtk_helpers.h"

#define GTK_TYPE_PASSTHROUGH_FIXED (gtk_passthrough_fixed_get_type())

// Spelled out because G_DEFINE_TYPE generates the get_type function but not the
// checking macros -- those come from the G_DECLARE_* family, which needs the
// struct in a header, and this type's struct is deliberately private to this
// file.
// 手動定義，因為 G_DEFINE_TYPE 只產生 get_type 函式，不產生型別檢查巨集——後者出自 G_DECLARE_*
// 系列，而該系列需要把 struct 放在標頭檔中，但此型別的 struct 刻意只存在於本檔案內。
#define GTK_IS_PASSTHROUGH_FIXED(obj) \
    (G_TYPE_CHECK_INSTANCE_TYPE((obj), GTK_TYPE_PASSTHROUGH_FIXED))

typedef struct _GtkPassthroughFixed {
    GtkFixed parent_instance;

    // Whether this one draws something. False for the structural containers
    // SwiftCrossUI's layout is built from, and set from the alpha channel for a
    // colour rectangle.
    // 此元件是否有繪製內容。SwiftCrossUI 版面所使用的結構性容器為 false；色塊則依其 alpha 通道
    // 設定。
    gboolean opaque;
} GtkPassthroughFixed;

typedef struct _GtkPassthroughFixedClass {
    GtkFixedClass parent_class;
} GtkPassthroughFixedClass;

G_DEFINE_TYPE(GtkPassthroughFixed, gtk_passthrough_fixed, GTK_TYPE_FIXED)

// Claims a point only if something has made this container interactive.
//
// GTK calls `contains` on a widget only after it has already offered the point
// to every child, so returning FALSE here removes the container from hit
// testing without hiding what it holds.
//
// The test is whether any event controller is attached. GtkBackend attaches a
// tap gesture to the widget it is asked to make tappable, so a stack carrying
// `.onTapGesture` has one and keeps its whole frame clickable, while a stack
// that is only structure has none and lets clicks through to whatever is
// behind it.
//
// 只有在此容器已被賦予互動能力時，才攔截該點。
//
// GTK 只會在把該點提供給所有子元件之後，才對 widget 呼叫 `contains`，因此在此回傳 FALSE 可將
// 容器自 hit testing 中移除，而不會遮蔽其所承載的內容。
//
// 判斷依據是「是否掛有任何 event controller」。GtkBackend 會把 tap gesture 掛在它被要求使其可
// 點擊的那個 widget 上，因此帶有 `.onTapGesture` 的 stack 會有 controller，其整個範圍仍可點擊；
// 而純粹作為結構的 stack 則沒有，點擊會穿透至其後方的元件。
static gboolean gtk_passthrough_fixed_contains(GtkWidget *widget, double x, double y) {
    GtkPassthroughFixed *self = (GtkPassthroughFixed *)widget;

    if (!self->opaque) {
        GListModel *controllers = gtk_widget_observe_controllers(widget);
        guint count = g_list_model_get_n_items(controllers);
        g_object_unref(controllers);

        if (count == 0) {
            return FALSE;
        }
    }

    return GTK_WIDGET_CLASS(gtk_passthrough_fixed_parent_class)->contains(widget, x, y);
}

void gtk_passthrough_fixed_set_opaque(GtkWidget *widget, gboolean opaque) {
    if (widget == NULL || !GTK_IS_PASSTHROUGH_FIXED(widget)) {
        return;
    }
    ((GtkPassthroughFixed *)widget)->opaque = opaque;
}

static void gtk_passthrough_fixed_class_init(GtkPassthroughFixedClass *klass) {
    GTK_WIDGET_CLASS(klass)->contains = gtk_passthrough_fixed_contains;
}

static void gtk_passthrough_fixed_init(GtkPassthroughFixed *self) {
    (void)self;
}

GtkWidget *gtk_passthrough_fixed_new(void) {
    return g_object_new(GTK_TYPE_PASSTHROUGH_FIXED, NULL);
}
