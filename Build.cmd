@echo off
if not "%platform_echo%" == "" @echo on
setlocal enabledelayedexpansion enableextensions

if "%1"=="/?" goto :usage

set _clean=
set _restore=
set _graph=
set _cache=
rem The /m flag to msbuild.exe controls how many instances of msbuild.exe are spawned.
rem The default of 4 was found to be a reasonable number to ensure good build times
rem without hitting out of memory issues.
set _procCount=/m:4
set _fake=
set _version=3.0.0-dev
set _lowpriority=%XAMLBUILD_LOWPRIORITY%
set _verbosity=/verbosity:minimal
set _quiet=
set _initFlavor=

set "_targetArgs="

:parseArgs
if "%1"=="/c"                  ( set _clean=1
) else if "%1"=="/restore"     ( set _restore=1
) else if "%1" == "/graph"     ( set _graph=1
) else if "%1" == "/cache"     ( set _graph=1 & set _cache=1
) else if "%1"=="/fake"        ( set _fake=1
) else if "%1" == "/lowpri"    ( set _lowpriority=1
) else if "%1" == "/normalpri" ( set _lowpriority=0
rem Quiet mode: suppress informational output, show only errors and elapsed time.
rem Useful for AI agents and CI/CD pipelines.
) else if "%1" == "/q"         ( set _quiet=1 & set _verbosity=/verbosity:quiet
rem Inline init: run init.cmd <flavor> /envcheck before building.
rem Allows building without a persistent shell session (e.g. from AI agents).
) else if "%1" == "/i"         ( set _initFlavor=%2 & shift
rem Normal is still pretty far from full verbosity but it can have more useful details than minimal and is not
rem nearly as verbose as detailed or diagnostic.
) else if "%1" == "/verbose"   ( set _verbosity=/verbosity:normal
) else if "%1"=="/b"           ( set _procCount=/m:2
) else if "%1"=="/m"           ( set _procCount=/m
) else if "%1"=="/version"     ( set _version=%2 & shift
) else if "%1"=="prodtest"     ( set "_targetArgs=%1"
) else if "%1"=="product"      ( set "_targetArgs=%1"
) else if "%1"=="pux"          ( set "_targetArgs=%1"
) else if "%1"=="test"         ( set "_targetArgs=%1"
) else if "%1"==""             ( goto:main
) else rem

shift
goto :parseArgs

:main
set _versionOption=/p:PlatformVersion=%_version%
set BUILDCMDSTARTTIME=%time%
set "_initScriptsDir=%~dp0tools\initScripts"

if not "%_initFlavor%" == "" (
    if "%_quiet%"=="1" (
        call "%_initScriptsDir%\init.cmd" %_initFlavor% /envcheck /notitle >nul
    ) else (
        echo Initializing build environment for %_initFlavor%...
        call "%_initScriptsDir%\init.cmd" %_initFlavor% /envcheck /notitle
    )
    if ERRORLEVEL 1 (
        echo ERROR: init.cmd %_initFlavor% /envcheck failed
        exit /b 1
    )
) else if "%EnvironmentInitialized%" == "" (
    echo Please run init.cmd or use /i ^<flavor^> to initialize the build environment
    exit /b 1
)

if "%_clean%"=="1" (
    call :callScript clean.cmd /all
    set _restore=1
)

call "%ToolsRoot%\buildtargets.cmd" %_targetArgs%
if ERRORLEVEL 2 goto :usage
if ERRORLEVEL 1 goto :showDurationAndExit

if not "%_quiet%"=="1" (
    echo ---
    echo BUILD SUCCEEDED.
)

goto :showDurationAndExit

:callScript
if "%_fake%"=="1" (
    echo COMMAND: %*
    goto :eof
)

call %*

if ERRORLEVEL 1 (
    echo ---
    echo ERROR: callScript FAILED.
)

goto :eof

:showDurationAndExit
set BUILDCMDENDTIME=%time%
:: Note: The '1's in this line are to convert a value like "08" to "108", since numbers which
::       begin with '0' are interpreted as octal, which makes "08" and "09" invalid. Adding the
::       '1's effectively adds 100 to both sides of the subtraction, avoiding this issue.
::       Hours has a leading space instead of 0, so the '1's trick isn't used on that one.
set /a BUILDDURATION_HRS= %BUILDCMDENDTIME:~0,2%- %BUILDCMDSTARTTIME:~0,2%
set /a BUILDDURATION_MIN=1%BUILDCMDENDTIME:~3,2%-1%BUILDCMDSTARTTIME:~3,2%
set /a BUILDDURATION_SEC=1%BUILDCMDENDTIME:~6,2%-1%BUILDCMDSTARTTIME:~6,2%
set /a BUILDDURATION_HSC=1%BUILDCMDENDTIME:~9,2%-1%BUILDCMDSTARTTIME:~9,2%
if %BUILDDURATION_HSC% lss 0 (
    set /a BUILDDURATION_HSC=!BUILDDURATION_HSC!+100
    set /a BUILDDURATION_SEC=!BUILDDURATION_SEC!-1
)
if %BUILDDURATION_SEC% lss 0 (
    set /a BUILDDURATION_SEC=!BUILDDURATION_SEC!+60
    set /a BUILDDURATION_MIN=!BUILDDURATION_MIN!-1
)
if %BUILDDURATION_MIN% lss 0 (
    set /a BUILDDURATION_MIN=!BUILDDURATION_MIN!+60
    set /a BUILDDURATION_HRS=!BUILDDURATION_HRS!-1
)
if %BUILDDURATION_HRS% lss 0 (
    set /a BUILDDURATION_HRS=!BUILDDURATION_HRS!+24
)

:: Add a '0' at the start to ensure at least two digits. The output will then just
:: show the last two digits for each.
set BUILDDURATION_HRS=0%BUILDDURATION_HRS%
set BUILDDURATION_MIN=0%BUILDDURATION_MIN%
set BUILDDURATION_SEC=0%BUILDDURATION_SEC%
set BUILDDURATION_HSC=0%BUILDDURATION_HSC%
if not "%_quiet%"=="1" (
    echo ---
    echo Start time: %BUILDCMDSTARTTIME%. End time: %BUILDCMDENDTIME%
)

echo    Elapsed: %BUILDDURATION_HRS:~-2%:%BUILDDURATION_MIN:~-2%:%BUILDDURATION_SEC:~-2%.%BUILDDURATION_HSC:~-2%
endlocal
goto :eof

:usage
echo Usage:
echo     build.cmd [targets] [options]
echo.
echo    Available targets:
echo        prodtest ^(default^)  Builds product code and tests ^(no samples^)
echo        product             Builds product code only ^(no tests or samples, subset of prodtest^)
echo        pux                 Builds Microsoft.UI.Xaml.dll ^(subset of product^)
echo        test                Builds tests only ^(subset of prodtest^)
echo.
echo    Options:
echo        /q              Quiet mode. Minimal output, only errors are shown. Useful for AI/automation.
echo        /i [flavor]     Initialize build environment inline (e.g. /i amd64chk, /i arm64fre).
echo        /c              Deletes bin, obj, temp, and packaging directories before building.
echo        /restore        Add the Nuget restore option
echo        /graph          Perform graph-based MSBuild scheduling.
echo        /cache          Perform a build with MSBuild project caching. Implies /graph.
echo        /b              Background mode (spawn fewer instances of msbuild.exe; 2 instead of 4).
echo        /m              Passes the /m flag to msbuild.
echo        /fake           Don't actually do the build--just tell me what you're going to build.
echo        /lowpri         Launch MSBuild using below normal priority.
echo        /normalpri      Launch MSBuild using normal priority.
echo        /verbose        Use normal verbosity.
echo        /version [ver]  Override PlatformVersion property (default is %_version%).
echo.

exit /b 1
