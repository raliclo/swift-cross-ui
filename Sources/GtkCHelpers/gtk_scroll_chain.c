// A wheel scroll across a one-axis GtkScrolledWindow reaches the scroll view
// around it, on GTK versions that swallow it.
//
// See the declaration in include/gtk_helpers.h for the measurement.
//
// 在會吞掉事件的 GTK 版本上，讓橫越單軸 GtkScrolledWindow 的滾輪捲動送達外圍的捲動視圖。測量結果見 include/gtk_helpers.h 的宣告。

#include "include/gtk_helpers.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

// Whether this GTK needs the forwarding: before 4.20.1, or forced with
// SCUI_GTK_SCROLL_CHAIN=1 (=0 turns it off), so the forwarding can be tried on
// a GTK that does not need it.
// 這個 GTK 是否需要轉交:4.20.1 之前，或以 SCUI_GTK_SCROLL_CHAIN=1 強制開啟(=0 關閉),好在不需要它的 GTK 上試驗轉交。
static gboolean scui_scroll_chain_needed(void) {
    const char *forced = g_getenv("SCUI_GTK_SCROLL_CHAIN");
    if (forced != NULL && strcmp(forced, "1") == 0) {
        return TRUE;
    }
    if (forced != NULL && strcmp(forced, "0") == 0) {
        return FALSE;
    }
    return gtk_check_version(4, 20, 1) != NULL;
}

// The nearest ancestor scrolled window that scrolls along the given axis.
// 沿指定軸捲動、最近的祖先 scrolled window。
static GtkScrolledWindow *scui_scroll_chain_target(GtkWidget *from, gboolean vertical) {
    for (GtkWidget *widget = gtk_widget_get_parent(from); widget != NULL;
         widget = gtk_widget_get_parent(widget)) {
        if (!GTK_IS_SCROLLED_WINDOW(widget)) {
            continue;
        }
        GtkPolicyType horizontal_policy, vertical_policy;
        gtk_scrolled_window_get_policy(GTK_SCROLLED_WINDOW(widget), &horizontal_policy, &vertical_policy);
        if ((vertical ? vertical_policy : horizontal_policy) != GTK_POLICY_NEVER) {
            return GTK_SCROLLED_WINDOW(widget);
        }
    }
    return NULL;
}

static gboolean scui_scroll_chain_scroll(GtkEventControllerScroll *controller, double dx, double dy,
                                         gpointer data) {
    (void)data;
    GtkWidget *widget = gtk_event_controller_get_widget(GTK_EVENT_CONTROLLER(controller));
    GtkPolicyType horizontal_policy, vertical_policy;
    gtk_scrolled_window_get_policy(GTK_SCROLLED_WINDOW(widget), &horizontal_policy, &vertical_policy);
    gboolean scrolls_horizontally = horizontal_policy != GTK_POLICY_NEVER;
    gboolean scrolls_vertically = vertical_policy != GTK_POLICY_NEVER;

    // Shift turns a vertical wheel into a horizontal scroll in GTK, which is
    // the strip's own direction, so it stays with the strip.
    // 在 GTK 中 Shift 會把垂直滾輪變成水平捲動，那正是長條自己的方向，所以留給長條。
    GdkModifierType state = gtk_event_controller_get_current_event_state(GTK_EVENT_CONTROLLER(controller));
    if (state & GDK_SHIFT_MASK) {
        return FALSE;
    }

    gboolean vertical;
    double delta;
    if (scrolls_horizontally && !scrolls_vertically && dy != 0 && dx == 0) {
        vertical = TRUE;
        delta = dy;
    } else if (scrolls_vertically && !scrolls_horizontally && dx != 0 && dy == 0) {
        vertical = FALSE;
        delta = dx;
    } else {
        return FALSE;
    }

    GtkScrolledWindow *target = scui_scroll_chain_target(widget, vertical);
    if (target == NULL) {
        return FALSE;
    }
    GtkAdjustment *adjustment = vertical ? gtk_scrolled_window_get_vadjustment(target)
                                         : gtk_scrolled_window_get_hadjustment(target);
    double page = gtk_adjustment_get_page_size(adjustment);
    // GTK's own wheel step, page^(2/3) per notch (scrolled_window_scroll);
    // surface units (a touchpad) are already pixels.
    // GTK 自己的滾輪步幅，每格 page^(2/3)(scrolled_window_scroll);surface 單位(觸控板)本來就是像素。
    if (gtk_event_controller_scroll_get_unit(controller) == GDK_SCROLL_UNIT_WHEEL) {
        delta *= pow(page, 2.0 / 3.0);
    }
    double lower = gtk_adjustment_get_lower(adjustment);
    double upper = gtk_adjustment_get_upper(adjustment) - page;
    double value = gtk_adjustment_get_value(adjustment) + delta;
    gtk_adjustment_set_value(adjustment, value < lower ? lower : (value > upper ? upper : value));
    return TRUE;
}

void scui_scrolled_window_chain_cross_axis_wheel(GtkWidget *scrolled_window) {
    if (!GTK_IS_SCROLLED_WINDOW(scrolled_window) || !scui_scroll_chain_needed()) {
        return;
    }
    if (g_object_get_data(G_OBJECT(scrolled_window), "scui-scroll-chain") != NULL) {
        return;
    }
    g_object_set_data(G_OBJECT(scrolled_window), "scui-scroll-chain", GINT_TO_POINTER(1));
    GtkEventController *controller =
        gtk_event_controller_scroll_new(GTK_EVENT_CONTROLLER_SCROLL_BOTH_AXES);
    // Capture runs before the scrolled window's own bubble-phase controller,
    // which is the one that returns GDK_EVENT_STOP on 4.14.
    // capture 階段比 scrolled window 自己的 bubble 階段控制器先執行，4.14 上回傳 GDK_EVENT_STOP 的正是後者。
    gtk_event_controller_set_propagation_phase(controller, GTK_PHASE_CAPTURE);
    g_signal_connect(controller, "scroll", G_CALLBACK(scui_scroll_chain_scroll), NULL);
    gtk_widget_add_controller(scrolled_window, controller);
}
