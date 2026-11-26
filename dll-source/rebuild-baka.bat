@echo off
REM Incremental rebuild of the Baka DLL (no clean, no reconfigure). ASCII.
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
set SRC=%~dp0
if "%SRC:~-1%"=="\" set SRC=%SRC:~0,-1%
"C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" --build "%SRC%\build\release"
if %ERRORLEVEL% neq 0 ( echo BUILD FAILED & exit /b 1 )
echo BUILD SUCCEEDED
