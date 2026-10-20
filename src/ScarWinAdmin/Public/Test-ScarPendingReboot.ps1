function Test-ScarPendingReboot {
<#
.SYNOPSIS
Reports Windows pending-reboot indicators without making changes.
.DESCRIPTION
Returns the individual indicator results and an overall Pending, NotDetected, or Indeterminate assessment.
.EXAMPLE
Test-ScarPendingReboot | ConvertTo-Json -Depth 6
#>
[CmdletBinding()]
param()
$checks = [System.Collections.Generic.List[object]]::new()
function Add-Indicator {
 param([string]$Name,[scriptblock]$Probe)
 try {
  $detected = [bool](& $Probe)
  $checks.Add([pscustomobject]@{ Name=$Name; Status=$(if($detected){'Detected'}else{'NotDetected'}); Error=$null })
 } catch {
  $checks.Add([pscustomobject]@{ Name=$Name; Status='Indeterminate'; Error=$_.Exception.Message })
 }
}
if ($env:OS -ne 'Windows_NT') { throw 'This utility requires Windows.' }
Add-Indicator 'CBS.RebootPending' { Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending' -ErrorAction Stop }
Add-Indicator 'CBS.RebootInProgress' { Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootInProgress' -ErrorAction Stop }
Add-Indicator 'WindowsUpdate.RebootRequired' { Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired' -ErrorAction Stop }
Add-Indicator 'SessionManager.PendingFileRenameOperations' {
 # Read the existing key first: access/provider errors must propagate to Add-Indicator.
 $p=Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction Stop
 $value=$p.PSObject.Properties['PendingFileRenameOperations']
 if ($null -eq $value -or $null -eq $value.Value) { return $false }
 return (@($value.Value).Count -gt 0)
}
Add-Indicator 'ComputerRename.Pending' {
 $current=(Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' -Name ComputerName -ErrorAction Stop).ComputerName
 $pending=(Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -Name ComputerName -ErrorAction Stop).ComputerName
 return ($current -ne $pending)
}
$statuses=@($checks | ForEach-Object { $_.Status })
$status=if($statuses -contains 'Detected'){'Pending'}elseif($statuses -contains 'Indeterminate'){'Indeterminate'}else{'NotDetected'}
[pscustomobject]@{
 PSTypeName='ScarWinAdmin.PendingRebootResult'
 SchemaVersion='1.0'
 Tool='ScarWinAdmin.PendingReboot'
 ComputerName=$env:COMPUTERNAME
 CollectedAtUtc=[datetime]::UtcNow.ToString('o')
 Status=$status
 Indicators=@($checks)
}
}
