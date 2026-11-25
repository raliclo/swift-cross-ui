// Composition effect graph nodes for Direct2D's built-in effects, without Win2D.
//
// A CompositionEffectFactory takes a Windows.Graphics.Effects.IGraphicsEffect and
// asks it, through IGraphicsEffectD2D1Interop, for a Direct2D effect CLSID, its
// properties by index and its sources. Win2D's effect classes are one implementation
// of that; this file is another, so WinUIBackend's visual effects need no
// Microsoft.Graphics.Canvas.dll (the user's decision, 2026-11-24: CI had no Win2D
// and every WinUI filter effect was silently skipped there). The interfaces are
// declared by hand, as composition_surface.cpp does, because their headers need
// the WinRT include directory; the property indices are checked against
// d2d1effects.h at compile time.
//
// Direct2D 內建效果的 Composition 效果圖節點，不使用 Win2D。
//
// CompositionEffectFactory 接受一個 Windows.Graphics.Effects.IGraphicsEffect,並經由
// IGraphicsEffectD2D1Interop 向它取得 Direct2D 效果的 CLSID、依索引的屬性與來源。Win2D 的效果類別是一種實作；
// 本檔是另一種，因此 WinUIBackend 的視覺效果不需要 Microsoft.Graphics.Canvas.dll(使用者的決定，2026-11-24:
// CI 沒有 Win2D,WinUI 的所有濾鏡效果在那裡都被無聲略過)。介面與 composition_surface.cpp 一樣手寫宣告，
// 因為它們的標頭需要 WinRT 的 include 目錄；屬性索引在編譯時與 d2d1effects.h 比對。

#ifdef _WIN32

#include "WinUIInterop.h"
#include <initguid.h>
#include <d2d1_1.h>
#include <d2d1effects.h>
#include <new>

namespace {

const IID kInspectable = {
    0xAF86E2E0, 0xB12D, 0x4C6A, {0x9C, 0x5A, 0xD7, 0xAA, 0x65, 0x10, 0x1E, 0x90}};
const IID kAgileObject = {
    0x94EA2B94, 0xE9CC, 0x49E0, {0xC0, 0xFF, 0xEE, 0x64, 0xCA, 0x8F, 0x5B, 0x90}};
const IID kGraphicsEffect = {
    0xCB51C0CE, 0x8FE6, 0x4636, {0xB2, 0x02, 0x86, 0x1F, 0xAA, 0x07, 0xD8, 0xF3}};
const IID kGraphicsEffectSource = {
    0x2D8F9DDC, 0x4339, 0x4EB9, {0x92, 0x16, 0xF9, 0xDE, 0xB7, 0x56, 0x58, 0xA2}};
// From windows.graphics.effects.interop.h. / 取自 windows.graphics.effects.interop.h。
const IID kGraphicsEffectD2D1Interop = {
    0x2FC57384, 0xA068, 0x44D7, {0xA3, 0x31, 0x30, 0x98, 0x2F, 0xCF, 0x71, 0x77}};
const IID kPropertyValue = {
    0x4BD682DD, 0x7554, 0x40E9, {0x9A, 0x9B, 0x82, 0x65, 0x4E, 0xDE, 0x7E, 0x62}};

// IInspectable, IGraphicsEffect (which adds Name) and IGraphicsEffectSource (which
// adds nothing, so IGraphicsEffect's vtable serves for it).
// IInspectable、IGraphicsEffect(加上 Name)與 IGraphicsEffectSource(沒有新增方法，因此可用 IGraphicsEffect 的 vtable)。
struct Inspectable : public IUnknown {
    virtual HRESULT STDMETHODCALLTYPE GetIids(ULONG *count, IID **iids) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetRuntimeClassName(void **className) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetTrustLevel(int *trustLevel) = 0;
};

struct GraphicsEffect : public Inspectable {
    virtual HRESULT STDMETHODCALLTYPE get_Name(void **name) = 0;
    virtual HRESULT STDMETHODCALLTYPE put_Name(void *name) = 0;
};

struct GraphicsEffectD2D1Interop : public IUnknown {
    virtual HRESULT STDMETHODCALLTYPE GetEffectId(GUID *id) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetNamedPropertyMapping(const wchar_t *name, UINT *index,
                                                              int *mapping) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetPropertyCount(UINT *count) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetProperty(UINT index, IUnknown **value) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetSource(UINT index, IUnknown **source) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetSourceCount(UINT *count) = 0;
};

constexpr UINT kMaxProperties = 17; // GammaTransfer's, the most of these effects
constexpr UINT kMaxSources = 2;     // ArithmeticComposite's, Blend's and Composite's

class EffectNode final : public GraphicsEffect, public GraphicsEffectD2D1Interop {
  public:
    EffectNode(const GUID &id, UINT propertyCount, UINT sourceCount)
        : id_(id), propertyCount_(propertyCount), sourceCount_(sourceCount) {}

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **out) override {
        if (out == nullptr) {
            return E_POINTER;
        }
        if (IsEqualIID(riid, __uuidof(IUnknown)) || IsEqualIID(riid, kInspectable) ||
            IsEqualIID(riid, kGraphicsEffect) || IsEqualIID(riid, kGraphicsEffectSource) ||
            IsEqualIID(riid, kAgileObject)) {
            *out = static_cast<GraphicsEffect *>(this);
        } else if (IsEqualIID(riid, kGraphicsEffectD2D1Interop)) {
            *out = static_cast<GraphicsEffectD2D1Interop *>(this);
        } else {
            *out = nullptr;
            return E_NOINTERFACE;
        }
        AddRef();
        return S_OK;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return InterlockedIncrement(&refs_); }
    ULONG STDMETHODCALLTYPE Release() override {
        ULONG left = InterlockedDecrement(&refs_);
        if (left == 0) {
            delete this;
        }
        return left;
    }

    HRESULT STDMETHODCALLTYPE GetIids(ULONG *count, IID **iids) override {
        if (count == nullptr || iids == nullptr) {
            return E_POINTER;
        }
        *count = 0;
        *iids = nullptr;
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetRuntimeClassName(void **className) override {
        if (className == nullptr) {
            return E_POINTER;
        }
        *className = nullptr; // the empty HSTRING / 空的 HSTRING
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetTrustLevel(int *trustLevel) override {
        if (trustLevel == nullptr) {
            return E_POINTER;
        }
        *trustLevel = 0; // BaseTrust
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE get_Name(void **name) override {
        if (name == nullptr) {
            return E_POINTER;
        }
        *name = nullptr;
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE put_Name(void *) override { return S_OK; }

    HRESULT STDMETHODCALLTYPE GetEffectId(GUID *id) override {
        if (id == nullptr) {
            return E_POINTER;
        }
        *id = id_;
        return S_OK;
    }
    // No property is animated, so none has a name.
    // 沒有任何屬性做動畫，因此沒有屬性需要名稱。
    HRESULT STDMETHODCALLTYPE GetNamedPropertyMapping(const wchar_t *, UINT *, int *) override {
        return E_INVALIDARG;
    }
    HRESULT STDMETHODCALLTYPE GetPropertyCount(UINT *count) override {
        if (count == nullptr) {
            return E_POINTER;
        }
        *count = propertyCount_;
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetProperty(UINT index, IUnknown **value) override {
        if (value == nullptr) {
            return E_POINTER;
        }
        *value = nullptr;
        if (index >= propertyCount_ || properties_[index] == nullptr) {
            return E_INVALIDARG;
        }
        return properties_[index]->QueryInterface(kPropertyValue, reinterpret_cast<void **>(value));
    }
    HRESULT STDMETHODCALLTYPE GetSource(UINT index, IUnknown **source) override {
        if (source == nullptr) {
            return E_POINTER;
        }
        *source = nullptr;
        if (index >= sourceCount_ || sources_[index] == nullptr) {
            return E_INVALIDARG;
        }
        return sources_[index]->QueryInterface(kGraphicsEffectSource,
                                               reinterpret_cast<void **>(source));
    }
    HRESULT STDMETHODCALLTYPE GetSourceCount(UINT *count) override {
        if (count == nullptr) {
            return E_POINTER;
        }
        *count = sourceCount_;
        return S_OK;
    }

    bool setProperty(UINT index, IUnknown *value) { return set(properties_, propertyCount_, index, value); }
    bool setSource(UINT index, IUnknown *source) { return set(sources_, sourceCount_, index, source); }

  private:
    ~EffectNode() {
        for (IUnknown *p : properties_) {
            if (p) {
                p->Release();
            }
        }
        for (IUnknown *s : sources_) {
            if (s) {
                s->Release();
            }
        }
    }

    template <UINT N> static bool set(IUnknown *(&slots)[N], UINT count, UINT index, IUnknown *value) {
        if (index >= count || value == nullptr) {
            return false;
        }
        value->AddRef();
        if (slots[index]) {
            slots[index]->Release();
        }
        slots[index] = value;
        return true;
    }

    volatile LONG refs_ = 1;
    GUID id_;
    UINT propertyCount_;
    UINT sourceCount_;
    IUnknown *properties_[kMaxProperties] = {};
    IUnknown *sources_[kMaxSources] = {};
};

// The indices WinUIInterop.h names, checked against the SDK's own.
// WinUIInterop.h 所命名的索引，與 SDK 自己的比對。
static_assert(int(SCUI_COLORMATRIX_MATRIX) == int(D2D1_COLORMATRIX_PROP_COLOR_MATRIX), "");
static_assert(int(SCUI_COLORMATRIX_ALPHA_MODE) == int(D2D1_COLORMATRIX_PROP_ALPHA_MODE), "");
static_assert(int(SCUI_COLORMATRIX_CLAMP) == int(D2D1_COLORMATRIX_PROP_CLAMP_OUTPUT), "");
static_assert(int(SCUI_COLORMATRIX_ALPHA_PREMULTIPLIED) == int(D2D1_COLORMATRIX_ALPHA_MODE_PREMULTIPLIED), "");
static_assert(int(SCUI_BLUR_DEVIATION) == int(D2D1_GAUSSIANBLUR_PROP_STANDARD_DEVIATION), "");
static_assert(int(SCUI_BLUR_OPTIMIZATION) == int(D2D1_GAUSSIANBLUR_PROP_OPTIMIZATION), "");
static_assert(int(SCUI_BLUR_BORDER_MODE) == int(D2D1_GAUSSIANBLUR_PROP_BORDER_MODE), "");
static_assert(int(SCUI_BLUR_OPTIMIZATION_BALANCED) == int(D2D1_GAUSSIANBLUR_OPTIMIZATION_BALANCED), "");
static_assert(int(SCUI_BLUR_BORDER_SOFT) == int(D2D1_BORDER_MODE_SOFT), "");
static_assert(int(SCUI_ARITHMETIC_COEFFICIENTS) == int(D2D1_ARITHMETICCOMPOSITE_PROP_COEFFICIENTS), "");
static_assert(int(SCUI_ARITHMETIC_CLAMP) == int(D2D1_ARITHMETICCOMPOSITE_PROP_CLAMP_OUTPUT), "");
static_assert(int(SCUI_LINEAR_RED_INTERCEPT) == int(D2D1_LINEARTRANSFER_PROP_RED_Y_INTERCEPT), "");
static_assert(int(SCUI_LINEAR_RED_SLOPE) == int(D2D1_LINEARTRANSFER_PROP_RED_SLOPE), "");
static_assert(int(SCUI_LINEAR_RED_DISABLE) == int(D2D1_LINEARTRANSFER_PROP_RED_DISABLE), "");
static_assert(int(SCUI_LINEAR_GREEN_INTERCEPT) == int(D2D1_LINEARTRANSFER_PROP_GREEN_Y_INTERCEPT), "");
static_assert(int(SCUI_LINEAR_BLUE_INTERCEPT) == int(D2D1_LINEARTRANSFER_PROP_BLUE_Y_INTERCEPT), "");
static_assert(int(SCUI_LINEAR_ALPHA_INTERCEPT) == int(D2D1_LINEARTRANSFER_PROP_ALPHA_Y_INTERCEPT), "");
static_assert(int(SCUI_LINEAR_ALPHA_DISABLE) == int(D2D1_LINEARTRANSFER_PROP_ALPHA_DISABLE), "");
static_assert(int(SCUI_LINEAR_CLAMP) == int(D2D1_LINEARTRANSFER_PROP_CLAMP_OUTPUT), "");
static_assert(int(SCUI_GAMMA_RED_AMPLITUDE) == int(D2D1_GAMMATRANSFER_PROP_RED_AMPLITUDE), "");
static_assert(int(SCUI_GAMMA_RED_EXPONENT) == int(D2D1_GAMMATRANSFER_PROP_RED_EXPONENT), "");
static_assert(int(SCUI_GAMMA_RED_OFFSET) == int(D2D1_GAMMATRANSFER_PROP_RED_OFFSET), "");
static_assert(int(SCUI_GAMMA_RED_DISABLE) == int(D2D1_GAMMATRANSFER_PROP_RED_DISABLE), "");
static_assert(int(SCUI_GAMMA_GREEN_AMPLITUDE) == int(D2D1_GAMMATRANSFER_PROP_GREEN_AMPLITUDE), "");
static_assert(int(SCUI_GAMMA_BLUE_AMPLITUDE) == int(D2D1_GAMMATRANSFER_PROP_BLUE_AMPLITUDE), "");
static_assert(int(SCUI_GAMMA_ALPHA_AMPLITUDE) == int(D2D1_GAMMATRANSFER_PROP_ALPHA_AMPLITUDE), "");
static_assert(int(SCUI_GAMMA_ALPHA_DISABLE) == int(D2D1_GAMMATRANSFER_PROP_ALPHA_DISABLE), "");
static_assert(int(SCUI_GAMMA_CLAMP) == int(D2D1_GAMMATRANSFER_PROP_CLAMP_OUTPUT), "");
static_assert(int(SCUI_HUE_ANGLE) == int(D2D1_HUEROTATION_PROP_ANGLE), "");
static_assert(int(SCUI_D2DBLEND_MODE) == int(D2D1_BLEND_PROP_MODE), "");
static_assert(int(SCUI_D2DBLEND_MULTIPLY) == int(D2D1_BLEND_MODE_MULTIPLY), "");
static_assert(int(SCUI_D2DBLEND_SCREEN) == int(D2D1_BLEND_MODE_SCREEN), "");
static_assert(int(SCUI_D2DBLEND_DARKEN) == int(D2D1_BLEND_MODE_DARKEN), "");
static_assert(int(SCUI_D2DBLEND_LIGHTEN) == int(D2D1_BLEND_MODE_LIGHTEN), "");
static_assert(int(SCUI_D2DBLEND_COLOR_BURN) == int(D2D1_BLEND_MODE_COLOR_BURN), "");
static_assert(int(SCUI_D2DBLEND_LINEAR_BURN) == int(D2D1_BLEND_MODE_LINEAR_BURN), "");
static_assert(int(SCUI_D2DBLEND_COLOR_DODGE) == int(D2D1_BLEND_MODE_COLOR_DODGE), "");
static_assert(int(SCUI_D2DBLEND_LINEAR_DODGE) == int(D2D1_BLEND_MODE_LINEAR_DODGE), "");
static_assert(int(SCUI_D2DBLEND_OVERLAY) == int(D2D1_BLEND_MODE_OVERLAY), "");
static_assert(int(SCUI_D2DBLEND_SOFT_LIGHT) == int(D2D1_BLEND_MODE_SOFT_LIGHT), "");
static_assert(int(SCUI_D2DBLEND_HARD_LIGHT) == int(D2D1_BLEND_MODE_HARD_LIGHT), "");
static_assert(int(SCUI_D2DBLEND_DIFFERENCE) == int(D2D1_BLEND_MODE_DIFFERENCE), "");
static_assert(int(SCUI_D2DBLEND_EXCLUSION) == int(D2D1_BLEND_MODE_EXCLUSION), "");
static_assert(int(SCUI_D2DBLEND_HUE) == int(D2D1_BLEND_MODE_HUE), "");
static_assert(int(SCUI_D2DBLEND_SATURATION) == int(D2D1_BLEND_MODE_SATURATION), "");
static_assert(int(SCUI_D2DBLEND_COLOR) == int(D2D1_BLEND_MODE_COLOR), "");
static_assert(int(SCUI_D2DBLEND_LUMINOSITY) == int(D2D1_BLEND_MODE_LUMINOSITY), "");
static_assert(int(SCUI_D2DCOMPOSITE_MODE) == int(D2D1_COMPOSITE_PROP_MODE), "");
static_assert(int(SCUI_D2DCOMPOSITE_DESTINATION_OVER) == int(D2D1_COMPOSITE_MODE_DESTINATION_OVER), "");
static_assert(int(SCUI_D2DCOMPOSITE_DESTINATION_OUT) == int(D2D1_COMPOSITE_MODE_DESTINATION_OUT), "");
static_assert(int(SCUI_D2DCOMPOSITE_SOURCE_ATOP) == int(D2D1_COMPOSITE_MODE_SOURCE_ATOP), "");
static_assert(int(SCUI_D2DCOMPOSITE_SOURCE_OVER) == int(D2D1_COMPOSITE_MODE_SOURCE_OVER), "");

} // namespace

extern "C" void *scui_effect_create(int kind) {
    const GUID *id = nullptr;
    UINT properties = 0;
    UINT sources = 1;
    switch (kind) {
    case SCUI_EFFECT_COLOR_MATRIX:
        id = &CLSID_D2D1ColorMatrix;
        properties = SCUI_COLORMATRIX_CLAMP + 1;
        break;
    case SCUI_EFFECT_GAUSSIAN_BLUR:
        id = &CLSID_D2D1GaussianBlur;
        properties = SCUI_BLUR_BORDER_MODE + 1;
        break;
    case SCUI_EFFECT_ARITHMETIC_COMPOSITE:
        id = &CLSID_D2D1ArithmeticComposite;
        properties = SCUI_ARITHMETIC_CLAMP + 1;
        sources = 2;
        break;
    case SCUI_EFFECT_LINEAR_TRANSFER:
        id = &CLSID_D2D1LinearTransfer;
        properties = SCUI_LINEAR_CLAMP + 1;
        break;
    case SCUI_EFFECT_GAMMA_TRANSFER:
        id = &CLSID_D2D1GammaTransfer;
        properties = SCUI_GAMMA_CLAMP + 1;
        break;
    case SCUI_EFFECT_HUE_ROTATION:
        id = &CLSID_D2D1HueRotation;
        properties = SCUI_HUE_ANGLE + 1;
        break;
    // Two sources each: the destination (the backdrop), then the source.
    // 各有兩個來源：先是目的地(背景),再來是來源。
    case SCUI_EFFECT_BLEND:
        id = &CLSID_D2D1Blend;
        properties = SCUI_D2DBLEND_MODE + 1;
        sources = 2;
        break;
    case SCUI_EFFECT_COMPOSITE:
        id = &CLSID_D2D1Composite;
        properties = SCUI_D2DCOMPOSITE_MODE + 1;
        sources = 2;
        break;
    default:
        return nullptr;
    }
    // The IGraphicsEffect pointer, holding the one reference.
    // IGraphicsEffect 指標，持有唯一的參考。
    EffectNode *node = new (std::nothrow) EffectNode(*id, properties, sources);
    return node ? static_cast<GraphicsEffect *>(node) : nullptr;
}

extern "C" int scui_effect_set_property(void *effect, unsigned index, void *propertyValue) {
    if (effect == nullptr) {
        return 0;
    }
    auto *node = static_cast<EffectNode *>(static_cast<GraphicsEffect *>(effect));
    return node->setProperty(index, static_cast<IUnknown *>(propertyValue)) ? 1 : 0;
}

extern "C" int scui_effect_set_source(void *effect, unsigned index, void *source) {
    if (effect == nullptr) {
        return 0;
    }
    auto *node = static_cast<EffectNode *>(static_cast<GraphicsEffect *>(effect));
    return node->setSource(index, static_cast<IUnknown *>(source)) ? 1 : 0;
}

#endif
