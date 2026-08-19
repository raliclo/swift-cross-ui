# gvsbuild

`testapp/install_gtk4_windows.zsh` downloads a prebuilt GTK 4 bundle from this
project. Nothing from it is vendored into this repository; the script fetches a
release asset at install time and the bundle lives outside the source tree, at
`C:/gtk4` by default.

- Project: https://github.com/wingtk/gvsbuild
- Asset used: `GTK4_Gvsbuild_<version>_x64.zip` from the GitHub releases
- Version pinned by the script: see `--version` in
  `testapp/install_gtk4_windows.zsh`

## Why this one

Swift on Windows targets the MSVC ABI and links the UCRT. MSYS2's GTK 4 is
built with MinGW and its import libraries do not link cleanly into MSVC
binaries. gvsbuild publishes GTK 4 built with MSVC, which is the reason it is
the source rather than a general-purpose package manager.

## Licensing

gvsbuild itself is a build system, distributed under the GPL-2.0 licence. The
binaries it produces are GTK and its dependencies, each carrying its own
licence — GTK and GLib are LGPL-2.1-or-later, and the bundle also contains
cairo, Pango, HarfBuzz, fontconfig, libpng, zlib, libjpeg, libtiff and others
under their respective terms.

Because the bundle is downloaded by the developer onto their own machine and is
not redistributed by this repository, no third-party binaries are shipped here.
Anyone who redistributes an application built against these libraries is
responsible for meeting the terms that apply to them, LGPL dynamic-linking
obligations in particular.

The licence texts ship inside the bundle; after running the installer they are
under the install prefix, alongside `share/`.
