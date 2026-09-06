#!/usr/bin/env bash
#
# Builds plutosvg (and plutovg, which it bundles as a submodule) and packages
# both into libplutosvg-0 / libplutosvg-dev.
#
# This is what gives SDL3_ttf its colour-emoji support. Neither library is
# packaged for Debian or Ubuntu. One build produces both, and they are versioned
# together, so they ship as a single package pair rather than being split.
set -euo pipefail
SCRIPT_NAME="make-plutosvg.sh"
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
require_tools

SRC="$REPOS_DIR/plutosvg"
BUILD="$BUILD_ROOT/plutosvg"
PKGSTAGE="$BUILD_ROOT/stage-plutosvg"

log "building plutosvg"
configure_and_build "$SRC" "$BUILD" \
    -DBUILD_SHARED_LIBS=ON \
    -DPLUTOSVG_BUILD_EXAMPLES=OFF \
    `# SDL3_ttf uses plutosvg's FreeType hook (plutosvg-ft.h), which upstream` \
    `# leaves off by default -- without it the library is useless to SDL3_ttf.` \
    -DPLUTOSVG_ENABLE_FREETYPE=ON \
\
    `# plutosvg only falls back to its bundled plutovg when find_package cannot` \
    `# see one already (CMakeLists.txt: "if(NOT plutovg_FOUND) add_subdirectory").` \
    `# Once libplutosvg-dev is installed that check succeeds, and the next build` \
    `# quietly produces a libplutosvg-0 carrying no libplutovg.so at all -- while` \
    `# its .pc still says "Requires: plutovg". The package pair is defined as` \
    `# shipping both, so refuse to find an outside copy, the same way SDL3 is` \
    `# pinned for the satellites.` \
    -DCMAKE_DISABLE_FIND_PACKAGE_plutovg=ON

stage_install "$BUILD" "$PKGSTAGE"

# Two .pc files are installed, plutosvg's and plutovg's. The package is named
# and versioned after plutosvg, so ask for that one rather than taking whichever
# turns up first.
VERSION="$(sed -n 's/^Version: *//p' "$PKGSTAGE/usr/lib/$MULTIARCH/pkgconfig/plutosvg.pc" | head -1)"
[ -n "$VERSION" ] || die "could not read plutosvg version from its pkg-config file"
SOMAJOR="$(find "$PKGSTAGE" -name 'libplutosvg.so.[0-9]*' -type f -print -quit)"
SOMAJOR="${SOMAJOR##*.so.}"; SOMAJOR="${SOMAJOR%%.*}"

make_packages "$PKGSTAGE" "libplutosvg-$SOMAJOR" "libplutosvg-dev" "$VERSION" \
    "https://github.com/sammycage/plutosvg" "$SRC/LICENSE" \
    "plutosvg and plutovg" \
" plutosvg renders SVG documents, including the OpenType-SVG glyphs used for
 colour emoji, on top of the plutovg canvas. Built here with its FreeType
 integration, which is what SDL3_ttf uses."
