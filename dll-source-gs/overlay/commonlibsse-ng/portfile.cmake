# Overlay port for commonlibsse-ng — builds from the local submodule
# via file:// URI, bypassing the colorglass registry's prebuilt binaries
# which are compiled against an older MSVC STL ABI.
# Pinned to f865d990f (v4.26.0) — matches fork submodule commit.
#
# NOTE: The v143 toolset is forced by the overlay triplet
# (overlay/x64-windows-static-md.cmake), NOT here — VCPKG_PLATFORM_TOOLSET
# is a triplet-level variable and has no effect in portfile context.

set(VCPKG_BUILD_TYPE release)

vcpkg_from_git(
    OUT_SOURCE_PATH SOURCE_PATH
    URL file://${CMAKE_CURRENT_LIST_DIR}/../../../dll-source/external/commonlibsse-ng
    REF f865d990f8d1495a5e9e7fc8a8d2b42c9af5619d
)

# NOTE: CommonLibSSE-NG uses ENABLE_SKYRIM_* (not SKYRIM*).
# SKYRIM_VR requires the OpenVR SDK (submodule at extern/openvr/headers)
# which vcpkg_from_git does not fetch recursively.
# GS plugin is SE/AE only, so VR is safely disabled.
vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        -DENABLE_SKYRIM_VR=OFF
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

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")