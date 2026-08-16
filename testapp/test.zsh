#!/usr/bin/env zsh
# Loader for one-file-per-test UI dry-runs.
#
# Examples:
#   zsh testapp/test.zsh P8 --both
#   zsh testapp/test.zsh P8 --both --showtime 60
#   zsh testapp/test.zsh P7 --wsl -n

set -euo pipefail

script_dir="${0:a:h}"

usage() {
    cat <<EOF_USAGE
Usage: test.zsh <P0..P17> [test options]

Examples:
  zsh testapp/test.zsh P8 --both
  zsh testapp/test.zsh P8 --both --showtime 60
  zsh testapp/test.zsh P7 --wsl -n

Single-test scripts live in testapp/test_support/test_Pn.zsh.
EOF_USAGE
}

if [ "$#" -eq 0 ]; then
    usage >&2
    exit 64
fi

test_name="$1"
shift

case "$test_name" in
    p*) test_name="${test_name:u}" ;;
esac

case "$test_name" in
    P<0-9>|P1<0-7>) ;;
    *)
        printf 'Unknown test: %s\n' "$test_name" >&2
        usage >&2
        exit 64
        ;;
esac

test_script="$script_dir/test_support/test_${test_name}.zsh"
if [ "$test_name" = "P6" ]; then
    test_script="$script_dir/test_P6.zsh"
fi

if [ ! -f "$test_script" ]; then
    printf 'Missing test script: %s\n' "$test_script" >&2
    exit 1
fi

exec zsh "$test_script" "$@"
