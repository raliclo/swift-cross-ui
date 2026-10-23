// first-frame-stall.c -- a GTK 4 window that starts drawing something new after
// 0.5 s and prints how long each frame took, to show that the first frame with
// new draw state stalls in every process on Mesa's d3d12 driver.
//
//   cc first-frame-stall.c -o first-frame-stall $(pkg-config --cflags --libs gtk4)
//   GALLIUM_DRIVER=d3d12 GDK_BACKEND=x11 ./first-frame-stall
//
// Output: one line per frame longer than 30 ms, then a summary line. The
// program quits by itself after 3 s.
#include <gtk/gtk.h>

static GtkWidget *fixed, *box;
static gint64 start_us, frame_start_us, worst_us, worst_at_us;
static int frames, slow_frames;
static gboolean moving;

static void on_before_paint(GdkFrameClock *clock, gpointer data) {
    (void)clock; (void)data;
    frame_start_us = g_get_monotonic_time();
}

static void on_after_paint(GdkFrameClock *clock, gpointer data) {
    (void)clock; (void)data;
    gint64 now = g_get_monotonic_time();
    gint64 took = now - frame_start_us;
    if (!moving)
        return;
    frames++;
    if (took > worst_us) {
        worst_us = took;
        worst_at_us = frame_start_us - start_us;
    }
    if (took > 30000) {
        slow_frames++;
        g_print("slow frame %d at %.3f s: %.1f ms\n", frames,
                (frame_start_us - start_us) / 1e6, took / 1000.0);
    }
}

static gboolean tick(GtkWidget *widget, GdkFrameClock *clock, gpointer data) {
    (void)widget; (void)data;
    double t = (gdk_frame_clock_get_frame_time(clock) - start_us) / 1e6;
    GskTransform *transform = gsk_transform_translate(NULL, &GRAPHENE_POINT_INIT(40 + 200 * (t - 0.5) / 2.5, 120));
    transform = gsk_transform_rotate(transform, 90 * t);
    gtk_fixed_set_child_transform(GTK_FIXED(fixed), box, transform);
    gsk_transform_unref(transform);
    return G_SOURCE_CONTINUE;
}

static gboolean start_moving(gpointer data) {
    (void)data;
    // New draw state: a rounded box with a shadow, under a rotation.
    box = gtk_label_new("moving");
    gtk_widget_add_css_class(box, "mover");
    gtk_fixed_put(GTK_FIXED(fixed), box, 0, 0);
    moving = TRUE;
    gtk_widget_add_tick_callback(fixed, tick, NULL, NULL);
    return G_SOURCE_REMOVE;
}

static gboolean finish(gpointer app) {
    g_print("frames %d, slow (>30 ms) %d, worst %.1f ms at %.3f s\n", frames, slow_frames,
            worst_us / 1000.0, worst_at_us / 1e6);
    g_application_quit(G_APPLICATION(app));
    return G_SOURCE_REMOVE;
}

static void on_map(GtkWidget *window, gpointer app) {
    GdkFrameClock *clock = gtk_widget_get_frame_clock(window);
    g_signal_connect(clock, "before-paint", G_CALLBACK(on_before_paint), NULL);
    g_signal_connect(clock, "after-paint", G_CALLBACK(on_after_paint), NULL);
    start_us = g_get_monotonic_time();
    g_timeout_add(500, start_moving, NULL);
    g_timeout_add(3000, finish, app);
}

static void activate(GtkApplication *app, gpointer data) {
    (void)data;
    GtkCssProvider *css = gtk_css_provider_new();
    gtk_css_provider_load_from_string(css,
        ".mover { background: #3366cc; color: white; padding: 12px; border-radius: 10px;"
        " box-shadow: 0 4px 12px rgba(0,0,0,0.5); }");
    gtk_style_context_add_provider_for_display(gdk_display_get_default(), GTK_STYLE_PROVIDER(css),
                                               GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    GtkWidget *window = gtk_application_window_new(app);
    gtk_window_set_default_size(GTK_WINDOW(window), 400, 300);
    fixed = gtk_fixed_new();
    gtk_fixed_put(GTK_FIXED(fixed), gtk_label_new("first-frame-stall: static text"), 20, 20);
    gtk_fixed_put(GTK_FIXED(fixed), gtk_button_new_with_label("a button"), 20, 50);
    gtk_window_set_child(GTK_WINDOW(window), fixed);
    g_signal_connect(window, "map", G_CALLBACK(on_map), app);
    gtk_window_present(GTK_WINDOW(window));
}

int main(int argc, char **argv) {
    GtkApplication *app = gtk_application_new(NULL, G_APPLICATION_NON_UNIQUE);
    g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
    int status = g_application_run(G_APPLICATION(app), argc, argv);
    g_object_unref(app);
    return status;
}
