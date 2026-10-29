// What WinUIBackend listens to for the graphics adapter in use going away, and
// the adapter identities it compares before and after.
//
// IDXGIFactory7::RegisterAdaptersChangedEvent signals an event whenever DXGI's
// adapter enumeration changes -- an adapter added or removed, a driver
// installed, upgraded or reset to the basic display driver. The signal does not
// say which adapter; WinUIBackend lists the adapters again by LUID and fires
// adapterRemoved only when the one it renders on is gone
// (GraphicsAdapterRemovalWatch). GtkBackend does the same on Windows in
// gtk_adapter_watch.c.
//
// WinUIBackend 為「使用中的繪圖介面卡消失」所監聽的訊號，以及它前後比對的介面卡識別。
//
// IDXGIFactory7::RegisterAdaptersChangedEvent 會在 DXGI 的介面卡列舉改變時觸發一個事件——新增或移除介面卡、安裝或
// 升級驅動、或退回基本顯示驅動。訊號不會說是哪一張;WinUIBackend 以 LUID 重新列出介面卡，只有它繪製所用的那一張不見了
// 才觸發 adapterRemoved(GraphicsAdapterRemovalWatch)。GtkBackend 在 Windows 上於 gtk_adapter_watch.c 做相同的事。

#ifdef _WIN32

#include "WinUIInterop.h"
#include <cstring>
#include <dxgi1_6.h>

namespace {

void (*adaptersChanged)(void) = nullptr;
HANDLE adaptersEvent = nullptr;
IDXGIFactory7 *watchedFactory = nullptr;
DWORD watchedCookie = 0;

uint64_t luidValue(LUID luid) {
    return (static_cast<uint64_t>(static_cast<uint32_t>(luid.HighPart)) << 32) | luid.LowPart;
}

// Registers the event with a fresh factory. Done again after every signal: a
// factory describes the adapters as they were when it was made, so the next
// change is watched through one that knows the current set.
// 以新的 factory 註冊事件。每次訊號後都重做一次:factory 描述的是它建立當時的介面卡，因此下一次變更要透過知道目前
// 集合的 factory 來監看。
bool registerAdaptersEvent() {
    if (watchedFactory) {
        watchedFactory->UnregisterAdaptersChangedEvent(watchedCookie);
        watchedFactory->Release();
        watchedFactory = nullptr;
    }
    IDXGIFactory7 *factory = nullptr;
    if (FAILED(CreateDXGIFactory1(__uuidof(IDXGIFactory7), reinterpret_cast<void **>(&factory)))) {
        return false;
    }
    if (FAILED(factory->RegisterAdaptersChangedEvent(adaptersEvent, &watchedCookie))) {
        factory->Release();
        return false;
    }
    watchedFactory = factory;
    return true;
}

// On a thread-pool thread: the factory is renewed here and the callback, which
// moves the work to the main thread, is called.
// 在 thread pool 的執行緒上：在此更新 factory,並呼叫會把工作移到主執行緒的回呼。
VOID CALLBACK adaptersSignalled(PVOID, BOOLEAN) {
    registerAdaptersEvent();
    if (adaptersChanged) adaptersChanged();
}

}  // namespace

extern "C" int scui_dxgi_hardware_adapters(scui_dxgi_adapter_identity *out, int capacity) {
    IDXGIFactory1 *factory = nullptr;
    if (FAILED(CreateDXGIFactory1(__uuidof(IDXGIFactory1), reinterpret_cast<void **>(&factory)))) {
        return 0;
    }
    int written = 0;
    for (UINT index = 0; written < capacity; index++) {
        IDXGIAdapter1 *adapter = nullptr;
        if (FAILED(factory->EnumAdapters1(index, &adapter)) || !adapter) break;
        DXGI_ADAPTER_DESC1 description = {};
        // Software adapters (WARP, the Basic Render Driver) draw on the CPU and
        // are never the GPU that can go away.
        // 軟體介面卡(WARP、Basic Render Driver)在 CPU 上繪製，不會是那張會消失的 GPU。
        if (SUCCEEDED(adapter->GetDesc1(&description)) &&
            (description.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) == 0) {
            scui_dxgi_adapter_identity *entry = &out[written++];
            std::memset(entry, 0, sizeof *entry);
            entry->luid = luidValue(description.AdapterLuid);
            WideCharToMultiByte(CP_UTF8, 0, description.Description, -1, entry->name,
                                static_cast<int>(sizeof entry->name) - 1, nullptr, nullptr);
        }
        adapter->Release();
    }
    factory->Release();
    return written;
}

extern "C" int scui_dxgi_watch_adapters(void (*changed)(void)) {
    static int registered = -1;
    adaptersChanged = changed;
    if (registered >= 0) return registered;
    registered = 0;
    adaptersEvent = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    HANDLE wait = nullptr;
    if (!adaptersEvent || !registerAdaptersEvent() ||
        !RegisterWaitForSingleObject(&wait, adaptersEvent, adaptersSignalled, nullptr, INFINITE,
                                     WT_EXECUTEINWAITTHREAD)) {
        return registered;
    }
    registered = 1;
    return registered;
}

#endif  // _WIN32
