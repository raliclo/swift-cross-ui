# One run per platform at a time. Sourced, not run.
#
#   platform_lock android      wait for, then hold, the Android lock until exit
#   platform_lock ios          the same for iOS
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
# PID. A lock whose owner is gone is taken over, so a killed run does not block
# every later one. Re-entrant through SCUI_PLATFORM_LOCK_<NAME>: test_android.zsh
# holds it while compile.zsh, its child, asks for it again.
#
# 每個平台一次只跑一個。以 source 載入。同一平台的兩次執行共用所有關鍵資源：裝置(一個 emulator、一個
# simulator)、編譯樹(.compile-work-<backend>),Android 還有那一個 Gradle 專案,iOS 則有 testapp/.bundledApp
# 與它用 PlistBuddy 改寫的 .xctestrun——第二次執行可能在第一次底下改掉它的動作檔路徑。真正平行需要每次執行
# 各有一台裝置與一棵編譯樹(各 5–15 GB)。這裡讓第二次執行等待，而不是弄壞第一次——不安全的正是這一點。
# 以平台為單位，而非整個桌面的 testapp/ui-lock.zsh:emulator 與 simulator 是不同裝置,Android 不必等 iOS。
# 鎖是一個以 mkdir 原子建立的目錄，內含持有者 PID。持有者已不在的鎖會被接手，因此被殺掉的執行不會擋住之後
# 每一次。可重入：透過 SCUI_PLATFORM_LOCK_<NAME>,test_android.zsh 持有時，它的子行程 compile.zsh 再要一次也行。

platform_lock() {
    local name="$1"
    local var="SCUI_PLATFORM_LOCK_${name:u}"
    local dir="${${(%):-%x}:A:h:h}/.platform-lock-$name"
    # Already ours: a parent run holds it and exported the token.
    # 已經是我們的：父行程持有並匯出了標記。
    if [ -n "${(P)var:-}" ] && [ -f "$dir/owner" ] && [ "$(cat "$dir/owner" 2>/dev/null)" = "${(P)var}" ]; then
        return 0
    fi
    local waited=0 owner
    until mkdir "$dir" 2>/dev/null; do
        owner="$(cat "$dir/owner" 2>/dev/null || true)"
        if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null; then
            print -u2 "==> $name lock: holder $owner is gone; taking it over"
            rm -rf -- "${dir:?}"
            continue
        fi
        if (( waited % 30 == 0 )); then
            print -u2 "==> waiting for the $name lock (held by pid ${owner:-?}: $(cat "$dir/what" 2>/dev/null || true))"
        fi
        sleep 2
        waited=$(( waited + 2 ))
    done
    print -r -- "$$" > "$dir/owner"
    print -r -- "${ZSH_ARGZERO:t} ${*[2,-1]}" > "$dir/what"
    export "$var=$$"
    # Released when the shell exits, and only by its owner. zshexit, not
    # `trap ... EXIT`: inside a function zsh runs an EXIT trap when the FUNCTION
    # returns, which would release the lock the moment it was taken. A run killed
    # outright skips zshexit too; the dead-PID takeover above covers that.
    # shell 結束時釋放，而且只由持有者釋放。用 zshexit 而不是 `trap ... EXIT`:在函式裡,zsh 會在「函式」返回
    # 時執行 EXIT trap,鎖一拿到就會被放掉。被直接殺掉的執行也不會跑 zshexit;上方的「持有者已不在就接手」
    # 涵蓋了那種情況。
    typeset -gA _platform_lock_dirs
    _platform_lock_dirs[$name]="$dir"
    (( ${zshexit_functions[(Ie)_platform_lock_release]} )) || zshexit_functions+=(_platform_lock_release)
}

_platform_lock_release() {
    local d
    for d in ${(v)_platform_lock_dirs}; do
        [ "$(cat "$d/owner" 2>/dev/null)" = "$$" ] && rm -rf -- "${d:?}"
    done
    return 0
}
