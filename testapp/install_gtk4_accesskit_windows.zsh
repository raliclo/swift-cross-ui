#!/usr/bin/env zsh
# Builds GTK 4.22.4 with the ACCESSKIT backend on Windows, into its own prefix,
# because no published binary has it and without it GtkBackend has no
# accessibility on this platform at all.
#
#   zsh testapp/install_gtk4_accesskit_windows.zsh --source C:/path/to/gtk-4.22.4
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
#
# WHAT IT BUILDS. Only GTK. Its dependencies come from the bundle already in
# C:/gtk4 through pkgconf, and nothing is written into that bundle: the result
# goes to a separate prefix, so a broken build cannot take the working one down.
# Point an app at it with PATH=C:/gtk4-accesskit/bin;C:/gtk4/bin;...
#
# 在 Windows 上建置**啟用 AccessKit** 的 GTK 4.22.4,安裝到獨立前綴——因為沒有任何已發布的二進位檔
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
    printf 'Give --source <dir>, a GTK 4.22.4 source tree (meson.build at its root).\n' >&2
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

printf 'configuring %s -> %s\n' "$source_dir" "$prefix"
python -m mesonbuild.mesonmain setup "$build" "$source_dir" \
    --prefix "$prefix" --buildtype release \
    -Dintrospection=disabled -Dbuild-tests=false -Dbuild-testsuite=false \
    -Dbuild-demos=false -Dbuild-examples=false \
    -Dmedia-gstreamer=disabled -Dvulkan=disabled \
    -Dsysprof=disabled -Dglib:sysprof=disabled \
    -Dx11-backend=false -Dwayland-backend=false -Dwin32-backend=true \
    -Daccesskit=enabled -Daccesskit-c:triplet=x86_64-pc-windows-msvc \
    -Dc_args=-D_USE_MATH_DEFINES \
    -Df16c=disabled

# `-D_USE_MATH_DEFINES`: GTK adds it only for `cc.get_id() == 'msvc'`, so
# clang-cl misses it and gsk fails on `M_LN2`.
# `-Df16c=disabled`: the F16C fast path uses GNU ifunc attributes, which do not
# exist in COFF, so the link fails on `half_to_float` / `float_to_half`.
# 前者:GTK 只為 msvc 加上該定義,clang-cl 會漏掉而死在 `M_LN2`。後者:F16C 快路徑用 GNU ifunc,COFF 沒有它,
# 連結會死在 `half_to_float`。

ninja -C "$build"
python -m mesonbuild.mesonmain install -C "$build"

printf '\nInstalled. To use it, put its bin FIRST:\n'
printf '    PATH="%s/bin:%s/bin:$PATH" ./P69-gtk4.exe\n' "$(cygpath -u "$prefix")" "$bundle_unix"
printf 'Check with: GTK_A11Y=help <app>  -- it must say "accesskit - Use the AccessKit accessibility backend".\n'
