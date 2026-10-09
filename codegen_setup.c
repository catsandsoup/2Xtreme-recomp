/* Title config for psxrecomp/host/psxrecomp_codegen_host.
 * Wired only when the build opts into -DPSX_SETUP_WIZARD=ON.
 * 
 * Requirement R2: Expand CPU Player Counts
 * Safe Actor Memory Relocation to high RAM (0x800B0000+) and
 * Loop Bound Updates for ROAD.EXE overlays via runtime hooks.
 */

#include "codegen_setup.h"
#include "psxrecomp_codegen_host.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>
#include <pthread.h>
#include <stdbool.h>

/* Forward declarations from psxrecomp runtime */
extern uint8_t *memory_get_ram_ptr(void);
extern void dirty_ram_mark_executable_range(uint32_t phys, uint32_t len);

/* --- R2 Master Game State (0x80010000) & Direct Boot Configuration --- */
#define MASTER_GAME_STATE_ADDR   0x00010000u
#define MASTER_GAME_STATE_SIZE   0x09F0u /* 2,544 bytes */

#define MGS_OFFSET_NUM_PLAYERS   0x0208u /* 520: 0=2P, 1=1P */
#define MGS_OFFSET_SKATER_ID     0x020Au /* 522: 0..15 */
#define MGS_OFFSET_COURSE_ID     0x020Bu /* 523: 0=LA, 1=Vegas, 2=Africa, 3=Japan */
#define MGS_OFFSET_TRACK_NUM     0x0216u /* 534: 0=Track 1, 1=Track 2, 2=Track 3, 3=Bonus */
#define MGS_OFFSET_DEMO_FLAG     0x0217u /* 535: 0=live race, 1=demo */
#define MGS_OFFSET_OVERLAY_ID    0x095Fu /* 2399: target overlay index (1=ROAD.EXE) */

#define SCUS_EXE_STRING_ADDR     0x00010CFCu
#define SCUS_WAIT_LOOP_ADDR      0x00011828u
#define SCUS_FMV_CALL_ADDR       0x0001191Cu
#define SCUS_LOGO_CALL_ADDR      0x00011A10u
#define SCUS_LOGO_JAL_ADDR       0x00011A14u

static DirectTrackConfig s_direct_track = {
    .enabled = false,
    .course_id = TRACK_COURSE_AFRICA,
    .track_num = TRACK_NUM_1,
    .num_players = 1,
    .skater_id = 0,
};

static volatile bool s_direct_boot_applied = false;
static pthread_mutex_t s_direct_track_mutex = PTHREAD_MUTEX_INITIALIZER;

/* --- R2 CPU Player Count Expansion & Relocation Configuration --- */
#define EXPANDED_RACER_COUNT        16
#define RELOCATED_RACER_PTRS_ADDR   0x800B0000u
#define RELOCATED_RACERS_ADDR       0x800B0100u
#define RACER_STRUCT_STRIDE         204u /* 0xCC */

static pthread_t s_r2_thread;
static volatile bool s_r2_running = false;
static volatile bool s_r2_initialized = false;
static uint32_t s_r2_patches_applied = 0;
static volatile bool s_r2_racers_opted_in = false;
static void r2_start_watcher(void);

/* Helper to write a 32-bit word in guest RAM */
static inline void r2_write_ram_u32(uint8_t *ram, uint32_t phys_addr, uint32_t val) {
    *(uint32_t *)(ram + phys_addr) = val;
}

/* Helper to read a 32-bit word from guest RAM */
static inline uint32_t r2_read_ram_u32(const uint8_t *ram, uint32_t phys_addr) {
    return *(const uint32_t *)(ram + phys_addr);
}

/* Apply R2 patches to guest RAM */
static void r2_apply_patches(uint8_t *ram) {
    /* 1. Ensure relocated memory tables are initialized */
    /* Table of pointers at 0x800B0000 (phys 0x000B0000) for all 16 racers */
    for (uint32_t i = 0; i < EXPANDED_RACER_COUNT; i++) {
        uint32_t racer_addr = RELOCATED_RACERS_ADDR + (i * RACER_STRUCT_STRIDE);
        r2_write_ram_u32(ram, 0x000B0000u + (i * 4u), racer_addr);
    }

    /* Mirror the first 10 pointers into legacy table at 0x8007D134 (phys 0x0007D134)
     * strictly bounds-capped to 10 entries (40 bytes) to NEVER touch 0x8007D15C! */
    for (uint32_t i = 0; i < 10; i++) {
        uint32_t racer_addr = RELOCATED_RACERS_ADDR + (i * RACER_STRUCT_STRIDE);
        r2_write_ram_u32(ram, 0x0007D134u + (i * 4u), racer_addr);
    }

    /* 2. Check for ROAD.EXE / SNOW.EXE / NIGHT.EXE overlay code in RAM
     * Signature: 0x80033AFC has original bound slti $v0, $s1, 10 (0x2a22000a) */
    if (r2_read_ram_u32(ram, 0x00033AFCu) == 0x2a22000au) {
        /* Loop Bound Patches:
         * 0x80033AFC: Pointer setup loop bound -> 16 (0x2a220010)
         * 0x80032A1C: AI drone spawn loop bound -> 16 (0x28420010)
         * 0x8003301C: Ranking bubble sort outer bound -> 15 (0x28e2000f)
         * 0x80033040: Ranking bubble sort inner bound -> 16 (0x29020010)
         * 0x800330E0: Ranking placement loop bound -> 16 (0x28e20010) */
        r2_write_ram_u32(ram, 0x00033AFCu, 0x2a220010u);
        r2_write_ram_u32(ram, 0x00032A1Cu, 0x28420010u);
        r2_write_ram_u32(ram, 0x0003301Cu, 0x28e2000fu);
        r2_write_ram_u32(ram, 0x00033040u, 0x29020010u);
        r2_write_ram_u32(ram, 0x000330E0u, 0x28e20010u);

        /* Base Address Relocation Patches in func_80033A9C:
         * 0x80033AA8: lui   $a1, 0x800B        (0x3c05800b)
         * 0x80033AAC: addiu $a1, $a1, 0x0000   (0x24a50000) -> 0x800B0000 (racer_ptrs)
         * 0x80033AB0: lui   $a0, 0x800B        (0x3c04800b)
         * 0x80033AB4: addiu $a0, $a0, 0x0100   (0x24840100) -> 0x800B0100 (racers)
         * 0x80033AE0: lui   $at, 0x800B        (0x3c01800b)
         * 0x80033AE8: sh    $s1, 0x01ac($at)   (0xa43101ac) -> 0x800B01AC (rank field) */
        r2_write_ram_u32(ram, 0x00033AA8u, 0x3c05800bu);
        r2_write_ram_u32(ram, 0x00033AACu, 0x24a50000u);
        r2_write_ram_u32(ram, 0x00033AB0u, 0x3c04800bu);
        r2_write_ram_u32(ram, 0x00033AB4u, 0x24840100u);
        r2_write_ram_u32(ram, 0x00033AE0u, 0x3c01800bu);
        r2_write_ram_u32(ram, 0x00033AE8u, 0xa43101acu);

        /* Redirect other racer_ptrs table loads in ROAD.EXE to 0x800B0000:
         * 0x8002F3E4: lui   $s1, 0x800B        (0x3c11800b)
         * 0x8002F3E8: addiu $s1, $s1, 0x0000   (0x26310000)
         * 0x80033030: lui   $t4, 0x800B        (0x3c0c800b)
         * 0x80033034: addiu $t4, $t4, 0x0000   (0x258c0000)
         * 0x800330C8: lui   $v1, 0x800B        (0x3c03800b)
         * 0x800330CC: addiu $v1, $v1, 0x0000   (0x24630000) */
        r2_write_ram_u32(ram, 0x0002F3E4u, 0x3c11800bu);
        r2_write_ram_u32(ram, 0x0002F3E8u, 0x26310000u);
        r2_write_ram_u32(ram, 0x00033030u, 0x3c0c800bu);
        r2_write_ram_u32(ram, 0x00033034u, 0x258c0000u);
        r2_write_ram_u32(ram, 0x000330C8u, 0x3c03800bu);
        r2_write_ram_u32(ram, 0x000330CCu, 0x24630000u);

        /* Mark code ranges dirty/executable in interpreter */
        dirty_ram_mark_executable_range(0x0002F000u, 0x6000u);
        s_r2_patches_applied++;
        fprintf(stdout, "[psxrecomp R2] Successfully patched race overlay: actor memory relocated to 0x%08X/0x%08X, loop bounds expanded to %d racers\n",
                RELOCATED_RACER_PTRS_ADDR, RELOCATED_RACERS_ADDR, EXPANDED_RACER_COUNT);
        fflush(stdout);
    }

    /* 3. Check for 2-player overlay ROAD2.EXE / SNOW2.EXE / NIGHT2.EXE
     * Signature: 0x800349D4 has slti $v0, $t0, 10 (0x2902000a) */
    if (r2_read_ram_u32(ram, 0x000349D4u) == 0x2902000au) {
        r2_write_ram_u32(ram, 0x000349D4u, 0x29020010u);
        dirty_ram_mark_executable_range(0x00034000u, 0x2000u);
        s_r2_patches_applied++;
        fprintf(stdout, "[psxrecomp R2] Successfully patched 2P race overlay loop bound at 0x800349D4 to %d racers\n",
                EXPANDED_RACER_COUNT);
        fflush(stdout);
    }
}

/* Helper to resolve target executable name and ID from configuration */
static const char* resolve_target_exe(const DirectTrackConfig* cfg, uint8_t* out_exe_id) {
    if (cfg->track_num == TRACK_NUM_BONUS) {
        if (cfg->course_id == TRACK_COURSE_JAPAN) {
            *out_exe_id = (cfg->num_players == 2) ? 11 : 10;
            return (cfg->num_players == 2) ? "cdrom:\\SNOWB2.EXE;1" : "cdrom:\\SNOWB.EXE;1";
        } else {
            *out_exe_id = (cfg->num_players == 2) ? 9 : 8;
            return (cfg->num_players == 2) ? "cdrom:\\ROADB2.EXE;1" : "cdrom:\\ROADB.EXE;1";
        }
    }

    if (cfg->course_id == TRACK_COURSE_JAPAN) {
        *out_exe_id = (cfg->num_players == 2) ? 5 : 2;
        return (cfg->num_players == 2) ? "cdrom:\\SNOW2.EXE;1" : "cdrom:\\SNOW.EXE;1";
    } else if (cfg->course_id == TRACK_COURSE_LAS_VEGAS) {
        *out_exe_id = (cfg->num_players == 2) ? 6 : 3;
        return (cfg->num_players == 2) ? "cdrom:\\NIGHT2.EXE;1" : "cdrom:\\NIGHT.EXE;1";
    } else {
        /* Africa or Los Angeles */
        *out_exe_id = (cfg->num_players == 2) ? 4 : 1;
        return (cfg->num_players == 2) ? "cdrom:\\ROAD2.EXE;1" : "cdrom:\\ROAD.EXE;1";
    }
}

/* Intercept SCUS_945.08 boot in RAM and redirect straight to race overlay */
static void apply_direct_track_boot_hook(uint8_t *ram) {
    if (!s_direct_track.enabled) return;

    uint8_t exe_id = 1;
    const char *exe_path = resolve_target_exe(&s_direct_track, &exe_id);

    /* Overwrite target executable path string at 0x80010CFC */
    strncpy((char *)(ram + SCUS_EXE_STRING_ADDR), exe_path, 32);

    if (!s_direct_boot_applied) {
        s_direct_boot_applied = true;
        fprintf(stdout, "[psxrecomp DirectTrack] Boot bypassed to %s (Course=%d, Track=%d, Players=%d, Skater=%d)\n",
                exe_path, s_direct_track.course_id, s_direct_track.track_num, s_direct_track.num_players, s_direct_track.skater_id);
        fflush(stdout);
    }

    /* Continuously maintain Master Game State at 0x80010000 */
    ram[MASTER_GAME_STATE_ADDR + MGS_OFFSET_NUM_PLAYERS] = (s_direct_track.num_players == 2) ? 0 : 1;
    ram[MASTER_GAME_STATE_ADDR + MGS_OFFSET_SKATER_ID]   = (uint8_t)s_direct_track.skater_id;
    ram[MASTER_GAME_STATE_ADDR + MGS_OFFSET_COURSE_ID]   = (uint8_t)s_direct_track.course_id;
    ram[MASTER_GAME_STATE_ADDR + MGS_OFFSET_TRACK_NUM]   = (uint8_t)s_direct_track.track_num;
    ram[MASTER_GAME_STATE_ADDR + MGS_OFFSET_DEMO_FLAG]   = 0; /* Live race */
    ram[MASTER_GAME_STATE_ADDR + MGS_OFFSET_OVERLAY_ID]  = exe_id;

    /* Patch SCUS_945.08 instructions in RAM */
    r2_write_ram_u32(ram, 0x00011768u, 0x00000000u);
    r2_write_ram_u32(ram, 0x00011A94u, 0x03e00008u);
    r2_write_ram_u32(ram, 0x00011A98u, 0x00000000u);
    r2_write_ram_u32(ram, SCUS_WAIT_LOOP_ADDR, 0x28020000u);
    r2_write_ram_u32(ram, SCUS_FMV_CALL_ADDR, 0x00000000u);
    r2_write_ram_u32(ram, SCUS_LOGO_CALL_ADDR, 0x00000000u);
    r2_write_ram_u32(ram, SCUS_LOGO_JAL_ADDR, 0x00000000u);

    dirty_ram_mark_executable_range(0x00011600u, 0x600u);
    dirty_ram_mark_executable_range(0x00011800u, 0x400u);
}

void psx_2xtreme_direct_track_apply_sync(void) {
    if (!s_direct_track.enabled) return;
    uint8_t *ram = memory_get_ram_ptr();
    if (ram != NULL) {
        apply_direct_track_boot_hook(ram);
    }
}

/* Check environment variables for direct track configuration */
static void psx_2xtreme_check_env(void) {
    const char *track_env = getenv("2XTREME_DIRECT_TRACK");
    if (track_env && *track_env) {
        psx_2xtreme_parse_direct_track_arg(track_env);
    }
    const char *players_env = getenv("2XTREME_DIRECT_PLAYERS");
    if (players_env && *players_env) {
        int p = atoi(players_env);
        if (p == 1 || p == 2) {
            s_direct_track.num_players = p;
        }
    }
    const char *skater_env = getenv("2XTREME_DIRECT_SKATER");
    if (skater_env && *skater_env) {
        int s = atoi(skater_env);
        if (s >= 0 && s <= 15) {
            s_direct_track.skater_id = s;
        }
    }
}

/* Background watcher thread */
static void *r2_watcher_thread(void *arg) {
    (void)arg;
    while (s_r2_running) {
        uint8_t *ram = memory_get_ram_ptr();
        if (ram != NULL) {
            apply_direct_track_boot_hook(ram);
            if (s_direct_track.enabled) {
                uint8_t exe_id = 1;
                resolve_target_exe(&s_direct_track, &exe_id);
                ram[MASTER_GAME_STATE_ADDR + MGS_OFFSET_NUM_PLAYERS] = (s_direct_track.num_players == 2) ? 0 : 1;
                ram[MASTER_GAME_STATE_ADDR + MGS_OFFSET_SKATER_ID]   = (uint8_t)s_direct_track.skater_id;
                ram[MASTER_GAME_STATE_ADDR + MGS_OFFSET_COURSE_ID]   = (uint8_t)s_direct_track.course_id;
                ram[MASTER_GAME_STATE_ADDR + MGS_OFFSET_TRACK_NUM]   = (uint8_t)s_direct_track.track_num;
                ram[MASTER_GAME_STATE_ADDR + MGS_OFFSET_DEMO_FLAG]   = 0;
                ram[MASTER_GAME_STATE_ADDR + MGS_OFFSET_OVERLAY_ID]  = exe_id;
            }
            if (s_r2_racers_opted_in) {
                r2_apply_patches(ram);
            }
        }
        usleep(500); /* 0.5 ms sleep = ~33 checks per frame */
    }
    return NULL;
}

static void r2_cleanup(void) {
    s_r2_running = false;
    if (s_r2_thread) {
        pthread_join(s_r2_thread, NULL);
    }
}

/* Experimental features are off by default (docs/PRODUCT_RULES.md §8).
 * Developers opt in to the 16-racer expansion with 2XTREME_DEV_RACERS=1.
 * The watcher thread only runs when an experiment needs it. */
static void r2_start_watcher(void) {
    if (s_r2_running) return;
    s_r2_running = true;
    if (pthread_create(&s_r2_thread, NULL, r2_watcher_thread, NULL) == 0) {
        atexit(r2_cleanup);
    } else {
        s_r2_running = false;
    }
}

static void r2_init_runtime_hook(void) {
    if (s_r2_initialized) return;
    s_r2_initialized = true;
    const char *racers_env = getenv("2XTREME_DEV_RACERS");
    s_r2_racers_opted_in = racers_env && strcmp(racers_env, "1") == 0;
    psx_2xtreme_check_env();
    if (s_r2_racers_opted_in || s_direct_track.enabled) {
        r2_start_watcher();
    }
}

void psx_direct_boot_race_track(int course_id, int track_num, int skater_id) {
    pthread_mutex_lock(&s_direct_track_mutex);
    s_direct_track.enabled = true;
    s_direct_track.course_id = (course_id >= 0 && course_id <= 3) ? course_id : TRACK_COURSE_AFRICA;
    s_direct_track.track_num = (track_num >= 0 && track_num <= 3) ? track_num : TRACK_NUM_1;
    s_direct_track.skater_id = (skater_id >= 0 && skater_id <= 15) ? skater_id : 0;
    if (s_direct_track.num_players < 1 || s_direct_track.num_players > 2) {
        s_direct_track.num_players = 1;
    }

    uint8_t *ram = memory_get_ram_ptr();
    if (ram != NULL) {
        uint8_t exe_id = 1;
        resolve_target_exe(&s_direct_track, &exe_id);

        /* Connect to the shared 2,544-byte state block at 0x80010000 */
        ram[MASTER_GAME_STATE_ADDR + MGS_OFFSET_NUM_PLAYERS] = (s_direct_track.num_players == 2) ? 0 : 1;
        ram[MASTER_GAME_STATE_ADDR + MGS_OFFSET_SKATER_ID]   = (uint8_t)s_direct_track.skater_id;
        ram[MASTER_GAME_STATE_ADDR + MGS_OFFSET_COURSE_ID]   = (uint8_t)s_direct_track.course_id;
        ram[MASTER_GAME_STATE_ADDR + MGS_OFFSET_TRACK_NUM]   = (uint8_t)s_direct_track.track_num;
        ram[MASTER_GAME_STATE_ADDR + MGS_OFFSET_DEMO_FLAG]   = 0;
        ram[MASTER_GAME_STATE_ADDR + MGS_OFFSET_OVERLAY_ID]  = exe_id;

        apply_direct_track_boot_hook(ram);
    }
    pthread_mutex_unlock(&s_direct_track_mutex);
    r2_start_watcher();
}

void psx_2xtreme_set_direct_track(const DirectTrackConfig* cfg) {
    if (!cfg) return;
    pthread_mutex_lock(&s_direct_track_mutex);
    s_direct_track = *cfg;
    if (s_direct_track.enabled) {
        uint8_t *ram = memory_get_ram_ptr();
        if (ram != NULL) {
            uint8_t exe_id = 1;
            resolve_target_exe(&s_direct_track, &exe_id);
            ram[MASTER_GAME_STATE_ADDR + MGS_OFFSET_NUM_PLAYERS] = (s_direct_track.num_players == 2) ? 0 : 1;
            ram[MASTER_GAME_STATE_ADDR + MGS_OFFSET_SKATER_ID]   = (uint8_t)s_direct_track.skater_id;
            ram[MASTER_GAME_STATE_ADDR + MGS_OFFSET_COURSE_ID]   = (uint8_t)s_direct_track.course_id;
            ram[MASTER_GAME_STATE_ADDR + MGS_OFFSET_TRACK_NUM]   = (uint8_t)s_direct_track.track_num;
            ram[MASTER_GAME_STATE_ADDR + MGS_OFFSET_DEMO_FLAG]   = 0;
            ram[MASTER_GAME_STATE_ADDR + MGS_OFFSET_OVERLAY_ID]  = exe_id;
            apply_direct_track_boot_hook(ram);
        }
    }
    pthread_mutex_unlock(&s_direct_track_mutex);
}

const DirectTrackConfig* psx_2xtreme_get_direct_track(void) {
    return &s_direct_track;
}

bool psx_2xtreme_parse_direct_track_arg(const char* track_name) {
    if (!track_name || !*track_name) return false;

    int course_id = -1;
    int track_num = 0;

    if (strcasecmp(track_name, "africa") == 0 || strcasecmp(track_name, "africa1") == 0 ||
        strcasecmp(track_name, "af") == 0 || strcasecmp(track_name, "af1") == 0) {
        course_id = TRACK_COURSE_AFRICA;
        track_num = TRACK_NUM_1;
    } else if (strcasecmp(track_name, "africa2") == 0 || strcasecmp(track_name, "af2") == 0) {
        course_id = TRACK_COURSE_AFRICA;
        track_num = TRACK_NUM_2;
    } else if (strcasecmp(track_name, "africa3") == 0 || strcasecmp(track_name, "af3") == 0) {
        course_id = TRACK_COURSE_AFRICA;
        track_num = TRACK_NUM_3;
    } else if (strcasecmp(track_name, "afb") == 0 || strcasecmp(track_name, "af_bonus") == 0 ||
               strcasecmp(track_name, "africa_bonus") == 0) {
        course_id = TRACK_COURSE_AFRICA;
        track_num = TRACK_NUM_BONUS;
    } else if (strcasecmp(track_name, "japan") == 0 || strcasecmp(track_name, "japan1") == 0 ||
               strcasecmp(track_name, "jp") == 0 || strcasecmp(track_name, "jp1") == 0 ||
               strcasecmp(track_name, "ja") == 0 || strcasecmp(track_name, "ja1") == 0) {
        course_id = TRACK_COURSE_JAPAN;
        track_num = TRACK_NUM_1;
    } else if (strcasecmp(track_name, "japan2") == 0 || strcasecmp(track_name, "jp2") == 0 ||
               strcasecmp(track_name, "ja2") == 0) {
        course_id = TRACK_COURSE_JAPAN;
        track_num = TRACK_NUM_2;
    } else if (strcasecmp(track_name, "japan3") == 0 || strcasecmp(track_name, "jp3") == 0 ||
               strcasecmp(track_name, "ja3") == 0) {
        course_id = TRACK_COURSE_JAPAN;
        track_num = TRACK_NUM_3;
    } else if (strcasecmp(track_name, "jpb") == 0 || strcasecmp(track_name, "jp_bonus") == 0 ||
               strcasecmp(track_name, "japan_bonus") == 0) {
        course_id = TRACK_COURSE_JAPAN;
        track_num = TRACK_NUM_BONUS;
    } else if (strcasecmp(track_name, "vegas") == 0 || strcasecmp(track_name, "vegas1") == 0 ||
               strcasecmp(track_name, "lv") == 0 || strcasecmp(track_name, "lv1") == 0 ||
               strcasecmp(track_name, "las_vegas") == 0 || strcasecmp(track_name, "lasvegas") == 0 ||
               strcasecmp(track_name, "las_vegas1") == 0 || strcasecmp(track_name, "lasvegas1") == 0) {
        course_id = TRACK_COURSE_LAS_VEGAS;
        track_num = TRACK_NUM_1;
    } else if (strcasecmp(track_name, "vegas2") == 0 || strcasecmp(track_name, "lv2") == 0 ||
               strcasecmp(track_name, "las_vegas2") == 0 || strcasecmp(track_name, "lasvegas2") == 0) {
        course_id = TRACK_COURSE_LAS_VEGAS;
        track_num = TRACK_NUM_2;
    } else if (strcasecmp(track_name, "vegas3") == 0 || strcasecmp(track_name, "lv3") == 0 ||
               strcasecmp(track_name, "las_vegas3") == 0 || strcasecmp(track_name, "lasvegas3") == 0) {
        course_id = TRACK_COURSE_LAS_VEGAS;
        track_num = TRACK_NUM_3;
    } else if (strcasecmp(track_name, "lvb") == 0 || strcasecmp(track_name, "lv_bonus") == 0 ||
               strcasecmp(track_name, "vegas_bonus") == 0) {
        course_id = TRACK_COURSE_LAS_VEGAS;
        track_num = TRACK_NUM_BONUS;
    } else if (strcasecmp(track_name, "la") == 0 || strcasecmp(track_name, "la1") == 0 ||
               strcasecmp(track_name, "los_angeles") == 0 || strcasecmp(track_name, "losangeles") == 0 ||
               strcasecmp(track_name, "los_angeles1") == 0 || strcasecmp(track_name, "losangeles1") == 0) {
        course_id = TRACK_COURSE_LOS_ANGELES;
        track_num = TRACK_NUM_1;
    } else if (strcasecmp(track_name, "la2") == 0 || strcasecmp(track_name, "los_angeles2") == 0 ||
               strcasecmp(track_name, "losangeles2") == 0) {
        course_id = TRACK_COURSE_LOS_ANGELES;
        track_num = TRACK_NUM_2;
    } else if (strcasecmp(track_name, "la3") == 0 || strcasecmp(track_name, "los_angeles3") == 0 ||
               strcasecmp(track_name, "losangeles3") == 0) {
        course_id = TRACK_COURSE_LOS_ANGELES;
        track_num = TRACK_NUM_3;
    } else if (strcasecmp(track_name, "lab") == 0 || strcasecmp(track_name, "la_bonus") == 0 ||
               strcasecmp(track_name, "los_angeles_bonus") == 0) {
        course_id = TRACK_COURSE_LOS_ANGELES;
        track_num = TRACK_NUM_BONUS;
    } else if (strcmp(track_name, "0") == 0) {
        course_id = TRACK_COURSE_LOS_ANGELES;
        track_num = TRACK_NUM_1;
    } else if (strcmp(track_name, "1") == 0) {
        course_id = TRACK_COURSE_LAS_VEGAS;
        track_num = TRACK_NUM_1;
    } else if (strcmp(track_name, "2") == 0) {
        course_id = TRACK_COURSE_AFRICA;
        track_num = TRACK_NUM_1;
    } else if (strcmp(track_name, "3") == 0) {
        course_id = TRACK_COURSE_JAPAN;
        track_num = TRACK_NUM_1;
    }

    if (course_id < 0) {
        fprintf(stderr, "[psxrecomp DirectTrack] Unknown track name '%s'. Supported: africa, japan, vegas, la (or with 1..3)\n",
                track_name);
        return false;
    }

    psx_direct_boot_race_track(course_id, track_num, s_direct_track.skater_id);
    return true;
}

/* Run hook via GCC/Clang constructor */
static void r2_constructor(void) __attribute__((constructor));
static void r2_constructor(void) {
    r2_init_runtime_hook();
}

static const PsxrecompCodegenHostConfig kCodegenConfig = {
    .display_name = "2Xtreme",
    .project_root_env = "2XTREME_PROJECT_ROOT",
    .build_dir_env = "2XTREME_BUILD_DIR",
    .force_setup_env = "2XTREME_FORCE_SETUP",
    .psxrecomp_cli_relpath = "psxrecomp/psxrecomp_cli.py",
    .seed_cfg_relpath = "game.toml",
    .game_toml_relpath = "game.toml",
    .gen_marker_relpath = "generated/SCUS_945.08_dispatch.c",
    .build_dir_name = "build-release",
    .cmake_target = "psx-runtime",
    .exe_basename = "2Xtreme",
    .prepare_note =
        "Uses your legal disc with the local psxrecomp SDK to generate "
        "BIOS + game C, then cmake --build. The product lives under "
        "build-release/; reopening this setup exe forwards there.",
    .prepare_note_windows =
        "Uses your legal disc with the local psxrecomp SDK to generate "
        "BIOS + game C, then quits and rebuilds via a helper. Afterward, "
        "this setup exe forwards to build-release/ (bios, mods, settings).",
    .prepare_note_no_cmake =
        "Uses your legal disc with the local psxrecomp SDK to generate "
        "BIOS + game C. Rebuild into build-release/, then relaunch this "
        "setup exe (it forwards to the product build).",
};

void psx_game_codegen_setup_apply(RecompLauncherCGameInfo* gi) {
    psxrecomp_codegen_host_apply(gi, &kCodegenConfig);
}

void psx_game_codegen_relaunch_or_exit(const char* disc_path) {
    psxrecomp_codegen_host_relaunch_or_exit(disc_path);
}

void psx_game_codegen_forward_if_built(int argc, char** argv) {
    r2_init_runtime_hook();
    psxrecomp_codegen_host_forward_if_built(&kCodegenConfig, argc, argv);
}
