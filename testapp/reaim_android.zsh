#!/usr/bin/env zsh
# Re-aim Android action files after a layout change, by the widget each point
# was recorded on rather than by arithmetic on the coordinates.
#
#   zsh testapp/reaim_android.zsh record FILE.actions ...  replay as written; keep each point's aim record
#   zsh testapp/reaim_android.zsh aim    FILE.actions ...  replay with those records: each point goes to its widget
#   zsh testapp/reaim_android.zsh report [-v]          what moved, and what must not be written back
#   zsh testapp/reaim_android.zsh write  STEM ...      put the moved points into the files (clean files only)
#   zsh testapp/reaim_android.zsh write --all          every clean file of the report
#   zsh testapp/reaim_android.zsh check  FILE.actions ...  replay as written; compare with the aim run
#
# `record` belongs to the build the files were last right on; `aim` and `check`
# to the build they are being moved to. Everything is kept under
# testapp/output/reaim/ (REAIM_DIR to change it), one set of files per stem:
# <mode>-<stem>.log, .logcat, .labels, .png, and aim-<stem>.actions, the file as it was aimed.
#
# **A file is clean only if** it replayed to the end, every point matched
# inside its own recorded widget under the same widget class, and no parking
# row left the screen. `write` refuses the rest and names them; those are
# re-aimed by hand. Each refusal is something that went wrong on 2026-10-13:
#
#   class-changed   P35, P2, P45: the recorded toggle resolved to the text
#                   label beside what is now a Switch, and pressing the label
#                   toggles nothing. P36 and P53 were the control itself under
#                   a new class -- which of the two it is has to be looked at.
#   near/unmatched  the widget was not found; the point is a guess.
#   park off screen P48, P51: a `move` that only parks the pointer before a
#                   scroll was matched to a widget now past the screen edge,
#                   and reaching it scrolled the page sideways first.
#   labels empty    P57, P72: the label capture was empty in both runs, so
#                   "same" said nothing. Read the capture or the log instead.
#
# **No device is an error, said at once.** Every replay asks adb for the device
# first. On 2026-10-13 the emulator was closed mid-sweep and the sweep sat in
# `adb logcat -c` for ten minutes without a word.
#
# 依每個點當初所記錄的元件(而不是對座標做算術)在版面改變後重新瞄準 Android 動作檔。
#
# `record` 屬於檔案上一次正確時的那個建置;`aim` 與 `check` 屬於要搬過去的建置。所有東西都放在
# testapp/output/reaim/(可用 REAIM_DIR 更改),每個檔名一組:<mode>-<stem>.log、.logcat、.labels、.png,以及 aim-<stem>.actions(瞄準當時的檔案)。
#
# **檔案要同時滿足以下才算乾淨**:重放到結尾、每個點都落在它自己所記錄的元件之內且元件類別相同、沒有任何
# 停駐列離開螢幕。其餘的 `write` 會拒絕並點名,那些要手動重新瞄準。每一種拒絕都是 2026-10-13 出過的錯:
#
#   class-changed   P35、P2、P45:紀錄中的 toggle 解析到現在是 Switch 的那個控制項旁邊的文字,而按文字什麼都
#                   不會切換。P36 與 P53 則是控制項本身換了類別——是哪一種必須親眼看。
#   near/unmatched  找不到元件;那個點是猜的。
#   park off screen P48、P51:只是在捲動前停放指標的 `move`,被比對到現在已超出螢幕邊緣的元件,為了到達它
#                   頁面先被橫向捲走。
#   labels empty    P57、P72:兩次的標籤擷取都是空的,所以「相同」不代表什麼。改讀擷圖或 log。
#
# **沒有裝置是錯誤,而且立刻明講。** 每次重放前都先向 adb 要裝置。2026-10-13 模擬器在掃描途中被關掉,
# 掃描就停在 `adb logcat -c` 十分鐘,一個字都沒說。
set -u
script_dir="${0:A:h}"; repo_root="${script_dir:h}"
android_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-${repo_root:h}/.android-sdk}}"
adb="$android_root/platform-tools/adb"
work="${REAIM_DIR:-$script_dir/output/reaim}"
actions="$script_dir/actions/android"
helper="$script_dir/test_support/reaim_android.py"

die() { print -u2 -- "error: $*"; exit 1; }

# Exit 3: no device. `adb get-state` answers at once where `adb logcat` waits.
# 結束碼 3:沒有裝置。`adb get-state` 會立刻回答,而 `adb logcat` 會一直等。
require_device() {
    [ -x "$adb" ] || die "no adb at $adb (set ANDROID_HOME)"
    local state
    state="$("$adb" get-state 2>&1)"
    [ "$state" = device ] && return 0
    print -u2 -- "error: no Android device before ${1:-the sweep}: adb get-state said \"$state\"."
    print -u2 -- "       Nothing was replayed. Boot the emulator -- any 'zsh testapp/test.zsh <Pn> --android' does -- and run this again."
    exit 3
}

app_of() {
    local stem="$1"
    case "$stem" in
        P15-DARK*) print P15-DARK ;;
        P17-DOE*) print P17-DOE ;;
        *) print "${stem%%-*}" ;;
    esac
}
package_of() { local app="$1"; print "dev.swiftcrossui.testapp.${${app:l}//-/}"; }

replay() {
    local mode="$1"; shift
    (( $# )) || die "$mode needs at least one action file"
    mkdir -p "$work"
    local -a files; files=("$@")
    local i f stem app log t0 pid rc shot rep previous following
    for (( i = 1; i <= $#files; i++ )); do
        f="${files[i]:A}"
        [ -f "$f" ] || die "no such action file: $f"
        stem="${f:t:r}"; app="$(app_of "$stem")"
        require_device "$stem"
        log="$work/$mode-$stem.log"
        previous=""; (( i > 1 )) && previous="$(app_of "${files[i-1]:t:r}")"
        [ "$previous" = "$app" ] || "$adb" uninstall "$(package_of "$app")" >/dev/null 2>&1
        unset ANDROID_AIM_FILE
        if [ "$mode" = aim ]; then
            [ -f "$work/record-$stem.logcat" ] || die "$stem has no record run; run 'record' on the build the file was right on"
            grep -a -- '-actionfile: aim ' "$work/record-$stem.logcat" | sed 's/^.*-actionfile: aim //' > "$work/$stem.aims"
            [ -s "$work/$stem.aims" ] && export ANDROID_AIM_FILE="$work/$stem.aims"
            # The file as it is aimed: the report works the moves out from this copy.
            # 瞄準當時的檔案:report 由這份複本算出位移。
            cp "$f" "$work/aim-$stem.actions"
        fi
        "$adb" logcat -c >/dev/null 2>&1
        while pgrep -f SoftPCB >/dev/null 2>&1; do print "waiting for SoftPCB before $stem"; sleep 60; done
        t0=$(date +%s)
        SCUI_DEBUG=1 zsh "$script_dir/test.zsh" "$app" --android --actionfile "$f" --no-showtime > "$log" 2>&1 &
        pid=$!
        while kill -0 $pid 2>/dev/null; do
            if (( $(date +%s) - t0 > ${REAIM_TIMEOUT:-1500} )); then kill $pid; print TIMEOUT >> "$log"; break; fi
            sleep 2
        done
        wait $pid 2>/dev/null; rc=$?
        require_device "the capture of $stem"
        "$adb" logcat -d 2>/dev/null | grep -a -e '-actionfile:' -e '\[P[0-9]' > "$work/$mode-$stem.logcat"
        "$adb" exec-out uiautomator dump /dev/tty 2>/dev/null | python3 "$helper" labels > "$work/$mode-$stem.labels"
        shot="$(ls -t "$script_dir"/output/screenshots/${app:l}-android-final-*.png 2>/dev/null | head -1)"
        [ -n "$shot" ] && cp "$shot" "$work/$mode-$stem.png"
        rep=no; grep -aq -- '-actionfile: replayed' "$work/$mode-$stem.logcat" && rep=ok
        print "$stem rc=$rc replay=$rep $(( $(date +%s) - t0 ))s aim records=$(grep -ac -- '-actionfile: aim ' "$work/$mode-$stem.logcat") aimed=$(grep -ac -- '-actionfile: aimed ' "$work/$mode-$stem.logcat")"
        following=""; (( i < $#files )) && following="$(app_of "${files[i+1]:t:r}")"
        [ "$following" = "$app" ] || "$adb" uninstall "$(package_of "$app")" >/dev/null 2>&1
    done
    print "SWEEP-DONE $mode: $#files file(s) in $work"
}

# The device's size in points, for the parking-row check. Asked of the device
# when there is one; the report still runs without, and says what it assumed.
# 裝置以點為單位的大小,供停駐列檢查使用。有裝置時向裝置詢問;沒有時 report 照跑,並說明它假設了什麼。
screen_args() {
    local size density
    [ -x "$adb" ] && [ "$("$adb" get-state 2>/dev/null)" = device ] || return 0
    size="$("$adb" shell wm size 2>/dev/null | grep -oE '[0-9]+x[0-9]+' | tail -1)"
    density="$("$adb" shell wm density 2>/dev/null | grep -oE '[0-9]+' | tail -1)"
    [ -n "$size" ] && [ -n "$density" ] && print -- "--screen $size --dpi $density"
}

write_back() {
    (( $# )) || die "write needs stems, or --all"
    [ -f "$work/aimed.json" ] || die "no report yet; run 'report' first"
    command -v csv2 >/dev/null || die "csv2 is not on PATH; the files are edited through it"
    local -a stems
    if [ "$1" = --all ]; then stems=($(python3 "$helper" clean "$work")); else stems=("$@"); fi
    (( $#stems )) || { print "nothing to write: the report has no clean file"; return 0; }
    local stem f line a b c d old new failed=0 touched=0
    for stem in $stems; do
        stem="${stem:t:r}"; f="$actions/$stem.actions"
        [ -f "$f" ] || die "no such action file: $f"; touched=0
        python3 "$helper" rows "$work" "$stem" | while IFS=$'\t' read -r line a b c d; do
            old="$(csv2 --headers 0 -get "$line:1" -i "$f")"
            new="$(python3 "$helper" setxy "$old" "$a" "$b" "$c" "$d")" || { failed=1; print -u2 -- "$stem line $line: refused"; continue; }
            printf '%s' "$new" > "$work/write.val"
            csv2 --headers 0 -update "$line:1" --value-file "$work/write.val" -i "$f" --in-place \
                && print "$stem line $line: ($a, $b) -> ($c, $d)" || failed=1
            (( ++touched ))
        done
        [ ${pipestatus[1]} -eq 0 ] || { failed=1; print -u2 -- "$stem: not written (see the line above)"; }
        (( touched || failed )) || print "$stem: nothing to write, every point already holds its target"
    done
    return $failed
}

command="${1:-}"; (( $# )) && shift
case "$command" in
    record | aim | check) replay "$command" "$@" ;;
    report) python3 "$helper" report "$work" "$actions" $(screen_args) "$@" ;;
    write) write_back "$@" ;;
    *) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
