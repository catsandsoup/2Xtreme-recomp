/* Disc handling for first-run setup: find the tracks a disc image needs,
 * check it is 2Xtreme (USA), and pull the boot executable out of track 1.
 * Plain C so it is easy to test on its own. */
#ifndef TWOX_DISC_H
#define TWOX_DISC_H

#include <stddef.h>
#include <stdint.h>

#define TWOX_MAX_TRACK_FILES 32

typedef struct {
    char cue_path[1024];            /* empty when the player chose a lone image */
    char data_path[1024];           /* track 1 (the data track) */
    int  sector_size;               /* 2352 (raw .bin) or 2048 (.iso) */
    int  file_count;                /* every file to copy, data track first */
    char files[TWOX_MAX_TRACK_FILES][1024];
    int  has_audio_tracks;
} TwoxDisc;

typedef enum {
    TWOX_DISC_OK = 0,
    TWOX_DISC_UNREADABLE,     /* file missing or not a disc image we read */
    TWOX_DISC_CHD,            /* .chd chosen: not supported yet */
    TWOX_DISC_MISSING_TRACK,  /* the .cue names a file that isn't there */
    TWOX_DISC_WRONG_GAME,     /* readable, but not 2Xtreme (USA) */
} TwoxDiscStatus;

/* Work out which files make up the disc the player chose (.cue, .bin, .iso).
 * A lone track-1 .bin picks up a .cue beside it that references it. */
TwoxDiscStatus twox_disc_resolve(const char *chosen, TwoxDisc *out);

/* Check track 1 is the known 2Xtreme (USA) dump (size + SHA-1). */
TwoxDiscStatus twox_disc_verify(const TwoxDisc *disc);

/* Extract a file from the ISO 9660 filesystem on track 1 (e.g. "SCUS_945.08").
 * Returns 0 on success. */
int twox_disc_extract(const char *data_path, int sector_size,
                      const char *name, const char *out_path);

#endif
