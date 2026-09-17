@echo off
goto :begin

rem This function is used to set enviroment variables in Azure Pipelines.
rem It will call task.setVariable on top of the regular "set" command if /pipeline is passed in.
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

:AddPathIfExists
set _ToAdd=%~1
if not exist "%_ToAdd%" ( goto :PathNotFound )

set PATH=%_ToAdd%;%PATH%
set _ToAdd=
exit /b 0

:PathNotFound
echo Could not find path: %~1
exit /b 4

:begin
set RepoRoot=%~dp0..\..
for %%i in ("%RepoRoot%") do set RepoRoot=%%~fi

set EnvCheck=
set EnvOnly=
set NoTitle=
set Verbose=
set Pipeline=

rem In case we run init.cmd multiple times, we don't want to keep our additions to PATH around.
rem We'll save the original value of PATH and restore it on future calls to init.cmd.
rem Given that PATH can get super long, we'll split this into multiple statements since having both "set"
rem statements on the same line can cause cmd to complain the command is too large.
if "%_OriginalPathBeforeInit%" neq "" goto :OriginalPathSet
set _OriginalPathBeforeInit=%PATH%
goto :DoneSettingPath

:OriginalPathSet
set PATH=%_OriginalPathBeforeInit%

:DoneSettingPath
set amd64=
set ARM64=
set ARM64EC=
set fre=
set chk=
set _BuildArch=
set _BuildType=
set _DotNetMoniker=net8.0
set _archIsSet=
set _noPgo=

set "_arg=%~1"
if "%_arg%"=="" set _arg=amd64chk
set _ArchType=%_arg%

rem x86 is no longer supported and has been dropped from arch parsing.
if /i "%_arg%"=="amd64chk"          ( set _BuildArch=amd64 & set Platform=x64 & set Configuration=Debug & set _BuildType=chk
) else if /i "%_arg%"=="amd64fre"   ( set _BuildArch=amd64 & set Platform=x64 & set Configuration=Release & set _BuildType=fre
) else if /i "%_arg%"=="x64chk"     ( set _BuildArch=amd64 & set Platform=x64 & set Configuration=Debug & set _BuildType=chk
) else if /i "%_arg%"=="x64fre"     ( set _BuildArch=amd64 & set Platform=x64 & set Configuration=Release & set _BuildType=fre
) else if /i "%_arg%"=="arm64chk"   ( set _BuildArch=ARM64 & set Platform=ARM64 & set Configuration=Debug & set _BuildType=chk
) else if /i "%_arg%"=="arm64fre"   ( set _BuildArch=ARM64 & set Platform=ARM64 & set Configuration=Release & set _BuildType=fre
) else if /i "%_arg%"=="arm64ecchk" ( set _BuildArch=ARM64EC & set Platform=ARM64EC & set Configuration=Debug & set _BuildType=chk
) else if /i "%_arg%"=="arm64ecfre" ( set _BuildArch=ARM64EC & set Platform=ARM64EC & set Configuration=Release & set _BuildType=fre
) else (
    echo ERROR: unknown arch/flavor '%_arg%'
    echo Usage: %~nx0 [amd64chk^|amd64fre^|x64chk^|x64fre^|arm64chk^|arm64fre^|arm64ecchk^|arm64ecfre]
    exit /b 1
)

shift

:parseArgs
if /i "%1"==""                 ( goto :doneParsingArgs
) else if /i "%1"=="/envonly"  ( set EnvOnly=true
) else if /i "%1"=="/envcheck" ( set EnvOnly=true & set EnvCheck=true
) else if /i "%1"=="/notitle"  ( set NoTitle=1
) else if /i "%1"=="/nopgo"    ( set _noPgo=1
) else if /i "%1"=="/verbose"  ( set Verbose=-Verbosity normal
) else if /i "%1"=="/pipeline" ( set EnvOnly=true & set Pipeline=true
) else (
    echo Unrecognized option: %1
    echo Usage: %~nx0 [flavor] [/envcheck^|/envonly^|/notitle^|/nopgo^|/verbose^|/pipeline]
    exit /b 1
)

shift
goto :parseArgs

:doneParsingArgs

rem Determine whether this is an internal (ADO) or OSS (public GitHub) build and expose it
rem to the build scripts (e.g. PostInit.ps1). The .azuredevops folder exists only in the
rem internal repo (it is excluded from the public mirror), matching the IsInternalPlatformBuild
rem MSBuild property in eng\Versions.props. Use explicit true/false (never empty) so
rem init.ps1's Invoke-CmdScript propagates the value.
if exist "%RepoRoot%\.azuredevops" (
    call :SetEnvironmentVariable IsInternalPlatformBuild true
) else (
    call :SetEnvironmentVariable IsInternalPlatformBuild false
)

if "%EnvCheck%"=="true" (
    if not exist "%RepoRoot%\packages" (
        echo ERROR: Cannot use /envcheck because a full init has not been run yet.
        echo        Required tools and NuGet packages are missing.
        echo.
        echo        Run a full init first:  init.cmd [flavor]
        echo        Example:                init.cmd amd64chk
        exit /b 1
    )
)

set PGOBuildMode=Off
if "%_BuildType%"=="fre" if not "%_BuildArch%"=="ARM64EC" if not "%_noPgo%"=="1" set PGOBuildMode=Optimize
set _noPgo=

if "%DevEnvDir%" == "" goto :NeedDevCmd
where msbuild >nul 2>&1
if errorlevel 1 goto :NeedDevCmd
goto :SkipDevCmd

:NeedDevCmd
    echo DevEnvDir environment variable not set or msbuild unavailable. Running DevCmd.cmd to get a developer command prompt...
    if /i "%_BuildArch%"=="ARM64EC" (
        call "%RepoRoot%\tools\DevCmd.cmd" /PreserveContext /prerelease -arch=arm64ec -host_arch=amd64
    ) else (
        call "%RepoRoot%\tools\DevCmd.cmd" /PreserveContext /prerelease -arch=%_BuildArch% -host_arch=amd64
    )
    if errorlevel 1 (
        echo Could not set up a developer command prompt
        exit /b %ERRORLEVEL%
    )

:SkipDevCmd
if not "%VisualStudioVersion:~0,2%" == "18" (echo Visual Studio 18.0 or later is required. && exit /b 1)

call :SetEnvironmentVariable _ArchType %_ArchType%
call :SetEnvironmentVariable _BuildType %_BuildType%
call :SetEnvironmentVariable _BuildArch %_BuildArch%

call :SetEnvironmentVariable Platform %Platform%
call :SetEnvironmentVariable Configuration %Configuration%
call :SetEnvironmentVariable PGOBuildMode %PGOBuildMode%
call :SetEnvironmentVariable Pipeline %Pipeline%

rem Set BUILDPLATFORM to Platform
if not "%Pipeline%"=="true" ( call :SetEnvironmentVariable BUILDPLATFORM %Platform% )

call :SetEnvironmentVariable RepoRoot "%RepoRoot%"
call :SetEnvironmentVariable BuildRoot "%RepoRoot%\build"
call :SetEnvironmentVariable DevelopmentRoot "%RepoRoot%\dev"
call :SetEnvironmentVariable EngineeringRoot "%RepoRoot%\eng"
call :SetEnvironmentVariable NuGetPackageRoot "%RepoRoot%\packages"
call :SetEnvironmentVariable SourceRoot "%RepoRoot%\src"
call :SetEnvironmentVariable TestRoot "%RepoRoot%\test"
call :SetEnvironmentVariable ToolsRoot "%RepoRoot%\tools"

call :SetEnvironmentVariable BuildArtifactsDir "%RepoRoot%\BuildOutput"
call :SetEnvironmentVariable BinRoot "%BuildArtifactsDir%\bin"
call :SetEnvironmentVariable BuildOutputRoot "%BuildArtifactsDir%\obj"
call :SetEnvironmentVariable LogRoot "%BuildArtifactsDir%\Logs"
call :SetEnvironmentVariable TempRoot "%BuildArtifactsDir%\Temp"

call :SetEnvironmentVariable TEMP "%TempRoot%"
call :SetEnvironmentVariable TMP "%TempRoot%"

if "%NoTitle%"=="" ( title %_ArchType% - %RepoRoot% )
if "%EnvOnly%"=="" ( pwsh -File "%ToolsRoot%\initScripts\Initialize-Restore.ps1" -RepoRoot %RepoRoot% %Verbose% )

set EnvironmentInitialized=1

exit /b 0