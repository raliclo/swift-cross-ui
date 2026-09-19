#!/usr/bin/env zsh
# One answer to "which GTK runtime does a -gtk4 app load?", sourced by
# run.zsh, window_sizes.zsh and test_support/test_common.zsh.
#
#   source testapp/test_support/gtk_runtime.zsh
#   scui_gtk_runtime_path   # prints the POSIX dirs to put in front of PATH
#
# THE ACCESSKIT BUILD FIRST, when it is installed. The gvsbuild bundle that
# install_gtk4_windows.zsh fetches is built WITHOUT the AccessKit backend --
# `GTK_A11Y=help` on it prints `accesskit - Disabled during GTK build` and
# `atspi - Not available on this platform` -- so with that runtime a screen
# reader sees ONE node on this platform, the window, and every `.accessibility*`
# modifier is a no-op. install_gtk4_accesskit_windows.zsh builds one that has it.
#
# BOTH directories, in that order. The AccessKit prefix holds GTK only; glib,
# pango, cairo, graphene and the rest still come from the bundle, so the bundle
# stays on PATH behind it.
#
# The apps are NOT rebuilt for this. Both are GTK 4.22.4 with the same ABI, and
# an executable built against the bundle's headers runs against either DLL --
# measured 2026-09-19 with P50 808x1005, P11 788x688 and P52 1028x968, identical
# under both runtimes, and P50's capture unchanged.
#
# Overrides, in order: GTK4_PREFIX names the runtime outright and nothing is
# added behind it; SCUI_GTK_NO_ACCESSKIT=1 goes back to the bundle alone.
#
# 一個地方回答「-gtk4 的 app 會載入哪一份 GTK runtime」,由 run.zsh、window_sizes.zsh 與 test_common.zsh 共用。
#
# **安裝了就優先用 AccessKit 那一份。** install_gtk4_windows.zsh 取得的 gvsbuild bundle 並未啟用 AccessKit
# ——在它上面 `GTK_A11Y=help` 會印出 `accesskit - Disabled during GTK build`——因此以那份 runtime 執行時,
# 螢幕閱讀器在這個平台上只看得到**一個**節點(視窗),所有 `.accessibility*` modifier 形同無效。
#
# **兩個目錄都放,順序如上**:AccessKit 前綴只含 GTK,glib/pango/cairo/graphene 等仍來自 bundle。
#
# **不需要為此重新建置 app**:兩者都是 GTK 4.22.4、ABI 相同,依 bundle 標頭建置的執行檔在任一份 DLL 上都能跑
# ——2026-09-19 實測,P50 808x1005、P11 788x688、P52 1028x968 在兩份 runtime 下完全相同,P50 的擷圖也一樣。
#
# 覆寫順序:`GTK4_PREFIX` 直接指定 runtime(其後不再附加);`SCUI_GTK_NO_ACCESSKIT=1` 回到只用 bundle。

# POSIX form before anything touches PATH. `:` is the separator there, so
# `C:/gtk4/bin` is not one entry but two, `C` and `/gtk4/bin`, neither of which
# exists -- the mistake each of the three call sites had already made once.
# 先轉成 POSIX 形式:PATH 以 `:` 分隔,因此 `C:/gtk4/bin` 不是一項而是 `C` 與 `/gtk4/bin` 兩項,兩者都不存在
# ——這正是那三個呼叫點各自犯過一次的錯。
scui_gtk_posix_path() {
    cygpath -u "$1" 2>/dev/null || printf '%s' "$1"
}

scui_gtk_runtime_path() {
    local bundle="${GTK4_PREFIX:-C:/gtk4}"
    local accesskit="${SCUI_GTK_ACCESSKIT_PREFIX:-C:/gtk4-accesskit}"
    local bundle_bin accesskit_bin
    bundle_bin="$(scui_gtk_posix_path "$bundle/bin")"
    accesskit_bin="$(scui_gtk_posix_path "$accesskit/bin")"

    if [[ -n "${GTK4_PREFIX:-}" || "${SCUI_GTK_NO_ACCESSKIT:-}" == "1" ]]; then
        printf '%s' "$bundle_bin"
        return
    fi

    if [[ -f "$accesskit_bin/gtk-4-1.dll" ]]; then
        printf '%s:%s' "$accesskit_bin" "$bundle_bin"
    else
        printf '%s' "$bundle_bin"
    fi
}
