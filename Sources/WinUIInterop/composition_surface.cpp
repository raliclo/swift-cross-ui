// Pixels into a Microsoft.UI.Composition drawing surface, for brushes XAML
// does not have.
//
// XAML has no conic brush and swift-winui projects neither ImageBrush nor
// LoadedImageSurface, so an AngularGradient shape style (a Path's fill or
// stroke, a TextBlock's foreground) is painted by a XamlCompositionBrushBase
// whose CompositionSurfaceBrush shows a CompositionDrawingSurface. The two
// steps that have no WinRT projection are here: making the composition
// graphics device from a Direct2D device (ICompositorInterop), and drawing
// the pixels into the surface (ICompositionDrawingSurfaceInterop). Both
// interfaces are declared by hand from Microsoft.UI.Composition.Interop.h,
// which needs C++/WinRT.
//
// 把像素寫進 Microsoft.UI.Composition 的 drawing surface,供 XAML 沒有的 brush 使用。
//
// XAML 沒有錐形 brush,swift-winui 也沒有投影 ImageBrush 或 LoadedImageSurface,因此 AngularGradient 形狀樣式
// (Path 的填色或描邊、TextBlock 的前景)由一個 XamlCompositionBrushBase 繪製，其 CompositionSurfaceBrush 顯示一個
// CompositionDrawingSurface。沒有 WinRT 投影的兩步在這裡：以 Direct2D device 建立 composition graphics device
// (ICompositorInterop),以及把像素畫進 surface(ICompositionDrawingSurfaceInterop)。兩個介面依
// Microsoft.UI.Composition.Interop.h 手寫宣告，因為那個標頭需要 C++/WinRT。

#ifdef _WIN32

#include "WinUIInterop.h"
#include <d2d1_1.h>
#include <d3d11.h>
#include <dxgi.h>

namespace {

// IID_ICompositorInterop and IID_ICompositionDrawingSurfaceInterop, from
// Microsoft.UI.Composition.Interop.h (WinAppSDK).
// 取自 Microsoft.UI.Composition.Interop.h(WinAppSDK)。
const IID kCompositorInterop = {
    0xFAB19398, 0x6D19, 0x4D8A, {0xB7, 0x52, 0x8F, 0x09, 0x6C, 0x39, 0x60, 0x69}};
const IID kDrawingSurfaceInterop = {
    0x2D6355C2, 0xAD57, 0x4EAE, {0x92, 0xE4, 0x4C, 0x3E, 0xFF, 0x65, 0xD5, 0x78}};

struct CompositorInterop : public IUnknown {
    virtual HRESULT STDMETHODCALLTYPE CreateGraphicsDevice(IUnknown *renderingDevice,
                                                           void **result) = 0;
};

struct DrawingSurfaceInterop : public IUnknown {
    virtual HRESULT STDMETHODCALLTYPE BeginDraw(const RECT *updateRect, REFIID iid,
                                                void **updateObject, POINT *updateOffset) = 0;
    virtual HRESULT STDMETHODCALLTYPE EndDraw() = 0;
    virtual HRESULT STDMETHODCALLTYPE Resize(SIZE sizePixels) = 0;
    virtual HRESULT STDMETHODCALLTYPE Scroll(const RECT *scrollRect, const RECT *clipRect,
                                             int offsetX, int offsetY) = 0;
    virtual HRESULT STDMETHODCALLTYPE ResumeDraw() = 0;
    virtual HRESULT STDMETHODCALLTYPE SuspendDraw() = 0;
};

template <class T> void release(T *&p) {
    if (p) {
        p->Release();
        p = nullptr;
    }
}

// One graphics device for the UI thread's compositor, made on first use.
// UI 執行緒的 compositor 只有一個 graphics device,第一次使用時建立。
void *cachedCompositor = nullptr;
IUnknown *cachedDevice = nullptr;

}  // namespace

extern "C" void *scui_composition_graphics_device(void *compositor) {
    if (!compositor) return nullptr;
    if (cachedDevice && cachedCompositor == compositor) {
        cachedDevice->AddRef();
        return cachedDevice;
    }

    ID3D11Device *d3d = nullptr;
    D3D_FEATURE_LEVEL level;
    HRESULT hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
                                   D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0,
                                   D3D11_SDK_VERSION, &d3d, &level, nullptr);
    if (FAILED(hr)) {
        hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_WARP, nullptr,
                               D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0, D3D11_SDK_VERSION,
                               &d3d, &level, nullptr);
    }
    if (FAILED(hr)) return nullptr;
    IDXGIDevice *dxgi = nullptr;
    hr = d3d->QueryInterface(__uuidof(IDXGIDevice), reinterpret_cast<void **>(&dxgi));
    release(d3d);
    if (FAILED(hr)) return nullptr;

    ID2D1Factory1 *factory = nullptr;
    hr = D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, __uuidof(ID2D1Factory1), nullptr,
                           reinterpret_cast<void **>(&factory));
    if (FAILED(hr)) {
        release(dxgi);
        return nullptr;
    }
    ID2D1Device *d2d = nullptr;
    hr = factory->CreateDevice(dxgi, &d2d);
    release(factory);
    release(dxgi);
    if (FAILED(hr)) return nullptr;

    CompositorInterop *interop = nullptr;
    hr = static_cast<IUnknown *>(compositor)->QueryInterface(
        kCompositorInterop, reinterpret_cast<void **>(&interop));
    if (FAILED(hr)) {
        release(d2d);
        return nullptr;
    }
    void *device = nullptr;
    hr = interop->CreateGraphicsDevice(d2d, &device);
    release(interop);
    release(d2d);
    if (FAILED(hr) || !device) return nullptr;

    if (cachedDevice) cachedDevice->Release();
    cachedDevice = static_cast<IUnknown *>(device);
    cachedCompositor = compositor;
    cachedDevice->AddRef();
    return device;
}

extern "C" int scui_drawing_surface_fill(void *surface, int width, int height,
                                         const uint8_t *bgra) {
    if (!surface || width <= 0 || height <= 0 || !bgra) return 0;
    DrawingSurfaceInterop *interop = nullptr;
    if (FAILED(static_cast<IUnknown *>(surface)->QueryInterface(
            kDrawingSurfaceInterop, reinterpret_cast<void **>(&interop))))
        return 0;
    ID2D1DeviceContext *context = nullptr;
    POINT offset{};
    HRESULT hr = interop->BeginDraw(nullptr, __uuidof(ID2D1DeviceContext),
                                    reinterpret_cast<void **>(&context), &offset);
    if (FAILED(hr) || !context) {
        release(interop);
        return 0;
    }
    // Pixels, not DIPs: the surface was made in pixels and the bitmap is drawn
    // one to one. / 像素而非 DIP:surface 以像素建立，位圖一對一繪製。
    context->SetDpi(96, 96);
    context->Clear(D2D1::ColorF(0, 0, 0, 0));
    ID2D1Bitmap *bitmap = nullptr;
    D2D1_BITMAP_PROPERTIES properties = D2D1::BitmapProperties(
        D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED), 96, 96);
    hr = context->CreateBitmap(D2D1::SizeU(static_cast<UINT32>(width), static_cast<UINT32>(height)),
                               bgra, static_cast<UINT32>(width) * 4, properties, &bitmap);
    if (SUCCEEDED(hr)) {
        context->DrawBitmap(bitmap,
                            D2D1::RectF(static_cast<FLOAT>(offset.x), static_cast<FLOAT>(offset.y),
                                        static_cast<FLOAT>(offset.x + width),
                                        static_cast<FLOAT>(offset.y + height)));
        release(bitmap);
    }
    release(context);
    HRESULT ended = interop->EndDraw();
    release(interop);
    return SUCCEEDED(hr) && SUCCEEDED(ended) ? 1 : 0;
}

#endif  // _WIN32
