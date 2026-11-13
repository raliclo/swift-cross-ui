#include "gtk_helpers.h"

GtkWidget *wrapped_gtk_message_dialog_new() {
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return gtk_message_dialog_new(
        NULL,
        GTK_DIALOG_MODAL | GTK_DIALOG_DESTROY_WITH_PARENT,
        GTK_MESSAGE_INFO,
        GTK_BUTTONS_NONE,
        ""
    );
    #pragma clang diagnostic pop
}

GtkLabel *wrapped_gtk_widget_as_label(GtkWidget *widget) {
    if (widget == NULL || !GTK_IS_LABEL(widget)) {
        return NULL;
    }
    return GTK_LABEL(widget);
}

const GConnectFlags SHIM_G_CONNECT_AFTER = G_CONNECT_AFTER;
// Was `G_CONNECT_AFTER`, which is a different flag. Corrected 2026-09-11.
// Nothing reached it -- `ConnectFlags.swapped` in Signals.swift is an enum case
// with no caller -- so this changed no behaviour, which is exactly why it could
// sit here being wrong. A shim whose whole job is to carry one constant across
// the language boundary, carrying the wrong one, fails silently by
// construction: the call still connects, just not the way it was asked to.
// 原本寫的是 `G_CONNECT_AFTER`,那是另一個旗標。2026-09-11 更正。
// 沒有任何地方觸及它——Signals.swift 裡的 `ConnectFlags.swapped` 是一個沒有呼叫端的 enum case
// ——因此這次更正不改變任何行為;而那正是它得以在此處保持錯誤的原因。一個「唯一職責就是把某個常數
// 帶過語言邊界」的 shim,若帶錯了常數,其失敗方式在構造上就是沉默的:那個呼叫仍然會連接成功,
// 只是連接的方式與所要求的不同。
const GConnectFlags SHIM_G_CONNECT_SWAPPED = G_CONNECT_SWAPPED;
// `G_CONNECT_DEFAULT` is plain zero -- no AFTER, no SWAPPED -- and is what a
// signal wants when its handler is the mechanism rather than an addition to a
// default handler. GtkSignalListItemFactory's setup/bind/unbind are that case.
// `G_CONNECT_DEFAULT` 就是單純的零——不 AFTER、也不 SWAPPED——而當一個 signal 的 handler
// **本身就是那個機制**、而非附加在某個預設 handler 之後時,要的就是它。
// GtkSignalListItemFactory 的 setup/bind/unbind 正是這種情形。
const GConnectFlags SHIM_G_CONNECT_DEFAULT = G_CONNECT_DEFAULT;
const GApplicationFlags SHIM_G_APPLICATION_HANDLES_OPEN = G_APPLICATION_HANDLES_OPEN;

gboolean scui_primary_button_warps_slider(void) {
    gboolean warps = TRUE;
    g_object_get(gtk_settings_get_default(), "gtk-primary-button-warps-slider", &warps, NULL);
    return warps;
}

void scui_show_uri(const char *uri) {
#if GTK_CHECK_VERSION(4, 10, 0)
    // The GTask behind the launch holds its own reference to the launcher.
    // launch 背後的 GTask 自己持有 launcher 的參考。
    GtkUriLauncher *launcher = gtk_uri_launcher_new(uri);
    gtk_uri_launcher_launch(launcher, NULL, NULL, NULL, NULL);
    g_object_unref(launcher);
#else
    gtk_show_uri(NULL, uri, GDK_CURRENT_TIME);
#endif
}

void scui_css_provider_load(GtkCssProvider *provider, const char *data, gssize length) {
#if GTK_CHECK_VERSION(4, 12, 0)
    GBytes *bytes = g_bytes_new(data, (gsize)length);
    gtk_css_provider_load_from_bytes(provider, bytes);
    g_bytes_unref(bytes);
#else
    gtk_css_provider_load_from_data(provider, data, length);
#endif
}

GtkStyleContext *scui_widget_add_own_css_provider(GtkWidget *widget, GtkCssProvider *provider, guint priority) {
G_GNUC_BEGIN_IGNORE_DEPRECATIONS
    GtkStyleContext *context = gtk_widget_get_style_context(widget);
    gtk_style_context_add_provider(context, GTK_STYLE_PROVIDER(provider), priority);
G_GNUC_END_IGNORE_DEPRECATIONS
    g_object_ref(context);
    return context;
}

void scui_style_context_remove_own_css_provider(GtkStyleContext *context, GtkCssProvider *provider) {
G_GNUC_BEGIN_IGNORE_DEPRECATIONS
    gtk_style_context_remove_provider(context, GTK_STYLE_PROVIDER(provider));
G_GNUC_END_IGNORE_DEPRECATIONS
    g_object_unref(context);
}

void scui_calendar_set_date(GtkCalendar *calendar, GDateTime *date) {
#if GTK_CHECK_VERSION(4, 20, 0)
    gtk_calendar_set_date(calendar, date);
#else
    gtk_calendar_select_day(calendar, date);
#endif
}

void scui_dialog_add_button(GtkDialog *dialog, const char *label, int response_id) {
G_GNUC_BEGIN_IGNORE_DEPRECATIONS
    gtk_dialog_add_button(dialog, label, response_id);
G_GNUC_END_IGNORE_DEPRECATIONS
}
