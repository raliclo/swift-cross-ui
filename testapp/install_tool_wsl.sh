#!/bin/bash
# Prepares a WSL (or plain Linux) environment for building and testing
# swift-cross-ui's GtkBackend.
#
# Run it inside the distribution, not from Windows:
#
#   wsl -d Ubuntu -- bash testapp/install_tool_wsl.sh
#
# It needs root for the apt packages and for /usr/local. `sudo` in a default
# WSL Ubuntu asks for a password; `wsl -d Ubuntu -u root` avoids handling one:
#
#   wsl -d Ubuntu -u root -- bash testapp/install_tool_wsl.sh
#
# Everything here is idempotent, so re-running it is safe.
#
# What it deals with, learned the hard way on Ubuntu 26.04:
#
# - swift.org publishes no toolchain for 26.04. The 24.04 build runs there, so
#   that is what gets installed.
# - That toolchain then fails to start, because 26.04 dropped the library
#   versions it was linked against: libxml2.so.2 (26.04 ships .so.16) and ICU 74
#   (26.04 ships 78). Both are extracted from the 24.04 packages into a separate
#   directory rather than installed, so nothing the distribution owns is
#   touched or downgraded.

set -euo pipefail

SWIFT_VERSION="${SWIFT_VERSION:-6.3.3}"
SWIFT_PLATFORM="${SWIFT_PLATFORM:-ubuntu24.04}"
SWIFT_PREFIX="${SWIFT_PREFIX:-/usr/local/swift}"
COMPAT_DIR="/usr/local/lib/swift-compat"

log() { printf '\n== %s\n' "$1"; }

if [ "$(id -u)" -ne 0 ]; then
    echo "This script installs system packages; run it as root:" >&2
    echo "  wsl -d <distro> -u root -- bash ${0}" >&2
    exit 1
fi

. /etc/os-release
log "Distribution: ${PRETTY_NAME:-unknown}"

log "Installing GTK 4 and build dependencies"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends \
    libgtk-4-dev pkg-config curl ca-certificates git \
    binutils libcurl4-openssl-dev libedit2 libncurses-dev \
    libpython3-dev libsqlite3-0 libz3-dev tzdata unzip

# Ubuntu 26.04 renamed the sonames the 24.04 toolchain was linked against. The
# replacements are taken from 24.04's own packages and kept in their own
# directory, ahead of nothing else on the search path, so the distribution's
# newer libxml2 and ICU stay in place for everything else.
if [ "${VERSION_ID:-}" = "26.04" ]; then
    log "Adding Ubuntu 24.04 compatibility libraries for the toolchain"
    mkdir -p "$COMPAT_DIR"
    work="$(mktemp -d)"
    trap 'rm -rf "$work"' EXIT

    fetch_lib() {
        local pool="$1" pattern="$2" description="$3"
        local deb
        deb="$(curl -fsSL "$pool" | grep -oE "$pattern" | sort -u | tail -1)"
        if [ -z "$deb" ]; then
            echo "Could not find $description in $pool" >&2
            exit 1
        fi
        echo "  $deb"
        curl -fsSL -o "$work/$deb" "$pool$deb"
        rm -rf "$work/x"
        mkdir -p "$work/x"
        dpkg-deb -x "$work/$deb" "$work/x"
        cp -a "$work"/x/usr/lib/x86_64-linux-gnu/$4 "$COMPAT_DIR/"
    }

    fetch_lib "http://archive.ubuntu.com/ubuntu/pool/main/libx/libxml2/" \
        'libxml2_2\.9\.14[^"]*_amd64\.deb' "libxml2 2.9.14" 'libxml2.so.2*'
    fetch_lib "http://archive.ubuntu.com/ubuntu/pool/main/i/icu/" \
        'libicu74_[^"]*_amd64\.deb' "ICU 74" 'libicu*.so.74*'

    echo "$COMPAT_DIR" > /etc/ld.so.conf.d/swift-compat.conf
    ldconfig
fi

log "Installing Swift $SWIFT_VERSION ($SWIFT_PLATFORM build)"
if [ -x "$SWIFT_PREFIX/usr/bin/swift" ] \
    && "$SWIFT_PREFIX/usr/bin/swift" --version 2>/dev/null | grep -q "$SWIFT_VERSION"; then
    echo "  already installed at $SWIFT_PREFIX"
else
    platform_path="${SWIFT_PLATFORM//./}"
    archive="swift-$SWIFT_VERSION-RELEASE-$SWIFT_PLATFORM.tar.gz"
    url="https://download.swift.org/swift-$SWIFT_VERSION-release/$platform_path/swift-$SWIFT_VERSION-RELEASE/$archive"

    echo "  $url"
    tmp="$(mktemp -d)"
    curl -fsSL -o "$tmp/$archive" "$url"
    rm -rf "$SWIFT_PREFIX"
    mkdir -p "$SWIFT_PREFIX"
    tar -xzf "$tmp/$archive" -C "$SWIFT_PREFIX" --strip-components=1
    rm -rf "$tmp"
fi

# A profile entry rather than symlinks into /usr/local/bin, so the toolchain can
# be replaced by pointing SWIFT_PREFIX somewhere else.
printf 'export PATH="%s/usr/bin:$PATH"\n' "$SWIFT_PREFIX" > /etc/profile.d/swift.sh
chmod 0644 /etc/profile.d/swift.sh

log "Verifying"
export PATH="$SWIFT_PREFIX/usr/bin:$PATH"
swift --version
echo "gtk4: $(pkg-config --modversion gtk4)"

# WSLg exports these; without them a GTK window has nowhere to appear and every
# UI test result would be meaningless.
if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    echo "display: ${DISPLAY:-unset} / wayland: ${WAYLAND_DISPLAY:-unset}"
else
    echo "display: none found -- GUI tests cannot run in this session" >&2
fi

log "Done. Open a new shell, or run: export PATH=\"$SWIFT_PREFIX/usr/bin:\$PATH\""
