// MainActivity.setup() -> AndroidBackend's entry point.
//
// Compiled by testapp/package_android.zsh with the NDK's clang and linked
// against lib<app>.so, so the APK's native code needs no CMake step in Gradle.
// The symbol is fixed because MainActivity's class is (see build.gradle.kts).
// 由 testapp/package_android.zsh 以 NDK 的 clang 編譯並連結 lib<app>.so,因此 Gradle 裡不需要 CMake 步驟。
// 符號固定，因為 MainActivity 的類別固定(見 build.gradle.kts)。
#include <jni.h>

void AndroidBackend_entrypoint(JNIEnv *env, jobject activity);

JNIEXPORT void JNICALL
Java_dev_swiftcrossui_testapp_MainActivity_setup(JNIEnv *env, jobject activity) {
    AndroidBackend_entrypoint(env, activity);
}
