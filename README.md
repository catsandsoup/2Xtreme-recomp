# 2Xtreme for Mac

Play **2Xtreme** (PlayStation, 1996), skating, biking, blading and
snowboarding around the world, as a native Mac app. Bring your own disc:
the app builds the game on your Mac from your copy, the first time you open
it. No emulator setup and no BIOS file needed.

> **Status: early preview, built in public.** First launch and the pause
> menu work; the rest of the roadmap is in [docs/ROADMAP.md](docs/ROADMAP.md).
> Download the latest preview from
> [Releases](https://github.com/catsandsoup/2Xtreme-recomp/releases), or build
> it yourself (below).

## How it works for players

1. Download `2Xtreme.zip` from
   [Releases](https://github.com/catsandsoup/2Xtreme-recomp/releases), unzip
   it and drag `2Xtreme.app` to Applications.
2. The app isn't notarized by Apple yet, so the first time macOS will refuse
   to open it. Open it once, then go to **System Settings → Privacy &
   Security**, scroll down and click **Open Anyway**.
3. Choose (or drop) your **2Xtreme (USA)** disc image. Use the
   `.cue` file so the music tracks come along.
4. Wait about 15 seconds while it prepares the game for your Mac. Then you're
   at the 2Xtreme intro. Later launches go straight to the game.

**What you need:** a Mac with Apple silicon on macOS 26 or later, and your own disc image of
2Xtreme (USA), SCUS-94508, as `.cue` + `.bin` (or a single `.bin` / `.iso`,
without music). `.chd` isn't supported yet. You don't need Xcode, Apple's
command line tools, Homebrew or Python.

**In the game:** press **Esc** (or **⌘,**, the controller's **Guide**
button, or **Select + Start**) to pause and open the menu: Resume, Picture
(sharpness, textures, full screen), Sound (volume), Quit. Changes are
remembered; picture changes show as soon as you resume.

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
| ✅ Preview download (not notarized yet) | |
| ⏳ Signed, notarized release; older macOS versions | M7 |

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

### Build the app from source

You don't need the disc to build the app: it contains no game code and
builds the game on first launch, like the download. You need an Apple
silicon Mac on macOS 26+, Apple's command line tools (`xcode-select
--install`), [Homebrew](https://brew.sh) and
[zig 0.16.0](https://ziglang.org/download/0.16.0/zig-aarch64-macos-0.16.0.tar.xz)
(sha256 `b23d70deaa879b5c2d486ed3316f7eaa53e84acf6fc9cc747de152450d401489`),
which the app bundles as its on-device compiler.

```bash
brew install cmake ninja freetype harfbuzz
git clone --recursive https://github.com/catsandsoup/2Xtreme-recomp.git
cd 2Xtreme-recomp
git -C psxrecomp apply "$PWD"/patches/psxrecomp/*.patch
ZIG_DIST=/path/to/zig-aarch64-macos-0.16.0 tools/macos/make_app.sh
```

The result is `dist/2Xtreme.app` (about 250 MB, a few minutes the first
time). The script builds the runtime against a pinned SDL3 release, packs the
SDK, recompiler and zig, signs ad hoc, and runs a release guard (no
disc-derived data, no local paths, nothing that needs a newer macOS). Test
hooks (fresh data folder, automatic disc pick, scripted menu input) are
listed in the handoff.

### Dev build with debug tools, from your own disc

The generated C stays local:

```bash
./psxrecomp/tools/ci/build_emitters.sh
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
