# How should a player's Mac get the game code? (research, 2026-10-09)

The constraint: nothing disc-derived is in the download, so the recompiled
game code must be produced on the player's Mac from their own disc.
Generating the C takes 13 s with a bundled recompiler and Python. The open
question is **what compiles it**.

## Options compared

| Option | Player experience | Verdict |
|---|---|---|
| **A. Apple's Command Line Tools** (system clang). Used by the shipped Road Trip port; the RetroPortingToolKit Mac toolchain also requires it. | Works, about a minute. But players without the tools must first install them: a large Apple download, several minutes, possibly an admin password. It's the riskiest step in our journey map. | **Proven fallback.** Already spiked: compile+link in ~2 s. |
| **B. Bundled compiler (`zig cc`, which carries clang, lld, macOS libc headers and libSystem stubs). Game built as a loadable module the prebuilt runtime opens.** | No Apple tools, works offline, same clang -O3 code, same speed. About 50 MB more download. | **Recommended**, subject to a 1-day spike. |
| C. Ship the compiled game code (Zelda64Recomp-style) | Zero setup | Rejected: owner's rule, nothing disc-derived is distributed. |
| D. Ship compiled code encrypted with a key from the disc | Zero setup | Rejected: still distributes derived code. |
| E. Run the game exe in psxrecomp's interpreter | Zero setup | Rejected for v1: it's emulation, slower, and not this project. |
| F. Bundled TinyCC | Small | Rejected: Apple Silicon support is unreliable and its code is unoptimised. |

## Why B is feasible here

Measured on the split build:

- The runtime needs only **6 symbols** from the game code
  (`psx_dispatch_game_compiled`, `psx_game_address_in_text`,
  `psx_game_is_function_entry`, `psx_game_text_native_ok`, …). Loading them
  from a module with `dlsym` is a small, contained runtime change.
- The game C includes only `stdint.h`, `stddef.h`, `stdio.h` and `string.h`
  from the system. `zig cc` ships those headers.
- The game module links with `-undefined dynamic_lookup` against the runtime
  executable, so it needs no Apple frameworks. That avoids the one thing a
  bundled toolchain can't legally provide: Apple's SDK framework stubs.

## Licences

zig: MIT. Its bundled LLVM/clang/lld: Apache-2.0 with LLVM exception. Its
macOS libc headers and stubs are redistributed by the zig project. All are
compatible with a free, noncommercial release (psxrecomp is PolyForm
Noncommercial).

## Decision

1. Spike B for at most a day: build the game module with bundled `zig cc`,
   load it from the prebuilt runtime, reach the main menu, with no Apple
   tools on the path.
2. If the spike passes, B becomes the first-run method and the Apple-tools
   screen disappears from the journey.
3. If it fails, ship A with a carefully designed Apple-tools screen.

Sources: Road Trip README (github.com/silentsudin/RoadTripAdventure-recomp),
RetroPorting-Toolchains README, zig issue #10217 and rust-lang/rust#131477
(zig cc links for macOS without Xcode), TinyCC Apple Silicon reports.
