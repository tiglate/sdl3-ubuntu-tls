# shellcheck shell=bash
#
# Shared machinery for the make-*.sh scripts: configure, build, stage, and turn
# a CMake install tree into a Debian runtime/-dev package pair.
#
# Every library is configured with prefix /usr but installed into a staging
# tree, never onto the system. Later libraries are pointed at that staging tree,
# so the whole chain builds without anything being installed first -- which is
# what lets this repository produce packages without asking for root.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPOS_DIR="$ROOT/repos"
DIST_DIR="$ROOT/dist"
BUILD_ROOT="$ROOT/build"
# The shared prefix every built library is installed into, and that dependent
# libraries resolve their dependencies against.
STAGING="$BUILD_ROOT/staging"
MULTIARCH="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || echo x86_64-linux-gnu)"
STAGING_LIBDIR="$STAGING/usr/lib/$MULTIARCH"
DEB_ARCH="$(dpkg-architecture -qDEB_HOST_ARCH 2>/dev/null || echo amd64)"

JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
FRESH="${FRESH:-0}"
MAKE_VERBOSE="${MAKE_VERBOSE:-0}"
DEB_MAINTAINER="${DEB_MAINTAINER:-}"
# Build and stage, but do not assemble any .deb. Set by debian/rules, which
# wants the merged install tree under $STAGING and lets debhelper do the
# splitting and dependency resolution its own way.
STAGE_ONLY="${STAGE_ONLY:-0}"

die() { echo "${SCRIPT_NAME:-make}: error: $*" >&2; exit 1; }
log() { echo "==> $*"; }

need_prog() {
    command -v "$1" >/dev/null 2>&1 || die "'$1' not found on PATH"
}

require_tools() {
    local t
    for t in cmake ninja dpkg-deb dpkg-architecture pkg-config; do
        need_prog "$t"
    done
}

# Version of an already-staged library, read from the pkg-config file it
# installed. Used both to depend on it and to check compatibility.
staged_pc_version() {
    local pc="$STAGING_LIBDIR/pkgconfig/$1.pc"
    [ -f "$pc" ] || return 1
    sed -n 's/^Version: *//p' "$pc" | head -1
}

# --- build -----------------------------------------------------------------

# configure_and_build <srcdir> <builddir> <extra cmake args...>
configure_and_build() {
    local src="$1" build="$2"; shift 2
    [ -d "$src" ] || die "source tree missing: $src (run ./clone.sh)"
    mkdir -p "$build"
    if [ "$FRESH" -eq 1 ]; then
        rm -f "$build/CMakeCache.txt"
        rm -rf "$build/CMakeFiles"
    fi
    # -O3 -DNDEBUG, i.e. the optimized build these packages are meant to ship.
    local args=(-S "$src" -B "$build" -G Ninja
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX=/usr
        -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
        # A distro-style package carries no rpath; dependents are found through
        # the staging prefix at build time and the system linker at run time.
        -DCMAKE_SKIP_INSTALL_RPATH=ON
        # CMake treats every prefix on PATH as a search root, so a Homebrew or
        # /usr/local copy of a library could silently win over the one this
        # script just staged. Search the staging tree and nothing else first.
        "-DCMAKE_PREFIX_PATH=$STAGING/usr"
        "$@")
    cmake "${args[@]}" > "$build/configure.log" 2>&1 || {
        cat "$build/configure.log" >&2
        die "configure failed for $src"
    }
    local build_args=(--build "$build" --parallel "$JOBS")
    if [ "$MAKE_VERBOSE" -eq 1 ]; then
        build_args+=(-v)
    fi
    cmake "${build_args[@]}"
}

# Installs into the shared staging prefix (for later libraries to build
# against) and into a private tree that gets carved into packages.
stage_install() {
    local build="$1" pkgstage="$2"
    rm -rf "$pkgstage"
    mkdir -p "$pkgstage" "$STAGING"
    DESTDIR="$STAGING" cmake --install "$build" >/dev/null
    DESTDIR="$pkgstage" cmake --install "$build" >/dev/null
}

# Prints the backend summary a project logged at configure time. The satellites
# and SDL3 word theirs differently, so try both shapes. Purely informational.
print_backends() {
    local build="$1" log="$1/configure.log" out
    [ -f "$log" ] || return 0
    out="$(sed -n 's/^-- - \(enabled\|disabled\):/  \1:/p' "$log" || true)"
    if [ -z "$out" ]; then
        out="$(sed -n '/Enabled backends:/,/^-- *$/p' "$log" | sed -n 's/^--   /  /p' || true)"
    fi
    if [ -n "$out" ]; then
        echo "$out"
    else
        echo "  (no optional backends)"
    fi
}

# --- packaging -------------------------------------------------------------

deb_maintainer() {
    if [ -n "$DEB_MAINTAINER" ]; then echo "$DEB_MAINTAINER"; return 0; fi
    local name email
    name="$(git config --get user.name 2>/dev/null || true)"
    email="$(git config --get user.email 2>/dev/null || true)"
    if [ -n "$name" ] && [ -n "$email" ]; then
        echo "$name <$email>"
    else
        echo "$(id -un) <$(id -un)@$(hostname)>"
    fi
}

# Best-effort system dependencies for a runtime tree. dpkg-shlibdeps wants to
# run from something resembling an unpacked Debian source tree, and needs -l for
# every directory holding a library it cannot otherwise find: the package's own
# (siblings, and the install RPATH is stripped) and the staging prefix (SDL3 and
# plutosvg are not installed on this system at all). Without those the run fails
# outright and every dependency is lost, not just the unresolvable ones.
deb_shlibdeps() {
    local rt="$1" pkg="$2" workdir depends libs=() l
    command -v dpkg-shlibdeps >/dev/null 2>&1 || return 0
    while IFS= read -r -d '' l; do libs+=("$l"); done \
        < <(find "$rt" -name 'lib*.so.[0-9]*' -type f -print0)
    [ ${#libs[@]} -gt 0 ] || return 0
    workdir="$(mktemp -d)"
    mkdir -p "$workdir/debian"
    printf 'Source: %s\nPackage: %s\nArchitecture: any\n' "$pkg" "$pkg" \
        > "$workdir/debian/control"
    if ! depends="$(cd "$workdir" && dpkg-shlibdeps -O --ignore-missing-info \
                        -l"$rt/usr/lib/$MULTIARCH" -l"$STAGING_LIBDIR" \
                        "${libs[@]}" 2>/dev/null)"; then
        echo "warning: dpkg-shlibdeps failed for $pkg; Depends will be incomplete" >&2
        depends=""
    fi
    rm -rf "$workdir"
    echo "${depends#shlibs:Depends=}"
}

# Records which SONAMEs this package provides, so dpkg-shlibdeps can resolve
# them once it is installed.
deb_shlibs() {
    local tree="$1" pkg="$2" version="$3" so libname major
    mkdir -p "$tree/DEBIAN"
    : > "$tree/DEBIAN/shlibs"
    while IFS= read -r -d '' so; do
        libname="$(basename "${so%.so.*}")"
        major="${so##*.so.}"
        major="${major%%.*}"
        echo "$libname $major $pkg (>= $version)" >> "$tree/DEBIAN/shlibs"
    done < <(find "$tree" -name 'lib*.so.[0-9]*' -type f -print0)
}

merge_depends() {
    local merged="" seen=" " dep pkg
    local IFS=','
    for dep in $1 $2; do
        dep="${dep#"${dep%%[![:space:]]*}"}"
        dep="${dep%"${dep##*[![:space:]]}"}"
        [ -n "$dep" ] || continue
        pkg="${dep%% *}"
        case "$seen" in *" $pkg "*) continue ;; esac
        seen="$seen$pkg "
        merged="${merged:+$merged, }$dep"
    done
    echo "$merged"
}

deb_assemble() {
    local tree="$1" control="$2" pkgfile="$3" size
    mkdir -p "$tree/DEBIAN"
    size="$(du -k -s --exclude=DEBIAN "$tree" | cut -f1)"
    printf '%s\nInstalled-Size: %s\n' "$control" "$size" > "$tree/DEBIAN/control"
    # Lets "dpkg -V" verify the package later.
    (cd "$tree" && find . -path ./DEBIAN -prune -o -type f -print0 \
        | xargs -0 -r md5sum | sed 's|  \./|  |' > DEBIAN/md5sums)
    dpkg-deb --build --root-owner-group "$tree" "$pkgfile" >/dev/null
    echo "  $(basename "$pkgfile")"
}

# make_packages <pkgstage> <runtime-pkg> <dev-pkg> <version> <homepage>
#               <license-file> <summary> <description-body> <extra-runtime-deps>
#
# Splits the staged install: anything that is a versioned shared object is
# runtime, everything else -- headers, the unversioned .so symlink, pkg-config
# and CMake files -- is what a developer needs.
make_packages() {
    local pkgstage="$1" runtime_pkg="$2" dev_pkg="$3" version="$4" \
          homepage="$5" license="$6" summary="$7" body="$8" extra_deps="${9:-}"

    # Under STAGE_ONLY the caller only wanted the staging prefix populated;
    # $STAGING already holds it, so this private copy has served its purpose.
    if [ "$STAGE_ONLY" = "1" ]; then
        log "staged $runtime_pkg / $dev_pkg $version (not packaging)"
        rm -rf "$pkgstage"
        return 0
    fi

    local root="$pkgstage/usr"
    [ -d "$root" ] || die "nothing was installed under $pkgstage/usr"

    local rt="$pkgstage.runtime" dv="$pkgstage.dev"
    rm -rf "$rt" "$dv"
    local f rel dest
    while IFS= read -r -d '' f; do
        rel="${f#"$pkgstage"/}"
        case "$(basename "$f")" in
            *.so.[0-9]*) dest="$rt" ;;
            *)           dest="$dv" ;;
        esac
        mkdir -p "$dest/$(dirname "$rel")"
        mv "$f" "$dest/$rel"
    done < <(find "$pkgstage" \( -type f -o -type l \) -print0)
    rm -rf "$pkgstage"
    [ -d "$rt" ] || die "no runtime files were staged for $runtime_pkg"
    [ -d "$dv" ] || die "no development files were staged for $dev_pkg"

    local pkg
    for pkg in "$runtime_pkg:$rt" "$dev_pkg:$dv"; do
        mkdir -p "${pkg#*:}/usr/share/doc/${pkg%%:*}"
        cp "$license" "${pkg#*:}/usr/share/doc/${pkg%%:*}/copyright"
    done

    local maintainer depends
    maintainer="$(deb_maintainer)"
    depends="$(deb_shlibdeps "$rt" "$runtime_pkg")"
    # Libraries this repository builds are not installed, so dpkg-shlibdeps
    # cannot name their packages; state those dependencies outright.
    depends="$(merge_depends "$depends" "$extra_deps")"

    mkdir -p "$DIST_DIR"
    deb_shlibs "$rt" "$runtime_pkg" "$version"
    deb_assemble "$rt" "Package: $runtime_pkg
Version: $version
Architecture: $DEB_ARCH
Maintainer: $maintainer
Section: libs
Priority: optional
Homepage: $homepage${depends:+
Depends: $depends}
Description: $summary (shared library)
$body
 .
 This package contains the shared library." \
        "$DIST_DIR/${runtime_pkg}_${version}_${DEB_ARCH}.deb"

    deb_assemble "$dv" "Package: $dev_pkg
Version: $version
Architecture: $DEB_ARCH
Maintainer: $maintainer
Section: libdevel
Priority: optional
Homepage: $homepage
Depends: $runtime_pkg (= $version)${DEV_EXTRA_DEPENDS:+, $DEV_EXTRA_DEPENDS}
Description: $summary (development files)
$body
 .
 This package contains the headers, pkg-config and CMake files needed to
 build against it." \
        "$DIST_DIR/${dev_pkg}_${version}_${DEB_ARCH}.deb"

    rm -rf "$rt" "$dv"
}
