#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P50"
# "P50 TITLE", not the app's description and not the scene title.
#
# **This app changes its own window title, which is the thing it tests**, so no
# fixed full title matches it for a whole run: it launches as
# "P50 TITLE A -- set by navigationTitle" and becomes "...TITLE B..." when the
# button is pressed. The scene title -- "P50 SCENE DEFAULT ..." -- only appears
# when navigationTitle has FAILED, so matching on that would photograph the
# window only in the case this app exists to detect.
#
# `screenshot.zsh` matches with `index($3, want)`, a substring, so the common
# prefix matches both states. Getting this wrong is quiet: an unmatched title
# falls back to the owning program's name and then to the whole screen, and a
# desktop capture of a cluttered screen looks like a test that ran.
#
# 用「P50 TITLE」，不是這支 app 的描述，也不是 scene 的標題。
#
# **這支 app 會改變自己的視窗標題，而那正是它所測試的東西**，因此沒有任何固定的完整標題能在整趟
# 執行中都對得上：它以「P50 TITLE A -- set by navigationTitle」啟動，按下按鈕後變成「…TITLE B…」。
# 至於 scene 的標題「P50 SCENE DEFAULT …」，只有在 navigationTitle **失敗**時才會出現，因此拿它來
# 比對，等於只在「這支 app 存在所要偵測的那個情況」下才拍得到視窗。
#
# `screenshot.zsh` 用的是 `index($3, want)`，屬於子字串比對，因此共同前綴兩種狀態都對得上。
# 這裡寫錯是安靜的：對不上的標題會退回比對「擁有該視窗的程式名稱」，再退回整個螢幕，而一張雜亂桌面的
# 擷圖看起來就像一次「有跑過」的測試。
export TEST_TITLE="P50 TITLE"
export TEST_TARGET="mac"
exec zsh "$support_dir/test_common.zsh" "$@"
