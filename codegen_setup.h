#ifndef CODEGEN_SETUP_H
#define CODEGEN_SETUP_H

#include <stdint.h>
#include <stdbool.h>

#if defined(RECOMP_LAUNCHER) && __has_include("recomp_launcher.h")
#include "recomp_launcher.h"
#else
struct RecompLauncherCGameInfo;
typedef struct RecompLauncherCGameInfo RecompLauncherCGameInfo;
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* Course IDs: 0=LA, 1=Vegas, 2=Africa, 3=Japan */
typedef enum {
    TRACK_COURSE_LOS_ANGELES = 0,
    TRACK_COURSE_LAS_VEGAS   = 1,
    TRACK_COURSE_AFRICA      = 2,
    TRACK_COURSE_JAPAN       = 3,
} TrackCourseId;

typedef enum {
    TRACK_NUM_1     = 0,
    TRACK_NUM_2     = 1,
    TRACK_NUM_3     = 2,
    TRACK_NUM_BONUS = 3,
} TrackNumId;

typedef struct {
    bool enabled;
    int course_id;   /* 0=LA, 1=Vegas, 2=Africa, 3=Japan */
    int track_num;   /* 0=Track 1, 1=Track 2, 2=Track 3, 3=Bonus */
    int num_players; /* 1 or 2 */
    int skater_id;   /* 0..15 (default 0) */
} DirectTrackConfig;

void psx_game_codegen_setup_apply(RecompLauncherCGameInfo* gi);
void psx_game_codegen_relaunch_or_exit(const char* disc_path);
void psx_game_codegen_forward_if_built(int argc, char** argv);

/* Milestone 2 (R2): State Machine Direct Boot C Hooks */
void psx_direct_boot_race_track(int course_id, int track_num, int skater_id);
void psx_2xtreme_set_direct_track(const DirectTrackConfig* cfg);
const DirectTrackConfig* psx_2xtreme_get_direct_track(void);
bool psx_2xtreme_parse_direct_track_arg(const char* track_name);
void psx_2xtreme_direct_track_apply_sync(void);

#ifdef __cplusplus
}
#endif

#endif
