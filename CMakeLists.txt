cmake_minimum_required(VERSION 3.20)
set(PSXRECOMP_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/psxrecomp" CACHE PATH
    "Path to psxrecomp")
if(NOT EXISTS "${PSXRECOMP_ROOT}/runtime/runtime.cmake")
    message(FATAL_ERROR
        "PSXRecomp runtime is missing: ${PSXRECOMP_ROOT}/runtime/runtime.cmake\n"
        "This project expects the psxrecomp framework checkout at ${PSXRECOMP_ROOT}.\n"
        "Run: git submodule update --init --recursive\n"
        "If psxrecomp/ is not a submodule, set -DPSXRECOMP_ROOT=<path-to-psxrecomp>.")
endif()

project(2Xtreme LANGUAGES C CXX)

# --- Opt-in product surfaces (OFF by default in the framework) -------------
# Scaffold prompts / flags fill these. Without recomp-ui, PSX_RECOMP_UI is OFF.
# The wizard (WIZARD_CMAKE_BLOCK / ENABLE_SETUP_WIZARD) is the first-run disc
# picker; releases are compiled from the committed generated/ C, so it never
# needs to generate or rebuild anything on a player's machine.
# recomp-ui submodule present (PSX_RECOMP_UI defaults ON).
# Full netplay UI — enable after adding recomp-ui + testing:
# if(EXISTS "${PSXRECOMP_ROOT}/lib/recomp-net/CMakeLists.txt")
#     set(PSX_NETPLAY ON CACHE BOOL "…" FORCE)
# endif()
set(PSX_SETUP_WIZARD ON CACHE BOOL
    "Advertise first-run setup wizard + Generate & rebuild in recomp-ui" FORCE)
include("${PSXRECOMP_ROOT}/runtime/runtime.cmake")

# This project's own mod catalog. The FRAMEWORK stages it -- together with its
# builtin psx.* packages -- into <exe-dir>/mods/bundled, and refuses to
# configure if a catalog exists here but is not declared. Never copy it by
# hand: five titles did, and framework 4cc04be3's rename of the staged
# directory broke all five silently (bead beads-eio.3.101).
set(PSX_PRELOADED_MODS "${CMAKE_CURRENT_SOURCE_DIR}/mods/preloaded")
if(NOT IS_DIRECTORY "${PSX_PRELOADED_MODS}")
    set(PSX_PRELOADED_MODS "NONE")
endif()

psxrecomp_add_game_runtime(psx-runtime
    PRELOADED_MODS_DIR "${PSX_PRELOADED_MODS}"
    # ENABLE_NETPLAY_IF_PRESENT
    # NETPLAY_LOBBY_URL "ws://netplay.retcomm.net:8765"
    ENABLE_SETUP_WIZARD
    PGXP
    WINDOW_TITLE "2Xtreme"
    DEFAULT_GAME_CONFIG_PATH "game.toml"
    MAX_PLAYERS 2
    # LAUNCHER_BOXART "${CMAKE_CURRENT_SOURCE_DIR}/launcher_assets/img/boxart.tga"
    APP_ICON "${CMAKE_CURRENT_SOURCE_DIR}/assets/psxrecomp.ico"
    # Committed game C (psxrecomp_cli.py generate; git add generated). Release
    # CI configures with -DPSXRECOMP_REQUIRE_GAME_C=ON so a checkout without
    # it fails instead of building a setup host.
    GEN_MARKER "generated/SCUS_945.08_dispatch.c"
    GEN_FULL_GLOB "generated/SCUS_945.08_full_*.c"
    CODEGEN_SETUP_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/codegen_setup.c"
)

# Stage runtime configs next to the exe for direct build/ launches. Only copy
# files that exist — never fail POST_BUILD when game_options.toml is absent.
foreach(_PSX_RUNTIME_CONFIG game.toml game_options.toml)
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/${_PSX_RUNTIME_CONFIG}")
        add_custom_command(TARGET psx-runtime POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "${CMAKE_CURRENT_SOURCE_DIR}/${_PSX_RUNTIME_CONFIG}"
                "$<TARGET_FILE_DIR:psx-runtime>/${_PSX_RUNTIME_CONFIG}"
            COMMENT "Staging ${_PSX_RUNTIME_CONFIG}"
            VERBATIM)
    endif()
endforeach()

if(APPLE)
    enable_language(OBJC OBJCXX)

    set_target_properties(psx-runtime PROPERTIES
        MACOSX_BUNDLE TRUE
        OUTPUT_NAME "2Xtreme"
        MACOSX_BUNDLE_BUNDLE_NAME "2Xtreme"
        MACOSX_BUNDLE_GUI_IDENTIFIER "com.retcomm.2xtreme"
        MACOSX_BUNDLE_BUNDLE_VERSION "1.0.0"
        MACOSX_BUNDLE_SHORT_VERSION_STRING "1.0.0"
        MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/platform/macos/Info.plist"
    )

    target_sources(psx-runtime PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/platform/macos/mac_menu.mm"
    )

    target_include_directories(psx-runtime PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/platform/macos"
    )

    target_link_libraries(psx-runtime PRIVATE
        "-framework AppKit"
        "-framework Foundation"
        "-framework Cocoa"
    )

    # Stage Resources into 2Xtreme.app/Contents/Resources
    add_custom_command(TARGET psx-runtime POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E make_directory
            "$<TARGET_FILE_DIR:psx-runtime>/../Resources"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_CURRENT_SOURCE_DIR}/assets/psxrecomp.png"
            "$<TARGET_FILE_DIR:psx-runtime>/../Resources/psxrecomp.png"
        COMMENT "Staging macOS bundle resources"
        VERBATIM
    )

    # Stage existing configurations into 2Xtreme.app/Contents/MacOS
    foreach(_CFG_FILE settings.toml disc.cfg bios.cfg input.ini keybinds.ini)
        if(EXISTS "${CMAKE_CURRENT_BINARY_DIR}/${_CFG_FILE}")
            add_custom_command(TARGET psx-runtime POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E copy_if_different
                    "${CMAKE_CURRENT_BINARY_DIR}/${_CFG_FILE}"
                    "$<TARGET_FILE_DIR:psx-runtime>/${_CFG_FILE}"
                COMMENT "Staging ${_CFG_FILE} into app bundle"
                VERBATIM
            )
        endif()
    endforeach()

    if(EXISTS "${CMAKE_CURRENT_BINARY_DIR}/mods/state.toml")
        add_custom_command(TARGET psx-runtime POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E make_directory
                "$<TARGET_FILE_DIR:psx-runtime>/mods"
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "${CMAKE_CURRENT_BINARY_DIR}/mods/state.toml"
                "$<TARGET_FILE_DIR:psx-runtime>/mods/state.toml"
            COMMENT "Staging mods/state.toml into app bundle"
            VERBATIM
        )
    endif()

    if(EXISTS "${CMAKE_CURRENT_BINARY_DIR}/mods/texture-packs")
        add_custom_command(TARGET psx-runtime POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E make_directory
                "$<TARGET_FILE_DIR:psx-runtime>/mods"
            COMMAND ${CMAKE_COMMAND} -E copy_directory
                "${CMAKE_CURRENT_BINARY_DIR}/mods/texture-packs"
                "$<TARGET_FILE_DIR:psx-runtime>/mods/texture-packs"
            COMMENT "Staging texture packs into app bundle"
            VERBATIM
        )
    endif()

    # Create compatibility symlink build-release/_2Xtreme -> 2Xtreme.app/Contents/MacOS/2Xtreme
    add_custom_command(TARGET psx-runtime POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E create_symlink
            "2Xtreme.app/Contents/MacOS/2Xtreme"
            "${CMAKE_CURRENT_BINARY_DIR}/_2Xtreme"
        COMMENT "Creating _2Xtreme compatibility symlink to 2Xtreme.app/Contents/MacOS/2Xtreme"
        VERBATIM
    )
endif()
