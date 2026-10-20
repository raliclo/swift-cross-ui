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
#ifdef __cplusplus
}
#endif

#endif  // _WIN32
