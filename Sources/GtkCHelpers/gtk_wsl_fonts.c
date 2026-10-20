// Windows' own UI font for GTK under WSL.
//
// WSLg's GTK falls back to DejaVu Sans, which has a regular and a bold face
// only, so the nine weights P22 draws came out as two (2026-10-20), and the
// text looked unlike the same app on Windows GTK (Segoe UI) and on GTK on the
// Mac (the system font). The Windows fonts are on disk at /mnt/c/Windows/Fonts
// but fontconfig does not look there. Only the files named here are added --
// not the directory: scanning a thousand fonts over WSL's 9p file system costs
// seconds at every launch.
//
// 在 WSL 下為 GTK 使用 Windows 自己的介面字型。WSLg 的 GTK 退回 DejaVu Sans,它只有一般與粗體兩種字面，因此
// P22 畫的九種字重只出現兩種(2026-10-20),文字看起來也與同一支 app 在 Windows GTK(Segoe UI)及 Mac 上的 GTK
// (系統字型)不同。Windows 字型就在 /mnt/c/Windows/Fonts,但 fontconfig 不會去那裡找。只加入此處指名的檔案
// ——而非整個資料夾:經由 WSL 的 9p 檔案系統掃描上千個字型，每次啟動都要花上數秒。

#include "include/gtk_helpers.h"

#if defined(__linux__)
#include <dirent.h>
#include <fontconfig/fontconfig.h>
#include <stdio.h>
#include <string.h>
#include <strings.h>
#endif

int scui_add_font_files(const char *directory, const char *prefix) {
#if defined(__linux__)
    if (!directory || !prefix) return 0;
    DIR *dir = opendir(directory);
    if (!dir) return 0;
    size_t prefixLength = strlen(prefix);
    int added = 0;
    char path[4096];
    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL) {
        const char *name = entry->d_name;
        size_t length = strlen(name);
        if (strncasecmp(name, prefix, prefixLength) != 0) continue;
        if (length < 4 || strcasecmp(name + length - 4, ".ttf") != 0) continue;
        if (snprintf(path, sizeof path, "%s/%s", directory, name) >= (int)sizeof path) continue;
        if (FcConfigAppFontAddFile(NULL, (const FcChar8 *)path)) added++;
    }
    closedir(dir);
    return added;
#else
    (void)directory;
    (void)prefix;
    return 0;
#endif
}
