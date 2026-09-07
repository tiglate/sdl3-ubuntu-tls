#!/usr/bin/env bash
#
# Builds SDL3_mixer and packages it into libsdl3-mixer0 / libsdl3-mixer-dev.
#
# Depends on SDL3 having been built first: it is resolved from the staging
# prefix under build/, not from the system, so nothing has to be installed.
set -euo pipefail
SCRIPT_NAME="make-sdl-mixer.sh"
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
require_tools

SRC="$REPOS_DIR/SDL_mixer"
BUILD="$BUILD_ROOT/SDL_mixer"
PKGSTAGE="$BUILD_ROOT/stage-SDL_mixer"

SDL3_VERSION="$(staged_pc_version sdl3)" \
    || die "SDL3 has not been built yet; run ./make.sh or ./make-sdl3.sh first"

log "building SDL3_mixer"
configure_and_build "$SRC" "$BUILD" \
    -DBUILD_SHARED_LIBS=ON \
    `# Its bundled copies of its dependencies are git submodules this checkout` \
    `# does not fetch, so always build against the system libraries.` \
    -DSDLMIXER_VENDORED=OFF \
    -DSDLMIXER_INSTALL=ON \
    -DSDLMIXER_INSTALL_CPACK=OFF \
    -DSDLMIXER_SAMPLES=OFF \
    -DSDLMIXER_TESTS=OFF \
\
    `# Pin SDL3 to the copy this repository staged, so a Homebrew or` \
    `# /usr/local SDL3 cannot silently be compiled against instead.` \
    "-DSDL3_DIR=$STAGING_LIBDIR/cmake/SDL3"

stage_install "$BUILD" "$PKGSTAGE"
print_backends "$BUILD"

VERSION="$(sed -n 's/^Version: *//p' "$PKGSTAGE/usr/lib/$MULTIARCH/pkgconfig/sdl3-mixer.pc" | head -1)"
[ -n "$VERSION" ] || die "could not read SDL3_mixer version from sdl3-mixer.pc"
SOMAJOR="$(find "$PKGSTAGE" -name 'lib*.so.[0-9]*' -not -name '*.so.*.*' -print -quit)"
SOMAJOR="${SOMAJOR##*.so.}"

DEV_EXTRA_DEPENDS="libsdl3-dev"
make_packages "$PKGSTAGE" "libsdl3-mixer$SOMAJOR" "libsdl3-mixer-dev" "$VERSION" \
    "https://github.com/libsdl-org/SDL_mixer" "$SRC/LICENSE.txt" \
    "SDL3_mixer audio mixer library" \
" SDL3_mixer is an add-on for SDL 3 that mixes and decodes audio: WAV, FLAC,
 MP3, Ogg Vorbis, Opus, MOD and MIDI.
 .
 Codecs are loaded on demand at run time, so support for a given format also
 depends on its shared library being present." \
    "libsdl3-0 (>= $SDL3_VERSION)"
