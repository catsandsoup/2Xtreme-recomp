# Roadmap to a finished 2Xtreme

## What "finished" means (v1.0)

A stranger downloads a DMG, drags 2Xtreme to Applications, picks their own
disc, and is at the 2Xtreme main menu in about a minute (plus a one-time
Apple tools install if they don't have it). They play the whole game with a
controller, pause and change settings in a menu that looks like 2Xtreme,
reach the same settings from the game's own Options item, and everything
(settings, saves, disc) is remembered. Gameplay is the original.

Out of scope for v1.0: Windows/Linux, texture packs, 16 racers and other
Extras (v1.1+, opt-in), and anything not verified on screen.

## Done so far

| | |
|---|---|
| Rules, design principles, player journey, critics | `docs/`, `.claude/agents/` |
| Public repo with no disc-derived content | catsandsoup/2Xtreme-recomp |
| Boot fixed (racer thread off by default) | reaches main menu, demo, credits |
| On-device architecture proven | generate 13 s, compile+link ~2 s, no Homebrew, runs outside repo |

## Milestones left

Each one ends with fresh screenshots of the player journey, both critics'
reviews, and a commit. Nothing moves on until its acceptance passes.

### M2 First launch (in progress)
- App shell: a small launcher in `2Xtreme.app` that holds the prebuilt
  runtime SDK, the emitter and the CLI.
- Welcome screen in 2Xtreme style: choose or drag a disc; plain errors.
- Check for Apple's command line tools; explain, install, carry on.
- Prepare with real progress: copy disc, generate, compile, link, into
  `~/Library/Application Support/2Xtreme`.
- Later launches go straight to the game; app updates re-prepare (~15 s).
- Stop staging dev settings into the bundle; GPU renderer by default.
- Open item: confirm the CLI runs on Apple's `/usr/bin/python3`.
- **Accept:** a brand-new macOS user account reaches the main menu without
  a terminal; relaunch goes straight in; nothing is written inside the app.

### M3 Pause and settings overlay
- Adapter for recomp-ui's runtime model in the psxrecomp main loop: input
  routed to the menu first, game frozen while open, nothing leaks on close.
- Pages: Resume · Picture · Controls · Sound · Save states · Game.
- Theme tokens sampled from the original screens; one file for every screen.
- Esc, controller Guide (or Select+Start) and ⌘, all open it.
- **Accept:** controller-only use of every item; settings persist; both
  critics pass.

### M4 The game's own Options
- Capture the original Options screen and what it controls.
- Reverse-engineer the `FE.EXE` Options entry; overlay-aware hook.
- Keep the original choices (written to the game's variables) next to ours.
- **Accept:** Options opens the overlay; Back returns to the main menu, 10
  times in a row, with no corrupted state.

### M5 Picture and performance, verified
- OpenGL default; "Original / Sharp / Sharper" scale and "Sharp / Smooth"
  filtering, each with before/after screenshots and measured frame rate.
- 1-day MoltenVK/Vulkan spike; keep it only if it beats OpenGL.
- Widescreen research: true expanded view with the HUD kept in shape.
  Ship only if it passes; otherwise it stays out.
- **Accept:** steady full speed in a race at the default setting on an M1.

### M6 Controls, saves and the edge cases
- Controller auto-detect with the right prompts; rebinding; rumble;
  analogue steering only if it feels right (with "Original").
- Second controller joins as Player 2.
- Auto-pause on controller disconnect and on focus loss.
- Memory cards invisible and permanent; save states with thumbnails.
- **Accept:** a full Veteran season saved, quit, relaunched and continued.

### M7 Release
- DMG build script; licence notices (PolyForm NC, SDL, FreeType,
  HarfBuzz, OpenBIOS); release guard scans the DMG for disc-derived data.
- GitHub Actions builds the app (no game code) on every push.
- Player-first README with screenshots, the three steps and the Gatekeeper
  "Open Anyway" step.
- **Accept:** download the DMG on another Mac, follow the README, play.
  The owner plays it start to finish and signs off.
  Publishing a release needs the owner's approval.

### v1.1+ Extras (opt-in, off by default)
16 racers and forced high-poly as one-shot overlay hooks in an "Extras"
page; HD texture packs once real artwork exists.

## What only the owner can do
- Test with a real controller (Claude can only simulate inputs).
- Run the fresh-Mac or new-user-account test and the Gatekeeper step.
- Play through the whole game and sign off.
- Approve each public release.

## Biggest risks
- The Options hook needs real reverse engineering of `FE.EXE`.
- True widescreen may not be feasible without breaking the HUD; then v1.0
  ships 4:3, sharp and honest.
- Apple's tools install is a heavy first-run step; a bundled compiler may
  be needed to remove it.
- psxrecomp is PolyForm Noncommercial: free releases only.
