// The GPUs of a WSL distribution, through DXCore.
//
// WSL has no /sys/class/drm: its GPUs reach Linux through /dev/dxg and
// /usr/lib/wsl/lib/libdxcore.so, and Mesa's d3d12 driver draws through them.
// GtkBackend listed only DRM cards, so P68 read "adapters: 0" under WSL on a
// machine with two (2026-10-19). This lists what DXCore lists, as Mesa sees
// it: the adapters that support D3D12 graphics, with their names and whether
// each is integrated.
//
// libdxcore.so is opened at run time, not linked: a Linux machine outside
// WSL has none, and there this returns 0. Its interfaces are COM with the
// plain three-slot IUnknown, measured with a standalone probe on 2026-10-19
// before relying on it: the factory, the list and both adapters answered,
// "NVIDIA GeForce RTX 4060 Laptop GPU" and "AMD Radeon(TM) Graphics".
//
// WSL 發行版的 GPU,經由 DXCore 取得。
//
// WSL 沒有 /sys/class/drm:它的 GPU 是經 /dev/dxg 與 /usr/lib/wsl/lib/libdxcore.so 進入 Linux,Mesa 的
// d3d12 驅動也透過它們繪製。GtkBackend 原本只列 DRM 卡，因此在有兩張卡的機器上,P68 於 WSL 讀到
// "adapters: 0"(2026-10-19)。本檔列出 DXCore 所列、也就是 Mesa 看到的：支援 D3D12 繪圖的介面卡，以及
// 各自的名稱與是否為內顯。
//
// libdxcore.so 在執行時開啟而非連結:WSL 以外的 Linux 沒有它，此時回傳 0。它的介面是 COM，採一般的三格
// IUnknown——2026-10-19 先以獨立探針量過才採用:factory、list 與兩張卡都有回應。

#include "include/gtk_helpers.h"

#if defined(__linux__)

#include <dlfcn.h>
#include <stdint.h>
#include <string.h>

typedef struct {
    uint32_t a;
    uint16_t b, c;
    uint8_t d[8];
} scui_guid;

typedef struct {
    void **vtbl;
} scui_com_object;

typedef int32_t (*scui_create_factory)(const scui_guid *, void **);
typedef int32_t (*scui_create_list)(scui_com_object *, uint32_t, const scui_guid *,
                                    const scui_guid *, void **);
typedef uint32_t (*scui_list_count)(scui_com_object *);
typedef int32_t (*scui_list_get)(scui_com_object *, uint32_t, const scui_guid *, void **);
typedef int32_t (*scui_get_property)(scui_com_object *, uint32_t, size_t, void *);
typedef uint32_t (*scui_release)(scui_com_object *);

static const scui_guid scui_iid_factory = {
    0x78ee5945, 0xc36e, 0x4b13, {0xa6, 0x69, 0x00, 0x5d, 0xd1, 0x1c, 0x0f, 0x06}};
static const scui_guid scui_iid_list = {
    0x526c7776, 0x40e9, 0x459b, {0xb7, 0x11, 0xf3, 0x2a, 0xd7, 0x6d, 0xfc, 0x28}};
static const scui_guid scui_iid_adapter = {
    0xf0db4c7f, 0xfe5a, 0x42a2, {0xbd, 0x62, 0xf2, 0xa6, 0xcf, 0x6f, 0xc8, 0x3e}};
static const scui_guid scui_attribute_d3d12_graphics = {
    0x0c9ece4d, 0x2f6e, 0x4f01, {0x8c, 0x96, 0xe8, 0x9e, 0x33, 0x1b, 0x47, 0xb1}};

// IUnknown: QueryInterface 0, AddRef 1, Release 2; each interface's own
// methods start at 3, in dxcore_interface.h's order.
// IUnknown:QueryInterface 0、AddRef 1、Release 2;各介面自己的方法從 3 開始，順序同 dxcore_interface.h。
enum { scui_slot_release = 2, scui_slot_first = 3 };
// DXCoreAdapterProperty: DriverDescription 2, IsIntegrated 12.
enum { scui_property_description = 2, scui_property_integrated = 12 };

static void scui_release_object(scui_com_object *object) {
    if (object != NULL) {
        ((scui_release)object->vtbl[scui_slot_release])(object);
    }
}

int scui_dxcore_adapters(scui_dxcore_adapter *out, int capacity) {
    void *library = dlopen("/usr/lib/wsl/lib/libdxcore.so", RTLD_NOW);
    if (library == NULL) {
        library = dlopen("libdxcore.so", RTLD_NOW);
    }
    if (library == NULL) {
        return 0;
    }
    scui_create_factory create = (scui_create_factory)dlsym(library, "DXCoreCreateAdapterFactory");
    scui_com_object *factory = NULL;
    if (create == NULL || create(&scui_iid_factory, (void **)&factory) < 0 || factory == NULL) {
        return 0;
    }
    scui_com_object *list = NULL;
    if (((scui_create_list)factory->vtbl[scui_slot_first])(
            factory, 1, &scui_attribute_d3d12_graphics, &scui_iid_list, (void **)&list) < 0 ||
        list == NULL) {
        scui_release_object(factory);
        return 0;
    }
    uint32_t total = ((scui_list_count)list->vtbl[scui_slot_first + 1])(list);
    int written = 0;
    for (uint32_t index = 0; index < total && written < capacity; index++) {
        scui_com_object *adapter = NULL;
        if (((scui_list_get)list->vtbl[scui_slot_first])(list, index, &scui_iid_adapter,
                                                         (void **)&adapter) < 0 ||
            adapter == NULL) {
            continue;
        }
        // IsValid, IsAttributeSupported, IsPropertySupported, GetProperty:
        // GetProperty is the fourth of the adapter's own methods.
        // IsValid、IsAttributeSupported、IsPropertySupported、GetProperty:GetProperty 是第四個。
        scui_get_property get = (scui_get_property)adapter->vtbl[scui_slot_first + 3];
        scui_dxcore_adapter *entry = &out[written];
        memset(entry, 0, sizeof *entry);
        uint8_t integrated = 0;
        if (get(adapter, scui_property_description, sizeof entry->name - 1, entry->name) >= 0 &&
            entry->name[0] != '\0') {
            get(adapter, scui_property_integrated, sizeof integrated, &integrated);
            entry->integrated = integrated != 0;
            written++;
        }
        scui_release_object(adapter);
    }
    scui_release_object(list);
    scui_release_object(factory);
    return written;
}

#else

int scui_dxcore_adapters(scui_dxcore_adapter *out, int capacity) {
    (void)out;
    (void)capacity;
    return 0;
}

#endif
