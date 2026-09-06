#!/usr/bin/env bash
#
# clone.sh -- fetch the newest *stable* release of SDL3, its satellite
# libraries and plutosvg into ./repos, choosing a combination they all agree
# on, and record the result in ./.version.
#
# Compatibility is not guessed. Every SDL satellite declares the SDL3 release
# it needs in its own CMakeLists.txt (SDL_REQUIRED_VERSION), so this walks each
# satellite's releases newest-first and takes the newest one whose requirement
# the chosen SDL3 actually satisfies. Picking, say, SDL_image 3.4.6 when SDL3
# is only 3.2.x would configure fine and fail later; this refuses to set that up.
set -euo pipefail

SCRIPT_NAME="clone.sh"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOS_DIR="$ROOT/repos"
VERSION_FILE="$ROOT/.version"

die() { echo "$SCRIPT_NAME: error: $*" >&2; exit 1; }
log() { echo "==> $*"; }

command -v git >/dev/null 2>&1 || die "git not found on PATH"

# name|url|tag-pattern
PROJECTS=(
    "SDL|https://github.com/libsdl-org/SDL|release-"
    "SDL_image|https://github.com/libsdl-org/SDL_image|release-"
    "SDL_mixer|https://github.com/libsdl-org/SDL_mixer|release-"
    "SDL_net|https://github.com/libsdl-org/SDL_net|release-"
    "SDL_ttf|https://github.com/libsdl-org/SDL_ttf|release-"
    "plutosvg|https://github.com/sammycage/plutosvg|v"
)
# Satellites, in the order they get built; each needs SDL3.
SATELLITES=(SDL_image SDL_mixer SDL_net SDL_ttf)

usage() {
    cat <<EOF
Usage: ./clone.sh [options]

Clones or updates ./repos with the newest mutually compatible stable releases,
then writes ./.version.

Options:
  --offline    Do not contact the network; only re-read what is already cloned
                and rewrite .version.
  --pinned     Check out exactly the versions .version already records, instead
                of resolving the newest compatible set. Leaves .version alone.
                This is what a release build uses: it reproduces the tree a tag
                was cut from, rather than whatever upstream published since.
  -h, --help   Show this help.
EOF
}

OFFLINE=0
PINNED=0
while [ $# -gt 0 ]; do
    case "$1" in
        --offline) OFFLINE=1; shift ;;
        --pinned) PINNED=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1 (see ./clone.sh --help)" ;;
    esac
done

# A blobless clone: full history and tags so releases can be compared and any
# tag's CMakeLists.txt read, without downloading every blob of every revision.
ensure_clone() {
    local name="$1" url="$2"
    local dir="$REPOS_DIR/$name"
    if [ -d "$dir/.git" ]; then
        if [ "$OFFLINE" -eq 0 ]; then
            log "updating $name"
            git -C "$dir" fetch --quiet --tags --force origin
        fi
    else
        [ "$OFFLINE" -eq 0 ] || die "$name is not cloned and --offline was given"
        log "cloning $name"
        mkdir -p "$REPOS_DIR"
        git clone --quiet --filter=blob:none "$url" "$dir"
    fi
}

# Release tags, oldest to newest, optionally restricted to one major version.
# These repositories still carry their SDL1 and SDL2 era tags, so asking for
# major 3 is what keeps "newest release" from meaning release-1.2.5. SDL marks
# development series with an odd minor (3.3.x, 3.5.x) and stable ones with an
# even minor, so odd minors are dropped too; plutosvg has no such convention.
stable_tags() {
    local name="$1" prefix="$2"
    local want_major="${3:-}"
    local dir="$REPOS_DIR/$name"
    local tag ver major minor
    while read -r tag; do
        ver="${tag#"$prefix"}"
        [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
        major="${ver%%.*}"
        if [ -n "$want_major" ] && [ "$major" != "$want_major" ]; then
            continue
        fi
        if [ "$prefix" = "release-" ]; then
            minor="$(echo "$ver" | cut -d. -f2)"
            [ $((minor % 2)) -eq 0 ] || continue
        fi
        echo "$ver"
    done < <(git -C "$dir" tag --list "${prefix}*") | sort -V
}

# The SDL3 release a satellite tag insists on, straight from its build files.
# Not every tag has a CMakeLists.txt, and "no declared requirement" is a
# legitimate answer rather than an error, so this never fails the script.
required_sdl_version() {
    local name="$1" tag="$2"
    git -C "$REPOS_DIR/$name" show "$tag:CMakeLists.txt" 2>/dev/null \
        | sed -n 's/^[[:space:]]*set(SDL_REQUIRED_VERSION[[:space:]]\+\([0-9.]*\).*/\1/p' \
        | head -1 || true
}

version_ge() {
    [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]
}

checkout() {
    local name="$1" tag="$2"
    local dir="$REPOS_DIR/$name"
    git -C "$dir" -c advice.detachedHead=false checkout --quiet --force "$tag"
    # plutosvg carries plutovg as a submodule; without this the tree configures
    # and then fails to build.
    if [ -f "$dir/.gitmodules" ]; then
        git -C "$dir" submodule update --quiet --init --recursive
    fi
}

for entry in "${PROJECTS[@]}"; do
    IFS='|' read -r name url _ <<< "$entry"
    ensure_clone "$name" "$url"
done

# --- pinned ----------------------------------------------------------------
#
# Resolution is deliberately skipped here. A release is built from the versions
# its tag recorded, so re-resolving would quietly build something else the
# moment upstream publishes between the tag and the build.

if [ "$PINNED" -eq 1 ]; then
    [ -f "$VERSION_FILE" ] || die "--pinned needs $VERSION_FILE, which does not exist"
    for entry in "${PROJECTS[@]}"; do
        IFS='|' read -r name _ prefix <<< "$entry"
        key="$(echo "$name" | tr '[:lower:]-' '[:upper:]_')"
        version="$(sed -n "s/^${key}=//p" "$VERSION_FILE" | head -1 || true)"
        [ -n "$version" ] || die "$VERSION_FILE records no version for $name"
        log "$name $version (pinned)"
        checkout "$name" "$prefix$version"
    done
    log "checked out the versions recorded in $VERSION_FILE"
    exit 0
fi

# SDL3 first: everything else is chosen to fit it.
SDL_VERSION="$(stable_tags SDL "release-" 3 | tail -1)"
[ -n "$SDL_VERSION" ] || die "no stable SDL release tags found"
log "SDL3 $SDL_VERSION (newest stable)"
checkout SDL "release-$SDL_VERSION"

declare -A CHOSEN=([SDL]="$SDL_VERSION")

for name in "${SATELLITES[@]}"; do
    chosen="" required=""
    while read -r candidate; do
        required="$(required_sdl_version "$name" "release-$candidate")"
        # No declared requirement means nothing to contradict.
        if [ -z "$required" ] || version_ge "$SDL_VERSION" "$required"; then
            chosen="$candidate"
        fi
    done < <(stable_tags "$name" "release-" 3)
    [ -n "$chosen" ] || die "no $name release is compatible with SDL3 $SDL_VERSION"

    newest="$(stable_tags "$name" "release-" 3 | tail -1)"
    if [ "$chosen" != "$newest" ]; then
        log "$name $chosen (held back: $newest needs SDL3 $(required_sdl_version "$name" "release-$newest"))"
    else
        required="$(required_sdl_version "$name" "release-$chosen")"
        log "$name $chosen (needs SDL3 ${required:-any})"
    fi
    checkout "$name" "release-$chosen"
    CHOSEN[$name]="$chosen"
done

PLUTOSVG_VERSION="$(stable_tags plutosvg "v" | tail -1)"
[ -n "$PLUTOSVG_VERSION" ] || die "no plutosvg release tags found"
log "plutosvg $PLUTOSVG_VERSION (newest stable)"
checkout plutosvg "v$PLUTOSVG_VERSION"
CHOSEN[plutosvg]="$PLUTOSVG_VERSION"

# --- .version --------------------------------------------------------------
#
# Tracked in git: it is what tells a release workflow that the upstream
# versions moved and a new set of packages is worth publishing. The repository
# version gets a patch bump whenever any pinned library version changes.

previous_version="1.0.0"
changed=0
if [ -f "$VERSION_FILE" ]; then
    previous_version="$(sed -n 's/^VERSION=//p' "$VERSION_FILE" | head -1 || true)"
    previous_version="${previous_version:-1.0.0}"
    for name in "${!CHOSEN[@]}"; do
        key="$(echo "$name" | tr '[:lower:]-' '[:upper:]_')"
        old="$(sed -n "s/^${key}=//p" "$VERSION_FILE" | head -1 || true)"
        [ "$old" = "${CHOSEN[$name]}" ] || changed=1
    done
    if [ "$changed" -eq 1 ]; then
        IFS=. read -r vmaj vmin vpatch <<< "$previous_version"
        NEW_VERSION="$vmaj.$vmin.$((vpatch + 1))"
    else
        NEW_VERSION="$previous_version"
    fi
else
    changed=1
    NEW_VERSION="$previous_version"
fi

{
    echo "# Generated by clone.sh -- do not edit by hand."
    echo "# VERSION is this repository's own version, bumped whenever any"
    echo "# upstream version below changes. Use it to tag GitHub releases."
    echo "VERSION=$NEW_VERSION"
    echo "SDL=${CHOSEN[SDL]}"
    echo "SDL_IMAGE=${CHOSEN[SDL_image]}"
    echo "SDL_MIXER=${CHOSEN[SDL_mixer]}"
    echo "SDL_NET=${CHOSEN[SDL_net]}"
    echo "SDL_TTF=${CHOSEN[SDL_ttf]}"
    echo "PLUTOSVG=${CHOSEN[plutosvg]}"
} > "$VERSION_FILE"

if [ "$changed" -eq 1 ] && [ "$NEW_VERSION" != "$previous_version" ]; then
    log "upstream versions changed: $previous_version -> $NEW_VERSION"
elif [ "$changed" -eq 1 ]; then
    log "recorded version $NEW_VERSION"
else
    log "no upstream changes; still $NEW_VERSION"
fi
log "wrote $VERSION_FILE"
