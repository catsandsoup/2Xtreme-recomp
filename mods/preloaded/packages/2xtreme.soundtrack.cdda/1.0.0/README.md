# 2Xtreme CDDA Soundtrack Replacement

This preloaded mod package configures and enables replacement Redbook CDDA audio tracks (Tracks 02–08) for 2Xtreme (`SCUS-94508`).

## Track Mapping
- **Track 01**: Game Data (MODE2/2352) - unaltered
- **Track 02**: Audio (Track 02.bin / 44.1 kHz 16-bit Stereo PCM) - Main Theme / Title Screen
- **Track 03**: Audio (Track 03.bin / 44.1 kHz 16-bit Stereo PCM) - Japan Track
- **Track 04**: Audio (Track 04.bin / 44.1 kHz 16-bit Stereo PCM) - USA Track
- **Track 05**: Audio (Track 05.bin / 44.1 kHz 16-bit Stereo PCM) - Africa Track
- **Track 06**: Audio (Track 06.bin / 44.1 kHz 16-bit Stereo PCM) - Europe Track
- **Track 07**: Audio (Track 07.bin / 44.1 kHz 16-bit Stereo PCM) - Bonus / Credits Track
- **Track 08**: Audio (Track 08.bin / 44.1 kHz 16-bit Stereo PCM) - Result / Menu Track

## Mounting
The tracks are mapped via `game.toml` multi-track CUE mount (`[game] disc`) and verified through `[netplay]` track count gates (`required_tracks = 8`).
