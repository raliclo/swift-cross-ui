#!/usr/bin/env zsh
# Builds GTK 4.24.1 with the ACCESSKIT backend on Windows, into its own prefix,
# because no published binary has it and without it GtkBackend has no
# accessibility on this platform at all.
#
#   zsh testapp/install_gtk4_accesskit_windows.zsh --source testapp/gtk4-source
#   zsh testapp/install_gtk4_accesskit_windows.zsh --prefix C:/gtk4-accesskit --build C:/gtk4-akbuild
#   zsh testapp/install_gtk4_accesskit_windows.zsh --help
#
# WHY IT EXISTS. `GTK_A11Y=help` on the gvsbuild bundle that
# install_gtk4_windows.zsh fetches prints `accesskit - Disabled during GTK
# build` and `atspi - Not available on this platform`, and an out-of-process UIA
# dump of any app then holds ONE node: the window. Checked 2026-09-17 against
# gvsbuild 2026.8.0, MSYS2 4.24.0, conda-forge 4.22.5 and vcpkg 4.22.5 -- none
# enable it. GTK's own MSVC CI does (`.gitlab-ci/test-msvc.bat`) but keeps only
# logs.
# Rechecked 2026-10-29: gvsbuild 2026.10.0 (GTK 4.24.1) still has `accesskit -
# Disabled during GTK build` and no accesskit symbol in gtk-4-1.dll.
# The source used then: testapp/gtk4-source on branch `develop` of
# https://github.com/raliclo/gtk -- 4.24.1 plus a fix for the touch-device
# use-after-free (todo-Gtk.md) -- with `--source testapp/gtk4-source`.
# 2026-10-29 重查:gvsbuild 2026.10.0(GTK 4.24.1)仍是 `accesskit - Disabled during GTK build`,gtk-4-1.dll 裡沒有
# 任何 accesskit 符號。當時所用的原始碼:testapp/gtk4-source,位於 https://github.com/raliclo/gtk 的 `develop`
# 分支——4.24.1 加上觸控裝置 use-after-free 的修正(todo-Gtk.md)。
#
# WHAT IT BUILDS. Only GTK. Its dependencies come from the bundle already in
# C:/gtk4 through pkgconf, and nothing is written into that bundle: the result
# goes to a separate prefix, so a broken build cannot take the working one down.
# Point an app at it with PATH=C:/gtk4-accesskit/bin;C:/gtk4/bin;...
#
# 在 Windows 上建置**啟用 AccessKit** 的 GTK 4.24.1,安裝到獨立前綴——因為沒有任何已發布的二進位檔
# 開啟它,而少了它,GtkBackend 在這個平台上完全沒有無障礙支援。
#
# 只建 GTK 本身:依賴取自 C:/gtk4 既有的 bundle(經 pkgconf),且不寫入該 bundle。
set -euo pipefail

script_path="${0:A}"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    sed -n '2,30p' "$script_path" | sed 's/^# \{0,1\}//'
    exit 0
fi

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) ;;
    *)
        printf 'install_gtk4_accesskit_windows.zsh: Windows only (uname -s = %s)\n' "$(uname -s)" >&2
        exit 2
        ;;
esac

source_dir="${SCUI_GTK_SOURCE:-}"
prefix='C:\gtk4-accesskit'
build='C:\gtk4-akbuild'
bundle='C:\gtk4'

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source) source_dir="$2"; shift 2 ;;
        --prefix) prefix="$2"; shift 2 ;;
        --build) build="$2"; shift 2 ;;
        --bundle) bundle="$2"; shift 2 ;;
        *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
done

if [[ -z "$source_dir" ]]; then
    printf 'Give --source <dir>, a GTK 4.24.1 source tree (meson.build at its root).\n' >&2
    exit 2
fi

# The tools, and the three things that each cost a build before they were
# understood.
#
# 1. MSVC's environment is set by vcvars64.bat, which only affects the cmd
#    process it runs in, so it is dumped once and read here. Its path is taken
#    in 8.3 form: Git Bash escapes the quotes a path with spaces needs, and cmd
#    then reports `'\"C:\Program Files\...\"' is not recognized`.
# 2. pkgconf from the bundle, not the pkg-config on PATH. That one splits its
#    search path on ':', so `C:/gtk4/...` becomes `C` plus `/gtk4/...`, every .pc
#    goes missing, and meson silently falls through to the wrap subprojects and
#    dies on `glib-2.0 ... found 2.84.0 but need >= 2.88`.
# 3. C:/gtk4/bin on PATH for the bundle's TOOLS, not only its DLLs. Without it
#    meson cannot find `glib-compile-resources`, falls back to the glib
#    subproject to supply the program, and that subproject then tries to
#    override a glib-2.0 pkgconf has already resolved.
#
# 1. vcvars64.bat 只在它自己的 cmd 行程內生效,因此 dump 一次再讀進來;路徑取 8.3 短檔名(Git Bash 會把
#    含空白路徑所需的引號跳脫掉)。2. 用 bundle 自帶的 pkgconf,而非 PATH 上那支會以 ':' 切分搜尋路徑的
#    pkg-config。3. 把 C:/gtk4/bin 放進 PATH 以取得 bundle 的**工具**。
vcvars=$(cygpath -d 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat' 2>/dev/null || true)
if [[ -z "$vcvars" ]]; then
    printf 'Visual Studio 2022 Community with the C++ toolset is required.\n' >&2
    exit 3
fi
env_dump="${TMPDIR:-/tmp}/scui-msvc-env.txt"
cmd.exe //c "call $vcvars && set" > "$env_dump" 2>/dev/null

for name in INCLUDE LIB LIBPATH; do
    value=$(grep -i "^${name}=" "$env_dump" | head -1 | cut -d= -f2- || true)
    [[ -n "$value" ]] && export $name="${value%$'\r'}"
done
win_path=$(grep -i '^Path=' "$env_dump" | head -1 | cut -d= -f2-)
converted=$(printf '%s' "${win_path%$'\r'}" | tr ';' '\n' | while read -r entry; do
    [[ -z "$entry" ]] && continue
    cygpath -u "$entry" 2>/dev/null || true
done | paste -sd: -)

bundle_unix=$(cygpath -u "$bundle")
export PATH="${bundle_unix}/bin:$HOME/.cargo/bin:${converted}:$PATH"
# The bundle's lib directory for the LINKER: several of its .pc files still name
# the machine gvsbuild built them on (`C:/gtk-build/...`), so `-ljpeg` arrives as
# `jpeg.lib` with nowhere to find it.
# bundle 的 lib 目錄要給**連結器**:它有數個 .pc 仍寫著 gvsbuild 當初的建置機器路徑。
export LIB="${bundle}\\lib;${LIB:-}"
export PKG_CONFIG="${bundle}\\bin\\pkgconf.exe"
export PKG_CONFIG_PATH="${bundle}\\lib\\pkgconfig"

# clang-cl, not cl. MSVC 19.44 dies compiling GTK's generated resource blob --
# `gtk/gtkresources.c(78895): fatal error C1060: compiler is out of heap space`
# on a 7.3 MB, 104k-line file, with 19 GB free and the 64-bit hosted compiler.
# Ruled out first: ccache, `-Zc:preprocessor`, and the optimisation level.
# clang-cl 23.1 compiles the same file with the same flags in seconds, and both
# target x86_64-pc-windows-msvc, which is the ABI Swift and the bundle use.
# 用 clang-cl 而非 cl:MSVC 19.44 編 GTK 產生的資源大檔時直接 C1060(已先排除 ccache、
# `-Zc:preprocessor` 與最佳化等級);clang-cl 數秒編完,且兩者 ABI 相同。
export CC=clang-cl
export CXX=clang-cl

# GTK's <tgmath.h> users (4.24.1: gsk/gskturbulencenode.c, gtk/svg/*) do not
# build with clang-cl against the MSVC CRT: clang's tgmath.h passes
# `_Complex float` where the CRT declares `_Fcomplex` (`tgmath.h(72,50): error:
# passing '_Complex float' to parameter of incompatible type '_Fcomplex'`). They
# use the type-generic names on real numbers only, so a tgmath.h that is just
# <math.h>, found first through -I, builds them unchanged. Until 2026-10-29 this
# was an edit to gtk/gtksvg.c inside the source tree, recorded nowhere else.
# GTK 中用到 <tgmath.h> 的檔案無法以 clang-cl 對 MSVC CRT 建置:clang 的 tgmath.h 傳入 `_Complex float`,而 CRT
# 宣告的是 `_Fcomplex`。它們只對實數使用型別泛型名稱，所以一個只 include <math.h> 的 tgmath.h,經 -I 優先找到，
# 就能原封不動地建置。2026-10-29 之前這是對原始碼樹中 gtk/gtksvg.c 的修改，除了那棵樹之外沒有任何紀錄。
shim="$(cygpath -u "$build")-tgmath"
mkdir -p "$shim"
printf '%s\n' '#pragma once' '#include <math.h>' > "$shim/tgmath.h"
shim_win="$(cygpath -m "$shim")"

printf 'configuring %s -> %s\n' "$source_dir" "$prefix"
# A build directory left by a failed run is configured afresh (--wipe) rather
# than refused; meson otherwise stops with "Directory already configured".
# 失敗留下的 build 目錄會從頭重新設定(--wipe)而不是被拒絕；否則 meson 會以「Directory already configured」停下。
reconfigure=()
[[ -f "$(cygpath -u "$build")/build.ninja" ]] && reconfigure=(--wipe)
python -m mesonbuild.mesonmain setup "${reconfigure[@]}" "$build" "$source_dir" \
    --prefix "$prefix" --buildtype release \
    -Dintrospection=disabled -Dbuild-tests=false -Dbuild-testsuite=false \
    -Dbuild-demos=false -Dbuild-examples=false \
    -Dmedia-gstreamer=disabled -Dvulkan=disabled \
    -Dsysprof=disabled -Dglib:sysprof=disabled \
    -Dx11-backend=false -Dwayland-backend=false -Dwin32-backend=true \
    -Daccesskit=enabled -Daccesskit-c:triplet=x86_64-pc-windows-msvc \
    "-Dc_args=['-D_USE_MATH_DEFINES','-I${shim_win}']" \
    -Df16c=disabled \
    -Dlibsass:cpp_std=c++17

# `-D_USE_MATH_DEFINES`: GTK adds it only for `cc.get_id() == 'msvc'`, so
# clang-cl misses it and gsk fails on `M_LN2`.
# `-Df16c=disabled`: the F16C fast path uses GNU ifunc attributes, which do not
# exist in COFF, so the link fails on `half_to_float` / `float_to_half`.
# `-Dlibsass:cpp_std=c++17`: a git checkout builds its theme with sassc, from
# the libsass subproject, which asks for C++11; the STL of MSVC 14.44.35207
# then fails in __msvc_bit_utils.hpp with "statement not allowed in constexpr
# function" (2026-10-29).
# 前者:GTK 只為 msvc 加上該定義,clang-cl 會漏掉而死在 `M_LN2`。後者:F16C 快路徑用 GNU ifunc,COFF 沒有它,
# 連結會死在 `half_to_float`。最後一項:git checkout 以 sassc 建置主題,來自要求 C++11 的 libsass 子專案;
# MSVC 14.44.35207 的 STL 於是在 __msvc_bit_utils.hpp 失敗(「statement not allowed in constexpr function」,2026-10-29)。

ninja -C "$build"
python -m mesonbuild.mesonmain install -C "$build"

printf '\nInstalled. To use it, put its bin FIRST:\n'
printf '    PATH="%s/bin:%s/bin:$PATH" ./P69-gtk4.exe\n' "$(cygpath -u "$prefix")" "$bundle_unix"
printf 'Check with: GTK_A11Y=help <app>  -- it must say "accesskit - Use the AccessKit accessibility backend".\n'
