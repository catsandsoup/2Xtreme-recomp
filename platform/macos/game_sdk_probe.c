/* Stands in for the game's recompiled C when the shipping runtime is built
 * (TWOX_GAME_MODULE_HOST). It holds nothing; it exists so this file is
 * compiled with exactly the flags the game C gets, and tools/macos/make_app.sh
 * records those flags in the app's SDK for the on-device game build. */
typedef int twox_game_sdk_probe;
