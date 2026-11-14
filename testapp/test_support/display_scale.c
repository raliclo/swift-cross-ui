// display_scale -- read or set each active display's scale (100%, 125%, ...).
//
//   display_scale get          print "display N: WxH scale P% (recommended R%)"
//   display_scale set 125      set every active display to 125%, then print
//
// For todo item 14 (2026-11-14): CI's windows-latest runner is 1920x1080 at
// 100% while testapp/actions/win was measured at 125%, and the user chose to
// try putting the runner at 125%. Per-monitor scale goes through
// DisplayConfigGetDeviceInfo / DisplayConfigSetDeviceInfo with the
// undocumented request types -3 (get) and -4 (set) that Settings itself uses;
// the values are steps relative to the display's recommended scale. The
// LogPixels registry value is not used: it needs a new sign-in.
// Exit 0 when every display reads back the requested scale, 1 otherwise.
//
// display_scale -- 讀取或設定每個作用中顯示器的縮放(100%、125%……)。為 todo 第 14 項(2026-11-14):CI 的 windows-latest
// runner 是 1920x1080、100%,而 testapp/actions/win 是在 125% 下量的，使用者選擇嘗試把 runner 設成 125%。每台顯示器的縮放
// 透過 DisplayConfigGetDeviceInfo / DisplayConfigSetDeviceInfo,使用「設定」本身用的未公開請求型別 -3(讀)與 -4(寫);
// 數值是相對於顯示器建議縮放的級數。不用 LogPixels 登錄值：它需要重新登入。每台顯示器讀回的都是要求的縮放時結束碼為 0,否則為 1。

#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <shellscalingapi.h>

typedef struct {
    DISPLAYCONFIG_DEVICE_INFO_HEADER header;
    INT32 minScaleRel;
    INT32 curScaleRel;
    INT32 maxScaleRel;
} ScaleGet;

typedef struct {
    DISPLAYCONFIG_DEVICE_INFO_HEADER header;
    INT32 scaleRel;
} ScaleSet;

static const UINT32 kScales[] = {100, 125, 150, 175, 200, 225, 250, 300, 350, 400, 450, 500};
static const int kScaleCount = (int)(sizeof kScales / sizeof kScales[0]);

static int read_scale(const DISPLAYCONFIG_PATH_INFO *path, int *current, int *recommended) {
    ScaleGet get;
    memset(&get, 0, sizeof get);
    get.header.type = (DISPLAYCONFIG_DEVICE_INFO_TYPE)-3;
    get.header.size = sizeof get;
    get.header.adapterId = path->sourceInfo.adapterId;
    get.header.id = path->sourceInfo.id;
    if (DisplayConfigGetDeviceInfo(&get.header) != ERROR_SUCCESS) {
        return 0;
    }
    int base = -get.minScaleRel;
    int index = base + get.curScaleRel;
    if (base < 0 || base >= kScaleCount || index < 0 || index >= kScaleCount) {
        return 0;
    }
    *recommended = (int)kScales[base];
    *current = (int)kScales[index];
    return 1;
}

int main(int argc, char **argv) {
    int setting = argc == 3 && strcmp(argv[1], "set") == 0;
    if (!setting && !(argc == 2 && strcmp(argv[1], "get") == 0)) {
        fprintf(stderr, "usage: display_scale get | display_scale set <percent>\n");
        return 64;
    }
    int target = setting ? atoi(argv[2]) : 0;
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    // Per-monitor aware, so GetDpiForMonitor below reports the real scale. / per-monitor aware,下方的 GetDpiForMonitor 才會回報真正的縮放。

    UINT32 pathCount = 0, modeCount = 0;
    if (GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, &pathCount, &modeCount) != ERROR_SUCCESS) {
        fprintf(stderr, "GetDisplayConfigBufferSizes failed\n");
        return 1;
    }
    DISPLAYCONFIG_PATH_INFO *paths = calloc(pathCount, sizeof *paths);
    DISPLAYCONFIG_MODE_INFO *modes = calloc(modeCount, sizeof *modes);
    if (paths == NULL || modes == NULL ||
        QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, &pathCount, paths, &modeCount, modes, NULL) != ERROR_SUCCESS) {
        fprintf(stderr, "QueryDisplayConfig failed\n");
        return 1;
    }

    int ok = pathCount > 0;
    for (UINT32 i = 0; i < pathCount; i++) {
        int current = 0, recommended = 0;
        if (!read_scale(&paths[i], &current, &recommended)) {
            printf("display %u: scale unreadable\n", i);
            ok = 0;
            continue;
        }
        if (setting && current != target) {
            int base = -1, wanted = -1;
            for (int k = 0; k < kScaleCount; k++) {
                if ((int)kScales[k] == recommended) base = k;
                if ((int)kScales[k] == target) wanted = k;
            }
            if (base < 0 || wanted < 0) {
                printf("display %u: %d%% is not a scale this tool knows\n", i, target);
                ok = 0;
                continue;
            }
            ScaleSet set;
            memset(&set, 0, sizeof set);
            set.header.type = (DISPLAYCONFIG_DEVICE_INFO_TYPE)-4;
            set.header.size = sizeof set;
            set.header.adapterId = paths[i].sourceInfo.adapterId;
            set.header.id = paths[i].sourceInfo.id;
            set.scaleRel = wanted - base;
            LONG status = DisplayConfigSetDeviceInfo(&set.header);
            if (status != ERROR_SUCCESS) {
                printf("display %u: DisplayConfigSetDeviceInfo failed: %ld\n", i, status);
            }
            read_scale(&paths[i], &current, &recommended);
        }
        DEVMODEW mode;
        memset(&mode, 0, sizeof mode);
        mode.dmSize = sizeof mode;
        DISPLAYCONFIG_SOURCE_DEVICE_NAME name;
        memset(&name, 0, sizeof name);
        name.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME;
        name.header.size = sizeof name;
        name.header.adapterId = paths[i].sourceInfo.adapterId;
        name.header.id = paths[i].sourceInfo.id;
        int haveMode = DisplayConfigGetDeviceInfo(&name.header) == ERROR_SUCCESS &&
                       EnumDisplaySettingsW(name.viewGdiDeviceName, ENUM_CURRENT_SETTINGS, &mode);
        printf("display %u: %lux%lu scale %d%% (recommended %d%%)\n", i,
               haveMode ? (unsigned long)mode.dmPelsWidth : 0UL,
               haveMode ? (unsigned long)mode.dmPelsHeight : 0UL, current, recommended);
        if (setting && current != target) {
            ok = 0;
        }
    }
    // What a process started now sees: the primary display's effective DPI to a
    // per-monitor-aware process (this one, see main). Run `get` as a fresh
    // process after `set` and this is what the apps launched afterwards get --
    // the number that matters, since a scale the API reports but apps do not see
    // would change nothing.
    // 現在啟動的行程看到什麼：主顯示器對 per-monitor-aware 行程(本行程，見 main)的有效 DPI。在 `set` 之後以新行程執行 `get`,
    // 印出的就是之後啟動的 app 會拿到的值——這才是重要的數字，因為 API 回報了、app 卻看不到的縮放什麼都不會改變。
    HMONITOR primary = MonitorFromPoint((POINT){0, 0}, MONITOR_DEFAULTTOPRIMARY);
    UINT dpiX = 0, dpiY = 0;
    if (primary != NULL && GetDpiForMonitor(primary, MDT_EFFECTIVE_DPI, &dpiX, &dpiY) == S_OK) {
        printf("effective dpi %u (%u%%) for a process started now\n", dpiX, dpiX * 100 / 96);
    }
    return ok ? 0 : 1;
}
