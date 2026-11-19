#!/usr/bin/env zsh
# Writes a SwiftPM toolset that compiles C and C++ with Visual Studio's clang, and prints its path.
#   zsh testapp/test_support/vs_clang_toolset.zsh OUT.json [MIN_MAJOR]   (MIN_MAJOR defaults to 22)
#   SCUI_SWIFT_TOOLSET=$(zsh testapp/test_support/vs_clang_toolset.zsh t.json) zsh testapp/compile.zsh P2
# MSVC 14.52's STL stops any clang before 22 with STL1000, and Swift 6.4.2 ships clang 21.1.6.
# SwiftPM ignores CC, CXX and PATH for its C/C++ targets; --toolset is what changed the compiler
# (scratch package, 2026-11-19). Fails, rather than writing a file, when the clang is missing or too old.
#
# 寫出讓 SwiftPM 以 Visual Studio 的 clang 編譯 C 與 C++ 的 toolset 檔，並印出其路徑。
#   zsh testapp/test_support/vs_clang_toolset.zsh OUT.json [最低主版本]   (預設 22)
# MSVC 14.52 的 STL 以 STL1000 擋下 22 以前的 clang,而 Swift 6.4.2 附的是 clang 21.1.6。SwiftPM 的 C/C++ target 不理會
# CC、CXX 與 PATH;改變編譯器的是 --toolset(暫存套件實測,2026-11-19)。clang 不存在或太舊時直接失敗，不寫檔。
set -euo pipefail
script_path="${0:A}"
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" || $# -lt 1 ]]; then
    sed -n '2,12p' "$script_path" | sed 's/^# \{0,1\}//'
    [[ $# -ge 1 ]] && exit 0 || exit 64
fi
out=$1 min_major=${2:-22}

vswhere="/c/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe"
[[ -x "$vswhere" ]] || { printf 'no vswhere at %s\n' "$vswhere" >&2; exit 1; }
vs_root="$("$vswhere" -latest -products '*' -property installationPath | tr -d '\r' | head -n 1)"
[[ -n "$vs_root" ]] || { printf 'vswhere found no Visual Studio\n' >&2; exit 1; }
bin_dir="$(cygpath -u "$vs_root")/VC/Tools/Llvm/x64/bin"
[[ -x "$bin_dir/clang.exe" ]] || { printf 'no clang in %s (component VC.Llvm.Clang)\n' "$bin_dir" >&2; exit 1; }

version="$("$bin_dir/clang.exe" --version | head -n 1)"
major="$(printf '%s\n' "$version" | sed -nE 's/.*clang version ([0-9]+)\..*/\1/p')"
printf 'Visual Studio clang: %s\n' "$version" >&2
[[ -n "$major" && "$major" -ge "$min_major" ]] || { printf 'clang %s is older than %s\n' "${major:-?}" "$min_major" >&2; exit 1; }

clang_path="$(cygpath -m "$bin_dir/clang.exe")"
clangxx_path="$(cygpath -m "$bin_dir/clang++.exe")"
printf '{\n  "schemaVersion": "1.0",\n  "cCompiler": { "path": "%s" },\n  "cxxCompiler": { "path": "%s" }\n}\n' \
    "$clang_path" "$clangxx_path" > "$out"
cygpath -m "${out:A}"
