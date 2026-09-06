#!/usr/bin/env bash
#
# Rewrites the Build-Depends field of debian/control from build-deps.txt.
#
# build-deps.txt is the single source of truth for what the builds detect their
# optional backends from -- the README tells humans to install it and the CI
# workflows install exactly it. Launchpad, though, reads Build-Depends and
# nothing else, so the two have to agree: a package listed in one and not the
# other means a backend that is enabled locally and silently missing from the
# PPA build, which is precisely the sort of difference nobody notices until a
# user reports that MP3 playback does not work.
#
# Run it after editing build-deps.txt; run it with --check in CI to fail on the
# difference rather than publish it.
set -euo pipefail

SCRIPT_NAME="sync-build-deps.sh"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTROL="$ROOT/debian/control"
DEPS="$ROOT/build-deps.txt"

die() { echo "$SCRIPT_NAME: error: $*" >&2; exit 1; }

CHECK=0
case "${1:-}" in
    --check) CHECK=1 ;;
    '') ;;
    *) die "usage: $0 [--check]" ;;
esac

[ -f "$CONTROL" ] || die "no $CONTROL"
[ -f "$DEPS" ] || die "no $DEPS"

# debhelper-compat is the one build dependency that belongs to the packaging
# rather than to the libraries, so it is stated here and not in build-deps.txt.
#
# build-essential and dpkg-dev are dropped the other way round: build-deps.txt
# names them because a human running "apt install" needs them, but every Debian
# build already has both (dpkg-dev is pulled in by build-essential), and
# depending on either without a version is a lintian error.
field="$(
    {
        echo "debhelper-compat (= 13)"
        grep -vE '^\s*(#|$)' "$DEPS" | grep -vxE 'build-essential|dpkg-dev'
    } | sed 's/^/ /' | sed '$ !s/$/,/'
)"

new="$(awk -v field="$field" '
    /^Build-Depends:/ { print "Build-Depends:"; print field; skip = 1; next }
    # The field ends at the next line that starts a new one, i.e. not a
    # continuation (continuations are indented).
    skip && /^[^ \t]/ { skip = 0 }
    !skip
' "$CONTROL")"

if [ "$CHECK" -eq 1 ]; then
    if ! diff -u <(cat "$CONTROL") <(printf '%s\n' "$new") > /dev/null; then
        echo "$SCRIPT_NAME: debian/control is out of sync with build-deps.txt:" >&2
        diff -u "$CONTROL" <(printf '%s\n' "$new") >&2 || true
        echo >&2
        echo "Run ./debian/sync-build-deps.sh to update it." >&2
        exit 1
    fi
    echo "debian/control Build-Depends matches build-deps.txt"
    exit 0
fi

printf '%s\n' "$new" > "$CONTROL"
echo "wrote Build-Depends into $CONTROL"
