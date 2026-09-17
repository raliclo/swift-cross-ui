// Keeps a removed pointing device alive. See the declaration in
// include/gtk_helpers.h for the crash this exists to stop.
// 讓被移除的指向裝置繼續存活。這支檔案要擋住的崩潰,見 include/gtk_helpers.h 中的宣告。

#include "include/gtk_helpers.h"

static void scui_on_device_removed(GdkSeat *seat, GdkDevice *device, gpointer data) {
    (void)seat;
    (void)data;
    // Never released: GTK's own references go away regardless, and whatever
    // still holds the raw pointer has no signal telling us when it stops.
    // 永不釋放:GTK 自己的參考照樣會消失,而仍握著裸指標的那一方,並沒有任何信號告訴我們它何時放手。
    g_object_ref(device);
}

void scui_retain_removed_devices(void) {
    GdkDisplay *display = gdk_display_get_default();
    if (display == NULL) {
        return;
    }
    GdkSeat *seat = gdk_display_get_default_seat(display);
    if (seat == NULL) {
        return;
    }
    g_signal_connect(seat, "device-removed", G_CALLBACK(scui_on_device_removed), NULL);
}
