# Overlay triplet for dll-source-gs: force VS 2022 v143 toolset.
# This prevents vcpkg from auto-detecting VS 2019 Build Tools (which
# produces CommonLibSSE objs with an STL ABI incompatible with the
# final plugin link step under MSVC 14.44).
set(VCPKG_TARGET_ARCHITECTURE x64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_PLATFORM_TOOLSET v143)
set(VCPKG_DISABLE_COMPILER_TRACKING ON)