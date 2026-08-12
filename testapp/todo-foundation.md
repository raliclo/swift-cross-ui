# Things to submit to swift-corelibs-foundation

Found while building P6's Windows video path. Each item cost a workaround in
`testapp/P6.swift` that would not exist if Foundation exposed the underlying
Win32 capability. Measurements are from this machine (Windows 11, AMD Radeon
iGPU + RTX 4060, 1920x1080 @ 125%).

## 1. `Pipe` gives no way to set the buffer size on Windows

`Sources/Foundation/FileHandle.swift` creates every pipe with a hardcoded 0:

```swift
if !CreatePipe(&hReadPipe, &hWritePipe, &saAttr, 0) {
  fatalError("CreatePipe failed")
}
```

`0` asks the kernel for its default, which is a few kilobytes. For anything
streaming bulk binary data that is far too small: an 8 MB video frame arrives in
thousands of reads, and each `read(upToCount:)` allocates a `Data` that the
caller then has to append into a growing buffer.

**Measured**: 102-164 ms to move one 1080p frame from a child process into the
app, against a 33 ms frame budget. Replacing the pipe with `CreatePipe` at 2
frames' worth of buffer, read with `ReadFile`, took the same work to 2-9 ms.

**Proposed**: pass a larger default `nSize`, or add an initialiser taking a
buffer size (`Pipe(bufferSize:)`). A larger default alone would fix most of it
and breaks no API.

**Note**: bigger is not automatically better. Measured at 4K60, 25 MB gave
49.9 fps, 128 MB gave 51.6, 512 MB gave 48.2 and 2 GB gave 45.3. A buffer at
least as large as one message is what matters; past that it only adds latency.

## 2. `FileHandle.fileDescriptor` is unavailable on Windows

Reading it traps with "Cannot perform non-owning handle to fd conversion", and
there is no other way to reach the underlying `HANDLE`. That makes any
zero-copy read impossible: bytes cannot be read straight into caller-provided
memory (here, a mapped D3D11 staging texture), because every read has to go
through a `Data` that Foundation allocates.

**Proposed**: expose the native handle on Windows -- either by making
`fileDescriptor` work, or by adding a documented Windows-only property
returning the `HANDLE`. Both `Pipe` and `FileHandle` need it.

**Workaround in P6**: `P6WideWin32Pipe` creates the pipe with `CreatePipe` and
keeps the raw handles, so `ReadFile` can write directly into GPU-visible
memory.

## 3. `Process` cannot set process creation flags

`CreateProcessW` is called with exactly one flag:

```swift
DWORD(CREATE_UNICODE_ENVIRONMENT), UnsafeMutableRawPointer(mutating: wszEnvironment),
```

There is no way to add `CREATE_NO_WINDOW`. A console child inherits its
parent's console when there is one and **opens a console window of its own when
there is not**, which is the case for any GUI app launched from Explorer or
from a pty-based terminal. P6 spawns ffmpeg, ffplay, zstd and ffprobe, and
restarts the decoder on every resolution or frame-rate change, so console
windows kept appearing over the player as the user worked.

**Proposed**: a way to influence creation flags. Even a single Windows-only
`Process` property (`createsNoWindow`, defaulting to today's behaviour) would
cover the common case; the general form would be an options set.

**Workaround in P6**: `P6WindowlessProcess` calls `CreateProcessW` directly
with `CREATE_NO_WINDOW`, which also meant reimplementing argument quoting per
`CommandLineToArgvW` rules, handle inheritance, termination and exit codes.

---

Not Foundation, but found alongside and worth reporting to swift-cross-ui:

- `WinUIElementRepresentable`'s default `sizeThatFits` asks the element for its
  desired size, and a `WinUI.Canvas` never measures its children, so any
  representable rooted at a Canvas measures as 0x0 and the layout centres it.
- The Windows file pickers do not return activation to the window that owned
  them, so choosing a file leaves the app behind whatever was underneath it.
  Fixed here in `WinUIBackend.showFileOpenDialog` and friends.
