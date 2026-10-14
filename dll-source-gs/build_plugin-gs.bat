@echo off
setlocal

REM  WARNING (FILE_STRUCTURE.md): the 2026-09-30 repo migration (path 1b^>1a)
REM left stale CMake caches in this build tree (CMakeCache.txt, cmake_install.cmake,
REM compile_commands.json still point at the OLD BKA workspace path). The NEXT clean
REM build of BOTH DLLs requires, from the repo root, BEFORE configuring:
REM   git clean -xdf dll-source/build/ dll-source-gs/build/
REM (or delete both build\release trees manually). Auto-regenerates thereafter.

call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1

REM dll-source-gs reference build: vcvars64 wrapper for cmake --preset release
REM Gate 0 class: build-config only (no source changes).

set SRC=%~dp0
if "%SRC:~-1%"=="\" set SRC=%SRC:~0,-1%
set BUILD=%SRC%\build\release
set CMAKE=C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe

REM VCPKG_OVERLAY_PORTS: replaces the colorglass-registry commonlibsse-ng
REM prebuilt (v3.7.0, compiled with older MSVC STL) with a source build
REM from the local submodule (v4.26.0, compiled with VS 2022 toolchain).
REM This fixes LNK2001: unresolved external symbol __std_replace_copy_2 /
REM __std_regex_transform_primary_char (STL ABI mismatch).
REM
REM VCPKG_OVERLAY_TRIPLETS: forces VS 2022 v143 toolset in vcpkg builds.
REM Without this, vcpkg picks VS 2019 Build Tools (v142), producing
REM CommonLibSSE object files with an STL ABI that conflicts with the
REM plugin link step under MSVC 14.44.
if exist "%SRC%\overlay\commonlibsse-ng\portfile.cmake" (
    set "VCPKG_OVERLAY_PORTS=%SRC%\overlay"
)
if exist "%SRC%\overlay\x64-windows-static-md.cmake" (
    set "VCPKG_OVERLAY_TRIPLETS=%SRC%\overlay"
)

if exist "%BUILD%" rmdir /s /q "%BUILD%"

"%CMAKE%" --preset release --fresh

if %ERRORLEVEL% neq 0 ( echo CONFIGURE FAILED & exit /b 1 )

"%CMAKE%" --build --preset release

if %ERRORLEVEL% neq 0 ( echo BUILD FAILED & exit /b 1 )

echo BUILD SUCCEEDED