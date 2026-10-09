/* Loads the player's game module (game.dylib, compiled on their Mac from
 * their own disc) next to the prebuilt runtime, and forwards the five entry
 * points the runtime calls into it. The runtime ships without any game code.
 */
#include <dlfcn.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct CPUState CPUState;

static int (*s_dispatch)(CPUState*, uint32_t);
static int (*s_in_text)(uint32_t);
static int (*s_is_entry)(uint32_t);
static int (*s_native_ok)(uint32_t);
static int (*s_native_ok_full)(uint32_t);

static void *resolve(void *h, const char *name) {
    void *p = dlsym(h, name);
    if (!p) {
        fprintf(stderr, "2Xtreme: game module is missing %s. Prepare the game again.\n", name);
        exit(1);
    }
    return p;
}

__attribute__((constructor)) static void load_game_module(void) {
    char exe[PATH_MAX];
    uint32_t len = sizeof(exe);
    if (_NSGetExecutablePath(exe, &len) != 0) exit(1);
    char *slash = strrchr(exe, '/');
    if (!slash) exit(1);
    snprintf(slash + 1, sizeof(exe) - (size_t)(slash + 1 - exe), "game.dylib");

    void *h = dlopen(exe, RTLD_NOW | RTLD_GLOBAL);
    if (!h) {
        fprintf(stderr, "2Xtreme: can't load the game module (%s). Prepare the game again.\n", dlerror());
        exit(1);
    }
    s_dispatch       = resolve(h, "psx_dispatch_game_compiled");
    s_in_text        = resolve(h, "psx_game_address_in_text");
    s_is_entry       = resolve(h, "psx_game_is_function_entry");
    s_native_ok      = resolve(h, "psx_game_text_native_ok");
    s_native_ok_full = resolve(h, "psx_game_text_native_ok_full");
}

int psx_dispatch_game_compiled(CPUState *cpu, uint32_t addr) { return s_dispatch(cpu, addr); }
int psx_game_address_in_text(uint32_t addr) { return s_in_text(addr); }
int psx_game_is_function_entry(uint32_t addr) { return s_is_entry(addr); }
int psx_game_text_native_ok(uint32_t addr) { return s_native_ok(addr); }
int psx_game_text_native_ok_full(uint32_t addr) { return s_native_ok_full(addr); }
