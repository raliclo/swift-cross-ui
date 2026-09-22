#!/bin/sh
#
# Compiles for Android when, and only when, the change touches code Android
# links.
#
# **The defect this exists for was invisible for two days and nothing reported
# it.** `Sources/SwiftCrossUI/Views/Mesh3DExport.swift` called `sin()` on a
# `Float`. Darwin's maths module has that overload; Bionic's `math.h` has
# `sin(double)` and `sinf(float)` and nothing between them, so on Android the
# compiler could not settle what `/` meant either and reported six errors. That
# file is not in a backend -- it is in `SwiftCrossUI`, which every platform links
# -- so AndroidBackend produced no binary at all from the day it landed while
# macOS and iOS were green and the work was reported as done. mistakes.md entry
# 24, and gate 4 of the `mistakes_prevention` skill: three platforms green says
# nothing whatever about the fourth.
#
# **Gated, not unconditional, and the gate is the whole design.** An Android
# compile is 30 to 95 seconds on this machine. Paying that on every run of
# `Scripts/test.sh` would buy nothing for the many changes that cannot break
# Android -- an AppKit file, an action file, a test app. Paying it when the
# change is in code Android links buys exactly the thing that was missed.
#
# **What counts as "code Android links" is an EXCLUDE list, so that a new target
# triggers the check rather than slipping past it.** Everything under `Sources/`
# counts except the platform backends Android demonstrably does not link. A
# target nobody has classified yet is treated as linked, which costs a minute
# and not two days.
#
# **A skip is not a pass, and the two are printed differently.** Nothing is said
# when the change cannot affect Android: a gate that prints on success trains
# people to ignore it. But when the change DOES touch that code and the Android
# SDK is absent, this says so loudly and still exits 0 -- a contributor without
# the SDK must not be blocked, and must also not be able to read silence as
# "Android is fine". That distinction is mistakes.md entry 4: a tool that
# printed nothing because it never ran looks exactly like one that found
# nothing.
#
# **What it does not cover.** It compares against `origin/develop`, so it
# catches a break before it is pushed and not after. And it builds the package,
# not the test apps: a `testapp/Pn.swift` with the same fault is outside the
# gate on purpose, because gating on `testapp/` would fire on every action-file
# edit and the app is built by whoever runs it anyway.
#
# 只有在改動觸及「Android 會連結的程式碼」時,才為 Android 編譯。
#
# **它所針對的那個缺陷隱形了兩天,而沒有任何東西回報它。**
# `Sources/SwiftCrossUI/Views/Mesh3DExport.swift` 對一個 `Float` 呼叫了 `sin()`。Darwin 的數學模組
# 有那個多載;Bionic 的 `math.h` 只有 `sin(double)` 與 `sinf(float)`,中間什麼都沒有——於是在 Android 上,
# 編譯器連 `/` 是什麼意思都定不下來,一次回報六個錯誤。那個檔案**不在**任何 backend 裡,它在
# `SwiftCrossUI`——每個平台都會連結的那一個——因此從它落地那天起,AndroidBackend 一個二進位都產不出來,
# 而 macOS 與 iOS 全綠、那份工作被回報為完成。mistakes.md 第 24 條,以及 `mistakes_prevention` skill 的
# 關口 4:三個平台全綠,對第四個平台什麼也沒說。
#
# **有閘門、不是無條件執行,而那個閘門就是整個設計。** 一次 Android 編譯在這台機器上是 30 到 95 秒。
# 讓 `Scripts/test.sh` 每次都付這筆錢,對「不可能弄壞 Android 的那些改動」什麼也買不到——一個 AppKit
# 檔案、一個動作檔、一支測試 app。而在「改動就落在 Android 會連結的程式碼裡」時付這筆錢,買到的
# 恰好就是當初漏掉的那一樣東西。
#
# **「Android 會連結的程式碼」是以**排除清單**定義的,好讓一個新的 target 會**觸發**檢查、而不是溜過去。**
# `Sources/` 底下的一切都算,除了那些 Android 明確不會連結的平台 backend。一個還沒有人分類過的 target
# 會被當成「有連結」——那代價是一分鐘,不是兩天。
#
# **跳過不等於通過,而兩者印出來的東西不同。** 當改動不可能影響 Android 時,什麼都不印:一個成功時
# 也會印東西的守衛,會訓練人們忽略它。但當改動**確實**觸及那些程式碼、而 Android SDK 不存在時,
# 它會大聲說出來,並且仍然以 0 結束——沒有 SDK 的貢獻者不該被擋住,但也不該能把沉默讀成
# 「Android 沒問題」。那個分別就是 mistakes.md 第 4 條:一個「因為從未執行而什麼都沒印」的工具,
# 與一個「執行了而什麼都沒找到」的工具,看起來一模一樣。
#
# **它涵蓋不到什麼。** 它是與 `origin/develop` 比較的,因此它抓的是「推出去之前」的破壞,不是之後。
# 而且它建的是套件、不是測試 app:一支帶著同樣錯誤的 `testapp/Pn.swift` 是**刻意**被留在閘門之外的,
# 因為把 `testapp/` 納入閘門會讓它在每一次動作檔編輯時都觸發,而那支 app 本來就是由跑它的人建的。

cd "$(dirname "$0")"/../ || exit 1

# The base to compare against, in the order that is most likely to be right.
# `origin/develop` covers commits made but not yet pushed AS WELL AS the working
# tree, because `git diff <commit>` compares the working tree to that commit --
# which is what is wanted here: the question is "does anything I am about to
# share break Android", not "does my last save".
#
# 用來比較的基準,依「最可能正確」的順序排列。`origin/develop` 同時涵蓋「已 commit 但尚未 push」
# 與工作目錄,因為 `git diff <commit>` 比較的是工作目錄與該 commit——而那正是此處要的:
# 問題是「我即將分享出去的東西有沒有弄壞 Android」,不是「我上一次存檔有沒有」。
base=""
for candidate in origin/develop '@{upstream}' HEAD; do
    if git rev-parse --verify --quiet "$candidate" >/dev/null 2>&1; then
        base="$candidate"
        break
    fi
done

if [ -z "$base" ]; then
    # No git at all, or a repository with no commits. Nothing to compare, and
    # nothing to say.
    # 完全沒有 git,或是一個沒有任何 commit 的倉庫。沒有東西可比,也沒有東西可說。
    exit 0
fi

changed=$(git diff --name-only "$base" 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null)

# The platform backends Android does not link. Everything else under `Sources/`
# is treated as linked -- see the note above about why this is an exclude list.
# Android 不會連結的那些平台 backend。`Sources/` 底下其餘一切都被視為「有連結」
# ——為何用排除清單,見上方說明。
relevant=$(printf '%s\n' "$changed" | grep -E '^(Package\.swift|Sources/)' \
    | grep -vE '^Sources/(AppKitBackend|UIKitBackend|SwiftCrossUIMetal|GtkBackend|Gtk|CGtk|GtkCHelpers|GtkCodeGen|GtkExample|WinUIBackend|WinUIInterop|CursesBackend|LVGLBackend|QtBackend)/')

if [ -z "$relevant" ]; then
    exit 0
fi

# The Android SDK, looked for in the same places `testapp/compile.zsh` looks.
# Asking compile.zsh to find out would conflate "no SDK here" with "the code is
# broken", and those need opposite responses.
# 在與 `testapp/compile.zsh` 相同的地方尋找 Android SDK。交給 compile.zsh 去發現,會把
# 「這裡沒有 SDK」與「程式碼壞了」混為一談,而這兩者需要相反的回應。
android_sdk_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$(cd .. && pwd)/.android-sdk}}"
swift_android_sdk=$(ls -d "$HOME"/Library/org.swift.swiftpm/swift-sdks/*android*.artifactbundle 2>/dev/null | head -1)

if [ ! -d "$android_sdk_root" ] || [ -z "$swift_android_sdk" ]; then
    echo "check_android_build: THIS CHECK DID NOT RUN." >&2
    echo "check_android_build: 這項檢查沒有執行。" >&2
    echo >&2
    echo "  The change touches code Android links:" >&2
    echo "  這次改動觸及了 Android 會連結的程式碼:" >&2
    printf '%s\n' "$relevant" | sort -u | sed 's/^/    /' >&2
    echo >&2
    echo "  ...and no Android SDK was found, so nothing was compiled for it." >&2
    echo "  ...而找不到 Android SDK,因此沒有任何東西為它編譯過。" >&2
    echo "    ANDROID_HOME / ANDROID_SDK_ROOT: $android_sdk_root" >&2
    echo "    Swift Android SDK: ${swift_android_sdk:-<none under ~/Library/org.swift.swiftpm/swift-sdks>}" >&2
    echo >&2
    echo "  Exiting 0 so that a contributor without the SDK is not blocked." >&2
    echo "  This message is the whole point: silence here would read as" >&2
    echo "  'Android is fine', and it is not a statement about Android at all." >&2
    echo "  以 0 結束,好讓沒有 SDK 的貢獻者不被擋住。這段訊息就是重點所在:" >&2
    echo "  此處的沉默會被讀成「Android 沒問題」,而它根本不是一句關於 Android 的話。" >&2
    echo >&2
    echo "  To install it: testapp/install_tools_android.zsh" >&2
    exit 0
fi

echo "check_android_build: core code changed; compiling for Android." >&2
printf '%s\n' "$relevant" | sort -u | sed 's/^/  /' >&2

# P0 rather than something larger: the package is the bulk of the work and every
# test app pulls all of it, so the app chosen only changes the last step.
# 用 P0 而不是更大的:主要的工作量在套件本身,而每一支測試 app 都會把它整個拉進來,
# 因此挑哪一支 app 只影響最後一步。
log=$(mktemp -t check_android_build)
if zsh testapp/compile.zsh -android P0 >"$log" 2>&1; then
    rm -f "$log"
    exit 0
fi

echo >&2
echo "check_android_build: the package does NOT compile for Android." >&2
echo "check_android_build: 本套件在 Android 上編不過。" >&2
echo >&2
grep -E 'error:' "$log" | head -20 | sed 's/^/  /' >&2
echo >&2
echo "  Full log: $log" >&2
echo >&2
echo "  macOS and iOS compiling says nothing about this. If the fault is in a" >&2
echo "  C maths or POSIX function, check whether Bionic has the overload --" >&2
echo "  sin(Float) is Darwin-only, and for trigonometry the fix is to compute" >&2
echo "  in Double and convert, which needs no #if." >&2
echo "  macOS 與 iOS 編得過,對這件事什麼也沒說。若問題出在某個 C 數學或 POSIX 函式," >&2
echo "  先確認 Bionic 有沒有那個多載——sin(Float) 是 Darwin 專屬的;三角函數的修法是" >&2
echo "  以 Double 運算再轉回來,那不需要任何 #if。" >&2
exit 1
