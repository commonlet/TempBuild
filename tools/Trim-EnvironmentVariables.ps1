function Set-EnvironmentVariable
{
    param(
        [string]$VariableName,
        [string]$VariableValue
    )

    Set-Item -Path "Env:$VariableName" -Value $VariableValue

    if ($env:Pipeline -eq 'true')
    {
        Write-Host "##vso[task.setVariable variable=$VariableName]$VariableValue"
    }

    if ($env:GITHUB_ACTIONS -eq 'true')
    {
        Add-Content -Path $env:GITHUB_ENV -Value "$VariableName=$VariableValue"
    }
}

$keepPatterns = @(
    'Microsoft',
    'Windows',
    'dotnet',
    'PowerShell',
    'Git'
)

$excludePatterns = @('hostedtoolcache')

$filteredPaths = ($env:PATH -split ';') | Where-Object {
    $path = $_
    if ([string]::IsNullOrWhiteSpace($path)) { return $false }

    $exclude = $excludePatterns | Where-Object { $path -like "*$_*" }
    if ($exclude) { return $false }

    $keep = $keepPatterns | Where-Object { $path -like "*$_*" }
    return [bool]$keep
} | Select-Object -Unique

$newPath = $filteredPaths -join ';'

$excludeVarPatterns = @(
    'ANDROID',
    'ANT_HOME',
    'CABAL_DIR',
    'CONDA',
    'GHCUP',
    'GOROOT',
    'GRADLE_HOME',
    'JAVA_HOME',
    'M2',
    'M2_REPO',
    'MAVEN_OPTS',
    'npm_config_prefix',
    'RTOOLS45_HOME',
    'SBT_HOME',
    'VCPKG_INSTALLATION_ROOT',
    'ChromeWebDriver',
    'EdgeWebDriver',
    'GeckoWebDriver',
    'IEWebDriver',
    'SELENIUM_JAR_PATH',
    'PG',
    'AZ_DEVOPS',
    'AZURE',
    'COBERTURA_HOME',
    'PIPX',
    'PHPROOT',
    'WIX',
    'PSModuleAnalysisCachePath',
    'DriverData',
    'ChocolateyInstall'
)

$allVars = Get-ChildItem Env:
$keepVars = @{}
$removedCount = 0

foreach ($var in $allVars)
{
    $name = $var.Name
    if ($name -eq 'PATH' -or $name -eq 'Path')
    {
        $keepVars[$name] = $newPath
        continue
    }

    $exclude = $excludeVarPatterns | Where-Object { $name -match $_ }
    if (-not $exclude)
    {
        $keepVars[$name] = $var.Value
    }
    else
    {
        $removedCount++
    }
}

Write-Host "Keeping $($keepVars.Count) variables, removing $removedCount variables"


foreach ($var in $allVars)
{
    $name = $var.Name
    if ($name -eq 'PATH' -or $name -eq 'Path') { continue }

    $exclude = $excludeVarPatterns | Where-Object { $name -match $_ }
    if ($exclude)
    {
        Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
    }
}

$env:PATH = $newPath
Set-EnvironmentVariable -VariableName "PATH" -VariableValue $newPath

foreach ($var in $allVars)
{
    $name = $var.Name
    if ($name -eq 'PATH' -or $name -eq 'Path') { continue }

    $exclude = $excludeVarPatterns | Where-Object { $name -match $_ }
    if (-not $exclude)
    {
        Set-EnvironmentVariable -VariableName $name -VariableValue $var.Value
    }
}

Write-Host "Environment variables reduced successfully!" -ForegroundColor Green
