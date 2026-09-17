# Usage: Run at solution root for Windows WinRT header exclusion and dependency summary.
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$solutionRootDir = Split-Path -Parent (Split-Path -Parent $scriptDir)

$devCommonDir = Join-Path $solutionRootDir "dev\Common"
$winrtPath = Join-Path $devCommonDir "winrt"
$buildPath = Join-Path $solutionRootDir "build"
$reservedHeadersTxt = Join-Path $buildPath "ExReservedWinRTHeaders.txt"

function Get-HeaderDependenciesFromFile 
{
    param($filePath)
    $deps = @()
    
    Get-Content $filePath | ForEach-Object {
        $line = $_

        if ($line -match "#include" -and $line -match "winrt" -and $line -match "Windows" -and $line -match "\.h" -and -not ($line -match "Microsoft")) 
        {
            if ($line -match "impl/") 
            {
                $result = $line -replace '.*impl/', ''
                $result = $result -replace '".*', ''
                $result = $result -replace '.*?([^-"\s]+\.h).*', '$1'
            }
            else 
            {
                $result = $line -replace '.*winrt/', ''
                $result = $result -replace '".*', ''
                $result = $result -replace '.*?([^-"\s]+\.h).*', '$1'
            }

            if (($null -ne $result) -and ($result -match "\.h")) 
            {
                $deps += $result
            }
        }
    }

    return $deps | Where-Object {$_ -ne ""}
}

# Traverse winrt for all Microsoft*.h files and collect header deps
$directHeaderDeps = @()

Get-ChildItem -Path $winrtPath -Recurse -Filter "Microsoft*.h" | ForEach-Object {
    $filePath = $_.FullName
    $directHeaderDeps += Get-HeaderDependenciesFromFile $filePath
}

$directHeaderDeps = $directHeaderDeps | Sort-Object | Get-Unique

# Read ExReservedWinRTHeaders.txt if exists (manual reserved set)
$reservedHeaderSet = @()

if (Test-Path $reservedHeadersTxt) 
{
    $reservedHeaderSet = Get-Content $reservedHeadersTxt | Where-Object { $_.Trim() -ne "" }
}

$prelimReservedHeaders = ($directHeaderDeps + $reservedHeaderSet) | Sort-Object | Get-Unique

# Recursive dependency expansion
function Expand-RecursiveHeaderDependencies 
{
    param($headers, $winrtRoot)

    $allDeps = @{}
    $queue = [System.Collections.Queue]::new()
    foreach ($h in $headers) { $queue.Enqueue($h) }

    while ($queue.Count -gt 0) 
    {
        $header = $queue.Dequeue()

        if (-not $allDeps.ContainsKey($header)) 
        {
            # Find the actual file for $header in winrtPath
            $searchFile = Get-ChildItem -Path $winrtRoot -Recurse -Filter "$header" | Select-Object -First 1
            $allDeps[$header] = $true

            if ($searchFile) 
            {
                $deps = Get-HeaderDependenciesFromFile $searchFile.FullName

                foreach ($d in $deps) 
                {
                    if (-not $allDeps.ContainsKey($d)) { $queue.Enqueue($d) }
                }
            }
        }
    }

    return $allDeps.Keys | Sort-Object
}

$finalReservedHeaders = Expand-RecursiveHeaderDependencies $prelimReservedHeaders $winrtPath
$allWindowsHeaders = Get-ChildItem -Path $winrtPath -Recurse -Filter "Windows*.h" | Select-Object -ExpandProperty Name | Sort-Object | Get-Unique
$unusedHeaders = Compare-Object $allWindowsHeaders $finalReservedHeaders | Where-Object { $_.SideIndicator -eq "<=" } | Select-Object -ExpandProperty InputObject | Sort-Object

# Delete unused Windows* headers
foreach ($unused in $unusedHeaders) 
{
    $targetFiles = Get-ChildItem -Path $winrtPath -Recurse -Filter $unused

    foreach ($tf in $targetFiles) 
    {
        try 
        {
            Remove-Item $tf.FullName -Force
        } 
        catch 
        {
            Write-Warning "Failed to delete $($tf.FullName): $_"
        }
    }
}