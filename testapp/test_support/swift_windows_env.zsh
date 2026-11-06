#!/usr/bin/env zsh
# Put the newest installed Swift for Windows on PATH, with its runtime and SDK. Source this.
# 把最新安裝的 Swift for Windows 連同其 runtime 與 SDK 放進 PATH。以 source 引入。
#
#   source "$script_dir/test_support/swift_windows_env.zsh"   (compile.zsh, test.zsh)
#   zsh testapp/test_support/swift_windows_env.zsh --help
#
# Picks the newest toolchain under %LOCALAPPDATA%\Programs\Swift\Toolchains that
# has a runtime of the same version, drops every other Swift Toolchains/Runtimes
# entry from PATH, puts the chosen two first, and points SDKROOT at that version's
# Windows SDK. Does nothing off Windows, or when no matching pair is installed
# (PATH is then left as the caller had it).
# 在 %LOCALAPPDATA%\Programs\Swift\Toolchains 底下挑出「有相同版本 runtime」的最新工具鏈，
# 從 PATH 移除其他所有 Swift Toolchains/Runtimes 項目，把選中的兩個放到最前面，並讓 SDKROOT
# 指向該版本的 Windows SDK。不在 Windows 上、或找不到相配的組合時，什麼都不做。
#
# Why (2026-11-06): the user upgraded Swift 6.4.1 -> 6.4.2, and the installer
# deleted 6.4.1. Every shell opened before that still had 6.4.1 in PATH and
# SDKROOT, so `swiftc` was "not found", Swift exes could not find swiftCore.dll,
# and a build reported "no such SDK ... 6.4.1". The user's rule: detect the latest
# version, do not pin one. Ported from multissh's helper/swift_windows_env.zsh,
# which hit the same thing on the 6.3.x -> 6.4.1 upgrade.
# 為什麼(2026-11-06):使用者把 Swift 6.4.1 升到 6.4.2,安裝程式刪掉了 6.4.1。在那之前開的
# shell 的 PATH 與 SDKROOT 仍指向 6.4.1,於是 `swiftc` 找不到、Swift 執行檔找不到
# swiftCore.dll、建置回報 "no such SDK ... 6.4.1"。使用者的規則：自動偵測最新版，不要釘死
# 版本。移植自 multissh 的 helper/swift_windows_env.zsh,它在 6.3.x -> 6.4.1 升級時遇過同一件事。

if [[ $ZSH_EVAL_CONTEXT == toplevel && ( ${1:-} == -h || ${1:-} == --help ) ]]; then
    sed -n '2,25p' "${0:A}" | sed 's/^# \{0,1\}//'
    exit 0
fi

if [[ $(uname -s) == *NT* ]]; then
    swift_windows_base="$(cygpath -u "${LOCALAPPDATA:-C:\\Users\\${USERNAME}\\AppData\\Local}")/Programs/Swift"
    # Numeric sort (glob qualifier n): 6.10.0 sorts after 6.4.2. Newest is tried first.
    # 數值排序(glob 限定詞 n):6.10.0 排在 6.4.2 之後。先試最新的。
    typeset -a swift_windows_toolchains
    swift_windows_toolchains=("$swift_windows_base"/Toolchains/*(N/n))
    swift_windows_version=''
    for swift_windows_candidate in "${(Oa)swift_windows_toolchains[@]}"; do
        swift_windows_candidate_version=${${swift_windows_candidate:t}%%+*}
        if [[ -d $swift_windows_base/Runtimes/$swift_windows_candidate_version/usr/bin &&
              -d $swift_windows_candidate/usr/bin ]]; then
            swift_windows_version=$swift_windows_candidate_version
            swift_windows_toolchain_bin=$swift_windows_candidate/usr/bin
            break
        fi
    done
    if [[ -n $swift_windows_version ]]; then
        swift_windows_runtime_bin=$swift_windows_base/Runtimes/$swift_windows_version/usr/bin
        # Drop the other Swift entries in both spellings: a deleted version is dead
        # weight, and an older one still installed would load mismatched DLLs.
        # 兩種路徑寫法的其他 Swift 項目都移除：已刪除的版本是累贅，仍安裝著的舊版會載入不相符的 DLL。
        path=(${path:#*/Programs/Swift/(Runtimes|Toolchains)/*})
        path=(${path:#*\\Programs\\Swift\\(Runtimes|Toolchains)\\*})
        path=("$swift_windows_runtime_bin" "$swift_windows_toolchain_bin" $path)
        export PATH
        swift_windows_sdk=$swift_windows_base/Platforms/$swift_windows_version/Windows.platform/Developer/SDKs/Windows.sdk
        if [[ -d $swift_windows_sdk ]]; then
            export SDKROOT="$(cygpath -w "$swift_windows_sdk")\\"
        fi
    fi
    unset swift_windows_candidate swift_windows_candidate_version swift_windows_toolchains
fi
