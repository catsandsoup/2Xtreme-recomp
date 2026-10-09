#ifndef MAC_MENU_H
#define MAC_MENU_H

#ifdef __cplusplus
extern "C" {
#endif

/* Install the macOS menu bar (a thin front for the in-game menu). */
void psx_macos_menu_install(void);

/* Kept for callers; the menu holds no state to sync. */
void psx_macos_menu_sync_state(void);

/* Test hook (--verify-menu): 1 if the menu bar is installed correctly. */
int  psx_macos_menu_verify_instantiation(void);

#ifdef __cplusplus
}
#endif

#endif /* MAC_MENU_H */
