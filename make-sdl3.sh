#!/usr/bin/env bash
#
# Builds SDL3 and packages it into libsdl3-0 / libsdl3-dev.
#
# Every optional backend SDL can find on this machine is enabled: SDL detects
# them from the installed dev packages, so what ends up in the package depends
# on what is installed at build time. Run ./make.sh features for the summary.
set -euo pipefail
SCRIPT_NAME="make-sdl3.sh"
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
require_tools

SRC="$REPOS_DIR/SDL"
BUILD="$BUILD_ROOT/SDL"
PKGSTAGE="$BUILD_ROOT/stage-SDL"

log "building SDL3"
configure_and_build "$SRC" "$BUILD" \
    -DSDL_SHARED=ON \
    `# Upstream defaults to shared-only; the -dev package ships libSDL3.a too.` \
    -DSDL_STATIC=ON \
    -DSDL_TESTS=OFF \
    -DSDL_EXAMPLES=OFF \
    -DSDL_INSTALL_CPACK=OFF \
    `# SDL turns this on for Linux, which bakes the install libdir into the` \
    `# shared object. A distro-style package has no business carrying an rpath.` \
    -DSDL_RPATH=OFF \
    `# Optional drivers SDL leaves off by default. OSS is auto-detected and` \
    `# simply stays off when soundcard.h is absent; OpenVR needs no dev package` \
    `# (SDL bundles openvr_capi.h and dlopens openvr_api at runtime).` \
    -DSDL_OSS=ON \
    -DSDL_OPENVR=ON

stage_install "$BUILD" "$PKGSTAGE"
print_backends "$BUILD"

VERSION="$(sed -n 's/^Version: *//p' "$PKGSTAGE/usr/lib/$MULTIARCH/pkgconfig/sdl3.pc" | head -1)"
[ -n "$VERSION" ] || die "could not read SDL3 version from sdl3.pc"
SOMAJOR="$(find "$PKGSTAGE" -name 'libSDL3.so.[0-9]*' -not -name '*.so.*.*' -print -quit)"
SOMAJOR="${SOMAJOR##*.so.}"

make_packages "$PKGSTAGE" "libsdl3-$SOMAJOR" "libsdl3-dev" "$VERSION" \
    "https://www.libsdl.org/" "$SRC/LICENSE.txt" \
    "Simple DirectMedia Layer 3" \
" SDL is a cross-platform library for low-level access to audio, keyboard,
 mouse, joystick and graphics hardware."
