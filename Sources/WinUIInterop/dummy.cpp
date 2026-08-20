// Without these imports, WinUIBackend's SwiftIInitializeWithWindow wrapper
// class fails to compile.
//
// Guarded for the same reason the header is: SwiftPM cannot make a target
// itself conditional, only a dependency on one, so this file is compiled on
// every platform. Unguarded it stopped `swift test` on Linux at
// `'ShObjIdl.h' file not found`. See the header for why that is necessary but
// not sufficient -- the build then stops inside swift-winui instead, and tests
// run on Windows. On other platforms this compiles to an empty translation
// unit.

#ifdef _WIN32

#include "WinUIInterop.h"
#include <ShObjIdl.h>
#include <Windows.h>

#endif  // _WIN32
