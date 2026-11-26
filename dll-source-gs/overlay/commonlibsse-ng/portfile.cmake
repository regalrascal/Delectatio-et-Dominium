# Overlay port for commonlibsse-ng — builds from the local submodule
# via file:// URI, bypassing the colorglass registry's prebuilt binaries
# which are compiled against an older MSVC STL ABI.
# Pinned to 1f0aa6e28 (v16.2.0) — matches fork submodule commit.
# REV-185: bumped from f865d990f (v4.26.0) because v4.26.0 predates the
# 1.7.104 runtime entirely (upstream learned RUNTIME_SSE_1_7_99/1_7_104 in
# v8.4.0, commit d470c02dc "Bump game version", 2026-08-28); a user report
# confirmed our DLLs misbehave on 1.7.104 built against the old headers.
#
# NOTE: The v143 toolset is forced by the overlay triplet
# (overlay/x64-windows-static-md.cmake), NOT here — VCPKG_PLATFORM_TOOLSET
# is a triplet-level variable and has no effect in portfile context.

set(VCPKG_BUILD_TYPE release)

# REV-185: CommonLibSSE-NG v16.2.0 vendors MinHook's hde64 decoder (3-file
# instruction-length decoder, SKSE_SUPPORT_PATCH_SAFETY) via FetchContent from
# github.com/TsudaKageyu/minhook.git tag v1.3.4 (commit c3fcafd). vcpkg sets
# FETCHCONTENT_FULLY_DISCONNECTED, which blocks the git download -- fetch it
# here instead and override the source dir so NG's FetchContent_MakeAvailable
# is a no-op populate.
vcpkg_from_git(
    OUT_SOURCE_PATH HDE64_SOURCE_PATH
    URL https://github.com/TsudaKageyu/minhook.git
    REF c3fcafdc10146beb5919319d0683e44e3c30d537
)

vcpkg_from_git(
    OUT_SOURCE_PATH SOURCE_PATH
    URL file://${CMAKE_CURRENT_LIST_DIR}/../../../dll-source/external/commonlibsse-ng
    REF 1f0aa6e28d3bb857ac0a2b1ac01701f6690d2a5f
)

# VR (DeD S293, VR workstream V1): vcpkg_from_git does not fetch submodules, so the OpenVR SDK
# (extern/openvr, needed for ENABLE_SKYRIM_VR) is missing from SOURCE_PATH. Copy its headers and
# win64 import lib from the same local checkout - the copy the Baka DLL build already uses. No
# download. The plugins never call OpenVR, so no shipped DLL imports openvr_api.dll.
set(DED_OPENVR_DIR "${CMAKE_CURRENT_LIST_DIR}/../../../dll-source/external/commonlibsse-ng/extern/openvr")
if(NOT EXISTS "${DED_OPENVR_DIR}/headers/openvr.h" OR NOT EXISTS "${DED_OPENVR_DIR}/lib/win64/openvr_api.lib")
    message(FATAL_ERROR "OpenVR SDK not found at ${DED_OPENVR_DIR} (init the dll-source commonlibsse-ng submodule recursively)")
endif()
file(COPY "${DED_OPENVR_DIR}/headers" DESTINATION "${SOURCE_PATH}/extern/openvr")
file(COPY "${DED_OPENVR_DIR}/lib/win64" DESTINATION "${SOURCE_PATH}/extern/openvr/lib")

# NOTE: CommonLibSSE-NG uses ENABLE_SKYRIM_* (not SKYRIM*).
# One DLL serves SE, AE and VR (runtime picked at load; addresses via Address Library /
# VR Address Library). VR was OFF from REV-185 until S293 only because the OpenVR SDK was
# not fetched; it is copied in above.
vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        -DFETCHCONTENT_SOURCE_DIR_HDE64=${HDE64_SOURCE_PATH}
        -DENABLE_SKYRIM_VR=ON
        -DENABLE_SKYRIM_SE=ON
        -DENABLE_SKYRIM_AE=ON
        -DBUILD_TESTS=OFF
)

vcpkg_cmake_install()

# CommonLibSSE-NG installs config files to lib/cmake/CommonLibSSE/ (cmake project name,
# not vcpkg port name). vcpkg_cmake_config_fixup relocates them to the share/ layout
# expected by find_package under the port's name.
vcpkg_cmake_config_fixup(CONFIG_PATH lib/cmake/CommonLibSSE
    DO_NOT_DELETE_PARENT_CONFIG_PATH)

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")

# CommonLibSSE-targets.cmake lists Microsoft::DirectXTK in
# INTERFACE_LINK_LIBRARIES, but the upstream CommonLibSSEConfig.cmake does
# NOT call find_dependency(directxtk). Add it so find_package(CommonLibSSE)
# in consumer projects resolves DirectXTK automatically.
file(READ "${CURRENT_PACKAGES_DIR}/share/commonlibsse-ng/CommonLibSSEConfig.cmake" _cfg)
string(REPLACE
    "find_dependency(spdlog CONFIG)"
    "find_dependency(spdlog CONFIG)\nfind_dependency(directxtk CONFIG)"
    _cfg "${_cfg}")
file(WRITE "${CURRENT_PACKAGES_DIR}/share/commonlibsse-ng/CommonLibSSEConfig.cmake" "${_cfg}")
unset(_cfg)

# CommonLibSSEConfig.cmake includes() CommonLibSSE.cmake (defines the
# add_commonlibsse_plugin macro consumed by dll-source-gs's CMakeLists.txt).
# The upstream install rules do not copy this file; we install it manually.
file(INSTALL "${SOURCE_PATH}/cmake/CommonLibSSE.cmake"
    DESTINATION "${CURRENT_PACKAGES_DIR}/share/commonlibsse-ng")

# REV-185: v16.2.0 moved LICENSE -> licenses/ (LICENSE-MIT.txt + LICENSE-hde64.txt)
vcpkg_install_copyright(FILE_LIST
    "${SOURCE_PATH}/licenses/LICENSE-MIT.txt"
    "${SOURCE_PATH}/licenses/LICENSE-hde64.txt")