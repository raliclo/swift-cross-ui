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
    char *pending_uri;  // reported from an idle, see uri_changed
    guint idle;
};

// WebKitGTK's UI process ABORTS -- taking the whole app with it -- when it
// cannot create a surfaceless EGL display. Measured on WSL 2026-09-17 with
// libwebkitgtk-6.0-4 installed: "Could not create surfaceless EGL display:
// EGL_NOT_INITIALIZED. Aborting..." with no Mesa variables set, and the same
// with GALLIUM_DRIVER=d3d12 (WSL has no DRM render node for that platform).
// With LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe the page drew. Neither
// WEBKIT_DISABLE_DMABUF_RENDERER=1 nor WEBKIT_DISABLE_COMPOSITING_MODE=1 avoided
// the abort.
//
// So: probe the same thing in-process first. If hardware EGL works nothing is
// changed -- a Linux desktop with a GPU keeps it. If not, fall back to llvmpipe
// and probe again. If that fails too, the web view is not created at all and the
// frame says why: an app that dies because it contains a WebView is worse than
// one that shows a sentence.
//
// WebKitGTK 的 UI 行程在無法建立 surfaceless EGL display 時會 **abort**——把整個 app 一起帶走。
// 2026-09-17 於裝好 libwebkitgtk-6.0-4 的 WSL 實測:未設任何 Mesa 變數時出現「Could not create
// surfaceless EGL display: EGL_NOT_INITIALIZED. Aborting...」,GALLIUM_DRIVER=d3d12 時亦同(WSL 沒有
// 該平台需要的 DRM render node)。改用 LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe 時頁面畫得出來。
// WEBKIT_DISABLE_DMABUF_RENDERER=1 與 WEBKIT_DISABLE_COMPOSITING_MODE=1 都擋不住 abort。
//
// 所以先在行程內探測同一件事。硬體 EGL 可用時什麼都不改——有 GPU 的 Linux 桌面保持原樣。不可用時
// 退回 llvmpipe 再探測。仍然失敗就根本不建立 web view,由框說明原因:因為含有 WebView 而死掉的 app,
// 比顯示一句話的 app 更糟。
#define SCUI_EGL_PLATFORM_SURFACELESS_MESA 0x31DD

static int surfaceless_egl_works(void) {
    void *egl = dlopen("libEGL.so.1", RTLD_NOW | RTLD_GLOBAL);
    if (egl == NULL) {
        return 0;
    }
    void *(*get_platform_display)(unsigned int, void *, const int *) =
        dlsym(egl, "eglGetPlatformDisplay");
    int (*initialize)(void *, int *, int *) = dlsym(egl, "eglInitialize");
    int (*terminate)(void *) = dlsym(egl, "eglTerminate");
    if (get_platform_display == NULL || initialize == NULL || terminate == NULL) {
        return 0;
    }
    void *display = get_platform_display(SCUI_EGL_PLATFORM_SURFACELESS_MESA, NULL, NULL);
    if (display == NULL) {
        return 0;
    }
    int major = 0, minor = 0;
    int ok = initialize(display, &major, &minor);
    if (ok) {
        terminate(display);
    }
    return ok;
}

// NULL when WebKit can be created safely; otherwise the reason it cannot.
// WebKit 可以安全建立時回傳 NULL;否則回傳無法建立的原因。
static char *ensure_webkit_can_render(void) {
    static int state = 0;  // 0 untried, 1 ok, -1 failed
    if (state == 1) {
        return NULL;
    }
    if (state == -1) {
        return g_strdup(
            "no surfaceless EGL display, even with LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe"
        );
    }
    if (surfaceless_egl_works()) {
        state = 1;
        return NULL;
    }
    g_message(
        "WebKitGTK: hardware surfaceless EGL is unavailable here; using llvmpipe "
        "(LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe) so WebKit does not abort"
    );
    g_setenv("LIBGL_ALWAYS_SOFTWARE", "1", TRUE);
    g_setenv("GALLIUM_DRIVER", "llvmpipe", TRUE);
    if (surfaceless_egl_works()) {
        state = 1;
        return NULL;
    }
    state = -1;
    return ensure_webkit_can_render();
}

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

static gboolean report_pending_uri(gpointer data) {
    ScuiWebView *view = data;
    view->idle = 0;
    if (view->pending_uri != NULL && view->callback != NULL) {
        view->callback(view->pending_uri, view->user_data);
    }
    g_clear_pointer(&view->pending_uri, g_free);
    return G_SOURCE_REMOVE;
}

// Reported from an IDLE, not from inside the signal. WebKit emits notify::uri
// synchronously within webkit_web_view_load_uri, and that call is made while
// SwiftCrossUI is navigating the view -- before updateWebView has necessarily
// installed onNavigate. Measured 2026-09-17 on WSL: the page drew and P38 said
// "Navigations reported: 0". An idle also matches WebView2, whose SourceChanged
// is always asynchronous, so both backends report in the same order.
// 從 **idle** 回報,而不是在訊號內部。WebKit 在 webkit_web_view_load_uri 之中**同步**發出
// notify::uri,而那個呼叫發生在 SwiftCrossUI 正在導覽 view 的時候——此時 updateWebView 不一定已經裝好
// onNavigate。2026-09-17 於 WSL 實測:頁面畫出來了,P38 卻顯示「Navigations reported: 0」。idle 也與
// WebView2 一致(其 SourceChanged 一律非同步),兩個 backend 的回報順序因此相同。
static void uri_changed(GObject *object, GParamSpec *pspec, gpointer data) {
    (void)pspec;
    ScuiWebView *view = data;
    char *unused = NULL;
    const WebKitFunctions *webkit = load_webkit(&unused);
    g_free(unused);
    if (webkit == NULL) {
        return;
    }
    const char *uri = webkit->get_uri(GTK_WIDGET(object));
    if (uri == NULL || uri[0] == '\0') {
        return;
    }
    g_free(view->pending_uri);
    view->pending_uri = g_strdup(uri);
    if (view->idle == 0) {
        view->idle = g_idle_add(report_pending_uri, view);
    }
}

static void host_destroyed(GtkWidget *widget, gpointer data) {
    (void)widget;
    ScuiWebView *view = data;
    if (view->idle != 0) {
        g_source_remove(view->idle);
    }
    if (view->destroy_user_data != NULL) {
        view->destroy_user_data(view->user_data);
    }
    g_free(view->pending_uri);
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
    if (webkit != NULL) {
        why = ensure_webkit_can_render();
        if (why != NULL) {
            webkit = NULL;
        }
    }
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
