# Design principles: 2Xtreme

How design thinking is built into every screen, hook and setting. Read with
[PRODUCT_RULES.md](PRODUCT_RULES.md). Reviews use the two critics in
`.claude/agents/` (ux-critic, style-critic) on fresh screenshots.

## 1. Start with the experience, work back to the technology

Every screen begins as one sentence about what the player is doing and
feeling, written before any code:

| Moment | The sentence |
|---|---|
| First launch | "I picked my disc and I'm at the 2Xtreme title in under a minute." |
| Returning | "I double-clicked and I'm in the game." |
| Pause | "I hit Esc or Guide, the game froze, I changed one thing and I'm back skating." |
| Options | "I chose Options in 2Xtreme's own menu and got settings that look like they belong." |
| Error | "It told me exactly what was wrong and what to press next." |

If a design doesn't serve its sentence, it's wrong, however clever it is.

## 2. Focus means saying no

- Fewer options, each obviously worth having. A setting exists for the
  player, not because the engine exposes it.
- Defaults must be right, so most players never open Options.
- Nothing appears until it works. No placeholder buttons, no "coming soon".
- Developer diagnostics and experiments (16 racers, forced high-poly,
  direct-track boot) live behind a hidden Developer page, never in player
  menus.

## 3. The game is the hero

- The fewest possible steps between double-click and skating.
- The setup screen appears once, then never again.
- The overlay covers as little as it can. The game stays visible and frozen
  behind it, so picture changes are seen live.
- Keep the original screens that still work well. Replace only the ones
  being improved (Options, pause).

## 4. It must look like 2Xtreme

From the original's own screens (references in `local/reference/`, never
published):

- **Backdrop:** dark brick wall under a single spotlight, heavy vignette.
- **Type:** chunky, outlined block capitals; graffiti for headings
  ("MAIN MENU").
- **Colour:** graffiti green and yellow on near-black. The red "2X" mark is
  the accent. The selected item is yellow and larger.
- **Prompts:** bottom-left strip with the D-pad and ✕ "Select".
- **Not:** Road Trip's rounded cheerful panels, stock ImGui grey, title
  bars, dense tables, tiny controls.

One token file (colours, type sizes, spacing, panel shapes, focus
treatment, prompt strip) drives the setup screen and the in-game overlay.
Exact colours are sampled from the reference screenshots, not guessed.

## 5. One interface, many doors

- Esc, the controller Guide button (or Select+Start), ⌘, and 2Xtreme's own
  Options item all open the **same** overlay, with the same state,
  persistence and validation.
- Entry context is kept. Back from Options returns to 2Xtreme's main menu.
  Back from pause resumes the same frame.
- The macOS menu bar only calls the overlay's actions. It never holds its
  own copy of settings.
- Hooks write the game's own variables where the game has them, so changes
  take effect natively.

## 6. Controller first, every time

- Every screen fully usable with a controller alone, then keyboard, then
  mouse.
- Focus is unmistakable: yellow, larger, never just a thin outline.
- Confirm/Back prompts match the device in use (keyboard keys, Xbox,
  PlayStation glyphs).
- No hover-only information. Plain-language labels first, technical detail
  second.
- Opening or closing a menu never leaks a press into the game.
- Panels stay still as focus moves. No resizing, no jumping.

## 7. Feedback is live and honest

- Changes apply immediately and visibly where possible.
- A setting that needs a restart says so before you commit it.
- Errors say what happened and what to do, in the game's voice, with one
  obvious next action.
- Hard cases are designed, not discovered: controller unplugged mid-race,
  window loses focus, disc missing on relaunch, quitting during first-run
  preparation.

## 8. Judge the real thing

A UI milestone is finished only after both critics review fresh screenshots
of the complete flow (first run, returning, pause, change a setting, back
out, resume, Options entry) with:

- **UX critic:** VERDICT, STEPS TO PLAY (first-time / returning), REMOVE,
  MUST FIX (at most five, ranked, exact changes).
- **Style critic:** VERDICT, FIT WITH 2XTREME, MUST FIX (at most five:
  screen, problem, exact visual change), compared side by side with the
  original's screens.

Widgets rendering or callbacks firing is not proof. Anything not tested is
marked as not tested.
