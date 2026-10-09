# Milestone 1: architecture audit and plan

Date: 2026-10-09. Rules: [PRODUCT_RULES.md](PRODUCT_RULES.md).
Everything below was checked against the real build in `build-release/`,
copied outside the repo and launched. "Verified" means I saw it work.
"Implemented" means code exists but nobody has seen it work.

## 1. The focused goal and lessons

**Goal:** a player double-clicks a Mac app, picks their own 2Xtreme disc
once, and is skating within a minute with a controller. Later launches go
straight to the game. Menus look like 2Xtreme, every setting works and is
remembered, and gameplay is the original unless the player turns something on.

The five lessons that matter most for this project right now:

1. **Judge by what a player sees.** The earlier "VICTORY CONFIRMED" work
   passed 18 tests, but none of them is a player journey, and the build
   cannot reach the title screen (section 2).
2. **Distribution decides architecture.** The recompiled game C is
   disc-derived, so it is no longer in the public repo. The app must
   generate it from the player's disc on their Mac, with a progress screen.
3. **One interface, many doors.** Esc, a controller button, the game's own
   Options item and the macOS menu bar all open the same overlay, built on
   recomp-ui's existing runtime model, not a new UI.
4. **Gameplay stays original by default.** 16 racers, forced high-poly
   models and direct-track boot become opt-in developer features, built as
   controlled hooks, not hand edits or background memory writers.
5. **Nothing reaches the menu until it works.** Remove settings that do
   nothing (Fast Boot, 16:9, HD textures) until they are proven.

## 2. What works, what is scaffolding, what is missing

| Area | State | Evidence |
|---|---|---|
| Build produces `2Xtreme.app` | **Implemented, partly verified** | Bundle exists and runs on this Mac. |
| Runs on a clean Mac | **Missing** | Links `/opt/homebrew` SDL3, FreeType and HarfBuzz. None are bundled (`otool -L`). |
| Runs outside the repo | **Verified only because of local paths** | Copied bundle booted, but found the disc through a hardcoded `/Users/monty/Downloads/...` path in the bundled `game.toml` and `settings.toml`. |
| Fresh user picks a disc | **Missing (verified broken)** | With no disc path the app prints "no graphical file picker on this platform", tells the user to use `--disc`, and exits. No window appears. |
| On-device game generation | **Scaffolding** | `codegen_setup.c` setup host exists, but needs the repo, Python, cmake and `build-release/` at runtime. Not usable by a stranger. |
| Boots to title screen | **Not verified, likely broken** | In 3 runs (headless 45 s, windowed 60 s, Start pressed) the picture stays on "Developed By / Sony Interactive Studios America". Cause unknown. Prime suspect: the always-on racer thread (below). |
| Writable data location | **Wrong** | Settings, mod state and overlay captures write into `2Xtreme.app/Contents/MacOS` (`exe_dir_from_argv` anchors everything there). Saves point into the repo. |
| Pre-boot launcher (recomp-ui) | **Implemented, not verified** | `skip_launcher = false`, but it never appeared in the fresh-user run. |
| In-game pause/settings overlay | **Missing** | psxrecomp never calls `recomp_runtime_ui_*`. Only a save-state slot picker and OSD toasts exist. recomp-ui's runtime model (`recomp-ui/docs/RUNTIME_UI.md`, MIT) is ready to reuse. |
| Game's own Options hook | **Missing** | The strings "OPTIONS" and "Pause Game" exist on the disc. The menu lives in the `FE.EXE` overlay. No address mapped. |
| macOS menu bar | **Implemented, never seen** | Only checked by `--verify-menu`, which exits before the game runs. |
| Menu: Fast Boot | **Nonfunctional** | Sets `g_mac_fast_boot`, which nothing reads. |
| Menu: 16:9 / 21:9 | **Nonfunctional or stretch** | The runtime logs "widescreen is mod-owned; clamping 16:9 -> 4:3". The menu setter bypasses the clamp, so at best it stretches. True expanded view is not verified. |
| Menu: internal resolution | **Implemented, not verified** | Calls `gr_set_scale`. Shipped settings use the **software** renderer. |
| Renderers | **OpenGL and software present; Vulkan unavailable** | Vulkan code compiled as stubs, no loader or MoltenVK linked; runtime says "Vulkan renderer is not available in this build". |
| Controller | **Implemented, not verified** | SDL gamepad, `keybinds.ini`, dead zones. Saved P1 device is keyboard. |
| HD textures | **Placeholder** | Pack files use fake hashes (`0123456789ABCDEF`) and contain no artwork, yet the feature is enabled by default. |
| CD-DA soundtrack mod | **Manifest only, not verified** | Enabled by default. |
| R1 forced high-poly | **Always on, hand-edited into `generated/`** | Lost on regeneration (kept as `local/generated-hand-edits.diff`). Its test reads a static JSON file and credits a BIOS ROM address (`0x1FC085D8`) as the skater draw function, so the evidence is invalid. |
| R2 16 racers | **Always on, unsafe** | A thread started by a C constructor writes guest RAM every 0.5 ms in every run, including menus, and overwrites the game's racer table at `0x8007D134` before any race. |
| Direct-track boot | **Developer feature, hand edits** | `--direct-track` plus `generated/` edits and the same thread. |
| psxrecomp changes | **Layering problem** | Runtime `main.cpp` includes the game's `codegen_setup.h`. Kept as `patches/psxrecomp/*.patch`. |
| Tests | **Not player-facing** | Existence, catalog and frame-count checks; tier 4 counts come from a saved JSON file, not a live run. |

Licences: psxrecomp is **PolyForm Noncommercial** (no commercial release),
recomp-ui and OpenBIOS are MIT, SDL is zlib, MoltenVK is Apache-2.0.

Prior art (post-mortem §2): no existing 2Xtreme port or decomp found.
DuckStation's cheat database lists RAM addresses for this disc
(P1 speed `0x8007D490`, P1 placement `0x8007D4CC`), and public DuckStation
savestates for SCUS-94508 exist, which gives an external reference that boots.

## 3. What has to be replaced or removed

1. **R2 racer thread** (`codegen_setup.c`): delete the constructor thread.
   Re-add 16 racers as an overlay-load hook that runs once, off by default,
   in a Developer page.
2. **Hand edits in `generated/`** (LOD, direct track): re-implement as
   recompiler config or runtime hooks so regeneration reproduces them. Off by
   default.
3. **macOS menu** (`platform/macos/mac_menu.mm`): replace with a thin menu
   (Settings… ⌘, / Full Screen / Window). Remove Fast Boot, Mods, Resolution
   and Aspect duplicates. Direct Track moves to a hidden Developer menu.
4. **Bundle staging** (`CMakeLists.txt` POST_BUILD): stop copying dev
   `settings.toml`, `disc.cfg`, `input.ini` and mod state into the app. Add
   dylib bundling and ad-hoc signing.
5. **Writable paths** (psxrecomp `exe_dir_from_argv`): writable files go to
   `~/Library/Application Support/2Xtreme`, read-only resources stay in the
   bundle.
6. **Defaults**: GPU renderer instead of software, 4:3 Original until
   widescreen is proven, HD textures and CD-DA off until verified, delete
   placeholder texture files.
7. **psxrecomp patch**: drop the game header include and game-specific CLI
   flags from the runtime. Keep only generic hooks.
8. **Tests**: replace static-JSON and existence tests with player-journey
   tests (below).
9. **Old agent reports** (`.agents/`): superseded by this audit. Kept local only.

## 4. Proposed player journeys

**First run**
1. Double-click 2Xtreme. A full-window welcome screen in 2Xtreme style:
   "Insert your disc. Choose your 2Xtreme (USA) disc image." [Choose Disc]
   (native macOS file panel; controller A works).
2. The disc is checked. Right disc: "2Xtreme (USA) recognised." Wrong disc:
   "This looks like <title>. 2Xtreme needs the USA disc (SCUS-94508)."
   [Choose Another].
3. If the game isn't prepared yet: "Preparing 2Xtreme for this Mac, about a
   minute", with a progress bar and the current step. If Apple's command line
   tools are missing, explain why they're needed and offer the system
   installer.
4. The game boots. Disc and prepared game are remembered.

**Returning:** double-click and the game boots straight away. No launcher.
"Change disc" lives in Settings.

**Pause:** Esc, the controller Guide button (or Select+Start), or ⌘, opens
the overlay and freezes the game. Back/Resume returns to the same frame. No
button press leaks into the game on open or close.

**Original Options:** choosing Options in 2Xtreme's main menu opens the same
overlay. Back returns to 2Xtreme's main menu, not gameplay.

## 5. Proposed overlay layout

```
2XTREME ─ PAUSED
  Resume
  Picture     Display: Original 4:3 · Sharpness: Original / 2× / 3× / 4× (recommended)
              Smoothing: Sharp / Smooth · Full screen
  Controls    Player 1 / Player 2: device, rebind, vibration, dead zone
  Sound       Volume
  Save states 4 slots with thumbnail and time
  Game        Change disc · Restart · Quit
                                       [A] Select   [B] Back
```

- Only settings that are proven to work appear. Widescreen appears only after
  true expanded view is verified. Settings that need a restart say so before
  you commit them.
- Prompts match the active device (keyboard, Xbox, PlayStation).
- Visual style is sampled from 2Xtreme's own title, Options and course
  screens, captured from the reference, as one token file shared by setup
  and overlay. No stock ImGui grey and no title bars.
- A Developer page (hidden unless launched with a developer flag) holds
  direct-track boot, 16 racers, forced high-poly and diagnostics.

## 6. Integration points

| Need | Where | Known? |
|---|---|---|
| Overlay input before game input | psxrecomp `main.cpp` SDL event loop. The save-state menu (around line 6903) is the pattern to follow. | Yes |
| Overlay drawing | `recomp_runtime_ui_render_imgui` on the OpenGL present path | Yes |
| Pause while open | Stop frame stepping in the main loop while the overlay is open | To design |
| Disc picker on macOS | `main.cpp` around line 2665 (non-Windows branch). Use SDL3's file dialog or `NSOpenPanel`. | Yes |
| User data dir | Replace `exe_dir_from_argv` for writable files with `SDL_GetPrefPath` | Yes |
| Options hook | `FE.EXE` menu handler, found from the "OPTIONS" string xref. Hook must be overlay-aware. | **Needs reverse engineering** |
| On-device generation | Bundle the recompiler and runtime sources, compile with the system clang, cache in user data dir | Needs a 1-day spike |

## 7. Acceptance tests (player journeys, with fresh screenshots)

1. Copy the app to `/Applications` on a Mac account with no repo, no
   Homebrew and no settings. It opens, asks for the disc, prepares, and
   reaches the title screen without a terminal.
2. Quit and relaunch. It goes straight to the title. Settings and disc are
   remembered, and nothing is written inside the app bundle.
3. Boot reaches title, main menu, course select and a race. Screenshots match
   the DuckStation reference.
4. Esc and controller each open the overlay mid-race. Every item works with
   controller only. Back resumes on the same frame with no input leaking.
5. The game's Options item opens the overlay, and Back returns to 2Xtreme's
   main menu.
6. Each Picture setting shows a before/after screenshot and a measured frame
   rate.
7. Saves made in-game survive a relaunch. Audio plays without dropouts.
8. With default settings, the game state matches the original (no 16 racers,
   no forced models).

## 8. Dev work left, in order

0. **Boot to the title screen** (blocker). Disable the racer thread, retest.
   If still stuck, compare against a pristine generation and the DuckStation
   reference. Capture original menu screenshots for the style tokens.
1. **Portable app and first run**: bundle dylibs, user data dir, macOS disc
   picker, first-run screen, on-device generation spike.
2. **Pause/settings overlay** on recomp-ui's runtime model, with the
   2Xtreme theme.
3. **Original Options hook** in `FE.EXE`.
4. **Verified graphics**: OpenGL default, resolution and smoothing, then a
   1-day MoltenVK spike to decide on Vulkan, then real widescreen if feasible.
5. **Experimental features** rebuilt as opt-in developer hooks.

## 9. Decisions needed from the owner

1. Approve on-device generation (bundle the recompiler, compile with Apple's
   free command line tools at first run).
2. Approve moving the racer, high-poly and direct-track features behind a
   hidden Developer page, off by default.
3. Approve writing all player data to `~/Library/Application Support/2Xtreme`
   (a psxrecomp runtime change, carried as a patch).
4. Approve OpenGL as the default renderer now, with Vulkan through MoltenVK
   decided after a 1-day spike.
5. Approve reducing the macOS menu bar to a thin front for the overlay.
