#!/usr/bin/env bash
#
# verify.sh -- prove the packages are usable, not just that they built.
#
# Builds tests/consumer against the packaged libraries and runs it. With no
# argument it uses the system-installed packages; give it a prefix to test an
# uninstalled set instead:
#
#   ./verify.sh                     # against installed .debs
#   ./verify.sh /tmp/extracted/usr  # against a tree unpacked with dpkg-deb -x
set -euo pipefail

SCRIPT_NAME="verify.sh"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${1:-}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

die() { echo "$SCRIPT_NAME: error: $*" >&2; exit 1; }

command -v cmake >/dev/null 2>&1 || die "cmake not found on PATH"

args=(-S "$ROOT/tests/consumer" -B "$WORK/build")
command -v ninja >/dev/null 2>&1 && args+=(-G Ninja)
if [ -n "$PREFIX" ]; then
    args+=("-DCMAKE_PREFIX_PATH=$PREFIX")
fi

echo "==> configuring consumer${PREFIX:+ against $PREFIX}"
cmake "${args[@]}" > "$WORK/configure.log" 2>&1 || {
    cat "$WORK/configure.log" >&2
    die "the consumer could not find the packaged libraries"
}
echo "==> building consumer"
cmake --build "$WORK/build" > "$WORK/build.log" 2>&1 || {
    cat "$WORK/build.log" >&2
    die "the consumer failed to build"
}

echo "==> running consumer"
if [ -n "$PREFIX" ]; then
    multiarch="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || echo x86_64-linux-gnu)"
    export LD_LIBRARY_PATH="$PREFIX/lib/$multiarch${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
# No display or sound card on a CI runner; the dummy drivers exercise the same
# initialisation paths without needing either.
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy "$WORK/build/sdl3_consumer"
echo "==> packages verified"
