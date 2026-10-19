#!/usr/bin/env python3
# gtk_frame_trace.py -- summarises a log written by gtk_frame_trace.dylib.
#
#   python3 -I gtk_frame_trace.py TRACE [FROM_S TO_S]
#
# Prints, for the ticks between FROM_S and TO_S seconds after the first tick:
# the tick count and rate, the tick-to-tick intervals in refresh intervals, how
# many CVDisplayLinkStart calls there were, and for each start how long until
# the display link's first callback (the wait that GTK's macOS backend adds to
# a frame when it has stopped the link after the previous one).
#
# gtk_frame_trace.py——彙整 gtk_frame_trace.dylib 所寫的記錄。印出第一個 tick 之後 FROM_S 到
# TO_S 秒之間的 tick 數與速率、以更新間隔為單位的 tick 間隔分布、CVDisplayLinkStart 的次數，以及
# 每次 start 到 display link 第一次 callback 的時間(GTK 的 macOS backend 在上一幀之後停掉 link
# 時，加到一幀上的等待)。
import sys
from collections import Counter

path = sys.argv[1]
start_s = float(sys.argv[2]) if len(sys.argv) > 2 else 0.0
end_s = float(sys.argv[3]) if len(sys.argv) > 3 else 1e9

events = []
for line in open(path):
    parts = line.split()
    if len(parts) < 2:
        continue
    events.append((parts[0], int(parts[1]), parts[2:]))

# Only the display links that are started and stopped (GDK's); a link that
# runs throughout, such as one the app keeps itself, is left out.
# 只取會被 start 與 stop 的 display link(GDK 的);一直在跑的 link(例如 app 自己保留的)不算。
def link_of(rest):
    return next((f[5:] for f in rest if f.startswith("link=")), None)

gdk_links = {link_of(rest) for kind, _, rest in events if kind == "start"}
events = [e for e in events if e[0] != "cv" or link_of(e[2]) in gdk_links]

ticks = [t for kind, t, _ in events if kind == "tick"]
if not ticks:
    print("no tick")
    sys.exit(1)
origin = ticks[0]
lo, hi = origin + start_s * 1e6, origin + end_s * 1e6
window = [e for e in events if lo <= e[1] < hi]
wticks = [t for kind, t, _ in window if kind == "tick"]
span = (min(hi, window[-1][1]) - lo) / 1e6 if window else 0
print(f"window {start_s:.1f}-{end_s:.1f} s: ticks {len(wticks)}"
      + (f" ({len(wticks) / span:.1f} per s)" if span > 0 else ""))

refresh = 16667
for kind, _, rest in window:
    if kind == "tick":
        for field in rest:
            if field.startswith("ri="):
                refresh = int(field[3:]) or refresh
        break

intervals = Counter()
for a, b in zip(wticks, wticks[1:]):
    intervals[round((b - a) / refresh)] += 1
print("tick intervals in refresh intervals: "
      + ", ".join(f"{k}: {v}" for k, v in sorted(intervals.items())))

starts = 0
latencies = []
pending = None
for kind, t, _ in window:
    if kind == "start":
        starts += 1
        pending = t
    elif kind == "cv" and pending is not None:
        latencies.append(t - pending)
        pending = None
print(f"CVDisplayLinkStart calls {starts}, stops {sum(1 for e in window if e[0] == 'stop')}, "
      f"callbacks {sum(1 for e in window if e[0] == 'cv')}")
if latencies:
    latencies.sort()
    n = len(latencies)
    buckets = Counter(min(int(l / refresh), 4) for l in latencies)
    print(f"start -> first callback: median {latencies[n // 2] / 1000:.1f} ms, "
          f"min {latencies[0] / 1000:.1f}, max {latencies[-1] / 1000:.1f}; in refresh intervals "
          + ", ".join(f"{'>=4' if k == 4 else k}: {v}" for k, v in sorted(buckets.items())))

# Work per frame: tick to the frame clock's after-paint, as logged.
# 每幀的工作量:tick 到 frame clock 的 after-paint。
work = []
last_tick = None
for kind, t, _ in window:
    if kind == "tick":
        last_tick = t
    elif kind == "paint" and last_tick is not None:
        work.append(t - last_tick)
        last_tick = None
if work:
    work.sort()
    print(f"tick -> after-paint (frame work): median {work[len(work) // 2] / 1000:.1f} ms, "
          f"90% {work[int(len(work) * 0.9)] / 1000:.1f} ms, max {work[-1] / 1000:.1f} ms, "
          f"over 16.7 ms: {sum(1 for w in work if w > refresh)} of {len(work)}")

# Tick to the next start (the paint), and callback to next tick.
# 每幀的工作量:tick 到下一次 start(繪製),以及 callback 到下一個 tick。
paint, wake = [], []
last_tick = last_cv = None
for kind, t, _ in window:
    if kind == "tick":
        if last_cv is not None:
            wake.append(t - last_cv)
        last_tick, last_cv = t, None
    elif kind == "start" and last_tick is not None:
        paint.append(t - last_tick)
        last_tick = None
    elif kind == "cv":
        last_cv = t
for name, values in (("tick -> CVDisplayLinkStart", paint), ("callback -> next tick", wake)):
    if values:
        values.sort()
        print(f"{name}: median {values[len(values) // 2] / 1000:.1f} ms, "
              f"90% {values[int(len(values) * 0.9)] / 1000:.1f} ms, max {values[-1] / 1000:.1f} ms")

# For each CVDisplayLinkStart: how long before the next callback slot it was
# made, and whether its first callback came at that slot or one refresh later.
# The slots are the callback times of the whole trace, which keep one phase.
# 每次 CVDisplayLinkStart:它在下一個 callback 時槽之前多久發出，以及第一次 callback 落在該時槽還是晚一個
# 更新週期。時槽取自整份記錄的 callback 時間，它們維持同一個相位。
callbacks = [t for kind, t, _ in events if kind == "cv"]
if callbacks and starts:
    slot = callbacks[len(callbacks) // 2]
    lead = {}
    pending = None
    for kind, t, _ in window:
        if kind == "start":
            pending = t
        elif kind == "cv" and pending is not None:
            before = (slot - pending) % refresh
            hit = lead.setdefault(int(before / 2000), [0, 0])
            hit[(t - pending) > before + refresh / 2] += 1
            pending = None
    print("start made N ms before the next callback slot: first callback at that slot / one later")
    for bucket in sorted(lead):
        print(f"  {bucket * 2:2d}-{bucket * 2 + 2:2d} ms: {lead[bucket][0]:4d} / {lead[bucket][1]:4d}")
