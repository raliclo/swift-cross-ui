# One run per platform at a time. Sourced at the top level of a script, with
# the platform as its argument -- not called as a function:
#
#   source "$script_dir/test_support/platform_lock.zsh" android
#   source "$script_dir/test_support/platform_lock.zsh" ios
#
# Two runs on one platform share everything that matters: the device (one
# emulator, one simulator), the compile tree (.compile-work-<backend>), and for
# Android the one Gradle project, for iOS testapp/.bundledApp and the .xctestrun
# it edits with PlistBuddy -- a second run can rewrite the first one's action
# file path under it. Running them truly in parallel would need a device and a
# tree per run (5-15 GB each). This makes a second run wait instead of
# corrupting the first, which is the part that was unsafe.
#
# Per platform, not the desktop-wide testapp/ui-lock.zsh: the emulator and the
# simulator are separate devices, and an Android run need not wait for an iOS
# one.
#
# The lock is a directory, created atomically by mkdir, holding the owner's
# PID. A lock whose owner is gone is taken over. Re-entrant through
# SCUI_PLATFORM_LOCK_<NAME>: test_android.zsh holds it while compile.zsh, its
# child, asks for it again, and the child leaves the release to its parent.
#
# **Why sourced, and why traps, not a function with zshexit (2026-10-05).** The
# first version was a function that registered a zshexit hook. zsh does not run
# zshexit when a script ends through `set -e` (any failing command in these
# scripts) or a signal (`timeout`), so those runs left their lock behind --
# measured: `false` and `kill -TERM` left it, `exit` released it, and SoftPCB-mac
# found an iOS lock owned by a dead run. An EXIT trap or TRAPEXIT set inside a
# function fires when the FUNCTION returns, releasing the lock at once
# (measured too). Traps set by a file sourced at the top level belong to the
# script: held throughout, released for `false`, `exit`, TERM, INT and a normal
# end, and still released when the caller later installs its own INT/TERM
# handler that calls `exit` (test_ios.zsh does).
#
# 每個平台一次只跑一個。在腳本最外層以 source 載入並帶平台名稱，不是當函式呼叫。同一平台的兩次執行共用裝置、
# 編譯樹，Android 還有那一個 Gradle 專案,iOS 則有 testapp/.bundledApp 與它改寫的 .xctestrun。這裡讓第二次
# 執行等待，而不是弄壞第一次。鎖是 mkdir 原子建立的目錄，內含持有者 PID;持有者已不在就接手；以
# SCUI_PLATFORM_LOCK_<NAME> 可重入，子行程把釋放留給父行程。**為何用 source 與 trap(2026-10-05)**:第一版是
# 註冊 zshexit 的函式，但腳本因 `set -e`(任何失敗的指令)或訊號(`timeout`)結束時 zsh 不跑 zshexit,鎖就留下
# 了——實測 `false` 與 `kill -TERM` 留下鎖,`exit` 會釋放;SoftPCB-mac 也發現一個屬於已結束執行的 iOS 鎖。
# 在函式裡設的 EXIT trap 或 TRAPEXIT 會在「函式」返回時觸發，鎖一拿到就放掉(同樣實測)。在最外層 source
# 的檔案所設的 trap 屬於整支腳本：全程持有，在 `false`、`exit`、TERM、INT 與正常結束時都會釋放，呼叫端之後
# 換上自己會 `exit` 的 INT/TERM 處理時也照樣釋放(test_ios.zsh 就是如此)。

_platform_lock_name="${1:?usage: source platform_lock.zsh <android|ios>}"
_platform_lock_var="SCUI_PLATFORM_LOCK_${_platform_lock_name:u}"
_platform_lock_dir="${${(%):-%x}:A:h:h}/.platform-lock-$_platform_lock_name"

# Already ours: a parent run holds it and exported the token. Leave it alone.
# 已經是我們的：父行程持有並匯出了標記。不動它。
if [ -n "${(P)_platform_lock_var:-}" ] && [ -f "$_platform_lock_dir/owner" ] \
    && [ "$(cat "$_platform_lock_dir/owner" 2>/dev/null)" = "${(P)_platform_lock_var}" ]; then
    :
else
    _platform_lock_waited=0
    until mkdir "$_platform_lock_dir" 2>/dev/null; do
        _platform_lock_owner="$(cat "$_platform_lock_dir/owner" 2>/dev/null || true)"
        if [ -n "$_platform_lock_owner" ] && ! kill -0 "$_platform_lock_owner" 2>/dev/null; then
            print -u2 "==> $_platform_lock_name lock: holder $_platform_lock_owner is gone; taking it over"
            rm -rf -- "${_platform_lock_dir:?}"
            continue
        fi
        if (( _platform_lock_waited % 30 == 0 )); then
            print -u2 "==> waiting for the $_platform_lock_name lock (held by pid ${_platform_lock_owner:-?}: $(cat "$_platform_lock_dir/what" 2>/dev/null || true))"
        fi
        sleep 2
        _platform_lock_waited=$(( _platform_lock_waited + 2 ))
    done
    print -r -- "$$" > "$_platform_lock_dir/owner"
    print -r -- "${ZSH_ARGZERO:t}" > "$_platform_lock_dir/what"
    export "$_platform_lock_var=$$"
    _platform_lock_release() {
        [ "$(cat "$_platform_lock_dir/owner" 2>/dev/null)" = "$$" ] && rm -rf -- "${_platform_lock_dir:?}"
        return 0
    }
    trap '_platform_lock_release' EXIT
    trap '_platform_lock_release; exit 143' TERM
    trap '_platform_lock_release; exit 130' INT
fi
