#!/usr/bin/env zsh
# One dry-run of P8: build, launch, wait until it has actually rendered,
# screenshot, close, and print the geometry it measured.
#
#   zsh testapp/test_p8.zsh              # WSLg / GtkBackend
#   zsh testapp/test_p8.zsh --windows    # Windows / WinUIBackend comparison
#   zsh testapp/test_p8.zsh --both       # WSLg first, then Windows
#   zsh testapp/test_p8.zsh -n           # skip the build, just run
#   zsh testapp/test_p8.zsh --showtime 60 # keep the window open 60s after render
#
# P8 covers GTK scroll-view issues, so WSLg is the default. The Windows path is
# only a comparison/control. Like test_p7.zsh, this waits for the app's own
# render marker instead of sleeping for a guessed duration.

set -euo pipefail

script_dir="${0:a:h}"
script_path="${0:a}"
app="P8"
title="P8 scroll views"
log_name="p8-debug-events.log"
marker="RENDER COMPLETE"
timeout_seconds=30
showtime_seconds=30
target="wsl"
do_build=1
summary_pattern='(cornerScroll|redChild|outerScroll|innerStrip|RENDER COMPLETE)'

usage() {
    sed -n '2,8p' "$script_path" | sed 's/^# \{0,1\}//'
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        -w|--wsl) target="wsl"; shift ;;
        --windows) target="windows"; shift ;;
        -b|--both) target="both"; shift ;;
        -n|--no-build) do_build=0; shift ;;
        --showtime)
            if [ "$#" -gt 1 ] && [[ "$2" == <-> ]]; then
                showtime_seconds="$2"
                shift 2
            else
                showtime_seconds=30
                shift
            fi
            ;;
        --showtime=*)
            showtime_seconds="${1#*=}"
            if ! [[ "$showtime_seconds" == <-> ]]; then
                printf 'Invalid --showtime value: %s\n' "$showtime_seconds" >&2
                exit 64
            fi
            shift
            ;;
        --no-showtime) showtime_seconds=0; shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 64 ;;
    esac
done

showtime() {
    local label="$1"

    if [ "$showtime_seconds" -le 0 ]; then
        return 0
    fi

    printf '==> Showtime: keeping %s open for %ss after render\n' "$label" "$showtime_seconds"
    printf '    You can inspect or interact with the window now; final screenshot follows.\n'
    sleep "$showtime_seconds"
}

kill_existing() {
    printf '==> Closing any running %s\n' "$app"

    if MSYS2_ARG_CONV_EXCL='*' tasklist.exe /NH /FI "IMAGENAME eq $app.exe" 2>/dev/null \
        | grep -qi "$app.exe"; then
        MSYS2_ARG_CONV_EXCL='*' taskkill.exe /F /IM "$app.exe" >/dev/null 2>&1 || true
    fi
    if MSYS2_ARG_CONV_EXCL='*' tasklist.exe /NH /FI "IMAGENAME eq $app.exe" 2>/dev/null \
        | grep -qi "$app.exe"; then
        printf '    WARNING: %s.exe is still running on Windows\n' "$app"
    else
        printf '    Windows: clear\n'
    fi

    MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu -- zsh -lc \
        "pkill -x $app 2>/dev/null; sleep 1; pgrep -ax $app || printf '    WSLg: clear\n'" \
        2>/dev/null || true
}

wait_for_marker_windows() {
    local out="$1"
    local waited=0

    printf '==> Waiting for "%s"' "$marker"
    while [ "$waited" -lt "$timeout_seconds" ]; do
        if [ -f "$out/$log_name" ] && grep -q "$marker" "$out/$log_name" 2>/dev/null; then
            printf ' -- rendered after %ss\n' "$waited"
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
        printf '.'
    done

    printf '\n==> Timed out after %ss\n' "$timeout_seconds"
    return 1
}

wait_for_marker_wsl() {
    local waited=0

    printf '==> Waiting for "%s"' "$marker"
    while [ "$waited" -lt "$timeout_seconds" ]; do
        if MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu -- zsh -lc \
            "grep -q '$marker' ~/proj/swift-cross-ui/testapp/output/$log_name 2>/dev/null"; then
            printf ' -- rendered after %ss\n' "$waited"
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
        printf '.'
    done

    printf '\n==> Timed out after %ss\n' "$timeout_seconds"
    return 1
}

print_summary_windows() {
    local out="$script_dir/output"

    printf '\n==> Windows P8 geometry\n'
    grep -hE "$summary_pattern" "$out/$log_name" 2>/dev/null \
        | sed 's/^P8 [0-9-]* [0-9:]* +0000 //' | sort -u || true
}

print_summary_wsl() {
    printf '\n==> WSLg P8 geometry\n'
    MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu -- zsh -lc \
        "cd ~/proj/swift-cross-ui/testapp/output && grep -hE '$summary_pattern' $log_name 2>/dev/null | sed 's/^P8 [0-9-]* [0-9:]* +0000 //' | sort -u" || true
}

run_windows() {
    local out="$script_dir/output"

    if [ "$do_build" -eq 1 ]; then
        printf '==> Building %s for Windows\n' "$app"
        zsh "$script_dir/compile.zsh" "$app" | grep -E 'error:|Build of product' || true
    fi

    : > "$out/$log_name"
    printf '==> Launching %s.exe\n' "$app"
    ( cd "$out" && "./$app.exe" --debug >/dev/null 2>&1 & )

    zsh "$script_dir/screenshot.zsh" -d 1 -w "$title" p8-windows-1s || true
    if wait_for_marker_windows "$out"; then
        showtime "Windows P8"
        zsh "$script_dir/screenshot.zsh" -d 1 -w "$title" p8-windows-final || true
    else
        zsh "$script_dir/screenshot.zsh" -d 0 -w "$title" p8-windows-timeout || true
    fi

    if MSYS2_ARG_CONV_EXCL='*' taskkill.exe /F /IM "$app.exe" 2>&1 | grep -q SUCCESS; then
        printf '==> Closed %s.exe\n' "$app"
    else
        printf '==> WARNING: %s.exe may still be running; check with tasklist\n' "$app"
    fi

    print_summary_windows
}

run_wsl() {
    if [ "$do_build" -eq 1 ]; then
        printf '==> Syncing sources to WSL\n'
        zsh "$script_dir/rsync_WSL.zsh" >/dev/null
        printf '==> Building %s for WSLg\n' "$app"
        MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu -- zsh -lc \
            "cd ~/proj/swift-cross-ui && zsh testapp/compile.zsh $app 2>&1 | grep -E 'error:|Build of product'" || true
    fi

    MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu -- zsh -lc \
        "cd ~/proj/swift-cross-ui/testapp/output && : > $log_name"

    printf '==> Launching %s under WSLg\n' "$app"
    MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu -- zsh -lc \
        "cd ~/proj/swift-cross-ui/testapp/output && ./$app --debug >/dev/null 2>&1" \
        >/dev/null 2>&1 &
    disown 2>/dev/null || true

    zsh "$script_dir/screenshot.zsh" -d 1 -w "$title" p8-wslg-1s || true
    if wait_for_marker_wsl; then
        showtime "WSLg P8"
        zsh "$script_dir/screenshot.zsh" -d 1 -w "$title" p8-wslg-final || true
    else
        zsh "$script_dir/screenshot.zsh" -d 0 -w "$title" p8-wslg-timeout || true
    fi

    MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu -- zsh -lc "pkill -x '$app' 2>/dev/null" || true
    printf '==> Closed %s under WSLg\n' "$app"
    print_summary_wsl
}

kill_existing

case "$target" in
    wsl) run_wsl ;;
    windows) run_windows ;;
    both) run_wsl; printf '\n'; run_windows ;;
esac
