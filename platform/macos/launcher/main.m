/* 2Xtreme launcher.
 *
 * Returning players: if the game is prepared, exec it immediately (no window).
 * First run: one window in 2Xtreme's spirit asks for the player's own disc,
 * then prepares the game on this Mac with the bundled tools (no Apple tools,
 * no Python) into ~/Library/Application Support/2Xtreme, and starts it.
 *
 * Nothing from the game's disc ships in the app; all game code is made here.
 */
#import <Cocoa/Cocoa.h>
#import <GameController/GameController.h>
#include <sys/sysctl.h>
#include <unistd.h>

#include "disc.h"

/* ---------- Paths ---------- */

static NSString *DataDir(void) {
    const char *over = getenv("TWOXTREME_DATA_DIR");  /* developer/test override */
    if (over && over[0]) return [NSString stringWithUTF8String:over];
    NSURL *base = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory
                                                         inDomains:NSUserDomainMask].firstObject;
    return [base.path stringByAppendingPathComponent:@"2Xtreme"];
}
static NSString *GameDir(void)  { return [DataDir() stringByAppendingPathComponent:@"game"]; }
static NSString *DiscDir(void)  { return [DataDir() stringByAppendingPathComponent:@"disc"]; }
static NSString *BuildDir(void) { return [DataDir() stringByAppendingPathComponent:@"build"]; }
static NSString *SavesDir(void) { return [DataDir() stringByAppendingPathComponent:@"saves"]; }
static NSString *Res(NSString *rel) {
    return [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:rel];
}
static NSString *BuildStamp(void) {
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    return [NSString stringWithFormat:@"%@ (%@)", info[@"CFBundleShortVersionString"], info[@"CFBundleVersion"]];
}
static NSString *StampPath(void) { return [GameDir() stringByAppendingPathComponent:@".prepared"]; }
static NSString *DiscRecordPath(void) { return [GameDir() stringByAppendingPathComponent:@".disc"]; }

static NSString *ReadText(NSString *p) {
    return [[NSString stringWithContentsOfFile:p encoding:NSUTF8StringEncoding error:nil]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

/* Prepared and current: the game, its module, this app's stamp, and the disc. */
static BOOL GameIsReady(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *disc = ReadText(DiscRecordPath());
    return [fm isExecutableFileAtPath:[GameDir() stringByAppendingPathComponent:@"2Xtreme"]] &&
           [fm fileExistsAtPath:[GameDir() stringByAppendingPathComponent:@"game.dylib"]] &&
           [ReadText(StampPath()) isEqualToString:BuildStamp()] &&
           disc.length && [fm fileExistsAtPath:disc];
}

/* Was it prepared before (an app update only needs a quick rebuild)? */
static BOOL DiscAlreadyCopied(void) {
    NSString *disc = ReadText(DiscRecordPath());
    return disc.length && [[NSFileManager defaultManager] fileExistsAtPath:disc];
}

static void LaunchGameAndExit(void) __attribute__((noreturn));
static void LaunchGameAndExit(void) {
    NSString *exe = [GameDir() stringByAppendingPathComponent:@"2Xtreme"];
    chdir(GameDir().fileSystemRepresentation);
    char *argv[] = {"2Xtreme", NULL};
    execv(exe.fileSystemRepresentation, argv);
    fprintf(stderr, "2Xtreme: could not start the game: %s\n", strerror(errno));
    exit(1);
}

/* ---------- Look: tokens sampled from 2Xtreme's menus (docs/DESIGN_PRINCIPLES.md) ---------- */

#define TWOX_YELLOW [NSColor colorWithSRGBRed:0.96 green:0.85 blue:0.18 alpha:1]
#define TWOX_GREEN  [NSColor colorWithSRGBRed:0.31 green:0.80 blue:0.49 alpha:1]
#define TWOX_RED    [NSColor colorWithSRGBRed:0.66 green:0.16 blue:0.12 alpha:1]
#define TWOX_INK    [NSColor colorWithSRGBRed:0.04 green:0.03 blue:0.03 alpha:1]
#define TWOX_TEXT   [NSColor colorWithSRGBRed:0.86 green:0.84 blue:0.80 alpha:1]

static NSFont *BlockFont(CGFloat size) {
    NSFont *f = [NSFont fontWithName:@"Futura-CondensedExtraBold" size:size];
    return f ? f : [NSFont systemFontOfSize:size weight:NSFontWeightBlack];
}
static NSFont *BodyFont(CGFloat size) {
    NSFont *f = [NSFont fontWithName:@"Futura-Medium" size:size];
    return f ? f : [NSFont systemFontOfSize:size weight:NSFontWeightMedium];
}

/* Extruded block capitals like the original menu: dark depth, then the face. */
static void DrawBlockText(NSString *text, NSPoint center, CGFloat size, NSColor *face) {
    NSDictionary *a = @{NSFontAttributeName: BlockFont(size), NSKernAttributeName: @(size * 0.02)};
    NSSize sz = [text sizeWithAttributes:a];
    NSPoint origin = NSMakePoint(round(center.x - sz.width / 2), round(center.y - sz.height / 2));
    NSMutableDictionary *depth = [a mutableCopy];
    depth[NSForegroundColorAttributeName] = TWOX_INK;
    int steps = (int)MAX(3, size / 12);
    for (int i = steps; i > 0; i--)
        [text drawAtPoint:NSMakePoint(origin.x + i, origin.y - i) withAttributes:depth];
    NSMutableDictionary *top = [a mutableCopy];
    top[NSForegroundColorAttributeName] = face;
    [text drawAtPoint:origin withAttributes:top];
}

static void DrawCenteredText(NSString *text, NSRect box, NSFont *font, NSColor *color) {
    NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new];
    ps.alignment = NSTextAlignmentCenter;
    NSDictionary *a = @{NSFontAttributeName: font, NSForegroundColorAttributeName: color,
                        NSParagraphStyleAttributeName: ps};
    NSRect r = [text boundingRectWithSize:box.size options:NSStringDrawingUsesLineFragmentOrigin attributes:a];
    NSRect drawn = NSMakeRect(box.origin.x, NSMidY(box) - r.size.height / 2, box.size.width, r.size.height);
    [text drawWithRect:drawn options:NSStringDrawingUsesLineFragmentOrigin attributes:a];
}

/* ---------- Setup view ---------- */

typedef NS_ENUM(NSInteger, SetupState) { SetupWelcome, SetupWorking, SetupError };

@interface SetupView : NSView
@property (nonatomic) SetupState state;
@property (nonatomic, copy) NSString *heading;
@property (nonatomic, copy) NSString *message;
@property (nonatomic, copy) NSString *buttonTitle;
@property (nonatomic, copy) NSString *step;
@property (nonatomic, copy) NSString *timeLeft;
@property (nonatomic) double progress;
@property (nonatomic) BOOL controllerActive;
@property (nonatomic) BOOL dropHover;
@property (nonatomic, copy) void (^onPrimary)(void);
@property (nonatomic, copy) void (^onDrop)(NSString *path);
@end

@implementation SetupView

- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)isFlipped { return NO; }

- (NSRect)buttonRect {
    NSRect b = self.bounds;
    return NSMakeRect(NSMidX(b) - 170, NSHeight(b) * 0.22, 340, 64);
}

- (void)drawBackdrop {
    NSRect b = self.bounds;
    [TWOX_INK setFill];
    NSRectFill(b);
    /* Brick wall, drawn here (no game artwork): dim courses of bricks. */
    CGFloat bw = 46, bh = 20;
    for (int row = 0; row * bh < NSHeight(b); row++) {
        CGFloat off = (row % 2) ? bw / 2 : 0;
        for (CGFloat x = -off; x < NSWidth(b); x += bw) {
            NSRect brick = NSMakeRect(x + 1.5, row * bh + 1.5, bw - 3, bh - 3);
            CGFloat shade = 0.10 + 0.03 * ((row * 7 + (int)(x / bw) * 3) % 4);
            [[NSColor colorWithSRGBRed:shade + 0.07 green:shade * 0.55 blue:shade * 0.42 alpha:1] setFill];
            [[NSBezierPath bezierPathWithRoundedRect:brick xRadius:1.5 yRadius:1.5] fill];
        }
    }
    /* One spotlight from above, heavy vignette, like the original menu. */
    NSGradient *spot = [[NSGradient alloc] initWithColorsAndLocations:
        [NSColor colorWithSRGBRed:0.35 green:0.40 blue:0.95 alpha:0.30], 0.0,
        [NSColor colorWithSRGBRed:0.20 green:0.20 blue:0.55 alpha:0.12], 0.45,
        [NSColor colorWithWhite:0 alpha:0.86], 1.0, nil];
    [spot drawInRect:b relativeCenterPosition:NSMakePoint(0, 0.55)];
}

- (void)drawPromptStrip {
    NSRect b = self.bounds;
    NSString *action = self.state == SetupWorking ? nil
        : (self.controllerActive ? @"Ⓐ  " : @"Return  ");
    if (!action) return;
    NSString *label = self.state == SetupError ? @"Try again" : @"Choose disc";
    NSString *s = [action stringByAppendingString:label];
    NSDictionary *a = @{NSFontAttributeName: BlockFont(20), NSForegroundColorAttributeName: TWOX_TEXT};
    NSRect strip = NSMakeRect(24, 20, [s sizeWithAttributes:a].width + 32, 38);
    [[NSColor colorWithWhite:0 alpha:0.55] setFill];
    [[NSBezierPath bezierPathWithRect:strip] fill];
    [s drawAtPoint:NSMakePoint(strip.origin.x + 16, strip.origin.y + 7) withAttributes:a];
}

- (void)drawRect:(NSRect)dirty {
    NSRect b = self.bounds;
    [self drawBackdrop];

    /* Title: the 2X mark in red, XTREME in yellow, extruded. */
    CGFloat titleY = NSHeight(b) * 0.80;
    DrawBlockText(@"2", NSMakePoint(NSMidX(b) - 150, titleY), 92, TWOX_RED);
    DrawBlockText(@"XTREME", NSMakePoint(NSMidX(b) + 40, titleY), 92, TWOX_YELLOW);

    DrawBlockText(self.heading ?: @"", NSMakePoint(NSMidX(b), NSHeight(b) * 0.60), 44,
                  self.state == SetupError ? TWOX_YELLOW : TWOX_GREEN);
    DrawCenteredText(self.message ?: @"", NSMakeRect(NSMidX(b) - 330, NSHeight(b) * 0.40, 660, 90),
                     BodyFont(20), TWOX_TEXT);

    if (self.state == SetupWorking) {
        NSRect bar = NSMakeRect(NSMidX(b) - 300, NSHeight(b) * 0.30, 600, 18);
        [[NSColor colorWithWhite:0 alpha:0.6] setFill];
        [[NSBezierPath bezierPathWithRect:NSInsetRect(bar, -3, -3)] fill];
        [[NSColor colorWithWhite:1 alpha:0.08] setFill];
        [[NSBezierPath bezierPathWithRect:bar] fill];
        NSRect fill = bar;
        fill.size.width = round(bar.size.width * MAX(0.0, MIN(1.0, self.progress)));
        [TWOX_GREEN setFill];
        [[NSBezierPath bezierPathWithRect:fill] fill];
        DrawCenteredText(self.step ?: @"", NSMakeRect(bar.origin.x, bar.origin.y - 52, bar.size.width, 30),
                         BodyFont(18), TWOX_TEXT);
        DrawCenteredText(self.timeLeft ?: @"", NSMakeRect(bar.origin.x, bar.origin.y - 82, bar.size.width, 26),
                         BodyFont(15), [TWOX_TEXT colorWithAlphaComponent:0.7]);
    } else {
        NSRect r = [self buttonRect];
        [[NSColor colorWithWhite:0 alpha:0.6] setFill];
        [[NSBezierPath bezierPathWithRect:NSOffsetRect(r, 5, -5)] fill];
        [(self.dropHover ? TWOX_GREEN : TWOX_YELLOW) setFill];
        [[NSBezierPath bezierPathWithRect:r] fill];
        DrawBlockText(self.buttonTitle ?: @"", NSMakePoint(NSMidX(r), NSMidY(r) + 2), 30, TWOX_INK);
    }
    [self drawPromptStrip];
}

- (void)mouseUp:(NSEvent *)e {
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
    if (self.state != SetupWorking && NSPointInRect(p, [self buttonRect]) && self.onPrimary) self.onPrimary();
}

- (void)keyDown:(NSEvent *)e {
    if (e.keyCode == 36 || e.keyCode == 76 || e.keyCode == 49) {  /* Return, Enter, Space */
        self.controllerActive = NO;
        if (self.state != SetupWorking && self.onPrimary) self.onPrimary();
    } else if (e.keyCode == 53 && self.state != SetupWorking) {    /* Esc */
        [NSApp terminate:nil];
    }
}

/* Drag a disc image onto the window. */
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)info {
    if (self.state == SetupWorking) return NSDragOperationNone;
    self.dropHover = YES; [self setNeedsDisplay:YES];
    return NSDragOperationCopy;
}
- (void)draggingExited:(id<NSDraggingInfo>)info { self.dropHover = NO; [self setNeedsDisplay:YES]; }
- (BOOL)performDragOperation:(id<NSDraggingInfo>)info {
    self.dropHover = NO; [self setNeedsDisplay:YES];
    NSURL *url = [NSURL URLFromPasteboard:info.draggingPasteboard];
    if (url.isFileURL && self.onDrop) { self.onDrop(url.path); return YES; }
    return NO;
}
@end

/* ---------- Preparing the game ---------- */

@interface Preparer : NSObject
@property (nonatomic, copy) void (^onProgress)(double fraction, NSString *step);
@property (nonatomic, copy) void (^onFailure)(NSString *heading, NSString *message);
@property (nonatomic, copy) void (^onDone)(void);
- (void)prepareWithDisc:(TwoxDisc)disc copyDisc:(BOOL)copyDisc;
@end

@implementation Preparer

- (void)report:(double)f step:(NSString *)s {
    dispatch_async(dispatch_get_main_queue(), ^{ if (self.onProgress) self.onProgress(f, s); });
}
- (void)fail:(NSString *)h message:(NSString *)m {
    dispatch_async(dispatch_get_main_queue(), ^{ if (self.onFailure) self.onFailure(h, m); });
}

static int RunTool(NSString *exe, NSArray<NSString *> *args, NSString *cwd, NSString **errText) {
    NSTask *t = [NSTask new];
    t.executableURL = [NSURL fileURLWithPath:exe];
    t.arguments = args;
    t.currentDirectoryURL = [NSURL fileURLWithPath:cwd];
    NSMutableDictionary *env = [NSMutableDictionary new];
    env[@"HOME"] = NSHomeDirectory();
    env[@"PATH"] = @"/bin";  /* never reach for Apple's developer tools */
    NSString *cache = [BuildDir() stringByAppendingPathComponent:@"zig-cache"];
    env[@"ZIG_GLOBAL_CACHE_DIR"] = cache;
    env[@"ZIG_LOCAL_CACHE_DIR"] = cache;
    t.environment = env;
    NSPipe *err = [NSPipe pipe];
    t.standardError = err;
    t.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    NSError *e = nil;
    if (![t launchAndReturnError:&e]) { if (errText) *errText = e.localizedDescription; return -1; }
    NSData *d = [err.fileHandleForReading readDataToEndOfFile];
    [t waitUntilExit];
    if (errText) *errText = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    return t.terminationStatus;
}

/* Copy the disc's files with progress, so the game never depends on where
 * the player keeps their image (and macOS never asks about that folder). */
- (NSString *)copyDisc:(TwoxDisc)disc from:(double)f0 to:(double)f1 {
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:DiscDir() error:nil];
    [fm createDirectoryAtPath:DiscDir() withIntermediateDirectories:YES attributes:nil error:nil];
    long long total = 0, done = 0;
    for (int i = 0; i < disc.file_count; i++)
        total += [[fm attributesOfItemAtPath:@(disc.files[i]) error:nil] fileSize];
    NSMutableArray *paths = [NSMutableArray new];
    if (disc.cue_path[0]) [paths addObject:@(disc.cue_path)];
    for (int i = 0; i < disc.file_count; i++) [paths addObject:@(disc.files[i])];
    static char buf[4 << 20];
    for (NSString *src in paths) {
        NSString *dst = [DiscDir() stringByAppendingPathComponent:src.lastPathComponent];
        FILE *in = fopen(src.fileSystemRepresentation, "rb"), *out = fopen(dst.fileSystemRepresentation, "wb");
        if (!in || !out) { if (in) fclose(in); if (out) fclose(out); return nil; }
        size_t n;
        while ((n = fread(buf, 1, sizeof(buf), in)) > 0) {
            if (fwrite(buf, 1, n, out) != n) { fclose(in); fclose(out); return nil; }
            if (![src.pathExtension.lowercaseString isEqualToString:@"cue"]) done += n;
            [self report:f0 + (f1 - f0) * (total ? (double)done / total : 1) step:@"Copying your disc…"];
        }
        fclose(in);
        if (fclose(out) != 0) return nil;
    }
    NSString *chosen = disc.cue_path[0] ? @(disc.cue_path) : @(disc.files[0]);
    return [DiscDir() stringByAppendingPathComponent:chosen.lastPathComponent];
}

- (void)prepareWithDisc:(TwoxDisc)disc copyDisc:(BOOL)copyDisc {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm createDirectoryAtPath:GameDir() withIntermediateDirectories:YES attributes:nil error:nil];
        [fm createDirectoryAtPath:SavesDir() withIntermediateDirectories:YES attributes:nil error:nil];

        /* 1. The player's disc, kept in our folder. */
        NSString *discPath = ReadText(DiscRecordPath());
        if (copyDisc) {
            discPath = [self copyDisc:disc from:0.0 to:0.35];
            if (!discPath) {
                [self fail:@"NOT ENOUGH ROOM"
                   message:@"2Xtreme couldn't copy your disc. Make sure your Mac has about 1 GB free, then try again."];
                return;
            }
        }
        TwoxDisc local;
        if (twox_disc_resolve(discPath.fileSystemRepresentation, &local) != TWOX_DISC_OK) {
            [self fail:@"DISC MISSING" message:@"Choose your 2Xtreme disc again."];
            return;
        }

        /* 2. Read the game's program off the disc and recompile it to C. */
        [self report:0.38 step:@"Reading the game from your disc…"];
        NSString *proj = BuildDir();
        [fm removeItemAtPath:[proj stringByAppendingPathComponent:@"generated"] error:nil];
        [fm createDirectoryAtPath:[proj stringByAppendingPathComponent:@"disc"] withIntermediateDirectories:YES attributes:nil error:nil];
        for (NSString *item in [fm contentsOfDirectoryAtPath:Res(@"project") error:nil]) {
            NSString *dst = [proj stringByAppendingPathComponent:item];
            [fm removeItemAtPath:dst error:nil];
            [fm copyItemAtPath:[Res(@"project") stringByAppendingPathComponent:item] toPath:dst error:nil];
        }
        NSString *exe = [proj stringByAppendingPathComponent:@"disc/SCUS_945.08"];
        if (twox_disc_extract(local.data_path, local.sector_size, "SCUS_945.08", exe.fileSystemRepresentation) != 0) {
            [self fail:@"CAN'T READ THE DISC" message:@"Your disc image looks damaged. Try making a fresh copy from the original disc."];
            return;
        }
        NSString *errText = nil;
        if (RunTool(Res(@"tools/psxrecomp-game"), @[@"--config", @"game.toml"], proj, &errText) != 0) {
            NSLog(@"psxrecomp-game: %@", errText);
            [self fail:@"PREPARING FAILED" message:@"2Xtreme couldn't read the game from your disc. Please report this, with your Mac model."];
            return;
        }

        /* 3. Build it for this Mac with the bundled compiler, in parallel. */
        NSString *gen = [proj stringByAppendingPathComponent:@"generated"];
        NSString *objDir = [proj stringByAppendingPathComponent:@"obj"];
        [fm removeItemAtPath:objDir error:nil];
        [fm createDirectoryAtPath:objDir withIntermediateDirectories:YES attributes:nil error:nil];
        NSArray *cflags = [ReadText(Res(@"sdk/cflags.txt")) componentsSeparatedByString:@"\n"];
        NSMutableArray *incs = [NSMutableArray new];
        for (NSString *d in [[fm contentsOfDirectoryAtPath:Res(@"sdk/include") error:nil] sortedArrayUsingSelector:@selector(compare:)])
            [incs addObject:[@"-I" stringByAppendingString:[Res(@"sdk/include") stringByAppendingPathComponent:d]]];
        [incs addObject:[@"-I" stringByAppendingString:gen]];
        NSMutableArray *sources = [NSMutableArray new];
        for (NSString *f in [fm contentsOfDirectoryAtPath:gen error:nil])
            if ([f.pathExtension isEqualToString:@"c"]) [sources addObject:f];

        NSString *zig = Res(@"toolchain/zig");
        __block int finished = 0, failed = 0;
        __block NSString *firstError = nil;
        dispatch_group_t group = dispatch_group_create();
        int ncpu = 4; size_t len = sizeof(ncpu);
        sysctlbyname("hw.ncpu", &ncpu, &len, NULL, 0);
        dispatch_semaphore_t slots = dispatch_semaphore_create(MAX(1, ncpu));
        NSObject *lock = [NSObject new];
        [self report:0.45 step:@"Building 2Xtreme for this Mac…"];
        for (NSString *src in sources) {
            dispatch_semaphore_wait(slots, DISPATCH_TIME_FOREVER);
            dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                NSMutableArray *args = [@[@"cc", @"-target", @"aarch64-macos.13.0", @"-fPIC"] mutableCopy];
                for (NSString *f in cflags) if (f.length) [args addObject:f];
                [args addObjectsFromArray:incs];
                [args addObjectsFromArray:@[@"-c", [gen stringByAppendingPathComponent:src],
                                            @"-o", [objDir stringByAppendingPathComponent:[src stringByAppendingString:@".o"]]]];
                NSString *e = nil;
                int rc = RunTool(zig, args, proj, &e);
                @synchronized (lock) {
                    finished++;
                    if (rc != 0) { failed++; if (!firstError) firstError = e; }
                }
                [self report:0.45 + 0.40 * finished / (double)sources.count step:@"Building 2Xtreme for this Mac…"];
                dispatch_semaphore_signal(slots);
            });
        }
        dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
        if (failed) {
            NSLog(@"zig cc: %@", firstError);
            [self fail:@"PREPARING FAILED" message:@"2Xtreme couldn't be built on this Mac. Please report this, with your Mac model."];
            return;
        }

        [self report:0.88 step:@"Finishing up…"];
        NSMutableArray *link = [@[@"cc", @"-target", @"aarch64-macos.13.0", @"-shared",
                                  @"-undefined", @"dynamic_lookup", @"-o",
                                  [proj stringByAppendingPathComponent:@"game.dylib"]] mutableCopy];
        for (NSString *src in sources) [link addObject:[objDir stringByAppendingPathComponent:[src stringByAppendingString:@".o"]]];
        if (RunTool(zig, link, proj, &errText) != 0) {
            NSLog(@"zig link: %@", errText);
            [self fail:@"PREPARING FAILED" message:@"2Xtreme couldn't be built on this Mac. Please report this, with your Mac model."];
            return;
        }

        /* 4. Install: the prebuilt runtime from the app, then the new module. */
        [self report:0.95 step:@"Finishing up…"];
        NSSet *keep = [NSSet setWithArray:@[@"settings.toml", @"input.ini", @"overlay_captures.json",
                                           @"overlay_captures.json.d", @".disc", @"saves"]];
        for (NSString *item in [fm contentsOfDirectoryAtPath:Res(@"runtime") error:nil]) {
            if ([keep containsObject:item]) continue;
            NSString *dst = [GameDir() stringByAppendingPathComponent:item];
            [fm removeItemAtPath:dst error:nil];
            [fm copyItemAtPath:[Res(@"runtime") stringByAppendingPathComponent:item] toPath:dst error:nil];
        }
        NSString *module = [GameDir() stringByAppendingPathComponent:@"game.dylib"];
        [fm removeItemAtPath:module error:nil];
        [fm moveItemAtPath:[proj stringByAppendingPathComponent:@"game.dylib"] toPath:module error:nil];
        [self writeSettingsIfMissing:discPath];
        [discPath writeToFile:DiscRecordPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [BuildStamp() writeToFile:StampPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [self report:1.0 step:@"Ready."];
        dispatch_async(dispatch_get_main_queue(), ^{ if (self.onDone) self.onDone(); });
    });
}

/* First-run defaults: the best experience for most players (PRODUCT_RULES §5). */
- (void)writeSettingsIfMissing:(NSString *)discPath {
    NSString *path = [GameDir() stringByAppendingPathComponent:@"settings.toml"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        /* Keep the player's settings; only point at the current disc copy. */
        NSString *s = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"(?m)^(\\[disc\\]\\s*\\npath\\s*=\\s*).*$" options:0 error:nil];
        NSString *escaped = [discPath stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
        s = [re stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0, s.length)
                                    withTemplate:[NSString stringWithFormat:@"$1\"%@\"", [NSRegularExpression escapedTemplateForString:escaped]]];
        [s writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        return;
    }
    NSString *saves = SavesDir();
    NSString *toml = [NSString stringWithFormat:
        @"# 2Xtreme settings. Written at first launch; the in-game menu updates it.\n\n"
         "[video]\n"
         "renderer = \"opengl\"\n"
         "internal_resolution = \"1080p\"\n"
         "texture_filtering = \"nearest\"\n"
         "aspect_ratio = \"4:3\"\n"
         "window_width = 1280\n"
         "fullscreen = 0\n\n"
         "[launcher]\n"
         "skip_launcher = true\n\n"
         "[disc]\n"
         "path = \"%@\"\n\n"
         "[memcard]\n"
         "dir = \"%@\"\n"
         "card1 = \"%@/card1.mcd\"\n"
         "card2 = \"%@/card2.mcd\"\n"
         "enable1 = true\n"
         "enable2 = true\n\n"
         "[controller]\n"
         "p1_device = \"auto\"\n"
         "p2_device = \"none\"\n",
        discPath, saves, saves, saves];
    [toml writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
@end

/* ---------- App ---------- */

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property (strong) NSWindow *window;
@property (strong) SetupView *view;
@property (strong) Preparer *preparer;
@property (strong) NSDate *started;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)n {
    NSRect frame = NSMakeRect(0, 0, 1000, 640);
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                        NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskFullSizeContentView
                                                backing:NSBackingStoreBuffered defer:NO];
    self.window.titlebarAppearsTransparent = YES;
    self.window.titleVisibility = NSWindowTitleHidden;
    self.window.title = @"2Xtreme";
    self.window.delegate = self;
    self.view = [[SetupView alloc] initWithFrame:frame];
    [self.view registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    __weak AppDelegate *weak = self;
    self.view.onPrimary = ^{ [weak primaryAction]; };
    self.view.onDrop = ^(NSString *path) { [weak useDisc:path]; };
    self.window.contentView = self.view;
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:self.view];
    [NSApp activateIgnoringOtherApps:YES];
    [self watchControllers];

    if (DiscAlreadyCopied()) {
        /* App update: the disc is already here, just rebuild quickly. */
        [self startPreparing:(TwoxDisc){0} copyDisc:NO heading:@"UPDATING 2XTREME"];
    } else {
        [self showWelcome];
        /* Developer/test hook: pick this disc automatically after the welcome
         * screen has been shown, so the whole journey can be screenshotted. */
        const char *test_disc = getenv("TWOXTREME_TEST_DISC");
        if (test_disc && test_disc[0]) {
            NSString *path = @(test_disc);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [self useDisc:path];
            });
        }
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)a { return YES; }

- (void)showWelcome {
    SetupView *v = self.view;
    v.state = SetupWelcome;
    v.heading = @"INSERT YOUR DISC";
    v.message = @"Choose your 2Xtreme (USA) disc image, or drop it here.\nUse the .cue file if you have one, so the music comes too.";
    v.buttonTitle = @"CHOOSE DISC";
    [v setNeedsDisplay:YES];
}

- (void)showError:(NSString *)heading message:(NSString *)message {
    SetupView *v = self.view;
    v.state = SetupError;
    v.heading = heading;
    v.message = message;
    v.buttonTitle = @"CHOOSE DISC";
    [v setNeedsDisplay:YES];
}

- (void)primaryAction {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.message = @"Choose your 2Xtreme (USA) disc image";
    panel.prompt = @"Use This Disc";
    panel.allowedFileTypes = @[@"cue", @"bin", @"img", @"iso", @"chd"];
    panel.directoryURL = [[NSFileManager defaultManager] URLsForDirectory:NSDownloadsDirectory inDomains:NSUserDomainMask].firstObject;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
        if (r == NSModalResponseOK) [self useDisc:panel.URL.path];
    }];
}

- (void)useDisc:(NSString *)path {
    TwoxDisc disc;
    switch (twox_disc_resolve(path.fileSystemRepresentation, &disc)) {
        case TWOX_DISC_CHD:
            [self showError:@"CHD NOT SUPPORTED YET"
                    message:@"2Xtreme can't read .chd images yet. Use the .cue and .bin version of your disc."];
            return;
        case TWOX_DISC_MISSING_TRACK:
            [self showError:@"TRACKS MISSING"
                    message:@"The .cue file lists tracks that aren't next to it. Keep all the .bin files in the same folder as the .cue."];
            return;
        case TWOX_DISC_OK: break;
        default:
            [self showError:@"THAT'S NOT A DISC IMAGE"
                    message:@"Choose the .cue (or .bin) file of your 2Xtreme (USA) disc."];
            return;
    }
    if (twox_disc_verify(&disc) != TWOX_DISC_OK) {
        [self showError:@"WRONG DISC"
                message:@"This isn't the 2Xtreme (USA) disc this version supports (SCUS-94508). Choose your 2Xtreme (USA) disc image."];
        return;
    }
    [self startPreparing:disc copyDisc:YES heading:@"PREPARING 2XTREME"];
}

- (void)startPreparing:(TwoxDisc)disc copyDisc:(BOOL)copyDisc heading:(NSString *)heading {
    SetupView *v = self.view;
    v.state = SetupWorking;
    v.heading = heading;
    v.message = disc.file_count && !disc.has_audio_tracks
        ? @"This copy has no music tracks, so the game will play without its soundtrack.\nThis happens once. Later, 2Xtreme starts straight away."
        : @"This happens once. Later, 2Xtreme starts straight away.";
    v.progress = 0; v.step = @"Getting ready…"; v.timeLeft = @"";
    [v setNeedsDisplay:YES];
    self.started = [NSDate date];
    self.preparer = [Preparer new];
    __weak AppDelegate *weak = self;
    self.preparer.onProgress = ^(double f, NSString *step) {
        AppDelegate *s = weak; if (!s) return;
        s.view.progress = f; s.view.step = step;
        NSTimeInterval spent = -[s.started timeIntervalSinceNow];
        if (f > 0.08 && f < 1) {
            int left = (int)ceil(spent / f * (1 - f));
            s.view.timeLeft = left <= 5 ? @"Almost there" : [NSString stringWithFormat:@"About %d seconds left", (left + 4) / 5 * 5];
        }
        [s.view setNeedsDisplay:YES];
    };
    self.preparer.onFailure = ^(NSString *h, NSString *m) { [weak showError:h message:m]; };
    self.preparer.onDone = ^{ LaunchGameAndExit(); };
    [self.preparer prepareWithDisc:disc copyDisc:copyDisc];
}

/* Controller: A chooses, and the prompt shows the controller's button. */
- (void)watchControllers {
    __weak AppDelegate *weak = self;
    void (^attach)(GCController *) = ^(GCController *c) {
        c.extendedGamepad.buttonA.pressedChangedHandler = ^(GCControllerButtonInput *b, float v, BOOL pressed) {
            AppDelegate *s = weak; if (!s || !pressed) return;
            s.view.controllerActive = YES;
            if (s.view.state != SetupWorking) [s primaryAction];
            [s.view setNeedsDisplay:YES];
        };
    };
    for (GCController *c in GCController.controllers) attach(c);
    [[NSNotificationCenter defaultCenter] addObserverForName:GCControllerDidConnectNotification object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        attach(note.object);
        weak.view.controllerActive = YES;
        [weak.view setNeedsDisplay:YES];
    }];
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (GameIsReady() && !getenv("TWOXTREME_FORCE_SETUP")) LaunchGameAndExit();
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        AppDelegate *d = [AppDelegate new];
        app.delegate = d;
        NSMenu *bar = [NSMenu new];
        NSMenuItem *appItem = [NSMenuItem new];
        NSMenu *appMenu = [NSMenu new];
        [appMenu addItemWithTitle:@"Quit 2Xtreme" action:@selector(terminate:) keyEquivalent:@"q"];
        appItem.submenu = appMenu;
        [bar addItem:appItem];
        app.mainMenu = bar;
        [app run];
    }
    return 0;
}
