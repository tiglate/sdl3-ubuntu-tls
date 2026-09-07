# sdl3-ubuntu-tls

Builds **SDL3** and its companion libraries from upstream source and packages
them as Debian `.deb` files for Ubuntu.

Ubuntu does not currently package the SDL3 satellite libraries at all, and its
SDL3 itself lags upstream. The usual answer — `git clone`, `cmake`,
`sudo make install` — scatters files no package manager tracks and cannot
cleanly remove. This repository does the same builds and hands you packages
instead, so `dpkg` owns every file and `apt remove` actually works.

Everything is compiled optimized (`CMAKE_BUILD_TYPE=Release`, i.e. `-O3
-DNDEBUG`) with every optional backend that your system has the development
packages for.

## Packages produced

| Package | Contents |
| --- | --- |
| `libsdl3-0` / `libsdl3-dev` | SDL3 itself |
| `libsdl3-image0` / `libsdl3-image-dev` | image loading (PNG, JPEG, WebP, AVIF, JXL, TIFF, SVG, …) |
| `libsdl3-mixer0` / `libsdl3-mixer-dev` | audio mixing (WAV, FLAC, MP3, Vorbis, Opus, MOD, MIDI) |
| `libsdl3-net0` / `libsdl3-net-dev` | TCP/UDP networking |
| `libsdl3-ttf0` / `libsdl3-ttf-dev` | TrueType text, HarfBuzz shaping, colour emoji |
| `libplutosvg0` / `libplutosvg-dev` | plutosvg + plutovg, which SDL3_ttf uses for colour emoji |

Each library ships as a runtime package and a matching `-dev` package, the way
Debian splits them: the shared library in one, the headers, `pkg-config` file
and CMake config in the other. `libsdl3-dev` also carries `libSDL3.a`.

## Quick start

```sh
./make.sh                              # clone, build, package into ./dist
sudo apt install ./dist/*.deb          # the one step that needs root
```

The first run takes a few minutes and needs a network connection. Everything
after that is local.

## How it works

`make.sh` runs the per-library scripts in dependency order:

```
plutosvg → SDL3 → SDL3_image, SDL3_mixer, SDL3_net → SDL3_ttf
```

The satellites need SDL3 to build against, and SDL3_ttf additionally needs
plutosvg. Rather than requiring you to install each package before the next one
can be built, every library is installed into a **staging prefix** under
`build/staging`, and later builds are pointed at it. Nothing touches your system
until you install the packages yourself.

Each library is also pinned to the SDL3 that was just staged (`-DSDL3_DIR=…`).
CMake treats every prefix on `PATH` as a search root, so without that pin a
Homebrew or `/usr/local` copy of SDL3 can silently win and you get libraries
compiled against one SDL3 while the package declares a dependency on another.

## Scripts

| Script | Purpose |
| --- | --- |
| `make.sh` | Clone if needed, build everything in order, write `./dist`. |
| `clone.sh` | Fetch the newest mutually compatible stable releases into `./repos`, and write `.version`. |
| `make-sdl3.sh` | SDL3. |
| `make-sdl-image.sh`, `make-sdl-mixer.sh`, `make-sdl-net.sh`, `make-sdl-ttf.sh` | The satellites. |
| `make-plutosvg.sh` | plutosvg and the plutovg canvas it bundles. |
| `lib/common.sh` | Shared build and packaging machinery. |
| `verify.sh` | Build and run a consumer against the packages to prove they work. |
| `debian/` | Debian source packaging for the PPA. `debian/sync-build-deps.sh` regenerates `Build-Depends` from `build-deps.txt`. |

Each `make-*.sh` can be run on its own if its dependencies are already staged.

### `make.sh` actions

```
./make.sh                  # build everything (default)
./make.sh build sdl-ttf    # one library, reusing what is staged
./make.sh features         # which optional backends each library got
./make.sh list             # pinned upstream versions and build order
./make.sh clean            # drop build/, keep repos/ and dist/
./make.sh purge [--repos]  # drop build/ and dist/, optionally repos/ too
```

Useful options: `-j N` (parallel jobs), `--fresh` (discard CMake caches and
re-probe the system — **use this after installing a new dev package**, since
CMake caches its detection results and will not notice on its own),
`-m "Name <email>"` (package maintainer field), `-v` (verbose build).

## Version selection

`clone.sh` picks the newest *stable* release of each project — for the SDL
family that means a `release-3.Y.Z` tag with an even minor, since odd minors are
development series.

Compatibility is checked, not assumed. Every SDL satellite declares the SDL3
release it needs in its own `CMakeLists.txt` (`SDL_REQUIRED_VERSION`), so
`clone.sh` walks each satellite's releases newest-first and takes the newest one
the chosen SDL3 actually satisfies, reporting anything held back:

```
==> SDL3 3.4.16 (newest stable)
==> SDL_image 3.4.6 (needs SDL3 3.4.0)
==> SDL_ttf 3.2.2 (needs SDL3 3.2.6)
```

A release build does not repeat this. `./clone.sh --pinned` checks out exactly
what `.version` already records, so a tag is built from the tree it was cut
from rather than from whatever upstream published in the meantime.

The result is written to `.version`, which is tracked in git:

```
VERSION=1.0.0
SDL=3.4.16
SDL_IMAGE=3.4.6
...
```

`VERSION` is this repository's own version. `clone.sh` bumps its patch number
whenever any upstream version changes, so a CI job can re-run `clone.sh`, notice
`.version` changed, and cut a GitHub release with the packages attached.

## Optional dependencies

Backends are detected at build time, so what you get depends on what is
installed when you build. [`build-deps.txt`](build-deps.txt) lists everything
worth having; it is the same list the CI workflows install:

```sh
sudo apt install $(grep -vE '^\s*(#|$)' build-deps.txt)
```

Run `./make.sh features` after a build to see what was actually enabled. If you
install something new afterwards, rebuild with `./make.sh --fresh` — CMake
caches its detection results and will not notice on its own.

## Verifying

`verify.sh` builds a small consumer (`tests/consumer`) that finds every packaged
library through its installed CMake config, links the imported targets and
initialises the subsystems that load dependencies at run time. It checks the
packages are *usable*, not merely that they built.

```sh
sudo apt install ./dist/*.deb
./verify.sh                      # against the installed packages

# or, without installing anything:
mkdir -p /tmp/x && for d in dist/*.deb; do dpkg-deb -x "$d" /tmp/x; done
./verify.sh /tmp/x/usr
```

## Continuous integration

| Workflow | Trigger | What it does |
| --- | --- | --- |
| `build` | push, pull request | Builds every package, installs them, runs `verify.sh`, checks they uninstall cleanly, and uploads the `.deb` files as artifacts. |
| `release` | weekly schedule, manual | Runs `clone.sh`; if `VERSION` moved to something not yet tagged, builds, verifies, commits `.version`, and publishes a GitHub release with the packages attached. |
| `ppa` | called by `release`, manual | Builds a signed Debian **source** package and uploads it to `ppa:tiglate/ppa`. |

The release job keys entirely off `.version`: no upstream change means no
version bump, no new tag, and no build. Trigger it by hand from the Actions tab
(with **force** to rebuild an existing tag).

## Publishing to the PPA

The packages are also published to
[`ppa:tiglate/ppa`](https://launchpad.net/~tiglate/+archive/ubuntu/ppa), which
installs them the ordinary way:

```sh
sudo add-apt-repository ppa:tiglate/ppa
sudo apt install libsdl3-dev libsdl3-image-dev libsdl3-mixer-dev \
                 libsdl3-net-dev libsdl3-ttf-dev
```

### Why the PPA does not use the `.deb` files

Launchpad does not accept binary packages. A PPA takes a GPG-signed *source*
package and builds the binaries itself, in its own clean chroot, for every
series and architecture the PPA has enabled. So the `ppa` workflow ignores
`dist/` entirely: it checks out the upstream sources at the versions `.version`
records (`./clone.sh --pinned`) and uploads those.

### One source package, twelve binaries

The six libraries have to be built in dependency order against each other, and a
Launchpad build can only see binaries the PPA has already *published* — roughly
twenty minutes behind the build that produced them. Six separate source packages
would therefore need ordered uploads and dependency-wait retries before the set
converged.

Instead, `debian/` describes a single source package, `sdl3-stack`, that vendors
all six upstream trees and produces all twelve binaries from one build. It is
not how Debian proper would do it, but for a personal PPA it means one upload,
one build, and no ordering problem. The build itself is not reimplemented:
`debian/rules` runs `make.sh` with `STAGE_ONLY=1`, which stops after populating
`build/staging` instead of assembling `.deb` files, and `debian/*.install` splits
that tree the same way `lib/common.sh` does locally.

`debian/source/options` keeps the upload small: every satellite is configured
`SDLxxx_VENDORED=OFF` and builds against the system libraries, so the `external/`
submodules are ~330 MB that no Linux build reads. Excluding them takes the source
package from 384 MB to 17 MB compressed.

### Package names

The runtime packages are named the way Debian and Ubuntu name them for these
SONAMEs — `libsdl3-0`, `libsdl3-image0`, `libsdl3-mixer0`, `libsdl3-net0`,
`libsdl3-ttf0`, `libplutosvg0` — rather than being given distinct names to sit alongside the
archive's. That is deliberate: Ubuntu ships its own SDL3 from 25.04 onward, and
a PPA package with the same name and a higher version *supersedes* the archive
one, which is the whole point of a PPA. A different name would instead put two
packages shipping the same `libSDL3.so.0` on the system and make them conflict
at the file level, with no upgrade path between them.

The satellites lost a hyphen (`libsdl3-ttf-0` became `libsdl3-ttf0`) when this
was first published. The runtime packages carry `Conflicts`/`Replaces` on the
old names so that anyone holding the `.deb` files from an earlier GitHub release
upgrades cleanly instead of hitting a file conflict.

### Versioning

Uploads are versioned `<SDL>+<VERSION>~<series><revision>` — for example
`3.4.16+1.0.0~noble1`. One source package carries six upstreams, so no single
upstream version identifies it: SDL3's leads so the package sorts sensibly
against a distro SDL3, and `VERSION` (which `clone.sh` bumps whenever *any*
pinned library moves) disambiguates the releases where SDL3 itself stood still.

**Launchpad accepts a version exactly once and there is no `--clobber`.** To
re-upload the same upstream versions — after a build failure, or a packaging
fix — re-run the workflow by hand with a higher `revision`.

### One-time setup

None of this can be automated; it has to be done once, by hand.

1. Sign the [Ubuntu Code of Conduct](https://launchpad.net/codeofconduct) on
   your Launchpad account, and create the PPA if it does not exist.
2. Create an OpenPGP key, publish it to the keyserver, and register its
   fingerprint at <https://launchpad.net/~tiglate/+editpgpkeys>. Launchpad
   confirms it by sending an encrypted email you have to decrypt and click.
3. Export the private key and store it as the repository secret
   `PPA_GPG_PRIVATE_KEY`:

   ```sh
   gpg --armor --export-secret-keys <key-id>
   ```

   If the key has a passphrase, store that as `PPA_GPG_PASSPHRASE` too; the
   workflow drives `gpg` through loopback pinentry when it is set.
4. Optionally set the repository variables `PPA_MAINTAINER_NAME` and
   `PPA_MAINTAINER_EMAIL`. They default to the `Maintainer` in `debian/control`,
   and the email should match an address on the signing key.

### Before an upload that matters

A Launchpad build failure costs a version number that cannot be reused, so run
the workflow by hand from the Actions tab with **dry_run** first. That builds the
source package and then rebuilds the binaries from it locally — the same thing
Launchpad is about to do — without uploading anything.

Adding another series (`jammy`, `plucky`, …) means running the workflow once per
series: each gets its own upload, versioned `~jammy1`, `~plucky1`, and so on.

Two differences from the `.deb` files `make.sh` produces are worth knowing about.
debhelper strips the shared libraries and emits matching `-dbgsym` packages,
which the local build does not — they land in the PPA's debug archive. And
`dpkg-shlibdeps` computes the inter-package dependencies from the libraries
themselves, rather than from the versions `make-sdl-ttf.sh` and
`make-sdl-mixer.sh` state by hand, because in a Launchpad chroot the
dependencies really are installed.

## Requirements

`cmake` (3.16+), `ninja-build`, `git`, `pkg-config`, `dpkg-dev`, and a C/C++
compiler. Linux only, and only really tested on Ubuntu.

## Notes

- `repos/`, `build/` and `dist/` are not tracked; `.version` is.
- Codecs are loaded on demand at run time, so a format also needs its shared
  library present. Those are not expressed as package dependencies — support
  degrades quietly instead of blocking installation.
- plutosvg and plutovg ship in one package pair: a single build produces both
  and they are versioned together.

## Licence

MIT, see [LICENSE](LICENSE). This repository only contains build scripts — the
libraries it packages are covered by their own licences (SDL3 and its satellites
are zlib, plutosvg and plutovg are MIT), and each package carries its upstream
licence as its `copyright` file.
