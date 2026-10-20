// SVG <text> coverage for WinUIBackend, through DirectWrite and Direct2D.
//
// What BackendFeatures.SVGText asks for: one run as coverage, its baseline on
// the x axis and its anchor at the origin, mapped to device pixels by an affine
// transform, filled or stroked. The run is laid out with IDWriteTextLayout, which
// brings DirectWrite's system font fallback for characters the chosen family
// lacks; its glyph runs are turned into outline geometry (OutlineCollector), and
// that geometry is filled or stroked by a Direct2D render target over a WIC
// bitmap, whose alpha is the coverage. Fill and stroke go through the same
// outline so the two agree to the pixel.
//
// SVG <text> 的覆蓋率，供 WinUIBackend 使用，經由 DirectWrite 與 Direct2D。
//
// BackendFeatures.SVGText 要的是：一段文字的覆蓋率，基線在 x 軸上、錨點在原點，以仿射轉換映射到裝置像素，
// 填滿或描邊。文字以 IDWriteTextLayout 排版，它帶來 DirectWrite 的系統字型替代，處理所選字型缺少的字元；
// 它的 glyph run 被轉成外框 geometry(OutlineCollector),再由畫在 WIC 位圖上的 Direct2D render target 填滿
// 或描邊，位圖的 alpha 就是覆蓋率。填滿與描邊走同一份外框，讓兩者逐像素一致。

#ifdef _WIN32

#include "WinUIInterop.h"
#include <d2d1.h>
#include <dwrite.h>
#include <wincodec.h>

#include <string>
#include <vector>

namespace {

template <class T> struct ComRef {
    T *p = nullptr;
    ComRef() = default;
    ComRef(const ComRef &) = delete;
    ComRef &operator=(const ComRef &) = delete;
    ~ComRef() {
        if (p) p->Release();
    }
    T **put() { return &p; }
    T *operator->() const { return p; }
    T *get() const { return p; }
};

// The text layout's glyph runs, as outline geometry in text space. Each run's
// outline is made at the glyph origin and moved to the run's baseline origin,
// because GetGlyphRunOutline takes no offset of its own.
// 文字版面的 glyph run,以文字空間中的外框 geometry 表示。每段的外框在字形原點產生、再移到該段的基線原點，
// 因為 GetGlyphRunOutline 自己不接受位移。
class OutlineCollector final : public IDWriteTextRenderer {
  public:
    explicit OutlineCollector(ID2D1Factory *factory) : factory_(factory) {}
    ~OutlineCollector() {
        for (auto *geometry : geometries) geometry->Release();
    }
    std::vector<ID2D1Geometry *> geometries;

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **out) override {
        if (riid == __uuidof(IUnknown) || riid == __uuidof(IDWritePixelSnapping) ||
            riid == __uuidof(IDWriteTextRenderer)) {
            *out = static_cast<IDWriteTextRenderer *>(this);
            AddRef();
            return S_OK;
        }
        *out = nullptr;
        return E_NOINTERFACE;
    }
    // Lives on the stack of the call that uses it; the count is only kept honest.
    // 活在使用它的那次呼叫的堆疊上；計數只是保持誠實。
    ULONG STDMETHODCALLTYPE AddRef() override { return ++references_; }
    ULONG STDMETHODCALLTYPE Release() override { return --references_; }

    HRESULT STDMETHODCALLTYPE IsPixelSnappingDisabled(void *, BOOL *disabled) override {
        *disabled = TRUE;
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetCurrentTransform(void *, DWRITE_MATRIX *matrix) override {
        *matrix = DWRITE_MATRIX{1, 0, 0, 1, 0, 0};
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetPixelsPerDip(void *, FLOAT *pixels) override {
        *pixels = 1;
        return S_OK;
    }

    HRESULT STDMETHODCALLTYPE DrawGlyphRun(void *, FLOAT x, FLOAT y, DWRITE_MEASURING_MODE,
                                           const DWRITE_GLYPH_RUN *run,
                                           const DWRITE_GLYPH_RUN_DESCRIPTION *,
                                           IUnknown *) override {
        ComRef<ID2D1PathGeometry> path;
        HRESULT hr = factory_->CreatePathGeometry(path.put());
        if (FAILED(hr)) return hr;
        ComRef<ID2D1GeometrySink> sink;
        hr = path->Open(sink.put());
        if (FAILED(hr)) return hr;
        sink->SetFillMode(D2D1_FILL_MODE_WINDING);
        hr = run->fontFace->GetGlyphRunOutline(run->fontEmSize, run->glyphIndices, run->glyphAdvances,
                                               run->glyphOffsets, run->glyphCount, run->isSideways,
                                               run->bidiLevel % 2, sink.get());
        if (FAILED(hr)) return hr;
        hr = sink->Close();
        if (FAILED(hr)) return hr;
        ID2D1TransformedGeometry *placed = nullptr;
        hr = factory_->CreateTransformedGeometry(path.get(), D2D1::Matrix3x2F::Translation(x, y),
                                                 &placed);
        if (FAILED(hr)) return hr;
        geometries.push_back(placed);
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE DrawUnderline(void *, FLOAT, FLOAT, const DWRITE_UNDERLINE *,
                                            IUnknown *) override {
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE DrawStrikethrough(void *, FLOAT, FLOAT, const DWRITE_STRIKETHROUGH *,
                                                IUnknown *) override {
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE DrawInlineObject(void *, FLOAT, FLOAT, IDWriteInlineObject *, BOOL,
                                               BOOL, IUnknown *) override {
        return S_OK;
    }

  private:
    ID2D1Factory *factory_;
    ULONG references_ = 1;
};

// The first of the comma-separated families the system has, or Segoe UI.
// 逗號分隔的家族中系統有的第一個，否則 Segoe UI。
std::wstring chooseFamily(IDWriteFactory *dwrite, const wchar_t *families) {
    ComRef<IDWriteFontCollection> collection;
    if (SUCCEEDED(dwrite->GetSystemFontCollection(collection.put(), FALSE)) && families) {
        std::wstring list(families);
        size_t start = 0;
        while (start <= list.size()) {
            size_t end = list.find(L',', start);
            if (end == std::wstring::npos) end = list.size();
            std::wstring name = list.substr(start, end - start);
            while (!name.empty() && name.front() == L' ') name.erase(name.begin());
            while (!name.empty() && name.back() == L' ') name.pop_back();
            UINT32 index = 0;
            BOOL exists = FALSE;
            if (!name.empty() && SUCCEEDED(collection->FindFamilyName(name.c_str(), &index, &exists)) &&
                exists) {
                return name;
            }
            start = end + 1;
        }
    }
    return L"Segoe UI";
}

}  // namespace

extern "C" int scui_svg_text_mask(const uint16_t *text, int textLength, const uint16_t *families,
                                  double fontSize, int bold, int italic, int anchor, double a,
                                  double b, double c, double d, double tx, double ty,
                                  double strokeWidth, int width, int height, uint8_t *out) {
    if (!text || textLength <= 0 || fontSize <= 0 || width <= 0 || height <= 0 || !out) return 0;

    // WIC is COM. The WinUI thread already has an apartment; anything else gets one
    // for the call. / WIC 是 COM。WinUI 執行緒已經有 apartment;其他執行緒在這次呼叫期間取得一個。
    HRESULT com = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    struct Uninit {
        bool on;
        ~Uninit() {
            if (on) CoUninitialize();
        }
    } uninit{SUCCEEDED(com)};

    ComRef<ID2D1Factory> d2d;
    if (FAILED(D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, d2d.put()))) return 0;
    ComRef<IDWriteFactory> dwrite;
    if (FAILED(DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory),
                                   reinterpret_cast<IUnknown **>(dwrite.put()))))
        return 0;
    ComRef<IWICImagingFactory> wic;
    if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(wic.put()))))
        return 0;

    std::wstring family = chooseFamily(dwrite.get(), reinterpret_cast<const wchar_t *>(families));
    ComRef<IDWriteTextFormat> format;
    if (FAILED(dwrite->CreateTextFormat(family.c_str(), nullptr,
                                        bold ? DWRITE_FONT_WEIGHT_BOLD : DWRITE_FONT_WEIGHT_NORMAL,
                                        italic ? DWRITE_FONT_STYLE_ITALIC : DWRITE_FONT_STYLE_NORMAL,
                                        DWRITE_FONT_STRETCH_NORMAL, static_cast<FLOAT>(fontSize),
                                        L"", format.put())))
        return 0;
    format->SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP);
    ComRef<IDWriteTextLayout> layout;
    if (FAILED(dwrite->CreateTextLayout(reinterpret_cast<const wchar_t *>(text),
                                        static_cast<UINT32>(textLength), format.get(), 1.0e6f,
                                        1.0e6f, layout.put())))
        return 0;

    DWRITE_TEXT_METRICS metrics{};
    if (FAILED(layout->GetMetrics(&metrics))) return 0;
    DWRITE_LINE_METRICS line{};
    UINT32 lines = 0;
    if (FAILED(layout->GetLineMetrics(&line, 1, &lines)) || lines == 0) return 0;
    double advance = metrics.widthIncludingTrailingWhitespace;
    double offset = anchor == 1 ? advance / 2 : (anchor == 2 ? advance : 0);

    // The layout draws from its top-left corner; this origin puts the baseline on
    // y = 0 and the anchor on x = 0, as Pango's move_to does in GtkBackend.
    // 版面從左上角開始畫；這個原點讓基線落在 y = 0、錨點落在 x = 0,與 GtkBackend 中 Pango 的 move_to 相同。
    OutlineCollector collector(d2d.get());
    if (FAILED(layout->Draw(nullptr, &collector, static_cast<FLOAT>(-offset),
                            static_cast<FLOAT>(-line.baseline))))
        return 0;

    ComRef<IWICBitmap> bitmap;
    if (FAILED(wic->CreateBitmap(static_cast<UINT>(width), static_cast<UINT>(height),
                                 GUID_WICPixelFormat32bppPBGRA, WICBitmapCacheOnLoad, bitmap.put())))
        return 0;
    D2D1_RENDER_TARGET_PROPERTIES properties = D2D1::RenderTargetProperties(
        D2D1_RENDER_TARGET_TYPE_SOFTWARE,
        D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED), 96, 96);
    ComRef<ID2D1RenderTarget> target;
    if (FAILED(d2d->CreateWicBitmapRenderTarget(bitmap.get(), properties, target.put()))) return 0;
    ComRef<ID2D1SolidColorBrush> white;
    if (FAILED(target->CreateSolidColorBrush(D2D1::ColorF(1, 1, 1, 1), white.put()))) return 0;

    target->BeginDraw();
    target->Clear(D2D1::ColorF(0, 0, 0, 0));
    target->SetAntialiasMode(D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
    target->SetTransform(D2D1::Matrix3x2F(static_cast<FLOAT>(a), static_cast<FLOAT>(b),
                                          static_cast<FLOAT>(c), static_cast<FLOAT>(d),
                                          static_cast<FLOAT>(tx), static_cast<FLOAT>(ty)));
    for (auto *geometry : collector.geometries) {
        if (strokeWidth > 0) {
            target->DrawGeometry(geometry, white.get(), static_cast<FLOAT>(strokeWidth));
        } else {
            target->FillGeometry(geometry, white.get());
        }
    }
    if (FAILED(target->EndDraw())) return 0;

    WICRect rect{0, 0, width, height};
    ComRef<IWICBitmapLock> lock;
    if (FAILED(bitmap->Lock(&rect, WICBitmapLockRead, lock.put()))) return 0;
    UINT stride = 0, size = 0;
    BYTE *data = nullptr;
    if (FAILED(lock->GetStride(&stride)) || FAILED(lock->GetDataPointer(&size, &data)) || !data)
        return 0;
    // Premultiplied white: the alpha byte is the coverage.
    // 預乘的白色:alpha 位元組就是覆蓋率。
    for (int row = 0; row < height; row++) {
        const BYTE *source = data + static_cast<size_t>(row) * stride;
        for (int column = 0; column < width; column++) {
            out[static_cast<size_t>(row) * width + column] = source[column * 4 + 3];
        }
    }
    return 1;
}

#endif  // _WIN32
