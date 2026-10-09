#include "disc.h"

#include <CommonCrypto/CommonDigest.h>
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>

/* The supported dump, from game.toml [prepare_disc]. */
#define TWOX_DATA_TRACK_SIZE 45715824LL
static const char *kTwoxDataTrackSha1 = "3f25e5d1366e60e70a416109711e109d48c9f19b";

static int ends_with(const char *s, const char *suffix) {
    size_t n = strlen(s), m = strlen(suffix);
    return n >= m && strcasecmp(s + n - m, suffix) == 0;
}

static long long file_size(const char *path) {
    struct stat st;
    return stat(path, &st) == 0 && S_ISREG(st.st_mode) ? (long long)st.st_size : -1;
}

static void dir_of(const char *path, char *out, size_t cap) {
    snprintf(out, cap, "%s", path);
    char *slash = strrchr(out, '/');
    if (slash) *slash = '\0'; else snprintf(out, cap, ".");
}

/* Parse a cue sheet into its FILE entries. Returns 0 on success. */
static TwoxDiscStatus parse_cue(const char *cue, TwoxDisc *out) {
    FILE *f = fopen(cue, "r");
    if (!f) return TWOX_DISC_UNREADABLE;
    char dir[1024];
    dir_of(cue, dir, sizeof(dir));
    char line[2048];
    int track_mode_seen = 0;
    while (fgets(line, sizeof(line), f)) {
        char *p = line;
        while (isspace((unsigned char)*p)) p++;
        if (strncasecmp(p, "FILE", 4) == 0) {
            char *q1 = strchr(p, '"');
            char *q2 = q1 ? strchr(q1 + 1, '"') : NULL;
            if (!q1 || !q2 || out->file_count >= TWOX_MAX_TRACK_FILES) { fclose(f); return TWOX_DISC_UNREADABLE; }
            *q2 = '\0';
            snprintf(out->files[out->file_count++], sizeof(out->files[0]), "%s/%s", dir, q1 + 1);
        } else if (strncasecmp(p, "TRACK", 5) == 0) {
            if (strcasestr(p, "AUDIO")) out->has_audio_tracks = 1;
            if (!track_mode_seen) {
                track_mode_seen = 1;
                out->sector_size = strcasestr(p, "/2048") ? 2048 : 2352;
            }
        }
    }
    fclose(f);
    if (out->file_count == 0) return TWOX_DISC_UNREADABLE;
    for (int i = 0; i < out->file_count; i++)
        if (file_size(out->files[i]) < 0) return TWOX_DISC_MISSING_TRACK;
    snprintf(out->cue_path, sizeof(out->cue_path), "%s", cue);
    snprintf(out->data_path, sizeof(out->data_path), "%s", out->files[0]);
    return TWOX_DISC_OK;
}

/* Look for a .cue in the same folder whose first FILE is this image. */
static int find_sibling_cue(const char *image, char *cue_out, size_t cap) {
    char dir[1024];
    dir_of(image, dir, sizeof(dir));
    const char *base = strrchr(image, '/');
    base = base ? base + 1 : image;
    char cmd_path[1100];
    /* Try the common naming first: "Name (Track 1).bin" -> "Name.cue". */
    char guess[1024];
    snprintf(guess, sizeof(guess), "%s", image);
    char *t = strcasestr(guess, " (Track 1).bin");
    if (t) {
        strcpy(t, ".cue");
        TwoxDisc probe = {0};
        if (parse_cue(guess, &probe) == TWOX_DISC_OK && strcmp(probe.files[0], image) == 0) {
            snprintf(cue_out, cap, "%s", guess);
            return 1;
        }
    }
    snprintf(cmd_path, sizeof(cmd_path), "%s", image);
    t = strrchr(cmd_path, '.');
    if (t) {
        strcpy(t, ".cue");
        TwoxDisc probe = {0};
        if (parse_cue(cmd_path, &probe) == TWOX_DISC_OK && strstr(probe.files[0], base)) {
            snprintf(cue_out, cap, "%s", cmd_path);
            return 1;
        }
    }
    return 0;
}

TwoxDiscStatus twox_disc_resolve(const char *chosen, TwoxDisc *out) {
    memset(out, 0, sizeof(*out));
    if (file_size(chosen) < 0) return TWOX_DISC_UNREADABLE;
    if (ends_with(chosen, ".chd")) return TWOX_DISC_CHD;
    if (ends_with(chosen, ".cue")) return parse_cue(chosen, out);

    if (ends_with(chosen, ".bin") || ends_with(chosen, ".img")) {
        char cue[1024];
        if (find_sibling_cue(chosen, cue, sizeof(cue))) return parse_cue(cue, out);
        out->sector_size = 2352;
    } else if (ends_with(chosen, ".iso")) {
        out->sector_size = 2048;
    } else {
        return TWOX_DISC_UNREADABLE;
    }
    out->file_count = 1;
    snprintf(out->files[0], sizeof(out->files[0]), "%s", chosen);
    snprintf(out->data_path, sizeof(out->data_path), "%s", chosen);
    return TWOX_DISC_OK;
}

TwoxDiscStatus twox_disc_verify(const TwoxDisc *disc) {
    if (disc->sector_size != 2352) return TWOX_DISC_WRONG_GAME;
    if (file_size(disc->data_path) != TWOX_DATA_TRACK_SIZE) return TWOX_DISC_WRONG_GAME;
    FILE *f = fopen(disc->data_path, "rb");
    if (!f) return TWOX_DISC_UNREADABLE;
    CC_SHA1_CTX ctx;
    CC_SHA1_Init(&ctx);
    static unsigned char buf[1 << 20];
    size_t n;
    while ((n = fread(buf, 1, sizeof(buf), f)) > 0) CC_SHA1_Update(&ctx, buf, (CC_LONG)n);
    fclose(f);
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1_Final(digest, &ctx);
    char hex[2 * CC_SHA1_DIGEST_LENGTH + 1];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) snprintf(hex + 2 * i, 3, "%02x", digest[i]);
    return strcmp(hex, kTwoxDataTrackSha1) == 0 ? TWOX_DISC_OK : TWOX_DISC_WRONG_GAME;
}

/* Read one 2048-byte user-data sector (Mode 2 Form 1 data starts at byte 24). */
static int read_sector(FILE *f, int sector_size, uint32_t lba, unsigned char *out) {
    long long off = (long long)lba * sector_size + (sector_size == 2352 ? 24 : 0);
    if (fseeko(f, off, SEEK_SET) != 0) return -1;
    return fread(out, 1, 2048, f) == 2048 ? 0 : -1;
}

static uint32_t le32(const unsigned char *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

int twox_disc_extract(const char *data_path, int sector_size,
                      const char *name, const char *out_path) {
    FILE *f = fopen(data_path, "rb");
    if (!f) return -1;
    unsigned char sec[2048];
    int rc = -1;
    if (read_sector(f, sector_size, 16, sec) != 0 || memcmp(sec + 1, "CD001", 5) != 0) goto done;

    uint32_t dir_lba = le32(sec + 156 + 2), dir_size = le32(sec + 156 + 10);
    size_t want = strlen(name);
    for (uint32_t s = 0; s < (dir_size + 2047) / 2048; s++) {
        if (read_sector(f, sector_size, dir_lba + s, sec) != 0) goto done;
        for (int pos = 0; pos < 2048;) {
            int len = sec[pos];
            if (len == 0) break;
            int name_len = sec[pos + 32];
            const char *rec_name = (const char *)sec + pos + 33;
            if ((size_t)name_len >= want && strncasecmp(rec_name, name, want) == 0 &&
                ((size_t)name_len == want || rec_name[want] == ';')) {
                uint32_t lba = le32(sec + pos + 2), size = le32(sec + pos + 10);
                FILE *o = fopen(out_path, "wb");
                if (!o) goto done;
                unsigned char data[2048];
                uint32_t left = size;
                for (uint32_t i = 0; left > 0; i++) {
                    if (read_sector(f, sector_size, lba + i, data) != 0) { fclose(o); goto done; }
                    uint32_t chunk = left < 2048 ? left : 2048;
                    fwrite(data, 1, chunk, o);
                    left -= chunk;
                }
                fclose(o);
                rc = 0;
                goto done;
            }
            pos += len;
        }
    }
done:
    fclose(f);
    return rc;
}
