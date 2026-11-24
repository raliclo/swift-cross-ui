// Everything here is Windows-only, and SwiftPM has no way to make a target
// itself conditional -- only a dependency on one. So this target is in the
// build graph on every platform, and unguarded it stopped `swift test` on Linux
// at `'Windows.h' file not found`.
//
// Necessary but not sufficient: with this guard the build gets further and then
// stops inside the swift-winui package at `'wtypesbase.h' file not found`,
// because `swift test` compiles every target including WinUIBackend. Adding
// platform conditions to WinUIBackend's product dependencies was tried and does
// not help for the same reason. Tests therefore run on Windows; this guard is
// the first of the two changes Linux would need, not a fix on its own.
#ifdef _WIN32

#include <Windows.h>
#include <ShObjIdl.h>
#include <d3d11.h>
// ID3D11VideoContext1::VideoProcessorSet{Stream,Output}ColorSpace1, which take a
// DXGI_COLOR_SPACE_TYPE enum. The equivalent in d3d11.h takes a struct of
// bitfields, which Swift cannot populate.
#include <d3d11_1.h>
#include <dxgi1_2.h>
// IDXGISwapChain2::SetMatrixTransform, used to scale a frame-sized composition
// swap chain up to the panel it is presented in.
#include <dxgi1_3.h>

// ISwapChainPanelNative is declared by WinAppSDK's
// microsoft.ui.xaml.media.dxinterop.h (part of the swift-winui package's
// CWinAppSDK nuget headers), which isn't exposed through any Swift module
// today. Rather than reach into that package's private include path, vendor
// the one interface we need directly, matching how the rest of this header
// leans on the standard Windows SDK COM interface shape (see
// IInitializeWithWindow from ShObjIdl.h, used by WinUIBackend's
// SwiftIInitializeWithWindow).
//
// IID: 63aad0b8-7c24-40ff-85a8-640d944cc325
#ifndef __ISwapChainPanelNative_FWD_DEFINED__
#define __ISwapChainPanelNative_FWD_DEFINED__
typedef interface ISwapChainPanelNative ISwapChainPanelNative;
#endif

#ifndef __ISwapChainPanelNative_INTERFACE_DEFINED__
#define __ISwapChainPanelNative_INTERFACE_DEFINED__

typedef struct ISwapChainPanelNativeVtbl {
    BEGIN_INTERFACE

    HRESULT(STDMETHODCALLTYPE *QueryInterface)
    (ISwapChainPanelNative *This, REFIID riid, void **ppvObject);

    ULONG(STDMETHODCALLTYPE *AddRef)(ISwapChainPanelNative *This);

    ULONG(STDMETHODCALLTYPE *Release)(ISwapChainPanelNative *This);

    HRESULT(STDMETHODCALLTYPE *SetSwapChain)
    (ISwapChainPanelNative *This, IDXGISwapChain *swapChain);

    END_INTERFACE
} ISwapChainPanelNativeVtbl;

interface ISwapChainPanelNative {
    CONST_VTBL struct ISwapChainPanelNativeVtbl *lpVtbl;
};

#endif

// libdispatch's main-queue handle, exported by dispatch.dll and declared only in
// its private headers. On Windows the handle is an event that libdispatch sets
// whenever the main queue has work, an asyncAfter that has come due included;
// Foundation's own RunLoop waits on it. WinUIBackend's run-loop tickler waits
// on it too, because the WinUI message loop does not (P66, 2026-10-19).
// libdispatch 的主佇列 handle，由 dispatch.dll 匯出，只宣告在其私有標頭中。在 Windows 上它是一個
// 事件，主佇列有工作時(包括到期的 asyncAfter)libdispatch 會設定它;Foundation 自己的 RunLoop 就是等它。
// WinUIBackend 的 run-loop tickler 也等它，因為 WinUI 的訊息迴圈不會(P66,2026-10-19)。
void *_dispatch_get_main_queue_handle_4CF(void);
// Drains the main queue. A wait on the handle above consumes its signal (it is
// auto-reset), so whoever waits must drain: with only a wait, the RunLoop never
// saw the signal again and P66's asyncAfter chain stopped after one call.
// 抽取主佇列。等待上面的 handle 會消耗掉它的訊號(auto-reset),所以等待者必須自己抽取：只等待不抽取時,
// RunLoop 再也看不到訊號,P66 的 asyncAfter 鏈在第一次呼叫後就停了。
void _dispatch_main_queue_callback_4CF(void *msg);

// One SVG <text> run as coverage, width*height bytes into `out`, top row first;
// 1 on success. `families` is comma-separated, the first the system has is used.
// anchor: 0 start, 1 middle, 2 end. strokeWidth <= 0 fills. See svg_text_mask.cpp.
// 一段 SVG <text> 的覆蓋率，寫入 `out` 共 width*height 個位元組、最上面一列在前；成功時回傳 1。
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
int scui_svg_text_mask(const uint16_t *text, int textLength, const uint16_t *families,
                       double fontSize, int bold, int italic, int anchor, double a, double b,
                       double c, double d, double tx, double ty, double strokeWidth, int width,
                       int height, uint8_t *out);

// A Microsoft.UI.Composition graphics device for `compositor` (its IUnknown), made
// from a Direct2D device and cached; AddRef'd, NULL on failure. See composition_surface.cpp.
// 以 Direct2D device 為 `compositor`(其 IUnknown)建立並快取的 composition graphics device;已 AddRef,失敗時為 NULL。
void *scui_composition_graphics_device(void *compositor);
// Draws width*height premultiplied BGRA pixels into a CompositionDrawingSurface
// (its IUnknown); 1 on success. / 把 width*height 個預乘 BGRA 像素畫進 CompositionDrawingSurface;成功時為 1。
int scui_drawing_surface_fill(void *surface, int width, int height, const uint8_t *bgra);

// One hardware adapter DXGI lists, by the LUID it keeps while present
// (adapter_watch.cpp). / DXGI 所列的一張硬體介面卡，以它存在期間保持不變的 LUID 表示(adapter_watch.cpp)。
typedef struct {
    uint64_t luid;
    char name[128];
} scui_dxgi_adapter_identity;
// The hardware adapters DXGI lists, in DXGI's order (software ones left out); how many.
// DXGI 所列的硬體介面卡，依 DXGI 的順序(不含軟體介面卡);回傳個數。
int scui_dxgi_hardware_adapters(scui_dxgi_adapter_identity *out, int capacity);
// Calls `changed` on a thread-pool thread whenever DXGI's adapter enumeration
// changes (IDXGIFactory7::RegisterAdaptersChangedEvent); 1 when registered, 0
// when it could not be. Later calls replace `changed` only.
// 每當 DXGI 的介面卡列舉改變(IDXGIFactory7::RegisterAdaptersChangedEvent),在 thread pool 執行緒上呼叫 `changed`;
// 註冊成功回傳 1,無法註冊回傳 0。之後的呼叫只替換 `changed`。
int scui_dxgi_watch_adapters(void (*changed)(void));

// Hide Others: every other process's visible, unowned, non-tool, uncloaked
// top-level window with a minimise box, except the desktop and the taskbar, is
// minimised without activation -- the effect of Win+Home -- and remembered; how
// many. Show All restores the remembered ones still minimised; how many
// (hide_others.cpp).
// Hide Others:其他行程中可見、沒有擁有者、不是工具視窗、沒有被 cloak、有最小化鈕的頂層視窗(桌面與工作列除外)一律
// 不啟用地最小化——即 Win+Home 的效果——並記下來；回傳數量。Show All 還原記下且仍最小化的視窗；回傳數量(hide_others.cpp)。
int scui_win32_hide_other_applications(void);
int scui_win32_show_hidden_applications(void);

// Direct2D built-in effects as Windows.Graphics.Effects.IGraphicsEffect nodes, for a
// CompositionEffectFactory, without Win2D (graphics_effect.cpp). scui_effect_create
// returns an IGraphicsEffect* holding one reference, or NULL; properties are
// IPropertyValue objects (passed as IInspectable*) at the indices below, which
// graphics_effect.cpp checks against d2d1effects.h; sources are IGraphicsEffectSource
// objects. Both setters take their own reference and return 1 on success.
// 把 Direct2D 內建效果做成 Windows.Graphics.Effects.IGraphicsEffect 節點，供 CompositionEffectFactory 使用，
// 不經過 Win2D(graphics_effect.cpp)。scui_effect_create 回傳持有一個參考的 IGraphicsEffect*,或 NULL;屬性是
// 位於下列索引的 IPropertyValue 物件(以 IInspectable* 傳入),graphics_effect.cpp 會與 d2d1effects.h 比對這些索引；
// 來源是 IGraphicsEffectSource 物件。兩個 setter 都自行持有參考，成功時回傳 1。
enum {
    SCUI_EFFECT_COLOR_MATRIX = 0,
    SCUI_EFFECT_GAUSSIAN_BLUR = 1,
    SCUI_EFFECT_ARITHMETIC_COMPOSITE = 2,
    SCUI_EFFECT_LINEAR_TRANSFER = 3,
    SCUI_EFFECT_GAMMA_TRANSFER = 4,
    SCUI_EFFECT_HUE_ROTATION = 5,
};
enum {
    SCUI_COLORMATRIX_MATRIX = 0,      // 20 floats, row-major 5x4 / 20 個 float,逐列的 5x4
    SCUI_COLORMATRIX_ALPHA_MODE = 1,  // UInt32
    SCUI_COLORMATRIX_CLAMP = 2,       // Boolean
    SCUI_COLORMATRIX_ALPHA_PREMULTIPLIED = 1,
    SCUI_BLUR_DEVIATION = 0,          // Single
    SCUI_BLUR_OPTIMIZATION = 1,       // UInt32
    SCUI_BLUR_BORDER_MODE = 2,        // UInt32
    SCUI_BLUR_OPTIMIZATION_BALANCED = 1,
    SCUI_BLUR_BORDER_SOFT = 0,
    SCUI_ARITHMETIC_COEFFICIENTS = 0, // 4 floats: multiply, source 1, source 2, offset
    SCUI_ARITHMETIC_CLAMP = 1,        // Boolean
    // Each channel: intercept, slope, disable; red, green, blue, alpha, then clamp.
    // 每個通道：截距、斜率、停用；依序紅、綠、藍、alpha,最後是 clamp。
    SCUI_LINEAR_RED_INTERCEPT = 0,
    SCUI_LINEAR_RED_SLOPE = 1,
    SCUI_LINEAR_RED_DISABLE = 2,
    SCUI_LINEAR_GREEN_INTERCEPT = 3,
    SCUI_LINEAR_BLUE_INTERCEPT = 6,
    SCUI_LINEAR_ALPHA_INTERCEPT = 9,
    SCUI_LINEAR_ALPHA_DISABLE = 11,
    SCUI_LINEAR_CLAMP = 12,
    // Each channel: amplitude, exponent, offset, disable; red, green, blue, alpha, clamp.
    // 每個通道：振幅、指數、偏移、停用；依序紅、綠、藍、alpha,最後是 clamp。
    SCUI_GAMMA_RED_AMPLITUDE = 0,
    SCUI_GAMMA_RED_EXPONENT = 1,
    SCUI_GAMMA_RED_OFFSET = 2,
    SCUI_GAMMA_RED_DISABLE = 3,
    SCUI_GAMMA_GREEN_AMPLITUDE = 4,
    SCUI_GAMMA_BLUE_AMPLITUDE = 8,
    SCUI_GAMMA_ALPHA_AMPLITUDE = 12,
    SCUI_GAMMA_ALPHA_DISABLE = 15,
    SCUI_GAMMA_CLAMP = 16,
    SCUI_HUE_ANGLE = 0,               // Single, in degrees / Single,單位為度
};
void *scui_effect_create(int kind);
int scui_effect_set_property(void *effect, unsigned index, void *propertyValue);
int scui_effect_set_source(void *effect, unsigned index, void *source);
#ifdef __cplusplus
}
#endif

#endif  // _WIN32
