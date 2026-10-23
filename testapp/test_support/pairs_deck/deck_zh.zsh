# deck_zh.zsh -- the zh-TW line under each note and the to-do page of missing
# screenshots, for build_deck.zsh and build_gtk_deck.zsh (sourced by both).
#
# Translations are data beside the English: {"P10": {"en": "...", "zh": "..."}}.
# "en" is the English the line was translated from. When the deck's English no
# longer matches it, the zh line is left out and named on stderr rather than
# shown beside a note it no longer translates.
#
# deck_zh.zsh —— 每則說明下方的 zh-TW 一行，以及缺少截圖的待辦頁，供 build_deck.zsh 與 build_gtk_deck.zsh 使用(兩者都 source)。
# 翻譯是放在英文旁邊的資料:{"P10": {"en": "...", "zh": "..."}}。"en" 是翻譯所依據的英文。簡報的英文與它不再相符時，
# 不印出那一行 zh,而是在 stderr 列出，免得它出現在一則它已不再翻譯的說明旁邊。

typeset -gA zh_en zh_text
typeset -ga zh_missing zh_stale todo_items todo_known

# Sides with no screenshot by design or out of a machine's scope, not by failure, keyed "DECK APP SIDE"
# (DECK is todo_deck, set by the builder: three or mac). The to-do page lists them
# apart, under "Not expected", so they are neither chased nor forgotten.
# 刻意而非失敗造成的沒有截圖，鍵為「DECK APP SIDE」(DECK 是 builder 設定的 todo_deck:three 或 mac)。
# 待辦頁把它們分開列在「預期沒有」之下，既不會被當成待辦去追，也不會被忘記。
typeset -g todo_deck=
typeset -gA todo_by_design=(
    'three P6 Windows' 'P6 imports the WinUI products, which a GTK build on Windows removes (compile.zsh); P6-v2 is its GTK counterpart|P6 import 了 WinUI 的 product,Windows 上的 GTK 建置會移除它們(compile.zsh);它的 GTK 版是 P6-v2'
    'mac P6-v2 macOS' 'P6-v2 imports Gtk itself, so AppKit cannot build it; it is the GTK counterpart of P6|P6-v2 自己 import 了 Gtk,所以 AppKit 無法建置；它是 P6 的 GTK 版'
    'three P12 Windows' 'P12 is the AndroidBackend repro app, out of scope on the Windows/WSL machine (gtk-test-plan-findings.md)|P12 是 AndroidBackend 的重現 app,不在 Windows/WSL 這台機器的範圍內(gtk-test-plan-findings.md)'
    'three P12 WSL' 'P12 is the AndroidBackend repro app, out of scope on the Windows/WSL machine (gtk-test-plan-findings.md); the two WSLg runs that were made (2026-10-21, 2026-10-22) exited 7, every capture failed|P12 是 AndroidBackend 的重現 app,不在 Windows/WSL 這台機器的範圍內(gtk-test-plan-findings.md);實際跑過的兩次 WSLg(2026-10-21、2026-10-22)都以 exit 7 結束，每張擷圖都失敗'
    'three P14 Windows' 'P14 is the UIKitBackend (iOS) repro app, out of scope on the Windows/WSL machine (gtk-test-plan-findings.md)|P14 是 UIKitBackend(iOS)的重現 app,不在 Windows/WSL 這台機器的範圍內(gtk-test-plan-findings.md)'
    'three P14 WSL' 'P14 is the UIKitBackend (iOS) repro app, out of scope on the Windows/WSL machine (gtk-test-plan-findings.md); the two WSLg runs that were made (2026-10-21, 2026-10-22) exited 7, every capture failed|P14 是 UIKitBackend(iOS) 的重現 app,不在 Windows/WSL 這台機器的範圍內(gtk-test-plan-findings.md);實際跑過的兩次 WSLg(2026-10-21、2026-10-22)都以 exit 7 結束，每張擷圖都失敗'
)

# FILE: load the translations; a missing file loads none.
# FILE:載入翻譯；檔案不存在時什麼都不載入。
zh_load() {
    [[ -f $1 ]] || return 0
    local app en zh
    while IFS=$'\t' read -r app en zh; do
        zh_en[$app]=$en
        zh_text[$app]=$zh
    done < <(jq -r 'to_entries[] | [.key, .value.en, .value.zh] | @tsv' $1 | tr -d '\r')
}

zh_escape() {
    local s=$1
    s=${s//&/&amp;}; s=${s//</&lt;}; s=${s//>/&gt;}; s=${s//\"/&quot;}
    printf '%s' $s
}

# APP EN LABEL: the zh-TW line for that app's note, only when it was translated from this English.
# APP EN LABEL:該 app 說明的 zh-TW 一行，只在它是由這段英文翻譯而來時才印出。
zh_line() {
    local app=$1 en=$2 label=$3
    [[ -n $en ]] || return 0
    if [[ -z ${zh_text[$app]:-} ]]; then zh_missing+=($app); return 0; fi
    if [[ ${zh_en[$app]} != $en ]]; then zh_stale+=($app); return 0; fi
    printf '%s\n' "<p class=\"cmp zh\" lang=\"zh-Hant-TW\"><b>$label</b> $(zh_escape ${zh_text[$app]})</p>"
}

zh_report() {
    (( $#zh_missing )) && printf '%s\n' "zh-TW: no translation for ${zh_missing[*]}" >&2
    (( $#zh_stale )) && printf '%s\n' "zh-TW: the English changed after translation, zh line left out: ${zh_stale[*]}" >&2
    return 0
}

# WHY: the reason a caption gives for a missing screenshot, in zh-TW.
# WHY:說明文字中缺少截圖的原因，譯成 zh-TW。
todo_zh() {
    local w=$1
    case $w in
        'no screenshot (exit not run)') w='未執行，沒有截圖' ;;
        'no screenshot (exit '*')') w="沒有截圖(exit ${${w#*exit }%)})" ;;
        'not in the GTK / macOS deck') w='不在 GTK / macOS 簡報中' ;;
        'not captured') w='尚未擷取' ;;
    esac
    printf '%s' $w
}

# APP FIGURES: note each figure without a screenshot for the to-do page.
# APP FIGURES:把每個沒有截圖的 figure 記到待辦頁。
todo_collect() {
    local app=$1 line label why reason
    local -a en zh
    for line in ${(f)2}; do
        [[ $line == '<figure><figcaption>'* ]] || continue
        label=${${line#*<b>}%%</b>*}
        why=${${line##* · }%%</figcaption>*}
        reason=${todo_by_design[$todo_deck $app $label]:-}
        if [[ -n $reason ]]; then
            todo_known+=("$app"$'\t'"$label"$'\t'"${reason%%|*}"$'\t'"${reason#*|}")
            continue
        fi
        en+=("$label: $why")
        zh+=("$label:$(todo_zh $why)")
    done
    (( $#en )) && todo_items+=("$app"$'\t'"${(j:; :)en}"$'\t'"${(j:;:)zh}")
    return 0
}

# APP SIDES: an app with no record at all, every side missing.
# APP SIDES:完全沒有紀錄的 app,每一邊都缺。
todo_uncaptured() {
    todo_items+=("$1"$'\t'"$2: not captured"$'\t'"${2// and / 與 }:$(todo_zh 'not captured')")
}

# The last page: every app with a side missing, from the captions themselves.
# 最後一頁：每個缺了某一邊的 app,取自說明文字本身。
todo_section() {
    local item app en zh
    printf '%s\n' '<section class="todo">'
    printf '%s\n' '<h1>To do: missing screenshots</h1>'
    printf '%s\n' '<p class="zh" lang="zh-Hant-TW">待辦：缺少截圖的頁面</p>'
    if (( ! $#todo_items )); then
        printf '%s\n' '<p>Every page has every screenshot.<span class="zh" lang="zh-Hant-TW">每一頁的截圖都齊全。</span></p>'
    else
        printf '%s\n' '<ul>'
        for item in $todo_items; do
            IFS=$'\t' read -r app en zh <<< $item
            printf '%s\n' "<li><b>$app</b> $(zh_escape $en)<span class=\"zh\" lang=\"zh-Hant-TW\">$(zh_escape $zh)</span></li>"
        done
        printf '%s\n' '</ul>'
    fi
    if (( $#todo_known )); then
        printf '%s\n' '<h2>Not expected: by design or out of scope</h2>'
        printf '%s\n' '<p class="zh" lang="zh-Hant-TW">預期沒有：刻意不建置，或不在該機器的範圍內</p>'
        printf '%s\n' '<ul class="known">'
        for item in $todo_known; do
            IFS=$'\t' read -r app side en zh <<< $item
            # data-* carry the reason to the slide, whose empty side shows it in place of the screenshot.
            # data-* 把原因帶到該頁，空著的那一邊會在截圖的位置顯示它。
            printf '%s\n' "<li data-app=\"$app\" data-side=\"$side\" data-en=\"$(zh_escape $en)\" data-zh=\"$(zh_escape $zh)\"><b>$app</b> $side: $(zh_escape $en)<span class=\"zh\" lang=\"zh-Hant-TW\">$side:$(zh_escape $zh)</span></li>"
        done
        printf '%s\n' '</ul>'
    fi
    printf '%s\n' '</section>'
}
