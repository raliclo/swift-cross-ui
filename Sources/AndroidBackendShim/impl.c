#include "header.h"

#include <stdio.h>
#include <stdint.h>
#include <fcntl.h>
#include <unistd.h>
#include <android/looper.h>

void android_log(int priority, const char *tag, const char *message) {
    __android_log_write(priority, tag, message);
}

// Stdio buffering, set from C because `stdout` and `stderr` are mutable C
// globals and Swift 6 refuses to touch one.
//
// The diagnostic is right rather than pedantic -- they ARE shared mutable state
// -- and every Swift-side way around it is a way of not saying so: an
// `@preconcurrency` import hides the question, `nonisolated(unsafe)` asserts
// something about a variable this package does not own. Doing it in C is not a
// workaround; buffering a FILE is a C-level operation and this is the C target.
//
// WHY IT MATTERS AT ALL, because a line of setvbuf looks like tidying: C stdio
// picks its buffering from what the descriptor IS. A terminal gets line
// buffering; everything else gets a full 4 KB buffer. The `dup2` that sends
// stdout to logcat makes it a pipe, so from that call onwards `print` writes
// into a buffer flushed when full or at exit -- and an app killed with
// `am force-stop`, which is how every test here ends, never exits. That
// asymmetry was once recorded as "an Android app's print cannot reach logcat"
// and filed as a platform limit. It was these two lines.
//
// stdio 的緩衝設定,改由 C 執行,因為 `stdout` 與 `stderr` 是可變的 C 全域變數,而 Swift 6 拒絕碰
// 其中任何一個。
//
// 那個診斷是**對的**,不是吹毛求疵——它們**確實**是共享的可變狀態——而 Swift 這一側每一種繞法,都是
// 一種「不把這件事說出來」的方式:`@preconcurrency` import 把問題藏起來,`nonisolated(unsafe)` 則是
// 對一個本套件並不擁有的變數做出斷言。在 C 裡做這件事不是繞道:替一個 FILE 設定緩衝本來就是 C 層級
// 的操作,而這裡就是那個 C target。
//
// 它為何重要——因為一行 setvbuf 看起來像在做整理:C stdio 是依「該描述子**是什麼**」來決定緩衝方式
// 的。終端機得到行緩衝;其他一切得到完整的 4 KB 緩衝區。把 stdout 送往 logcat 的那個 `dup2` 使它成為
// 一條 pipe,因此自該次呼叫起,`print` 寫入的是一個「緩衝區滿了才沖、行程結束才沖」的緩衝區——而一個
// 以 `am force-stop` 終結的 app(此處每一次測試都是這樣結束的)永遠不會結束。那個不對稱曾被記錄為
// 「Android app 的 print 到不了 logcat」並當成平台限制。它其實就是這兩行。
void android_configure_stdio(void) {
    setvbuf(stdout, NULL, _IOLBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
}

// The main dispatch queue, drained when it has work rather than when polled.
//
// Until 2026-10-01 the only thing that drained it was MainRunLoopTickler, which
// runs RunLoop.main from a Handler posted every 50 ms at most. libdispatch hands
// main-queue work to a run loop by signalling a file descriptor; nothing was
// watching that descriptor, so every `Task { @MainActor }`,
// `DispatchQueue.main.async` and `asyncAfter` waited for the next tick. P66's
// 8 ms sampler saw 3 values of a 0.5 s animation where iOS saw 31, and every
// runInMainThread on Android carried up to 50 ms of latency.
//
// The descriptor is an eventfd on Linux-family platforms. The Looper watches it
// and calls back on the main thread; the callback empties the counter (the
// descriptor is set non-blocking first, so an empty counter cannot block) and
// drains the queue exactly as CFRunLoop would.
//
// 主 dispatch 佇列，在它有工作時就排空，而不是被輪詢時才排空。
//
// 2026-10-01 之前，唯一排空它的是 MainRunLoopTickler——它從一個最多每 50 ms 投遞一次的 Handler
// 執行 RunLoop.main。libdispatch 是以「對一個檔案描述子發訊號」把主佇列的工作交給 run loop 的;沒有
// 任何東西在看那個描述子，所以每一個 `Task { @MainActor }`、`DispatchQueue.main.async` 與
// `asyncAfter` 都要等下一次 tick。P66 的 8 ms 取樣器在 0.5 秒的動畫中只看到 3 個值，iOS 看到 31 個;
// Android 上每一次 runInMainThread 都帶著最多 50 ms 的延遲。
//
// 在 Linux 系平台上那個描述子是一個 eventfd。Looper 監看它並在主執行緒回呼;回呼先清空計數(描述子
// 事先設為非阻塞，計數為空時不會卡住),再如 CFRunLoop 一樣排空佇列。
extern int _dispatch_get_main_queue_handle_4CF(void);
extern void _dispatch_main_queue_callback_4CF(void *msg);

static int android_main_queue_ready(int fd, int events, void *data) {
    (void)events;
    (void)data;
    uint64_t count;
    while (read(fd, &count, sizeof count) > 0) {
    }
    _dispatch_main_queue_callback_4CF(NULL);
    return 1; // keep watching
}

int android_attach_main_queue_to_looper(void) {
    ALooper *looper = ALooper_forThread();
    if (looper == NULL) {
        return -1;
    }
    int fd = _dispatch_get_main_queue_handle_4CF();
    if (fd < 0) {
        return -2;
    }
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags >= 0 && !(flags & O_NONBLOCK)) {
        fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    }
    if (ALooper_addFd(looper, fd, ALOOPER_POLL_CALLBACK, ALOOPER_EVENT_INPUT,
                      android_main_queue_ready, NULL) != 1) {
        return -3;
    }
    return 0;
}
