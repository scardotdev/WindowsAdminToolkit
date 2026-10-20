[CmdletBinding()]
param([string]$OutputDirectory=(Join-Path (Split-Path -Parent $PSScriptRoot) 'out'))
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$module=Join-Path $root 'src/ScarWinAdmin/Public/Test-ScarPendingReboot.ps1'
$dest=Join-Path $OutputDirectory 'scripts/maintenance'
New-Item -ItemType Directory -Force -Path $dest | Out-Null
$script = "# Generated from src/ScarWinAdmin/Public/Test-ScarPendingReboot.ps1. Do not edit.`r`n" + (Get-Content -Raw $module) + "`r`nTest-ScarPendingReboot`r`n"
Set-Content -LiteralPath (Join-Path $dest 'Test-PendingReboot.ps1') -Value $script -Encoding UTF8
$diskSource=Join-Path $root 'src/ScarWinAdmin/Public/Get-ScarDiskUsage.ps1'
$diskDest=Join-Path $OutputDirectory 'scripts/storage'
New-Item -ItemType Directory -Force -Path $diskDest | Out-Null
$diskScript="# Generated from src/ScarWinAdmin/Public/Get-ScarDiskUsage.ps1. Do not edit.`r`n" + (Get-Content -Raw $diskSource) + "`r`nGet-ScarDiskUsage @args`r`n"
# Add param-block compatible script entrypoint: wrapper splats bound parameters as named arguments.
$wrapper=@'
[CmdletBinding()]
param(
 [string]$Path,
 [ValidateRange(0,32)][int]$MaxDepth=2,
 [ValidateRange(1,1000000)][int]$MaxItems=10000,
 [ValidateRange(1,3600)][int]$TimeoutSeconds=30,
 [ValidateRange(0,100)][double]$WarningFreePercent=20,
 [ValidateRange(0,100)][double]$CriticalFreePercent=10,
 [ValidateRange(1,100)][int]$Top=10
)
'@
$diskScript=$wrapper + "`r`n" + (Get-Content -Raw $diskSource) + "`r`nGet-ScarDiskUsage @PSBoundParameters`r`n"
Set-Content -LiteralPath (Join-Path $diskDest 'Get-DiskUsage.ps1') -Value $diskScript -Encoding UTF8
Copy-Item -Path (Join-Path $root 'src/ScarWinAdmin') -Destination $OutputDirectory -Recurse -Force
Write-Output "Built artifacts in $OutputDirectory"
