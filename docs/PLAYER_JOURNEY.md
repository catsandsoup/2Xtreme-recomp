# The player's journey

Written entirely from the player's side. Every screen, hook and setting must
earn its place on this map. Read with [DESIGN_PRINCIPLES.md](DESIGN_PRINCIPLES.md).

## Who the player is

Someone who skated, biked, bladed and snowboarded through 2Xtreme in 1996,
probably as a kid, usually with a friend on the second controller. Now an
adult on a Mac, nostalgic, owns the disc (or a rip of it), may have an Xbox
or PlayStation controller in a drawer. They don't know or care what
"recompilation", "OpenBIOS" or "PGXP" mean. They want **that** game, the
way they remember it, only better looking, without a weekend of setup.

What they're secretly afraid of: that it's another fiddly emulator setup,
that it won't work on their Mac, that it'll look blurry and stretched, and
that the soundtrack won't be there.

## The journey, stage by stage

### 0. Hearing about it
- **Wants:** to know if they can play 2Xtreme on their Mac, properly.
- **Sees:** a post or the GitHub page.
- **Expects:** a screenshot or clip, a Download button, one honest line:
  "Bring your own 2Xtreme disc."
- **Delighted by:** a crisp gameplay clip; "No emulator, no BIOS, no setup."
- **Dislikes:** build instructions first, jargon, cmake, "personal use only".
- **We must:** lead the README with picture, download and three steps.
  Developer instructions go below the fold.

### 1. Download and install
- **Does:** downloads a DMG, drags 2Xtreme to Applications.
- **Expects:** a normal Mac app, a sensible size.
- **Dislikes:** the unsigned-app Gatekeeper warning. It feels like malware.
- **We must:** show the exact "Open Anyway" step with a screenshot on the
  download page, because the app isn't notarised.

### 2. First launch: "where's my game?"
- **Wants:** to be playing. Now.
- **Sees:** a full window in 2Xtreme's own style (brick wall, spotlight):
  "Choose your 2Xtreme disc."
- **Does:** picks a file, or drags it onto the window.
- **Expects:** it accepts what they actually have: a `.cue` with its
  `.bin` files, a single `.bin`, or a `.chd`.
- **Delighted by:** drag-and-drop working; no BIOS needed;
  "2Xtreme (USA) ✓" appearing instantly.
- **Dislikes:** errors like "track 2 missing" or "hash mismatch".
- **We must:** speak plainly. Wrong game: "This is <title>. 2Xtreme needs
  the USA disc." Music tracks missing: "This copy has no music tracks. The
  game will play, but silently. Use the .cue file if you have it."

### 3. Apple's tools (the riskiest moment)
- **Sees:** a macOS dialog asking to install "command line developer tools",
  which takes several minutes the first time.
- **Feels:** confused and suspicious. "Why does a game need developer tools?"
- **We must:**
  - say why in one line before the dialog appears: "2Xtreme builds itself
    for your Mac with Apple's free tools. One time only, a few minutes.";
  - then carry on automatically when the install finishes;
  - skip this screen entirely when the tools are already installed.
- **Later:** consider bundling a compiler so this step disappears.

### 4. Preparing (under a minute)
- **Sees:** a progress bar with real steps ("Reading your disc…",
  "Building 2Xtreme for this Mac…") and time remaining.
- **Delighted by:** something alive on screen. The brick wall, the 2X logo.
  Possibly the game's own music, played from their own disc.
- **Dislikes:** a frozen bar, fans spinning with no explanation, losing
  everything if they quit halfway.
- **We must:** resume cleanly after a quit, and never repeat this step.

### 5. First boot
- **Expects:** the 2Xtreme intro, then the main menu they remember.
- **Delighted by:**
  - a sharp picture at a sensible window size, never stretched;
  - a controller that just works, with the right button prompts;
  - the soundtrack playing;
  - Start skipping the intro.
- **Dislikes:** a tiny window, blur, keyboard only, a controller that isn't
  detected, crackly or missing music.
- **We must:** default to a GPU renderer at a sharp scale, auto-detect
  controllers, mount the music tracks, and test exactly this moment with
  screenshots.

### 6. Playing
- **Wants:** it to feel exactly as they remember. The same physics, the same
  racers, kicking and punching rivals off their boards.
- **Delighted by:** smooth frame pacing, responsive controls, analogue
  steering if it feels right, rumble, shorter loads.
- **Dislikes:** slowdown, input lag, crashes, anything that changes the
  game. Original behaviour is sacred by default.

### 7. Pausing and settings
- **Does:** presses Esc, or the controller's Guide button, mid-race.
- **Expects:** the game freezes, a few clear choices, Back resumes.
- **Delighted by:** the menu looks like 2Xtreme; a change to the picture
  shows live behind the menu; it remembers next time.
- **Dislikes:** a developer panel full of words like "supersampling";
  restarts; a button press leaking into the race on close.

### 8. Choosing "Options" in 2Xtreme's own menu
- **Expects:** the options they remember from 1996 (to be checked on the
  original: likely sound, music and controller settings).
- **Delighted by:** those options plus the modern ones (picture, controls),
  in one place, in the game's style, remembered across launches. The
  original only kept them on a memory card.
- **Dislikes:** losing the game's own options, or landing somewhere that
  doesn't feel like 2Xtreme.
- **We must:** capture what the original Options screen holds before
  designing the hook, keep those choices (written to the game's own
  variables), and return to the main menu on Back.

### 9. Saving progress
- **Expects:** Veteran seasons and records save and load like on the
  PlayStation, with no memory card fuss.
- **Delighted by:** it just works; quick save mid-race as an extra.
- **Dislikes:** lost progress, "memory card not present", file management.
- **We must:** keep the memory cards permanent and invisible in their
  user folder.

### 10. Two players
- **Does:** a friend plugs in a second controller.
- **Delighted by:** "Player 2 joined" and straight into split-screen.
- **Dislikes:** digging through settings to assign controllers.

### 11. Coming back tomorrow
- **Does:** double-clicks 2Xtreme.
- **Expects:** the game. No launcher, no setup, no questions.
- **Delighted by:** it's instant; Start skips the intro.
- **Dislikes:** a permission prompt about the Downloads folder (macOS asks
  when an app re-reads files there); "Can't find your disc" because they
  tidied their Downloads.
- **We must:** keep the player's own disc copy in 2Xtreme's user folder at
  setup, so it never goes missing and macOS never asks again.

### 12. When things go wrong
| Situation | What the player should see |
|---|---|
| Controller unplugged mid-race | Game pauses: "Controller disconnected. Reconnect, or press Esc to use the keyboard." |
| Window loses focus | Game pauses, music fades. Resumes where they left it. |
| App updated | One short "Updating 2Xtreme… (15 s)" screen. Never the full setup again. |
| Quit during preparation | Next launch picks up where it stopped. |
| Disc copy deleted | "2Xtreme needs your disc again." [Choose Disc] |

## What they don't care about

Recompilation, BIOS types, renderers by name, PGXP, overlay caches, debug
ports, internal resolution numbers. These stay invisible or behind plain
words ("Sharp", "Smooth", "Original").

Experiments like 16 racers may delight some players later as clearly
labelled "Extras", off by default. They never belong in the core journey.

## Changes this makes to the plan

1. Keep a copy of the player's disc in the user folder during setup
   (avoids macOS folder prompts and missing-disc failures).
2. Design the "Apple's tools" screen explicitly. Investigate removing it
   with a bundled compiler.
3. Accept `.cue`, single `.bin` and `.chd`, with drag-and-drop and plain errors.
4. First boot defaults: GPU renderer, sharp scaling, larger window, music
   mounted, controller auto-detected with matching prompts.
5. Start skips intro FMVs (check the original allows it).
6. Before designing the Options hook, record what the original Options
   screen contains, and keep those choices.
7. Auto-pause on controller disconnect and on focus loss.
8. App updates re-prepare silently in about 15 seconds.
9. README and download page lead with the player, not the build.

## Journey acceptance (what we screenshot every milestone)

First launch → disc → preparing → intro → main menu → race → pause → change
a setting → resume → Options from the game's menu → Back → quit → relaunch
straight into the game.
