# Product rules for 2Xtreme (standing, non-negotiable)

These rules govern every change to this project, by any person or AI agent
(Claude Code, Antigravity/Gemini, or anyone else). Read them at the start of
every session, apply each section before writing code, and re-check them
before calling anything finished.

## The goal (a player outcome, not a technique)

> A player downloads a Mac app, picks their own 2Xtreme disc once, and is
> skating within a minute, with a controller. Later launches go straight to
> the game. The menus look like they belong to 2Xtreme, every setting works
> and is remembered, and the game plays exactly like the original unless the
> player turns something on.

Technique preferences (static recompilation, Vulkan/MoltenVK, recomp-ui) are
constraints that serve that sentence. They are never the goal.

## How the post-mortem applies here

| Post-mortem rule | What it means for 2Xtreme |
|---|---|
| §1 Player outcome first | Every milestone is judged by a player journey (first run, returning launch, pause, settings, resume), not by passing internals. |
| §2 Reuse before building | Reuse recomp-ui's runtime overlay model (`recomp-ui/docs/RUNTIME_UI.md`), psxrecomp's renderers, SDL, MoltenVK. Search for prior 2Xtreme work before reverse engineering anything. Run proposed spikes first. |
| §3 Distribution from day one | No disc contents and no disc-derived data in the download or the public repo. The player's own disc is the only input. First-run setup is a designed, cached experience with progress and friendly errors. |
| §4 Narrow scope | One configuration: NTSC-U SCUS-94508, macOS arm64. Finish each feature end to end before starting the next. |
| §5 Reachable from a real UI | No player feature lives only in an env var, CLI flag or unseen menu bar. Every setting has a UI entry point, persists, and has a README line. |
| §6 Borrow the art direction | Theme sampled from 2Xtreme's own menus into one token file. Hook the game's Options entry and pause action, draw our modern UI, write results back into the game's own state. |
| §7 Improve what players feel | Controls, picture, speed, saving and menus come before exotic content. |
| §8 Preserve gameplay | Racer expansion, forced high-poly models and direct-track boot are opt-in and off by default. No enhancement changes physics, timing, AI or progression unless the player turns it on. |
| §9 Test what the user sees | Tests target visible outcomes. Someone looks at the real build (screenshots) every milestone. Test the release build the way a stranger gets it. |
| §10 AI agents | Light coordination, hands-on work, reviewer passes (UX critic, style critic, release guard). Re-question inherited plans. |

## Done means

A feature is done only when a player can find it, use it with a controller,
keep the setting across relaunches, and a fresh screenshot shows it working.
A passing build, a surviving process, a symbol in a binary or a polygon count
is not proof.

---

# Source: Post-mortem: why one port shipped and another stalled

(Verbatim as supplied by the project owner, 2026-10-09.)

A reusable checklist for any software project, especially game ports, mods, remasters, or apps built with AI coding agents. It comes from two projects that ported the same PS2 game to the Mac with the same AI tools. One shipped a polished app on two platforms. The other produced rigorous but debug-looking internals and stalled. The difference was decisions, not talent or tools.

Give this file to a new project, or to an AI agent at the start of one, and ask it to apply each section before writing code.

---

## 1. Start from the player's outcome, not the technique

**What worked:** the goal was "a player downloads an app, picks their disc, and is driving within a minute, with a controller, on a Mac or a phone." Every technical choice served that sentence.

**What failed:** the goal was "a faithful, 1:1, no-emulation static recompilation." That is a technique, and it quietly ranked purity above usefulness.

Lessons:
- Write the goal as something a user does or feels. Put it at the top of the project's main document.
- Write technique preferences ("native", "no emulation", "byte-exact") as constraints under the goal, never as the goal.
- When a choice is close, ask: "which option gets a real person playing sooner?"
- Separate **what the user experiences** (gameplay must feel identical) from **how it is built inside** (internals can reuse anything). "1:1" should almost always mean the first.

## 2. Look for existing work before writing anything

**What worked:** the shipped project reused a mature, hardware-validated renderer (paraLLEl-GS), MoltenVK, Dear ImGui, SDL and community format docs, and spent its own time on what is unique to the game.

**What failed:** the other project studied the same renderer, listed it as an option, rejected it as "unknown risk", noted "run a 1-day spike if our own approach fails", and never ran the spike. It then spent weeks writing its own renderer. Nobody searched for an existing port of the same game until a finished one turned up.

Lessons:
- Day one: search for "<game or product> + port / recomp / remake / mod / app" and for every major component (renderer, audio, UI, input, packaging). Write down what exists.
- Default to reuse for anything that is not the project's core value. Build only what makes the project different.
- When a plan says "fallback: try X in a short spike", run the spike first. One day of testing an assumption is cheaper than weeks of avoiding it.
- Re-question early big decisions whenever progress slows. Plans inherited across sessions or agents tend to never get re-asked.

## 3. Design for distribution from day one

**What worked:** the app ships no copyrighted code or data. On first launch it reads the user's own disc, recompiles the game on the user's machine with the system compiler (offering to install Apple's free tools if missing), shows a progress bar (under a minute), and caches the result. So it could be shared publicly, released through CI, and get real users and feedback.

**What failed:** the other app baked the recompiled game into the binary. That made it legally unshareable ("personal use only"), so there was never a release, never outside users, and never the pressure that turns a prototype into a product.

Lessons:
- Ask on day one: "how will a stranger legally get and run this?" Shape the architecture around the answer.
- Ship early, even if small. A release loop (CI build, versioned downloads, an issue tracker) creates the feedback that drives polish.
- Make first-run setup a designed experience: clear prompts, validation with friendly errors, progress with time remaining, everything cached so later launches are instant.

## 4. Narrow the scope until it fits, then finish it

**What worked:** one game version (one disc region, one executable hash), checked against a known-good dump. Mac first, then Android. Each feature finished end to end before the next.

**What failed:** a long, parallel plan (renderer milestones, resolution scaling, high frame rate, widescreen, packaging, chooser screens, research tracks) with many items half done at once.

Lessons:
- Support one configuration perfectly before a second.
- Prefer few features finished and reachable from the UI over many features behind flags.
- A feature is done when a user can find it, use it and keep the setting, not when the internals pass a test.

## 5. Make every feature reachable from a real UI

**What worked:** every option (aspect ratio, HUD position, frame rate, resolution, upscaler, anti-aliasing, texture packs, controls, rumble, save states) lives in an in-game menu, persists between launches, and is described in the README.

**What failed:** most features were environment variables (`SOMETHING=4 ./run.sh`) or a macOS menu bar that was never seen on screen, so it felt like a debug build even when the engine worked.

Lessons:
- No feature without a UI entry point and saved settings. Environment variables are for developers and tests only.
- Defaults should be the best experience for most users (e.g. progressive picture on, sensible resolution), with "original" available as an option.
- Write the user-facing README section at the same time as the feature.

## 6. UI: borrow the original art direction, not its old code

**What worked:** the settings, save-state and setup screens are the app's own UI, drawn with a standard library (Dear ImGui, fully custom-drawn) in a style sampled from the game's own menus: exact colours, panel shapes, frame and name tab, selection bar, the game's own cursor motif, corner rivets, button-prompt boxes, and a rounded font that matches the game's lettering. It is sharp at any resolution, so it feels like part of the game, only modern.

**How it plugs in:** when the player picks the game's own "Options" item, a hook replaces the game's options routine and opens the app's menu instead. Pause > Settings is redirected the same way. The app's settings then write the game's own variables (vibration, radio station), so changes take effect in the game itself.

**What failed:** the alternative plan tried to add pages inside the game's menu code using its low-resolution text routine: harder to build, dated to look at, and fragile.

Lessons:
- Sample the original's palette, shapes, motifs and type into a small theme file. Use it everywhere.
- Hook the entry points (the menu item, the pause action), then draw your own modern UI. Write results back into the original's state so it behaves natively.
- Keep the original screens that still work well; replace only the ones you are improving.
- Use review passes with screenshots side by side against the original. A "style critic" (a person or an AI prompt) comparing them catches what code review cannot.
- Design for every input: controller first, keyboard, mouse, handheld. Show the right button glyphs for the device in use.

## 7. Functionality: improve what players feel

**What worked:**
- **Modern controls:** analogue gas and brake on the triggers, reverse by holding brake, the original layout as an option, full rebinding, dead zones, rumble tuned to road surface, engine and collisions.
- **Quality of life the original lacked:** saved settings, four save-state slots with thumbnails and timestamps, a performance overlay, a second-screen map on dual-screen devices, texture-pack dump and load.
- **Visual upgrades with taste:** widescreen with the HUD kept in shape and anchored, high resolution with modern upscalers and anti-aliasing, extra frames re-rendered from real geometry (no added latency), and a hook to remove a known artefact (interlace shift) by default.

Lessons:
- Prioritise what a player notices in the first five minutes: controls, picture, speed, saving, menus.
- Fix the original's annoyances (no saved options, awkward controls) before adding exotic content.
- When you change the original's behaviour, give an "original" setting, but default to the better experience.

## 8. Gameplay: preserve the feel, improve around it

**What worked:** game logic stays exactly as the original. Improvements sit around it: presentation, controls, saving, and options that write the game's own state. Gameplay-changing extras come later and are opt-in.

Lessons:
- Never let an enhancement change physics, timing, AI or progression unless the user explicitly turns it on.
- Prefer hooks that set the game's own variables over replacing its logic.
- Content additions (new cars, levels, texture packs) come after the core experience is excellent.

## 9. Testing: test what the user sees, and look at it yourself

**What worked:** a regression suite (about 110 tests) plus regular hands-on play on real devices, debugging against a trusted reference (an established emulator's debugger), and performance checks on fixed scenes.

**What failed:** very strong automated exactness gates (byte-identical frames, deterministic replays) that proved the new code matched the *old internal code*, not that it matched the real hardware or felt good. Agents ran headless, often with the display asleep, so nobody saw the app. A user found a missing menu within minutes of opening it.

Lessons:
- Keep automated tests, but aim them at user-visible outcomes: does it boot, can you reach every menu, do settings persist, is it at full speed.
- Validate against an external ground truth (real hardware, a mature reference), not only against your own earlier version.
- Look at the product at least every few days: launch it, play it, screenshot it. If an AI agent cannot see the screen, a human must.
- Test the release build the way a user gets it (download, Gatekeeper, first run), not just the developer build.

## 10. Working with AI agents

**What worked:** one focused human driving the work hands-on, with the AI doing the heavy lifting, plus specialist agent prompts for review (bug tester, performance profiler, release guard, reverse engineer, UI style critic, UX critic).

**What failed:** large orchestration overhead: many capped agents, briefs, hand-offs and reports, agents dying on usage limits, and an orchestrator that kept pushing an inherited plan instead of re-questioning it. Much effort went into coordination rather than product.

Lessons:
- Give the AI the user outcome (section 1) and ask it to propose the architecture **after** a prior-art search (section 2). Make it show the search.
- Ask the AI to argue against its own plan: "What existing project or library makes this unnecessary? What is the fastest way to a playable release? What would a user complain about first?"
- Use reviewer agents with clear roles (style critic against original screenshots, UX critic for the flow from launch to fun, release guard before every push).
- Keep coordination light: fewer, longer, hands-on sessions beat many tiny delegated tasks.
- Don't let early documents become unquestionable. Re-read the goal every session and ask whether the current work still serves it.

## 11. A one-page checklist

Before starting:
- [ ] Goal written as a user outcome, with technique preferences listed as constraints.
- [ ] Prior-art search done: same product, same components. Reuse decided per component.
- [ ] Distribution path decided: how a stranger legally gets and runs it.
- [ ] Scope narrowed to one configuration.

While building:
- [ ] Each feature has a UI entry point, saved settings and a README line.
- [ ] UI themed from the original's art direction; hooks at entry points; settings write the original's own state.
- [ ] Controls, picture, speed, saving and menus prioritised over content.
- [ ] Original behaviour preserved; changes opt-in or with an "original" setting.
- [ ] Someone plays the real build every few days and screenshots it.
- [ ] Risky assumptions tested with short spikes before long builds.

Before each release:
- [ ] Release build tested as a user gets it (first run, permissions, errors).
- [ ] Nothing copyrighted or derived from the user's files is in the download.
- [ ] Automated suite green; style and UX review on fresh screenshots.

---

*Written from a comparison of two ports of the same PS2 game built with the same AI tools in 2026. The successful one is open source: <https://github.com/silentsudin/RoadTripAdventure-recomp>.*
