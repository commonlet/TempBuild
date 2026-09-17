param(
    [Parameter(Mandatory)] [string]$Flavor,
    [Parameter(Mandatory)] [string]$Platform,
    [Parameter(Mandatory)] [string]$Configuration
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot "build.psm1") -Force
Invoke-CiBuild  -Flavor $Flavor -Platform $Platform -Configuration $Configuration