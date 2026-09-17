param(
    [Parameter(Mandatory=$true)] [string] $repoRoot,
    [string]$Verbosity = 'quiet'
)

$startTime = [datetime]::Now
$ErrorActionPreference = "Stop"
# Suppress Write-Progress rendering which can crash PowerShell 5.1 in some terminal environments.
if ($Verbosity -eq 'quiet')
{
    $ProgressPreference = "SilentlyContinue"
}

$scriptsDir = $PSScriptRoot
$initScriptsDir = "$RepoRoot\tools\initScripts"
$preInitScript = "$initScriptsDir\PreInit.ps1"
$preRestoreToolsScript = "$initScriptsDir\PreRestoreTools.ps1"
$postInitScript = "$initScriptsDir\PostInit.ps1"

# Run PreInit.ps1 if it exists
if (Test-Path $preInitScript)
{
    . $preInitScript -RepoRoot $RepoRoot
}

# Enable long path support if necessary
. "$scriptsDir\Initialize-CheckLongPathSupport.ps1"

# Download the NuGet tools if necessary
. "$scriptsDir\Initialize-NuGet.ps1" -RepoRoot $RepoRoot -Verbosity $Verbosity

# Download the MSBuild tools if necessary
# . "$scriptsDir\Initialize-InstallMSBuild.ps1" -InstallDir "$RepoRoot\.buildtools" -Verbosity $Verbosity

# Initialize local Git repository if .git does not exist
if (-not (Test-Path (Join-Path $RepoRoot ".git")))
{
    . "$scriptsDir\Initialize-LocalGitRepository.ps1" -RepoRoot $RepoRoot
}

# Run PreRestoreTools.ps1 if it exists
if (Test-Path $preRestoreToolsScript)
{
    . $preRestoreToolsScript -RepoRoot $RepoRoot
}

# Run PostInit.ps1 if it exists
if (Test-Path $postInitScript)
{
    . $postInitScript -RepoRoot $RepoRoot -Verbosity $Verbosity
}

$duration = (([datetime]::Now - $startTime).TotalSeconds).ToString("N2")
Write-Host Initialized environment for $env:_BuildArch $env:_BuildType `($duration s`)
