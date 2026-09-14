// Captures a named top-level window with Windows Graphics Capture and writes a
// 32-bit BMP. PrintWindow remains a fallback for hosts where WGC is unavailable.

#include <windows.h>
#include <dwmapi.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstring>
#include <cstdio>
#include <cwctype>
#include <fstream>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

using namespace winrt;
namespace capture = winrt::Windows::Graphics::Capture;
namespace directx = winrt::Windows::Graphics::DirectX;
namespace direct3d = winrt::Windows::Graphics::DirectX::Direct3D11;

namespace {

struct Image {
    int width = 0;
    int height = 0;
    std::vector<std::uint8_t> bgra;
};

int nonBlackTenths(Image const& image);

std::wstring needle;
HWND target = nullptr;

std::wstring windowTitle(HWND window) {
    wchar_t value[512]{};
    int length = GetWindowTextW(window, value, static_cast<int>(std::size(value)));
    return length > 0 ? std::wstring(value, length) : std::wstring();
}

std::wstring lowercase(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t character) {
        return static_cast<wchar_t>(std::towlower(character));
    });
    return value;
}

BOOL CALLBACK findWindow(HWND window, LPARAM) {
    if (target || !IsWindowVisible(window)) return TRUE;
    auto title = windowTitle(window);
    if (!title.empty() && lowercase(title).find(needle) != std::wstring::npos) {
        target = window;
        std::wprintf(L"window: %ls\n", title.c_str());
        return FALSE;
    }
    return TRUE;
}

com_ptr<ID3D11Device> makeD3DDevice() {
    UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
    D3D_FEATURE_LEVEL levels[] = {
        D3D_FEATURE_LEVEL_11_1,
        D3D_FEATURE_LEVEL_11_0,
        D3D_FEATURE_LEVEL_10_1,
        D3D_FEATURE_LEVEL_10_0,
    };
    com_ptr<ID3D11Device> device;
    com_ptr<ID3D11DeviceContext> context;
    D3D_FEATURE_LEVEL level{};
    check_hresult(D3D11CreateDevice(
        nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, flags, levels,
        static_cast<UINT>(std::size(levels)), D3D11_SDK_VERSION,
        device.put(), &level, context.put()));
    return device;
}

direct3d::IDirect3DDevice makeWinRTDevice(ID3D11Device* device) {
    com_ptr<IDXGIDevice> dxgi;
    check_hresult(device->QueryInterface(dxgi.put()));
    com_ptr<IInspectable> inspectable;
    check_hresult(CreateDirect3D11DeviceFromDXGIDevice(dxgi.get(), inspectable.put()));
    return inspectable.as<direct3d::IDirect3DDevice>();
}

capture::GraphicsCaptureItem captureItemForWindow(HWND window) {
    auto itemInterop = get_activation_factory<capture::GraphicsCaptureItem, IGraphicsCaptureItemInterop>();
    capture::GraphicsCaptureItem item{nullptr};
    check_hresult(itemInterop->CreateForWindow(
        window, guid_of<capture::GraphicsCaptureItem>(), put_abi(item)));
    return item;
}

std::optional<Image> captureWithWGC(
    capture::GraphicsCaptureItem const& item,
    std::chrono::milliseconds timeout
) {

    auto d3dDevice = makeD3DDevice();
    auto context = [&] {
        com_ptr<ID3D11DeviceContext> value;
        d3dDevice->GetImmediateContext(value.put());
        return value;
    }();
    auto winrtDevice = makeWinRTDevice(d3dDevice.get());
    auto size = item.Size();
    if (size.Width <= 0 || size.Height <= 0) return std::nullopt;

    auto pool = capture::Direct3D11CaptureFramePool::CreateFreeThreaded(
        winrtDevice, directx::DirectXPixelFormat::B8G8R8A8UIntNormalized, 2, size);
    auto session = pool.CreateCaptureSession(item);
    std::mutex mutex;
    std::condition_variable condition;
    capture::Direct3D11CaptureFrame captured{nullptr};
    auto token = pool.FrameArrived([&](auto const& sender, auto const&) {
        std::lock_guard lock(mutex);
        captured = sender.TryGetNextFrame();
        condition.notify_one();
    });

    session.StartCapture();
    std::optional<Image> result;
    auto deadline = std::chrono::steady_clock::now() + timeout;
    while (std::chrono::steady_clock::now() < deadline) {
        capture::Direct3D11CaptureFrame frame{nullptr};
        {
            std::unique_lock lock(mutex);
            condition.wait_until(lock, deadline, [&] { return captured != nullptr; });
            if (!captured) break;
            frame = captured;
            captured = nullptr;
        }

        auto contentSize = frame.ContentSize();
        auto access = frame.Surface().as<::Windows::Graphics::DirectX::Direct3D11::IDirect3DDxgiInterfaceAccess>();
        com_ptr<ID3D11Texture2D> source;
        check_hresult(access->GetInterface(__uuidof(ID3D11Texture2D), source.put_void()));
        D3D11_TEXTURE2D_DESC description{};
        source->GetDesc(&description);
        description.Width = static_cast<UINT>(contentSize.Width);
        description.Height = static_cast<UINT>(contentSize.Height);
        description.Usage = D3D11_USAGE_STAGING;
        description.BindFlags = 0;
        description.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
        description.MiscFlags = 0;
        com_ptr<ID3D11Texture2D> staging;
        check_hresult(d3dDevice->CreateTexture2D(&description, nullptr, staging.put()));

        D3D11_BOX region{0, 0, 0, description.Width, description.Height, 1};
        context->CopySubresourceRegion(staging.get(), 0, 0, 0, 0, source.get(), 0, &region);
        D3D11_MAPPED_SUBRESOURCE mapped{};
        check_hresult(context->Map(staging.get(), 0, D3D11_MAP_READ, 0, &mapped));
        Image image;
        image.width = static_cast<int>(description.Width);
        image.height = static_cast<int>(description.Height);
        auto rowBytes = static_cast<std::size_t>(image.width) * 4;
        image.bgra.resize(rowBytes * static_cast<std::size_t>(image.height));
        for (int row = 0; row < image.height; ++row) {
            std::memcpy(
                image.bgra.data() + static_cast<std::size_t>(row) * rowBytes,
                static_cast<std::uint8_t*>(mapped.pData) + static_cast<std::size_t>(row) * mapped.RowPitch,
                rowBytes);
        }
        context->Unmap(staging.get(), 0);
        frame.Close();
        result = std::move(image);
        if (nonBlackTenths(*result) >= 20) break;
    }
    pool.FrameArrived(token);
    session.Close();
    pool.Close();
    return result;
}

std::optional<Image> captureWithPrintWindow(HWND window) {
    RECT rect{};
    if (!GetWindowRect(window, &rect)) return std::nullopt;
    int width = rect.right - rect.left;
    int height = rect.bottom - rect.top;
    if (width <= 0 || height <= 0) return std::nullopt;

    HDC screen = GetDC(nullptr);
    HDC memory = CreateCompatibleDC(screen);
    BITMAPINFO info{};
    info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth = width;
    info.bmiHeader.biHeight = -height;
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = BI_RGB;
    void* bits = nullptr;
    HBITMAP bitmap = CreateDIBSection(memory, &info, DIB_RGB_COLORS, &bits, nullptr, 0);
    if (!bitmap || !bits) {
        DeleteDC(memory);
        ReleaseDC(nullptr, screen);
        return std::nullopt;
    }
    HGDIOBJ old = SelectObject(memory, bitmap);
    BOOL ok = PrintWindow(window, memory, 0x00000002);

    Image image;
    image.width = width;
    image.height = height;
    auto byteCount = static_cast<std::size_t>(width) * height * 4;
    image.bgra.assign(static_cast<std::uint8_t*>(bits), static_cast<std::uint8_t*>(bits) + byteCount);
    SelectObject(memory, old);
    DeleteObject(bitmap);
    DeleteDC(memory);
    ReleaseDC(nullptr, screen);
    if (!ok) return std::nullopt;
    return image;
}

int nonBlackTenths(Image const& image) {
    std::size_t count = 0;
    for (std::size_t index = 0; index < image.bgra.size(); index += 4) {
        if (image.bgra[index] > 8 || image.bgra[index + 1] > 8 || image.bgra[index + 2] > 8) ++count;
    }
    auto pixels = static_cast<std::size_t>(image.width) * image.height;
    return pixels ? static_cast<int>(count * 1000 / pixels) : 0;
}

bool writeBMP(std::wstring const& path, Image const& image) {
    auto rowBytes = static_cast<std::uint32_t>(image.width * 4);
    auto pixelBytes = rowBytes * static_cast<std::uint32_t>(image.height);
    BITMAPFILEHEADER file{};
    file.bfType = 0x4D42;
    file.bfOffBits = sizeof(BITMAPFILEHEADER) + sizeof(BITMAPINFOHEADER);
    file.bfSize = file.bfOffBits + pixelBytes;
    BITMAPINFOHEADER info{};
    info.biSize = sizeof(info);
    info.biWidth = image.width;
    info.biHeight = image.height;
    info.biPlanes = 1;
    info.biBitCount = 32;
    info.biCompression = BI_RGB;
    info.biSizeImage = pixelBytes;

    std::ofstream output(path, std::ios::binary);
    if (!output) return false;
    output.write(reinterpret_cast<char const*>(&file), sizeof(file));
    output.write(reinterpret_cast<char const*>(&info), sizeof(info));
    for (int row = image.height - 1; row >= 0; --row) {
        output.write(
            reinterpret_cast<char const*>(image.bgra.data() + static_cast<std::size_t>(row) * rowBytes),
            rowBytes);
    }
    return output.good();
}

} // namespace

int wmain(int argc, wchar_t** argv) {
    if (argc < 3) {
        std::fputs("usage: wincap.exe <title substring> <out.bmp>\n", stderr);
        return 2;
    }
    init_apartment(apartment_type::multi_threaded);
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    needle = lowercase(argv[1]);
    auto deadline = GetTickCount64() + 5000;
    do {
        target = nullptr;
        EnumWindows(findWindow, 0);
        if (target) break;
        Sleep(250);
    } while (GetTickCount64() < deadline);
    if (!target) {
        std::fwprintf(stderr, L"no visible window matched \"%ls\"\n", argv[1]);
        return 1;
    }

    RECT rect{};
    GetWindowRect(target, &rect);
    auto exstyle = static_cast<unsigned long long>(GetWindowLongPtrW(target, GWL_EXSTYLE));
    DWORD cloaked = 0;
    DwmGetWindowAttribute(target, DWMWA_CLOAKED, &cloaked, sizeof(cloaked));
    DWORD affinity = 0;
    GetWindowDisplayAffinity(target, &affinity);
    std::printf("window rect: (%ld,%ld)-(%ld,%ld) %ldx%ld  exstyle: 0x%llx\n",
        rect.left, rect.top, rect.right, rect.bottom,
        rect.right - rect.left, rect.bottom - rect.top, exstyle);
    std::printf("window state: cloaked=%lu displayAffinity=0x%lx\n", cloaked, affinity);

    std::optional<Image> image;
    char const* method = "WindowsGraphicsCapture";
    try {
        image = captureWithWGC(captureItemForWindow(target), std::chrono::milliseconds(750));
    } catch (hresult_error const& error) {
        std::printf("WindowsGraphicsCapture failed: 0x%08lx\n", static_cast<unsigned long>(error.code().value));
    }
    if (image) {
        auto wgcTenths = nonBlackTenths(*image);
        std::printf("WindowsGraphicsCapture frame: %dx%d  non-black: %d.%d%%\n",
            image->width, image->height, wgcTenths / 10, wgcTenths % 10);
    }
    if (!image || nonBlackTenths(*image) < 20) {
        method = "PrintWindowFallback";
        image = captureWithPrintWindow(target);
    }
    if (!image) {
        std::fputs("capture failed\n", stderr);
        return 1;
    }

    auto tenths = nonBlackTenths(*image);
    auto pixels = static_cast<std::size_t>(image->width) * image->height;
    std::size_t nonBlack = pixels * static_cast<std::size_t>(tenths) / 1000;
    std::printf("method: %s\n", method);
    std::printf("size: %dx%d  non-black: %zu/%zu (%d.%d%%)\n",
        image->width, image->height, nonBlack, pixels, tenths / 10, tenths % 10);
    if (!writeBMP(argv[2], *image)) {
        std::fwprintf(stderr, L"write failed: %ls\n", argv[2]);
        return 1;
    }
    std::wprintf(L"wrote %ls\n", argv[2]);
    if (tenths < 20) {
        std::printf("capture rejected: %d.%d%% non-black is below the 2%% minimum\n", tenths / 10, tenths % 10);
        return 3;
    }
    return 0;
}
