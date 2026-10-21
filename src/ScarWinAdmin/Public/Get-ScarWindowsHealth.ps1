function Get-ScarWindowsHealth {
<#
.SYNOPSIS
Collects an evidence-backed, read-only Windows health snapshot.
#>
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
if($CriticalDiskFreePercent -gt $WarningDiskFreePercent){throw 'CriticalDiskFreePercent cannot exceed WarningDiskFreePercent.'}
if($CriticalMemoryUsedPercent -lt $WarningMemoryUsedPercent){throw 'CriticalMemoryUsedPercent cannot be below WarningMemoryUsedPercent.'}
if($ServiceName.Count -gt 30){throw 'At most 30 services are supported.'}
if($env:OS -ne 'Windows_NT'){throw 'This utility requires Windows.'}
foreach($path in @($OutputJsonPath,$OutputHtmlPath)){
 if(-not [string]::IsNullOrEmpty($path) -and (Test-Path -LiteralPath $path) -and -not $Force){throw "Output already exists (specify -Force): $path"}
}
$clock=[Diagnostics.Stopwatch]::StartNew()
$sources=[System.Collections.Generic.List[object]]::new()
$errors=[System.Collections.Generic.List[object]]::new()
$findings=[System.Collections.Generic.List[object]]::new()
$hostInfo=$null;$cpu=$null;$memory=$null;$disk=$null;$reboot=$null;$events=$null;$services=@();$network=$null
$timedOut=$false
function Add-HealthSource {
 param([string]$Name,[string]$Status,[string]$Message)
 $sources.Add([pscustomobject]@{Source=$Name;Status=$Status;Error=$Message})
 if($Status -in @('Unavailable','Partial')){$errors.Add([pscustomobject]@{Source=$Name;Message=$Message})}
}
function Add-HealthFinding {
 param([string]$Id,[string]$Severity,[string]$Title,[string]$Evidence,[string]$Source,[string]$NextStep)
 $findings.Add([pscustomobject]@{FindingId=$Id;Severity=$Severity;Title=$Title;Evidence=$Evidence;Source=$Source;ObservedAtUtc=[datetime]::UtcNow.ToString('o');SuggestedNextStep=$NextStep})
}
function Test-HealthBudget {return ($clock.Elapsed.TotalSeconds -lt $TimeoutSeconds)}
if(Test-HealthBudget){
 try {
  $os=Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
  $computer=Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
  $uptime=$null
  if($os.LastBootUpTime){$uptime=[math]::Round(([datetime]::Now - [datetime]$os.LastBootUpTime).TotalHours,2)}
  $hostInfo=[pscustomobject]@{Caption=$os.Caption;Version=$os.Version;BuildNumber=$os.BuildNumber;LastBootUpTime=$os.LastBootUpTime;UptimeHours=$uptime;Manufacturer=$computer.Manufacturer;Model=$computer.Model}
  Add-HealthSource 'Host' 'Complete' $null
  $total=[double]$computer.TotalPhysicalMemory;$free=[double]$os.FreePhysicalMemory*1024
  if($total -le 0){throw 'Invalid physical memory capacity.'}
  $used=[math]::Round((1-$free/$total)*100,2)
  $memory=[pscustomobject]@{TotalBytes=[long]$total;AvailableBytes=[long]$free;UsedPercent=$used;SampledAtUtc=[datetime]::UtcNow.ToString('o');Source='Win32_OperatingSystem'}
  Add-HealthSource 'Memory' 'Complete' $null
  if($used -ge $CriticalMemoryUsedPercent){Add-HealthFinding 'memory.critical' 'Critical' 'Memory usage above critical threshold' "$used percent used" 'Memory' 'Review memory consumers and workload.'}
  elseif($used -ge $WarningMemoryUsedPercent){Add-HealthFinding 'memory.warning' 'Warning' 'Memory usage elevated' "$used percent used" 'Memory' 'Review memory consumers.'}
 } catch {
  if($null -eq $hostInfo){Add-HealthSource 'Host' 'Unavailable' $_.Exception.Message}
  if($null -eq $memory){Add-HealthSource 'Memory' 'Unavailable' $_.Exception.Message}
 }
}
if(Test-HealthBudget){
 try {
  $sample=Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop
  $values=@($sample | ForEach-Object {[double]$_.LoadPercentage})
  if($values.Count -eq 0){throw 'No CPU samples available.'}
  $load=[math]::Round(($values | Measure-Object -Average).Average,2)
  $cpu=[pscustomobject]@{UsedPercent=$load;SampledAtUtc=[datetime]::UtcNow.ToString('o');Source='Win32_Processor.LoadPercentage';SampleType='Instantaneous'}
  Add-HealthSource 'Cpu' 'Complete' $null
  if($load -ge $WarningCpuPercent){Add-HealthFinding 'cpu.warning' 'Warning' 'CPU usage elevated in one sample' "$load percent, instantaneous" 'Cpu' 'Collect additional samples before attributing cause.'}
 } catch {Add-HealthSource 'Cpu' 'Unavailable' $_.Exception.Message}
}
if(Test-HealthBudget){
 try {
  $disk=Get-ScarDiskUsage -WarningFreePercent $WarningDiskFreePercent -CriticalFreePercent $CriticalDiskFreePercent
  Add-HealthSource 'Disk' $(if($disk.CollectionStatus -eq 'Complete'){'Complete'}else{'Partial'}) $(if($disk.CollectionStatus -eq 'Complete'){$null}else{'Disk utility returned partial coverage.'})
  foreach($volume in $disk.Volumes){
   if($volume.Severity -in @('Critical','Warning')){Add-HealthFinding ("disk."+$volume.Drive) $volume.Severity ("Low free space on "+$volume.Drive) ("Free: "+$volume.FreePercent+" percent") 'Disk' 'Review storage consumption and capacity.'}
  }
 } catch {Add-HealthSource 'Disk' 'Unavailable' $_.Exception.Message}
}
if(Test-HealthBudget){
 try {
  $reboot=Test-ScarPendingReboot
  $state=if($reboot.Status -eq 'Indeterminate'){'Partial'}else{'Complete'}
  Add-HealthSource 'Reboot' $state $(if($state -eq 'Partial'){'Pending reboot assessment indeterminate.'}else{$null})
  if($reboot.Status -eq 'Pending'){Add-HealthFinding 'reboot.pending' 'Warning' 'Restart pending' 'One or more reboot indicators were detected.' 'Reboot' 'Plan an approved maintenance restart.'}
 } catch {Add-HealthSource 'Reboot' 'Unavailable' $_.Exception.Message}
}
if(Test-HealthBudget){
 try {
  $remain=[math]::Max(1,[math]::Min(3600,[int]($TimeoutSeconds-$clock.Elapsed.TotalSeconds)))
  $events=Get-ScarEventSummary -LookbackHours $EventLookbackHours -MaxEventsPerLog $MaxEventsPerLog -TimeoutSeconds $remain
  Add-HealthSource 'Events' $(if($events.CollectionStatus -eq 'Complete'){'Complete'}else{'Partial'}) $(if($events.CollectionStatus -eq 'Complete'){$null}else{'Event query incomplete.'})
 } catch {Add-HealthSource 'Events' 'Unavailable' $_.Exception.Message}
}
if($ServiceName.Count -gt 0 -and (Test-HealthBudget)){
 foreach($name in $ServiceName){
  try {
   $service=Get-Service -Name $name -ErrorAction Stop
   $services+= [pscustomobject]@{Name=$name;Status=[string]$service.Status;DisplayName=$service.DisplayName}
  } catch {
   $services+= [pscustomobject]@{Name=$name;Status='Unavailable';DisplayName=$null}
   $errors.Add([pscustomobject]@{Source='Services';Message=($_.Exception.Message)})
  }
 }
 Add-HealthSource 'Services' $(if(@($services | Where-Object Status -eq 'Unavailable').Count){'Partial'}else{'Complete'}) $(if(@($services | Where-Object Status -eq 'Unavailable').Count){'Some services unavailable.'}else{$null})
} elseif($ServiceName.Count -eq 0){Add-HealthSource 'Services' 'Skipped' $null}
if($IncludeNetwork -and (Test-HealthBudget)){
 try{
  $network=Get-ScarNetworkDiagnostics -TimeoutSeconds ([math]::Max(1,[math]::Min(120,[int]($TimeoutSeconds-$clock.Elapsed.TotalSeconds))))
  Add-HealthSource 'Network' $(if($network.CollectionStatus -eq 'Complete'){'Complete'}else{'Partial'}) $(if($network.CollectionStatus -eq 'Complete'){$null}else{'Network inventory incomplete.'})
 }catch{Add-HealthSource 'Network' 'Unavailable' $_.Exception.Message}
} elseif(-not $IncludeNetwork){Add-HealthSource 'Network' 'Skipped' $null}
if(-not (Test-HealthBudget)){$timedOut=$true;Add-HealthSource 'Budget' 'Partial' 'Overall time budget exhausted.'}
$partial=$timedOut -or @($sources | Where-Object {$_.Status -in @('Unavailable','Partial')}).Count -gt 0
$prioritized=@($findings.ToArray() | Sort-Object @{Expression={switch($_.Severity){'Critical'{0}'Warning'{1}default{2}}}},Source,FindingId)
$health=if(@($prioritized | Where-Object Severity -eq 'Critical').Count){'Critical'}elseif(@($prioritized | Where-Object Severity -eq 'Warning').Count){'Warning'}elseif($partial){'Unknown'}else{'NoFindings'}
$result=[pscustomobject]@{
 PSTypeName='ScarWinAdmin.WindowsHealthResult';SchemaVersion='1.0';Tool='ScarWinAdmin.WindowsHealth'
 ComputerName=$env:COMPUTERNAME;CollectedAtUtc=[datetime]::UtcNow.ToString('o');DurationMs=$clock.ElapsedMilliseconds
 CollectionStatus=$(if($partial){'Partial'}else{'Complete'});HealthStatus=$health
 SourceStatus=$sources.ToArray();Host=$hostInfo;Cpu=$cpu;Memory=$memory;Disk=$disk;Reboot=$reboot;Events=$events
 Services=@($services);Network=$network;Findings=$prioritized;CollectionErrors=$errors.ToArray();TimedOut=$timedOut
}
foreach($entry in @(@{Path=$OutputJsonPath;Kind='Json'},@{Path=$OutputHtmlPath;Kind='Html'})){
 if([string]::IsNullOrWhiteSpace($entry.Path)){continue}
 try {
  if($entry.Kind -eq 'Json'){$value=ConvertTo-Json -InputObject $result -Depth 16}
  else {
   $encode=[System.Net.WebUtility]
   $rows=foreach($finding in $result.Findings){
    '<tr><td>'+ $encode::HtmlEncode($finding.Severity) +'</td><td>'+ $encode::HtmlEncode($finding.Title) +'</td><td>'+ $encode::HtmlEncode($finding.Evidence) +'</td></tr>'
   }
   $value='<!doctype html><html><head><meta charset="utf-8"><title>Windows Health Snapshot</title></head><body><h1>Windows Health Snapshot</h1><p>Collection: '+$encode::HtmlEncode($result.CollectionStatus)+' | Health: '+$encode::HtmlEncode($result.HealthStatus)+'</p><table><tr><th>Severity</th><th>Finding</th><th>Evidence</th></tr>'+($rows -join '')+'</table></body></html>'
  }
  $destination=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($entry.Path)
  if((Test-Path -LiteralPath $destination) -and -not $Force){throw 'Output already exists.'}
  [IO.File]::WriteAllText($destination,[string]$value,[Text.UTF8Encoding]::new($false))
 }catch{$errors.Add([pscustomobject]@{Source='Report';Message=$_.Exception.Message});$result.CollectionErrors=$errors.ToArray();$result.CollectionStatus='Partial'}
}
$result
}
