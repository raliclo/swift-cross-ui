#!/usr/bin/env zsh
# Installs an MSVC-built GTK 4 on Windows so GtkBackend can be built there.
#
#   zsh testapp/install_gtk4_windows.zsh
#   zsh testapp/install_gtk4_windows.zsh --prefix C:/gtk4 --version 2026.8.0
#   zsh testapp/install_gtk4_windows.zsh --show-changes   # audit the .pc edits
#   zsh testapp/install_gtk4_windows.zsh --help
#
# 在 Windows 上安裝以 MSVC 建置的 GTK 4，使 GtkBackend 得以在該平台建置。
#
# The ABI is the whole point. Swift on Windows targets the MSVC ABI, and MSYS2's
# GTK 4 is built with MinGW, whose import libraries do not link cleanly into
# MSVC binaries. gvsbuild publishes GTK 4 built with MSVC, which is why the
# bundle comes from there rather than from a package manager.
#
# Source and licensing: https://github.com/wingtk/gvsbuild, recorded in
# Acknowledgements/gvsbuild/README.md. Nothing is vendored into this repository;
# the bundle is fetched at install time and lives outside the source tree.
# 來源與授權：https://github.com/wingtk/gvsbuild ，記錄於
# Acknowledgements/gvsbuild/README.md。本 repository 不內含任何相關檔案；套件於安裝時
# 取得，且存放於原始碼樹之外。
# 重點在 ABI。Swift on Windows 以 MSVC ABI 為目標，而 MSYS2 的 GTK 4 是 MinGW 建置，
# 其 import library 無法乾淨地連結進 MSVC 二進位檔。gvsbuild 提供的是 MSVC 建置的
# GTK 4，這就是本腳本從該處取得套件、而非使用套件管理員的原因。
#
# Why this matters here: building the WinUI backend pulls in WinAppSDK, which
# dominates compile time. Measured on this machine, P6 takes 95-103s to build on
# Windows against WinUIBackend and 13-22s in WSL against GtkBackend. With GTK 4
# present, `canImport(GtkBackend)` succeeds and DefaultBackend already prefers
# it over WinUIBackend, so no source change is needed to switch.
# 為何在此專案重要：建置 WinUI backend 會帶入 WinAppSDK，而它主導了編譯時間。本機實測：
# P6 在 Windows 上以 WinUIBackend 建置需 95-103 秒，在 WSL 上以 GtkBackend 建置僅需
# 13-22 秒。裝好 GTK 4 之後 `canImport(GtkBackend)` 即成立，而 DefaultBackend 本來就
# 把它排在 WinUIBackend 之前，因此無需改動任何原始碼即可切換。

set -euo pipefail

# A patch file was considered for the .pc rewriting and rejected on measurement.
# Because the CR removal touches every line of every file, a unified diff of the
# change is 8397 lines and 382 KB across all 302 files -- almost entirely line
# endings, and pinned to one gvsbuild release. Nobody reviews that, and a
# version bump silently invalidates it. The transformation below is two rules
# that hold for any release, and `--show-changes` gives the same auditability
# without shipping the noise.
# 曾考慮以 patch 檔處理 .pc 的改寫，實測後放棄。由於移除 CR 會動到每個檔案的每一行，
# 該變更的 unified diff 在 302 個檔案上共 8397 行、382 KB，其中絕大部分是行尾差異，
# 且鎖定於單一 gvsbuild 發行版。這種內容沒有人會審，而版本一旦更新即靜默失效。下方的
# 轉換只有兩條規則、適用於任何發行版，而 `--show-changes` 能提供同等的可稽核性，
# 且不必附帶那些雜訊。

script_path="${0:a}"
prefix="C:/gtk4"
version="2026.8.0"
show_changes=0

usage() {
    sed -n '2,8p' "$script_path" | sed 's/^# \{0,1\}//'
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --prefix)
            [ "$#" -ge 2 ] || { printf -- '--prefix needs a path\n' >&2; exit 64; }
            prefix="$2"; shift 2 ;;
        --version)
            [ "$#" -ge 2 ] || { printf -- '--version needs a value\n' >&2; exit 64; }
            version="$2"; shift 2 ;;
        --show-changes) show_changes=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 64 ;;
    esac
done

archive="GTK4_Gvsbuild_${version}_x64.zip"
url="https://github.com/wingtk/gvsbuild/releases/download/${version}/${archive}"

# An explicit drive-letter path, never /tmp. Each POSIX-ish toolset on this
# machine maps `/` to its own installation root -- zsh to
# C:/Users/<user>/scoop/apps/zsh/<version>/ and Git to
# C:/Users/<user>/scoop/apps/git/<version>/ -- so `/tmp` names two different
# real directories depending on which binary reads it. Measured: curl wrote the
# 286 MB archive into zsh's tree and unzip then reported it could not find the
# file, after a completed download. A drive letter is unambiguous to every tool.
# 使用明確的磁碟機路徑，絕不用 /tmp。本機每一套類 POSIX 工具鏈都把 `/` 對應到自己的
# 安裝根目錄——zsh 對應 C:/Users/<user>/scoop/apps/zsh/<版本>/，Git 對應
# C:/Users/<user>/scoop/apps/git/<版本>/——因此 `/tmp` 依讀取它的執行檔不同而指向兩個
# 不同的實體目錄。實測：curl 把 286 MB 的檔案寫進 zsh 的目錄樹，而 unzip 在下載已完成
# 的情況下回報找不到檔案。磁碟機路徑對每個工具都沒有歧義。
work="${GTK4_DOWNLOAD_DIR:-C:/gtk4-download}"

printf '==> GTK 4 %s -> %s\n' "$version" "$prefix"

if [ -f "$prefix/lib/pkgconfig/gtk4.pc" ]; then
    printf '    already installed\n'
else
    mkdir -p "$work"
    if [ ! -s "$work/$archive" ]; then
        printf '==> Downloading (about 286 MB)\n'
        curl -fL --progress-bar -o "$work/$archive" "$url"
    fi

    printf '==> Extracting\n'
    mkdir -p "$prefix"
    # The bundle unpacks as bin/, lib/, include/ at the top level, so it goes
    # straight into the prefix.
    # 套件解壓後頂層即為 bin/、lib/、include/，因此直接解到 prefix。
    unzip -q -o "$work/$archive" -d "$prefix"
fi

if [ ! -f "$prefix/lib/pkgconfig/gtk4.pc" ]; then
    printf 'gtk4.pc not found under %s/lib/pkgconfig after extraction.\n' "$prefix" >&2
    printf 'The archive layout may have changed; inspect %s\n' "$prefix" >&2
    exit 1
fi

# The bundle is not relocatable as shipped. Every .pc file carries the prefix of
# the machine gvsbuild built on -- C:/gtk-build/gtk/x64/release -- so unless it
# is rewritten, pkg-config reports include and library paths that do not exist
# here and the build fails with `'gtk/gtk.h' file not found`. Measured on this
# release: 301 of 302 .pc files hardcode it.
#
# The prefix is rewritten to `${pcfiledir}/../..` rather than to an absolute
# path, and that detail is the whole reason this works. SwiftPM parses .pc files
# itself instead of shelling out to pkg-config.exe, and its parser splits
# keyword lines on the first colon -- so `prefix=C:/gtk4` is read as the keyword
# `prefix=C` with value `/gtk4`, the variable `prefix` is never defined, and it
# reports `Expected a value for variable 'prefix'`. A Windows drive letter in
# any variable value hits this. The relocatable form contains no colon, so it
# parses, and it resolves to wherever the bundle actually sits.
#
# The .pc files also arrive with CRLF endings, which go at the same time. `tr -d`
# is used rather than dos2unix because it removes CR and touches nothing else;
# dos2unix silently strips a UTF-8 BOM as well.
# 套件在出廠狀態下無法重新定位。每個 .pc 檔都帶著 gvsbuild 建置機器的 prefix——
# C:/gtk-build/gtk/x64/release——若不改寫，pkg-config 會回報此處不存在的 include 與
# library 路徑，建置便以 `'gtk/gtk.h' file not found` 失敗。本次發行版實測：302 個 .pc
# 檔中有 301 個硬編碼該路徑。
#
# 這些 .pc 檔同時使用 CRLF 行尾。SwiftPM 自行解析 .pc 而非呼叫 pkg-config.exe，其解析器
# 對此回報 `Expected a value for variable 'prefix'`，因此一併移除 CR。此處使用 `tr -d`
# 而非 dos2unix，因為前者只移除 CR、不動其他任何位元組；dos2unix 會連 UTF-8 BOM 一起
# 靜默刪除。
printf '\n==> Making .pc files relocatable\n'
built_prefix="C:/gtk-build/gtk/x64/release"
rewritten=0

# Two separate concerns, deliberately not mixed.
#
# The line endings go first, with one `tr` across every file. They have to be
# first rather than last, even though doing them last would keep the patch
# closer to the shipped bytes: MSYS tools read in text mode and drop CR whether
# asked to or not. Measured -- a `sed -i` that only touched the prefix line took
# gtk4.pc from 14 CR bytes to 0. So nothing downstream can preserve CRLF, and
# normalising up front is the only order that leaves the patch applying to
# content that actually matches.
#
# The path substitutions then come from a checked-in patch rather than more
# in-line substitution, so the change is reviewable as a diff. Keeping CR out of
# it is what makes that worthwhile: with line endings in the same step the diff
# was 8397 lines, because every line of every file differed. Separated, it is
# 2745, of which roughly 600 are real changes and the rest is 302 files' worth
# of headers.
# 兩件事刻意分開處理。
#
# 行尾先處理，以單一 `tr` 掃過所有檔案。必須放在最前而非最後——儘管放最後能讓 patch
# 更貼近套件出廠的位元組：MSYS 工具以文字模式讀檔，無論是否要求都會丟棄 CR。實測：一個
# 只改 prefix 那一行的 `sed -i`，就讓 gtk4.pc 的 CR 從 14 個變成 0 個。因此下游沒有任何
# 環節能保留 CRLF，先行正規化是唯一能讓 patch 套用在「內容真的相符」之上的順序。
#
# 路徑替換則改由簽入的 patch 提供，而非繼續用行內替換，使該變更能以 diff 形式被審閱。
# 把 CR 排除在外正是這麼做的價值所在：若與行尾同一步處理，diff 會是 8397 行，因為每個
# 檔案的每一行都不同；分開之後是 2745 行，其中約 600 行是實際變更，其餘為 302 個檔案的
# 標頭。
patch_file="${script_path:h}/patches/gtk4-pkgconfig-relocate.patch"

printf '    normalising line endings\n'
for pc in "$prefix"/lib/pkgconfig/*.pc; do
    tr -d '\r' < "$pc" > "$pc.tmp" && mv "$pc.tmp" "$pc"
done

if [ "$show_changes" -eq 1 ]; then
    printf '    the patch changes these lines:\n'
    grep -E '^[+-](prefix=|.*gtk-build)' "$patch_file" | head -12 | sed 's/^/      /'
    printf '      ... (%s lines total)\n' "$(wc -l < "$patch_file")"
fi
if [ -f "$patch_file" ] \
    && (cd "$prefix/lib/pkgconfig" && patch -p1 --forward --silent < "$patch_file") 2>/dev/null; then
    rewritten="$(grep -c '^diff ' "$patch_file")"
    printf '    patch applied to %s files\n' "$rewritten"
else
    # The patch is generated from one gvsbuild release, so a different one will
    # not match. Falling back keeps the installer working across versions; the
    # two rules are the same ones the patch encodes. `${prefix}` is substituted
    # rather than the real path for the parser reason above: it has no colon.
    # 該 patch 由單一 gvsbuild 發行版產生，換一個版本便無法相符。此處退回以規則處理，
    # 使安裝程式跨版本仍可運作；這兩條規則與 patch 所編碼的完全相同。此處代入
    # `${prefix}` 而非真實路徑，理由同上：它不含冒號。
    printf '    patch did not apply; falling back to substitution\n' >&2
    printf '    (expected when the gvsbuild version differs from the patch)\n' >&2
    for pc in "$prefix"/lib/pkgconfig/*.pc; do
        sed -e 's|^prefix=.*|prefix=${pcfiledir}/../..|' \
            -e "s|$built_prefix|\${prefix}|g" "$pc" > "$pc.tmp"
        mv "$pc.tmp" "$pc"
        rewritten=$((rewritten + 1))
    done
    printf '    %s files rewritten\n' "$rewritten"
fi

if grep -rq "$built_prefix" "$prefix/lib/pkgconfig/" 2>/dev/null; then
    printf 'Some .pc files still reference %s after rewriting.\n' "$built_prefix" >&2
    grep -rl "$built_prefix" "$prefix/lib/pkgconfig/" 2>/dev/null | head -3 >&2
    exit 1
fi

# Checked with the bundle's own pkg-config, which is the reference for whether
# the rewrite produced something valid at all. SwiftPM's parser is stricter, but
# a file this one rejects is broken for everyone.
# 以套件自帶的 pkg-config 檢查，它是「改寫後是否仍然有效」的基準。SwiftPM 的解析器更
# 嚴格，但連這一支都拒絕的檔案，對任何工具都是壞的。
if [ -x "$prefix/bin/pkg-config.exe" ]; then
    reported="$(PKG_CONFIG_PATH="$prefix/lib/pkgconfig" "$prefix/bin/pkg-config.exe" --modversion gtk4 2>&1)"
    printf '    pkg-config reports gtk4 %s\n' "$reported"
fi

printf '\n==> Installed\n'
printf '    gtk4.pc : %s/lib/pkgconfig/gtk4.pc\n' "$prefix"

# pkg-config has to be told where to look, and the DLLs have to be on PATH at
# run time. These are printed rather than written to a profile, because which
# shell and which profile is the caller's business.
# 必須告訴 pkg-config 到何處尋找，且執行期 DLL 必須位於 PATH。此處只列印而不寫入任何
# profile，因為要用哪個 shell、哪個 profile 是呼叫端的決定。
printf '\n==> Add these to your environment before building:\n'
printf "    export PKG_CONFIG_PATH='%s/lib/pkgconfig'\n" "$prefix"
printf "    export PATH=\"%s/bin:\$PATH\"\n" "$prefix"

# SwiftPM does not apply a systemLibrary's pkgConfig cflags on Windows. Measured:
# the clang invocation for GtkCHelpers carried only its own include directory and
# nothing from gtk4.pc, so the build failed with `'gtk/gtk.h' file not found`
# even with PKG_CONFIG_PATH set and pkg-config reporting the right flags. Passing
# the same -I flags through -Xcc builds it. That is why the command below is not
# a plain `swift build`.
# SwiftPM 在 Windows 上不會套用 systemLibrary 的 pkgConfig cflags。實測：GtkCHelpers 的
# clang 呼叫只帶了自己的 include 目錄，gtk4.pc 的內容一項也沒有，因此即使已設定
# PKG_CONFIG_PATH 且 pkg-config 回報正確的 flags，建置仍以 `'gtk/gtk.h' file not found`
# 失敗。將同一批 -I 經由 -Xcc 傳入即可建置成功。這就是下方指令並非單純
# `swift build` 的原因。
printf '\n==> Build with the include flags passed explicitly:\n'
printf '    cflags=()\n'
printf "    for f in \$(%s/bin/pkg-config.exe --cflags gtk4); do\n" "$prefix"
printf '        case "$f" in -I*) cflags+=(-Xcc "$f") ;; esac\n'
printf '    done\n'
printf '    swift build --target GtkBackend "${cflags[@]}"\n'
printf '\n    SwiftPM does not apply pkgConfig cflags on Windows, so a plain\n'
printf '    `swift build` fails with '"'"'gtk/gtk.h'"'"' file not found.\n'
