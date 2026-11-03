import CWinRT
@_spi(Backends) import SwiftCrossUI
import WinAppSDK
import WinSDK
import WinUI
@preconcurrency import WindowsFoundation

public func getWindowIDFromWindow(_ hWnd: HWND?) -> WinAppSDK.WindowId {
    HWNDInterop.shared.getWindowIDFromWindow(hWnd)
}

public func getWindowFromWindowId(_ windowID: WinAppSDK.WindowId) -> HWND? {
    HWNDInterop.shared.getWindowFromWindowId(windowID)
}

extension WinAppSDK.AppWindow {
    /// Returns the window handle for the app window.
    public func getHWND() -> HWND? {
        HWNDInterop.shared.getWindowFromWindowId(id)
    }
}

extension WinUI.Window {
    /// Returns the window handle for the window.
    ///
    /// - Note: This is a relatively expensive operation, particularly due to its use
    /// of the `appWindow` getter. If an `AppWindow` is already available, prefer to
    /// use `getHWND()` on that instead; better yet, if the window handle will be used
    /// frequently, assign it to a stored property, as it will not change during the
    /// lifetime of the window.
    public func getHWND() -> HWND? {
        // The appWindow can become nil when a Window is closed.
        guard let appWindow else { return nil }
        return appWindow.getHWND()
    }
}

/// - Safety: This is sendable because all of the pointers have static lifetimes
///   and can be shared across threads. The pointers aren't used for internal
///   mutability.
private struct HWNDInterop: @unchecked Sendable {
    private typealias pfnGetWindowIdFromWindow =
        @convention(c) (
            HWND?,
            UnsafeMutablePointer<__x_ABI_CMicrosoft_CUI_CWindowId>?
        ) -> HRESULT
    private typealias pfnGetWindowFromWindowId =
        @convention(c) (
            __x_ABI_CMicrosoft_CUI_CWindowId,
            UnsafeMutablePointer<HWND?>?
        ) -> HRESULT
    private var hModule: HMODULE!
    private var getWindowIDFromWindow_impl: pfnGetWindowIdFromWindow!
    private var getWindowFromWindowID_impl: pfnGetWindowFromWindowId!

    static let shared = HWNDInterop()

    init() {
        "Microsoft.Internal.FrameworkUdk.dll".withCString(encodedAs: UTF16.self) {
            hModule = GetModuleHandleW($0)
            if hModule == nil {
                hModule = LoadLibraryW($0)
            }
        }

        if let pfn = GetProcAddress(hModule, "Windowing_GetWindowIdFromWindow") {
            getWindowIDFromWindow_impl = unsafeBitCast(pfn, to: pfnGetWindowIdFromWindow.self)
        }

        if let pfn = GetProcAddress(hModule, "Windowing_GetWindowFromWindowId") {
            getWindowFromWindowID_impl = unsafeBitCast(pfn, to: pfnGetWindowFromWindowId.self)
        }
    }

    /// The id of a window, or the invalid id 0 if there is none -- a destroyed
    /// window is the usual reason, and that is no reason to end the process.
    /// 視窗的 id;沒有時為無效的 id 0——通常是視窗已銷毀，而那不是終止行程的理由。
    fileprivate func getWindowIDFromWindow(_ hWnd: HWND?) -> WinAppSDK.WindowId {
        var windowID = __x_ABI_CMicrosoft_CUI_CWindowId()
        guard let impl = getWindowIDFromWindow_impl else {
            logger.warning("Windowing_GetWindowIdFromWindow is unavailable")
            return .init(value: 0)
        }
        let hr: HRESULT = impl(hWnd, &windowID)
        if hr != S_OK {
            logger.warning("Unable to get window ID, hr=\(hr)")
            return .init(value: 0)
        }
        return .init(value: windowID.Value)
    }

    /// The window handle for an id, or nil: a closed window's id no longer
    /// maps to a handle, and callers already treat nil as "no window".
    /// id 對應的視窗 handle,或 nil:已關閉視窗的 id 不再對應到 handle,而呼叫端本來就把 nil 當成「沒有視窗」。
    fileprivate func getWindowFromWindowId(_ windowID: WinAppSDK.WindowId) -> HWND? {
        var hWnd: HWND?
        guard let impl = getWindowFromWindowID_impl else {
            logger.warning("Windowing_GetWindowFromWindowId is unavailable")
            return nil
        }
        let hr: HRESULT = impl(.from(swift: windowID), &hWnd)
        if hr != S_OK {
            return nil
        }
        return hWnd
    }
}
