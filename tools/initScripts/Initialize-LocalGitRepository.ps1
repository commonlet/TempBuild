param(
    [Parameter(Mandatory=$true)] [string] $repoRoot
)

$ErrorActionPreference = "Stop"

Set-Location -Path $repoRoot
Write-Host -NoNewline "Initializing local Git repository..."

git init
if ($LASTEXITCODE -ne 0) { throw "git init failed with exit code $LASTEXITCODE" }

git config user.email "ci@example.com"
git config user.name "CI"

git commit --allow-empty -m "Initialize local Git repository for build" --quiet
if ($LASTEXITCODE -ne 0) { throw "git commit failed with exit code $LASTEXITCODE" }

$head = git rev-parse HEAD
Write-Host -ForegroundColor Green "Done. HEAD: $head"
