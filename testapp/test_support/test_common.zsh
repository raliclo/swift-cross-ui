#!/usr/bin/env zsh
# Shared GUI dry-run helper for test_P*.zsh wrappers.
#
# The flow intentionally matches test_P8.zsh: build, launch, take an early
# screenshot, optionally wait for an app render marker, keep the window open for
# tester collaboration, take a final screenshot, close, and print diagnostics.

set -euo pipefail

support_dir="${0:a:h}"
script_dir="${support_dir:h}"
script_path="${0:a}"
app="${TEST_APP:?TEST_APP is required}"
title="${TEST_TITLE:-$app}"
log_name="${TEST_LOG_NAME:-${app:l}-debug-events.log}"
marker="${TEST_MARKER:-}"
timeout_seconds="${TEST_TIMEOUT_SECONDS:-30}"
showtime_seconds="${TEST_SHOWTIME_SECONDS:-30}"
target="${TEST_TARGET:-wsl}"
do_build=1
summary_pattern="${TEST_SUMMARY_PATTERN:-RENDER COMPLETE|content:|geometry|size|scroll|Scroll|#}"
app_args="${TEST_APP_ARGS:---debug}"

usage() {
    cat <<EOF_USAGE
Usage: ${script_path:t} [--wsl|--windows|--both] [-n|--no-build] [--showtime [seconds]|--showtime=seconds|--no-showtime]

Runs $app with the common UI dry-run flow.
Default target: $target
Default showtime: ${showtime_seconds}s
EOF_USAGE
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

    if [ -z "$marker" ]; then
        printf '==> No render marker configured; using screenshot timing\n'
        return 0
    fi

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

    if [ -z "$marker" ]; then
        printf '==> No render marker configured; using screenshot timing\n'
        return 0
    fi

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

    printf '\n==> Windows %s diagnostics\n' "$app"
    grep -hE "$summary_pattern" "$out/$log_name" 2>/dev/null \
        | sed "s/^$app [0-9-]* [0-9:]* +0000 //" | sort -u || true
}

print_summary_wsl() {
    printf '\n==> WSLg %s diagnostics\n' "$app"
    MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu -- zsh -lc \
        "cd ~/proj/swift-cross-ui/testapp/output && grep -hE '$summary_pattern' $log_name 2>/dev/null | sed 's/^$app [0-9-]* [0-9:]* +0000 //' | sort -u" || true
}

run_windows() {
    local out="$script_dir/output"
    local label="${app:l}-windows"

    if [ "$do_build" -eq 1 ]; then
        printf '==> Building %s for Windows\n' "$app"
        zsh "$script_dir/compile.zsh" "$app" | grep -E 'error:|Build of product' || true
    fi

    mkdir -p "$out"
    : > "$out/$log_name"
    printf '==> Launching %s.exe\n' "$app"
    ( cd "$out" && "./$app.exe" ${(z)app_args} >/dev/null 2>&1 & )

    zsh "$script_dir/screenshot.zsh" -d 1 -w "$title" "$label-1s" || true
    if wait_for_marker_windows "$out"; then
        showtime "Windows $app"
        zsh "$script_dir/screenshot.zsh" -d 1 -w "$title" "$label-final" || true
    else
        zsh "$script_dir/screenshot.zsh" -d 0 -w "$title" "$label-timeout" || true
    fi

    if MSYS2_ARG_CONV_EXCL='*' taskkill.exe /F /IM "$app.exe" 2>&1 | grep -q SUCCESS; then
        printf '==> Closed %s.exe\n' "$app"
    else
        printf '==> WARNING: %s.exe may still be running; check with tasklist\n' "$app"
    fi

    print_summary_windows
}

run_wsl() {
    local label="${app:l}-wslg"

    if [ "$do_build" -eq 1 ]; then
        printf '==> Syncing sources to WSL\n'
        zsh "$script_dir/rsync_WSL.zsh" >/dev/null
        printf '==> Building %s for WSLg\n' "$app"
        MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu --cd /home/lowei/proj/swift-cross-ui -- \
            zsh testapp/compile.zsh "$app" 2>&1 | grep -E 'error:|Build of product' || true
    fi

    MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu -- zsh -lc \
        "cd ~/proj/swift-cross-ui/testapp/output && : > $log_name"

    printf '==> Launching %s under WSLg\n' "$app"
    MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu --cd /home/lowei/proj/swift-cross-ui/testapp/output -- \
        zsh -lc "./$app ${(q)app_args} >/dev/null 2>&1" \
        >/dev/null 2>&1 &
    disown 2>/dev/null || true

    zsh "$script_dir/screenshot.zsh" -d 1 -w "$title" "$label-1s" || true
    if wait_for_marker_wsl; then
        showtime "WSLg $app"
        zsh "$script_dir/screenshot.zsh" -d 1 -w "$title" "$label-final" || true
    else
        zsh "$script_dir/screenshot.zsh" -d 0 -w "$title" "$label-timeout" || true
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
    *) printf 'Unknown target: %s\n' "$target" >&2; exit 64 ;;
esac
