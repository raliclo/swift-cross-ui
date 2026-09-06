#!/usr/bin/env bash
# Builds the Swift Bundler that Android APK builds actually use.
#
#   bash Scripts/build-android-bundler.sh
#
# Two things this exists for, and both were learned by getting them wrong.
#
# **The artefact.** `test_android.zsh` prefers
# `Vendor/swift-bundler/.build/out/Products/Debug/swift-bundler` -- the
# swiftbuild build tree -- over `$repo_root/swift-bundler`, because ErrorKit's
# resource bundle sits beside it there. `swift build -c debug` writes
# `.build/debug/swift-bundler`, which the Android path never looks at. On
# 2026-09-04 three rebuilds went to the ignored copy, the generated manifest kept
# coming out unchanged, and the missing element was diagnosed as an encoder bug
# that did not exist. Build both; copy the plain one to the repo root for the
# iOS path, which does use it.
#
# **The patch.** `testapp/patches/swift-bundler-android-service.patch` carries
# two changes this tree needs: the `<service>` element that
# `windowLevel(.floating)` cannot work without, and the strip that takes an APK
# from 212 MB to 169. The submodule points at `moreSwift/swift-bundler`, which
# is upstream and not ours to push to, so the patch has to be re-applied after
# any `git submodule update`.
#
# 建置「Android APK 建置實際會使用」的那個 Swift Bundler。
#
# 本腳本存在的兩個理由，而兩者都是做錯之後才學到的。
#
# **產物。** `test_android.zsh` 優先採用
# `Vendor/swift-bundler/.build/out/Products/Debug/swift-bundler`——也就是 swiftbuild 的建置樹——
# 而非 `$repo_root/swift-bundler`，因為 ErrorKit 的 resource bundle 就放在那裡它的旁邊。
# `swift build -c debug` 寫出的是 `.build/debug/swift-bundler`，而 Android 路徑從不查看那裡。
# 2026-09-04，三次重建都建到了那個被忽略的副本，產生出來的 manifest 始終沒有改變，而缺少的元素
# 被診斷成一個並不存在的編碼器 bug。此處兩個都建；並把普通的那一個複製到 repo root，供確實會用它的
# iOS 路徑使用。
#
# **那份 patch。** `testapp/patches/swift-bundler-android-service.patch` 帶有本樹需要的兩項變更：
# `windowLevel(.floating)` 少了就無法運作的 `<service>` 元素，以及讓 APK 由 212 MB 降到 169 的
# 剝除步驟。該 submodule 指向上游的 `moreSwift/swift-bundler`，不是我們可以推送的對象，因此每次
# `git submodule update` 之後都必須重新套用這份 patch。
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bundler_dir="$repo_root/Vendor/swift-bundler"
patch_file="$repo_root/testapp/patches/swift-bundler-android-service.patch"

[ -f "$bundler_dir/Package.swift" ] || {
    echo "Vendor/swift-bundler is empty; run: git submodule update --init --recursive" >&2
    exit 1
}

cd "$bundler_dir"

# `--check` first, so a second run is not an error. `git apply` refuses a patch
# that is already applied, and that refusal is indistinguishable from a patch
# that does not fit any more.
# 先用 `--check`，使第二次執行不會變成錯誤。`git apply` 會拒絕一份已套用的 patch，而那個拒絕
# 與「這份 patch 已經不再吻合」無從區分。
if git apply --check "$patch_file" 2>/dev/null; then
    git apply "$patch_file"
    echo "==> applied $(basename "$patch_file")"
elif git apply --reverse --check "$patch_file" 2>/dev/null; then
    echo "==> patch already applied"
else
    echo "$(basename "$patch_file") does not apply and is not applied." >&2
    echo "The submodule has moved under it; re-make the patch." >&2
    exit 1
fi

echo "==> building the swiftbuild product (the one Android uses)"
swift build --build-system swiftbuild --product swift-bundler

echo "==> building the plain product (the one iOS uses)"
swift build -c debug --product swift-bundler
cp .build/debug/swift-bundler "$repo_root/swift-bundler"

android="$bundler_dir/.build/out/Products/Debug/swift-bundler"
[ -x "$android" ] || { echo "swiftbuild product missing: $android" >&2; exit 1; }

echo
echo "Android:  $android"
echo "iOS:      $repo_root/swift-bundler"
echo
echo "Set SCUI_KEEP_SWIFT_AST=1 when building an APK you intend to attach lldb to;"
echo "the default strips .swift_ast and takes about 43 MB off each APK."
