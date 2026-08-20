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

// Swift suddenly stopped finding these corresponding `G_*` enum members on its
// own on macOS. Weirdly everything worked in one command run, and then it started
// failing in the next (with identical code). Then when I tried recreating the
// issue on my Mac I could, even though I successfully built Gtk/Gtk3 a few days
// earlier... I'm perplexed, but this does at least solve the issue
extern const GConnectFlags SHIM_G_CONNECT_AFTER;
extern const GConnectFlags SHIM_G_CONNECT_SWAPPED;
extern const GApplicationFlags SHIM_G_APPLICATION_HANDLES_OPEN;

#ifdef __cplusplus
}
#endif /* __cplusplus */

#endif /* __GTK_HELPERS_H__ */
