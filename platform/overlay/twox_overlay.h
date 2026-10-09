/* 2Xtreme in-game menu: the one settings interface every door opens. */
#ifndef TWOX_OVERLAY_H
#define TWOX_OVERLAY_H

#ifdef __cplusplus
extern "C" {
#endif

/* Open the menu at the next frame (Esc, controller, ⌘, and the game's own
 * Options item all end up here). Safe to call from any thread. */
void twox_overlay_request_open(void);

/* Non-zero while the menu is showing (the game is paused). */
int twox_overlay_is_open(void);

#ifdef __cplusplus
}
#endif

#endif
