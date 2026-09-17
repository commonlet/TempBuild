param(
    [Parameter(Mandatory = $true)]
    [string]$InputFile,

    [Parameter(Mandatory = $true)]
    [string]$OutputFile,

    [switch]$KeepCondition
)

if (-not (Test-Path $InputFile))
{
    Write-Host "Input file does not exist: $InputFile" -ForegroundColor Red
    exit 1
}

$content = Get-Content $InputFile -Raw -Encoding UTF8
$parts = $content -split '(?=<PropertyGroup)'
$pkgGroup = $null

for ($i = $parts.Count - 1; $i -ge 0; $i--)
{
    if ($parts[$i] -match '<PropertyGroup' -and $parts[$i] -match 'Pkg')
    {
        $pkgGroup = $parts[$i]
        break
    }
}

if (-not $pkgGroup)
{
    Write-Host "Error: Cannot find PropertyGroup containing 'Pkg' in $InputFile" -ForegroundColor Red
    exit 1
}

$pkgContent = $pkgGroup -replace '(?s)^<PropertyGroup[^>]*>(.*?)</PropertyGroup>.*$', '$1'

if (-not $KeepCondition)
{
    $pkgContent = $pkgContent -replace '\s+Condition="[^"]*"', ''
}

$lines = $pkgContent -split "`r`n"
while ($lines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($lines[0])) { $lines = $lines[1..($lines.Count - 1)] }
while ($lines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($lines[-1])) { $lines = $lines[0..($lines.Count - 2)] }
$pkgContent = $lines -join "`r`n"

$outputContent = @(
    '<?xml version="1.0" encoding="utf-8" standalone="no"?>',
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">',
    '  <PropertyGroup Condition=" ''$(ExcludeRestorePackageImports)'' != ''true'' ">',
    $pkgContent,
    '  </PropertyGroup>',
    '</Project>'
) -join "`r`n"

New-Item -ItemType Directory -Path (Split-Path $OutputFile -Parent) -Force | Out-Null
$outputContent | Out-File -FilePath $OutputFile -Encoding utf8NoBOM -Force

Write-Host "Generated: $OutputFile" -ForegroundColor Green
