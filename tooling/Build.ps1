[CmdletBinding()]
param([string]$OutputDirectory=(Join-Path (Split-Path -Parent $PSScriptRoot) 'out'))
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$module=Join-Path $root 'src/ScarWinAdmin/Public/Test-ScarPendingReboot.ps1'
$dest=Join-Path $OutputDirectory 'scripts/maintenance'
New-Item -ItemType Directory -Force -Path $dest | Out-Null
$script = "# Generated from src/ScarWinAdmin/Public/Test-ScarPendingReboot.ps1. Do not edit.`r`n" + (Get-Content -Raw $module) + "`r`nTest-ScarPendingReboot`r`n"
Set-Content -LiteralPath (Join-Path $dest 'Test-PendingReboot.ps1') -Value $script -Encoding UTF8
Copy-Item -Path (Join-Path $root 'src/ScarWinAdmin') -Destination $OutputDirectory -Recurse -Force
Write-Output "Built artifacts in $OutputDirectory"
