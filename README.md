# 2Xtreme for Mac

Play **2Xtreme** (PlayStation, 1996), skating, biking, blading and
snowboarding around the world, as a native Mac app. Bring your own disc:
the app builds the game on your Mac from your copy, the first time you open
it. No emulator setup and no BIOS file needed.

> **Status: work in progress, no download yet.** First launch and the pause
> menu work; the rest of the roadmap is in [docs/ROADMAP.md](docs/ROADMAP.md).

## How it will work for players

1. Download `2Xtreme.app` and drag it to Applications.
2. Open it and choose (or drop) your **2Xtreme (USA)** disc image. Use the
   `.cue` file so the music tracks come along.
3. Wait about 15 seconds while it prepares the game for your Mac. Then you're
   at the 2Xtreme intro. Later launches go straight to the game.

**What you need:** a Mac with Apple silicon, and your own disc image of
2Xtreme (USA), SCUS-94508, as `.cue` + `.bin` (or a single `.bin` / `.iso`,
without music). `.chd` isn't supported yet. You don't need Xcode, Apple's
command line tools, Homebrew or Python.

**In the game:** press **Esc** (or **⌘,**, the controller's **Guide**
button, or **Select + Start**) to pause and open the menu: Resume, Picture
(sharpness, textures, full screen), Sound (volume), Quit. Changes apply
straight away and are remembered.

**Your files** live in `~/Library/Application Support/2Xtreme/`:

| Folder | Holds |
|---|---|
| `disc/` | A copy of your disc image, so the game never loses it |
| `game/` | The game built from it, plus `settings.toml` |
| `saves/` | Memory cards (`card1.mcd`, `card2.mcd`) |

To start over, quit and delete that folder.

## What's done and what isn't

| | |
|---|---|
| ✅ First launch: disc check, preparing in ~15 s, straight in afterwards | |
| ✅ Pause menu in 2Xtreme's style (keyboard verified; controller still to test) | |
| ⏳ The game's own **Options** item opens the same menu | M4 |
| ⏳ Full speed everywhere, verified picture settings, maybe true widescreen | M5 |
| ⏳ Controller rebinding, rumble, Player 2, save states | M6 |
| ⏳ Downloadable release | M7 |

Gameplay is the original. Experiments (16 racers, forced high-detail models)
are developer-only and off.

## Legal

You must own the original game. Nothing from the disc, no game code and no
BIOS is in this repository or in the app: the game code is generated on your
Mac from your own disc and stays there. The app runs on the bundled MIT
OpenBIOS. psxrecomp is PolyForm Noncommercial, so releases are free.

## For developers

Start with [docs/HANDOFF.md](docs/HANDOFF.md). Project rules:
[docs/PRODUCT_RULES.md](docs/PRODUCT_RULES.md), design:
[docs/DESIGN_PRINCIPLES.md](docs/DESIGN_PRINCIPLES.md), player journey:
[docs/PLAYER_JOURNEY.md](docs/PLAYER_JOURNEY.md), why on-device building:
[docs/DISTRIBUTION_RESEARCH.md](docs/DISTRIBUTION_RESEARCH.md).

Build the app (needs Xcode, CMake, Ninja, Homebrew SDL3/FreeType/HarfBuzz,
and zig 0.16.0 unpacked somewhere):

```bash
git submodule update --init --recursive
git -C psxrecomp apply ../patches/psxrecomp/*.patch
./psxrecomp/tools/ci/build_emitters.sh
ZIG_DIST=/path/to/zig-aarch64-macos-0.16.0 tools/macos/make_app.sh dist
```

`dist/2Xtreme.app` contains no game code. Test hooks (fresh data folder,
automatic disc pick, scripted menu input) are listed in the handoff.

Dev build with debug tools, from your own disc (the generated C stays local):

```bash
python3 psxrecomp/psxrecomp_cli.py generate \
  --config game.toml --project-root . --disc disc/<your>.cue
cmake -S . -B build-release -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build-release --target psx-runtime
```

Built on [psxrecomp](https://github.com/mstan/psxrecomp) and
[recomp-ui](https://github.com/RetroPortingToolKit/recomp-ui). Symbols:
`symbols.toml` → `python3 tools/sync_symbols.py` → `psx_symbols.h` (see
`psxrecomp/docs/SYMBOLS.md`).

<!-- retcomm-readme-raid -->
---

<p align="center">
  <sub><b>R.A.I.D. — Retro AI Development</b> · a Discord for AI-assisted retro reverse-engineering, decomp &amp; recomp</sub>
</p>

<p align="center">
  <a href="https://discord.gg/Ad9BwSzctP"><img src=".github/raid-discord.png" alt="Join the Retro AI Development (R.A.I.D.) Discord" width="200"></a>
</p>
<!-- /retcomm-readme-raid -->
