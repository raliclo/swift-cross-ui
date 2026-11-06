#!/usr/bin/env zsh
# record_winui_sizes.zsh -- copy WinUI exe sizes from the build manifest into
# matrix_coverage/executable-size.csv2, through csv2.
# 把 WinUI exe 的大小從 build manifest 複製到 matrix_coverage/executable-size.csv2(經由 csv2)。
#
#   zsh testapp/test_support/record_winui_sizes.zsh P1 P2 ...
#   zsh testapp/test_support/record_winui_sizes.zsh --help
#
# Fills windows_winui_debug_bytes and windows_winui_debug_measured for each app
# whose newest manifest row is a debug build; anything else is reported and
# skipped. The bytes are the manifest's, written after compile.zsh's strip; the
# file on disk is printed beside them so a mismatch is visible.
# 為每支最新 manifest 列是 debug 建置的 app 填入兩欄；其他情況回報並略過。位元組數取自 manifest(strip 之後),
# 旁邊印出磁碟上的檔案大小，不一致時看得出來。
#
# Why it exists (2026-11-06): P1-P40 were built in batches and each batch's exes
# deleted to fit C:, and build-manifest.csv2 is not tracked, so without this copy
# the sizes would be lost with the files.
# 為何存在(2026-11-06):P1-P40 分批建置，每批刪除 exe 以騰出 C: 空間，而 build-manifest.csv2 未被追蹤，
# 不抄過來，大小就隨檔案一起消失。

set -u
script_path="${0:A}"
if [[ "${1:-}" == (-h|--help) || $# -eq 0 ]]; then
    sed -n '2,21p' "$script_path" | sed 's/^# \{0,1\}//'
    exit 0
fi

repo="${script_path:h:h:h}"
manifest="$repo/testapp/output/build-manifest.csv2"
table="$repo/matrix_coverage/executable-size.csv2"
exit_code=0
for app in "$@"; do
    file="$app-WinUI.exe"
    mrow=$(csv2 -contains "$file" --search-column file -i "$manifest" | awk -F: '{print $1}' | tail -1)
    if [ -z "$mrow" ]; then printf '%s: no manifest row\n' "$app"; exit_code=1; continue; fi
    config=$(csv2 -get "$mrow:5" -i "$manifest")
    built=$(csv2 -get "$mrow:7" -i "$manifest")
    bytes=$(csv2 -get "$mrow:8" -i "$manifest")
    disk=$(stat -c %s "$repo/testapp/output/$file" 2>/dev/null || printf gone)
    if [ "$config" != debug ]; then printf '%s: manifest says %s, skipped\n' "$app" "$config"; exit_code=1; continue; fi
    trow=""
    for r in $(csv2 -contains "$app" --search-column app -i "$table" | awk -F: '{print $1}'); do
        [ "$(csv2 -get "$r:1" -i "$table")" = "$app" ] && trow=$r
    done
    if [ -z "$trow" ]; then printf '%s: no row in executable-size.csv2\n' "$app"; exit_code=1; continue; fi
    csv2 -update "$trow:4" "$bytes" -i "$table" --in-place >/dev/null || { exit_code=1; continue; }
    csv2 -update "$trow:5" "${built%%T*}" -i "$table" --in-place >/dev/null || { exit_code=1; continue; }
    printf '%s row %s: %s bytes (disk %s) built %s\n' "$app" "$trow" "$bytes" "$disk" "$built"
done
exit $exit_code
