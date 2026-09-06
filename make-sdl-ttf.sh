#!/usr/bin/env bash
#
# Builds SDL3_ttf and packages it into libsdl3-ttf-0 / libsdl3-ttf-dev.
#
# Depends on SDL3 having been built first: it is resolved from the staging
# prefix under build/, not from the system, so nothing has to be installed.
set -euo pipefail
SCRIPT_NAME="make-sdl-ttf.sh"
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
require_tools

SRC="$REPOS_DIR/SDL_ttf"
BUILD="$BUILD_ROOT/SDL_ttf"
PKGSTAGE="$BUILD_ROOT/stage-SDL_ttf"

SDL3_VERSION="$(staged_pc_version sdl3)" \
    || die "SDL3 has not been built yet; run ./make.sh or ./make-sdl3.sh first"
PLUTOSVG_VERSION="$(staged_pc_version plutosvg)" \
    || die "plutosvg has not been built yet; run ./make.sh or ./make-plutosvg.sh first"

log "building SDL3_ttf"
configure_and_build "$SRC" "$BUILD" \
    -DBUILD_SHARED_LIBS=ON \
    `# Its bundled copies of its dependencies are git submodules this checkout` \
    `# does not fetch, so always build against the system libraries.` \
    -DSDLTTF_VENDORED=OFF \
    -DSDLTTF_INSTALL=ON \
    -DSDLTTF_INSTALL_CPACK=OFF \
    -DSDLTTF_SAMPLES=OFF \
    -DSDLTTF_HARFBUZZ=ON \
    -DSDLTTF_PLUTOSVG=ON \
\
    `# Pin SDL3 to the copy this repository staged, so a Homebrew or` \
    `# /usr/local SDL3 cannot silently be compiled against instead.` \
    "-DSDL3_DIR=$STAGING_LIBDIR/cmake/SDL3"

stage_install "$BUILD" "$PKGSTAGE"
print_backends "$BUILD"

VERSION="$(sed -n 's/^Version: *//p' "$PKGSTAGE/usr/lib/$MULTIARCH/pkgconfig/sdl3-ttf.pc" | head -1)"
[ -n "$VERSION" ] || die "could not read SDL3_ttf version from sdl3-ttf.pc"
SOMAJOR="$(find "$PKGSTAGE" -name 'lib*.so.[0-9]*' -not -name '*.so.*.*' -print -quit)"
SOMAJOR="${SOMAJOR##*.so.}"

DEV_EXTRA_DEPENDS="libsdl3-dev"
make_packages "$PKGSTAGE" "libsdl3-ttf-$SOMAJOR" "libsdl3-ttf-dev" "$VERSION" \
    "https://github.com/libsdl-org/SDL_ttf" "$SRC/LICENSE.txt" \
    "SDL3_ttf TrueType font rendering library" \
" SDL3_ttf is an add-on for SDL 3 that renders TrueType fonts to SDL surfaces
 and textures, with text shaping through HarfBuzz and colour emoji through
 plutosvg." \
    "libsdl3-0 (>= $SDL3_VERSION), libplutosvg-0 (>= $PLUTOSVG_VERSION)"
