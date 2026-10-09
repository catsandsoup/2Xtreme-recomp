#ifndef MAC_MENU_H
#define MAC_MENU_H

#ifdef __cplusplus
extern "C" {
#endif

/* Initialize native macOS NSMenu bar and attach to NSApp */
void psx_macos_menu_install(void);

/* Synchronize menu checkmarks with active engine / persisted settings */
void psx_macos_menu_sync_state(void);

/* Headless / test verification hook: returns 1 if NSMenu is instantiated correctly */
int  psx_macos_menu_verify_instantiation(void);

/* Aspect ratio (Widescreen): 0=4:3, 1=16:9, 2=21:9 */
void psx_macos_set_widescreen(int aspect_mode);
int  psx_macos_get_widescreen(void);

/* Internal resolution: 1=native (240p), 720, 1080, 1440, 2160, -1=match display */
void psx_macos_set_resolution(int ir_preset);
int  psx_macos_get_resolution(void);

/* Fast boot (skip BIOS intro) */
void psx_macos_set_fast_boot(int enabled);
int  psx_macos_get_fast_boot(void);

/* Mod package / feature toggles (HD Textures, CD-DA Soundtrack) */
void psx_macos_set_mod_enabled(const char* package_id, const char* feature_id, int enabled);
int  psx_macos_get_mod_enabled(const char* package_id, const char* feature_id);

/* Direct Track Launch hook (R2/R3 State Machine integration)
 * Course IDs: 0=LA, 1=Vegas, 2=Africa, 3=Japan */
void psx_macos_launch_direct_track(int course_id, int track_num, int skater_id);

#ifdef __cplusplus
}
#endif

#endif /* MAC_MENU_H */
