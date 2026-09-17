@echo off
if not "%platform_echo%" == "" @echo on

set _targetProduct=
set _targetProdTest=
set _targetMux=
set _targetTest=

:parseTargets
if "%1"=="" goto :doneParsingTargets
if "%1"=="prodtest" ( set _targetProdTest=1& shift & goto :parseTargets )
if "%1"=="product"  ( set _targetProduct=1& shift & goto :parseTargets )
if "%1"=="pux"      ( set _targetMux=1& shift & goto :parseTargets )
if "%1"=="test"     ( set _targetTest=1& shift & goto :parseTargets )

echo Unrecognized target or option: %1
exit /b 2

:doneParsingTargets
rem If no targets specified, default to prodtest
if "%_targetProduct%%_targetProdTest%%_targetMux%%_targetTest%" == "" ( set _targetProdTest=1 )

if "%_targetProdTest%" == "1" if "%_targetProduct%" == "1" (
    echo Target ProdTest includes Product, no need to use both.
    exit /b 1
)

if "%_targetMux%" == "1" if "%_targetProduct%" == "1" (
    echo Target Product includes mux, no need to use both.
    exit /b 1
)

if "%_targetMux%" == "1" if "%_targetProdTest%" == "1" (
    echo Target ProdTest includes mux, no need to use both.
    exit /b 1
)

if "%_targetTest%" == "1" if "%_targetProdTest%" == "1" (
    echo Target ProdTest includes test, no need to use both.
    exit /b 1
)

call :buildSolution "%EngineeringRoot%\PackageReference\PackageReference.csproj"
if ERRORLEVEL 1 exit /b 1

if "%_targetMux%" == "1" (
    msbuild "%DevelopmentRoot%\DXaml\packages.csproj" /p:Platform=%Platform%
    call :buildSolution "%DevelopmentRoot%\DXaml\xcp\dxaml\dllsrv\winrt\native\Microsoft.ui.xaml.vcxproj"
    if ERRORLEVEL 1 exit /b 1
)
if "%_targetProduct%" == "1" (
    call :buildSolution "%RepoRoot%\Microsoft.UI.Xaml-Product.sln"
    if ERRORLEVEL 1 exit /b 1
    call :buildSolution "%RepoRoot%\controls\dev\dll\Microsoft.UI.Xaml.Controls.vcxproj"
    if ERRORLEVEL 1 exit /b 1
)
if "%_targetProdTest%" == "1" (
    call :buildSolution "%RepoRoot%\dxaml\Microsoft.UI.Xaml.sln"
    if ERRORLEVEL 1 exit /b 1
    call :buildSolution "%RepoRoot%\controls\MUXControls.sln" /restore
    if ERRORLEVEL 1 exit /b 1
)
if "%_targetTest%" == "1" (
    call :buildSolution "%RepoRoot%\controls\MUXControls.sln" /restore
    if ERRORLEVEL 1 exit /b 1
)

exit /b 0

:buildSolution
set _solution=%1
shift
set _args=%*

for %%i in (%_solution%) do set _title=%%~ni
set _binlog=%LogRoot%\%_title%.%_BuildArch%%_BuildType%.binlog

if "%_quiet%"=="1" (
    set _options=/bl:!_binlog! !_verbosity! /clp:ErrorsOnly /ds:false !_procCount! %_args% %_versionOption% /nr:false
) else (
    set _options=/bl:!_binlog! !_verbosity! /clp:Summary,ForceNoAlign /ds:false !_procCount! %_args% %_versionOption% /nr:false
)

if "%_restore%"=="1" (
    if not "%_quiet%"=="1" echo Adding restore option...
    set _options=/restore /p:DisableWarnForInvalidRestoreProjects=true !_options!
)

if "%_graph%"=="1" (
    if not "%_quiet%"=="1" echo Adding graph option...
    set _options=!_options! /graph
)

if "%_cache%"=="1" (
    if not "%_quiet%"=="1" echo Enabling project cache
    set _options=!_options! /reportfileaccesses /p:MSBuildCacheEnabled=true /p:MSBuildCacheLogDirectory=%LogRoot%\MSBuildCacheLogs\%_title%.%_BuildArch%%_BuildType%
)

if "%_lowpriority%"=="1" ( set _options=!_options! /lowPriority )

rem Define Configuration and Platform as global properties instead of just env vars to ensure consistent behavior with VS.
if defined Configuration set _options=!_options! /p:Configuration=%Configuration%
if defined Platform set _options=!_options! /p:Platform=%Platform%
if defined PGOBuildMode set _options=!_options! /p:PGOBuildMode=%PGOBuildMode%

set _command=call msbuild !_options!

if "%_fake%"=="1" (
    echo COMMAND: %_command%
    goto :eof
)

rem Clear the PSModulePath environment variable. This avoids issues when the caller is a version of
rem powershell that does not match the version of powershell that msbuild invokes. (Ex: pwsh.exe vs
rem powershell.exe)
rem This is safe because cmd.exe is its own process and setting the environment variable here will
rem not affect the parent process.
if not "%PSModulePath%" == "" ( set PSModulePath= )

%_command%

if ERRORLEVEL 1 (
    echo ---
    echo ERROR: buildSolution for !_solution! FAILED.  Binlog is here: !_binlog!
)

goto:eof