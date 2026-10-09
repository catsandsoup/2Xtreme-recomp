#!/bin/bash
# Spike: prove the on-device split works.
#
#   1. Package the prebuilt runtime (everything except the game's generated C)
#      into an SDK folder: one static archive, the static deps, the dylibs,
#      only the headers the generated C includes, and the exact compile flags.
#   2. In a clean product folder that never touches the repo, compile freshly
#      generated game C against that SDK, link, and stage read-only resources.
#
# Usage: split_link_spike.sh <build-dir> <generated-dir> <out-dir>
# Nothing disc-derived goes into the SDK; the generated C only reaches <out-dir>.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="$(cd "$1" && pwd)"
GEN="$(cd "$2" && pwd)"
OUT="$3"
SDK="$OUT/sdk"
GAME="$OUT/game"
rm -rf "$OUT"
mkdir -p "$SDK/lib" "$SDK/include" "$GAME/obj" "$GAME/lib"

cd "$BUILD"
LINK="$(ninja -t commands psx-runtime | grep -- '-o 2Xtreme.app/Contents/MacOS/2Xtreme ' | tail -1)"
LINK="${LINK#: && }"
LINK="${LINK%% && *}"

# ---- 1. SDK: runtime archive (all objects except the game's generated C) ----
RUNTIME_OBJS=()
for tok in $LINK; do
  case "$tok" in
    *generated/SCUS_*.o) ;;
    *.o) RUNTIME_OBJS+=("$BUILD/$tok") ;;
  esac
done
ar rcs "$SDK/lib/libpsxruntime.a" "${RUNTIME_OBJS[@]}"

# Static deps and dylibs named on the link line.
STATIC_LIBS=()
DYLIBS=()
for tok in $LINK; do
  case "$tok" in
    *.a) cp "$BUILD/$tok" "$SDK/lib/"; STATIC_LIBS+=("$SDK/lib/$(basename "$tok")") ;;
    *.dylib) DYLIBS+=("$tok") ;;
  esac
done

# Compile flags for the generated C (taken from the real build).
CC_CMD="$(ninja -t commands psx-runtime | grep -- 'generated/SCUS_945.08_full_00.c' | grep -- ' -c ' | head -1)"
DEFINES=()
INCS=()
# Let the shell unquote the command exactly as ninja would run it.
eval "TOKS=($CC_CMD)"
i=0
while [ $i -lt ${#TOKS[@]} ]; do
  t="${TOKS[$i]}"
  case "$t" in
    -D*) DEFINES+=("$t") ;;
    -I*) INCS+=("${t#-I}") ;;
    -isystem) i=$((i+1)); INCS+=("${TOKS[$i]}") ;;
    -O*|-std=*|-arch|arm64|-f*|-W*) DEFINES+=("$t") ;;
  esac
  i=$((i+1))
done

# Copy only the headers the generated C actually includes, keyed by include root.
HDRS="$(cc "${DEFINES[@]}" $(printf -- '-I%s ' "${INCS[@]}") -M "$GEN/SCUS_945.08_full_00.c" "$GEN/SCUS_945.08_dispatch.c" \
        | tr ' \\' '\n\n' | grep '\.h$' | sort -u)"
SDK_INCS=()
n=0
for inc in "${INCS[@]}"; do
  dst="$SDK/include/i$n"
  mkdir -p "$dst"
  SDK_INCS+=("$dst")
  for h in $HDRS; do
    case "$h" in
      "$inc"/*) rel="${h#"$inc"/}"; mkdir -p "$dst/$(dirname "$rel")"; cp "$h" "$dst/$rel" ;;
    esac
  done
  n=$((n+1))
done
printf '%s\n' "${DEFINES[@]}" > "$SDK/cflags.txt"

# Bundle every non-system dylib, following dependencies recursively, and
# point them all at @rpath so nothing loads from /opt/homebrew on a player's Mac.
mkdir -p "$SDK/dylibs"
is_foreign() { case "$1" in /usr/lib/*|/System/*|@*) return 1 ;; *) return 0 ;; esac; }
bundle_dylib() {
  local src name dst dep
  src="$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")"
  src="$(readlink -f "$src")"
  name="$(basename "$(otool -D "$src" | tail -1)")"
  dst="$SDK/dylibs/$name"
  [ -e "$dst" ] && return 0
  cp "$src" "$dst"
  chmod u+w "$dst"
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
  BUNDLED+=("$SDK/dylibs/$(basename "$(otool -D "$(readlink -f "$d")" | tail -1)")")
done

# ---- 2. Product: compile fresh game C against the SDK, outside the repo ----
mkdir -p "$GAME/src"
cp "$GEN"/*.c "$GEN"/*.h "$GAME/src/"
start=$(date +%s)
pids=()
for c in "$GAME"/src/*.c; do
  cc "${DEFINES[@]}" $(printf -- '-I%s ' "${SDK_INCS[@]}") -I"$GAME/src" \
     -c "$c" -o "$GAME/obj/$(basename "$c").o" &
  pids+=($!)
done
for p in "${pids[@]}"; do wait "$p"; done
compiled=$(date +%s)

cp "$SDK"/dylibs/*.dylib "$GAME/lib/"
c++ -O3 -arch arm64 -o "$GAME/2Xtreme" "$GAME"/obj/*.o \
    -Wl,-force_load,"$SDK/lib/libpsxruntime.a" "${STATIC_LIBS[@]}" \
    "${BUNDLED[@]}" \
    -lz -framework OpenGL -framework AppKit -framework Foundation -framework Cocoa \
    -Wl,-rpath,@executable_path/lib
codesign --force -s - "$GAME/2Xtreme"
linked=$(date +%s)

# Read-only resources from the built app (never settings, captures or mod state).
APPDIR="$BUILD/2Xtreme.app/Contents/MacOS"
for r in bios assets game.toml game_options.toml keybinds.ini; do
  [ -e "$APPDIR/$r" ] && cp -R "$APPDIR/$r" "$GAME/"
done
mkdir -p "$GAME/mods"
[ -d "$BUILD/mods/bundled" ] && cp -R "$BUILD/mods/bundled" "$GAME/mods/"

echo "compile: $((compiled-start)) s, link: $((linked-compiled)) s"
echo "headers copied: $(find "$SDK/include" -name '*.h' | wc -l | tr -d ' ')"
echo "product: $GAME/2Xtreme"
