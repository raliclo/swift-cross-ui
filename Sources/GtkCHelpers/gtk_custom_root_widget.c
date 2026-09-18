#include "gtk_custom_root_widget.h"

G_DEFINE_FINAL_TYPE(GtkCustomRootWidget, gtk_custom_root_widget, GTK_TYPE_WIDGET)

static void gtk_custom_root_widget_init(GtkCustomRootWidget *self) {}

static void gtk_custom_root_widget_class_init(GtkCustomRootWidgetClass *klass) {
    GtkWidgetClass *widget_class = GTK_WIDGET_CLASS (klass);
    widget_class->measure = gtk_custom_root_widget_measure;
    widget_class->size_allocate = gtk_custom_root_widget_allocate;
    widget_class->get_request_mode = gtk_custom_root_widget_size_request_mode;
}

GtkSizeRequestMode gtk_custom_root_widget_size_request_mode(GtkWidget *widget) {
    return GTK_SIZE_REQUEST_HEIGHT_FOR_WIDTH;
}

void gtk_custom_root_widget_measure(
    GtkWidget *widget,
    GtkOrientation orientation,
    int for_size,
    int *minimum,
    int *natural,
    int *minimum_baseline,
    int *natural_baseline
) {
    GtkCustomRootWidget *root_widget = GTK_CUSTOM_ROOT_WIDGET(widget);
    // Natural must be >= minimum, or GTK warns on every measure pass. It used to
    // be safe to report 0 because the minimum was also 0; now that the minimum
    // carries the window's content minimum (so the window cannot be shrunk into
    // its content), the natural size has to match it. SwiftCrossUI decides the
    // real allocation separately via preempt_allocated_size, so the value here
    // only needs to satisfy the invariant.
    switch (orientation) {
        case GTK_ORIENTATION_HORIZONTAL:
            *minimum = root_widget->minimum_width;
            *natural = root_widget->minimum_width;
            break;
        case GTK_ORIENTATION_VERTICAL:
            *minimum = root_widget->minimum_height;
            *natural = root_widget->minimum_height;
            break;
    }
}

void gtk_custom_root_widget_allocate(
    GtkWidget *widget,
    int width,
    int height,
    int baseline
) {
    GtkCustomRootWidget *root_widget = GTK_CUSTOM_ROOT_WIDGET(widget);

    // GTK 4 requires a container to measure a child before allocating it, and
    // this went straight to gtk_widget_allocate. The result was a warning on
    // every single layout pass:
    //
    //   Allocating size to GtkFixed without calling gtk_widget_measure().
    //   How does the code know the size to allocate?
    //
    // The measurements are discarded here on purpose. SwiftCrossUI has already
    // decided the layout and this widget's job is to hand that decision down;
    // the call exists because GTK caches the result and refuses to allocate
    // sensibly without it, not because the numbers are wanted.
    //
    // GTK 4 要求容器在配置子元件之前必須先量測它，而此處先前直接呼叫了
    // gtk_widget_allocate。結果是每一次 layout pass 都會產生警告（如上）。
    //
    // 此處刻意捨棄量測結果。SwiftCrossUI 早已決定好版面，本 widget 的職責只是把該決定往下
    // 傳遞；這次呼叫的存在是因為 GTK 會快取其結果、且少了它便無法正常配置，而非因為需要
    // 這些數值。
    // `child` starts NULL in gtk_custom_root_widget_new, and gtk_widget_measure
    // asserts on NULL rather than returning, so the two measure calls above are
    // unsafe until a child is set. The original gtk_widget_allocate had the same
    // exposure and had simply never been reached that way.
    //
    // Added on a theory that this was killing P11 at startup. It was not -- P11
    // turned out to be an assertionFailure over an unsupported picker style, and
    // this guard changed nothing about it. Kept because the hazard is real on
    // its own terms, not because it was observed to fire.
    //
    // `child` 在 gtk_custom_root_widget_new 中被初始化為 NULL，而 gtk_widget_measure 對 NULL 會
    // 觸發 assert 而非直接返回，因此在子元件設定之前，上方的兩次 measure 呼叫並不安全。原本的
    // gtk_widget_allocate 有相同的暴露面，只是從未以那種方式被觸及。
    //
    // 此防護最初是基於「它導致 P11 在啟動時死亡」的假設而加入。事實並非如此——P11 的真正成因是
    // 對不支援的 picker 樣式所觸發的 assertionFailure，而本防護對它毫無影響。保留的理由是該風險
    // 本身確實存在，而非因為曾觀察到它被觸發。
    if (root_widget->child == NULL) {
        root_widget->has_been_allocated = true;
        return;
    }

    int ignored_minimum, ignored_natural, ignored_min_baseline, ignored_nat_baseline;
    gtk_widget_measure(
        root_widget->child, GTK_ORIENTATION_HORIZONTAL, -1,
        &ignored_minimum, &ignored_natural,
        &ignored_min_baseline, &ignored_nat_baseline
    );
    gtk_widget_measure(
        root_widget->child, GTK_ORIENTATION_VERTICAL, width,
        &ignored_minimum, &ignored_natural,
        &ignored_min_baseline, &ignored_nat_baseline
    );

    gtk_widget_allocate(root_widget->child, width, height, 0, NULL);

    root_widget->has_been_allocated = true;

    if (width == root_widget->allocated_width && height == root_widget->allocated_height) {
        return;
    }

    root_widget->allocated_width = width;
    root_widget->allocated_height = height;

    if (root_widget->resize_callback != NULL) {
        CustomWidgetSize size = { .width = width, .height = height };
        root_widget->resize_callback(root_widget->resize_callback_data, size);
    }
}

GtkWidget *gtk_custom_root_widget_new(void) {
    GtkCustomRootWidget *widget = g_object_new(GTK_CUSTOM_ROOT_WIDGET_TYPE, NULL);
    widget->child = NULL;
    widget->resize_callback = NULL;
    widget->resize_callback_data = NULL;
    widget->minimum_width = 0;
    widget->minimum_height = 0;
    widget->allocated_width = 0;
    widget->allocated_height = 0;
    widget->has_been_allocated = false;

    return GTK_WIDGET(widget);
}

void gtk_custom_root_widget_set_child(GtkCustomRootWidget *self, GtkWidget *child) {
    self->child = child;
    gtk_widget_set_parent(child, GTK_WIDGET(self));
}

void gtk_custom_root_widget_get_size(GtkCustomRootWidget *widget, gint *width, gint *height) {
    if (widget->has_been_allocated) {
        *width = widget->allocated_width;
        *height = widget->allocated_height;
    } else {
        *width = 0;
        *height = 0;
    }
}

void gtk_custom_root_widget_set_minimum_size(
    GtkCustomRootWidget *self,
    gint minimum_width,
    gint minimum_height
) {
    self->minimum_width = minimum_width;
    self->minimum_height = minimum_height;
    gtk_widget_queue_resize(GTK_WIDGET(self));
}

// A preempted size must be READABLE, which is the whole point of preempting it.
//
// This wrote the two numbers and left `has_been_allocated` false, so
// `gtk_custom_root_widget_get_size` kept answering 0x0 until GTK's own
// allocation arrived. `GtkBackend.size(ofWindow:)` reads exactly that, and
// `WindowReference` proposes it as the window size on every update triggered
// before the first allocation.
//
// Measured 2026-09-18 with `SCUI_DEBUG_WINDOW_SIZE=1` on P52, whose benchmark
// updates the window immediately: pass 1 proposed 1000x900 (its `.defaultSize`),
// pass 2 proposed **0x0**, and the window settled at `max(minimum 724x0, 0x0)`
// -- 752x68 on screen, a title bar with nothing under it. Resized by hand the
// content drew correctly, so only the size was ever wrong. P51 and P54, which
// have the same ScrollView root but no early update, were unaffected, and WinUI
// proposed 1000x900 on all three passes.
//
// 被預先設定的尺寸必須讀得到,那正是「預先設定」的全部用意。
//
// 此處原本只寫入兩個數字、卻讓 `has_been_allocated` 維持 false,於是在 GTK 自己的配置抵達之前,
// `gtk_custom_root_widget_get_size` 一直回答 0x0。`GtkBackend.size(ofWindow:)` 讀的正是它,而
// `WindowReference` 會把它當成視窗尺寸提議出去——只要有任何一次更新發生在第一次配置之前。
//
// 2026-09-18 以 `SCUI_DEBUG_WINDOW_SIZE=1` 在 P52 上量到(它的基準測試會立刻觸發視窗更新):第一趟提議
// 1000x900(它的 `.defaultSize`),第二趟提議 **0x0**,視窗於是停在 `max(最小 724x0, 0x0)`——畫面上是
// 752x68,一條標題列、底下什麼都沒有。手動放大後內容繪製完全正常,錯的自始至終只有尺寸。P51 與 P54 有同樣的
// ScrollView root 但沒有那麼早的更新,因此不受影響;WinUI 三趟都提議 1000x900。
void gtk_custom_root_widget_preempt_allocated_size(
    GtkCustomRootWidget *self,
    gint allocated_width,
    gint allocated_height
) {
    self->allocated_width = allocated_width;
    self->allocated_height = allocated_height;
    self->has_been_allocated = true;
}

void gtk_custom_root_widget_set_resize_callback(
    GtkCustomRootWidget *self,
    void (*callback)(void*, CustomWidgetSize),
    void *data
) {
    self->resize_callback = callback;
    self->resize_callback_data = data;
}
