# d3d12: no persistent cache for shader variants or PSOs -- every process pays the full compile again on WSLg

<!--
Draft for https://gitlab.freedesktop.org/mesa/mesa/-/issues, written 2026-10-23
from measurements in the swift-cross-ui repository (queue.md row 27,
matrix_coverage/results.csv2: wsl, gtk4, P96). Not filed yet. Paste everything
below this comment as the issue body; the title is the heading above.
-->

## System information

| | |
|---|---|
| OS | Ubuntu 26.04 LTS in WSL2, Windows 10.0.26300.9711 |
| Kernel | 6.18.54.1-microsoft-standard-WSL2 |
| GPU | NVIDIA GeForce RTX 4060 Laptop GPU, Windows driver 617.42 |
| Mesa | 26.0.8-1ubuntu0.3 (`libgl1-mesa-dri`, `mesa-libgallium`) |
| OpenGL | `D3D12 (NVIDIA GeForce RTX 4060 Laptop GPU)`, 4.6 Core Profile |
| Environment | `GALLIUM_DRIVER=d3d12 MESA_D3D12_DEFAULT_ADAPTER_NAME=NVIDIA` |
| Client | GTK 4.22.4 (`GskGLRenderer`, X11 via `GDK_BACKEND=x11`) |

## Describe the issue

On WSLg, a GTK 4 application stalls on the first frame that draws a
combination of state it has not drawn before in that process. In our test app
(a GTK 4 window with 33 stroked curves, labels and small moving rectangles) the
first frame in which the rectangles move waits **870 ms** between GTK's frame
clock `layout` and `paint` phases, in every run. Every later frame takes
16.9 ms (59 fps). The stall was the same length in every run we made of the
same binary (866-985 ms without any mitigation): nothing from one process's
compiles survives into the next.

Reading `src/gallium/drivers/d3d12` at tag `mesa-26.0.8`, the d3d12 driver
keeps no cache across processes at either level where the work happens:

1. **Shader variants are in memory only.** `select_shader_variant`
   (`d3d12_compiler.cpp`) builds a key with `d3d12_fill_shader_key`, searches
   the selector's in-memory list (`sel->first`), and on a miss clones the NIR,
   runs the lowering passes and `compile_nir`, ending in `nir_to_dxil`. The
   result is only linked into that list.
2. **No disk shader cache hook.** `d3d12_screen.cpp` does not implement
   `get_disk_shader_cache`, so Mesa's shader cache is not used for this driver.
   (`~/.cache/mesa_shader_cache` on this machine holds 373 entries, the newest
   written three days before these measurements; none were added by the d3d12
   runs measured here. Where the older entries came from we have not
   established.)
3. **Pipeline state objects are created with no cached blob.**
   `d3d12_pipeline_state.cpp` sets `CachedPSO.pCachedBlob = NULL` and
   `CachedPSO.CachedBlobSizeInBytes = 0` for every graphics PSO (lines 404-406
   and 549-550), so the native driver compiles each PSO from DXIL again in each
   process.
4. **PSOs are cached per context.** The PSO cache lives on `d3d12_context`. An
   application with one GL context per window (GTK) recompiles the same PSOs
   for each window's context even within one process.

## Measurements

Profiled with `perf record -F 1000 --call-graph dwarf,32768` (Ubuntu's
`linux-perf` 7.0.14; the perf shipped under
`/usr/lib/linux-tools/*-microsoft-standard-WSL2` resolves no symbols):

| | whole 4 s run | main thread, during the stall |
|---|---|---|
| `libgallium-26.0.8` (Mesa d3d12) | 29% | 51% |
| `libnvwgf2umx.so` (NVIDIA D3D user-mode driver) | 14% | 21% |
| `libnvidia-gpucomp.so` (NVIDIA shader compiler) | 17% | 5% |

Much of the stall is also off the CPU: the main thread has stretches with no
samples while it waits.

With `LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe` the same frame waits
443 ms -- llvmpipe's own JIT, shown only to separate the CPU-side share from the
GPU path; it is not the subject of this report.

### What an application can do today, and its limit

We added a warm-up in the application: before the window's content exists, a
throwaway window is realized and one offscreen frame of common GSK nodes (color,
rounded clip, linear gradient, border, shadow, text, a filled and a stroked
`GskPath`, a transformed fill) is rendered with `gsk_renderer_render_texture`.
Interleaved, two rounds each:

| | stall | first 3 s |
|---|---|---|
| no warm-up | 870 ms | 41.0 / 41.7 fps |
| warm-up in a throwaway window | about 560 ms | 48.3 / 49.0 fps |
| warm-up in the application's own window | 451 / 484 ms (against 570 / 611 in the same runs) | -- |

The last row shows the per-context PSO cache (point 4): warming the window that
will draw saves about another 120 ms, but realizing an application's window
that early has side effects in GTK, so it is not a general answer. What remains
is draw state the warm-up does not happen to reach, which an application cannot
enumerate.

## Steps to reproduce

A standalone GTK 4 program, `first-frame-stall.c` (attached, about 100 lines,
public GTK API only): a window with a label and a button; after 0.5 s it adds a
rounded, shadowed label under a rotating `GtkFixed` child transform and moves it
every frame. It prints every frame longer than 30 ms (frame clock
`before-paint` to `after-paint`) and quits after 3 s.

```sh
cc first-frame-stall.c -o first-frame-stall $(pkg-config --cflags --libs gtk4)
GALLIUM_DRIVER=d3d12 MESA_D3D12_DEFAULT_ADAPTER_NAME=NVIDIA GDK_BACKEND=x11 ./first-frame-stall
LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe GDK_BACKEND=x11 ./first-frame-stall
```

Measured 2026-10-23 on the system above, three d3d12 runs in a row and one
llvmpipe run:

| run | first frame with the new state | frames over 30 ms |
|---|---|---|
| d3d12 1 | 63.3 ms | 2 |
| d3d12 2 | 63.8 ms | 2 |
| d3d12 3 | 76.2 ms | 2 |
| llvmpipe | under 30 ms | 1 |

The first frame with the new state is slow in every process on d3d12 and not on
llvmpipe. The other slow frame, at about 1.4 s, appears on llvmpipe too (160 ms)
and is not part of this report. This program uses few node types, so its stall
is short; our application, which draws more kinds of nodes in its first moving
frame, waits 870 ms the same way.

## Expected behaviour

A second run of the same binary should reuse the compiled variants and PSOs, as
the GL drivers with a disk cache do -- either through `get_disk_shader_cache`
for the DXIL variants, or by storing the blob from
`ID3D12PipelineState::GetCachedBlob` and passing it back through `CachedPSO`
(or an `ID3D12PipelineLibrary`) for the PSOs.

## Possible directions

- Implement `get_disk_shader_cache` in `d3d12_screen.cpp`, keyed on the variant
  key and the adapter, so `nir_to_dxil` results survive.
- Persist PSOs: after creation, `GetCachedBlob()` into the disk cache keyed on
  the PSO description; on the next run pass it in `CachedPSO`.
  `ID3D12PipelineLibrary` is the other route. A blob can be rejected after a
  driver update (`D3D12_ERROR_DRIVER_VERSION_MISMATCH`), so a fallback to a
  plain create is needed.
- Share the PSO cache across contexts of a screen, which would also help
  applications with a GL context per window within a single process.

We are happy to test a branch.

## Related issues and current main

Searched 2026-10-23: the 147 issues labelled `d3d12` (open and closed), the
issue search for "d3d12 shader cache", "d3d12 PSO cache", "CachedPSO" and
"get_disk_shader_cache", and merge requests labelled `d3d12` matching "cache",
"pso" and "pipeline". None asks for or adds a persistent cache in the d3d12
gallium driver. Related:

- #7681 *Add shader cache support on windows and macos* (open) -- the disk
  cache itself on those platforms. On WSL/Linux the disk cache works; the d3d12
  driver does not use it.
- !21610 *d3d12: Cache varying info to reduce compare/copy cost* (merged) -- an
  in-memory cache, not across processes.

`main` at 01237de5 (2026-10-23) is unchanged in this respect:
`d3d12_screen.cpp` has no `disk_cache`, `d3d12_pipeline_state.cpp` still sets
`pCachedBlob = NULL` in both places, and nothing calls `GetCachedBlob`.

## Regression

Not known; this does not look like a regression, rather a cache that was never
implemented for d3d12.
