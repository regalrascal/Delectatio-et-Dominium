@echo off
setlocal

REM  WARNING (FILE_STRUCTURE.md): the 2026-09-30 repo migration (path 1b^>1a)
REM left stale CMake caches in this build tree (CMakeCache.txt, cmake_install.cmake,
REM compile_commands.json still point at the OLD BKA workspace path). The NEXT clean
REM build of BOTH DLLs requires, from the repo root, BEFORE configuring:
REM   git clean -xdf dll-source/build/ dll-source-gs/build/
REM (or delete both build\release trees manually). Auto-regenerates thereafter.

call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1

REM Paths are resolved relative to this script's own folder (portable â€” clone anywhere).
set SRC=%~dp0
if "%SRC:~-1%"=="\" set SRC=%SRC:~0,-1%
set BUILD=%SRC%\build\release
set CMAKE=C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe
REM Bare "ninja.exe" relies on PATH resolution, which doesn't reliably pick up the copy VS bundles under
REM CommonExtensions in every shell context (confirmed real build failure: "no such file or directory" on
REM a clean configure despite vcvars64.bat having run) -- pass its full path instead.
set NINJA=C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe

if exist "%BUILD%" rmdir /s /q "%BUILD%"

"%CMAKE%" -B "%BUILD%" -S "%SRC%" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_COMPILER=cl.exe -DCMAKE_MAKE_PROGRAM="%NINJA%" -DCMAKE_TOOLCHAIN_FILE=C:/vcpkg/scripts/buildsystems/vcpkg.cmake -DVCPKG_TARGET_TRIPLET=x64-windows-static -DCMAKE_PREFIX_PATH=C:/vcpkg/installed/x64-windows-static -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF

if %ERRORLEVEL% neq 0 ( echo CONFIGURE FAILED & exit /b 1 )

"%CMAKE%" --build "%BUILD%"

if %ERRORLEVEL% neq 0 ( echo BUILD FAILED & exit /b 1 )

echo BUILD SUCCEEDED
