// What GtkBackend listens to for the graphics adapter in use going away, and
// the adapter identities it compares before and after.
//
// Windows: DXGI. IDXGIFactory7::RegisterAdaptersChangedEvent signals an event
// whenever the adapter enumeration changes (an adapter added or removed, a
// driver installed or upgraded); the adapters are then listed again by LUID.
// dxgi.dll is opened at run time rather than linked, so this target's link
// line is unchanged.
//
// WSL: DXCore, the adapter list Mesa's d3d12 driver renders through. An
// IDXCoreAdapterList goes stale when the set of adapters changes; DXCore
// reports that through RegisterEventNotification(AdapterListStale) where the
// notification type is supported, and otherwise the list is asked every two
// seconds (IsStale is a flag read, not an enumeration).
//
// Linux with DRM cards: the kernel's uevents on a NETLINK_KOBJECT_UEVENT socket,
// the same messages `udevadm monitor --kernel` prints, readable without
// privileges. A drm or pci device being removed or unbound from its driver
// counts; GtkBackend then lists /sys/class/drm again.
//
// In every case `changed` is called on the GTK main thread, and only means the
// set may have changed: GtkBackend compares the adapter it renders on with the
// new list (GraphicsAdapterRemovalWatch) and fires adapterRemoved only when
// that one is gone.
//
// GtkBackend 為「使用中的繪圖介面卡消失」所監聽的訊號，以及它前後比對的介面卡識別。
//
// Windows:DXGI。IDXGIFactory7::RegisterAdaptersChangedEvent 會在介面卡列舉改變時(新增或移除介面卡、安裝或
// 升級驅動)觸發一個事件，接著以 LUID 重新列出介面卡。dxgi.dll 在執行時開啟而非連結，所以本 target 的連結設定不變。
//
// WSL:DXCore,即 Mesa 的 d3d12 驅動所用的介面卡清單。介面卡集合改變時 IDXCoreAdapterList 會變成 stale;在支援該
// 通知類型時 DXCore 經 RegisterEventNotification(AdapterListStale)通知，否則每兩秒問一次清單(IsStale 只是讀旗標，
// 不是重新列舉)。
//
// 有 DRM 顯示卡的 Linux:核心在 NETLINK_KOBJECT_UEVENT socket 上送出的 uevent,也就是 `udevadm monitor --kernel`
// 印出的訊息，不需特權即可讀取。drm 或 pci 裝置被移除或與驅動解除綁定時算數;GtkBackend 接著重新列出 /sys/class/drm。
//
// 所有情況下 `changed` 都在 GTK 主執行緒上呼叫，而且只代表「集合可能變了」:GtkBackend 會把它繪製所用的介面卡與
// 新清單比對(GraphicsAdapterRemovalWatch),只有那一張不見了才觸發 adapterRemoved。

#include "include/gtk_helpers.h"

#include <stdint.h>
#include <string.h>

static void (*scui_adapter_changed)(void);

static gboolean scui_adapter_changed_on_main(gpointer unused) {
    (void)unused;
    if (scui_adapter_changed != NULL) {
        scui_adapter_changed();
    }
    return G_SOURCE_REMOVE;
}

#ifdef G_OS_WIN32

#include <windows.h>
#include <dxgi1_6.h>

// Written out rather than taken from dxguid.lib, which this target does not link.
// 直接寫出而不取自 dxguid.lib,本 target 沒有連結它。
static const GUID scui_iid_dxgi_factory1 = {
    0x770aae78, 0xf26f, 0x4dba, {0xa8, 0x29, 0x25, 0x3c, 0x83, 0xd1, 0xb3, 0x87}};
static const GUID scui_iid_dxgi_factory6 = {
    0xc1b6694f, 0xff09, 0x44a9, {0xb0, 0x3c, 0x77, 0x90, 0x0a, 0x0a, 0x1d, 0x17}};
static const GUID scui_iid_dxgi_factory7 = {
    0xa4966eed, 0x76db, 0x44da, {0x84, 0xc1, 0xee, 0x9a, 0x7a, 0xfb, 0x20, 0xa8}};
static const GUID scui_iid_dxgi_adapter1 = {
    0x29038f61, 0x3839, 0x4626, {0x91, 0xfd, 0x08, 0x68, 0x79, 0x01, 0x1a, 0x05}};

typedef HRESULT(WINAPI *scui_create_dxgi_factory1)(REFIID, void **);

static IDXGIFactory1 *scui_dxgi_factory(void) {
    static scui_create_dxgi_factory1 create = NULL;
    static gboolean looked = FALSE;
    if (!looked) {
        looked = TRUE;
        HMODULE dxgi = LoadLibraryW(L"dxgi.dll");
        if (dxgi != NULL) {
            create = (scui_create_dxgi_factory1)GetProcAddress(dxgi, "CreateDXGIFactory1");
        }
    }
    IDXGIFactory1 *factory = NULL;
    if (create == NULL || FAILED(create(&scui_iid_dxgi_factory1, (void **)&factory))) {
        return NULL;
    }
    return factory;
}

static uint64_t scui_luid_value(LUID luid) {
    return ((uint64_t)(uint32_t)luid.HighPart << 32) | (uint64_t)luid.LowPart;
}

// Fills `out` from one adapter unless it is a software one (WARP, the Basic
// Render Driver): those draw on the CPU and are never the GPU that can go away.
// 由一張介面卡填入 `out`,軟體介面卡(WARP、Basic Render Driver)除外：它們在 CPU 上繪製，不會是那張會消失的 GPU。
static gboolean scui_dxgi_identity(IDXGIAdapter1 *adapter, scui_adapter_identity *out) {
    DXGI_ADAPTER_DESC1 description;
    memset(&description, 0, sizeof description);
    if (FAILED(adapter->lpVtbl->GetDesc1(adapter, &description)) ||
        (description.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) != 0) {
        return FALSE;
    }
    memset(out, 0, sizeof *out);
    out->luid = scui_luid_value(description.AdapterLuid);
    WideCharToMultiByte(CP_UTF8, 0, description.Description, -1, out->name,
                        (int)sizeof out->name - 1, NULL, NULL);
    return TRUE;
}

int scui_adapter_identities(scui_adapter_identity *out, int capacity) {
    IDXGIFactory1 *factory = scui_dxgi_factory();
    if (factory == NULL) {
        return 0;
    }
    int written = 0;
    for (UINT index = 0; written < capacity; index++) {
        IDXGIAdapter1 *adapter = NULL;
        if (FAILED(factory->lpVtbl->EnumAdapters1(factory, index, &adapter)) || adapter == NULL) {
            break;
        }
        if (scui_dxgi_identity(adapter, &out[written])) {
            written++;
        }
        adapter->lpVtbl->Release(adapter);
    }
    factory->lpVtbl->Release(factory);
    return written;
}

guint64 scui_dxgi_preferred_adapter_luid(int preference) {
    IDXGIFactory1 *factory = scui_dxgi_factory();
    if (factory == NULL) {
        return 0;
    }
    IDXGIFactory6 *factory6 = NULL;
    uint64_t luid = 0;
    if (SUCCEEDED(factory->lpVtbl->QueryInterface(factory, &scui_iid_dxgi_factory6,
                                                  (void **)&factory6))) {
        for (UINT index = 0; luid == 0; index++) {
            IDXGIAdapter1 *adapter = NULL;
            if (FAILED(factory6->lpVtbl->EnumAdapterByGpuPreference(
                    factory6, index, (DXGI_GPU_PREFERENCE)preference, &scui_iid_dxgi_adapter1,
                    (void **)&adapter)) ||
                adapter == NULL) {
                break;
            }
            scui_adapter_identity identity;
            if (scui_dxgi_identity(adapter, &identity)) {
                luid = identity.luid;
            }
            adapter->lpVtbl->Release(adapter);
        }
        factory6->lpVtbl->Release(factory6);
    }
    factory->lpVtbl->Release(factory);
    return luid;
}

static HANDLE scui_adapters_event;
static IDXGIFactory7 *scui_watched_factory;
static DWORD scui_watched_cookie;

// Registers the event with a fresh factory. Done again after every signal: a
// factory describes the adapters as they were when it was made, so the next
// change is watched through one that knows the current set.
// 以新的 factory 註冊事件。每次訊號後都重做一次:factory 描述的是它建立當時的介面卡，因此下一次變更要透過知道目前
// 集合的 factory 來監看。
static gboolean scui_register_adapters_event(void) {
    if (scui_watched_factory != NULL) {
        scui_watched_factory->lpVtbl->UnregisterAdaptersChangedEvent(scui_watched_factory,
                                                                     scui_watched_cookie);
        scui_watched_factory->lpVtbl->Release(scui_watched_factory);
        scui_watched_factory = NULL;
    }
    IDXGIFactory1 *factory = scui_dxgi_factory();
    if (factory == NULL) {
        return FALSE;
    }
    IDXGIFactory7 *factory7 = NULL;
    HRESULT result = factory->lpVtbl->QueryInterface(factory, &scui_iid_dxgi_factory7,
                                                     (void **)&factory7);
    factory->lpVtbl->Release(factory);
    if (FAILED(result) || factory7 == NULL) {
        return FALSE;
    }
    if (FAILED(factory7->lpVtbl->RegisterAdaptersChangedEvent(factory7, scui_adapters_event,
                                                              &scui_watched_cookie))) {
        factory7->lpVtbl->Release(factory7);
        return FALSE;
    }
    scui_watched_factory = factory7;
    return TRUE;
}

static gboolean scui_adapters_changed_on_main(gpointer unused) {
    scui_register_adapters_event();
    return scui_adapter_changed_on_main(unused);
}

// On a thread-pool thread; the work goes to the GTK main loop.
// 在 thread pool 的執行緒上；工作交給 GTK 主迴圈。
static VOID CALLBACK scui_adapters_signalled(PVOID context, BOOLEAN timed_out) {
    (void)context;
    (void)timed_out;
    g_idle_add(scui_adapters_changed_on_main, NULL);
}

int scui_adapter_watch_start(void (*changed)(void)) {
    static int mode = -1;
    scui_adapter_changed = changed;
    if (mode >= 0) {
        return mode;
    }
    mode = 0;
    scui_adapters_event = CreateEventW(NULL, FALSE, FALSE, NULL);
    HANDLE wait = NULL;
    if (scui_adapters_event == NULL || !scui_register_adapters_event() ||
        !RegisterWaitForSingleObject(&wait, scui_adapters_event, scui_adapters_signalled, NULL,
                                     INFINITE, WT_EXECUTEDEFAULT)) {
        return mode;
    }
    mode = 2;
    return mode;
}

gboolean scui_uevent_is_adapter_removal(const char *message, int length) {
    (void)message;
    (void)length;
    return FALSE;
}

#elif defined(__linux__)

#include <dlfcn.h>
#include <glib-unix.h>
#include <linux/netlink.h>
#include <stdint.h>
#include <sys/socket.h>
#include <unistd.h>

// The DXCore interfaces as gtk_dxcore.c describes them: COM with the plain
// three-slot IUnknown, each interface's own methods from slot 3 in
// dxcore_interface.h's order.
// DXCore 介面，與 gtk_dxcore.c 所述相同：採一般三格 IUnknown 的 COM,各介面自己的方法從第 3 格起，順序同
// dxcore_interface.h。
typedef struct {
    uint32_t a;
    uint16_t b, c;
    uint8_t d[8];
} scui_watch_guid;

typedef struct {
    void **vtbl;
} scui_watch_object;

typedef int32_t (*scui_watch_create_factory)(const scui_watch_guid *, void **);
typedef int32_t (*scui_watch_create_list)(scui_watch_object *, uint32_t, const scui_watch_guid *,
                                          const scui_watch_guid *, void **);
typedef uint32_t (*scui_watch_list_count)(scui_watch_object *);
typedef int32_t (*scui_watch_list_get)(scui_watch_object *, uint32_t, const scui_watch_guid *,
                                       void **);
typedef uint8_t (*scui_watch_list_is_stale)(scui_watch_object *);
typedef int32_t (*scui_watch_get_property)(scui_watch_object *, uint32_t, size_t, void *);
typedef uint8_t (*scui_watch_notification_supported)(scui_watch_object *, uint32_t);
typedef void (*scui_watch_notification)(uint32_t, scui_watch_object *, void *);
typedef int32_t (*scui_watch_register)(scui_watch_object *, scui_watch_object *, uint32_t,
                                       scui_watch_notification, void *, uint32_t *);
typedef int32_t (*scui_watch_unregister)(scui_watch_object *, uint32_t);
typedef uint32_t (*scui_watch_release)(scui_watch_object *);

static const scui_watch_guid scui_watch_iid_factory = {
    0x78ee5945, 0xc36e, 0x4b13, {0xa6, 0x69, 0x00, 0x5d, 0xd1, 0x1c, 0x0f, 0x06}};
static const scui_watch_guid scui_watch_iid_list = {
    0x526c7776, 0x40e9, 0x459b, {0xb7, 0x11, 0xf3, 0x2a, 0xd7, 0x6d, 0xfc, 0x28}};
static const scui_watch_guid scui_watch_iid_adapter = {
    0xf0db4c7f, 0xfe5a, 0x42a2, {0xbd, 0x62, 0xf2, 0xa6, 0xcf, 0x6f, 0xc8, 0x3e}};
static const scui_watch_guid scui_watch_d3d12_graphics = {
    0x0c9ece4d, 0x2f6e, 0x4f01, {0x8c, 0x96, 0xe8, 0x9e, 0x33, 0x1b, 0x47, 0xb1}};

// Factory: CreateAdapterList 3, GetAdapterByLuid 4, IsNotificationTypeSupported 5,
// RegisterEventNotification 6, UnregisterEventNotification 7. List: GetAdapter 3,
// GetAdapterCount 4, IsStale 5.
// Adapter: GetProperty 6. DXCoreAdapterProperty: InstanceLuid 0, DriverDescription 2.
// DXCoreNotificationType: AdapterListStale 0.
enum {
    scui_watch_slot_release = 2,
    scui_watch_slot_create_list = 3,
    scui_watch_slot_supported = 5,
    scui_watch_slot_register = 6,
    scui_watch_slot_unregister = 7,
    scui_watch_slot_get = 3,
    scui_watch_slot_count = 4,
    scui_watch_slot_is_stale = 5,
    scui_watch_slot_property = 6,
    scui_watch_property_luid = 0,
    scui_watch_property_description = 2,
    scui_watch_list_stale = 0,
};

static scui_watch_object *scui_dxcore_factory;
static scui_watch_object *scui_dxcore_list;
static gboolean scui_dxcore_registered;
static uint32_t scui_dxcore_cookie;

static void scui_watch_release_object(scui_watch_object *object) {
    if (object != NULL) {
        ((scui_watch_release)object->vtbl[scui_watch_slot_release])(object);
    }
}

static scui_watch_object *scui_watch_factory(void) {
    static gboolean looked = FALSE;
    if (looked) {
        return scui_dxcore_factory;
    }
    looked = TRUE;
    void *library = dlopen("/usr/lib/wsl/lib/libdxcore.so", RTLD_NOW);
    if (library == NULL) {
        library = dlopen("libdxcore.so", RTLD_NOW);
    }
    if (library == NULL) {
        return NULL;
    }
    scui_watch_create_factory create =
        (scui_watch_create_factory)dlsym(library, "DXCoreCreateAdapterFactory");
    if (create == NULL || create(&scui_watch_iid_factory, (void **)&scui_dxcore_factory) < 0) {
        scui_dxcore_factory = NULL;
    }
    return scui_dxcore_factory;
}

static scui_watch_object *scui_watch_new_list(scui_watch_object *factory) {
    scui_watch_object *list = NULL;
    if (((scui_watch_create_list)factory->vtbl[scui_watch_slot_create_list])(
            factory, 1, &scui_watch_d3d12_graphics, &scui_watch_iid_list, (void **)&list) < 0) {
        return NULL;
    }
    return list;
}

int scui_adapter_identities(scui_adapter_identity *out, int capacity) {
    scui_watch_object *factory = scui_watch_factory();
    if (factory == NULL) {
        return 0;
    }
    scui_watch_object *list = scui_watch_new_list(factory);
    if (list == NULL) {
        return 0;
    }
    uint32_t total = ((scui_watch_list_count)list->vtbl[scui_watch_slot_count])(list);
    int written = 0;
    for (uint32_t index = 0; index < total && written < capacity; index++) {
        scui_watch_object *adapter = NULL;
        if (((scui_watch_list_get)list->vtbl[scui_watch_slot_get])(
                list, index, &scui_watch_iid_adapter, (void **)&adapter) < 0 ||
            adapter == NULL) {
            continue;
        }
        scui_watch_get_property get =
            (scui_watch_get_property)adapter->vtbl[scui_watch_slot_property];
        scui_adapter_identity *entry = &out[written];
        memset(entry, 0, sizeof *entry);
        // LUID: a 32-bit LowPart then a 32-bit HighPart. / LUID:先 32 位元的 LowPart,再 32 位元的 HighPart。
        uint32_t luid[2] = {0, 0};
        if (get(adapter, scui_watch_property_luid, sizeof luid, luid) >= 0) {
            entry->luid = ((uint64_t)luid[1] << 32) | luid[0];
            get(adapter, scui_watch_property_description, sizeof entry->name - 1, entry->name);
            written++;
        }
        scui_watch_release_object(adapter);
    }
    scui_watch_release_object(list);
    return written;
}

guint64 scui_dxgi_preferred_adapter_luid(int preference) {
    (void)preference;
    return 0;
}

// A list made now, kept so that its staleness can be asked or notified.
// 現在建立的清單，保留下來以便詢問或接收它是否 stale。
static gboolean scui_watch_refresh_list(void) {
    // The registration names the old list, so it goes before the list does;
    // otherwise each stale list would leave one behind.
    // 註冊指向舊清單，所以要在清單之前撤銷；否則每一份 stale 清單都會遺留一個註冊。
    if (scui_dxcore_registered) {
        ((scui_watch_unregister)scui_dxcore_factory->vtbl[scui_watch_slot_unregister])(
            scui_dxcore_factory, scui_dxcore_cookie);
        scui_dxcore_registered = FALSE;
    }
    scui_watch_release_object(scui_dxcore_list);
    scui_dxcore_list = scui_watch_new_list(scui_dxcore_factory);
    return scui_dxcore_list != NULL;
}

static gboolean scui_dxcore_register(void);

static gboolean scui_dxcore_stale_on_main(gpointer unused) {
    scui_watch_refresh_list();
    scui_dxcore_register();
    return scui_adapter_changed_on_main(unused);
}

// On a DXCore thread; the work goes to the GTK main loop.
// 在 DXCore 的執行緒上；工作交給 GTK 主迴圈。
static void scui_dxcore_notified(uint32_t type, scui_watch_object *object, void *context) {
    (void)type;
    (void)object;
    (void)context;
    g_idle_add(scui_dxcore_stale_on_main, NULL);
}

static gboolean scui_dxcore_register(void) {
    if (scui_dxcore_list == NULL) {
        return FALSE;
    }
    scui_dxcore_registered =
        ((scui_watch_register)scui_dxcore_factory->vtbl[scui_watch_slot_register])(
            scui_dxcore_factory, scui_dxcore_list, scui_watch_list_stale, scui_dxcore_notified,
            NULL, &scui_dxcore_cookie) >= 0;
    return scui_dxcore_registered;
}

static gboolean scui_dxcore_poll(gpointer unused) {
    (void)unused;
    if (scui_dxcore_list != NULL &&
        ((scui_watch_list_is_stale)scui_dxcore_list->vtbl[scui_watch_slot_is_stale])(
            scui_dxcore_list) != 0) {
        scui_watch_refresh_list();
        scui_adapter_changed_on_main(NULL);
    }
    return G_SOURCE_CONTINUE;
}

gboolean scui_uevent_is_adapter_removal(const char *message, int length) {
    // "remove@/devices/...\0ACTION=remove\0DEVPATH=...\0SUBSYSTEM=drm\0...": the
    // fields are NUL-separated; the four that matter are all 13 bytes long.
    // 各欄位以 NUL 分隔；需要的四個都是 13 個位元組。
    gboolean removed = FALSE;
    gboolean adapter = FALSE;
    for (int at = 0; at < length;) {
        const char *field = message + at;
        size_t size = strnlen(field, (size_t)(length - at));
        if (size == 13) {
            removed = removed || memcmp(field, "ACTION=remove", 13) == 0 ||
                      memcmp(field, "ACTION=unbind", 13) == 0;
            adapter = adapter || memcmp(field, "SUBSYSTEM=drm", 13) == 0 ||
                      memcmp(field, "SUBSYSTEM=pci", 13) == 0;
        }
        at += (int)size + 1;
    }
    return removed && adapter;
}

static gboolean scui_uevent_ready(gint descriptor, GIOCondition condition, gpointer unused) {
    (void)condition;
    (void)unused;
    char buffer[8192];
    gboolean relevant = FALSE;
    ssize_t length;
    while ((length = recv(descriptor, buffer, sizeof buffer, 0)) > 0) {
        relevant = relevant || scui_uevent_is_adapter_removal(buffer, (int)length);
    }
    if (relevant) {
        scui_adapter_changed_on_main(NULL);
    }
    return G_SOURCE_CONTINUE;
}

int scui_adapter_watch_start(void (*changed)(void)) {
    static int mode = -1;
    scui_adapter_changed = changed;
    if (mode >= 0) {
        return mode;
    }
    mode = 0;
    if (scui_watch_factory() != NULL) {
        if (!scui_watch_refresh_list()) {
            return mode;
        }
        scui_watch_notification_supported supported =
            (scui_watch_notification_supported)scui_dxcore_factory->vtbl[scui_watch_slot_supported];
        if (supported(scui_dxcore_factory, scui_watch_list_stale) != 0 && scui_dxcore_register()) {
            mode = 2;
        } else {
            g_timeout_add_seconds(2, scui_dxcore_poll, NULL);
            mode = 1;
        }
        return mode;
    }
    int descriptor =
        socket(AF_NETLINK, SOCK_DGRAM | SOCK_CLOEXEC | SOCK_NONBLOCK, NETLINK_KOBJECT_UEVENT);
    if (descriptor < 0) {
        return mode;
    }
    struct sockaddr_nl address;
    memset(&address, 0, sizeof address);
    address.nl_family = AF_NETLINK;
    // Group 1 carries the kernel's own uevents (group 2 is udev's re-broadcast).
    // 群組 1 是核心自己的 uevent(群組 2 是 udev 的轉播)。
    address.nl_groups = 1;
    if (bind(descriptor, (struct sockaddr *)&address, sizeof address) < 0) {
        close(descriptor);
        return mode;
    }
    g_unix_fd_add(descriptor, G_IO_IN, scui_uevent_ready, NULL);
    mode = 3;
    return mode;
}

#else

int scui_adapter_identities(scui_adapter_identity *out, int capacity) {
    (void)out;
    (void)capacity;
    return 0;
}

guint64 scui_dxgi_preferred_adapter_luid(int preference) {
    (void)preference;
    return 0;
}

gboolean scui_uevent_is_adapter_removal(const char *message, int length) {
    (void)message;
    (void)length;
    return FALSE;
}

int scui_adapter_watch_start(void (*changed)(void)) {
    scui_adapter_changed = changed;
    (void)scui_adapter_changed_on_main;
    return 0;
}

#endif
