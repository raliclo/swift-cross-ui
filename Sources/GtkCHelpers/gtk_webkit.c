// A real web view for GtkBackend on Linux and WSL: WebKitGTK 6.0, loaded at
// run time with dlopen. The Windows twin is gtk_webview2.c; both implement the
// scui_webview_* API declared in include/gtk_helpers.h.
//
// WHY dlopen AND NOT A BUILD DEPENDENCY. The 2026-09-04 decision in
// GtkBackend+WebView.swift rules out webkitgtk-6.0 as an unconditional system
// dependency, because GtkBackend also builds on Windows where WebKitGTK does not
// exist. Loading the library at run time needs no headers and no link flag, so
// every GTK build is unchanged, and a Linux machine without the runtime package
// still builds and runs -- the frame says which package to install. Only three
// functions are called, and their C signatures are stable across WebKitGTK 6.x:
//
//   GtkWidget  *webkit_web_view_new (void);
//   void        webkit_web_view_load_uri (WebKitWebView *, const gchar *);
//   const char *webkit_web_view_get_uri (WebKitWebView *);
//
// Unlike WebView2, WebKitWebView IS a GtkWidget, so it goes straight into the
// host box and GTK lays it out; there is no separate window to keep in place.
//
// GtkBackend 在 Linux 與 WSL 上真正的 web view:WebKitGTK 6.0,於執行期以 dlopen 載入。Windows 版是
// gtk_webview2.c;兩者都實作 include/gtk_helpers.h 宣告的 scui_webview_* API。
//
// **為何用 dlopen 而非建置相依。** GtkBackend+WebView.swift 中 2026-09-04 的決策排除了把
// webkitgtk-6.0 當成無條件系統相依,因為 GtkBackend 也在沒有 WebKitGTK 的 Windows 上建置。執行期載入
// 不需要標頭也不需要連結旗標,所以每一個 GTK 建置都不受影響;沒有 runtime 套件的 Linux 機器照樣建得出、
// 跑得起來——框裡會說出該裝哪個套件。只呼叫三個函式,其 C 簽名在 WebKitGTK 6.x 間穩定(見上)。
//
// 與 WebView2 不同,WebKitWebView **本身就是** GtkWidget,所以直接放進 host box、由 GTK 排版;沒有
// 另一個需要對位的視窗。

#include "include/gtk_helpers.h"

#ifndef G_OS_WIN32

#include <dlfcn.h>

// The SONAME of WebKitGTK 6.0's runtime (Ubuntu/Debian: libwebkitgtk-6.0-4).
// WebKitGTK 6.0 runtime 的 SONAME(Ubuntu/Debian 套件:libwebkitgtk-6.0-4)。
#define SCUI_WEBKIT_LIBRARY "libwebkitgtk-6.0.so.4"
#define SCUI_WEBKIT_PACKAGE_HINT "install libwebkitgtk-6.0-4 (sudo apt install libwebkitgtk-6.0-4)"

typedef struct {
    GtkWidget *(*web_view_new)(void);
    void (*load_uri)(GtkWidget *, const char *);
    const char *(*get_uri)(GtkWidget *);
} WebKitFunctions;

struct ScuiWebView {
    GtkWidget *host;
    GtkWidget *label;
    GtkWidget *web_view;
    char *failure;
    ScuiWebViewNavigatedFunc callback;
    void *user_data;
    GDestroyNotify destroy_user_data;
};

static const WebKitFunctions *load_webkit(char **why) {
    static WebKitFunctions functions;
    static int state = 0;  // 0 untried, 1 loaded, -1 failed
    static char *failure = NULL;
    if (state == 1) {
        return &functions;
    }
    if (state == -1) {
        *why = g_strdup(failure);
        return NULL;
    }

    void *library = dlopen(SCUI_WEBKIT_LIBRARY, RTLD_NOW | RTLD_GLOBAL);
    if (library == NULL) {
        const char *error = dlerror();
        failure = g_strdup_printf(
            "%s could not be loaded (%s); %s", SCUI_WEBKIT_LIBRARY,
            error != NULL ? error : "unknown error", SCUI_WEBKIT_PACKAGE_HINT
        );
        state = -1;
        *why = g_strdup(failure);
        return NULL;
    }
    functions.web_view_new = dlsym(library, "webkit_web_view_new");
    functions.load_uri = dlsym(library, "webkit_web_view_load_uri");
    functions.get_uri = dlsym(library, "webkit_web_view_get_uri");
    if (functions.web_view_new == NULL || functions.load_uri == NULL
        || functions.get_uri == NULL)
    {
        failure = g_strdup_printf(
            "%s is missing webkit_web_view_new/load_uri/get_uri", SCUI_WEBKIT_LIBRARY
        );
        state = -1;
        *why = g_strdup(failure);
        return NULL;
    }
    state = 1;
    return &functions;
}

static void uri_changed(GObject *object, GParamSpec *pspec, gpointer data) {
    (void)pspec;
    ScuiWebView *view = data;
    char *unused = NULL;
    const WebKitFunctions *webkit = load_webkit(&unused);
    g_free(unused);
    if (webkit == NULL || view->callback == NULL) {
        return;
    }
    const char *uri = webkit->get_uri(GTK_WIDGET(object));
    if (uri != NULL && uri[0] != '\0') {
        view->callback(uri, view->user_data);
    }
}

static void host_destroyed(GtkWidget *widget, gpointer data) {
    (void)widget;
    ScuiWebView *view = data;
    if (view->destroy_user_data != NULL) {
        view->destroy_user_data(view->user_data);
    }
    g_free(view->failure);
    g_free(view);
}

gboolean scui_webview_is_compiled_in(void) {
    return TRUE;
}

ScuiWebView *scui_webview_new(GtkWidget *host) {
    ScuiWebView *view = g_new0(ScuiWebView, 1);
    view->host = host;
    g_signal_connect(host, "destroy", G_CALLBACK(host_destroyed), view);

    char *why = NULL;
    const WebKitFunctions *webkit = load_webkit(&why);
    if (webkit == NULL) {
        view->failure = why;
        g_warning("WebKitGTK: %s", why);
        char *text = g_strdup_printf("WebKitGTK could not start: %s", why);
        view->label = gtk_label_new(text);
        g_free(text);
        gtk_label_set_wrap(GTK_LABEL(view->label), TRUE);
        gtk_widget_set_hexpand(view->label, TRUE);
        gtk_widget_set_vexpand(view->label, TRUE);
        gtk_box_append(GTK_BOX(host), view->label);
        return view;
    }

    view->web_view = webkit->web_view_new();
    gtk_widget_set_hexpand(view->web_view, TRUE);
    gtk_widget_set_vexpand(view->web_view, TRUE);
    gtk_box_append(GTK_BOX(host), view->web_view);
    g_signal_connect(view->web_view, "notify::uri", G_CALLBACK(uri_changed), view);
    return view;
}

void scui_webview_set_navigated_callback(
    ScuiWebView *view, ScuiWebViewNavigatedFunc callback, void *user_data,
    GDestroyNotify destroy
) {
    if (view->destroy_user_data != NULL) {
        view->destroy_user_data(view->user_data);
    }
    view->callback = callback;
    view->user_data = user_data;
    view->destroy_user_data = destroy;
}

void scui_webview_navigate(ScuiWebView *view, const char *uri) {
    if (view->web_view == NULL) {
        return;
    }
    char *unused = NULL;
    const WebKitFunctions *webkit = load_webkit(&unused);
    g_free(unused);
    if (webkit != NULL) {
        webkit->load_uri(view->web_view, uri);
    }
}

const char *scui_webview_unavailable_reason(ScuiWebView *view) {
    return view->failure;
}

#endif
