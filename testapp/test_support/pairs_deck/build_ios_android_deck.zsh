#!/bin/zsh
# Build the iOS / Android pairs deck ("iOS and Android Pairs", published 2026-10-12): one slide
# per test app, UIKitBackend on the iPhone simulator on the left and AndroidBackend on the
# Android emulator on the right, both at rest.
#
#   zsh testapp/test_support/pairs_deck/build_ios_android_deck.zsh OUTDIR
#
# Writes OUTDIR/index.html, and OUTDIR/img/{ios,android}-pN.jpg for every side captured by
# capture_mobile.zsh. Publish index.html with those images to the same artifact URL; the
# images already published there are kept by the publish, and the page refers to them.
#
# Two sources, the newer winning per app and side:
# - testapp/output/ios-android-pairs.csv2, written by capture_mobile.zsh. The newest record
#   for an app and platform replaces what was published, a failed run included: its side
#   then shows the exit status, so a recapture that failed is seen rather than hidden.
# - ios-android-slides.csv2 beside this script: what each slide showed when the deck had no
#   generator (2026-11-06) -- the chip, the note, and the published image with its caption.
#   The chip and the note are always read from here; edit this file to change them. An app
#   with no row gets "unrecorded" and no note.
# Every caption ends with the app's size and build date, measured now from the file
# test.zsh launches: output/Pn-ios.app/Pn and .androidApk/Pn.apk.
# The zh-TW line under a note comes from ios-android-notes.zh-TW.json (deck_zh.zsh). The last
# slide lists the sides missing a screenshot, and the testapp/ sources never captured.
#
# 產生 iOS / Android 對照簡報(「iOS and Android Pairs」,2026-10-12 發布):每支測試 app 一頁，左邊是 iPhone
# 模擬器上的 UIKitBackend,右邊是 Android 模擬器上的 AndroidBackend,都是靜止時的畫面。
# 寫出 OUTDIR/index.html,以及 capture_mobile.zsh 擷取過的每一邊的 OUTDIR/img/{ios,android}-pN.jpg。把 index.html
# 連同這些影像發布到同一個 artifact 網址；那裡已發布的影像會被保留，頁面直接引用它們。
# 兩個來源，每個 app 的每一邊取較新的那個:
# - testapp/output/ios-android-pairs.csv2,由 capture_mobile.zsh 寫入。某 app 某平台最新的一筆取代已發布的那張，
#   失敗的執行也一樣：那一邊會顯示結束狀態，重新擷取失敗時看得到，不會被藏起來。
# - 本腳本旁的 ios-android-slides.csv2:簡報還沒有產生器時(2026-11-06)每頁顯示的內容——標籤、說明，以及已發布
#   的影像與其說明。標籤與說明一律從這裡讀；要改就改這個檔。沒有列的 app 標成 unrecorded、沒有說明。
# 每個說明的最後是 app 的大小與建置日期，在此時從 test.zsh 啟動的檔案量得:output/Pn-ios.app/Pn 與 .androidApk/Pn.apk。
# 說明下方的 zh-TW 一行來自 ios-android-notes.zh-TW.json(deck_zh.zsh)。最後一頁列出缺少截圖的那些邊，以及 testapp/
# 有原始檔卻從未擷取的 app。

emulate -L zsh
setopt pipe_fail extended_glob
here=${0:A:h}
repo=${here:h:h:h}
source $here/deck_zh.zsh
todo_deck=ios
out=${1:?usage: build_ios_android_deck.zsh OUTDIR}
mkdir -p $out/img
slides=$here/ios-android-slides.csv2
pairs=$repo/testapp/output/ios-android-pairs.csv2
zh_load $here/ios-android-notes.zh-TW.json

# Screenshot pixels per point on the iPhone simulator, and the Android AVD's density
# (swift-cross-ui-api36: 1080 px wide, 2.625, so 411 dp).
# iPhone 模擬器截圖每 point 的像素數，以及 Android AVD 的密度(swift-cross-ui-api36:寬 1080 px、2.625,即 411 dp)。
ios_scale=3
android_density=2.625

# As the published page escaped its notes: & < > " and '.
# 與已發布頁面跳脫說明的方式相同:& < > " 與 '。
html_escape() {
    local s=$1
    s=${s//&/&amp;}; s=${s//</&lt;}; s=${s//>/&gt;}; s=${s//\"/&quot;}; s=${s//\'/&#x27;}
    print -r -- $s
}

# Fields are joined with US (0x1f), not tab: tab is whitespace to `read`, which would drop an
# empty note and shift every field after it.
# 欄位以 US(0x1f)連接而不是 tab:對 `read` 而言 tab 是空白，空的說明會被吞掉，其後每一欄都會錯位。
typeset -A chip note kept_img kept_cap image exitcode
typeset -a listed
while IFS=$'\x1f' read -r app c n ii ic ai ac; do
    listed+=($app)
    chip[$app]=$c; note[$app]=$n
    kept_img[$app/iOS]=$ii; kept_cap[$app/iOS]=$ic
    kept_img[$app/Android]=$ai; kept_cap[$app/Android]=$ac
done < <(csv2 -r --json -i $slides | jq -r 'select(.fields) | .fields | [.app, .chip, .note, .ios_image, .ios_caption, .android_image, .android_caption] | join("\u001f")')

# Newest record per app and platform: later records win.
# 每個 app 與平台取最新一筆：較後面的紀錄優先。
if [[ -f $pairs ]]; then
    while IFS=$'\x1f' read -r app platform rc img; do
        case $platform in
            ios) side=iOS ;;
            android) side=Android ;;
            *) continue ;;
        esac
        listed+=($app)
        image[$app/$side]=$img
        exitcode[$app/$side]=$rc
    done < <(csv2 -r --json -i $pairs | jq -r 'select(.fields) | .fields | [.app, .platform, .exit, .image] | join("\u001f")')
fi

# Numeric order: P2 before P10, P15 before P15-DARK.
# 依數字排序:P2 在 P10 之前,P15 在 P15-DARK 之前。
apps=(${(f)"$(print -rl -- ${(u)listed} | sort -t P -k2,2n -k2,2)"})

# The built app's size and date, for the caption: the file test.zsh launched, which a later
# build may have replaced since the screenshot was taken.
# 說明用的 app 建置大小與日期:test.zsh 啟動的那個檔案；擷圖之後可能已被重新建置取代。
app_size() {
    local bin=$1
    if [[ ! -f $bin ]]; then
        print -rn -- 'app size n/a: no build left'
        return
    fi
    printf 'app %.1f MB, built %s' $(( $(stat -L -f %z $bin) / 1048576.0 )) "$(stat -L -f %Sm -t %F $bin)"
}

stamps=()
figure() {
    local app=$1 side=$2 backend bin prefix src middle img rc
    if [[ $side == iOS ]]; then
        backend=UIKitBackend; prefix=ios; bin=$repo/testapp/output/$app-ios.app/$app
    else
        backend=AndroidBackend; prefix=android; bin=$repo/testapp/.androidApk/$app.apk
    fi
    if (( ${+exitcode[$app/$side]} )); then
        img=${image[$app/$side]}; rc=${exitcode[$app/$side]}
        if [[ -z $img || ! -f $repo/$img ]]; then
            print -r -- "<figure><figcaption><b>$side</b> $backend · no screenshot (exit $rc)</figcaption></figure>"
            return
        fi
        local jpg=$out/img/$prefix-${(L)app}.jpg
        sips -s format jpeg -s formatOptions 80 --resampleHeight 1100 $repo/$img --out $jpg >/dev/null || return 1
        local w=$(sips -g pixelWidth $repo/$img | awk '/pixelWidth/ {print $2}')
        local h=$(sips -g pixelHeight $repo/$img | awk '/pixelHeight/ {print $2}')
        local stamp=${${img:t:r}##*-final-}
        if [[ $side == iOS ]]; then
            middle="$((w / ios_scale)) × $((h / ios_scale)) pt · $stamp"
        else
            middle="$(printf '%.0f' $(( w / android_density ))) dp wide · $stamp"
        fi
        src="img/$prefix-${(L)app}.jpg?v=$stamp"
    else
        src=${kept_img[$app/$side]:-}
        middle=${kept_cap[$app/$side]:-}
        if [[ -z $src ]]; then
            print -r -- "<figure><figcaption><b>$side</b> $backend · ${middle:-not captured}</figcaption></figure>"
            return
        fi
    fi
    stamps+=(${src##*v=})
    print -r -- "<figure><img data-src=\"$src\" alt=\"$app on $side\"><figcaption><b>$side</b> $backend · $middle · $(app_size $bin)</figcaption></figure>"
}

{
    head=$(<$here/template-head.html)
    head=${head//@@TITLE@@/iOS and Android Pairs}
    head=${head//@@BENCH@@/#5b3a9e}
    head=${head//@@BENCH_DARK@@/#2c1a55}
    head=${head//@@MUTED@@/#ddd3f3}
    head=${head//@@RULE@@/#8a70c4}
    head=${head//@@IMG_SIZE@@/height: 1040px; width: auto;}
    head=${head//@@TILE_RATIO@@/440 \/ 956}
    print -r -- $head
    slides_html=$(
        for app in $apps; do
            c=${chip[$app]:-unrecorded}
            print -r -- "<section data-app=\"$app\">"
            print -r -- "<header><h2>$app</h2><span class=\"chip $c\">$c</span><p class=\"note\">$(html_escape "${note[$app]:-}")</p></header>"
            print -r -- '<div class="pair">'
            body=$(
                figure $app iOS
                figure $app Android
            )
            print -r -- $body
            todo_collect $app "$body"
            print -r -- '</div>'
            zh_line $app "${note[$app]:-}" '中文說明'
            print -r -- '</section>'
            # The capture dates on this slide, for the cover. / 本頁的擷取日期，給封面用。
            print -r -- $body | grep -o 'v=[0-9]\{8\}' | sed 's/v=/@@DATE /'
        done
        # Apps with a source in testapp/ and no slide at all.
        # testapp/ 有原始檔卻完全沒有頁面的 app。
        srcs=($repo/testapp/P*.swift(N))
        for src in ${(f)"$(print -rl -- ${${srcs:t}%.swift} | sort -t P -k2,2n -k2,2)"}; do
            (( ${apps[(Ie)$src]} )) || todo_uncaptured $src 'iOS and Android'
        done
        todo_section
        # Inside the subshell: the zh and to-do lists were filled here. / 在子 shell 之內：zh 與待辦清單是在這裡填的。
        zh_report
    )
    dates=(${(u)${(on)${(M)${(f)slides_html}:#@@DATE *}#@@DATE }})
    dates=(${dates/(#b)([0-9][0-9][0-9][0-9])([0-9][0-9])([0-9][0-9])/$match[1]-$match[2]-$match[3]})
    print -r -- '<section class="cover">'
    print -r -- '  <h1>iOS and Android, pair by pair</h1>'
    print -r -- "  <p>$#apps test apps, each captured at rest on the iPhone simulator (UIKitBackend) and the Android emulator (AndroidBackend), scaled to the same height. Captured on ${(j:, :)dates}; every caption gives its own capture time, and the size and build date of the app it shows.</p>"
    print -r -- "  <p class=\"zh\" lang=\"zh-Hant-TW\">共 $#apps 支測試 app,每支都在 iPhone 模擬器(UIKitBackend)與 Android 模擬器(AndroidBackend)上靜止時擷取，縮放到相同高度。擷取日期:${(j:、:)dates};每張截圖的說明列出它自己的擷取時間，以及所示 app 的大小與建置日期。每頁截圖下方附中文說明；最後一頁列出缺少的截圖。</p>"
    print -r -- '  <p><kbd>→</kbd> <kbd>←</kbd> step through the apps. <b>Grid</b> at the bottom left lists every app. Type a number in the box beside it to jump there. <b>−</b> <b>100%</b> <b>+</b> zoom the page; hold the mouse button or a finger on the captures until the pointer becomes a hand, then drag to move around.</p>'
    print -r -- '  <div class="legend"><span class="chip aligned">aligned</span> matches <span class="chip noted">noted</span> a recorded difference <span class="chip unrecorded">unrecorded</span> no comparison row yet</div>'
    print -r -- '</section>'
    print -r -- ${(F)${(f)slides_html}:#@@DATE *}
    tail=$(<$here/template-tail.html)
    tail=${tail//@@SLIDE_W@@/1100}
    tail=${tail//@@SLIDE_H@@/1320}
    tail=${tail//@@TILE_SIDE@@/ios}
    print -r -- $tail
} > $out/index.html
print -r -- "$out/index.html: $#apps apps"
