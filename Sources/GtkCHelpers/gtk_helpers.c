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
const GConnectFlags SHIM_G_CONNECT_SWAPPED = G_CONNECT_AFTER;
const GApplicationFlags SHIM_G_APPLICATION_HANDLES_OPEN = G_APPLICATION_HANDLES_OPEN;
