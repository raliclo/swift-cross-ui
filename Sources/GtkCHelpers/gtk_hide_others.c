// Hide Others and Show All for GtkBackend where the application object of macOS
// is not there to do it: on Windows through Win32, on X11 through the window
// manager (ICCCM WM_CHANGE_STATE, the request XIconifyWindow sends).
//
// See the declarations in include/gtk_helpers.h for what each platform does and
// for why Wayland is the one place this is not offered.
//
// GtkBackend 在沒有 macOS application 物件可代勞之處的 Hide Others 與 Show All:Windows 上經由 Win32,
// X11 上經由視窗管理員(ICCCM 的 WM_CHANGE_STATE,也就是 XIconifyWindow 送出的請求)。
//
// 各平台的做法，以及為何 Wayland 是唯一不提供的地方，見 include/gtk_helpers.h 中的宣告。

#include "include/gtk_helpers.h"

#ifdef G_OS_WIN32
#include <windows.h>
#elif defined(GDK_WINDOWING_X11) && !defined(__APPLE__)
#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <gdk/x11/gdkx.h>
#include <unistd.h>
#endif

#ifdef G_OS_WIN32

// The windows Hide Others minimised, so that Show All restores those and no
// others: a window that was already minimised stays where it was.
// Hide Others 所最小化的視窗，讓 Show All 只還原這些：原本就已最小化的視窗維持原狀。
static GArray *scui_hidden_windows;

// DWMWA_CLOAKED, spelled out because the constant is version-gated in the SDK
// headers. / DWMWA_CLOAKED,因為 SDK 標頭中此常數有版本條件，所以寫成字面值。
#define SCUI_DWMWA_CLOAKED 14

typedef HRESULT(WINAPI *scui_dwm_get_window_attribute)(HWND, DWORD, PVOID, DWORD);

static gboolean scui_is_cloaked(HWND window) {
    static scui_dwm_get_window_attribute get = NULL;
    static gboolean looked = FALSE;
    if (!looked) {
        looked = TRUE;
        HMODULE dwm = LoadLibraryW(L"dwmapi.dll");
        if (dwm != NULL) {
            get = (scui_dwm_get_window_attribute)GetProcAddress(dwm, "DwmGetWindowAttribute");
        }
    }
    DWORD cloaked = 0;
    return get != NULL &&
           SUCCEEDED(get(window, SCUI_DWMWA_CLOAKED, &cloaked, sizeof cloaked)) && cloaked != 0;
}

// Whether `window` is another application's window that Win+Home would
// minimise: visible, top-level, not owned, not a tool window, not cloaked (a
// suspended UWP app or a window on another virtual desktop), not the desktop or
// the taskbar, and with a minimise box -- a window without one offers no way to
// minimise it, and that is how always-on-top overlays look.
//
// `window` 是否是 Win+Home 會最小化的「其他應用程式的視窗」:可見、頂層、沒有擁有者、不是工具視窗、
// 沒有被 cloak(暫停中的 UWP app 或位於其他虛擬桌面的視窗)、不是桌面或工作列，而且有最小化鈕——
// 沒有最小化鈕的視窗本身就不提供最小化，而總在最上層的浮動層正是這個樣子。
static gboolean scui_is_other_application_window(HWND window) {
    DWORD process = 0;
    GetWindowThreadProcessId(window, &process);
    if (process == GetCurrentProcessId()) {
        return FALSE;
    }
    if (!IsWindowVisible(window) || IsIconic(window) || GetWindow(window, GW_OWNER) != NULL) {
        return FALSE;
    }
    LONG_PTR extended = GetWindowLongPtrW(window, GWL_EXSTYLE);
    LONG_PTR style = GetWindowLongPtrW(window, GWL_STYLE);
    if ((extended & WS_EX_TOOLWINDOW) != 0 || (style & WS_MINIMIZEBOX) == 0) {
        return FALSE;
    }
    wchar_t name[64];
    if (GetClassNameW(window, name, 64) > 0 &&
        (lstrcmpW(name, L"Progman") == 0 || lstrcmpW(name, L"WorkerW") == 0 ||
         lstrcmpW(name, L"Shell_TrayWnd") == 0 || lstrcmpW(name, L"Shell_SecondaryTrayWnd") == 0)) {
        return FALSE;
    }
    return !scui_is_cloaked(window);
}

static BOOL CALLBACK scui_hide_one(HWND window, LPARAM count) {
    if (!scui_is_other_application_window(window)) {
        return TRUE;
    }
    // Asynchronous, so a hung application cannot stall this one, and without
    // activation, so the focus stays on the window the command came from.
    // 非同步，讓沒有回應的 app 拖不住這一個；不啟用，讓焦點留在下指令的視窗上。
    if (ShowWindowAsync(window, SW_SHOWMINNOACTIVE)) {
        for (guint index = 0; index < scui_hidden_windows->len; index++) {
            if (g_array_index(scui_hidden_windows, HWND, index) == window) {
                return TRUE;
            }
        }
        g_array_append_val(scui_hidden_windows, window);
        *(int *)count += 1;
    }
    return TRUE;
}

#elif defined(GDK_WINDOWING_X11) && !defined(__APPLE__)

static GArray *scui_hidden_windows;

// One property of `window` as an array of 32-bit items (which Xlib hands back
// as longs); NULL when absent. Free with XFree.
// `window` 的某個屬性，以 32 位元項目陣列取得(Xlib 以 long 交回);不存在時為 NULL。以 XFree 釋放。
static unsigned long *scui_x11_property(Display *display, Window window, Atom property,
                                        Atom type, unsigned long *count) {
    Atom actual = None;
    int format = 0;
    unsigned long remaining = 0;
    unsigned char *data = NULL;
    *count = 0;
    if (XGetWindowProperty(display, window, property, 0, 4096, False, type, &actual, &format,
                           count, &remaining, &data) != Success ||
        data == NULL) {
        return NULL;
    }
    if (format != 32 || *count == 0) {
        XFree(data);
        *count = 0;
        return NULL;
    }
    return (unsigned long *)data;
}

static gboolean scui_x11_has_atom(Display *display, Window window, Atom property, Atom wanted) {
    unsigned long count = 0;
    unsigned long *atoms = scui_x11_property(display, window, property, XA_ATOM, &count);
    gboolean found = FALSE;
    for (unsigned long index = 0; atoms != NULL && index < count; index++) {
        found = found || atoms[index] == wanted;
    }
    if (atoms != NULL) {
        XFree(atoms);
    }
    return found;
}

// The client windows the window manager manages: _NET_CLIENT_LIST where the
// manager keeps it (EWMH), otherwise the root's children and their children
// that carry WM_STATE (ICCCM: the manager puts WM_STATE on every client window
// it manages, inside whatever frame it reparents it into).
// 視窗管理員所管理的 client 視窗：管理員有維護時取 _NET_CLIENT_LIST(EWMH),否則取 root 的子視窗及其子視窗中
// 帶有 WM_STATE 者(ICCCM:管理員會在它管理的每個 client 視窗上放 WM_STATE,不論把它 reparent 進哪個框)。
static GArray *scui_x11_clients(GdkDisplay *gdk_display, Display *display, Window root) {
    GArray *clients = g_array_new(FALSE, FALSE, sizeof(Window));
    unsigned long count = 0;
    unsigned long *list = scui_x11_property(
        display, root, gdk_x11_get_xatom_by_name_for_display(gdk_display, "_NET_CLIENT_LIST"),
        XA_WINDOW, &count);
    if (list != NULL) {
        for (unsigned long index = 0; index < count; index++) {
            Window window = (Window)list[index];
            g_array_append_val(clients, window);
        }
        XFree(list);
        return clients;
    }
    Atom wm_state = gdk_x11_get_xatom_by_name_for_display(gdk_display, "WM_STATE");
    Window unused_root = None, unused_parent = None, *children = NULL;
    unsigned int child_count = 0;
    if (!XQueryTree(display, root, &unused_root, &unused_parent, &children, &child_count)) {
        return clients;
    }
    for (unsigned int index = 0; index < child_count; index++) {
        unsigned long state_count = 0;
        unsigned long *state =
            scui_x11_property(display, children[index], wm_state, wm_state, &state_count);
        if (state != NULL) {
            XFree(state);
            g_array_append_val(clients, children[index]);
            continue;
        }
        Window *inner = NULL;
        unsigned int inner_count = 0;
        if (XQueryTree(display, children[index], &unused_root, &unused_parent, &inner,
                       &inner_count)) {
            for (unsigned int nested = 0; nested < inner_count; nested++) {
                state = scui_x11_property(display, inner[nested], wm_state, wm_state, &state_count);
                if (state != NULL) {
                    XFree(state);
                    g_array_append_val(clients, inner[nested]);
                }
            }
            if (inner != NULL) {
                XFree(inner);
            }
        }
    }
    if (children != NULL) {
        XFree(children);
    }
    return clients;
}

// Whether `window` is one of this process's: by _NET_WM_PID, and by comparison
// with the X windows of this process's GDK surfaces, for a client that does not
// set the PID.
// `window` 是否屬於本行程：依 _NET_WM_PID,另外再與本行程 GDK surface 的 X window 比對，以涵蓋不設 PID 的情況。
static gboolean scui_x11_is_own(GdkDisplay *gdk_display, Display *display, Window window) {
    unsigned long count = 0;
    unsigned long *pid = scui_x11_property(
        display, window, gdk_x11_get_xatom_by_name_for_display(gdk_display, "_NET_WM_PID"),
        XA_CARDINAL, &count);
    if (pid != NULL) {
        gboolean own = (pid_t)pid[0] == getpid();
        XFree(pid);
        if (own) {
            return TRUE;
        }
    }
    GListModel *toplevels = gtk_window_get_toplevels();
    guint total = g_list_model_get_n_items(toplevels);
    gboolean own = FALSE;
    for (guint index = 0; index < total && !own; index++) {
        GtkWindow *toplevel = g_list_model_get_item(toplevels, index);
        GdkSurface *surface = gtk_native_get_surface(GTK_NATIVE(toplevel));
        own = surface != NULL && GDK_IS_X11_SURFACE(surface) &&
              gdk_x11_surface_get_xid(surface) == window;
        g_object_unref(toplevel);
    }
    return own;
}

// Whether `window` is an ordinary application window this command should
// iconify: not a dock, desktop or other special type, not transient for
// another window (a dialog goes with its owner), and not already iconic.
// `window` 是否為此指令應圖示化的一般 app 視窗：不是 dock、桌面或其他特殊類型，不是另一個視窗的 transient
// (對話框跟著它的擁有者),也不是已經圖示化。
static gboolean scui_x11_is_ordinary(GdkDisplay *gdk_display, Display *display, Window window) {
    unsigned long count = 0;
    Atom type_property = gdk_x11_get_xatom_by_name_for_display(gdk_display, "_NET_WM_WINDOW_TYPE");
    unsigned long *types = scui_x11_property(display, window, type_property, XA_ATOM, &count);
    if (types != NULL) {
        Atom normal = gdk_x11_get_xatom_by_name_for_display(gdk_display, "_NET_WM_WINDOW_TYPE_NORMAL");
        Atom dialog = gdk_x11_get_xatom_by_name_for_display(gdk_display, "_NET_WM_WINDOW_TYPE_DIALOG");
        gboolean ordinary = types[0] == normal || types[0] == dialog;
        XFree(types);
        if (!ordinary) {
            return FALSE;
        }
    }
    Window owner = None;
    if (XGetTransientForHint(display, window, &owner) && owner != None) {
        return FALSE;
    }
    Atom wm_state = gdk_x11_get_xatom_by_name_for_display(gdk_display, "WM_STATE");
    unsigned long *state = scui_x11_property(display, window, wm_state, wm_state, &count);
    if (state != NULL) {
        gboolean iconic = state[0] == IconicState;
        XFree(state);
        if (iconic) {
            return FALSE;
        }
    }
    return !scui_x11_has_atom(
        display, window, gdk_x11_get_xatom_by_name_for_display(gdk_display, "_NET_WM_STATE"),
        gdk_x11_get_xatom_by_name_for_display(gdk_display, "_NET_WM_STATE_HIDDEN"));
}

#endif

gboolean scui_hide_others_supported(void) {
#if defined(G_OS_WIN32)
    return TRUE;
#elif defined(GDK_WINDOWING_X11) && !defined(__APPLE__)
    GdkDisplay *display = gdk_display_get_default();
    return display != NULL && GDK_IS_X11_DISPLAY(display);
#else
    return FALSE;
#endif
}

int scui_hide_other_applications(void) {
#if defined(G_OS_WIN32)
    if (scui_hidden_windows == NULL) {
        scui_hidden_windows = g_array_new(FALSE, FALSE, sizeof(HWND));
    }
    int count = 0;
    EnumWindows(scui_hide_one, (LPARAM)&count);
    return count;
#elif defined(GDK_WINDOWING_X11) && !defined(__APPLE__)
    GdkDisplay *gdk_display = gdk_display_get_default();
    if (gdk_display == NULL || !GDK_IS_X11_DISPLAY(gdk_display)) {
        return -1;
    }
    if (scui_hidden_windows == NULL) {
        scui_hidden_windows = g_array_new(FALSE, FALSE, sizeof(Window));
    }
    Display *display = gdk_x11_display_get_xdisplay(gdk_display);
    Window root = DefaultRootWindow(display);
    // A client may go away between being listed and being read; its BadWindow
    // is expected and ignored rather than reported through GDK's handler.
    // client 可能在被列出與被讀取之間消失；它的 BadWindow 是預期中的，忽略而不經 GDK 的處理器回報。
    gdk_x11_display_error_trap_push(gdk_display);
    GArray *clients = scui_x11_clients(gdk_display, display, root);
    int count = 0;
    for (guint index = 0; index < clients->len; index++) {
        Window window = g_array_index(clients, Window, index);
        if (scui_x11_is_own(gdk_display, display, window) ||
            !scui_x11_is_ordinary(gdk_display, display, window)) {
            continue;
        }
        // XIconifyWindow sends the ICCCM WM_CHANGE_STATE client message with
        // IconicState to the root window, which is how a client that is not the
        // window manager asks for any window to be iconified.
        // XIconifyWindow 對 root 視窗送出帶 IconicState 的 ICCCM WM_CHANGE_STATE client message,這正是
        // 非視窗管理員的 client 請求把任一視窗圖示化的方式。
        if (XIconifyWindow(display, window, DefaultScreen(display))) {
            gboolean known = FALSE;
            for (guint seen = 0; seen < scui_hidden_windows->len && !known; seen++) {
                known = g_array_index(scui_hidden_windows, Window, seen) == window;
            }
            if (!known) {
                g_array_append_val(scui_hidden_windows, window);
            }
            count++;
        }
    }
    g_array_free(clients, TRUE);
    XFlush(display);
    gdk_x11_display_error_trap_pop_ignored(gdk_display);
    return count;
#else
    return -1;
#endif
}

int scui_show_hidden_applications(void) {
#if defined(G_OS_WIN32)
    int count = 0;
    for (guint index = 0; scui_hidden_windows != NULL && index < scui_hidden_windows->len; index++) {
        HWND window = g_array_index(scui_hidden_windows, HWND, index);
        // Only what is still there and still minimised: a window the user
        // restored or closed in the meantime is left alone.
        // 只處理仍存在且仍最小化的視窗：期間已被使用者還原或關閉的視窗不去動它。
        if (IsWindow(window) && IsIconic(window) && ShowWindowAsync(window, SW_RESTORE)) {
            count++;
        }
    }
    if (scui_hidden_windows != NULL) {
        g_array_set_size(scui_hidden_windows, 0);
    }
    return count;
#elif defined(GDK_WINDOWING_X11) && !defined(__APPLE__)
    GdkDisplay *gdk_display = gdk_display_get_default();
    if (gdk_display == NULL || !GDK_IS_X11_DISPLAY(gdk_display) || scui_hidden_windows == NULL) {
        return gdk_display != NULL && GDK_IS_X11_DISPLAY(gdk_display) ? 0 : -1;
    }
    Display *display = gdk_x11_display_get_xdisplay(gdk_display);
    Atom wm_state = gdk_x11_get_xatom_by_name_for_display(gdk_display, "WM_STATE");
    int count = 0;
    gdk_x11_display_error_trap_push(gdk_display);
    for (guint index = 0; index < scui_hidden_windows->len; index++) {
        Window window = g_array_index(scui_hidden_windows, Window, index);
        unsigned long state_count = 0;
        unsigned long *state = scui_x11_property(display, window, wm_state, wm_state, &state_count);
        gboolean iconic = state != NULL && state[0] == IconicState;
        if (state != NULL) {
            XFree(state);
        }
        if (!iconic) {
            continue;
        }
        // ICCCM 4.1.4: a client goes from Iconic to Normal by being mapped; the
        // window manager receives the MapRequest and de-iconifies it.
        // ICCCM 4.1.4:client 被 map 即從 Iconic 回到 Normal;視窗管理員收到 MapRequest 後把它解除圖示化。
        XMapWindow(display, window);
        count++;
    }
    g_array_set_size(scui_hidden_windows, 0);
    XFlush(display);
    gdk_x11_display_error_trap_pop_ignored(gdk_display);
    return count;
#else
    return -1;
#endif
}
