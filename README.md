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
| `libsdl3-image-0` / `libsdl3-image-dev` | image loading (PNG, JPEG, WebP, AVIF, JXL, TIFF, SVG, …) |
| `libsdl3-mixer-0` / `libsdl3-mixer-dev` | audio mixing (WAV, FLAC, MP3, Vorbis, Opus, MOD, MIDI) |
| `libsdl3-net-0` / `libsdl3-net-dev` | TCP/UDP networking |
| `libsdl3-ttf-0` / `libsdl3-ttf-dev` | TrueType text, HarfBuzz shaping, colour emoji |
| `libplutosvg-0` / `libplutosvg-dev` | plutosvg + plutovg, which SDL3_ttf uses for colour emoji |

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
installed when you build. To cover essentially everything:

```sh
sudo apt install \
  libasound2-dev libpulse-dev libpipewire-0.3-dev libjack-jackd2-dev libsndio-dev \
  libx11-dev libxext-dev libxrandr-dev libxcursor-dev libxfixes-dev libxi-dev \
  libxss-dev libxkbcommon-dev libwayland-dev wayland-protocols libdecor-0-dev \
  libdrm-dev libgbm-dev libgl-dev libgles-dev libegl-dev libvulkan-dev \
  libudev-dev libdbus-1-dev libibus-1.0-dev libusb-1.0-0-dev liburing-dev \
  libfreetype-dev libharfbuzz-dev \
  libpng-dev libjpeg-dev libtiff-dev libwebp-dev libavif-dev libjxl-dev \
  libvorbis-dev libopusfile-dev libflac-dev libmpg123-dev libxmp-dev \
  libwavpack-dev libgme-dev libfluidsynth-dev
```

Run `./make.sh features` after a build to see what was actually enabled. If you
install something new afterwards, rebuild with `./make.sh --fresh`.

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
