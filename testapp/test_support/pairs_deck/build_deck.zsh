#!/bin/zsh
# Build the GTK / macOS pairs deck: one slide per test app, AppKitBackend on the
# left and GtkBackend on the right, both captured at rest on this Mac by
# capture_macos.zsh. The same page as the iOS / Android deck published on
# 2026-10-12 (reveal.js, the Grid index, the number box), from its own page:
# template-head.html and template-tail.html are that page with the parts that
# differ between the decks turned into @@TOKENS@@.
#
#   zsh testapp/test_support/pairs_deck/build_deck.zsh OUTDIR
#
# Writes OUTDIR/index.html and OUTDIR/img/{macos,gtk}-pN.jpg. Publish OUTDIR.
#
# The chip on each slide comes from results.csv2, as the iOS / Android chips
# do: the newest mac,gtk4 row for that app whose note starts with
# "GTK/macOS comparison:" -- "aligned" or "noted" after the colon, and the rest
# of the note under the app id. No such row is "unrecorded": nobody has put
# the two side by side and said whether they match. A side whose run left no
# screenshot shows the exit status instead of an image.
#
# 產生 GTK / macOS 對照簡報：每支測試 app 一頁，左邊 AppKitBackend、右邊 GtkBackend,兩者都由 capture_macos.zsh
# 在這台 Mac 上靜止時擷取。頁面與 2026-10-12 發布的 iOS / Android 簡報相同(reveal.js、Grid 索引、號碼框),
# 取自該頁本身:template-head.html 與 template-tail.html 就是那一頁，只把兩份簡報不同的部分換成 @@TOKENS@@。
# 每頁的標籤與 iOS / Android 的一樣來自 results.csv2:該 app 最新一筆 mac,gtk4、備註以「GTK/macOS comparison:」開頭
# 的紀錄——冒號後是 aligned 或 noted,其餘備註顯示在 app 編號旁。沒有這種紀錄就是 unrecorded:還沒有人把兩者
# 並排看過並說出是否一致。某一邊的執行沒有留下擷圖時，顯示結束狀態而不是影像。

emulate -L zsh
setopt pipe_fail
here=${0:A:h}
repo=${here:h:h:h}
out=${1:?usage: build_deck.zsh OUTDIR}
mkdir -p $out/img
pairs=$repo/testapp/output/macos-pairs.csv2
results=$repo/matrix_coverage/results.csv2

html_escape() {
    local s=$1
    s=${s//&/&amp;}; s=${s//</&lt;}; s=${s//>/&gt;}; s=${s//\"/&quot;}
    print -r -- $s
}

# Newest record per app and backend: later records win.
typeset -A image exitcode
while IFS=$'\t' read -r app backend rc img; do
    image[$app/$backend]=$img
    exitcode[$app/$backend]=$rc
done < <(csv2 -r --json -i $pairs | jq -r 'select(.fields) | .fields | [.app, .backend, .exit, .image] | @tsv')

typeset -A chip note
while IFS=$'\t' read -r app text; do
    rest=${text#GTK/macOS comparison:}
    rest=${rest## }
    case $rest in
        aligned*) chip[$app]=aligned ;;
        noted*) chip[$app]=noted ;;
        *) continue ;;
    esac
    note[$app]=$rest
done < <(csv2 -r --json -i $results | jq -r 'select(.fields) | .fields | select(.platform == "mac" and .backend == "gtk4" and (.note | startswith("GTK/macOS comparison:"))) | [.app, .note] | @tsv')

apps=(${(on)${(u)${(k)image%%/*}}})
# Numeric order: P2 before P10, P15 before P15-DARK.
apps=(${(f)"$(print -rl -- $apps | sort -t P -k2,2n -k2,2)"})

figure() {
    local app=$1 backend=$2 side=$3 label=$4 name=$5
    local img=${image[$app/$backend]} rc=${exitcode[$app/$backend]}
    if [[ -z $img || ! -f $repo/$img ]]; then
        print -r -- "<figure><figcaption><b>$label</b> $name · no screenshot (exit ${rc:-?})</figcaption></figure>"
        return
    fi
    local jpg=$out/img/$side-${(L)app}.jpg
    sips -s format jpeg -s formatOptions 80 --resampleHeight 900 $repo/$img --out $jpg >/dev/null
    local w=$(sips -g pixelWidth $repo/$img | awk '/pixelWidth/ {print $2}')
    local h=$(sips -g pixelHeight $repo/$img | awk '/pixelHeight/ {print $2}')
    local stamp=${${img:t:r}##*-final-}
    print -r -- "<figure><img data-src=\"img/$side-${(L)app}.jpg?v=$stamp\" alt=\"$app on $label\"><figcaption><b>$label</b> $name · $((w / 2)) × $((h / 2)) pt · $stamp</figcaption></figure>"
}

{
    head=$(<$here/template-head.html)
    head=${head//@@TITLE@@/GTK and macOS Pairs}
    head=${head//@@BENCH@@/#1d5c63}
    head=${head//@@BENCH_DARK@@/#0f3338}
    head=${head//@@MUTED@@/#cfe6e3}
    head=${head//@@RULE@@/#5f9a9f}
    head=${head//@@IMG_SIZE@@/width: 520px; height: 900px; object-fit: contain; object-position: top;}
    head=${head//@@TILE_RATIO@@/520 \/ 900}
    print -r -- $head
    print -r -- '<section class="cover">'
    print -r -- '  <h1>GTK and macOS, pair by pair</h1>'
    print -r -- "  <p>$#apps test apps, each captured at rest on this Mac with AppKitBackend (left) and GtkBackend (right, TEST_BACKEND=gtk4), $(date +%Y-%m-%d), scaled to the same height.</p>"
    print -r -- '  <p><kbd>→</kbd> <kbd>←</kbd> step through the apps. <b>Grid</b> at the bottom left lists every app. Type a number in the box beside it to jump there.</p>'
    print -r -- '  <div class="legend"><span class="chip aligned">aligned</span> matches <span class="chip noted">noted</span> a recorded difference <span class="chip unrecorded">unrecorded</span> no comparison row yet</div>'
    print -r -- '</section>'
    for app in $apps; do
        c=${chip[$app]:-unrecorded}
        print -r -- "<section data-app=\"$app\">"
        print -r -- "<header><h2>$app</h2><span class=\"chip $c\">$c</span><p class=\"note\">$(html_escape "${note[$app]}")</p></header>"
        print -r -- '<div class="pair">'
        figure $app appkit macos macOS AppKitBackend
        figure $app gtk4 gtk GTK 'GtkBackend on macOS'
        print -r -- '</div></section>'
    done
    tail=$(<$here/template-tail.html)
    tail=${tail//@@SLIDE_W@@/1180}
    tail=${tail//@@SLIDE_H@@/1060}
    tail=${tail//@@TILE_SIDE@@/macos}
    print -r -- $tail
} > $out/index.html
print -r -- "$out/index.html: $#apps apps"
