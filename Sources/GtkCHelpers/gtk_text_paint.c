// Text painted with a gradient: SwiftUI's `.foregroundStyle(LinearGradient(...))`
// on a `Text`. GtkLabel is a final type, so it cannot draw this itself; the
// containers the label sits in (the passthrough fixed and the clipping fixed) do
// it when they snapshot their children. A child with a text paint is snapshotted
// as the alpha mask of a GSK mask node whose source is the gradient over the
// child's bounds, so the gradient shows exactly where the glyphs are.
//
// 以漸層上色的文字：`Text` 上的 SwiftUI `.foregroundStyle(LinearGradient(...))`。GtkLabel 是 final 型別，無法自己畫；
// 改由 label 所在的容器(passthrough fixed 與裁切 fixed)在 snapshot 子元件時處理。帶文字上色的子元件被 snapshot 成
// GSK mask 節點的 alpha 遮罩，來源是覆蓋該子元件外框的漸層，所以漸層恰好出現在字形所在之處。
#include "gtk_helpers.h"

#include <string.h>

#if GTK_CHECK_VERSION(4, 14, 0)
gboolean scui_append_gradient(
    GtkSnapshot *snapshot, const ScuiShapePaint *paint, const graphene_rect_t *box,
    const graphene_rect_t *area
);
#endif

static GQuark scui_text_paint_quark(void) {
    return g_quark_from_static_string("scui-text-paint");
}

static void scui_text_paint_free(gpointer data) {
    ScuiShapePaint *paint = data;
    g_free((gpointer)paint->stops);
    g_free(paint);
}

void scui_widget_set_text_paint(GtkWidget *widget, const ScuiShapePaint *paint) {
    if (paint == NULL || paint->kind == 0) {
        if (g_object_get_qdata(G_OBJECT(widget), scui_text_paint_quark()) != NULL) {
            g_object_set_qdata(G_OBJECT(widget), scui_text_paint_quark(), NULL);
            gtk_widget_queue_draw(widget);
        }
        return;
    }
    ScuiShapePaint *copy = g_new(ScuiShapePaint, 1);
    *copy = *paint;
    copy->stops = NULL;
    if (paint->stop_count > 0 && paint->stops != NULL) {
        double *stops = g_new(double, paint->stop_count * 5);
        memcpy(stops, paint->stops, sizeof(double) * paint->stop_count * 5);
        copy->stops = stops;
    } else {
        copy->stop_count = 0;
    }
    g_object_set_qdata_full(G_OBJECT(widget), scui_text_paint_quark(), copy, scui_text_paint_free);
    gtk_widget_queue_draw(widget);
}

gboolean scui_snapshot_children_painting_text(GtkWidget *widget, GtkSnapshot *snapshot) {
#if GTK_CHECK_VERSION(4, 14, 0)
    gboolean any = FALSE;
    for (GtkWidget *child = gtk_widget_get_first_child(widget); child != NULL;
         child = gtk_widget_get_next_sibling(child)) {
        if (g_object_get_qdata(G_OBJECT(child), scui_text_paint_quark()) != NULL) {
            any = TRUE;
            break;
        }
    }
    if (!any) {
        return FALSE;
    }
    for (GtkWidget *child = gtk_widget_get_first_child(widget); child != NULL;
         child = gtk_widget_get_next_sibling(child)) {
        const ScuiShapePaint *paint = g_object_get_qdata(G_OBJECT(child), scui_text_paint_quark());
        graphene_rect_t bounds;
        if (paint == NULL || !gtk_widget_compute_bounds(child, widget, &bounds)) {
            gtk_widget_snapshot_child(widget, child, snapshot);
            continue;
        }
        // The mask first, then the source. / 先遮罩，再來源。
        gtk_snapshot_push_mask(snapshot, GSK_MASK_MODE_ALPHA);
        gtk_widget_snapshot_child(widget, child, snapshot);
        gtk_snapshot_pop(snapshot);
        if (!scui_append_gradient(snapshot, paint, &bounds, &bounds)) {
            GdkRGBA colour = {
                (float)paint->rgba[0], (float)paint->rgba[1], (float)paint->rgba[2], (float)paint->rgba[3]
            };
            gtk_snapshot_append_color(snapshot, &colour, &bounds);
        }
        gtk_snapshot_pop(snapshot);
    }
    return TRUE;
#else
    (void)widget;
    (void)snapshot;
    return FALSE;
#endif
}
