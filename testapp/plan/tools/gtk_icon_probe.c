/* Asks GTK itself which icon names resolve, instead of reading a frozen spec.
 *
 * testapp/plan/symbol-table-v1.md dropped 21 of 28 candidates on the freedesktop
 * Icon Naming Specification, which carries 288 names frozen in the mid-2000s and
 * has nothing for edit, view, crop, more, share, upload, today, slideshow,
 * compass or directions. That document names querying a live theme with
 * gtk_icon_theme_has_icon as the highest-value next step and records that it
 * could not be done: no theme index was available to grep.
 *
 * GTK 4 is installed here, so it can be. This prints one line per candidate:
 * the name and whether the current display's icon theme resolves it.
 */
#include <gtk/gtk.h>
#include <stdio.h>

/* Names are read from argv so the probe outlives any one list. With no
 * arguments it prints the theme name and exits, which is the check worth
 * running first: a theme named Adwaita with no Adwaita package installed
 * answers out of GTK's built-in resource, and that answers a different
 * question than the one you asked.
 *
 * 名稱由 argv 讀入，使本探針的壽命長於任何一份特定清單。不帶引數執行時，它會印出主題名稱後結束，
 * 而那正是最該先跑的檢查：一個名為 Adwaita、但系統並未安裝 Adwaita 套件的主題，回答的是 GTK 內建
 * 資源，那與你所問的並不是同一個問題。
 */
static const char *unused_names[] = {
    "edit-clear", "document-edit", "document-edit-symbolic",
    "view-more", "view-more-symbolic", "view-more-horizontal-symbolic",
    "edit-cut", "edit-crop", "crop-symbolic",
    "send-to", "send-to-symbolic", "document-send", "document-send-symbolic",
    "share", "emblem-shared", "share-symbolic",
    "view-list", "view-list-symbolic", "view-grid-symbolic",
    "alarm", "alarm-symbolic", "clock", "clock-symbolic",
    "mark-location", "mark-location-symbolic", "find-location-symbolic",
    "compass", "compass-symbolic",
    "view-fullscreen", "view-refresh",
    "media-playback-start", "camera-photo",
    NULL,
};

int main(int argc, char **argv) {
    gtk_init();
    GdkDisplay *display = gdk_display_get_default();
    if (display == NULL) { printf("no display; cannot query a theme\n"); return 2; }
    GtkIconTheme *theme = gtk_icon_theme_get_for_display(display);
    printf("theme name: %s\n", gtk_icon_theme_get_theme_name(theme));
    int found = 0, total = 0;
    for (int i = 1; i < argc; i++) {
        gboolean has = gtk_icon_theme_has_icon(theme, argv[i]);
        printf("  %-34s %s\n", argv[i], has ? "YES" : "no");
        total++; if (has) found++;
    }
    printf("resolved %d of %d\n", found, total);
    return 0;
}
