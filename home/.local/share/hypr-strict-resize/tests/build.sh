#!/bin/sh
# Builds the two test input clients into this folder: vptr (wlr virtual pointer: moves,
# left/right buttons, wheel) and vkbd (virtual keyboard with a plain US keymap: real key
# presses, so key bindings fire). Use them against a nested Hyprland (WAYLAND_DISPLAY of the
# nested instance), see README.org.
set -e
cd "$(dirname "$(readlink -f "$0")")"
mkdir -p gen vptr vkbd
for p in wlr-virtual-pointer-unstable-v1 virtual-keyboard-unstable-v1; do
    wayland-scanner client-header "$p.xml" "gen/$p.h"
    wayland-scanner private-code "$p.xml" "gen/$p.c"
done
cc -Igen -o vptr/vptr vptr.c gen/wlr-virtual-pointer-unstable-v1.c $(pkg-config --cflags --libs wayland-client)
cc -Igen -o vkbd/vkbd vkbd.c gen/virtual-keyboard-unstable-v1.c $(pkg-config --cflags --libs wayland-client xkbcommon)
echo "built vptr/vptr and vkbd/vkbd"
