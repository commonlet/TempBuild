param(
    [Parameter(Mandatory)] [string]$Target,
    [Parameter(Mandatory)] [string]$Flavor,
    [Parameter(Mandatory)] [string]$Platform,
    [Parameter(Mandatory)] [string]$Configuration
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot "build.psm1")

Write-Host "Installing rclone..."
winget install Rclone.Rclone --source winget

# Update-Path
$env:Path = (@(
    [System.Environment]::GetEnvironmentVariable("Path","Machine"),
    [System.Environment]::GetEnvironmentVariable("Path","User")
) -split ';' | Where-Object { $_ } | Select-Object -Unique) -join ';'

rclone --version

if (-not $env:DRIVE_SERVICE_JSON -or -not $env:DRIVE_UPLOAD_CONFIG)
{
    Write-Host "::error::Required secrets are not set."
    exit 1
}

$saJsonPath = "$env:RUNNER_TEMP\drive-service-account.json"
[IO.File]::WriteAllBytes($saJsonPath, [Convert]::FromBase64String($env:DRIVE_SERVICE_JSON))
$driveUploadConfig = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($env:DRIVE_UPLOAD_CONFIG))

$rcloneDir = "$env:USERPROFILE\.config\rclone"
New-Item -ItemType Directory -Force -Path $rcloneDir | Out-Null

$rcloneConf = @"
[drive]
type = drive
scope = drive
shared_with_me = true
service_account_file = $saJsonPath

$driveUploadConfig
"@

$rcloneConf | Out-File -FilePath "$rcloneDir\rclone.conf" -Encoding utf8

rclone listremotes

Write-Host "Syncing from Drive to working directory..."
rclone sync "drive:YCL-PlatformSDK" "$env:GITHUB_WORKSPACE" --transfers 8 --checkers 32 --drive-chunk-size 64M --fast-list --progress --stats 1m `
  --filter "+ Build.cmd" `
  --filter "+ init.ps1" `
  --filter "+ tools/**" `
  --filter "+ .github/**" `
  --filter "- **"

if ($LASTEXITCODE -ne 0) 
{
    Write-Host "::error::rclone sync failed with exit code $LASTEXITCODE."
    exit $LASTEXITCODE
}

Invoke-CiBuild  -Flavor $Flavor -Platform $Platform -Configuration $Configuration -Target $Target
Push-BuildArtifacts -Flavor $Flavor

$stableCount = 0
$stableRounds = 2

$defaultInterval = 300
$fastInterval = 150
$pollInterval = $defaultInterval

while ($true)
{
    Start-Sleep -Seconds $pollInterval

    rclone check "drive:YCL-PlatformSDK" "$env:GITHUB_WORKSPACE" --fast-list --one-way --max-age 5m
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 1)
    {
        Write-Host "::error::rclone check failed with exit code $LASTEXITCODE."
        exit $LASTEXITCODE
    }

    $hasChanges = $LASTEXITCODE -eq 1

    if ($hasChanges)
    {
        rclone sync "drive:YCL-PlatformSDK" "$env:GITHUB_WORKSPACE" --fast-list --drive-shared-with-me `
            --filter "- .git/**" `
            --filter "- .github/**" `
            --filter "- BuildOutput/**" `
            --filter "- packages/**" `
            --filter "+ packages/LocalPackages.config"

        if ($LASTEXITCODE -ne 0)
        {
            Write-Host "::error::rclone sync failed with exit code $LASTEXITCODE."
            exit $LASTEXITCODE
        }

        $stableCount = 0
        $pollInterval = $fastInterval
    }
    else
    {
        $stableCount++
        $pollInterval = $defaultInterval

        if ($stableCount -ge $stableRounds)
        {
            Start-CiBuild -Target $Target
            Push-BuildArtifacts -Flavor $Flavor

            $stableCount = 0
        }
    }
}
