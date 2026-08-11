#include <Windows.h>
#include <ShObjIdl.h>
#include <d3d11.h>
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
