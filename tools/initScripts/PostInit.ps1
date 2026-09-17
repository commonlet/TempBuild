param(
    [Parameter(Mandatory=$true)] [string] $RepoRoot,
    [string] $Verbosity = 'minimal'
)

Write-Host "Restoring (MSBuild-integrated, CPM-aware)..."
msbuild -nologo -t:Restore "$RepoRoot\YCL-PlatformSDK.slnx" -v:$Verbosity
Write-Host -ForegroundColor Green "Restore done."