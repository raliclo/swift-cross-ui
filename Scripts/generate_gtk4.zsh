#!/usr/bin/env zsh

cd ${0:A:h}/..

# Generate Gtk4 wrapper
swift run GtkCodeGen Sources/GtkCodeGen/GirFiles/Gtk-4.0.gir Sources/Gtk/Generated CGtk
zsh Scripts/format.zsh Sources/Gtk/Generated
