#!/bin/zsh
# Build the GTK three-way deck: one slide per test app, GtkBackend on Windows,
# under WSL and on macOS, side by side, with WSL in the middle so it sits next
# to each of the other two. Same page as the GTK / macOS deck (build_deck.zsh):
# template-head.html and template-tail.html with their @@TOKENS@@ filled in.
#
#   zsh testapp/test_support/pairs_deck/build_gtk_deck.zsh OUTDIR MAC_TSV
#   zsh testapp/test_support/pairs_deck/build_gtk_deck.zsh --help
#
# Windows and WSL come from capture_gtk.zsh: the newest record per app in
# testapp/output/gtk-pairs-win.csv2 and gtk-pairs-wsl.csv2, each screenshot
# scaled to 900 px high as OUTDIR/img/{win,wsl}-pN.jpg (ffmpeg). The WSL records
# and their screenshots must be copied into this checkout's testapp/output first;
# the WSL checkout is a separate copy. macOS is not re-captured: MAC_TSV lists,
# per app, the image already published in the GTK / macOS deck and its caption
# (app, image path there, caption), and the publish copies those images as
# img/mac-pN.jpg. The chip counts the sides that have a screenshot.
#
# 產生 GTK 三方對照簡報：每支測試 app 一頁,GtkBackend 在 Windows、WSL 與 macOS 上並排,WSL 放中間，使它分別
# 緊鄰另外兩者。頁面與 GTK / macOS 簡報(build_deck.zsh)相同：填好 @@TOKENS@@ 的 template-head.html 與
# template-tail.html。Windows 與 WSL 來自 capture_gtk.zsh:testapp/output/gtk-pairs-win.csv2 與 gtk-pairs-wsl.csv2
# 中每支 app 最新的一筆，擷圖縮成 900 px 高的 OUTDIR/img/{win,wsl}-pN.jpg(ffmpeg)。WSL 的紀錄與擷圖要先複製到
# 本 checkout 的 testapp/output;WSL 的 checkout 是另一份拷貝。macOS 不重拍:MAC_TSV 逐 app 列出 GTK / macOS
# 簡報裡已發布的影像與其說明(app、該處影像路徑、說明),發布時把它們複製成 img/mac-pN.jpg。標籤是有擷圖的邊數。

emulate -L zsh
setopt pipe_fail
script_path=${0:A}
here=${script_path:h}
repo=${here:h:h:h}
if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    sed -n '2,17p' $script_path | sed 's/^# \{0,1\}//'
    exit 0
fi
out=${1:?usage: build_gtk_deck.zsh OUTDIR MAC_TSV}
mac_tsv=${2:?usage: build_gtk_deck.zsh OUTDIR MAC_TSV}
mkdir -p $out/img

# Newest record per app and side: later records win. The fields hold no commas.
# 每支 app 每一邊最新的紀錄：較晚的紀錄勝出。欄位內沒有逗號。
typeset -A image exitcode
for side in win wsl; do
    file=$repo/testapp/output/gtk-pairs-${side}.csv2
    [[ -s $file ]] || continue
    while IFS=, read -r utc app rc img; do
        image[$app/$side]=${img//\"/}
        exitcode[$app/$side]=$rc
    done < <(csv2 -r -i $file)
done

# The built app sizes for the captions. Windows: Pn-gtk4.exe here. WSL: the Linux
# binaries in the WSL checkout, a separate copy, read with stat through wsl.exe.
# 說明用的 app 建置大小。Windows:此處的 Pn-gtk4.exe。WSL:WSL checkout(另一份拷貝)裡的 Linux 執行檔，經 wsl.exe 以 stat 讀取。
typeset -A wsl_bytes wsl_mtime
while read -r name bytes mtime; do
    wsl_bytes[$name]=$bytes
    wsl_mtime[$name]=$mtime
done < <(MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu --cd /home/lowei/proj/swift-cross-ui/testapp/output -- sh -c 'stat -c "%n %s %Y" P* 2>/dev/null')

typeset -A mac_src mac_caption
while IFS=$'\t' read -r app src caption; do
    mac_src[$app]=$src
    mac_caption[$app]=$caption
done < $mac_tsv

apps=(${(u)${(k)image%%/*}} ${(k)mac_src})
apps=(${(u)apps})
# Numeric order: P2 before P10, P15 before P15-DARK.
# 數字順序:P2 在 P10 之前,P15 在 P15-DARK 之前。
apps=(${(f)"$(printf '%s\n' $apps | sort -t P -k2,2n -k2,2)"})

# "app 13.7 MB, built 2026-10-21" from a byte count and an mtime, or n/a without them.
# 由位元組數與 mtime 得出「app 13.7 MB, built 2026-10-21」;沒有就是 n/a。
app_size() {
    if [[ -z ${1:-} ]]; then
        printf '%s' 'app size n/a: no build left'
        return
    fi
    printf 'app %.1f MB, built %s' $(( $1 / 1048576.0 )) "$(date -d @$2 +%F)"
}

figure() {
    local app=$1 side=$2 label=$3 name=$4
    local img=${image[$app/$side]} rc=${exitcode[$app/$side]}
    if [[ -z $img || ! -f $repo/$img ]]; then
        printf '%s\n' "<figure><figcaption><b>$label</b> $name · no screenshot (exit ${rc:-not run})</figcaption></figure>"
        return
    fi
    local jpg=$out/img/$side-${(L)app}.jpg
    ffmpeg -y -loglevel error -i $repo/$img -vf scale=-2:900 -q:v 4 $jpg
    local size=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x $repo/$img)
    local stamp=${${img:t:r}##*-final-}
    local appsize
    if [[ $side == win ]]; then
        local exe=$repo/testapp/output/$app-gtk4.exe
        if [[ -f $exe ]]; then appsize=$(app_size $(stat -c '%s %Y' $exe)); else appsize=$(app_size); fi
    else
        appsize=$(app_size ${wsl_bytes[$app]:-} ${wsl_mtime[$app]:-})
    fi
    printf '%s\n' "<figure><img data-src=\"img/$side-${(L)app}.jpg?v=$stamp\" alt=\"$app on $label\"><figcaption><b>$label</b> $name · ${size/x/ × } px · $stamp · $appsize</figcaption></figure>"
}

mac_figure() {
    local app=$1
    if [[ -z ${mac_src[$app]:-} ]]; then
        printf '%s\n' '<figure><figcaption><b>macOS</b> GtkBackend · not in the GTK / macOS deck</figcaption></figure>'
        return
    fi
    printf '%s\n' "<figure><img data-src=\"img/mac-${(L)app}.jpg?v=${mac_src[$app]##*\?v=}\" alt=\"$app on macOS\"><figcaption><b>macOS</b> ${mac_caption[$app]}</figcaption></figure>"
}

{
    head=$(<$here/template-head.html)
    head=${head//@@TITLE@@/GTK Three Ways}
    head=${head//@@BENCH@@/#3a3358}
    head=${head//@@BENCH_DARK@@/#1f1b33}
    head=${head//@@MUTED@@/#d8d3ee}
    head=${head//@@RULE@@/#7d74ad}
    head=${head//@@IMG_SIZE@@/width: 440px; height: 900px; object-fit: contain; object-position: top;}
    head=${head//@@TILE_RATIO@@/440 \/ 900}
    printf '%s\n' $head
    printf '%s\n' '<section class="cover">'
    printf '%s\n' '  <h1>GTK on Windows, WSL and macOS</h1>'
    printf '%s\n' "  <p>$#apps test apps with GtkBackend, each captured at rest: Windows GTK (left) and WSLg (middle) on this PC, $(date +%Y-%m-%d), and GTK on the Mac (right) from the GTK / macOS deck, scaled to the same height.</p>"
    printf '%s\n' '  <p><kbd>→</kbd> <kbd>←</kbd> step through the apps. <b>Grid</b> at the bottom left lists every app. Type a number in the box beside it to jump there.</p>'
    printf '%s\n' '  <div class="legend"><span class="chip aligned">3 of 3</span> every side captured <span class="chip noted">2 of 3</span> one side missing; its caption says why</div>'
    printf '%s\n' '</section>'
    for app in $apps; do
        body=$(
            figure $app win 'Windows' 'GtkBackend on Windows'
            figure $app wsl 'WSL' 'GtkBackend under WSLg'
            mac_figure $app
        )
        count=$(printf '%s\n' $body | grep -c '<img ')
        if (( count == 3 )); then c=aligned; else c=noted; fi
        printf '%s\n' "<section data-app=\"$app\">"
        printf '%s\n' "<header><h2>$app</h2><span class=\"chip $c\">$count of 3</span><p class=\"note\"></p></header>"
        printf '%s\n' '<div class="pair">'
        printf '%s\n' $body
        printf '%s\n' '</div></section>'
    done
    tail=$(<$here/template-tail.html)
    tail=${tail//@@SLIDE_W@@/1460}
    tail=${tail//@@SLIDE_H@@/1060}
    tail=${tail//@@TILE_SIDE@@/wsl}
    printf '%s\n' $tail
} > $out/index.html
printf '%s\n' "$out/index.html: $#apps apps"
