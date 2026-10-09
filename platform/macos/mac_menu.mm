/* macOS menu bar for 2Xtreme.
 *
 * A thin front for the in-game menu: Settings… opens the same overlay as Esc
 * and the controller (docs/DESIGN_PRINCIPLES.md §5). It holds no settings of
 * its own. Developer tools appear only with TWOXTREME_DEVELOPER=1.
 */
#import <Cocoa/Cocoa.h>
#include "mac_menu.h"
#include "twox_overlay.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>

extern "C" __attribute__((weak)) void psx_direct_boot_race_track(int course_id, int track_num, int skater_id);

static bool developer_mode(void) {
    const char *e = getenv("TWOXTREME_DEVELOPER");
    return e && std::strcmp(e, "1") == 0;
}

struct TrackPreset { const char *name; int course_id; };
static const TrackPreset kTracks[] = {
    {"Los Angeles", 0}, {"Las Vegas", 1}, {"Africa", 2}, {"Japan", 3},
};

@interface PSXMacMenuController : NSObject
+ (instancetype)sharedController;
- (void)populateMainMenu;
@end

@implementation PSXMacMenuController

+ (instancetype)sharedController {
    static PSXMacMenuController *s_instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s_instance = [[PSXMacMenuController alloc] init]; });
    return s_instance;
}

- (NSMenuItem *)item:(NSString *)title action:(SEL)action key:(NSString *)key {
    NSMenuItem *i = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key];
    i.target = self;
    return i;
}

- (void)populateMainMenu {
    NSMenu *bar = [[NSMenu alloc] initWithTitle:@"MainMenu"];

    NSMenuItem *appItem = [[NSMenuItem alloc] initWithTitle:@"2Xtreme" action:nil keyEquivalent:@""];
    NSMenu *app = [[NSMenu alloc] initWithTitle:@"2Xtreme"];
    [app addItemWithTitle:@"About 2Xtreme" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [app addItem:[NSMenuItem separatorItem]];
    [app addItem:[self item:@"Settings…" action:@selector(openSettings:) key:@","]];
    [app addItem:[NSMenuItem separatorItem]];
    [app addItemWithTitle:@"Hide 2Xtreme" action:@selector(hide:) keyEquivalent:@"h"];
    NSMenuItem *others = [app addItemWithTitle:@"Hide Others" action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
    others.keyEquivalentModifierMask = NSEventModifierFlagOption | NSEventModifierFlagCommand;
    [app addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""];
    [app addItem:[NSMenuItem separatorItem]];
    [app addItemWithTitle:@"Quit 2Xtreme" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = app;
    [bar addItem:appItem];

    NSMenuItem *winItem = [[NSMenuItem alloc] initWithTitle:@"Window" action:nil keyEquivalent:@""];
    NSMenu *win = [[NSMenu alloc] initWithTitle:@"Window"];
    [win addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    NSMenuItem *fs = [win addItemWithTitle:@"Full Screen" action:@selector(toggleFullScreen:) keyEquivalent:@"f"];
    fs.keyEquivalentModifierMask = NSEventModifierFlagControl | NSEventModifierFlagCommand;
    winItem.submenu = win;
    [bar addItem:winItem];

    if (developer_mode() && psx_direct_boot_race_track) {
        NSMenuItem *devItem = [[NSMenuItem alloc] initWithTitle:@"Developer" action:nil keyEquivalent:@""];
        NSMenu *dev = [[NSMenu alloc] initWithTitle:@"Developer"];
        for (size_t i = 0; i < sizeof(kTracks) / sizeof(kTracks[0]); i++) {
            NSMenuItem *t = [self item:[NSString stringWithFormat:@"Boot Straight to %s", kTracks[i].name]
                                action:@selector(directTrack:) key:@""];
            t.tag = (NSInteger)i;
            [dev addItem:t];
        }
        devItem.submenu = dev;
        [bar addItem:devItem];
    }
    [NSApp setMainMenu:bar];
}

- (void)openSettings:(id)sender { twox_overlay_request_open(); }

- (void)directTrack:(NSMenuItem *)sender {
    if (sender.tag >= 0 && sender.tag < (NSInteger)(sizeof(kTracks) / sizeof(kTracks[0])))
        psx_direct_boot_race_track(kTracks[sender.tag].course_id, 0, 0);
}
@end

void psx_macos_menu_install(void) {
    @autoreleasepool { [[PSXMacMenuController sharedController] populateMainMenu]; }
}

void psx_macos_menu_sync_state(void) {}

int psx_macos_menu_verify_instantiation(void) {
    @autoreleasepool {
        NSMenu *menu = [NSApp mainMenu];
        NSMenuItem *app = [menu itemWithTitle:@"2Xtreme"];
        return menu && app && [app.submenu itemWithTitle:@"Settings…"] && [menu itemWithTitle:@"Window"] ? 1 : 0;
    }
}
