#!/bin/bash
# Spike B: build the game as a module with a bundled zig (no Apple tools),
# and load it from a prebuilt runtime that contains no game code.
#
# Usage: zig_module_spike.sh <split-out-dir from split_link_spike.sh> <zig-dir>
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SPLIT="$(cd "$1" && pwd)"
ZIG="$(cd "$2" && pwd)/zig"
SDK="$SPLIT/sdk"
OUT="$SPLIT/module"
rm -rf "$OUT"
mkdir -p "$OUT/obj" "$OUT/lib"

# ---- Prebuilt half (done once by us, with the normal toolchain) ----
# Runtime executable: runtime archive + module loader, exporting its symbols
# so the game module can call back into it.
cc -O2 -c "$REPO/platform/macos/game_module_loader.c" -o "$OUT/obj/loader.o"
STATIC_LIBS=()
for a in "$SDK"/lib/*.a; do
  [ "$(basename "$a")" = libpsxruntime.a ] || STATIC_LIBS+=("$a")
done
c++ -O3 -arch arm64 -o "$OUT/2Xtreme" "$OUT/obj/loader.o" \
    -Wl,-force_load,"$SDK/lib/libpsxruntime.a" "${STATIC_LIBS[@]}" \
    "$SDK"/dylibs/libSDL3.0.dylib "$SDK"/dylibs/libfreetype.6.dylib "$SDK"/dylibs/libharfbuzz.0.dylib \
    -lz -framework OpenGL -framework AppKit -framework Foundation -framework Cocoa \
    -Wl,-export_dynamic -Wl,-rpath,@executable_path/lib
codesign --force -s - "$OUT/2Xtreme"
cp "$SDK"/dylibs/*.dylib "$OUT/lib/"

# ---- Player half: only the bundled zig, Apple's tools hidden ----
CFLAGS=()
while IFS= read -r f; do
  case "$f" in -arch|arm64) ;; *) CFLAGS+=("$f") ;; esac
done < "$SDK/cflags.txt"
INCS=()
for d in "$SDK"/include/i*; do INCS+=("-I$d"); done

export ZIG_GLOBAL_CACHE_DIR="$OUT/zig-cache" ZIG_LOCAL_CACHE_DIR="$OUT/zig-cache"
start=$(date +%s)
pids=()
for c in "$SPLIT"/game/src/*.c; do
  env -i HOME="$HOME" PATH=/bin ZIG_GLOBAL_CACHE_DIR="$ZIG_GLOBAL_CACHE_DIR" ZIG_LOCAL_CACHE_DIR="$ZIG_LOCAL_CACHE_DIR" \
    "$ZIG" cc -target aarch64-macos.13.0 -fPIC "${CFLAGS[@]}" "${INCS[@]}" -I"$SPLIT/game/src" \
    -c "$c" -o "$OUT/obj/$(basename "$c").o" &
  pids+=($!)
done
for p in "${pids[@]}"; do wait "$p"; done
compiled=$(date +%s)
env -i HOME="$HOME" PATH=/bin ZIG_GLOBAL_CACHE_DIR="$ZIG_GLOBAL_CACHE_DIR" ZIG_LOCAL_CACHE_DIR="$ZIG_LOCAL_CACHE_DIR" \
  "$ZIG" cc -target aarch64-macos.13.0 -shared -undefined dynamic_lookup \
  -o "$OUT/game.dylib" "$OUT"/obj/SCUS_*.o
linked=$(date +%s)

# Read-only resources, same as the split product.
for r in bios assets game.toml game_options.toml keybinds.ini mods; do
  [ -e "$SPLIT/game/$r" ] && cp -R "$SPLIT/game/$r" "$OUT/"
done
rm -f "$OUT/mods/state.toml" "$OUT/input.ini"

echo "zig compile: $((compiled-start)) s, zig link: $((linked-compiled)) s"
echo "product: $OUT/2Xtreme (+ game.dylib)"
