#!/usr/bin/env zsh
# Embeds the SVG test fixtures in testapp/P84.swift, so the app shows the same
# samples and CoreSVG references on every platform without bundling files.
#
#   zsh testapp/test_support/make_P84_fixtures.zsh
#
# Everything in P84.swift after the marker line is replaced; everything before
# it is kept byte for byte. The source is Tests/SwiftCrossUITests/SVGFixtures
# (regenerate the references there first with Scripts/svg_golden.zsh). Written
# through csv2's line mode, per CLAUDE.md.
#
# 把 SVG 測試 fixture 內嵌進 testapp/P84.swift,讓 app 在每個平台上不必打包檔案就能顯示同樣的樣本
# 與 CoreSVG 參考圖。P84.swift 中標記行之後的內容會被取代，之前的內容逐位元組保留。來源是
# Tests/SwiftCrossUITests/SVGFixtures(先在那裡以 Scripts/svg_golden.zsh 重新產生參考圖)。依 CLAUDE.md
# 經由 csv2 的逐行模式寫入。

set -euo pipefail

support_dir="${0:A:h}"
testapp_dir="${support_dir:h}"
repo="${testapp_dir:h}"
fixtures="$repo/Tests/SwiftCrossUITests/SVGFixtures"
app="$testapp_dir/P84.swift"
marker='// MARK: - Generated fixtures (test_support/make_P84_fixtures.zsh) / 產生的 fixture'

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    sed -n '2,15p' "${0:A}" | sed 's/^# \{0,1\}//'
    exit 0
fi

# Lines up to and including the marker. / 到標記行(含)為止的各行。
head_count="$(csv2 --headers 0 -contains "$marker" -i "$app" | sed -n '1s/:.*//p')"
if [ -z "$head_count" ]; then
    printf "%s\n" "make_P84_fixtures.zsh: marker not found in $app" >&2
    exit 1
fi
lines=("${(@f)$(csv2 --headers 0 -mid "1,$head_count" -r -i "$app")}")

base64_lines() {
    base64 -i "$1" | fold -w 100
}

lines+=('enum P84Fixtures {')
lines+=('    struct Fixture {')
lines+=('        let name: String')
lines+=('        /// Base64 of the .svg file. / .svg 檔的 base64。')
lines+=('        let svg: String')
lines+=('        /// Base64 of the CoreSVG reference PNG, 640 x 400. / CoreSVG 參考 PNG 的 base64。')
lines+=('        let png: String?')
lines+=('    }')
lines+=('')
lines+=('    static let samples: [Fixture] = [')
for name in softpcb_microstrip softpcb_spiral softpcb_meander features unsupported; do
    lines+=("        Fixture(name: \"$name\", svg: \"\"\"")
    lines+=("${(@f)$(base64_lines "$fixtures/$name.svg")}")
    if [ -f "$fixtures/$name.reference.png" ]; then
        lines+=('""", png: """')
        lines+=("${(@f)$(base64_lines "$fixtures/$name.reference.png")}")
        lines+=('"""),')
    else
        lines+=('""", png: nil),')
    fi
done
lines+=('    ]')
lines+=('}')

print -rl -- "${lines[@]}" | csv2 -si --headers 0 -r -o "$app"
chmod 644 "$app"
printf '%s\n' "P84.swift: $(wc -l < "$app" | tr -d ' ') lines"
