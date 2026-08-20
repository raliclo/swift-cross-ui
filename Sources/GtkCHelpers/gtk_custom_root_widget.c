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
    switch (orientation) {
        case GTK_ORIENTATION_HORIZONTAL:
            *minimum = root_widget->minimum_width;
            *natural = 0;
            break;
        case GTK_ORIENTATION_VERTICAL:
            *minimum = root_widget->minimum_height;
            *natural = 0;
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

void gtk_custom_root_widget_preempt_allocated_size(
    GtkCustomRootWidget *self,
    gint allocated_width,
    gint allocated_height
) {
    self->allocated_width = allocated_width;
    self->allocated_height = allocated_height;
}

void gtk_custom_root_widget_set_resize_callback(
    GtkCustomRootWidget *self,
    void (*callback)(void*, CustomWidgetSize),
    void *data
) {
    self->resize_callback = callback;
    self->resize_callback_data = data;
}
