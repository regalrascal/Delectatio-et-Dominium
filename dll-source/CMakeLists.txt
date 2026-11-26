cmake_minimum_required(VERSION 3.21)
add_compile_definitions(_WIN32_WINNT=0x0A00)

if(POLICY CMP0135)
    cmake_policy(SET CMP0135 NEW)
endif()

# VCPKG_TARGET_TRIPLET=x64-windows-static (set by build_plugin.bat) builds spdlog/fmt/etc against the
# static CRT (/MT) -- the standard choice for SKSE plugins, so end users don't need a matching VC++
# Redistributable. CMake's own default for our OWN sources is still /MD unless told otherwise, which
# means our object files silently link against a DIFFERENT CRT than vcpkg's static libs -- confirmed
# real build failure: LNK2038 "RuntimeLibrary mismatch" against spdlog.lib/fmt.lib/libcpmt.lib on a
# clean rebuild. CMP0091 must be set NEW before project() for CMAKE_MSVC_RUNTIME_LIBRARY to actually
# take effect.
if(POLICY CMP0091)
    cmake_policy(SET CMP0091 NEW)
endif()
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

project(
    SkyrimNet_BakaIntegration
    VERSION 1.4.1
    LANGUAGES CXX
)

set(PROJECT_OUTPUT_NAME "${PROJECT_NAME}-v${PROJECT_VERSION}")
# No automatic copy of the built DLL (DeD S287). The old default wrote a copy into ../dist/ on every
# build (it tripped the dist hygiene step), and the SKYRIM_MODS_FOLDER branch would have written into
# the MO2 mods folder (DeD ruleset rule 1: the user deploys). The DLL stays in build/release/; the
# release flow copies it into SKSE/Plugins/ with a hash check. Opt-in only: -DOUTPUT_FOLDER=<dir>.

list(APPEND CMAKE_MODULE_PATH "${PROJECT_SOURCE_DIR}/cmake")

set(BUILD_ROOT "${CMAKE_SOURCE_DIR}/build")
set(FETCHCONTENT_BASE_DIR "${BUILD_ROOT}/external_builds")

include(CompilerFlags)
include(commonlibsse)

include_directories(${CMAKE_SOURCE_DIR}/include)
include_directories(${CMAKE_SOURCE_DIR}/src)
include_directories(${CMAKE_SOURCE_DIR}/external/nlohmann/..)   # vendored nlohmann-json 3.12.0 (MIT), S316
# Magelight workstream Phase 1: the DeDService UI host contract (header-only, resolved at runtime).
include_directories(${CMAKE_SOURCE_DIR}/../dll-source-ded/include)

add_commonlibsse_plugin(${PROJECT_NAME}
    SOURCES
    src/Plugin.cpp
    src/DeDPanelClient.cpp
    src/BakaPanel.cpp
    src/SlaveTatsPanel.cpp
    src/SlaveTatsNative.cpp
    src/TattooVision.cpp
    src/PapyrusFunctions.cpp
    src/SkyrimNetBridge.cpp
    src/HitEventSink.cpp
    NAME ${PROJECT_NAME}
    AUTHOR "Dag"
    EMAIL ""
    USE_ADDRESS_LIBRARY
    MINIMUM_SKSE_VERSION "2.0.1.04"
)

target_compile_features(${PROJECT_NAME} PRIVATE cxx_std_23)
target_precompile_headers(${PROJECT_NAME} PRIVATE src/PCH.h)
target_compile_definitions(${PROJECT_NAME} PRIVATE SPDLOG_ACTIVE_LEVEL=SPDLOG_LEVEL_TRACE) # <--- enable all spdlog log levels (including trace)
enable_lto_for_target(${PROJECT_NAME})

target_link_libraries(${PROJECT_NAME} PRIVATE CommonLibSSE::CommonLibSSE)


if(DEFINED OUTPUT_FOLDER)
    set(DLL_FOLDER "${OUTPUT_FOLDER}/SKSE/Plugins")
    message(STATUS "SKSE plugin output folder: ${DLL_FOLDER}")
    add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
        COMMAND "${CMAKE_COMMAND}" -E make_directory "${DLL_FOLDER}"
        COMMAND "${CMAKE_COMMAND}" -E copy_if_different "$<TARGET_FILE:${PROJECT_NAME}>" "${DLL_FOLDER}/$<TARGET_FILE_NAME:${PROJECT_NAME}>"
        COMMAND "${CMAKE_COMMAND}" -E copy_if_different "$<TARGET_PDB_FILE:${PROJECT_NAME}>" "${DLL_FOLDER}/$<TARGET_PDB_FILE_NAME:${PROJECT_NAME}>"
        VERBATIM
    )
else()
    message(STATUS "No OUTPUT_FOLDER given: the built DLL stays in the build folder (no auto-copy).")
endif()
