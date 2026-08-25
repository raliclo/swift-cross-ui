#include "gtk_helpers.h"

// See gtk_helpers.h for why these exist: GtkDropTarget negotiates over GTypes
// and hands back a GValue, and both the types and the value unpacking need
// macros/getters that Swift cannot reach.

GType scui_gtype_string(void) {
    return G_TYPE_STRING;
}

GType scui_gtype_file_list(void) {
    return GDK_TYPE_FILE_LIST;
}

GdkDragAction scui_drag_action_copy(void) {
    return GDK_ACTION_COPY;
}

int scui_drop_value_kind(const GValue *value) {
    if (value == NULL) {
        return 0;
    }
    if (G_VALUE_HOLDS(value, GDK_TYPE_FILE_LIST)) {
        return 1;
    }
    if (G_VALUE_HOLDS_STRING(value)) {
        return 2;
    }
    return 0;
}

char *scui_drop_value_uri_list(const GValue *value) {
    if (value == NULL || !G_VALUE_HOLDS(value, GDK_TYPE_FILE_LIST)) {
        return NULL;
    }
    GdkFileList *list = g_value_get_boxed(value);
    if (list == NULL) {
        return NULL;
    }

    // gdk_file_list_get_files transfers the container (the GSList) but not the
    // GFiles, so g_slist_free the list and leave the files alone.
    GSList *files = gdk_file_list_get_files(list);
    GString *out = g_string_new(NULL);
    for (GSList *node = files; node != NULL; node = node->next) {
        GFile *file = node->data;
        char *uri = g_file_get_uri(file);
        if (uri != NULL) {
            g_string_append(out, uri);
            g_string_append(out, "\r\n");
            g_free(uri);
        }
    }
    g_slist_free(files);

    // g_string_free(_, FALSE) hands back the char* buffer for the caller to own.
    return g_string_free(out, FALSE);
}

char *scui_drop_value_string(const GValue *value) {
    if (value == NULL || !G_VALUE_HOLDS_STRING(value)) {
        return NULL;
    }
    const char *string = g_value_get_string(value);
    return string != NULL ? g_strdup(string) : NULL;
}
