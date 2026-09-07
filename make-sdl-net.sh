#!/usr/bin/env bash
#
# Builds SDL3_net and packages it into libsdl3-net0 / libsdl3-net-dev.
#
# Depends on SDL3 having been built first: it is resolved from the staging
# prefix under build/, not from the system, so nothing has to be installed.
set -euo pipefail
SCRIPT_NAME="make-sdl-net.sh"
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
require_tools

SRC="$REPOS_DIR/SDL_net"
BUILD="$BUILD_ROOT/SDL_net"
PKGSTAGE="$BUILD_ROOT/stage-SDL_net"

SDL3_VERSION="$(staged_pc_version sdl3)" \
    || die "SDL3 has not been built yet; run ./make.sh or ./make-sdl3.sh first"

log "building SDL3_net"
configure_and_build "$SRC" "$BUILD" \
    -DBUILD_SHARED_LIBS=ON \
    -DSDLNET_INSTALL=ON \
    -DSDLNET_SAMPLES=OFF \
\
    `# Pin SDL3 to the copy this repository staged, so a Homebrew or` \
    `# /usr/local SDL3 cannot silently be compiled against instead.` \
    "-DSDL3_DIR=$STAGING_LIBDIR/cmake/SDL3"

stage_install "$BUILD" "$PKGSTAGE"
print_backends "$BUILD"

VERSION="$(sed -n 's/^Version: *//p' "$PKGSTAGE/usr/lib/$MULTIARCH/pkgconfig/sdl3-net.pc" | head -1)"
[ -n "$VERSION" ] || die "could not read SDL3_net version from sdl3-net.pc"
SOMAJOR="$(find "$PKGSTAGE" -name 'lib*.so.[0-9]*' -not -name '*.so.*.*' -print -quit)"
SOMAJOR="${SOMAJOR##*.so.}"

DEV_EXTRA_DEPENDS="libsdl3-dev"
make_packages "$PKGSTAGE" "libsdl3-net$SOMAJOR" "libsdl3-net-dev" "$VERSION" \
    "https://github.com/libsdl-org/SDL_net" "$SRC/LICENSE.txt" \
    "SDL3_net networking library" \
" SDL3_net is an add-on for SDL 3 providing a small portable networking API
 for TCP and UDP sockets." \
    "libsdl3-0 (>= $SDL3_VERSION)"
