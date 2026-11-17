#!/usr/bin/env bash
# Build strict-resize.so against the installed Hyprland and install it to
# ~/.local/lib/hyprland/. Run again after every Hyprland update (a plugin built for another
# version refuses to load and says so in a notification).
#
# Nothing here needs root: the compiler pieces and -dev headers that aren't installed
# (g++-14, the hypr* and xcb -dev packages) are downloaded with apt-get and unpacked into
# .deps/root, matching whatever versions apt currently offers.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

DEPS=.deps
ROOT=$PWD/$DEPS/root
PKGS=(g++-14-x86-64-linux-gnu libstdc++-14-dev libaquamarine-dev libhyprcursor-dev
      libhyprgraphics-dev libhyprlang-dev libhyprutils-dev libinput-dev libxcb-xfixes0-dev
      libxcb-icccm4-dev libxcb-composite0-dev libxcb-res0-dev libxcb-errors-dev liblua5.4-dev
      glslang-dev)   # glslang: the renderer headers (drag-to-place draws its preview)

if [[ ${1:-} == --refresh || ! -d $ROOT ]]; then
    rm -rf "$DEPS"
    mkdir -p "$DEPS/debs"
    (cd "$DEPS/debs" && apt-get download "${PKGS[@]}")
    for d in "$DEPS"/debs/*.deb; do dpkg -x "$d" "$ROOT"; done
fi

# Hyprland's own .pc file pulls in a long chain of -dev packages (libjxl, libheif, ...) that
# only matter for building Hyprland itself, so the include paths are given directly.
CFLAGS_HL="-I/usr/include/hyprland/protocols -I/usr/include/hyprland -I/usr/include/hyprland/src $(pkg-config --cflags pixman-1 libdrm pangocairo wayland-server xkbcommon)"
EXTRA_INC=(-isystem "$ROOT/usr/include" -isystem "$ROOT/usr/include/lua5.4" -isystem "$ROOT/usr/include/x86_64-linux-gnu" -isystem "$ROOT/usr/include/c++/14"
           -isystem "$ROOT/usr/include/x86_64-linux-gnu/c++/14")

OUT=strict-resize.so
# shellcheck disable=SC2086
x86_64-linux-gnu-gcc-14 -x c++ -B "$ROOT/usr/libexec/gcc/x86_64-linux-gnu/14/" \
    -shared -fPIC -O2 -g -std=c++26 -fno-gnu-unique -Wall -Wno-deprecated-declarations \
    "${EXTRA_INC[@]}" $CFLAGS_HL main.cpp -o "$OUT"

DEST=$HOME/.local/lib/hyprland
mkdir -p "$DEST"
install -m 0644 "$OUT" "$DEST/$OUT.new"
mv -f "$DEST/$OUT.new" "${STRICT_RESIZE_OUT:-$DEST/$OUT}"   # replace by rename: never rewrite a library that is loaded
echo "installed ${STRICT_RESIZE_OUT:-$DEST/$OUT} (built for $(Hyprland --version 2>/dev/null | head -1))"
