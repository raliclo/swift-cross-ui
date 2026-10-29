// Moves the keyboard focus out of a subtree before it is detached.
//
// See the declaration in include/gtk_helpers.h for the GTK defect this works
// around.
//
// 在子樹被拆下之前，把鍵盤焦點移出它。所繞過的 GTK 缺陷見 include/gtk_helpers.h 的宣告。

#include "include/gtk_helpers.h"

void scui_release_focus_within(GtkWidget *widget) {
    if (widget == NULL) {
        return;
    }
    GtkRoot *root = gtk_widget_get_root(widget);
    if (root == NULL) {
        return;
    }
    GtkWidget *focus = gtk_root_get_focus(root);
    if (focus == NULL) {
        return;
    }
    if (focus == widget || gtk_widget_is_ancestor(focus, widget)) {
        gtk_root_set_focus(root, NULL);
    }
}
