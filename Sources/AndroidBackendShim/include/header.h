#include <android/log.h>

// We use this forward declaration to call the app's main function without ever
// being given a handle to it.
int main(int argc, char **argv);

void android_log(int priority, const char *tag, const char *message);

// See impl.c for why this is in C rather than Swift.
// 為何這件事寫在 C 而不是 Swift 裡,見 impl.c。
void android_configure_stdio(void);
