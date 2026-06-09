# Building Hugin from source on Apple Silicon macOS

The Homebrew cask (`brew install --cask hugin`) is deprecated as of
2025-11: it ships an x86_64 binary that runs under Rosetta, and the
Tip-of-the-Day startup dialog deadlocks on macOS 14+ inside
`CABackingStoreGetFrontTexture`. Native arm64 needs a from-source build.

Upstream is alive on SourceForge Mercurial (`tmodes` still landing
commits in 2026), so the from-source path is viable. The dated git
mirror on GitHub is stale (2019) — don't use it.

## Get the source

```bash
brew install mercurial
cd ~/Development
hg clone http://hg.code.sf.net/p/hugin/hugin hugin-hg
```

## Dependencies (Homebrew)

```bash
brew install cmake llvm wxwidgets boost exiv2 openexr libtiff libpng \
             little-cms2 fftw glew libpano gettext sqlite gsl hdf5 \
             lapack jpeg-turbo imath libomp pkg-config
```

Two non-brew deps need to be built from source:
- **vigra** (upstream `ukoethe/vigra` on GitHub)
- **enblend/enfuse** (`hg clone http://hg.code.sf.net/p/enblend/code enblend-enfuse`)

Both should install to a local prefix, e.g. `~/Development/hugin-prefix`.

## Build vigra

```bash
git clone --depth 1 https://github.com/ukoethe/vigra.git
cd vigra && mkdir build && cd build
cmake .. \
  -DCMAKE_INSTALL_PREFIX="$HOME/Development/hugin-prefix" \
  -DCMAKE_PREFIX_PATH="/opt/homebrew" \
  -DWITH_OPENEXR=ON -DWITH_HDF5=OFF -DWITH_LEMON=OFF \
  -DWITH_BOOST_GRAPH=OFF -DWITH_VIGRANUMPY=OFF \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
  -DBUILD_SHARED_LIBS=ON
make -j$(sysctl -n hw.ncpu) && make install
```

## Build enblend/enfuse

Enblend's CMakeLists doesn't bundle OpenMP linker flags — its
`set_target_properties(... LINK_FLAGS ${OpenMP_CXX_FLAGS})` directly
substitutes whatever `OpenMP_CXX_FLAGS` contains. So `-L .../libomp/lib
-lomp` must go in `OpenMP_CXX_FLAGS` (not in `CMAKE_EXE_LINKER_FLAGS`).

```bash
cd ~/Development/enblend-enfuse && mkdir build && cd build
cmake .. \
  -DCMAKE_INSTALL_PREFIX="$HOME/Development/hugin-prefix" \
  -DCMAKE_PREFIX_PATH="$HOME/Development/hugin-prefix;/opt/homebrew;/opt/homebrew/opt/libomp" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
  -DENABLE_OPENMP=ON \
  -DOpenMP_C_FLAGS="-Xpreprocessor -fopenmp -I/opt/homebrew/opt/libomp/include -L/opt/homebrew/opt/libomp/lib -lomp" \
  -DOpenMP_CXX_FLAGS="-Xpreprocessor -fopenmp -I/opt/homebrew/opt/libomp/include -L/opt/homebrew/opt/libomp/lib -lomp" \
  -DOpenMP_C_LIB_NAMES="omp" -DOpenMP_CXX_LIB_NAMES="omp" \
  -DOpenMP_omp_LIBRARY="/opt/homebrew/opt/libomp/lib/libomp.dylib"
make -j$(sysctl -n hw.ncpu) && make install
```

Use Apple's clang (the default), not brew's `llvm`. brew llvm's libc++
includes get into a fight with the SDK's C headers
(`<cerrno> tried including <errno.h> but didn't find libc++'s <errno.h>`).

## Build Hugin

Two patches needed (committed on the `macos-arm64-build` branch in the
local hg clone):

1. **Deployment target 10.9 → 11.0** in `CMakeLists.txt`. Hugin's
   `std::filesystem` usage in `src/hugin_base/hugin_utils/utils.cpp`
   requires 10.15+, and 11.0 is the Apple Silicon floor anyway.
2. **Decouple bundle lookup from `MAC_SELF_CONTAINED_BUNDLE`**. With
   the flag OFF, Hugin's runtime falls through to "bare name on PATH",
   so it can't find cpfind/nona/enblend from inside its own .app
   bundle. The patch removes the `#if defined MAC_SELF_CONTAINED_BUNDLE`
   guard around `MacGetPathToBundledExecutableFile` and its callers
   in `Executor.cpp`, `platform.{h,cpp}`, and `AutoCtrlPointCreator.cpp`.

Why not just set `MAC_SELF_CONTAINED_BUNDLE=ON`? The flag also
activates `mac/PackageMacAppBundleLibs.sh` which tries to copy every
linked dylib into the bundle and resolve `@rpath/` references — and
fails on modern brew dylibs.

```bash
cd ~/Development/hugin-hg && mkdir build && cd build
cmake .. \
  -DCMAKE_INSTALL_PREFIX="$HOME/Development/hugin-prefix" \
  -DCMAKE_PREFIX_PATH="$HOME/Development/hugin-prefix;/opt/homebrew;/opt/homebrew/opt/libomp;/opt/homebrew/opt/wxwidgets" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_HSI=OFF \
  -DMAC_SELF_CONTAINED_BUNDLE=OFF \
  -DwxWidgets_CONFIG_EXECUTABLE=/opt/homebrew/opt/wxwidgets/bin/wx-config
make -j$(sysctl -n hw.ncpu) && make install
```

## Post-install: rpath, signature, tool symlinks

The install step doesn't add rpath to any of the installed binaries,
nor does it symlink the CLI tools into the .app bundles where Hugin
and PTBatcherGUI look for them.

```bash
PREFIX=$HOME/Development/hugin-prefix

# 1. rpath + ad-hoc sign every Mach-O in bin/
#    (Apple Silicon refuses to run unsigned binaries; the linker
#    adds an ad-hoc signature by default but install_name_tool
#    invalidates it.)
for bin in "$PREFIX/bin"/*; do
  file "$bin" 2>/dev/null | grep -q 'Mach-O' || continue
  install_name_tool -add_rpath "$PREFIX/lib" "$bin" 2>/dev/null
  codesign --force --sign - "$bin" 2>/dev/null
done

# 2. Same for Hugin.app and PTBatcherGUI.app main binaries
for app in Hugin PTBatcherGUI; do
  bin="$PREFIX/Applications/$app.app/Contents/MacOS/$app"
  install_name_tool -add_rpath "$PREFIX/lib" "$bin"
  codesign --force --sign - "$bin"
done

# 3. Symlink CLI tools into both .app bundles' MacOS dir
#    Hugin's patched lookup calls CFBundleCopyAuxiliaryExecutableURL,
#    which only checks the calling process's own bundle. So tools
#    needed by Hugin go in Hugin.app, tools needed by PTBatcherGUI
#    go in PTBatcherGUI.app.
TOOLS="cpfind autooptimiser nona enblend enfuse celeste_standalone
icpfind cpclean linefind vig_optimize align_image_stack pano_modify
pto_var pto_gen pto_lensstack pto_merge pto_template pto_mask pto_move
geocpset checkpto deghosting_mask fulla hugin_executor hugin_hdrmerge
hugin_stacker hugin_lensdb verdandi tca_correct exiftool pano_trafo"
for app in Hugin PTBatcherGUI; do
  for t in $TOOLS; do
    src="$PREFIX/bin/$t"
    dst="$PREFIX/Applications/$app.app/Contents/MacOS/$t"
    [ -x "$src" ] && [ ! -e "$dst" ] && ln -s "$src" "$dst"
  done
done

# 4. Hugin needs PTBatcherGUI in its own bundle to launch it (via
#    wxExecute on the path next to the Hugin binary)
ln -s "$PREFIX/Applications/PTBatcherGUI.app/Contents/MacOS/PTBatcherGUI" \
      "$PREFIX/Applications/Hugin.app/Contents/MacOS/PTBatcherGUI"
```

## Launching

`open Hugin.app` (or Finder/Spotlight double-click) works once the
ad-hoc signature is in place. LaunchServices on macOS 15+ rejects
unsigned binaries (`_LSOpenURLsWithCompletionHandler failed with
error -54` / "Launch requires secure launch with spawn constraints").

Direct launch via `Hugin.app/Contents/MacOS/Hugin` also works.

A shell-script main executable in the bundle breaks LaunchServices
(bundle is considered malformed). If you need to inject env vars, do
it from a launcher script *outside* the bundle, not by replacing the
main exec.

## GUI gotchas (one-time)

- **Preferences → General → Copy log messages to clipboard.** Without
  this, the assistant dialog auto-closes on failure and you have no
  way to see what cpfind/autooptimiser actually said.
- **View → Interface → Expert** to expose TrX/TrY/TrZ columns in the
  Optimizer tab. Required for translation-based mosaic optimization.
- **Photos tab → Optimize → Geometric → "Custom parameters"** to make
  the Optimizer tab itself appear in the notebook. Presets hide it.

## Workflow: copy-stand flat-art mosaic

See `~/dots/bin/scripts/stitch-mosaic.sh` for a scripted version of:

1. `pto_gen` to seed the project from EXIF
2. `cpfind --multirow` (not `--linearmatch`) to detect a grid layout
3. `cpclean` to drop CP outliers
4. `pto_var --opt TrX,TrY` to mark camera translation (anchor stays
   pinned)
5. `autooptimiser -n` to run the optimizer on those vars
6. `pano_modify --projection=0 --fov=AUTO --canvas=AUTO --crop=AUTO`
7. `hugin_executor --stitching` to run nona + enblend

Don't optimize TrZ unless the camera physically moved closer/farther
between frames. Don't optimize y/p/r unless the copy stand tilted.
Residuals in pixel units scale with image size — on a 24MP frame,
20–40px residual is fine (≈0.5% of frame width).
