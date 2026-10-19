// The main dispatch queue, drained when it has work rather than when polled.
//
// GtkBackend on Linux and Windows drained it only from its run-loop tickler, a
// g_timeout of up to 50 ms that services RunLoop.main. libdispatch hands main-
// queue work to a run loop by signalling a handle, and nothing in GLib's loop
// watched that handle, so every `DispatchQueue.main.async`, `asyncAfter` and
// `Task { @MainActor }` waited for the next tick. P66's 8 ms sampler saw 2
// values of a 0.5 s animation on Windows GTK (2026-10-19), where AppKit sees
// 31; AndroidBackend had the same fault and the same cure on 2026-10-01
// (AndroidBackendShim/impl.c).
//
// On Linux the handle is an eventfd: GLib watches it, and the callback empties
// the counter (non-blocking, so an empty one cannot block) and drains the queue
// as CFRunLoop would. On Windows it is an event: a one-shot thread-pool wait
// hands the drain to the main loop with g_idle_add_full, which is safe from any
// thread, and the drain arms the next wait. The wait consumes the event's
// signal, so the drain has to be ours -- RunLoop.main no longer sees it.
// macOS is not served here: GDK runs on the CFRunLoop there, which already
// watches the port.
//
// 主 dispatch 佇列，在它有工作時就排空，而不是被輪詢時才排空。
//
// GtkBackend 在 Linux 與 Windows 上只靠 run-loop tickler 排空它——一個最多 50 ms 的 g_timeout,用來服務
// RunLoop.main。libdispatch 是以「對一個 handle 發訊號」把主佇列的工作交給 run loop 的，而 GLib 的迴圈沒有
// 任何東西在看那個 handle，所以每一個 `DispatchQueue.main.async`、`asyncAfter` 與 `Task { @MainActor }`
// 都要等下一次 tick。P66 的 8 ms 取樣器在 Windows GTK 上對 0.5 秒的動畫只看到 2 個值(2026-10-19),AppKit
// 看到 31 個;AndroidBackend 在 2026-10-01 有同樣的問題、同樣的解法(AndroidBackendShim/impl.c)。
//
// 在 Linux 上那個 handle 是 eventfd:GLib 監看它，回呼先清空計數(非阻塞，空的計數不會卡住)，再如 CFRunLoop
// 一樣排空佇列。在 Windows 上它是一個事件：一次性的執行緒池等待以 g_idle_add_full(可從任何執行緒呼叫)把排空
// 交給主迴圈，排空完再設下一次等待。等待會消耗掉事件的訊號，所以排空必須由我們做——RunLoop.main 不會再看到它。
// macOS 不在此處處理:GDK 在那裡跑在 CFRunLoop 上，而 CFRunLoop 本來就監看那個 port。

#include "include/gtk_helpers.h"

#if defined(G_OS_WIN32)

#include <windows.h>

extern void *_dispatch_get_main_queue_handle_4CF(void);
extern void _dispatch_main_queue_callback_4CF(void *msg);

static HANDLE scui_main_queue_wait;

static void scui_arm_main_queue_wait(void);

static gboolean scui_drain_main_queue(gpointer data) {
    (void)data;
    _dispatch_main_queue_callback_4CF(NULL);
    scui_arm_main_queue_wait();
    return G_SOURCE_REMOVE;
}

static VOID CALLBACK scui_main_queue_signalled(PVOID context, BOOLEAN timed_out) {
    (void)context;
    (void)timed_out;
    g_idle_add_full(G_PRIORITY_DEFAULT, scui_drain_main_queue, NULL, NULL);
}

static void scui_arm_main_queue_wait(void) {
    if (scui_main_queue_wait != NULL) {
        UnregisterWait(scui_main_queue_wait);
        scui_main_queue_wait = NULL;
    }
    HANDLE handle = _dispatch_get_main_queue_handle_4CF();
    if (handle == NULL) {
        return;
    }
    if (!RegisterWaitForSingleObject(&scui_main_queue_wait, handle, scui_main_queue_signalled,
                                     NULL, INFINITE, WT_EXECUTEONLYONCE)) {
        scui_main_queue_wait = NULL;
    }
}

gboolean scui_watch_dispatch_main_queue(void) {
    scui_arm_main_queue_wait();
    return scui_main_queue_wait != NULL;
}

#elif defined(__linux__)

#include <fcntl.h>
#include <glib-unix.h>
#include <stdint.h>
#include <unistd.h>

extern int _dispatch_get_main_queue_handle_4CF(void);
extern void _dispatch_main_queue_callback_4CF(void *msg);

static gboolean scui_main_queue_ready(gint fd, GIOCondition condition, gpointer data) {
    (void)condition;
    (void)data;
    uint64_t count;
    while (read(fd, &count, sizeof count) > 0) {
    }
    _dispatch_main_queue_callback_4CF(NULL);
    return G_SOURCE_CONTINUE;
}

gboolean scui_watch_dispatch_main_queue(void) {
    int fd = _dispatch_get_main_queue_handle_4CF();
    if (fd < 0) {
        return FALSE;
    }
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags >= 0 && !(flags & O_NONBLOCK)) {
        fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    }
    g_unix_fd_add(fd, G_IO_IN, scui_main_queue_ready, NULL);
    return TRUE;
}

#else

gboolean scui_watch_dispatch_main_queue(void) {
    return FALSE;
}

#endif
