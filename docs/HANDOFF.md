# Handoff (2026-10-09)

For the next session (Claude, Antigravity or a person). Read first:
[PRODUCT_RULES.md](PRODUCT_RULES.md), [DESIGN_PRINCIPLES.md](DESIGN_PRINCIPLES.md),
[PLAYER_JOURNEY.md](PLAYER_JOURNEY.md), [ROADMAP.md](ROADMAP.md).
Standing owner requests: commit and push every change to `origin main`
(github.com/catsandsoup/2Xtreme-recomp); judge everything by what the player
sees, with fresh screenshots.

## Where things stand

| Milestone | State | Evidence |
|---|---|---|
| M1 audit | Done | [M1_AUDIT.md](M1_AUDIT.md) |
| Boot fix | Done: 16-racer thread was blocking boot, now opt-in (`2XTREME_DEV_RACERS=1`) | `ff922c6` |
| M2 first launch | **Done and verified**: launcher app, disc pick/drop/verify, copy into `~/Library/Application Support/2Xtreme`, on-device recompile + build with bundled zig (no Apple tools, no Python, ~13 s), relaunch goes straight in, nothing written in the app | `d334e02`, `a63d6e1` |
| M3 pause menu | **Mostly working, not finished** | `59e24b5` |
| M4 game's own Options | Not started | |
| M5 picture/performance | Not started. Owner saw **52 fps / 0.86×** | |
| M6 controls/saves | Not started | |
| M7 release | Not started | |

### M3 details
- Code: `platform/overlay/twox_overlay.cpp` (model = recomp-ui runtime UI,
  presentation = ours), `platform/macos/mac_menu.mm` (thin menu bar: Settings…
  ⌘, / Window / developer-only menu with `TWOXTREME_DEVELOPER=1`).
- psxrecomp change: one weak hook `psx_host_overlay_present()` before the
  swap in `gpu_gl_renderer.c`, carried in `patches/psxrecomp/*.patch`.
- Verified by scripted test: open, navigate, Sharpness change saved to
  `settings.toml`, Back, Resume closes. Owner also used it by keyboard.
- To do:
  1. Check the 105-alpha dim on a bright scene (it was 150 and dark scenes
     went black).
  2. Remove or keep the `TWOXTREME_TEST_SCRIPT` diagnostic `fprintf`s (they
     only print when that env var is set).
  3. Verify on screen that Sharpness and Textures visibly change the picture
     (before/after screenshots).
  4. Real controller test (owner): Guide, Select+Start, D-pad, A/✕, B/○.
  5. Known gap: Full screen set from the menu bypasses psxrecomp's own
     ⌘F/Alt+Enter state, so the first ⌘F afterwards can be a no-op.
  6. Run both critics (`.claude/agents/`) on fresh screenshots.
  7. No Controls or Save-state pages yet (M6). Don't add placeholders.

## How to build and test

```bash
# zig 0.16.0 aarch64-macos (sha256 b23d70deaa879b5c2d486ed3316f7eaa53e84acf6fc9cc747de152450d401489)
# from https://ziglang.org/download/0.16.0/zig-aarch64-macos-0.16.0.tar.xz, unpacked anywhere
ZIG_DIST=/path/to/zig-aarch64-macos-0.16.0 tools/macos/make_app.sh dist
```

`make_app.sh` configures `build-shipping` (OpenBIOS only), builds the runtime
without game code, bundles libraries, packs SDK headers, the recompiler,
pruned zig and licences, builds the launcher, signs ad hoc, and runs a
release guard. Output: `dist/2Xtreme.app` (~245 MB, gitignored).

Developer/test environment variables:

| Variable | Effect |
|---|---|
| `TWOXTREME_DATA_DIR=<dir>` | Use this instead of `~/Library/Application Support/2Xtreme` (fresh-user tests) |
| `TWOXTREME_TEST_DISC=<cue>` | Setup picks this disc 3 s after the welcome screen |
| `TWOXTREME_FORCE_SETUP=1` | Show setup even if prepared |
| `TWOXTREME_TEST_OPEN_AFTER_S=<s>` | Open the pause menu s seconds after the first frame |
| `TWOXTREME_TEST_SCRIPT=down,accept,...` | Feed menu inputs every 1.5 s (up/down/left/right/accept/back/xbox/ps) |
| `TWOXTREME_DEVELOPER=1` | Show the Developer menu (direct-track boot) |
| `2XTREME_DEV_RACERS=1` | 16-racer experiment (memory thread, unsafe; rebuild as a hook) |

Deleting `<data>/game/.prepared` exercises the "app updated" path.

Screenshots of one window (no desktop): get the window id for a pid with a
tiny CoreGraphics swift script (`CGWindowListCopyWindowInfo`, owner pid,
layer 0), then `screencapture -x -o -l<id> out.png`. Test windows take
keyboard focus, so warn the owner before a run; their typing lands in the game.

The shipping build has no TCP debug server (`PSX_NO_DEBUG_TOOLS`). The dev
build in `build-release` has it on port 4370 (`psxrecomp/tools/debug_client.py`).

## Local-only state (never push)
- Branch `legacy-with-generated`: old history with disc-derived game C and
  hand edits.
- `local/`: `generated-hand-edits.diff` (old LOD and direct-track edits) and
  `reference/` (original 2Xtreme screenshots for style work: main menu,
  title, intro, demo race, credits).
- `generated/` is the pristine output for the owner's disc (gitignored).
- `psxrecomp` submodule has local edits. Re-create them with
  `git -C psxrecomp apply ../patches/psxrecomp/*.patch`.

## Next, in order
1. Finish M3 (list above), commit, push.
2. M4: capture the original Options screen first (what it controls). Find the
   `FE.EXE` Options handler from the "OPTIONS" string. Hook it so choosing
   Options opens the overlay; Back returns to the main menu; keep the
   original options (write the game's own variables). FE.EXE runs through
   the overlay interpreter, so the hook must be overlay-aware.
3. M5: measure speed in the shipping build at default settings (owner's
   0.86× was probably the dev build: software renderer + 4× SSAA). Then
   sharpness/smoothing before/after screenshots, a 1-day MoltenVK spike,
   and widescreen research (ship only if HUD-correct).
4. M6, M7 per ROADMAP.md.

## Things that bit us
- Without Apple's tools, `/usr/bin/python3` is a stub that triggers their
  install. The setup path must not call Python (it doesn't).
- `psxrecomp-game` needs `bios/*.toml` profiles beside `game.toml`.
- zig wants `-target aarch64-macos.13.0` (not `.13`).
- The runtime ships SCPH1001 (Sony BIOS) C upstream; our builds use
  `-DPSXRECOMP_BIOS_STEMS=OpenBIOS` so it never ships.
- Never write into the app bundle; the product lives in the user data dir.
