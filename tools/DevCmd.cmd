@echo off

rem Scripts cannot set enviroment variables because of an older handler in the agent that is not compatible with some pipeline containers
rem Hence to set enviroment variables, use SetEnvironmentVariable
goto :begin

:SetEnvironmentVariable
set _varName=%~1
set _varValue=%~2
set %_varName%=%_varValue%

if not "%Pipeline%"=="true" (
    set _varName=
    set _varValue=
    exit /b 0
)

echo ##vso[task.setVariable variable=%_varName%]%_varValue%
set _varName=
set _varValue=
exit /b 0

:PrintVsWhere
@echo on
%vswhere% -products Microsoft.VisualStudio.Product.BuildTools -property InstallationPath %PrereleaseArg%
%vswhere% -requires Microsoft.Component.MSBuild -property InstallationPath %PrereleaseArg%
@echo off
exit /b 0

:begin
pushd %~dp0
set PrereleaseArg=

setlocal enableextensions enabledelayedexpansion

set _ARGS=

rem We are targeting VS 2026 (version 18.x) or later
if exist %temp%\PlatformSDK.PreserveContext.marker del %temp%\PlatformSDK.PreserveContext.marker

:ParseArgs
if "%1" EQU "" (
    goto :DoneParsing
) else if /i "%1" EQU "/PreserveContext" (
    echo. > %temp%\PlatformSDK.PreserveContext.marker
) else if /i "%1" EQU "/Prerelease" (
    set PrereleaseArg=-prerelease
) else (
    set _ARGS=%_ARGS% %1=%2
    shift
)

shift
goto ParseArgs

:DoneParsing
set vswhere="%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist %vswhere% (echo VSWhere.exe not found. Install MSBuild first from OneTimeSetup.cmd && exit /b 1)

rem Try MSBuild first
set MSBuildInstallpath=
for /f "tokens=*" %%a in ('%vswhere% -products Microsoft.VisualStudio.Product.BuildTools -property InstallationPath %PrereleaseArg% -latest') do set MSBuildInstallPath=%%a

if "%MSBuildInstallPath%" EQU "" (
    rem We didn't find MSBuild, try a full VSexit
    for /f "tokens=*" %%a in ('%vswhere% -requires Microsoft.Component.MSBuild -property InstallationPath %PrereleaseArg% -latest') do set MSBuildInstallPath=%%a
)

if "%MSBuildInstallPath%" EQU "" (
    echo Could not find an MSBuild install, exiting
    if defined AGENT_NAME ( call :PrintVsWhere )
    exit /b 2
)

rem In the pipeline, vswhere cannot locate VS build tools installed as part of the pipeline run without a restart.  If the .buildtools directory exists,
rem implying the pipeline installed VS build tools, use them instead.

if exist %~dp0.buildtools (
    echo Using MSBuild from .buildtools directory...
    set MSBuildInstallPath=%~dp0.buildtools
) else (
    echo .buildtools directory not found, using MSBuild from vswhere...
)

endlocal & (
    echo "Initializing VS Command Prompt from %MSBuildInstallPath%\Common7\Tools\VsDevCmd.bat ..."
    call "%MSBuildInstallPath%\Common7\Tools\VsDevCmd.bat" /no_logo %_ARGS%
)

rem These variables are set in VsDevCmd.bat but we need to set them again with SetEnvironmentVariable to work in pipeline containers
call :SetEnvironmentVariable VCToolsInstallDir "%VCToolsInstallDir%"
call :SetEnvironmentVariable VCToolsRedistDir "%VCToolsRedistDir%"
call :SetEnvironmentVariable ExtensionSdkDir "%ExtensionSdkDir%"

if not exist %temp%\PlatformSDK.PreserveContext.marker ( pwsh -NoExit -Command "Set-Location -Path '%RepoRoot%'" )
if exist %temp%\PlatformSDK.PreserveContext.marker (del %temp%\PlatformSDK.PreserveContext.marker)

exit /b 0
