#ifndef __GTK_HELPERS_H__
#define __GTK_HELPERS_H__

#include <gtk/gtk.h>

#ifdef __cplusplus
extern "C" {
#endif /* __cplusplus */

GtkWidget *wrapped_gtk_message_dialog_new(void);

// GTK_IS_LABEL is a macro, so Swift cannot see it. Needed to walk a widget tree
// and act only on the labels in it: a table cell holds an arbitrary view, and
// text selection is a property of GtkLabel rather than of a container.
GtkLabel *wrapped_gtk_widget_as_label(GtkWidget *widget);

// A GtkFixed that does not claim pointer events for itself. Implemented in
// gtk_passthrough_fixed.c, which explains why it exists and how it works.
//
// Declared here rather than in its own header: SwiftPM builds this target as an
// umbrella *directory* module, and a header added to that directory was not
// picked up by an incremental build -- Swift reported "cannot find
// gtk_passthrough_fixed_new in scope" while the file sat next to the others that
// worked. Adding to a header the module already knows about avoids depending on
// that refresh.
//
// 一個不會為自己攔截指標事件的 GtkFixed。實作位於 gtk_passthrough_fixed.c，該處說明了它存在的
// 理由與運作方式。
//
// 宣告放在此處而非自己的標頭檔：SwiftPM 將此 target 建置為 umbrella *目錄* 模組，而新增至該目錄
// 的標頭檔在增量建置中不會被採納——Swift 回報 `cannot find gtk_passthrough_fixed_new in scope`，
// 而該檔案就放在其他可用標頭的旁邊。改為加入模組已知的標頭檔，即可避免依賴那次重整。
GtkWidget *gtk_passthrough_fixed_new(void);

// Marks a passthrough fixed as drawing something, so it claims the points it
// covers again. For colour rectangles: a transparent one should let clicks
// through, an opaque one should not.
//
// A flag read at hit time rather than a can-target call, for two reasons. It
// leaves can-target free for allowsHitTesting(), which would otherwise be
// fighting over the same bit. And it composes with the event-controller test in
// `contains`, so a transparent colour carrying a tap gesture stays clickable
// whichever order the colour and the gesture are applied in.
//
// 將某個 passthrough fixed 標記為「有繪製內容」，使其重新攔截所覆蓋的點。用於色塊：透明的應讓
// 點擊穿透，不透明的則不應。
//
// 採用「在 hit 時讀取的旗標」而非直接呼叫 can-target，有兩個理由。其一，這讓 can-target 保留給
// allowsHitTesting() 使用，否則兩者會爭奪同一個位元。其二，它能與 `contains` 中的 event
// controller 判斷組合運作，因此帶有 tap gesture 的透明色塊無論「顏色」與「手勢」以何種順序套用，
// 都仍可點擊。
void gtk_passthrough_fixed_set_opaque(GtkWidget *widget, gboolean opaque);

// Swift suddenly stopped finding these corresponding `G_*` enum members on its
// own on macOS. Weirdly everything worked in one command run, and then it started
// failing in the next (with identical code). Then when I tried recreating the
// issue on my Mac I could, even though I successfully built Gtk/Gtk3 a few days
// earlier... I'm perplexed, but this does at least solve the issue
extern const GConnectFlags SHIM_G_CONNECT_AFTER;
extern const GConnectFlags SHIM_G_CONNECT_SWAPPED;
extern const GApplicationFlags SHIM_G_APPLICATION_HANDLES_OPEN;

// Drag-and-drop (drop target) helpers. GtkDropTarget negotiates over GTypes,
// but the ones we want -- a string and a list of files -- are only reachable in
// C via macros (G_TYPE_STRING) or per-instance getters (GDK_TYPE_FILE_LIST),
// neither of which Swift can see. And a dropped GValue has to be turned into
// bytes, which means touching GdkFileList/GFile and the G_VALUE_HOLDS macros.
// All of that lives here so the Swift side deals only in GType and char*.
//
// Declared in this existing header, not a new one, for the umbrella-module
// reason noted above.
//
// 拖放（drop target）輔助函式。GtkDropTarget 以 GType 進行協商，但我們要的兩種——字串與檔案清單
// ——在 C 中只能透過巨集（G_TYPE_STRING）或每實例的 getter（GDK_TYPE_FILE_LIST）取得，兩者 Swift
// 都看不到。而放下的 GValue 也必須轉為位元組，這需碰觸 GdkFileList/GFile 與 G_VALUE_HOLDS 巨集。
// 這些全放在此處，讓 Swift 端只需處理 GType 與 char*。
//
// 宣告放於此既有標頭而非新標頭，理由同上方的 umbrella 模組註記。

// The GType a drop target should accept for plain UTF-8 text.
GType scui_gtype_string(void);

// The GType a drop target should accept for one or more files.
GType scui_gtype_file_list(void);

// The GdkDragAction bitmask for a copy -- the only action we request.
GdkDragAction scui_drag_action_copy(void);

// What kind of payload a dropped GValue carries: 1 = file list, 2 = string,
// 0 = neither (a type we did not offer, so the caller should refuse it).
int scui_drop_value_kind(const GValue *value);

// For a file-list value, a newly-allocated text/uri-list: CRLF-separated
// file:// URIs, one per file. NULL if the value is not a file list. The caller
// owns the result and must g_free it.
char *scui_drop_value_uri_list(const GValue *value);

// For a string value, a newly-allocated copy of it. NULL if the value is not a
// string. The caller owns the result and must g_free it.
char *scui_drop_value_string(const GValue *value);

#ifdef __cplusplus
}
#endif /* __cplusplus */

#endif /* __GTK_HELPERS_H__ */
