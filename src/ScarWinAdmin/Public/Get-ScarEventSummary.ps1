function Get-ScarEventSummary {
<#
.SYNOPSIS
Summarizes recurring events from selected Windows event logs.
.DESCRIPTION
Read-only, bounded event-log triage with explicit per-log collection errors. Severity and frequency are descriptive, not root-cause assessments.
.EXAMPLE
Get-ScarEventSummary -LookbackHours 24 -MaxEventsPerLog 500
.EXAMPLE
Get-ScarEventSummary -LogName System -EventId 7031,7034 -ProviderName 'Service Control Manager'
#>
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
if($env:OS -ne 'Windows_NT'){throw 'This utility requires Windows.'}
$start=[datetime]::UtcNow.AddHours(-$LookbackHours)
$clock=[Diagnostics.Stopwatch]::StartNew()
$raw=New-Object 'System.Collections.Generic.List[object]'
$issues=New-Object 'System.Collections.Generic.List[object]'
$perLog=New-Object 'System.Collections.Generic.List[object]'
$timedOut=$false
foreach($log in $LogName){
 if($clock.Elapsed.TotalSeconds -ge $TimeoutSeconds){
  $timedOut=$true
  $issues.Add([pscustomobject]@{LogName=$log; Error='Time budget exhausted before querying log.'})
  continue
 }
 $filter=@{LogName=$log;StartTime=$start;Level=$Level}
 if($PSBoundParameters.ContainsKey('EventId')){$filter.ID=$EventId}
 if($PSBoundParameters.ContainsKey('ProviderName')){$filter.ProviderName=$ProviderName}
 try {
  # Read one extra event to distinguish a capped result from a complete query.
  $events=@(Get-WinEvent -FilterHashtable $filter -MaxEvents ($MaxEventsPerLog+1) -ErrorAction Stop)
  $capped=$events.Count -gt $MaxEventsPerLog
  $count=0
  foreach($event in $events){
   if($count -ge $MaxEventsPerLog){break}
   if($clock.Elapsed.TotalSeconds -ge $TimeoutSeconds){$timedOut=$true;break}
   $raw.Add([pscustomobject]@{
    LogName=$log;ProviderName=[string]$event.ProviderName;EventId=[int]$event.Id
    Level=[int]$event.Level;TimeCreated=$event.TimeCreated
    RecordId=$event.RecordId;MachineName=$event.MachineName
    Message=[string]$event.Message
   })
   $count++
  }
  $perLog.Add([pscustomobject]@{LogName=$log;Collected=$count;Capped=$capped;Status=$(if($capped -or $timedOut){'Partial'}else{'Complete'})})
 } catch {
  # 0x80070016 / 15007 can mean no matching events: avoid interpreting access failures as empty logs.
  $err=$_
  if($err.FullyQualifiedErrorId -match 'NoMatchingEventsFound' -or $err.Exception.Message -match 'No events were found that match'){
   if($clock.Elapsed.TotalSeconds -ge $TimeoutSeconds){$timedOut=$true}
   $perLog.Add([pscustomobject]@{LogName=$log;Collected=0;Capped=$false;Status=$(if($timedOut){'Partial'}else{'Complete'})})
  } else {
   $issues.Add([pscustomobject]@{LogName=$log;Error=$err.Exception.Message})
   $perLog.Add([pscustomobject]@{LogName=$log;Collected=0;Capped=$false;Status='Failed'})
  }
 }
}
$groups=@($raw | Group-Object LogName,ProviderName,EventId,Level | ForEach-Object {
 $items=@($_.Group | Sort-Object TimeCreated -Descending)
 $first=$items | Sort-Object TimeCreated | Select-Object -First 1
 [pscustomobject]@{
  LogName=$items[0].LogName
  ProviderName=$items[0].ProviderName
  EventId=$items[0].EventId
  Level=$items[0].Level
  Count=$items.Count
  FirstSeenUtc=$first.TimeCreated.ToUniversalTime().ToString('o')
  LastSeenUtc=$items[0].TimeCreated.ToUniversalTime().ToString('o')
  Samples=@($items | Select-Object -First $SamplesPerGroup | ForEach-Object {
   [pscustomobject]@{TimeUtc=$_.TimeCreated.ToUniversalTime().ToString('o');RecordId=$_.RecordId;Message=$_.Message}
  })
 }
} | Sort-Object Count -Descending | Select-Object -First $Top)
$status=if($issues.Count -gt 0 -or $timedOut -or @($perLog | Where-Object Status -ne 'Complete').Count -gt 0){'Partial'}else{'Complete'}
[pscustomobject]@{
 PSTypeName='ScarWinAdmin.EventSummaryResult'
 SchemaVersion='1.0'
 Tool='ScarWinAdmin.EventSummary'
 ComputerName=$env:COMPUTERNAME
 CollectedAtUtc=[datetime]::UtcNow.ToString('o')
 CollectionStatus=$status
 LookbackHours=$LookbackHours
 TimedOut=$timedOut
 Logs=$perLog.ToArray()
 GroupedEvents=$groups
 CollectionErrors=$issues.ToArray()
}
}
