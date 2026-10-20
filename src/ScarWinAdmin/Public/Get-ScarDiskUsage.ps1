function Get-ScarDiskUsage {
<#
.SYNOPSIS
Reports volume capacity and bounded file usage within an explicitly selected directory.
.DESCRIPTION
Read-only disk diagnostics. File enumeration is opt-in with -Path; scans are bounded by MaxItems, MaxDepth and TimeoutSeconds. Results with skipped or inaccessible paths are Partial, never Complete.
.EXAMPLE
Get-ScarDiskUsage
.EXAMPLE
Get-ScarDiskUsage -Path C:\Logs -MaxDepth 2 -MaxItems 10000 -TimeoutSeconds 20
#>
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
if($CriticalFreePercent -gt $WarningFreePercent) { throw 'CriticalFreePercent cannot exceed WarningFreePercent.' }
if($env:OS -ne 'Windows_NT') { throw 'This utility requires Windows.' }
$errors=@()
$volumes=@()
try {
 foreach($d in @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop)) {
  if($null -eq $d.Size -or [double]$d.Size -le 0) { continue }
  $free=[double]$d.FreeSpace
  $pct=[math]::Round(100*$free/[double]$d.Size,2)
  $severity=if($pct -le $CriticalFreePercent){'Critical'}elseif($pct -le $WarningFreePercent){'Warning'}else{'Informational'}
  $volumes+= [pscustomobject]@{ Drive=$d.DeviceID; SizeBytes=[long]$d.Size; FreeBytes=[long]$d.FreeSpace; FreePercent=$pct; Severity=$severity }
 }
} catch { $errors+=('Volume inventory: '+$_.Exception.Message) }
$files=@()
$scanned=0
$truncated=$false
$scannedBytes=[long]0
if($PSBoundParameters.ContainsKey('Path')) {
 try {
  $root=(Get-Item -LiteralPath $Path -ErrorAction Stop)
  if(-not $root.PSIsContainer){ throw 'Path must refer to a directory.' }
  $queue=New-Object 'System.Collections.Generic.Queue[object]'
  $queue.Enqueue([pscustomobject]@{ Directory=$root.FullName; Depth=0 })
  $timer=[Diagnostics.Stopwatch]::StartNew()
  while($queue.Count -gt 0) {
   if($timer.Elapsed.TotalSeconds -ge $TimeoutSeconds){$truncated=$true;break}
   $entry=$queue.Dequeue()
   try {
    $children=Get-ChildItem -LiteralPath $entry.Directory -Force -ErrorAction Stop
    foreach($item in $children) {
     if($timer.Elapsed.TotalSeconds -ge $TimeoutSeconds -or $scanned -ge $MaxItems){$truncated=$true;break}
     $scanned++
     if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
     if($item.PSIsContainer) {
      if($entry.Depth -lt $MaxDepth){ $queue.Enqueue([pscustomobject]@{Directory=$item.FullName;Depth=$entry.Depth+1}) }
      else { $truncated=$true }
     } else {
      $scannedBytes += [long]$item.Length
      $files+= [pscustomobject]@{Path=$item.FullName;Bytes=[long]$item.Length}
     }
    }
   } catch { $errors+=('Directory '+$entry.Directory+': '+$_.Exception.Message) }
   if($truncated -and ($scanned -ge $MaxItems -or $timer.Elapsed.TotalSeconds -ge $TimeoutSeconds)){break}
  }
 } catch { $errors+=('Scan: '+$_.Exception.Message) }
}
$topFiles=@($files | Sort-Object Bytes -Descending | Select-Object -First $Top)
$status=if($errors.Count -gt 0 -or $truncated){'Partial'}else{'Complete'}
[pscustomobject]@{
 PSTypeName='ScarWinAdmin.DiskUsageResult'
 SchemaVersion='1.0'
 Tool='ScarWinAdmin.DiskUsage'
 ComputerName=$env:COMPUTERNAME
 CollectedAtUtc=[datetime]::UtcNow.ToString('o')
 CollectionStatus=$status
 Volumes=@($volumes)
 ScanPath=$(if($PSBoundParameters.ContainsKey('Path')){$Path}else{$null})
 ScannedItems=$scanned
 ScannedFileBytes=$scannedBytes
 TopFiles=$topFiles
 ScanTruncated=$truncated
 CollectionErrors=@($errors)
}
}
