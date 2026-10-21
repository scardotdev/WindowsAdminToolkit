[CmdletBinding()]
param([string]$OutputDirectory)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
# $PSScriptRoot is empty inside param defaults on Windows PowerShell 5.1, so default here.
if (-not $OutputDirectory) { $OutputDirectory=Join-Path $root 'out' }
$module=Join-Path $root 'src/ScarWinAdmin/Public/Test-ScarPendingReboot.ps1'
$dest=Join-Path $OutputDirectory 'scripts/maintenance'
New-Item -ItemType Directory -Force -Path $dest | Out-Null
$script = "# Generated from src/ScarWinAdmin/Public/Test-ScarPendingReboot.ps1. Do not edit.`r`n" + (Get-Content -Raw $module) + "`r`nTest-ScarPendingReboot`r`n"
Set-Content -LiteralPath (Join-Path $dest 'Test-PendingReboot.ps1') -Value $script -Encoding UTF8
$diskSource=Join-Path $root 'src/ScarWinAdmin/Public/Get-ScarDiskUsage.ps1'
$diskDest=Join-Path $OutputDirectory 'scripts/storage'
New-Item -ItemType Directory -Force -Path $diskDest | Out-Null
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
$eventSource=Join-Path $root 'src/ScarWinAdmin/Public/Get-ScarEventSummary.ps1'
$eventDest=Join-Path $OutputDirectory 'scripts/diagnostics'
New-Item -ItemType Directory -Force -Path $eventDest | Out-Null
$eventWrapper=@'
[CmdletBinding()]
param(
 [ValidateNotNullOrEmpty()][string[]]$LogName=@('System','Application'),
 [ValidateRange(1,8760)][int]$LookbackHours=24,
 [ValidateRange(1,100000)][int]$MaxEventsPerLog=1000,
 [ValidateRange(1,100)][int]$Top=20,
 [ValidateRange(1,10)][int]$SamplesPerGroup=3,
 [ValidateRange(1,3600)][int]$TimeoutSeconds=30,
 [ValidateSet(1,2,3,4,5)][int[]]$Level=@(1,2,3),
 [int[]]$EventId,
 [string[]]$ProviderName
)
'@
$eventScript=$eventWrapper + "`r`n" + (Get-Content -Raw $eventSource) + "`r`nGet-ScarEventSummary @PSBoundParameters`r`n"
Set-Content -LiteralPath (Join-Path $eventDest 'Get-WindowsEventSummary.ps1') -Value $eventScript -Encoding UTF8
$networkSource=Join-Path $root 'src/ScarWinAdmin/Public/Get-ScarNetworkDiagnostics.ps1'
$networkDest=Join-Path $OutputDirectory 'scripts/network'
New-Item -ItemType Directory -Force -Path $networkDest | Out-Null
$networkWrapper=@'
[CmdletBinding()]
param(
 [string[]]$DnsTarget=@(),
 [string[]]$TcpTarget=@(),
 [ValidateRange(1,65535)][int[]]$TcpPort=@(),
 [ValidateRange(1,120)][int]$TimeoutSeconds=30,
 [ValidateRange(1,30)][int]$PerTestTimeoutSeconds=5,
 [switch]$SkipRoutes,
 [switch]$SkipProxy,
 [switch]$IncludeIPv6
)
'@
$networkScript=$networkWrapper + "`r`n" + (Get-Content -Raw $networkSource) + "`r`nGet-ScarNetworkDiagnostics @PSBoundParameters`r`n"
Set-Content -LiteralPath (Join-Path $networkDest 'Get-NetworkDiagnostics.ps1') -Value $networkScript -Encoding UTF8
$healthDest=Join-Path $OutputDirectory 'scripts/health'
New-Item -ItemType Directory -Force -Path $healthDest | Out-Null
$healthWrapper=@'
[CmdletBinding()]
param(
 [ValidateRange(1,168)][int]$EventLookbackHours=24,
 [ValidateRange(1,5000)][int]$MaxEventsPerLog=500,
 [string[]]$ServiceName=@(),
 [ValidateRange(0,100)][double]$WarningDiskFreePercent=20,
 [ValidateRange(0,100)][double]$CriticalDiskFreePercent=10,
 [ValidateRange(0,100)][double]$WarningMemoryUsedPercent=85,
 [ValidateRange(0,100)][double]$CriticalMemoryUsedPercent=95,
 [ValidateRange(0,100)][double]$WarningCpuPercent=90,
 [ValidateRange(10,600)][int]$TimeoutSeconds=90,
 [switch]$IncludeNetwork,
 [string]$OutputJsonPath,
 [string]$OutputHtmlPath,
 [switch]$Force
)
'@
$dependencies=@('Test-ScarPendingReboot','Get-ScarDiskUsage','Get-ScarEventSummary','Get-ScarNetworkDiagnostics','Get-ScarWindowsHealth')
$healthSources=@($dependencies | ForEach-Object { Get-Content -Raw (Join-Path $root ('src/ScarWinAdmin/Public/'+$_+'.ps1')) })
$healthScript=$healthWrapper + "`r`n" + ($healthSources -join "`r`n") + "`r`nGet-ScarWindowsHealth @PSBoundParameters`r`n"
Set-Content -LiteralPath (Join-Path $healthDest 'Get-WindowsHealth.ps1') -Value $healthScript -Encoding UTF8
Copy-Item -Path (Join-Path $root 'src/ScarWinAdmin') -Destination $OutputDirectory -Recurse -Force
Write-Output "Built artifacts in $OutputDirectory"
