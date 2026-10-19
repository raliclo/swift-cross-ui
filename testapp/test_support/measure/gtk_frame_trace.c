// gtk_frame_trace.c -- logs, with one clock, every event that decides when a
// GTK app on macOS draws its next frame: CVDisplayLinkStart/Stop, every
// CVDisplayLink output callback, and every tick callback installed with
// gtk_widget_add_tick_callback (with the GdkFrameClock's frame counter, frame
// time, refresh interval and the previous frame's timings).
//
// It is injected with DYLD_INSERT_LIBRARIES and interposes the calls, so the app
// and GTK are run unmodified. Times are microseconds of mach_absolute_time, the
// clock g_get_monotonic_time and GDK's presentation times use on macOS.
//
// gtk_frame_trace.c——以同一個時鐘記錄決定 macOS 上 GTK app 何時畫下一幀的每一個事件:
// CVDisplayLinkStart/Stop、每一次 CVDisplayLink 輸出 callback,以及每一個以
// gtk_widget_add_tick_callback 安裝的 tick callback(附 GdkFrameClock 的幀計數、幀時間、
// 更新間隔與前一幀的 timings)。以 DYLD_INSERT_LIBRARIES 注入並 interpose 這些呼叫，因此 app 與 GTK
// 都不必修改。時間是 mach_absolute_time 的微秒，也就是 macOS 上 g_get_monotonic_time 與 GDK
// presentation time 所用的時鐘。
//
// Build / 建置:
//   cc -dynamiclib -O2 -o /tmp/gtk_frame_trace.dylib \
//      testapp/test_support/measure/gtk_frame_trace.c \
//      -framework CoreVideo -L/opt/homebrew/lib -lgtk-4 -lgobject-2.0
// Run / 執行:
//   GTK_FRAME_TRACE=/tmp/trace.log DYLD_INSERT_LIBRARIES=/tmp/gtk_frame_trace.dylib APP
// Lines / 各行:
//   start T link=L | stop T link=L | cv T out=OUTPUT_T link=L   (CVDisplayLink, any thread)
//   tick T ft=FRAME_TIME n=FRAME_COUNTER ri=REFRESH_INTERVAL prev_pt=PRESENTATION_TIME
//   paint T                                  (the frame clock's after-paint, so tick to paint is the frame's work)

#include <CoreVideo/CoreVideo.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct _GtkWidget GtkWidget;
typedef struct _GdkFrameClock GdkFrameClock;
typedef struct _GdkFrameTimings GdkFrameTimings;
typedef int (*GtkTickCallback)(GtkWidget *, GdkFrameClock *, void *);
typedef void (*GDestroyNotify)(void *);

extern unsigned gtk_widget_add_tick_callback(GtkWidget *, GtkTickCallback, void *, GDestroyNotify);
extern int64_t gdk_frame_clock_get_frame_time(GdkFrameClock *);
extern int64_t gdk_frame_clock_get_frame_counter(GdkFrameClock *);
extern void gdk_frame_clock_get_refresh_info(GdkFrameClock *, int64_t, int64_t *, int64_t *);
extern GdkFrameTimings *gdk_frame_clock_get_timings(GdkFrameClock *, int64_t);
extern int64_t gdk_frame_timings_get_presentation_time(GdkFrameTimings *);
extern unsigned long g_signal_connect_data(void *, const char *, void *, void *, void *, int);

static FILE *trace_file;
static pthread_once_t trace_once = PTHREAD_ONCE_INIT;

static void trace_open(void) {
    const char *path = getenv("GTK_FRAME_TRACE");
    trace_file = fopen(path ? path : "/dev/stderr", "w");
}

static int64_t now_us(void) {
    static mach_timebase_info_data_t base;
    if (base.denom == 0) mach_timebase_info(&base);
    return (int64_t)((__uint128_t)mach_absolute_time() * base.numer / base.denom / 1000);
}

static int64_t host_us(uint64_t host) {
    static mach_timebase_info_data_t base;
    if (base.denom == 0) mach_timebase_info(&base);
    return (int64_t)((__uint128_t)host * base.numer / base.denom / 1000);
}

#define TRACE(...)                                  \
    do {                                            \
        pthread_once(&trace_once, trace_open);      \
        if (trace_file) {                           \
            fprintf(trace_file, __VA_ARGS__);       \
            fflush(trace_file);                     \
        }                                           \
    } while (0)

// CVDisplayLink / CVDisplayLink 部分

typedef struct {
    CVDisplayLinkOutputCallback callback;
    void *user;
} OutputBox;

static CVReturn traced_output(CVDisplayLinkRef link, const CVTimeStamp *now, const CVTimeStamp *out,
                              CVOptionFlags in, CVOptionFlags *flags, void *pointer) {
    OutputBox *box = pointer;
    TRACE("cv %lld out=%lld link=%p\n", (long long)now_us(), (long long)host_us(out->hostTime), (void *)link);
    return box->callback(link, now, out, in, flags, box->user);
}

static CVReturn my_set_output(CVDisplayLinkRef link, CVDisplayLinkOutputCallback cb, void *user) {
    OutputBox *box = malloc(sizeof *box);
    box->callback = cb;
    box->user = user;
    return CVDisplayLinkSetOutputCallback(link, traced_output, box);
}

static CVReturn my_start(CVDisplayLinkRef link) {
    TRACE("start %lld link=%p\n", (long long)now_us(), (void *)link);
    return CVDisplayLinkStart(link);
}

static CVReturn my_stop(CVDisplayLinkRef link) {
    TRACE("stop %lld link=%p\n", (long long)now_us(), (void *)link);
    return CVDisplayLinkStop(link);
}

// Tick callbacks / tick callback 部分

typedef struct {
    GtkTickCallback callback;
    void *data;
    GDestroyNotify destroy;
} TickBox;

static void traced_after_paint(GdkFrameClock *clock, void *data) {
    (void)clock;
    (void)data;
    TRACE("paint %lld\n", (long long)now_us());
}

static int traced_tick(GtkWidget *widget, GdkFrameClock *clock, void *pointer) {
    TickBox *box = pointer;
    static GdkFrameClock *connected;
    if (connected != clock) {
        connected = clock;
        g_signal_connect_data(clock, "after-paint", (void *)traced_after_paint, NULL, NULL, 0);
    }
    int64_t counter = gdk_frame_clock_get_frame_counter(clock);
    int64_t refresh = 0, presentation = 0;
    gdk_frame_clock_get_refresh_info(clock, gdk_frame_clock_get_frame_time(clock), &refresh, NULL);
    GdkFrameTimings *previous = gdk_frame_clock_get_timings(clock, counter - 1);
    if (previous) presentation = gdk_frame_timings_get_presentation_time(previous);
    TRACE("tick %lld ft=%lld n=%lld ri=%lld prev_pt=%lld\n", (long long)now_us(),
          (long long)gdk_frame_clock_get_frame_time(clock), (long long)counter, (long long)refresh,
          (long long)presentation);
    return box->callback(widget, clock, box->data);
}

static void traced_destroy(void *pointer) {
    TickBox *box = pointer;
    if (box->destroy) box->destroy(box->data);
    free(box);
}

static unsigned my_add_tick(GtkWidget *widget, GtkTickCallback callback, void *data, GDestroyNotify destroy) {
    TickBox *box = malloc(sizeof *box);
    box->callback = callback;
    box->data = data;
    box->destroy = destroy;
    return gtk_widget_add_tick_callback(widget, traced_tick, box, traced_destroy);
}

#define INTERPOSE(replacement, original)                                              \
    __attribute__((used)) static struct { const void *r; const void *o; } interpose_##original \
        __attribute__((section("__DATA,__interpose"))) = {(const void *)replacement, (const void *)original}

INTERPOSE(my_set_output, CVDisplayLinkSetOutputCallback);
INTERPOSE(my_start, CVDisplayLinkStart);
INTERPOSE(my_stop, CVDisplayLinkStop);
INTERPOSE(my_add_tick, gtk_widget_add_tick_callback);
