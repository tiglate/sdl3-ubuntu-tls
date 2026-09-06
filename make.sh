#!/usr/bin/env bash
#
# make.sh -- build every library and produce the .deb packages in ./dist.
#
# With no arguments it clones what is missing, then builds each library in
# dependency order. Nothing is installed onto the system: each library is
# installed into a staging prefix under build/ that the next one resolves
# against, so the whole set builds from a clean checkout without root. The
# packages it leaves in ./dist are the only thing you install.
set -euo pipefail

SCRIPT_NAME="make.sh"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT/lib/common.sh"

# Build order is a dependency order: plutosvg and SDL3 stand alone, every
# satellite needs SDL3, and SDL_ttf additionally needs plutosvg.
ORDER=(plutosvg sdl3 sdl-image sdl-mixer sdl-net sdl-ttf)

usage() {
    cat <<EOF
Usage: ./make.sh [action] [options]

Actions:
  build [lib...]   Clone if needed, then build and package. With no argument,
                    every library in dependency order:
                      ${ORDER[*]}
                    Named libraries are built on their own, which assumes their
                    dependencies were staged by an earlier run. This is the
                    default action.
  features         Report which optional backends each library was built with,
                    from the last configure. Builds nothing.
  clean            Remove build/ (build trees and the staging prefix), keeping
                    ./repos and ./dist.
  purge            Remove build/ and dist/. Add --repos to drop ./repos too and
                    start from a bare checkout.
  list             Show the libraries, in build order, and their pinned versions.

Options:
  -j, --jobs N       Parallel compile jobs (default: all cores, currently $JOBS).
      --fresh        Discard each CMake cache and re-probe the system. Use after
                      installing a new dev package, whose presence CMake would
                      otherwise not notice. Forces a full rebuild.
      --repos        With "purge", also delete ./repos.
  -m, --maintainer S Maintainer field for the packages ("Name <email>").
  -v, --verbose      Pass -v through to the underlying build tool.
  -h, --help         Show this help.

Everything is compiled optimized (CMAKE_BUILD_TYPE=Release, i.e. -O3 -DNDEBUG).

Examples:
  ./make.sh                          # clone, build everything, packages in ./dist
  ./make.sh --fresh                  # after installing new dev packages
  ./make.sh build sdl-ttf            # just SDL3_ttf, reusing what is staged
  ./make.sh features
EOF
}

ACTION="build"
case "${1:-}" in
    build|features|clean|purge|list) ACTION="$1"; shift ;;
    -h|--help|help) usage; exit 0 ;;
esac

SELECTED=()
while [ $# -gt 0 ] && [[ "$1" != -* ]]; do
    SELECTED+=("$1"); shift
done

PURGE_REPOS=0
while [ $# -gt 0 ]; do
    case "$1" in
        -j|--jobs) [ $# -ge 2 ] || die "$1 requires an argument"; JOBS="$2"; shift 2 ;;
        --fresh) FRESH=1; shift ;;
        --repos) PURGE_REPOS=1; shift ;;
        -m|--maintainer) [ $# -ge 2 ] || die "$1 requires an argument"; DEB_MAINTAINER="$2"; shift 2 ;;
        -v|--verbose) MAKE_VERBOSE=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1 (see ./make.sh --help)" ;;
    esac
done
export JOBS FRESH MAKE_VERBOSE DEB_MAINTAINER

# Maps a library name to the repository clone.sh checks out for it.
repo_of() {
    case "$1" in
        plutosvg)  echo plutosvg ;;
        sdl3)      echo SDL ;;
        sdl-image) echo SDL_image ;;
        sdl-mixer) echo SDL_mixer ;;
        sdl-net)   echo SDL_net ;;
        sdl-ttf)   echo SDL_ttf ;;
        *)         return 1 ;;
    esac
}

case "$ACTION" in
    clean)
        rm -rf "$BUILD_ROOT"
        log "removed $BUILD_ROOT"
        exit 0
        ;;
    purge)
        rm -rf "$BUILD_ROOT" "$DIST_DIR"
        log "removed build/ and dist/"
        if [ "$PURGE_REPOS" -eq 1 ]; then
            rm -rf "$REPOS_DIR"
            log "removed repos/"
        fi
        exit 0
        ;;
    list)
        if [ -f "$ROOT/.version" ]; then
            sed -n 's/^\([A-Z_]*\)=\(.*\)/  \1 \2/p' "$ROOT/.version"
        else
            echo "  no .version yet -- run ./clone.sh"
        fi
        echo
        echo "Build order: ${ORDER[*]}"
        exit 0
        ;;
    features)
        for lib in "${ORDER[@]}"; do
            build="$BUILD_ROOT/$(repo_of "$lib")"
            [ -f "$build/configure.log" ] || continue
            echo "$lib:"
            print_backends "$build"
        done
        exit 0
        ;;
esac

# --- build -----------------------------------------------------------------

if [ ! -d "$REPOS_DIR" ]; then
    log "no ./repos yet, cloning"
    "$ROOT/clone.sh"
fi

TARGETS=("${ORDER[@]}")
if [ ${#SELECTED[@]} -gt 0 ]; then
    TARGETS=()
    for lib in "${SELECTED[@]}"; do
        repo_of "$lib" >/dev/null || die "unknown library: $lib (see ./make.sh --help)"
        TARGETS+=("$lib")
    done
fi

mkdir -p "$DIST_DIR"
for lib in "${TARGETS[@]}"; do
    "$ROOT/make-$lib.sh"
done

echo
log "packages in $DIST_DIR:"
ls -1 "$DIST_DIR" | sed 's/^/  /'
echo
echo "Install them with:"
echo "  sudo apt install $DIST_DIR/*.deb"
