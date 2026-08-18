#!/usr/bin/env zsh
# P6 under the standard test flow, on both Windows and WSLg.
#
#   zsh testapp/test.zsh P6
#
# P6 已有一個獨立的 testapp/test_P6.zsh，早於本框架，且只在本機啟動——在 Windows
# 上它跑 P6.exe，但沒有任何路徑能啟動 WSL build。本 wrapper 補上這個缺口，讓 P6
# 與 P0-P5、P7-P17 走同一套流程；獨立腳本仍保留給 GPU matrix 那類 P6 專屬的工作。
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P6"
export TEST_TITLE="P6 stream player"
export TEST_LOG_NAME="p6-debug-events.log"

# P6 has no "RENDER COMPLETE" line -- that marker was added to P7 and P8, not to
# P6, which predates it. Rather than add an announcement to P6, wait for the
# evidence each platform already writes when a picture reaches the screen. The
# two are different: Linux takes the CPU path and logs `frame MM:SS WxH` per
# displayed frame, while Windows presents through D3D11 and logs
# `d3d11 surface: first present ok`. Neither line appears on the other side, so
# the marker is an alternation -- `grep -q` here is BRE, hence `\|`.
#
# The obvious `frame ` does not work, in both directions. `session token 1
# ... mode frame frame-drop off` is written before anything is decoded, so it
# matched on line 3 of both logs and the framework reported "rendered after 0s"
# for a window that had not drawn yet. Requiring the `MM:SS` timestamp moves
# the Linux match to the first real frame; on Windows that form never appears
# at all, so `frame ` there would have matched the same false line forever.
# P6 沒有 "RENDER COMPLETE" 那行——該 marker 是為 P7、P8 加的，P6 早於它。與其在 P6
# 裡再加一句宣告，不如等各平台在「畫面已上螢幕」時本來就會寫下的證據。兩者並不相同：
# Linux 走 CPU 路徑，每顯示一格記錄一行 `frame MM:SS WxH`；Windows 經由 D3D11 呈現，
# 記錄的是 `d3d11 surface: first present ok`。兩行都不會出現在對方平台，因此 marker
# 採用 alternation——此處的 `grep -q` 是 BRE，故用 `\|`。
#
# 直覺的 `frame ` 在兩個方向上都不成立。`session token 1 ... mode frame frame-drop
# off` 在任何解碼發生之前就已寫入，因此它會命中兩份日誌的第 3 行，使框架對一個尚未
# 繪製的視窗回報 "rendered after 0s"。加上 `MM:SS` 時間戳的要求後，Linux 的命中點才
# 移到第一張真正的影格；而 Windows 上根本不存在該格式，`frame ` 在那裡只會永遠命中
# 同一行假訊號。
export TEST_MARKER="frame [0-9][0-9]:[0-9][0-9]\|first present ok"

# `-f` with no value falls back to P6's defaultFilePattern (P6.swift:1056), so
# the media file is named in one place rather than duplicated here. P6 searches
# the working directory and the executable's directory, and the framework runs
# it from testapp/output/ on both targets.
#
# That directory is excluded from both git (.git/info/exclude) and rsync
# (rsync_WSL.zsh --exclude='output/'), by design -- it is per-machine. So the
# media file does not travel with the sources and must be placed on each side
# once; WSL had none until it was copied there, which is why P6 had never run
# on Linux at all.
# `-f` 不帶值時會退回 P6 的 defaultFilePattern（P6.swift:1056），因此媒體檔名只在
# 一處出現，不在此重複。P6 會搜尋工作目錄與執行檔所在目錄，而框架在兩個目標上都從
# testapp/output/ 啟動它。
#
# 該目錄同時被 git（.git/info/exclude）與 rsync（rsync_WSL.zsh --exclude='output/'）
# 排除，這是刻意的——它屬於各機器自己。因此媒體檔不會隨原始碼傳送，兩邊都必須各放
# 一次；WSL 端在複製過去之前一直沒有，這正是 P6 從未在 Linux 上跑過的原因。
export TEST_APP_ARGS="-f -autoplay --debug"

# `ffmpeg args:` records the decode pipeline including the pixel format, and
# `frame` carries the timestamp and size, so the summary shows both what was
# asked for and what came back.
# `ffmpeg args:` 記錄解碼管線（含像素格式），`frame` 帶有時間戳與尺寸，因此摘要能
# 同時看到「要求了什麼」與「回來了什麼」。
export TEST_SUMMARY_PATTERN="frame |ffmpeg args:|decoder pipe|window metrics|dropped"

export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
