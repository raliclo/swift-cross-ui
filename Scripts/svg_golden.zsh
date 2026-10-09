#!/usr/bin/env zsh
# Regenerates the reference PNGs the SVG golden tests compare against.
#
#   zsh Scripts/svg_golden.zsh            every <name>.svg in the fixture folder
#   zsh Scripts/svg_golden.zsh --kicad    first re-export the three KiCad samples
#                                         from SoftPCB (needs KiCad and the
#                                         SoftPCB checkout beside this one)
#
# macOS only: the reference renderer is NSImage (CoreSVG), via
# Scripts/svg_reference_png.swift. Every reference is 640 x 400, the size
# SVGTests rasterises at. Look at the PNGs before committing them -- a
# reference is only useful if it is right, and CoreSVG has known gaps (listed
# in svg_reference_png.swift).
#
# 重新產生 SVG 黃金測試所比對的參考 PNG。僅限 macOS:參考算繪器是 NSImage(CoreSVG),經由
# Scripts/svg_reference_png.swift。每張參考圖都是 640 x 400,即 SVGTests 點陣化的尺寸。提交前
# 先看過這些 PNG——參考圖只有在正確時才有用，而 CoreSVG 有已知的缺口(列於
# svg_reference_png.swift)。

set -euo pipefail

script_dir="${0:A:h}"
repo="${script_dir:h}"
fixtures="$repo/Tests/SwiftCrossUITests/SVGFixtures"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    sed -n '2,18p' "${0:A}" | sed 's/^# \{0,1\}//'
    exit 0
fi

if [ "$(uname -s)" != "Darwin" ]; then
    printf "%s\n" "svg_golden.zsh: the reference renderer is NSImage; run it on macOS." >&2
    exit 1
fi

if [ "${1:-}" = "--kicad" ]; then
    kicad_cli="${KICAD_CLI:-/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli}"
    boards="${SOFTPCB_DIR:-$repo/../SoftPCB}/kicad/variants"
    for board in "$boards"/softpcb_{microstrip,spiral,meander}.kicad_pcb; do
        name="${board:t:r}"
        "$kicad_cli" pcb export svg --layers F.Cu,B.Cu,F.SilkS,Edge.Cuts --mode-single \
            --page-size-mode 2 --exclude-drawing-sheet -o "$fixtures/$name.svg" "$board"
    done
fi

binary="$(mktemp -d)/svg_reference_png"
swiftc -O "$script_dir/svg_reference_png.swift" -o "$binary"
for svg in "$fixtures"/*.svg; do
    # Fixtures that are not meant to have a reference say so in their name.
    # 不打算有參考圖的 fixture 在檔名中註明。
    case "${svg:t}" in unsupported*) continue ;; esac
    "$binary" "$svg" "${svg:r}.reference.png" 640 400
    printf "%s\n" "${svg:t} -> ${svg:t:r}.reference.png"
done
