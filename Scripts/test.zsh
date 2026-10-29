#!/usr/bin/env zsh

cd ${0:A:h}/..

# A submodule at the wrong commit compiles, so nothing else here would notice.
# See Scripts/check_submodules.zsh for the day it did not.
# 停在錯誤 commit 的 submodule 照樣編得過，因此此處沒有別的東西會注意到它。它沒被注意到的那一天，
# 見 Scripts/check_submodules.zsh。
zsh Scripts/check_submodules.zsh || exit 1

# A `(VERIFIED …)` note citing an action file nobody has is a claim nobody can
# check, and it reads exactly like one they can.
# 一句引用了「沒有人擁有的動作檔」的 `(VERIFIED …)`，是一個沒有人能檢查的主張，而它讀起來與一個
# 可以檢查的主張完全相同。
zsh Scripts/check_action_files.zsh || exit 1
# Immediately after it, and they are not the same check: that one asks whether
# a cited file EXISTS, this one whether its rows will parse -- and unlike the
# Swift suite's "every tracked action file parses", this one covers a file that
# git has not been told about yet, which is every action file at the moment it
# matters most.
# 緊接在它之後,而兩者不是同一項檢查:那一個問的是被引用的檔案**是否存在**,這一個問的是它的
# 各列**解析得過嗎**——而且與 Swift 測試套件那個「every tracked action file parses」不同,
# 這一個涵蓋「git 還不知道它存在」的檔案,而那正是每一個動作檔最要緊的那一刻。
zsh Scripts/check_action_file_fields.zsh || exit 1
zsh Scripts/check_results_columns.zsh || exit 1
zsh Scripts/check_mistakes_numbering.zsh || exit 1

# The only check here that costs real time, and it is gated so that it usually
# costs none. It compiles for Android when the change touches code Android
# links, because `swift test` below builds this host's targets and says nothing
# whatever about a platform it cannot build -- which is how the SwiftCrossUI
# core went two days without compiling for Android while macOS and iOS were
# green. mistakes.md entry 24; the script's own header has the measurements and
# says what a skip means.
#
# 此處唯一真正花時間的檢查,而它有閘門,因此通常一毛錢也不花。當改動觸及 Android 會連結的程式碼時,
# 它會為 Android 編譯一次——因為下面的 `swift test` 建的是**這台主機**的 target,對一個它建不起來的
# 平台什麼也沒說;而那正是 SwiftCrossUI 的核心在 macOS 與 iOS 全綠的情況下、兩天沒有為 Android
# 編譯成功過的原因。mistakes.md 第 24 條;量測數字與「跳過代表什麼」寫在該腳本自己的檔頭。
zsh Scripts/check_android_build.zsh || exit 1

# `swift test` builds all targets in the package (even those not depended upon
# by any test targets), which leads to `swift test` on its own being broken
# for SwiftCrossUI
#
# **This script is the only build gate that works on a Mac, and `swift build` is
# not one.** Plain `swift build` fails here for two reasons that have nothing to
# do with the change being tested:
#
#   WinUIBackend  CWinRT needs `wtypesbase.h`, a Windows header
#   UIKitBackend  `unable to resolve module dependency: 'UIKit'` on macOS
#
# Both are the package containing targets this host cannot build, which is the
# point of a cross-platform toolkit. Someone who reaches for `swift build` gets
# two failures, neither of which they caused, and the natural reading is that
# they broke the tree. Use this script; use `testapp/compile.zsh` for a
# particular platform.
#
# **本腳本是 Mac 上唯一有效的建置閘門，而 `swift build` 不是。** 裸的 `swift build` 在此處會因為兩個
# 與「正在測試的改動」毫無關係的理由而失敗：
#
#   WinUIBackend  CWinRT 需要 `wtypesbase.h`，那是一個 Windows 標頭檔
#   UIKitBackend  在 macOS 上得到 `unable to resolve module dependency: 'UIKit'`
#
# 兩者都源於「本套件含有這台主機建不起來的 target」，而那正是一個跨平台工具組的意義所在。伸手去用
# `swift build` 的人會拿到兩個並非自己造成的失敗，而最自然的讀法是「我把樹弄壞了」。請用本腳本；
# 要針對特定平台，請用 `testapp/compile.zsh`。

# On macOS, GtkCHelpers' GL files include <epoxy/gl.h>, and gtk4.pc lists epoxy
# as a private requirement, so the pkg-config cflags SwiftPM applies never name
# Homebrew's include directory. testapp/compile.zsh -gtk4 passes it for the same
# reason. Without it this script stopped on `'epoxy/gl.h' file not found`
# before any test ran (2026-10-30).
# macOS 上 GtkCHelpers 的 GL 檔案 include <epoxy/gl.h>,而 gtk4.pc 把 epoxy 列為 private requirement,
# 所以 SwiftPM 套用的 pkg-config cflags 從不提及 Homebrew 的 include 目錄。testapp/compile.zsh -gtk4
# 出於同樣的理由傳入它。少了它，本腳本會在任何測試執行前停在 `'epoxy/gl.h' file not found`(2026-10-30)。
host_flags=()
if [ "$(uname -s)" = Darwin ] && command -v brew >/dev/null 2>&1; then
    host_flags=(-Xcc "-I$(brew --prefix)/include")
fi
swift test --test-product swift-cross-uiPackageTests "${host_flags[@]}" "$@"
