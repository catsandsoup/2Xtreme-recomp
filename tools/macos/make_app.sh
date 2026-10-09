#!/bin/bash
# Build the distributable 2Xtreme.app (no game code inside).
#
#   ZIG_DIST=<unpacked zig-aarch64-macos dir> tools/macos/make_app.sh [out-dir]
#
# Contents/MacOS/2Xtreme          launcher (first-run setup, then starts the game)
# Contents/Resources/runtime/     prebuilt runtime with no game code + libraries
# Contents/Resources/sdk/         headers and flags to compile the player's game C
# Contents/Resources/project/     recompiler config (game.toml, seeds, BIOS profiles)
# Contents/Resources/tools/       psxrecomp-game (the recompiler)
# Contents/Resources/toolchain/   pruned zig (clang + linker + macOS libc stubs)
# Contents/Resources/licenses/    third-party notices
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:-$REPO/dist}"
mkdir -p "$OUT" && OUT="$(cd "$OUT" && pwd)"   # the script cd's around; keep OUT absolute
BUILD="$REPO/build-shipping"
: "${ZIG_DIST:?set ZIG_DIST to an unpacked zig-aarch64-macos release}"
# Oldest macOS the app runs on. Homebrew's SDL3/FreeType/HarfBuzz bottles set
# the floor (they are built for macOS 26); our own code is built to match.
MACOS_MIN=26.0
export MACOSX_DEPLOYMENT_TARGET="$MACOS_MIN"
APP="$OUT/2Xtreme.app"
C="$APP/Contents"
RES="$C/Resources"

echo "== 1/7 Runtime (OpenBIOS only: no Sony BIOS code)"
cmake -S "$REPO" -B "$BUILD" -G Ninja -DCMAKE_BUILD_TYPE=Release -DPSXRECOMP_BIOS_STEMS=OpenBIOS \
      -DTWOX_GAME_MODULE_HOST=ON -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOS_MIN" \
      -DCMAKE_DISABLE_FIND_PACKAGE_SDL3=ON >/dev/null   # pinned SDL3, built for MACOS_MIN
cmake --build "$BUILD" --target psx-runtime >/dev/null

rm -rf "$APP"
mkdir -p "$C/MacOS" "$RES"/{runtime/lib,sdk/include,project/bios,tools,toolchain,licenses}

echo "== 2/7 Prebuilt runtime that loads the player's game module"
cd "$BUILD"
LINK="$(ninja -t commands psx-runtime | grep -- '-o 2Xtreme.app/Contents/MacOS/2Xtreme ' | tail -1)"
LINK="${LINK#: && }"
LINK="${LINK%% && *}"
OBJS=(); STATIC=(); DYLIBS=(); SYSLIBS=()
abs() { case "$1" in /*) echo "$1" ;; *) echo "$BUILD/$1" ;; esac; }
prev=""
for tok in $LINK; do
  # System frameworks SDL3 needs, incl. weak ones passed as -Xlinker pairs.
  if [ "$prev" = "-framework" ] || [ "$prev" = "-Xlinker" ]; then SYSLIBS+=("$prev" "$tok"); prev=""; continue; fi
  case "$tok" in
    *generated/SCUS_*.o|*game_sdk_probe.c.o) ;;   # never game code in the runtime
    *.o) OBJS+=("$(abs "$tok")") ;;
    *.a) STATIC+=("$(abs "$tok")") ;;
    *.dylib) DYLIBS+=("$tok") ;;
    -l*) SYSLIBS+=("$tok") ;;
  esac
  prev="$tok"
done
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Bundle every non-system dylib, recursively, under @rpath.
is_foreign() { case "$1" in /usr/lib/*|/System/*|@*) return 1 ;; *) return 0 ;; esac; }
bundle_dylib() {
  local src name dst dep
  src="$(readlink -f "$1")"
  name="$(basename "$(otool -D "$src" | tail -1)")"
  dst="$RES/runtime/lib/$name"
  [ -e "$dst" ] && return 0
  cp "$src" "$dst"; chmod u+w "$dst"
  install_name_tool -id "@rpath/$name" "$dst" 2>/dev/null
  for dep in $(otool -L "$dst" | tail -n +2 | awk '{print $1}'); do
    if is_foreign "$dep"; then
      bundle_dylib "$dep"
      install_name_tool -change "$dep" "@rpath/$(basename "$dep")" "$dst" 2>/dev/null
    fi
  done
  codesign --force -s - "$dst" 2>/dev/null
}
BUNDLED=()
for d in "${DYLIBS[@]}"; do
  bundle_dylib "$d"
  BUNDLED+=("$RES/runtime/lib/$(basename "$(otool -D "$(readlink -f "$d")" | tail -1)")")
done
c++ -O3 -arch arm64 -o "$RES/runtime/2Xtreme" "${OBJS[@]}" "${STATIC[@]}" "${BUNDLED[@]}" \
    ${SYSLIBS[@]+"${SYSLIBS[@]}"} -lz -framework OpenGL -framework AppKit -framework Foundation -framework Cocoa \
    -Wl,-export_dynamic -Wl,-rpath,@executable_path/lib
codesign --force -s - "$RES/runtime/2Xtreme"
APPDIR="$BUILD/2Xtreme.app/Contents/MacOS"
for r in bios assets mods game.toml game_options.toml; do cp -R "$APPDIR/$r" "$RES/runtime/"; done
cp "$REPO/recomp-ui/keybinds.ini" "$RES/runtime/" 2>/dev/null || true
rm -f "$RES/runtime/mods/state.toml"

echo "== 3/7 SDK: headers and flags for the game C"
CC_CMD="$(ninja -t commands psx-runtime | grep -- 'platform/macos/game_sdk_probe.c' | grep -- ' -c ' | head -1)"
[ -n "$CC_CMD" ] || { echo "make_app: no compile command for the game C flags"; exit 1; }
eval "TOKS=($CC_CMD)"
FLAGS=(); INCS=()
i=0
while [ $i -lt ${#TOKS[@]} ]; do
  t="${TOKS[$i]}"
  case "$t" in
    -D*|-O*|-std=*|-f*|-W*) FLAGS+=("$t") ;;
    -I*) INCS+=("${t#-I}") ;;
    -isystem) i=$((i+1)); INCS+=("${TOKS[$i]}") ;;
  esac
  i=$((i+1))
done
printf '%s\n' "${FLAGS[@]}" > "$RES/sdk/cflags.txt"
n=0
for inc in "${INCS[@]}"; do
  case "$inc" in "$REPO"/*) ;; *) continue ;; esac   # game C only needs our headers
  dst="$RES/sdk/include/i$(printf '%02d' $n)"
  mkdir -p "$dst"
  (cd "$inc" && find . -name '*.h' -print0 | xargs -0 -I{} rsync -R {} "$dst/")
  n=$((n+1))
done
cd "$REPO"

echo "== 4/7 Recompiler and its config"
psxrecomp/tools/ci/build_emitters.sh --build-dir "$BUILD/recompiler" >/dev/null
cp "$BUILD/recompiler/psxrecomp-game" "$RES/tools/"
cp game.toml game_options.toml symbols.toml "$RES/project/"
cp -R seeds "$RES/project/"
cp psxrecomp/bios/*.toml "$RES/project/bios/"

echo "== 5/7 Bundled compiler (pruned zig)"
Z="$RES/toolchain"
cp "$ZIG_DIST/zig" "$ZIG_DIST/LICENSE" "$Z/"
mkdir -p "$Z/lib/libc/include"
cp -R "$ZIG_DIST/lib/std" "$ZIG_DIST/lib/compiler_rt" "$ZIG_DIST/lib/include" "$Z/lib/"
cp "$ZIG_DIST"/lib/*.zig "$ZIG_DIST"/lib/*.h "$Z/lib/" 2>/dev/null || true
cp -R "$ZIG_DIST/lib/libc/darwin" "$Z/lib/libc/"
for d in "$ZIG_DIST"/lib/libc/include/*darwin* "$ZIG_DIST"/lib/libc/include/*macos*; do
  [ -e "$d" ] && cp -R "$d" "$Z/lib/libc/include/"
done

echo "== 6/7 Launcher"
cc -O2 -fobjc-arc -Wall -Wno-deprecated-declarations \
   "$REPO/platform/macos/launcher/main.m" "$REPO/platform/macos/launcher/disc.c" \
   -framework Cocoa -framework GameController -o "$C/MacOS/2Xtreme"
VERSION="$(cat "$REPO/VERSION")"
BUILD_ID="$(git -C "$REPO" rev-parse --short HEAD)"
# Uncommitted work: add the runtime's hash, so a local rebuild re-prepares
# the installed game instead of silently keeping the old one.
if ! git -C "$REPO" diff --quiet HEAD -- . ':!psxrecomp' || ! git -C "$REPO/psxrecomp" diff --quiet HEAD; then
  BUILD_ID="$BUILD_ID+$(shasum "$RES/runtime/2Xtreme" | cut -c1-7)"
fi
sed -e "s/<string>1.0.0<\/string>/<string>$VERSION<\/string>/" \
    -e "s/<key>CFBundleVersion<\/key>\n\s*<string>1<\/string>//" \
    "$REPO/platform/macos/Info.plist" > "$C/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_ID" "$C/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string $MACOS_MIN" "$C/Info.plist"
ICONSET="$TMP/AppIcon.iconset"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$REPO/assets/psxrecomp.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$REPO/assets/psxrecomp.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$RES/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$C/Info.plist"

echo "== 7/7 Licences, signing, release guard"
cp psxrecomp/LICENSE "$RES/licenses/psxrecomp-PolyForm-Noncommercial.txt"
cp psxrecomp/bios/OpenBIOS.LICENSE "$RES/licenses/OpenBIOS.txt"
cp recomp-ui/LICENSE "$RES/licenses/recomp-ui.txt"
cp "$ZIG_DIST/LICENSE" "$RES/licenses/zig.txt"
cp -R psxrecomp/runtime/licenses/. "$RES/licenses/" 2>/dev/null || true
cp "$BUILD/_deps/sdl3-src/LICENSE.txt" "$RES/licenses/SDL3-LICENSE.txt"
for lib in freetype harfbuzz; do
  for f in /opt/homebrew/opt/$lib/{LICENSE*,COPYING*,LICENSE.txt,docs/FTL.TXT}; do
    [ -f "$f" ] && cp "$f" "$RES/licenses/$lib-$(basename "$f")"
  done
done
codesign --force --deep -s - "$APP"

# Release guard: nothing disc-derived, no local paths, no dev state.
bad=0
for pat in 'generated/SCUS' 'SCUS_945.08_full' 'overlay_captures' 'settings.toml' 'state.toml' 'SCPH1001_full'; do
  if find "$APP" -path "*$pat*" | grep -q .; then echo "GUARD: found $pat"; bad=1; fi
done
if grep -rIl "/Users/" "$RES/project" "$RES/sdk/cflags.txt" "$RES/runtime/game.toml" 2>/dev/null | grep -q .; then
  echo "GUARD: local path found"; bad=1
fi
if nm "$RES/runtime/2Xtreme" | grep -q "func_8001"; then echo "GUARD: game code in runtime"; bad=1; fi
while IFS= read -r f; do
  minos="$(otool -l "$f" | awk '/LC_BUILD_VERSION/{b=1} b&&/minos/{print $2; exit}')"
  if [ -n "$minos" ] && [ "$(printf '%s\n%s\n' "$minos" "$MACOS_MIN" | sort -V | tail -1)" != "$MACOS_MIN" ]; then
    echo "GUARD: $(basename "$f") needs macOS $minos (app promises $MACOS_MIN)"; bad=1
  fi
done < <(find "$APP" -type f \( -perm -u+x -o -name '*.dylib' \) -exec sh -c 'file -b "$1" | grep -q Mach-O && echo "$1"' _ {} \;)
[ $bad = 0 ] || { echo "release guard FAILED"; exit 1; }
echo "release guard OK"
du -sh "$APP"
echo "built $APP"
