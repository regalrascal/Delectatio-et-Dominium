cmake_minimum_required(VERSION 3.21)
project(DeDService VERSION 1.0.0 LANGUAGES CXX)

# : framework service DLL (docs/features/service-dll.md spec of record).
# Third chain: sibling of dll-source / dll-source-gs, same overlay toolchain.

find_package(CommonLibSSE CONFIG REQUIRED)

add_commonlibsse_plugin(${PROJECT_NAME}
    SOURCES
        src/Plugin.cpp
        src/PapyrusBinding.cpp
        src/ServiceState.cpp
        src/Scheduler.cpp
        src/EventPump.cpp
)

target_compile_features(${PROJECT_NAME} PRIVATE cxx_std_23)
target_precompile_headers(${PROJECT_NAME} PRIVATE src/PCH.h)

# Dynamic CRT (/MD) + static libs — matches the x64-windows-static-md vcpkg triplet
# (see CMakePresets.json; same ABI rationale as dll-source-gs).
set_property(TARGET ${PROJECT_NAME} PROPERTY
    MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL")

target_include_directories(${PROJECT_NAME} PRIVATE include src)
