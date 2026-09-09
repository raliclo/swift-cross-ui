#!/bin/sh

cd "$(dirname "$0")"/../

# A submodule at the wrong commit compiles, so nothing else here would notice.
# See Scripts/check_submodules.sh for the day it did not.
# 停在錯誤 commit 的 submodule 照樣編得過，因此此處沒有別的東西會注意到它。它沒被注意到的那一天，
# 見 Scripts/check_submodules.sh。
sh Scripts/check_submodules.sh || exit 1

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
swift test --test-product swift-cross-uiPackageTests $@
