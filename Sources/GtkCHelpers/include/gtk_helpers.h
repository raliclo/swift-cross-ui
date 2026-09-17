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

// A GtkDrawingArea that does not claim pointer events for a path it did not
// fill. Implemented in gtk_passthrough_drawing_area.c, which records the
// measurement it came from.
//
// The container version above was not enough: `.border(_:width:)` is an
// overlaid stroked Rectangle, so the widget in the hit path is a DRAWING AREA,
// not a Fixed, and a plain one claims its whole allocation. Task #111 -- "a
// click inside a popover does nothing" -- was that border swallowing every
// click meant for the buttons it surrounded.
//
// Declared here rather than in its own header, for the umbrella-module reason
// recorded above gtk_passthrough_fixed_new -- and that note now covers SOURCE
// files too. Adding gtk_passthrough_drawing_area.c to this directory on
// 2026-09-10 produced `lld-link: error: undefined symbol:
// gtk_passthrough_drawing_area_new` from an incremental build: the declaration
// was visible, the definition was never compiled, and the failure reads as a
// missing library rather than a stale file list. `touch Package.swift` forces
// the replan that picks it up. Worth the two lines, because the error names the
// symbol and says nothing about the file that was skipped.
//
// 此宣告放在此處而非自己的標頭檔,理由同 gtk_passthrough_fixed_new 上方所記——而該註記現在也涵蓋
// **原始檔**。2026-09-10 將 gtk_passthrough_drawing_area.c 加入本目錄後,增量建置產生了
// `lld-link: error: undefined symbol: gtk_passthrough_drawing_area_new`:宣告看得見,定義卻從未
// 被編譯,而該錯誤讀起來像是缺少函式庫,而不是一份過期的檔案清單。`touch Package.swift` 可強制
// 重新規劃並納入它。值得寫這兩行,因為錯誤訊息指名的是符號,對「被略過的那個檔案」隻字未提。
//
// 一個不會為「自己並未填色的路徑」攔截指標事件的 GtkDrawingArea。實作位於
// gtk_passthrough_drawing_area.c，該處記錄了它所源自的那次量測。
//
// 上方的容器版本並不足夠：`.border(_:width:)` 是一個疊加其上、帶描邊的 Rectangle，因此位於命中
// 路徑上的 widget 是一個 **drawing area** 而非 Fixed，而一般的 drawing area 會攔截其整個配置範圍。
// 任務 #111——「在 popover 內點擊沒有反應」——正是那個邊框吞掉了每一次原本要給它所包圍之按鈕的點擊。
//
// 宣告放在此處而非自己的標頭檔，理由同 gtk_passthrough_fixed_new 上方所記的 umbrella 模組註記。
GtkWidget *gtk_passthrough_drawing_area_new(void);

// Marks a path widget as filling something, so it claims the points it covers
// again. A stroke-only path -- a border -- should let clicks through; a filled
// shape should not.
//
// 將某個路徑 widget 標記為「有填色」，使其重新攔截所覆蓋的點。只有描邊的路徑——例如邊框——應讓
// 點擊穿透；填實的形狀則不應。
void gtk_passthrough_drawing_area_set_opaque(GtkWidget *widget, gboolean opaque);

// A GtkFixed that clips its children to its own size request rather than letting
// them draw past it. This is the #389 clip: a plain GtkFixed measures to the
// bounding box of its children, so a child larger than the frame makes the
// container get allocated the child's size, and overflow: hidden then clips to
// that larger box -- i.e. not at all. This widget's measure returns its
// size request instead, so the allocation is the frame, and it also pushes a
// clip in snapshot so the cut happens regardless.
//
// 一個會將子元件裁切至「自身 size request」的 GtkFixed,而非任由子元件畫到框外。此即 #389 的裁切:
// 一般 GtkFixed 會 measure 成其子元件的外接框,因此比框更大的子元件會使容器被 allocate 成子元件的
// 尺寸,overflow: hidden 便裁到那個較大的框——形同沒裁。此 widget 的 measure 改為回傳其 size
// request,使 allocation 即為該框,並於 snapshot 中推入 clip,確保裁切確實發生。
GtkWidget *scui_clip_fixed_new(void);

// Sets the corner radius the clip follows. Zero, the default, clips to a plain
// rectangle -- what `clipped()` asks for. A positive radius makes the clip follow
// the rounded border, so `cornerRadius(r)` cuts the child to the rounded shape
// instead of leaving square corners showing underneath it.
//
// 設定裁切所依循的圓角半徑。預設為零，裁切為純矩形——即 `clipped()` 所要求者。正值會使裁切沿著
// 圓角邊框進行，因此 `cornerRadius(r)` 會將子元件裁成圓角形狀，而非在其下留下方形的角。
void scui_clip_fixed_set_corner_radius(GtkWidget *widget, int radius);

// Pins a window above every other window, or releases it. Returns whether the
// platform could honour the request at all.
//
// GTK 4 has no always-on-top API of its own: gtk_window_set_keep_above was GTK 3
// and was removed. On Windows that does not matter, because a GTK window is an
// ordinary HWND underneath and SetWindowPos works on it -- but reaching the HWND
// means gdk_win32_surface_get_handle, which lives behind a platform header Swift
// cannot see. Hence a helper: Swift passes a widget and a bool.
//
// On every other platform this returns FALSE and does nothing. Under Wayland a
// client cannot raise itself above another application by design. X11 has
// _NET_WM_STATE_ABOVE, which would work where the window manager implements it
// -- but WSLg's does not: measured 2026-08-26, its root _NET_SUPPORTED lists
// only _NET_WM_MOVERESIZE, _NET_WM_STATE, _NET_WM_STATE_FULLSCREEN and the two
// MAXIMIZED atoms. Re-check with `xprop -root _NET_SUPPORTED` before assuming
// that is still true, or before assuming it holds on a desktop Linux where it
// usually would.
//
// 將視窗釘在所有視窗之上，或解除之。回傳該平台是否有能力實現此請求。
//
// GTK 4 本身沒有置頂 API：gtk_window_set_keep_above 屬於 GTK 3 且已被移除。在 Windows 上這無妨，
// 因為 GTK 視窗底層就是一個普通的 HWND，SetWindowPos 對它有效——但要取得該 HWND 需要
// gdk_win32_surface_get_handle，而它位於 Swift 看不到的平台專屬標頭之後。因此設此輔助函式：
// Swift 只需傳入一個 widget 與一個 bool。
//
// 在其他所有平台上，此函式回傳 FALSE 且不做任何事。Wayland 依設計不允許 client 把自己抬到其他
// 應用程式之上。X11 有 _NET_WM_STATE_ABOVE，在窗口管理員有實作之處是可行的——但 WSLg 的並沒有：
// 實測於 2026-08-26，其 root 的 _NET_SUPPORTED 只列出 _NET_WM_MOVERESIZE、_NET_WM_STATE、
// _NET_WM_STATE_FULLSCREEN 與兩個 MAXIMIZED atom。在假定此事仍然成立之前，或在假定它於「通常會
// 支援」的桌面 Linux 上亦然之前，請以 `xprop -root _NET_SUPPORTED` 重新確認。
gboolean scui_window_set_topmost(GtkWidget *window, gboolean topmost);

// Asks Windows for a dark or light title bar. Returns whether the platform
// could honour it.
//
// Only Windows needs this, and only because a GTK window there wears a native
// Win32 title bar that knows nothing about GTK's theme. So a dark GTK app gets
// a light bar with dark buttons -- the one part of the window that visibly did
// not get the message. `DwmSetWindowAttribute` with
// DWMWA_USE_IMMERSIVE_DARK_MODE is what tells the compositor otherwise.
//
// The attribute is 20 on Windows 10 2004 and later, and was 19 on 1809. Both
// are tried, cheaply, because passing an unsupported attribute is an error
// return rather than a crash, and getting it wrong on an older build would show
// up as "the setting silently does nothing" -- which is the failure mode this
// whole area keeps producing.
//
// On Linux this returns FALSE and does nothing: GTK draws its own decorations
// there and they already follow the theme variant GtkBackend sets.
//
// 要求 Windows 使用深色或淺色標題列。回傳該平台是否能夠實現此請求。
//
// 只有 Windows 需要它，原因是 GTK 視窗在該處配戴的是原生 Win32 標題列，而後者對 GTK 的主題一無所知。
// 因此深色的 GTK app 會得到一條淺色標題列與深色按鈕——成為整個視窗中唯一「顯然沒有收到通知」的部分。
// 帶 DWMWA_USE_IMMERSIVE_DARK_MODE 的 `DwmSetWindowAttribute` 正是用來告知合成器的手段。
//
// 該屬性在 Windows 10 2004 及之後為 20，在 1809 為 19。兩者都會嘗試，成本極低，因為傳入不支援的
// 屬性只會得到錯誤回傳而非崩潰；而在較舊的組建上弄錯，症狀會是「該設定悄悄地毫無作用」——正是這個
// 領域不斷產生的那種失敗模式。
//
// 在 Linux 上此函式回傳 FALSE 且不做任何事：GTK 於該處自行繪製視窗裝飾，而它們已經跟隨 GtkBackend
// 所設定的主題變體。
gboolean scui_window_set_dark_titlebar(GtkWidget *window, gboolean dark);

// The scale the DISPLAY reports for the monitor this window is on -- 1.25 at
// 125% -- or 0 where that is not available. Implemented in gtk_window_scale.c.
//
// This exists because GDK on Windows does not carry it. Measured 2026-09-16
// with the display at 125%, driven by P42 --scale-probe, three readings two
// seconds apart:
//
//     GTK widget_scale_factor=1 surface_scale=1.0 surface_scale_factor=1
//
// `gdk_surface_get_scale` is the GTK 4.12 double, and GTK here is 4.22, so it
// is present and it answered 1.0. The display really was at 125%: the same app
// built against WinUIBackend, running minutes apart on the same desktop,
// recorded `scale factor -> 1.25`. So this is not "the integer API rounds" --
// GDK's fractional API returns the unscaled value too, and no GDK call on this
// platform states the display scale at all.
//
// Kept separate from `gdk_surface_get_scale` rather than replacing it: on
// Wayland and X11 that call IS the display's fraction and should stay the
// source. This helper returns 0 off Win32 for exactly that reason.
//
// 顯示器就「此視窗所在的那台螢幕」所回報的縮放比例——125% 時為 1.25——取不到時回傳 0。
// 實作位於 gtk_window_scale.c。
//
// 它之所以存在,是因為 **GDK 在 Windows 上並不攜帶這個值**。實測於 2026-09-16,顯示器設為 125%,
// 以 P42 --scale-probe 驅動,每兩秒一次、共三次讀數:
//
//     GTK widget_scale_factor=1 surface_scale=1.0 surface_scale_factor=1
//
// `gdk_surface_get_scale` 是 GTK 4.12 起提供的**倍精度小數**版本,而此處的 GTK 是 4.22,因此它
// 確實存在——而它回答 1.0。顯示器當時確實在 125%:同一支 app 以 WinUIBackend 建置、在同一個桌面上
// 相隔數分鐘執行,記錄到 `scale factor -> 1.25`。所以這不是「整數 API 會取整」——**GDK 的小數 API
// 同樣回傳未縮放的值**,在這個平台上沒有任何 GDK 呼叫陳述得出顯示器的縮放。
//
// 刻意與 `gdk_surface_get_scale` 並存而非取代它:在 Wayland 與 X11 上,那個呼叫回傳的就是顯示器的
// 小數,應繼續作為來源。本 helper 在非 Win32 上回傳 0,正是為此。
double scui_window_display_scale(GtkWidget *window);

// Every Win32 number that bears on the window's scale, in one newly-allocated
// string. The caller owns it and must g_free it. Diagnostics, not policy:
// nothing in the framework reads this, and P42's --scale-probe prints it.
//
// It exists because the first answer was measured and was still wrong.
// `GetDpiForWindow` reported 1.25 at 125%, which looked like the fix -- and
// then kept reporting 1.25 after the display was changed to 100%, across 99
// readings two seconds apart. The value was not stale by one sample; it never
// moved. That rules out the notification being the problem and points at the
// process's DPI awareness, which is what `awareness` here reports.
//
// 所有與該視窗縮放有關的 Win32 數字,集中於一個新配置的字串。呼叫端擁有它,必須 g_free。這是
// **診斷**而非政策:框架中沒有任何東西讀它,由 P42 的 --scale-probe 印出。
//
// 它之所以存在,是因為第一個答案量過了、卻仍然是錯的。`GetDpiForWindow` 在 125% 下回報 1.25,
// 看起來就是修好了——然後在顯示器被改成 100% 之後,它**繼續**回報 1.25,連續 99 次、每兩秒一次。
// 那個值不是慢了一拍,而是**從未移動**。這排除了「問題出在通知」,並指向行程的 DPI awareness,
// 亦即此處的 `awareness`。
char *scui_window_scale_diagnostics(GtkWidget *window);

// A WebView2 browser hosted over a GTK placeholder widget, on Windows.
// Implemented in gtk_webview2.c, which records why WebView2 and not WebKitGTK,
// and why the loader is loaded at runtime rather than linked.
//
// scui_webview_new returns NULL where it is not compiled in (not Windows, or
// WebView2.h was absent at build time) -- ask scui_webview_is_compiled_in. The
// object lives as long as `host`: destroying the widget closes the browser.
// The callback receives the new top-level URI as UTF-8.
//
// 在 Windows 上,覆蓋於 GTK 佔位 widget 之上的 WebView2 瀏覽器。實作位於 gtk_webview2.c,該處記錄了
// 為何用 WebView2 而非 WebKitGTK,以及為何 loader 在執行期載入而非連結。
//
// 未編入時(非 Windows,或建置時沒有 WebView2.h)scui_webview_new 回傳 NULL——請用
// scui_webview_is_compiled_in 詢問。此物件與 `host` 同壽:widget 銷毀時瀏覽器即關閉。回呼收到的是
// 新的頂層 URI(UTF-8)。
typedef struct ScuiWebView ScuiWebView;
typedef void (*ScuiWebViewNavigatedFunc)(const char *uri, void *user_data);
gboolean scui_webview_is_compiled_in(void);
ScuiWebView *scui_webview_new(GtkWidget *host);
// `destroy` is called with `user_data` when the host widget is destroyed, so
// the caller can release whatever `user_data` keeps alive.
// host widget 銷毀時會以 `user_data` 呼叫 `destroy`,讓呼叫端釋放 `user_data` 所保住的東西。
void scui_webview_set_navigated_callback(
    ScuiWebView *view, ScuiWebViewNavigatedFunc callback, void *user_data,
    GDestroyNotify destroy
);
void scui_webview_navigate(ScuiWebView *view, const char *uri);
// NULL while nothing has failed; otherwise why the browser could not start.
// 尚未失敗時為 NULL;否則說明瀏覽器為何無法啟動。
const char *scui_webview_unavailable_reason(ScuiWebView *view);

// Swift suddenly stopped finding these corresponding `G_*` enum members on its
// own on macOS. Weirdly everything worked in one command run, and then it started
// failing in the next (with identical code). Then when I tried recreating the
// issue on my Mac I could, even though I successfully built Gtk/Gtk3 a few days
// earlier... I'm perplexed, but this does at least solve the issue
extern const GConnectFlags SHIM_G_CONNECT_AFTER;
extern const GConnectFlags SHIM_G_CONNECT_SWAPPED;
extern const GConnectFlags SHIM_G_CONNECT_DEFAULT;
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

// G_TYPE_BOOLEAN, for the same reason the two above exist: it is a macro, so
// Swift cannot see it, and `gtk_accessible_update_state_value` needs a GValue
// initialised to it. `scui_gtype_string()` already covers G_TYPE_STRING.
// G_TYPE_BOOLEAN,理由與上面兩個相同:它是一個巨集,Swift 看不到它,而
// `gtk_accessible_update_state_value` 需要一個以它初始化的 GValue。
// `scui_gtype_string()` 已經涵蓋了 G_TYPE_STRING。
GType scui_gtype_boolean(void);

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
