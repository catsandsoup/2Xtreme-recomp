#import <Cocoa/Cocoa.h>
#include "mac_menu.h"
#include "config_loader.h"
#include "mod_packages.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <functional>
#include <iostream>

namespace fs = std::filesystem;
using PSXRecompV4::ModPackageManager;

/* --- External Weak Engine Hooks --- */
extern "C" {
__attribute__((weak)) void psx_engine_set_widescreen(int mode);
__attribute__((weak)) int  psx_engine_get_widescreen(void);
__attribute__((weak)) void psx_engine_set_resolution(int ir_preset);
__attribute__((weak)) int  psx_engine_get_resolution(void);
__attribute__((weak)) void psx_engine_set_fast_boot(int enabled);
__attribute__((weak)) int  psx_engine_get_fast_boot(void);
__attribute__((weak)) void psx_direct_boot_race_track(int course_id, int track_num, int skater_id);
}

/* Weak default implementation for psx_direct_boot_race_track if M2 is not yet linked */
__attribute__((weak)) void psx_direct_boot_race_track(int course_id, int track_num, int skater_id) {
    std::fprintf(stdout,
        "[psx_macos] Default weak psx_direct_boot_race_track called (course=%d, track=%d, skater=%d)\n",
        course_id, track_num, skater_id);
    std::fflush(stdout);
}

/* Track configuration table for Direct Track Launch */
struct TrackPreset {
    const char *name;
    int course_id;
    int track_num;
    int skater_id;
    const char *key;
};

static const TrackPreset kTracks[] = {
    {"Start Africa Track (Bypass All Menus)", 2, 0, 0, "1"},
    {"Start Los Angeles Track", 0, 0, 0, "2"},
    {"Start Las Vegas Track", 1, 0, 0, "3"},
    {"Start Japan Track", 3, 0, 0, "4"},
};

static fs::path get_active_config_dir() {
    @autoreleasepool {
        NSString *execPath = [[NSBundle mainBundle] executablePath];
        if (execPath) {
            fs::path p([execPath UTF8String]);
            fs::path parent = p.parent_path();
            if (fs::exists(parent / "settings.toml") || fs::exists(parent / "game.toml")) {
                return parent;
            }
            // If running inside 2Xtreme.app/Contents/MacOS, settings might also reside at repo/build root
            fs::path root = parent.parent_path().parent_path().parent_path();
            if (fs::exists(root / "settings.toml") || fs::exists(root / "game.toml")) {
                return root;
            }
            return parent;
        }
        return fs::current_path();
    }
}

static void mutate_and_save_settings(const std::function<void(PSXRecompV4::UserSettings&)>& mutate) {
    fs::path dir = get_active_config_dir();
    fs::path p = dir / "settings.toml";
    PSXRecompV4::UserSettings s = PSXRecompV4::load_user_settings(p);
    mutate(s);
    PSXRecompV4::save_user_settings(p, s);
}

/* --- Objective-C Menu Controller --- */
@interface PSXMacMenuController : NSObject <NSMenuItemValidation>
+ (instancetype)sharedController;
- (void)populateMainMenu;
- (void)refreshCheckmarks;
- (void)onToggleFastBoot:(id)sender;
- (void)onDirectTrackSelected:(id)sender;
- (void)onAspectSelected:(id)sender;
- (void)onResolutionSelected:(id)sender;
- (void)onToggleModHDTextures:(id)sender;
- (void)onToggleModCDDA:(id)sender;
@end

@implementation PSXMacMenuController

+ (instancetype)sharedController {
    static PSXMacMenuController *s_instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s_instance = [[PSXMacMenuController alloc] init];
    });
    return s_instance;
}

- (void)populateMainMenu {
    NSApplication *app = [NSApplication sharedApplication];
    NSMenu *mainMenuBar = [[NSMenu alloc] initWithTitle:@"MainMenu"];

    // -------------------------------------------------------------
    // 1. Application Menu ("2Xtreme")
    // -------------------------------------------------------------
    NSMenuItem *appItem = [[NSMenuItem alloc] initWithTitle:@"2Xtreme" action:nil keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"2Xtreme"];
    [appMenu addItemWithTitle:@"About 2Xtreme" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Hide 2Xtreme" action:@selector(hide:) keyEquivalent:@"h"];
    NSMenuItem *hideOthers = [appMenu addItemWithTitle:@"Hide Others" action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
    [hideOthers setKeyEquivalentModifierMask:(NSEventModifierFlagOption | NSEventModifierFlagCommand)];
    [appMenu addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit 2Xtreme" action:@selector(terminate:) keyEquivalent:@"q"];
    [appItem setSubmenu:appMenu];
    [mainMenuBar addItem:appItem];

    // -------------------------------------------------------------
    // 2. Game Menu
    // -------------------------------------------------------------
    NSMenuItem *gameItem = [[NSMenuItem alloc] initWithTitle:@"Game" action:nil keyEquivalent:@""];
    NSMenu *gameMenu = [[NSMenu alloc] initWithTitle:@"Game"];

    NSMenuItem *fastBoot = [[NSMenuItem alloc] initWithTitle:@"Fast Boot (Bypass BIOS)"
                                                      action:@selector(onToggleFastBoot:)
                                               keyEquivalent:@"b"];
    [fastBoot setTarget:self];
    [fastBoot setTag:101];
    [gameMenu addItem:fastBoot];

    [gameMenu addItem:[NSMenuItem separatorItem]];

    // Direct Track Launch submenu (R2/R3 State Machine Integration)
    NSMenuItem *raceSubmenuItem = [[NSMenuItem alloc] initWithTitle:@"Direct Track Launch" action:nil keyEquivalent:@""];
    NSMenu *raceSubmenu = [[NSMenu alloc] initWithTitle:@"Direct Track Launch"];

    for (size_t i = 0; i < sizeof(kTracks) / sizeof(kTracks[0]); i++) {
        const TrackPreset &t = kTracks[i];
        NSMenuItem *tItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithUTF8String:t.name]
                                                       action:@selector(onDirectTrackSelected:)
                                                keyEquivalent:[NSString stringWithUTF8String:t.key]];
        [tItem setTarget:self];
        [tItem setTag:(NSInteger)i];
        [raceSubmenu addItem:tItem];
    }
    [raceSubmenuItem setSubmenu:raceSubmenu];
    [gameMenu addItem:raceSubmenuItem];

    [gameItem setSubmenu:gameMenu];
    [mainMenuBar addItem:gameItem];

    // -------------------------------------------------------------
    // 3. Video Menu (Widescreen & Resolution Dropdowns)
    // -------------------------------------------------------------
    NSMenuItem *videoItem = [[NSMenuItem alloc] initWithTitle:@"Video" action:nil keyEquivalent:@""];
    NSMenu *videoMenu = [[NSMenu alloc] initWithTitle:@"Video"];

    // Aspect Ratio / Widescreen Submenu
    NSMenuItem *aspectItem = [[NSMenuItem alloc] initWithTitle:@"Widescreen / Aspect Ratio" action:nil keyEquivalent:@""];
    NSMenu *aspectMenu = [[NSMenu alloc] initWithTitle:@"Widescreen / Aspect Ratio"];

    NSMenuItem *aspect43 = [[NSMenuItem alloc] initWithTitle:@"4:3 (Native PS1)" action:@selector(onAspectSelected:) keyEquivalent:@""];
    [aspect43 setTarget:self]; [aspect43 setTag:0]; [aspectMenu addItem:aspect43];

    NSMenuItem *aspect169 = [[NSMenuItem alloc] initWithTitle:@"16:9 (Widescreen)" action:@selector(onAspectSelected:) keyEquivalent:@""];
    [aspect169 setTarget:self]; [aspect169 setTag:1]; [aspectMenu addItem:aspect169];

    NSMenuItem *aspect219 = [[NSMenuItem alloc] initWithTitle:@"21:9 (Ultrawide)" action:@selector(onAspectSelected:) keyEquivalent:@""];
    [aspect219 setTarget:self]; [aspect219 setTag:2]; [aspectMenu addItem:aspect219];

    [aspectItem setSubmenu:aspectMenu];
    [videoMenu addItem:aspectItem];

    // Internal Resolution Submenu
    NSMenuItem *resItem = [[NSMenuItem alloc] initWithTitle:@"Internal Resolution" action:nil keyEquivalent:@""];
    NSMenu *resMenu = [[NSMenu alloc] initWithTitle:@"Internal Resolution"];

    struct { const char *label; int tag; } resPresets[] = {
        {"Native (240p / 1x)", 1},
        {"720p (3x)", 720},
        {"1080p (4.5x)", 1080},
        {"1440p (6x)", 1440},
        {"4K (9x)", 2160},
        {"Match Display Resolution", -1}
    };
    for (const auto &r : resPresets) {
        NSMenuItem *ri = [[NSMenuItem alloc] initWithTitle:[NSString stringWithUTF8String:r.label]
                                                    action:@selector(onResolutionSelected:)
                                             keyEquivalent:@""];
        [ri setTarget:self];
        [ri setTag:r.tag];
        [resMenu addItem:ri];
    }
    [resItem setSubmenu:resMenu];
    [videoMenu addItem:resItem];

    [videoMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *fs = [videoMenu addItemWithTitle:@"Toggle Full Screen" action:@selector(toggleFullScreen:) keyEquivalent:@"f"];
    [fs setKeyEquivalentModifierMask:(NSEventModifierFlagControl | NSEventModifierFlagCommand)];

    [videoItem setSubmenu:videoMenu];
    [mainMenuBar addItem:videoItem];

    // -------------------------------------------------------------
    // 4. Mods Menu (HD Textures & CD-DA Toggles)
    // -------------------------------------------------------------
    NSMenuItem *modsItem = [[NSMenuItem alloc] initWithTitle:@"Mods" action:nil keyEquivalent:@""];
    NSMenu *modsMenu = [[NSMenu alloc] initWithTitle:@"Mods"];

    NSMenuItem *hdTextItem = [[NSMenuItem alloc] initWithTitle:@"HD Texture Pack"
                                                        action:@selector(onToggleModHDTextures:)
                                                 keyEquivalent:@""];
    [hdTextItem setTarget:self];
    [hdTextItem setTag:301];
    [modsMenu addItem:hdTextItem];

    NSMenuItem *cddaItem = [[NSMenuItem alloc] initWithTitle:@"CD-DA Audio Replacement"
                                                     action:@selector(onToggleModCDDA:)
                                              keyEquivalent:@""];
    [cddaItem setTarget:self];
    [cddaItem setTag:302];
    [modsMenu addItem:cddaItem];

    [modsItem setSubmenu:modsMenu];
    [mainMenuBar addItem:modsItem];

    // -------------------------------------------------------------
    // 5. Window Menu
    // -------------------------------------------------------------
    NSMenuItem *windowItem = [[NSMenuItem alloc] initWithTitle:@"Window" action:nil keyEquivalent:@""];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    [windowMenu addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    [windowMenu addItemWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""];
    [windowMenu addItem:[NSMenuItem separatorItem]];
    [windowMenu addItemWithTitle:@"Bring All to Front" action:@selector(arrangeInFront:) keyEquivalent:@""];
    [windowItem setSubmenu:windowMenu];
    [mainMenuBar addItem:windowItem];

    [app setMainMenu:mainMenuBar];
    [self refreshCheckmarks];
}

- (void)onToggleFastBoot:(id)sender {
    int cur = psx_macos_get_fast_boot();
    psx_macos_set_fast_boot(!cur);
    [self refreshCheckmarks];
}

- (void)onDirectTrackSelected:(id)sender {
    NSMenuItem *item = (NSMenuItem *)sender;
    NSInteger idx = item.tag;
    if (idx >= 0 && idx < (NSInteger)(sizeof(kTracks) / sizeof(kTracks[0]))) {
        const TrackPreset &t = kTracks[idx];
        psx_macos_launch_direct_track(t.course_id, t.track_num, t.skater_id);
    }
}

- (void)onAspectSelected:(id)sender {
    NSMenuItem *item = (NSMenuItem *)sender;
    psx_macos_set_widescreen((int)item.tag);
    [self refreshCheckmarks];
}

- (void)onResolutionSelected:(id)sender {
    NSMenuItem *item = (NSMenuItem *)sender;
    psx_macos_set_resolution((int)item.tag);
    [self refreshCheckmarks];
}

- (void)onToggleModHDTextures:(id)sender {
    int cur = psx_macos_get_mod_enabled("psx.enhancement.hd-textures", "hd-textures");
    psx_macos_set_mod_enabled("psx.enhancement.hd-textures", "hd-textures", !cur);
    [self refreshCheckmarks];
}

- (void)onToggleModCDDA:(id)sender {
    int cur = psx_macos_get_mod_enabled("2xtreme.soundtrack.cdda", "cdda-soundtrack");
    psx_macos_set_mod_enabled("2xtreme.soundtrack.cdda", "cdda-soundtrack", !cur);
    [self refreshCheckmarks];
}

- (void)refreshCheckmarks {
    NSMenu *mainMenu = [NSApp mainMenu];
    if (!mainMenu) return;

    // Fast Boot
    NSMenuItem *gameItem = [mainMenu itemWithTitle:@"Game"];
    if (gameItem && [gameItem submenu]) {
        NSMenuItem *fbItem = [[gameItem submenu] itemWithTag:101];
        if (fbItem) {
            [fbItem setState:(psx_macos_get_fast_boot() ? NSControlStateValueOn : NSControlStateValueOff)];
        }
    }

    // Aspect & Resolution
    NSMenuItem *videoItem = [mainMenu itemWithTitle:@"Video"];
    if (videoItem && [videoItem submenu]) {
        NSMenu *videoSub = [videoItem submenu];
        NSMenuItem *aspectItem = [videoSub itemWithTitle:@"Widescreen / Aspect Ratio"];
        if (aspectItem && [aspectItem submenu]) {
            int curAspect = psx_macos_get_widescreen();
            for (NSMenuItem *item in [[aspectItem submenu] itemArray]) {
                [item setState:(item.tag == curAspect ? NSControlStateValueOn : NSControlStateValueOff)];
            }
        }

        NSMenuItem *resItem = [videoSub itemWithTitle:@"Internal Resolution"];
        if (resItem && [resItem submenu]) {
            int curRes = psx_macos_get_resolution();
            for (NSMenuItem *item in [[resItem submenu] itemArray]) {
                [item setState:(item.tag == curRes ? NSControlStateValueOn : NSControlStateValueOff)];
            }
        }
    }

    // Mods
    NSMenuItem *modsItem = [mainMenu itemWithTitle:@"Mods"];
    if (modsItem && [modsItem submenu]) {
        NSMenu *modsSub = [modsItem submenu];
        NSMenuItem *hdItem = [modsSub itemWithTag:301];
        if (hdItem) {
            int curHD = psx_macos_get_mod_enabled("psx.enhancement.hd-textures", "hd-textures");
            [hdItem setState:(curHD ? NSControlStateValueOn : NSControlStateValueOff)];
        }
        NSMenuItem *cddaItem = [modsSub itemWithTag:302];
        if (cddaItem) {
            int curCDDA = psx_macos_get_mod_enabled("2xtreme.soundtrack.cdda", "cdda-soundtrack");
            [cddaItem setState:(curCDDA ? NSControlStateValueOn : NSControlStateValueOff)];
        }
    }
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    return YES;
}

@end

/* --- C Bridge Functions Implementation --- */

void psx_macos_menu_install(void) {
    @autoreleasepool {
        [[PSXMacMenuController sharedController] populateMainMenu];
    }
}

void psx_macos_menu_sync_state(void) {
    @autoreleasepool {
        [[PSXMacMenuController sharedController] refreshCheckmarks];
    }
}

int psx_macos_menu_verify_instantiation(void) {
    @autoreleasepool {
        NSMenu *menu = [NSApp mainMenu];
        if (!menu) return 0;
        if (![menu itemWithTitle:@"2Xtreme"]) return 0;
        if (![menu itemWithTitle:@"Game"]) return 0;
        if (![menu itemWithTitle:@"Video"]) return 0;
        if (![menu itemWithTitle:@"Mods"]) return 0;

        // Verify submenus exist and are populated
        NSMenuItem *gameItem = [menu itemWithTitle:@"Game"];
        if (!gameItem.submenu || ![gameItem.submenu itemWithTitle:@"Fast Boot (Bypass BIOS)"]) return 0;
        if (![gameItem.submenu itemWithTitle:@"Direct Track Launch"]) return 0;

        NSMenuItem *videoItem = [menu itemWithTitle:@"Video"];
        if (!videoItem.submenu || ![videoItem.submenu itemWithTitle:@"Widescreen / Aspect Ratio"]) return 0;
        if (![videoItem.submenu itemWithTitle:@"Internal Resolution"]) return 0;

        NSMenuItem *modsItem = [menu itemWithTitle:@"Mods"];
        if (!modsItem.submenu || ![modsItem.submenu itemWithTitle:@"HD Texture Pack"]) return 0;
        if (![modsItem.submenu itemWithTitle:@"CD-DA Audio Replacement"]) return 0;

        return 1;
    }
}

void psx_macos_set_widescreen(int aspect_mode) {
    int num = 4, den = 3;
    if (aspect_mode == 1) { num = 16; den = 9; }
    else if (aspect_mode == 2) { num = 21; den = 9; }

    if (psx_engine_set_widescreen) {
        psx_engine_set_widescreen(aspect_mode);
    }

    mutate_and_save_settings([num, den](PSXRecompV4::UserSettings& s) {
        s.has_aspect_ratio = true;
        s.aspect_num = num;
        s.aspect_den = den;
    });
}

int psx_macos_get_widescreen(void) {
    if (psx_engine_get_widescreen) {
        return psx_engine_get_widescreen();
    }
    fs::path dir = get_active_config_dir();
    PSXRecompV4::UserSettings s = PSXRecompV4::load_user_settings(dir / "settings.toml");
    if (s.has_aspect_ratio) {
        if (s.aspect_num == 16 && s.aspect_den == 9) return 1;
        if (s.aspect_num == 21 && s.aspect_den == 9) return 2;
    }
    return 0; // 4:3
}

void psx_macos_set_resolution(int ir_preset) {
    if (psx_engine_set_resolution) {
        psx_engine_set_resolution(ir_preset);
    }

    mutate_and_save_settings([ir_preset](PSXRecompV4::UserSettings& s) {
        s.has_internal_resolution = true;
        s.internal_resolution = ir_preset;
    });
}

int psx_macos_get_resolution(void) {
    if (psx_engine_get_resolution) {
        return psx_engine_get_resolution();
    }
    fs::path dir = get_active_config_dir();
    PSXRecompV4::UserSettings s = PSXRecompV4::load_user_settings(dir / "settings.toml");
    if (s.has_internal_resolution) {
        return s.internal_resolution;
    }
    return 1; // Native
}

void psx_macos_set_fast_boot(int enabled) {
    if (psx_engine_set_fast_boot) {
        psx_engine_set_fast_boot(enabled);
    }

    mutate_and_save_settings([enabled](PSXRecompV4::UserSettings& s) {
        s.has_fast_boot = true;
        s.fast_boot = (enabled != 0);
    });
}

int psx_macos_get_fast_boot(void) {
    if (psx_engine_get_fast_boot) {
        return psx_engine_get_fast_boot();
    }
    fs::path dir = get_active_config_dir();
    PSXRecompV4::UserSettings s = PSXRecompV4::load_user_settings(dir / "settings.toml");
    if (s.has_fast_boot) {
        return s.fast_boot ? 1 : 0;
    }
    return 0;
}

void psx_macos_set_mod_enabled(const char* package_id, const char* feature_id, int enabled) {
    fs::path dir = get_active_config_dir();
    fs::path mods_dir = dir / "mods";
    if (!fs::exists(mods_dir)) {
        fs::path parent = dir.parent_path().parent_path().parent_path() / "mods";
        if (fs::exists(parent)) mods_dir = parent;
    }
    ModPackageManager mgr(mods_dir);
    mgr.load_state();
    mgr.set_feature_enabled(package_id ? package_id : "", feature_id ? feature_id : "", enabled != 0);
    mgr.save_state();
}

int psx_macos_get_mod_enabled(const char* package_id, const char* feature_id) {
    fs::path dir = get_active_config_dir();
    fs::path mods_dir = dir / "mods";
    if (!fs::exists(mods_dir)) {
        fs::path parent = dir.parent_path().parent_path().parent_path() / "mods";
        if (fs::exists(parent)) mods_dir = parent;
    }
    ModPackageManager mgr(mods_dir);
    mgr.load_state();
    return mgr.feature_enabled(package_id ? package_id : "", feature_id ? feature_id : "") ? 1 : 0;
}

void psx_macos_launch_direct_track(int course_id, int track_num, int skater_id) {
    std::fprintf(stdout,
        "[psx_macos] Triggering Direct Track Launch: course=%d, track=%d, skater=%d\n",
        course_id, track_num, skater_id);
    std::fflush(stdout);
    if (psx_direct_boot_race_track) {
        psx_direct_boot_race_track(course_id, track_num, skater_id);
    }
}
