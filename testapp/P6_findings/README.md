# P6 Windows performance findings

`gpu-modes.csv` is written by `testapp/gpu-matrix.zsh`, one row per GPU mode
per run:

```
zsh testapp/gpu-matrix.zsh <resolution> <target fps> <seconds>
zsh testapp/gpu-matrix.zsh 4k 60 20
```

Columns are `date_tested, mode, resolution, target_fps, measured_fps,
frames_dropped_per_sec, read_avg_ms, present_avg_ms, seconds, ffmpeg_args`.
`ffmpeg_args` is the exact argument list P6 handed to ffmpeg for that run, so a
row can be reproduced without guessing.

`read_avg_ms` is the time to get one frame from the decoder's pipe into mapped
GPU memory; `present_avg_ms` is the copy into the back buffer plus `Present`.
Both come from the `stage timings:` lines P6 logs once a second.

## What the 2026-08-12 rows show

- **The GPU does not matter.** At every resolution and frame rate the five
  modes -- default, `-amd`, `-nvidia`, `-both-gpu` and `-no-gpu` (Microsoft's
  CPU rasteriser) -- land within noise of each other, and presenting costs
  0-6 ms against frame budgets of 16-33 ms. Selecting a GPU is not a lever on
  this workload.
- **The reader is the cost.** `read_avg_ms` tracks the total load almost
  exactly: 8 ms at 1080p30, 21 ms at 1080p60, 58 ms at 4K30, and 380-1020 ms at
  4K60.
- **The decoder is not the cost.** Running the same filter chain standalone
  (`ffmpeg ... -f rawvideo -pix_fmt rgba -y NUL`) produced 4K60 frames at about
  123 fps, roughly 2.1x realtime. ffmpeg can produce far more than P6 consumes.
- That leaves CPU contention as the open question: at 4K60 ffmpeg saturates the
  machine producing frames nothing is waiting for, and the same 33 MB frame that
  takes 58 ms to read at 4K30 takes ten times longer. Pacing the decoder to the
  playback rate (`-re` / `-readrate`) is the next thing to try.

Earlier, before P6 owned its pipe, the read stage cost 100-160 ms per frame at
1080p alone. Foundation's `Pipe` calls `CreatePipe(..., 0)` on Windows, so the
buffer is the system default of a few kilobytes and there is no API to change
it; each `read(upToCount:)` also allocates a `Data` that is appended into a
growing frame-sized buffer and copied a second time into the texture. P6 now
creates its own pipe with an 8 MB buffer and reads with `ReadFile` straight into
the mapped staging texture.
