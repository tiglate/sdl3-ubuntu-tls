#!/usr/bin/env bash
#
# Builds SDL3_image and packages it into libsdl3-image0 / libsdl3-image-dev.
#
# Depends on SDL3 having been built first: it is resolved from the staging
# prefix under build/, not from the system, so nothing has to be installed.
set -euo pipefail
SCRIPT_NAME="make-sdl-image.sh"
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
require_tools

SRC="$REPOS_DIR/SDL_image"
BUILD="$BUILD_ROOT/SDL_image"
PKGSTAGE="$BUILD_ROOT/stage-SDL_image"

SDL3_VERSION="$(staged_pc_version sdl3)" \
    || die "SDL3 has not been built yet; run ./make.sh or ./make-sdl3.sh first"

log "building SDL3_image"
configure_and_build "$SRC" "$BUILD" \
    -DBUILD_SHARED_LIBS=ON \
    `# Its bundled copies of its dependencies are git submodules this checkout` \
    `# does not fetch, so always build against the system libraries.` \
    -DSDLIMAGE_VENDORED=OFF \
    -DSDLIMAGE_INSTALL=ON \
    -DSDLIMAGE_INSTALL_CPACK=OFF \
    -DSDLIMAGE_SAMPLES=OFF \
    -DSDLIMAGE_TESTS=OFF \
    `# Upstream leaves JXL off by default; enable it so an installed libjxl-dev
     # is actually used. It simply stays off when absent.` \
    -DSDLIMAGE_JXL=ON \
\
    `# Pin SDL3 to the copy this repository staged, so a Homebrew or` \
    `# /usr/local SDL3 cannot silently be compiled against instead.` \
    "-DSDL3_DIR=$STAGING_LIBDIR/cmake/SDL3"

stage_install "$BUILD" "$PKGSTAGE"
print_backends "$BUILD"

VERSION="$(sed -n 's/^Version: *//p' "$PKGSTAGE/usr/lib/$MULTIARCH/pkgconfig/sdl3-image.pc" | head -1)"
[ -n "$VERSION" ] || die "could not read SDL3_image version from sdl3-image.pc"
SOMAJOR="$(find "$PKGSTAGE" -name 'lib*.so.[0-9]*' -not -name '*.so.*.*' -print -quit)"
SOMAJOR="${SOMAJOR##*.so.}"

DEV_EXTRA_DEPENDS="libsdl3-dev"
make_packages "$PKGSTAGE" "libsdl3-image$SOMAJOR" "libsdl3-image-dev" "$VERSION" \
    "https://github.com/libsdl-org/SDL_image" "$SRC/LICENSE.txt" \
    "SDL3_image image loading library" \
" SDL3_image is an add-on for SDL 3 that loads images as SDL surfaces and
 textures: PNG, JPEG, WebP, AVIF, GIF, TIFF, SVG, QOI and more." \
    "libsdl3-0 (>= $SDL3_VERSION)"
