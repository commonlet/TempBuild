function Initialize-BuildEnvironment
{
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$Flavor)
    
    # Run init with /envcheck to set up environment variables and PATH
    # This skips NuGet restore — a full init must have been run previously.
    try 
    {
        . (Join-Path $repoRootDir "init.ps1") $Flavor /envcheck /notitle
    } 
    catch 
    {
        Write-Host "ERROR: init.ps1 $Flavor /envcheck failed: $_" -ForegroundColor Red
        exit 1
    }
}

function Start-CiBuild
{
    [CmdletBinding()]
    param([string]$Target)

    Write-Host "=== BEFORE Build.cmd ==="
    Write-Host "EnvironmentInitialized = $env:EnvironmentInitialized"
    Write-Host "ToolsRoot = $env:ToolsRoot"
    Write-Host "RepoRoot = $env:RepoRoot"
    
    & (Join-Path $repoRootDir "Build.cmd") $Target
    if ($LASTEXITCODE -ne 0) 
    {
        Write-Host "::error::Build failed with exit code $LASTEXITCODE."
        exit $LASTEXITCODE
    }
}

function Invoke-CiBuild
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Flavor,
        [Parameter(Mandatory)] [string]$Platform,
        [Parameter(Mandatory)] [string]$Configuration,
        [string]$Target
    )

    Write-Host "flavor=$Flavor platform=$Platform configuration=$Configuration"
    
    $secretsToClear = @(
        'ACTIONS_RUNTIME_TOKEN',
        'ACTIONS_RUNTIME_URL',
        'ACTIONS_RESULTS_URL',
        'ACTIONS_CACHE_URL',
        'ACTIONS_ID_TOKEN_REQUEST_TOKEN',
        'ACTIONS_ID_TOKEN_REQUEST_URL',
        'GITHUB_TOKEN'
    )

    foreach ($v in $secretsToClear) 
    {
        Remove-Item "env:$v" -ErrorAction SilentlyContinue
    }

    $global:repoRootDir = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path

    # GitHub Actions runner has many pre-installed components, making environment variables
    # exceed cmd's 8191-character limit. Trim them first to avoid init.cmd failures.
    . (Join-Path $repoRootDir "tools\Trim-EnvironmentVariables.ps1")

    $binlogDir = Join-Path $env:GITHUB_WORKSPACE "BuildOutput\Logs"
    if (-not (Test-Path $binlogDir)) { New-Item -ItemType Directory -Force -Path $binlogDir | Out-Null }

    Initialize-BuildEnvironment -Flavor $Flavor
    Start-CiBuild -Target $Target
}

function Push-BuildArtifacts
{
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$Flavor)

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $localArtifactsDir = Join-Path $env:GITHUB_WORKSPACE "BuildOutput"
    $remoteArtifactsDir = "drive_upload:BuildArtifacts/YCL-PlatformSDK/${timestamp}_${Flavor}"

    Write-Host "Uploading BuildOutput to $remoteArtifactsDir"

    rclone copy $localArtifactsDir $remoteArtifactsDir `
        --include "bin/**" `
        --include "Logs/**" `
        --transfers 8 `
        --checkers 16 `
        --drive-chunk-size 64M `
        --fast-list `
        --progress

    if ($LASTEXITCODE -ne 0)
    {
        Write-Host "::error::rclone upload failed with exit code $LASTEXITCODE."
        exit $LASTEXITCODE
    }

    Write-Host "Upload completed: $remoteArtifactsDir"
}