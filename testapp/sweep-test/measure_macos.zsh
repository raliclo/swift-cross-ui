#!/usr/bin/env zsh
# Captures one Pn's window on macOS so its coordinates can be read off the image.
#
#   zsh testapp/sweep-test/measure_macos.zsh P21
#   zsh testapp/sweep-test/measure_macos.zsh P21 --keep     leave it running
#
# Writing an action file needs the control positions, and on macOS the only way
# to get them for an app you cannot instrument is to look at it. This does the
# four steps that took four round trips by hand: build with SCUI_DEBUG, launch,
# wake the display, capture the window by id.
#
# 擷取某支 Pn 在 macOS 上的視窗，以便自影像讀出其座標。
#
# 撰寫動作檔需要控制項的位置，而在 macOS 上，對於一支無法注入探針的 app，取得位置的唯一方法就是
# 看它。本腳本執行的是原本需要四個回合才能手動完成的四個步驟：以 SCUI_DEBUG 建置、啟動、喚醒
# 顯示器、依視窗 id 擷取。

set -euo pipefail

script_path="${0:A}"
testapp_dir="${script_path:h:h}"
repo="${testapp_dir:h}"

app="${1:-}"
keep=0
[ "${2:-}" = --keep ] && keep=1

case "$app" in
    P<->|P<->-*) ;;
    *) sed -n '2,6p' "$script_path" | sed 's/^# \{0,1\}//' >&2; exit 64 ;;
esac

[ "$(uname -s)" = Darwin ] || { printf 'macOS only.\n' >&2; exit 3; }

# SCUI_DEBUG=1, always. Without it -actionfile is compiled out, so the binary
# this produces is the one the action file will actually be replayed against
# rather than a lookalike that silently ignores the flag.
# 一律使用 SCUI_DEBUG=1。少了它，-actionfile 會被編譯掉，因此此處產生的執行檔，正是動作檔實際將被
# 重放於其上的那一個，而非一個會靜默忽略該旗標的相似品。
printf '==> building %s with SCUI_DEBUG=1\n' "$app"
( cd "$repo" && SCUI_DEBUG=1 zsh testapp/compile.zsh "$app" 2>&1 | grep -E 'error:|Build complete' ) || true

pkill -x "$app" 2>/dev/null || true
sleep 1
( cd "$testapp_dir/output" && ./"$app" --debug >/dev/null 2>&1 & )

# Polled, not slept. A fixed wait is a guess about the slowest app, and the
# first version guessed five seconds -- P21 needed longer and reported "no
# window owned by P21", which reads like the app failing to start rather than
# the helper being impatient.
# 採輪詢而非固定睡眠。固定等待是對「最慢的那支 app」的猜測，而第一版猜了五秒——P21 需要更久，於是
# 回報「no window owned by P21」，那讀起來像是 app 啟動失敗，而非本工具不夠有耐心。
# `|| true` on the read, and the break tested separately.
#
# `read` returns 1 at end of input, which is what an empty window list gives it,
# and under `set -e` that ended the polling on the first attempt -- the helper
# then reported "no window after 20s" having actually looked once. P21's window
# appears in about six seconds and was being missed by a script that had already
# stopped looking.
#
# read 加上 `|| true`，break 的判斷獨立出來。
#
# `read` 在輸入結束時回傳 1，而空的視窗清單給它的正是輸入結束；在 `set -e` 之下，這會使輪詢在第一
# 次嘗試後就結束——本工具於是回報「20 秒內沒有視窗」，而實際上它只看了一次。P21 的視窗約六秒後出現，
# 卻被一支早已停止尋找的腳本錯過。
# The window query lives in a quoted heredoc and takes the app name from the
# environment.
#
# It was an `osascript -e "..."` string before, nested inside a command
# substitution inside a double-quoted assignment, and somewhere in those three
# layers the interpolation stopped working: the same JavaScript matched P21 when
# run straight from a shell and matched nothing from inside this script. A
# quoted heredoc is not interpolated by the shell at all, so there is one less
# thing that can silently change the program being run.
#
# 視窗查詢改為置於引號化的 heredoc 中，並自環境變數取得 app 名稱。
#
# 先前它是 `osascript -e "..."` 字串，巢狀於命令替換之中、又位於一個雙引號賦值裡；在那三層之間的
# 某一層，插值失效了：同一段 JavaScript 直接在 shell 中執行可以匹配到 P21，從本腳本內執行卻匹配
# 不到任何東西。引號化的 heredoc 完全不會被 shell 插值，因此少了一個會靜默改變「實際執行的程式」
# 的環節。
# The query lists every window and the shell picks the row; JXA does no
# filtering.
#
# Filtering inside JXA meant getting the app name into it, and neither an
# interpolated -e string nor an environment variable read through
# NSProcessInfo worked -- the script could see [P21] in the window list while
# its own `find` matched nothing, so the name never arrived. Emitting
# `owner id x y w h` per line and using grep removes the only thing that was
# going wrong.
#
# 此查詢會列出所有視窗，並由 shell 挑出所需的那一列；JXA 不做任何過濾。
#
# 在 JXA 內過濾意味著必須把 app 名稱送進去，而無論是插值的 -e 字串，或透過 NSProcessInfo 讀取環境
# 變數，都行不通——本腳本能在視窗清單中看到 [P21]，其自身的 `find` 卻匹配不到任何東西，可見該名稱
# 從未送達。改為每列輸出 `owner id x y w h` 再以 grep 處理，即可移除唯一出錯的環節。
all_windows() {
    # The script goes to a file, not to stdin.
    #
    # `osascript -l JavaScript <<'JXA'` produces no output and exits 0 -- it does
    # not read the script from stdin, and says nothing about it. That silence is
    # what made this hard to see: the helper reported "no window owned by P21"
    # while its own debug dump of every window it could see was also empty,
    # because both went through the same heredoc. A file argument works, and so
    # does -e.
    #
    # 腳本寫入檔案，而非交給 stdin。
    #
    # `osascript -l JavaScript <<'JXA'` 不會產生任何輸出且以 0 結束——它不從 stdin 讀取腳本，也不
    # 對此發出任何說明。正是這份沉默使問題難以察覺：本工具回報「no window owned by P21」，而它自己
    # 用來列出所有可見視窗的除錯輸出同樣是空的，因為兩者走的是同一個 heredoc。改用檔案引數即可運作，
    # -e 亦然。
    # 2>&1, not 2>/dev/null. JXA's console.log writes to stderr, so discarding
    # stderr discards the entire result -- the command then succeeds and prints
    # nothing, which reads as "no windows exist". Every working osascript call in
    # this session had 2>&1 on it; the one that did not spent several rounds
    # looking like a permissions or heredoc problem.
    # 用 2>&1 而非 2>/dev/null。JXA 的 console.log 寫入 stderr，因此丟棄 stderr 等於丟棄全部結果——
    # 該指令會成功且不輸出任何東西，讀起來就像「沒有任何視窗」。本次工作中每一個能運作的 osascript
    # 呼叫都帶著 2>&1；唯一沒帶的那個，花了好幾個回合看起來像是權限或 heredoc 的問題。
    local js="${TMPDIR:-/tmp}/scui-measure-$$.js"
    cat > "$js" <<'JXA'
ObjC.import('CoreGraphics');
const all = ObjC.deepUnwrap(ObjC.castRefToObject($.CGWindowListCopyWindowInfo(1, 0)));
all.forEach(w => {
  const b = w.kCGWindowBounds || {};
  console.log([(w.kCGWindowOwnerName || '-'), w.kCGWindowNumber,
               b.X, b.Y, b.Width, b.Height].join(' '));
});
JXA
    osascript -l JavaScript "$js" 2>&1 || true
    rm -f "$js"
}

wid=""
for _ in {1..20}; do
    sleep 1
    line="$(all_windows | awk -v a="$app" '$1 == a {print $2, $3, $4, $5, $6; exit}')" || true
    if [ -n "$line" ]; then
        read -r wid wx wy ww wh <<<"$line" || true
        [ -n "$wid" ] && break
    fi
done

if [ -z "${wid:-}" ]; then
    printf '!! no window owned by %s after 20s; alive=%s\n' \
        "$app" "$(pgrep -x "$app" >/dev/null && printf yes || printf no)" >&2
    printf '!! owners this process can see:\n' >&2
    all_windows | awk '{print "  [" $1 "]"}' | head -12 >&2
    exit 1
fi

# caffeinate before capturing.
#
# A sleeping display defeats window capture completely: screencapture -l returns
# "could not create image from window" for every window including the frontmost,
# while a whole-screen grab still exits 0 and hands back a black frame. That cost
# an afternoon of window captures that looked like a bug in the capture path.
# `-u` asserts user activity, which wakes the display; the capture then succeeds
# immediately.
#
# 擷取前先 caffeinate。
#
# 顯示器睡著會使視窗擷取完全失效：screencapture -l 對每一個視窗（包含最前方那個）都回傳
# 「could not create image from window」，而全螢幕擷取仍會以 0 結束並交回一張全黑的畫面。這曾造成
# 一整個下午的視窗擷取失敗，且看起來像是擷取路徑本身的缺陷。`-u` 會宣告使用者活動以喚醒顯示器，
# 擷取隨即成功。
caffeinate -u -t 30 &
sleep 2

out="$testapp_dir/output/screenshots/$app-measure.png"
mkdir -p "${out:h}"
rm -f "$out"
screencapture -x -o -l "$wid" "$out" 2>&1 | head -1 || true

if [ ! -s "$out" ]; then
    printf '!! capture produced no file for window %s\n' "$wid" >&2
    [ "$keep" -eq 0 ] && pkill -x "$app" 2>/dev/null
    exit 1
fi

printf '\n%s window %s at %s,%s size %sx%s (points)\n' "$app" "$wid" "$wx" "$wy" "$ww" "$wh"
printf 'image: %s\n' "$out"
# The scale is measured, not assumed.
#
# This block used to say "the image is at backing scale, so a logical point is
# image/2". That is true of some windows and not others: on this machine P3
# captured 1920x1256 for a 960x628 window while P18 captured 720x548 for one of
# 706x538. The scale belongs to the display the window opened on, so moving a
# window between displays changes it, and a sentence cannot know which one this
# run used. Two action files were written against the wrong divisor before this
# was measured.
#
# 縮放比例是量出來的，不是假設的。
#
# 這一段原本寫著「影像為 backing scale，故邏輯點 = 影像座標/2」。那對某些視窗成立、對其他則否：
# 在這台機器上，P3 的 960x628 視窗擷取為 1920x1256，而 P18 的 706x538 視窗擷取為 720x548。縮放
# 比例屬於「視窗開在哪一台顯示器」，因此把視窗搬到另一台顯示器就會改變它，而一句寫死的說明無從
# 得知本次執行用的是哪一台。在實際量測之前，已有兩份動作檔照著錯誤的除數寫成。
px=$(sips -g pixelWidth "$out" 2>/dev/null | awk '/pixelWidth/{print $2}')
if [ -n "${px:-}" ] && [ "$ww" -gt 0 ]; then
    printf 'capture: %spx wide for %spt -- divide image coordinates by %s\n' \
        "$px" "$ww" "$(( px / ww ))"
fi
printf 'origin=frame is what this capture gives directly: -o omits the shadow, so the\n'
printf 'image top-left is the frame top-left. origin=client would need a title bar\n'
printf 'height subtracted, which nothing here measures.\n'
printf 'origin=frame 是本擷取直接給出的：-o 省略陰影，故影像左上角即 frame 左上角。origin=client\n'
printf '則需扣除標題列高度，而此處沒有任何東西量測它。\n'

[ "$keep" -eq 0 ] && { pkill -x "$app" 2>/dev/null || true; }
exit 0
