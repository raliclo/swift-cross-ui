// A real web view for GtkBackend on Windows: WebView2, hosted as a child of the
// GTK window's HWND and kept over a placeholder widget GTK lays out.
//
// WHY WebView2 AND NOT WebKitGTK. WebKitGTK has no Windows port -- nothing
// under C:/gtk4 and no gvsbuild recipe -- while WebView2 is the engine
// WinUIBackend already drives. GTK4 on Windows hands out its surface HWND, so
// the browser can be a child window of the GTK window. See
// GtkBackend+WebView.swift for the decision record.
//
// HOW IT IS BUILT, and why it degrades VISIBLY instead of failing to build:
//   - WebView2.h is needed at compile time. testapp/install_gtk4_windows.zsh
//     puts it under <prefix>/include/webview2, and compile.zsh adds that
//     include path. Without it this file compiles the stubs at the bottom and
//     scui_webview_unavailable_reason() says so -- a build machine missing an
//     optional SDK must still build GtkBackend.
//   - WebView2Loader.dll is loaded at RUNTIME with LoadLibraryW, from
//     <prefix>/bin next to GTK's own DLLs, rather than linked. A link-time
//     dependency would turn "no loader" into "the app does not start".
//
// THE ONE ORDERING RULE. The browser is created only once the placeholder is
// mapped and its native surface exists, because the controller needs a parent
// HWND. Until then navigate() just remembers the URI.
//
// GtkBackend 在 Windows 上真正的 web view:WebView2,以 GTK 視窗 HWND 的子視窗形式掛載,並保持
// 覆蓋在 GTK 所排版的佔位 widget 上。
//
// **為何用 WebView2 而非 WebKitGTK。** WebKitGTK 沒有 Windows 版本(C:/gtk4 下沒有,gvsbuild 也沒有
// 配方),而 WebView2 是 WinUIBackend 已在驅動的引擎。GTK4 在 Windows 上會交出 surface 的 HWND,
// 所以瀏覽器可以是 GTK 視窗的子視窗。決策紀錄見 GtkBackend+WebView.swift。
//
// **如何建置,以及為何「看得見地降級」而非建置失敗:**
//   - 編譯時需要 WebView2.h。testapp/install_gtk4_windows.zsh 把它放在 <prefix>/include/webview2,
//     compile.zsh 加入該 include 路徑。沒有它時,本檔編譯底部的 stub,並由
//     scui_webview_unavailable_reason() 說明原因——缺少選配 SDK 的建置機器仍必須建得出 GtkBackend。
//   - WebView2Loader.dll 在**執行期**以 LoadLibraryW 從 <prefix>/bin(與 GTK 自己的 DLL 同處)載入,
//     而不是連結進來。連結期相依會把「沒有 loader」變成「app 啟動不了」。
//
// **唯一的順序規則。** 只有在佔位 widget 已 map、且其 native surface 存在之後才建立瀏覽器,因為
// controller 需要父 HWND。在那之前 navigate() 只記住 URI。

#include "include/gtk_helpers.h"

#ifdef G_OS_WIN32
#include <gdk/win32/gdkwin32.h>
#include <windows.h>
#if __has_include(<WebView2.h>)
#define COBJMACROS
#include <WebView2.h>
#define SCUI_HAVE_WEBVIEW2 1
#endif
#endif

#ifdef SCUI_HAVE_WEBVIEW2

typedef enum {
    SCUI_WV_WAITING,   // no parent HWND yet
    SCUI_WV_CREATING,  // environment or controller requested
    SCUI_WV_READY,
    SCUI_WV_FAILED,
} ScuiWebViewState;

struct ScuiWebView {
    GtkWidget *host;
    // A child of `host`, empty unless the browser fails -- then it says why.
    // `host` 的子元件,平時為空,瀏覽器失敗時說明原因。
    GtkWidget *label;
    HWND parent;
    ScuiWebViewState state;
    char *failure;
    char *pending_uri;
    ICoreWebView2Controller *controller;
    ICoreWebView2 *webview;
    EventRegistrationToken source_token;
    ScuiWebViewNavigatedFunc callback;
    void *user_data;
    GDestroyNotify destroy_user_data;
    RECT last_bounds;
    int last_visible;
    guint timer;
    int ref_count;  // the GTK side plus each in-flight COM handler
};

static void webview_retain(ScuiWebView *view) { view->ref_count++; }

static void webview_release(ScuiWebView *view) {
    if (--view->ref_count > 0) {
        return;
    }
    g_free(view->failure);
    g_free(view->pending_uri);
    g_free(view);
}

// Records the failure AND writes it into the host label at once. Failures
// arrive asynchronously, from completion handlers, so a caller that checked
// only when the view updated would usually never see them.
// 記錄失敗,**並且**立刻寫進 host label。失敗是從 completion handler 非同步抵達的,只在 view
// 更新時才檢查的呼叫端,通常永遠看不到它們。
static void show_failure(ScuiWebView *view) {
    if (view->host != NULL && view->label != NULL && view->failure != NULL) {
        char *text = g_strdup_printf("WebView2 could not start: %s", view->failure);
        gtk_label_set_text(GTK_LABEL(view->label), text);
        g_free(text);
    }
}

static void webview_fail(ScuiWebView *view, const char *what, HRESULT hr) {
    view->state = SCUI_WV_FAILED;
    g_free(view->failure);
    view->failure = g_strdup_printf("%s failed, HRESULT 0x%08lx", what, (unsigned long)hr);
    g_warning("WebView2: %s", view->failure);
    show_failure(view);
}

// ---- A minimal COM handler: one vtable pointer, a count, and the owner. ----
// QueryInterface answers every IID with itself. WebView2 only ever asks a
// completion handler for IUnknown or its own interface, and comparing IIDs
// would need the IID definitions, which the NuGet package does not ship.
// ---- 最小的 COM handler:一個 vtable 指標、一個計數、以及擁有者。----
// QueryInterface 對任何 IID 都回傳自己。WebView2 只會向 completion handler 要 IUnknown 或它自己的
// 介面,而比對 IID 需要 IID 的定義,NuGet 套件並未附帶。

typedef struct {
    void *vtbl;
    LONG refs;
    ScuiWebView *owner;
} Handler;

static HRESULT STDMETHODCALLTYPE handler_query(void *self, REFIID riid, void **out) {
    (void)riid;
    *out = self;
    ((Handler *)self)->refs++;
    return S_OK;
}

static ULONG STDMETHODCALLTYPE handler_add_ref(void *self) {
    return (ULONG)++((Handler *)self)->refs;
}

static ULONG STDMETHODCALLTYPE handler_release(void *self) {
    Handler *handler = self;
    LONG refs = --handler->refs;
    if (refs == 0) {
        webview_release(handler->owner);
        g_free(handler);
    }
    return (ULONG)refs;
}

static Handler *handler_new(void *vtbl, ScuiWebView *owner) {
    Handler *handler = g_new0(Handler, 1);
    handler->vtbl = vtbl;
    handler->refs = 1;
    handler->owner = owner;
    webview_retain(owner);
    return handler;
}

static void apply_bounds(ScuiWebView *view);

// Source changed -> report the new top-level URI, which covers navigation the
// app asked for and navigation the user made inside the page.
// Source 改變 -> 回報新的頂層 URI,涵蓋 app 要求的導覽與使用者在頁面內所做的導覽。
static HRESULT STDMETHODCALLTYPE source_changed_invoke(
    void *self, ICoreWebView2 *sender, ICoreWebView2SourceChangedEventArgs *args
) {
    (void)args;
    ScuiWebView *view = ((Handler *)self)->owner;
    LPWSTR source = NULL;
    if (SUCCEEDED(ICoreWebView2_get_Source(sender, &source)) && source != NULL) {
        char *utf8 = g_utf16_to_utf8((gunichar2 *)source, -1, NULL, NULL, NULL);
        if (utf8 != NULL && view->callback != NULL) {
            view->callback(utf8, view->user_data);
        }
        g_free(utf8);
        CoTaskMemFree(source);
    }
    return S_OK;
}

static ICoreWebView2SourceChangedEventHandlerVtbl source_changed_vtbl = {
    (void *)handler_query, (void *)handler_add_ref, (void *)handler_release,
    (void *)source_changed_invoke,
};

static void navigate_now(ScuiWebView *view, const char *uri) {
    wchar_t *wide = (wchar_t *)g_utf8_to_utf16(uri, -1, NULL, NULL, NULL);
    if (wide == NULL) {
        return;
    }
    HRESULT hr = ICoreWebView2_Navigate(view->webview, wide);
    if (FAILED(hr)) {
        g_warning("WebView2: Navigate(%s) failed, HRESULT 0x%08lx", uri, (unsigned long)hr);
    }
    g_free(wide);
}

static HRESULT STDMETHODCALLTYPE controller_completed_invoke(
    void *self, HRESULT result, ICoreWebView2Controller *controller
) {
    ScuiWebView *view = ((Handler *)self)->owner;
    if (FAILED(result) || controller == NULL) {
        webview_fail(view, "CreateCoreWebView2Controller", result);
        return S_OK;
    }
    // The GTK side may have gone while the browser was starting.
    // 瀏覽器啟動期間,GTK 那一側可能已經消失。
    if (view->host == NULL) {
        ICoreWebView2Controller_Close(controller);
        return S_OK;
    }

    ICoreWebView2Controller_AddRef(controller);
    view->controller = controller;
    HRESULT hr = ICoreWebView2Controller_get_CoreWebView2(controller, &view->webview);
    if (FAILED(hr) || view->webview == NULL) {
        webview_fail(view, "get_CoreWebView2", hr);
        return S_OK;
    }

    Handler *source_handler = handler_new(&source_changed_vtbl, view);
    ICoreWebView2_add_SourceChanged(
        view->webview,
        (ICoreWebView2SourceChangedEventHandler *)source_handler,
        &view->source_token
    );
    handler_release(source_handler);

    view->state = SCUI_WV_READY;
    view->last_visible = -1;
    apply_bounds(view);

    if (view->pending_uri != NULL) {
        navigate_now(view, view->pending_uri);
        g_clear_pointer(&view->pending_uri, g_free);
    }
    return S_OK;
}

static ICoreWebView2CreateCoreWebView2ControllerCompletedHandlerVtbl controller_completed_vtbl = {
    (void *)handler_query, (void *)handler_add_ref, (void *)handler_release,
    (void *)controller_completed_invoke,
};

static HRESULT STDMETHODCALLTYPE environment_completed_invoke(
    void *self, HRESULT result, ICoreWebView2Environment *environment
) {
    ScuiWebView *view = ((Handler *)self)->owner;
    if (FAILED(result) || environment == NULL) {
        webview_fail(view, "CreateCoreWebView2EnvironmentWithOptions", result);
        return S_OK;
    }
    if (view->host == NULL) {
        return S_OK;
    }
    Handler *handler = handler_new(&controller_completed_vtbl, view);
    HRESULT hr = ICoreWebView2Environment_CreateCoreWebView2Controller(
        environment, view->parent,
        (ICoreWebView2CreateCoreWebView2ControllerCompletedHandler *)handler
    );
    handler_release(handler);
    if (FAILED(hr)) {
        webview_fail(view, "CreateCoreWebView2Controller", hr);
    }
    return S_OK;
}

static ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandlerVtbl environment_completed_vtbl = {
    (void *)handler_query, (void *)handler_add_ref, (void *)handler_release,
    (void *)environment_completed_invoke,
};

typedef HRESULT(STDAPICALLTYPE *CreateEnvironmentFunc)(
    PCWSTR, PCWSTR, ICoreWebView2EnvironmentOptions *,
    ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *
);

static CreateEnvironmentFunc load_loader(char **why) {
    static HMODULE module = NULL;
    static CreateEnvironmentFunc function = NULL;
    if (function != NULL) {
        return function;
    }
    if (module == NULL) {
        module = LoadLibraryW(L"WebView2Loader.dll");
    }
    if (module == NULL) {
        *why = g_strdup_printf(
            "WebView2Loader.dll could not be loaded (error %lu); run testapp/install_gtk4_windows.zsh",
            GetLastError()
        );
        return NULL;
    }
    function = (CreateEnvironmentFunc)(void *)GetProcAddress(
        module, "CreateCoreWebView2EnvironmentWithOptions"
    );
    if (function == NULL) {
        *why = g_strdup("WebView2Loader.dll has no CreateCoreWebView2EnvironmentWithOptions");
    }
    return function;
}

static void start_browser(ScuiWebView *view) {
    // WebView2 completes into the calling thread's apartment, which has to be
    // single-threaded with a message loop -- the lesson of P38 on WinUIBackend.
    // GTK's main thread pumps Win32 messages; this makes sure it is STA.
    // WebView2 會把完成通知送回呼叫端執行緒的 apartment,而它必須是有訊息迴圈的單執行緒 apartment
    // ——這正是 WinUIBackend 上 P38 的教訓。GTK 主執行緒會抽取 Win32 訊息;這裡確保它是 STA。
    HRESULT apartment = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    if (apartment == RPC_E_CHANGED_MODE) {
        webview_fail(view, "CoInitializeEx(STA) -- the GTK thread is multi-threaded", apartment);
        return;
    }

    char *why = NULL;
    CreateEnvironmentFunc create = load_loader(&why);
    if (create == NULL) {
        view->state = SCUI_WV_FAILED;
        g_free(view->failure);
        view->failure = why;
        g_warning("WebView2: %s", why);
        show_failure(view);
        return;
    }

    view->state = SCUI_WV_CREATING;
    Handler *handler = handler_new(&environment_completed_vtbl, view);
    HRESULT hr = create(
        NULL, NULL, NULL, (ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *)handler
    );
    handler_release(handler);
    if (FAILED(hr)) {
        webview_fail(view, "CreateCoreWebView2EnvironmentWithOptions", hr);
    }
}

// Places the browser over the placeholder. Bounds are in the parent HWND's
// client pixels: the widget's position in its root, plus the root's offset
// inside the surface (GTK's client-side shadow), times the surface scale.
// 把瀏覽器放到佔位 widget 上方。bounds 是父 HWND 的 client 像素:widget 在 root 中的位置,加上 root
// 在 surface 內的偏移(GTK 的 client-side 陰影),再乘以 surface scale。
static void apply_bounds(ScuiWebView *view) {
    if (view->controller == NULL || view->host == NULL) {
        return;
    }
    int visible = gtk_widget_is_drawable(view->host) ? 1 : 0;
    RECT bounds = {0, 0, 0, 0};
    if (visible) {
        GtkRoot *root = gtk_widget_get_root(view->host);
        GtkNative *native = gtk_widget_get_native(view->host);
        graphene_rect_t rect;
        if (root != NULL && native != NULL
            && gtk_widget_compute_bounds(view->host, GTK_WIDGET(root), &rect))
        {
            double surface_x = 0, surface_y = 0;
            gtk_native_get_surface_transform(native, &surface_x, &surface_y);
            GdkSurface *surface = gtk_native_get_surface(native);
            double scale = surface != NULL ? gdk_surface_get_scale(surface) : 1.0;
            bounds.left = (LONG)((rect.origin.x + surface_x) * scale + 0.5);
            bounds.top = (LONG)((rect.origin.y + surface_y) * scale + 0.5);
            bounds.right = bounds.left + (LONG)(rect.size.width * scale + 0.5);
            bounds.bottom = bounds.top + (LONG)(rect.size.height * scale + 0.5);
        } else {
            visible = 0;
        }
    }

    if (visible != view->last_visible) {
        ICoreWebView2Controller_put_IsVisible(view->controller, visible ? TRUE : FALSE);
        view->last_visible = visible;
    }
    if (visible && !EqualRect(&bounds, &view->last_bounds)) {
        ICoreWebView2Controller_put_Bounds(view->controller, bounds);
        view->last_bounds = bounds;
    }
}

static gboolean tick(gpointer data) {
    ScuiWebView *view = data;
    if (view->host == NULL) {
        return G_SOURCE_REMOVE;
    }
    if (view->state == SCUI_WV_WAITING && gtk_widget_get_mapped(view->host)) {
        GtkNative *native = gtk_widget_get_native(view->host);
        GdkSurface *surface = native != NULL ? gtk_native_get_surface(native) : NULL;
        HWND hwnd = surface != NULL ? gdk_win32_surface_get_handle(surface) : NULL;
        if (hwnd != NULL) {
            view->parent = hwnd;
            start_browser(view);
        }
    }
    if (view->state == SCUI_WV_READY) {
        apply_bounds(view);
    }
    return G_SOURCE_CONTINUE;
}

static void host_destroyed(GtkWidget *widget, gpointer data) {
    (void)widget;
    ScuiWebView *view = data;
    view->host = NULL;
    view->label = NULL;
    if (view->timer != 0) {
        g_source_remove(view->timer);
        view->timer = 0;
    }
    if (view->webview != NULL) {
        ICoreWebView2_remove_SourceChanged(view->webview, view->source_token);
        ICoreWebView2_Release(view->webview);
        view->webview = NULL;
    }
    if (view->controller != NULL) {
        ICoreWebView2Controller_Close(view->controller);
        ICoreWebView2Controller_Release(view->controller);
        view->controller = NULL;
    }
    if (view->destroy_user_data != NULL) {
        view->destroy_user_data(view->user_data);
    }
    view->callback = NULL;
    view->user_data = NULL;
    view->destroy_user_data = NULL;
    webview_release(view);
}

ScuiWebView *scui_webview_new(GtkWidget *host) {
    ScuiWebView *view = g_new0(ScuiWebView, 1);
    view->host = host;
    view->label = gtk_label_new("");
    gtk_label_set_wrap(GTK_LABEL(view->label), TRUE);
    gtk_widget_set_hexpand(view->label, TRUE);
    gtk_widget_set_vexpand(view->label, TRUE);
    gtk_box_append(GTK_BOX(host), view->label);
    view->ref_count = 1;
    view->last_visible = -1;
    view->timer = g_timeout_add(50, tick, view);
    g_signal_connect(host, "destroy", G_CALLBACK(host_destroyed), view);
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
    if (view->state == SCUI_WV_READY && view->webview != NULL) {
        navigate_now(view, uri);
    } else {
        g_free(view->pending_uri);
        view->pending_uri = g_strdup(uri);
    }
}

const char *scui_webview_unavailable_reason(ScuiWebView *view) {
    return view->state == SCUI_WV_FAILED ? view->failure : NULL;
}

gboolean scui_webview_is_compiled_in(void) {
    return TRUE;
}

#elif defined(G_OS_WIN32)  // Windows without WebView2.h; Linux is gtk_webkit.c

struct ScuiWebView {
    int unused;
};

ScuiWebView *scui_webview_new(GtkWidget *host) {
    (void)host;
    return NULL;
}

void scui_webview_set_navigated_callback(
    ScuiWebView *view, ScuiWebViewNavigatedFunc callback, void *user_data,
    GDestroyNotify destroy
) {
    (void)view;
    (void)callback;
    if (destroy != NULL) {
        destroy(user_data);
    }
}

void scui_webview_navigate(ScuiWebView *view, const char *uri) {
    (void)view;
    (void)uri;
}

const char *scui_webview_unavailable_reason(ScuiWebView *view) {
    (void)view;
    return NULL;
}

gboolean scui_webview_is_compiled_in(void) {
    return FALSE;
}

#endif
