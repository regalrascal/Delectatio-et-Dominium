@echo off
REM Incremental rebuild of DeDService (no clean): cmake --build reconfigures itself when CMakeLists changes.
REM Then the companion DeDService.psc compile, as build_plugin-ded.bat does. ASCII.
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
set SRC=%~dp0
if "%SRC:~-1%"=="\" set SRC=%SRC:~0,-1%
set BUILD=%SRC%\build\release
set "VCPKG_OVERLAY_PORTS=%SRC%\overlay"
set "VCPKG_OVERLAY_TRIPLETS=%SRC%\overlay"
"C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" --build --preset release
if %ERRORLEVEL% neq 0 ( echo BUILD FAILED & exit /b 1 )
set CC=D:\Steam\steamapps\common\Skyrim Special Edition\Papyrus Compiler\PapyrusCompiler.exe
set FLAGS=D:\Steam\steamapps\common\Skyrim Special Edition\Data\Source\Scripts\TESV_Papyrus_Flags.flg
for %%A in ("D:\Steam\steamapps\common\Skyrim Special Edition\Data\Source\Scripts") do set VAN=%%~sA
"%CC%" "%SRC%\papyrus\DeDService.psc" -i="%SRC%\papyrus;%VAN%" -o="%BUILD%" -f="%FLAGS%"
if %ERRORLEVEL% neq 0 ( echo PSC COMPILE FAILED & exit /b 1 )
echo BUILD SUCCEEDED