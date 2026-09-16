#include "header.h"

#include <stdio.h>

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
