cmake_minimum_required(VERSION 3.21)
project(DeDDowned VERSION 0.1.0 LANGUAGES CXX)

# DeD Downed module DLL (spec docs/specs/ded-downed-a2-spec.md; A3b leg 2). The engine hooks; all state lives in
# DeDService (dll-source-ded/include/DeDDowned_API.h). Same overlay toolchain as dll-source-ded.

find_package(CommonLibSSE CONFIG REQUIRED)

add_commonlibsse_plugin(${PROJECT_NAME}
    SOURCES
        src/Plugin.cpp
)

target_compile_features(${PROJECT_NAME} PRIVATE cxx_std_23)
target_precompile_headers(${PROJECT_NAME} PRIVATE src/PCH.h)
set_property(TARGET ${PROJECT_NAME} PROPERTY
    MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL")
target_include_directories(${PROJECT_NAME} PRIVATE src ../dll-source-ded/include external/skyrimnet)

find_package(nlohmann_json CONFIG REQUIRED)
target_link_libraries(${PROJECT_NAME} PRIVATE nlohmann_json::nlohmann_json)
