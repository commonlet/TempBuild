param(
    [Parameter(Position = 0)]
    [string]$PackageName = "",

    [Parameter(Position = 1)]
    [bool]$AllowPrerelease = $true
)

$RepoRoot = Split-Path -Parent $PSScriptRoot
$NuGetPackageRoot = Join-Path $RepoRoot "packages"
$LocalStorePath = Join-Path $NuGetPackageRoot "LocalStore"
$LocalPackageConfiguration = Join-Path $NuGetPackageRoot "LocalPackages.config"
$PackageRestoreProj = Join-Path $RepoRoot "eng\PackageReference\PackageReference.csproj"

$localPackagesLower = (Test-Path $LocalPackageConfiguration) ? (Get-Content $LocalPackageConfiguration | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_.ToLower() }) : @()

$feedIndexUrls = @(
    "https://api.nuget.org/v3/index.json",
    "https://pkgs.dev.azure.com/shine-oss/microsoft-ui-xaml/_packaging/WinUI-Dependencies/nuget/v3/index.json",
    "https://pkgs.dev.azure.com/winui/microsoft-ui-xaml/_packaging/WinUI-Dependencies/nuget/v3/index.json",
    "https://microsoft.pkgs.visualstudio.com/ProjectReunion/_packaging/Project.Reunion.nuget.internal/nuget/v3/index.json",
    "https://pkgs.dev.azure.com/microsoft/_packaging/WindowsSDK.Internal.IXP/nuget/v3/index.json"
)

$propsFilePath = Join-Path $RepoRoot "Directory.Packages.props"
$propsLines = Get-Content $propsFilePath
$failedPackages = @()

$packagesToQuery = @()
for ($i = 0; $i -lt $propsLines.Count; $i++)
{
    if ($propsLines[$i] -match '<PackageVersion\s+Include\s*=\s*"([^"]+)"\s+Version\s*=\s*"([^"]+)"\s*/>')
    {
        $includeName = $Matches[1]
        $nugetApiName = $includeName.ToLower()
        if ($localPackagesLower -contains $nugetApiName)
        {
            Write-Host "[Local] Skipping packages listed in LocalPackages.config: $includeName"
            continue
        }

        $packagesToQuery += [PSCustomObject]@{ Index = $i; Name = $includeName; ApiName = $nugetApiName; CurrentVersion = $Matches[2] }
    }
}

$queryResults = $packagesToQuery | ForEach-Object -Parallel {
    $pkg = $_
    foreach ($idxUrl in $using:feedIndexUrls)
    {
        try
        {
            $svc = (Invoke-WebRequest -Uri $idxUrl -UseBasicParsing).Content | ConvertFrom-Json
            $base = ($svc.resources | Where-Object { $_.'@type' -eq "PackageBaseAddress/3.0.0" } | Select-Object -First 1).'@id'
            if (-not $base) { continue }

            $versions = (Invoke-WebRequest -Uri "$base$($pkg.ApiName)/index.json" -UseBasicParsing).Content | ConvertFrom-Json | Select-Object -ExpandProperty versions

            $stable = @($versions | Where-Object { $_ -notmatch '-' })
            if ($stable.Count -gt 0)
            {
                return [PSCustomObject]@{ Package = $pkg; Latest = $stable[-1]; HasStable = $true }
            }
            elseif ($using:AllowPrerelease)
            {
                $sorted = $versions | Sort-Object { $_ } -Descending
                if ($sorted.Count -gt 0) { return [PSCustomObject]@{ Package = $pkg; Latest = $sorted[0]; HasStable = $false } }
            }
            else
            {
                return [PSCustomObject]@{ Package = $pkg; Latest = $null; HasStable = $false; Failed = $true }
            }
        }
        catch { continue }
    }

    return [PSCustomObject]@{ Package = $pkg; Latest = $null; HasStable = $false }
} -ThrottleLimit 10

foreach ($item in $queryResults)
{
    $pkg = $item.Package
    if ($item.Latest)
    {
        if ($pkg.CurrentVersion -ne $item.Latest)
        {
            Write-Host "[NuGet] Querying latest $(if ($item.HasStable) { "stable" } else { "prerelease" }) version for: $($pkg.Name) ($($pkg.CurrentVersion) -> $($item.Latest))"
            $propsLines[$pkg.Index] = $propsLines[$pkg.Index] -replace 'Version\s*=\s*"[^"]*"', "Version=""$($item.Latest)"""
        }
        else
        {
            Write-Host "[NuGet] Querying latest version for: $($pkg.Name) (Latest)"
        }
    }
    elseif ($item.Failed)
    {
        $failedPackages += $pkg.Name
        Write-Host "[NuGet] No stable version found for: $($pkg.Name)"
    }
    else
    {
        Write-Host "[NuGet] Package not found on feed, keeping current version '$($pkg.CurrentVersion)': $($pkg.Name)"
    }
}

$propsLines = $propsLines | ForEach-Object { if ($_ -match '^\s*<PackageVersion\s+') { '    ' + $_.TrimStart() } else { $_ } }
Set-Content -Path $propsFilePath -Value ($propsLines -join "`r`n")

msbuild $PackageRestoreProj /t:Restore /p:NuGetInteractive="true"

if (Test-Path $NuGetPackageRoot)
{
    $topFolders = Get-ChildItem -Path $NuGetPackageRoot -Directory | Where-Object { $_.FullName -ne $LocalStorePath }
    foreach ($top in $topFolders)
    {
        $versionFolders = Get-ChildItem -Path $top.FullName -Directory
        if ($versionFolders.Count -le 1) { continue }

        $pkgNameLower = $top.Name.ToLower()
        $targetVersion = $null
        foreach ($line in $propsLines)
        {
            if ($line -match '<PackageVersion\s+Include\s*=\s*"([^"]+)"\s+Version\s*=\s*"([^"]+)"\s*/>' -and $Matches[1].ToLower() -eq $pkgNameLower)
            {
                $targetVersion = $Matches[2]
                break
            }
        }

        if ($targetVersion)
        {
            $versionFolders | Where-Object { $_.Name -ne $targetVersion } | Remove-Item -Recurse -Force
        }
        else
        {
            $parsed = $versionFolders | ForEach-Object {
                $nuspec = Get-ChildItem -Path $_.FullName -Filter "*.nuspec" -File | Select-Object -First 1
                [PSCustomObject]@{ Folder = $_; LastWriteTime = if ($nuspec) { $nuspec.LastWriteTime } else { $_.LastWriteTime } }
            }

            $latest = $parsed | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            $parsed | Where-Object { $_.Folder.FullName -ne $latest.Folder.FullName } | ForEach-Object { Remove-Item -Path $_.Folder.FullName -Recurse -Force }
        }
    }
}

if ($failedPackages.Count -gt 0)
{
    Write-Host "The following packages could not be updated to the latest version:"
    $failedPackages | ForEach-Object { Write-Host $_ }
}
