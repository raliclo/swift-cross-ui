#!/usr/bin/env zsh
# Reads P69's accessibility tree through EXTERNAL UI Automation (Windows), in the
# control and content views a screen reader walks -- the WinUI counterpart of
# p69_atspi.zsh: its seven checks plus two for unlabelled button names.
#
#   zsh testapp/test_support/measure/p69_uia.zsh testapp/output/P69-WinUI.exe
#   zsh testapp/test_support/measure/p69_uia.zsh --help
#
# Builds uia_tree.c into testapp/helper/bin on first use (clang), launches the
# app, waits 12 s, dumps both views to testapp/output/p69-uia-<view>.txt, and
# kills the app. Exit 0 only if every check passes in BOTH views.
#
# 透過**外部** UI Automation(Windows)讀取 P69 的無障礙樹,看的是螢幕閱讀器走訪的 control 與
# content view——p69_atspi.zsh 在 WinUI 上的對應版本,七項檢查相同。第一次使用時以 clang 把
# uia_tree.c 建置到 testapp/helper/bin,啟動 app、等 12 秒,把兩個 view 傾印到
# testapp/output/p69-uia-<view>.txt,再結束 app。只有兩個 view 的每項檢查都通過才以 0 結束。
set -euo pipefail

script_path="${0:A}"

if [[ $# -eq 0 || "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    sed -n '2,16p' "$script_path" | sed 's/^# \{0,1\}//'
    exit 0
fi

app="${1:A}"
testapp_dir="${script_path:h:h:h}"
source_file="${script_path:h}/uia_tree.c"
exe_file="${testapp_dir}/helper/bin/uia_tree.exe"
out_dir="${testapp_dir}/output"

if [[ ! -x "$exe_file" || "$source_file" -nt "$exe_file" ]]; then
    mkdir -p "${exe_file:h}"
    printf 'p69_uia.zsh: building %s\n' "$exe_file" >&2
    clang -O1 -Wall -municode "$source_file" -o "$exe_file" \
        -luser32 -lole32 -loleaut32 -luiautomationcore
fi

image="${app:t}"
taskkill -f -im "$image" >/dev/null 2>&1 || true
"$app" --debug > "${out_dir}/p69-uia-app.log" 2>&1 &
trap 'taskkill -f -im "$image" >/dev/null 2>&1 || true' EXIT
sleep 12

failed=0
check() {
    local view="$1" name="$2" ok="$3"
    printf '%-8s %-18s %s\n' "$view" "$name" "$ok"
    [[ "$ok" == true ]] || failed=1
}

for view in control content; do
    dump="${out_dir}/p69-uia-${view}.txt"
    "$exe_file" "P69 accessibility" "$view" > "$dump"
    count() { grep -c -- "$1" "$dump" || true; }
    # `class=` is NOT matched: WinUI names the class `Button` and GTK, through
    # AccessKit, names it `GtkButton`, and this probe has to grade both. The
    # window's own Close button is excluded by requiring content=1, which the
    # title-bar one does not have on WinUI; on GTK the header bar's Close is a
    # real content button, so the count is `>= 1` rather than `== 1`.
    # 不比對 `class=`:WinUI 叫 `Button`,GTK 經 AccessKit 叫 `GtkButton`,而這支探針兩邊都要評。視窗自己的
    # Close 以 `content=1` 排除(WinUI 標題列那顆沒有);GTK 的 header bar Close 是真正的內容按鈕,因此用 `>= 1`。
    check $view label "$([[ $(count "button name='Close'") -ge 1 ]] && printf true || printf false)"
    check $view no_original_label "$([[ $(count "name='X'") -eq 0 ]] && printf true || printf false)"
    check $view hint "$([[ $(count "help='Removes the file permanently'") -eq 1 ]] && printf true || printf false)"
    check $view value "$([[ $(count "status='40 percent'") -eq 1 ]] && printf true || printf false)"
    check $view text_label "$([[ $(count "name='Half past twelve'") -eq 1 ]] && printf true || printf false)"
    check $view no_original_text "$([[ $(count "name='12:30'") -eq 0 ]] && printf true || printf false)"
    check $view hidden "$([[ $(count "name='decorative'") -eq 0 ]] && printf true || printf false)"
    # UIA only: an unlabelled button named from its text, and that text not
    # left behind as a child, which would be announced twice.
    # 僅 UIA:未設標籤的按鈕以其文字命名,且該文字不留作子節點,否則會被念兩次。
    check $view derived_names "$([[ $(count "button name='Delete'") -ge 1 && $(count "button name='Volume'") -ge 1 ]] && printf true || printf false)"
    check $view no_duplicate_text "$([[ $(count "text name='Delete'") -eq 0 && $(count "text name='Volume'") -eq 0 ]] && printf true || printf false)"
done

exit $failed
