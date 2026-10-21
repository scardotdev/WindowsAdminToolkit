function Get-ScarWindowsHealth {
<#
.SYNOPSIS
Collects an evidence-backed, read-only Windows health snapshot.
.DESCRIPTION
Aggregates the toolkit's disk, reboot, event and (optionally) network utilities with instantaneous OS, CPU, memory and explicitly named service state.
CollectionStatus (was evidence gathered?) and HealthStatus (what was observed?) are independent. Report files are written only when -OutputJsonPath/-OutputHtmlPath are given; their outcomes are returned in ReportOutputs and never change CollectionStatus.
.EXAMPLE
Get-ScarWindowsHealth -ServiceName 'Spooler','W32Time' -OutputJsonPath .\health.json
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
foreach($name in $ServiceName){
 if([string]::IsNullOrWhiteSpace($name) -or $name -match '[*?\[\]]'){throw "ServiceName must be an explicit service name without wildcards: '$name'"}
}
if($env:OS -ne 'Windows_NT'){throw 'This utility requires Windows.'}
# Validate output locations before any collection so a bad path fails fast.
$reportRequests=@()
foreach($request in @(@{Path=$OutputJsonPath;Kind='Json'},@{Path=$OutputHtmlPath;Kind='Html'})){
 if([string]::IsNullOrWhiteSpace($request.Path)){continue}
 $full=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($request.Path)
 if(-not (Test-Path -LiteralPath (Split-Path -Parent $full) -PathType Container)){throw "Output directory does not exist: $(Split-Path -Parent $full)"}
 if((Test-Path -LiteralPath $full) -and -not $Force){throw "Output already exists (specify -Force): $full"}
 $reportRequests+= @{Kind=$request.Kind;Path=$full}
}
if($reportRequests.Count -eq 2 -and $reportRequests[0].Path -ieq $reportRequests[1].Path){throw 'OutputJsonPath and OutputHtmlPath must differ.'}
$clock=[Diagnostics.Stopwatch]::StartNew()
$lap=[Diagnostics.Stopwatch]::StartNew()
$sources=[System.Collections.Generic.List[object]]::new()
$errors=[System.Collections.Generic.List[object]]::new()
$findings=[System.Collections.Generic.List[object]]::new()
$hostInfo=$null;$cpu=$null;$memory=$null;$disk=$null;$reboot=$null;$events=$null;$services=@();$network=$null
$timedOut=$false
function Add-HealthSource {
 param([string]$Name,[string]$Status,[string]$Message)
 $sources.Add([pscustomobject]@{Source=$Name;Status=$Status;ElapsedMs=$lap.ElapsedMilliseconds;Error=$Message})
 $lap.Restart()
 if($Status -in @('Unavailable','Partial')){$errors.Add([pscustomobject]@{Source=$Name;Message=$Message})}
}
function Add-HealthFinding {
 param([string]$Id,[string]$Severity,[string]$Title,[string]$Evidence,[string]$Source,[string]$NextStep)
 $findings.Add([pscustomobject]@{FindingId=$Id;Severity=$Severity;Title=$Title;Evidence=$Evidence;Source=$Source;ObservedAtUtc=[datetime]::UtcNow.ToString('o');SuggestedNextStep=$NextStep})
}
function Test-HealthBudget {return ($clock.Elapsed.TotalSeconds -lt $TimeoutSeconds)}
function Get-ChildDetail {
 param([object]$Child,[string]$Default)
 $texts=@($Child.CollectionErrors | Where-Object {$null -ne $_} | ForEach-Object {
  if($_ -is [string]){$_}elseif($_.Error){[string]$_.Error}elseif($_.Message){[string]$_.Message}else{[string]$_}
 })
 if($texts.Count -eq 0){return $Default}
 return ($Default+' '+(($texts | Select-Object -First 3) -join '; '))
}
function Skip-HealthSource {param([string]$Name) Add-HealthSource $Name 'Skipped' 'Time budget exhausted before collection.'}

# Host and memory (independent of the child utilities).
if(Test-HealthBudget){
 try {
  $os=Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
  $computer=Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
  $bootUtc=$null;$uptime=$null
  if($os.LastBootUpTime){$bootUtc=([datetime]$os.LastBootUpTime).ToUniversalTime();$uptime=[math]::Round(([datetime]::UtcNow - $bootUtc).TotalHours,2)}
  $hostInfo=[pscustomobject]@{Caption=$os.Caption;Version=$os.Version;BuildNumber=$os.BuildNumber;LastBootUpTimeUtc=$(if($bootUtc){$bootUtc.ToString('o')}else{$null});UptimeHours=$uptime;Manufacturer=$computer.Manufacturer;Model=$computer.Model}
  Add-HealthSource 'Host' 'Complete' $null
  # Reject missing/invalid measurements instead of letting casts turn them into zero.
  if($null -eq $os.FreePhysicalMemory -or $null -eq $computer.TotalPhysicalMemory){throw 'Physical memory measurement is missing.'}
  $total=[double]$computer.TotalPhysicalMemory;$free=[double]$os.FreePhysicalMemory*1024
  if($total -le 0 -or $free -lt 0 -or $free -gt $total){throw 'Invalid physical memory measurement.'}
  $used=[math]::Round((1-$free/$total)*100,2)
  $memory=[pscustomobject]@{TotalBytes=[long]$total;AvailableBytes=[long]$free;UsedPercent=$used;SampledAtUtc=[datetime]::UtcNow.ToString('o');Source='Win32_OperatingSystem'}
  Add-HealthSource 'Memory' 'Complete' $null
  if($used -ge $CriticalMemoryUsedPercent){Add-HealthFinding 'memory.critical' 'Critical' 'Memory usage above critical threshold' "$used percent used" 'Memory' 'Review memory consumers and workload.'}
  elseif($used -ge $WarningMemoryUsedPercent){Add-HealthFinding 'memory.warning' 'Warning' 'Memory usage elevated' "$used percent used" 'Memory' 'Review memory consumers.'}
 } catch {
  if($null -eq $hostInfo){Add-HealthSource 'Host' 'Unavailable' $_.Exception.Message}
  if($null -eq $memory){Add-HealthSource 'Memory' 'Unavailable' $_.Exception.Message}
 }
} else {Skip-HealthSource 'Host';Skip-HealthSource 'Memory'}
if(Test-HealthBudget){
 try {
  $sample=@(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop)
  $values=@($sample | Where-Object {$null -ne $_.LoadPercentage -and [double]$_.LoadPercentage -ge 0 -and [double]$_.LoadPercentage -le 100} | ForEach-Object {[double]$_.LoadPercentage})
  if($values.Count -eq 0){throw 'No valid CPU load samples available.'}
  $load=[math]::Round(($values | Measure-Object -Average).Average,2)
  $cpu=[pscustomobject]@{UsedPercent=$load;SamplesUsed=$values.Count;SamplesReturned=$sample.Count;SampledAtUtc=[datetime]::UtcNow.ToString('o');Source='Win32_Processor.LoadPercentage';SampleType='Instantaneous'}
  if($values.Count -lt $sample.Count){Add-HealthSource 'Cpu' 'Partial' "Only $($values.Count) of $($sample.Count) processors reported a valid load."}
  else {Add-HealthSource 'Cpu' 'Complete' $null}
  if($load -ge $WarningCpuPercent){Add-HealthFinding 'cpu.warning' 'Warning' 'CPU usage elevated in one sample' "$load percent, instantaneous" 'Cpu' 'Collect additional samples before attributing cause.'}
 } catch {Add-HealthSource 'Cpu' 'Unavailable' $_.Exception.Message}
} else {Skip-HealthSource 'Cpu'}
if(Test-HealthBudget){
 try {
  $disk=Get-ScarDiskUsage -WarningFreePercent $WarningDiskFreePercent -CriticalFreePercent $CriticalDiskFreePercent
  if($disk.CollectionStatus -eq 'Complete'){Add-HealthSource 'Disk' 'Complete' $null}
  else {Add-HealthSource 'Disk' 'Partial' (Get-ChildDetail $disk 'Disk utility returned partial coverage.')}
  foreach($volume in $disk.Volumes){
   if($volume.Severity -in @('Critical','Warning')){Add-HealthFinding ("disk."+$volume.Drive) $volume.Severity ("Low free space on "+$volume.Drive) ("Free: "+$volume.FreePercent+" percent") 'Disk' 'Review storage consumption and capacity.'}
  }
 } catch {Add-HealthSource 'Disk' 'Unavailable' $_.Exception.Message}
} else {Skip-HealthSource 'Disk'}
if(Test-HealthBudget){
 try {
  $reboot=Test-ScarPendingReboot
  # The utility ranks Detected above Indeterminate, so inspect the indicators themselves for coverage gaps.
  $unknown=@($reboot.Indicators | Where-Object {$_.Status -eq 'Indeterminate'})
  if($unknown.Count -gt 0 -or $reboot.Status -eq 'Indeterminate'){
   $detail='Reboot indicator coverage incomplete'+$(if($unknown.Count){': '+((($unknown | ForEach-Object {$_.Name+' ('+$_.Error+')'}) | Select-Object -First 3) -join '; ')}else{'.'})
   Add-HealthSource 'Reboot' 'Partial' $detail
   Add-HealthFinding 'reboot.indeterminate' 'Informational' 'Reboot assessment incomplete' $detail 'Reboot' 'Re-run with sufficient permissions to read the failed indicators.'
  } else {Add-HealthSource 'Reboot' 'Complete' $null}
  if($reboot.Status -eq 'Pending'){Add-HealthFinding 'reboot.pending' 'Warning' 'Restart pending' 'One or more reboot indicators were detected.' 'Reboot' 'Plan an approved maintenance restart.'}
 } catch {Add-HealthSource 'Reboot' 'Unavailable' $_.Exception.Message}
} else {Skip-HealthSource 'Reboot'}
if(Test-HealthBudget){
 try {
  $remain=[math]::Max(1,[math]::Min(3600,[int]($TimeoutSeconds-$clock.Elapsed.TotalSeconds)))
  $events=Get-ScarEventSummary -LookbackHours $EventLookbackHours -MaxEventsPerLog $MaxEventsPerLog -TimeoutSeconds $remain
  if($events.CollectionStatus -eq 'Complete'){Add-HealthSource 'Events' 'Complete' $null}
  else {Add-HealthSource 'Events' 'Partial' (Get-ChildDetail $events 'Event query incomplete.')}
 } catch {Add-HealthSource 'Events' 'Unavailable' $_.Exception.Message}
} else {Skip-HealthSource 'Events'}
if($ServiceName.Count -gt 0){
 # The budget is re-checked per lookup; remaining names are recorded as Skipped. A missing service is an observation, not a failure.
 foreach($name in $ServiceName){
  if(-not (Test-HealthBudget)){
   $services+= [pscustomobject]@{Name=$name;Status='Skipped';DisplayName=$null;Error='Time budget exhausted before lookup.'}
   continue
  }
  try {
   $service=@(Get-Service -Name $name -ErrorAction Stop)[0]
   $services+= [pscustomobject]@{Name=$name;Status=[string]$service.Status;DisplayName=$service.DisplayName;Error=$null}
  } catch {
   if($_.FullyQualifiedErrorId -like 'NoServiceFoundForGivenName*'){
    $services+= [pscustomobject]@{Name=$name;Status='NotFound';DisplayName=$null;Error=$null}
    Add-HealthFinding ("service."+$name+".notfound") 'Informational' ("Service not found: "+$name) 'No service with this name exists on the host.' 'Services' 'Confirm the service name is correct for this system.'
   } else {
    $services+= [pscustomobject]@{Name=$name;Status='Unavailable';DisplayName=$null;Error=$_.Exception.Message}
   }
  }
 }
 $gaps=@($services | Where-Object {$_.Status -in @('Unavailable','Skipped')})
 if($gaps.Count -gt 0){Add-HealthSource 'Services' 'Partial' (($gaps | Select-Object -First 3 | ForEach-Object {$_.Name+': '+$_.Error}) -join '; ')}
 else {Add-HealthSource 'Services' 'Complete' $null}
} else {Add-HealthSource 'Services' 'Skipped' $null}
if($IncludeNetwork){
 if(Test-HealthBudget){
  try{
   $network=Get-ScarNetworkDiagnostics -TimeoutSeconds ([math]::Max(1,[math]::Min(120,[int]($TimeoutSeconds-$clock.Elapsed.TotalSeconds))))
   if($network.CollectionStatus -eq 'Complete'){Add-HealthSource 'Network' 'Complete' $null}
   else {Add-HealthSource 'Network' 'Partial' (Get-ChildDetail $network 'Network inventory incomplete.')}
  }catch{Add-HealthSource 'Network' 'Unavailable' $_.Exception.Message}
 } else {Skip-HealthSource 'Network'}
} else {Add-HealthSource 'Network' 'Skipped' $null}
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
 ReportOutputs=@()
}
function ConvertTo-HealthHtml {
 param([object]$Report)
 function E([object]$v){[System.Net.WebUtility]::HtmlEncode([string]$v)}
 function Table([string[]]$Headers,[object[]]$Rows){
  $head=($Headers | ForEach-Object {'<th>'+(E $_)+'</th>'}) -join ''
  $body=($Rows | ForEach-Object {'<tr>'+((@($_) | ForEach-Object {'<td>'+(E $_)+'</td>'}) -join '')+'</tr>'}) -join ''
  '<table><tr>'+$head+'</tr>'+$body+'</table>'
 }
 $parts=New-Object 'System.Collections.Generic.List[string]'
 $parts.Add('<h1>Windows Health Snapshot</h1>')
 $parts.Add('<p>Computer: '+(E $Report.ComputerName)+' | Collected (UTC): '+(E $Report.CollectedAtUtc)+' | Duration: '+(E $Report.DurationMs)+' ms</p>')
 $parts.Add('<p>Collection: '+(E $Report.CollectionStatus)+' | Health: '+(E $Report.HealthStatus)+' | Timed out: '+(E $Report.TimedOut)+'</p>')
 $parts.Add('<p><em>This report may contain hostnames, service names and error text. Review it before sharing. Severity reflects configured thresholds and observed evidence, not a diagnosis.</em></p>')
 $parts.Add('<h2>Source coverage</h2>'+(Table @('Source','Status','Elapsed ms','Detail') @($Report.SourceStatus | ForEach-Object {,@($_.Source,$_.Status,$_.ElapsedMs,$_.Error)})))
 $parts.Add('<h2>Findings</h2>'+(Table @('Severity','Finding','Evidence','Source','Suggested next step') @($Report.Findings | ForEach-Object {,@($_.Severity,$_.Title,$_.Evidence,$_.Source,$_.SuggestedNextStep)})))
 $parts.Add('<h2>Collection errors</h2>'+(Table @('Source','Message') @($Report.CollectionErrors | ForEach-Object {,@($_.Source,$_.Message)})))
 $evidence=New-Object 'System.Collections.Generic.List[object]'
 if($Report.Host){$h=$Report.Host;$evidence.Add(@('Host',($h.Caption+' '+$h.Version+' build '+$h.BuildNumber),('Last boot (UTC) '+$h.LastBootUpTimeUtc+'; uptime '+$h.UptimeHours+' h; '+$h.Manufacturer+' '+$h.Model)))}
 if($Report.Cpu){$evidence.Add(@('CPU',([string]$Report.Cpu.UsedPercent+' percent'),('Single instantaneous sample at '+$Report.Cpu.SampledAtUtc)))}
 if($Report.Memory){$evidence.Add(@('Memory',([string]$Report.Memory.UsedPercent+' percent used'),([string]$Report.Memory.AvailableBytes+' of '+[string]$Report.Memory.TotalBytes+' bytes available')))}
 if($Report.Reboot){$evidence.Add(@('Reboot',[string]$Report.Reboot.Status,((@($Report.Reboot.Indicators) | ForEach-Object {[string]$_.Name+'='+[string]$_.Status}) -join '; ')))}
 if($Report.Disk){foreach($v in @($Report.Disk.Volumes)){$evidence.Add(@(('Disk '+$v.Drive),([string]$v.FreePercent+' percent free'),('Size '+$v.SizeBytes+' bytes; free '+$v.FreeBytes+' bytes; '+$v.Severity)))}}
 foreach($s in @($Report.Services)){$evidence.Add(@(('Service '+$s.Name),[string]$s.Status,[string]$s.DisplayName))}
 if($Report.Events){foreach($g in @($Report.Events.GroupedEvents | Select-Object -First 10)){$evidence.Add(@(('Event '+$g.LogName+' / '+$g.ProviderName),('ID '+$g.EventId+' x'+$g.Count),('First '+$g.FirstSeenUtc+'; last '+$g.LastSeenUtc)))}}
 if($Report.Network){foreach($a in @($Report.Network.Adapters)){$evidence.Add(@(('Adapter '+$a.Name),[string]$a.Status,[string]$a.Description))}}
 $parts.Add('<h2>Evidence</h2>'+(Table @('Item','Value','Detail') @($evidence.ToArray() | ForEach-Object {,@($_)})))
 '<!doctype html><html><head><meta charset="utf-8"><title>Windows Health Snapshot</title></head><body>'+($parts -join '')+'</body></html>'
}
function Write-HealthReport {
 param([string]$Destination,[string]$Text,[bool]$Replace)
 $encoding=[Text.UTF8Encoding]::new($false)
 if($Replace){[IO.File]::WriteAllText($Destination,$Text,$encoding);return}
 # CreateNew fails if the file appeared after validation, so nothing is overwritten without -Force.
 $stream=[IO.File]::Open($Destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write)
 try{$writer=[IO.StreamWriter]::new($stream,$encoding);try{$writer.Write($Text)}finally{$writer.Dispose()}}finally{$stream.Dispose()}
}
$outputs=@()
foreach($request in $reportRequests){
 try {
  $text=if($request.Kind -eq 'Json'){ConvertTo-Json -InputObject $result -Depth 16}else{ConvertTo-HealthHtml $result}
  Write-HealthReport $request.Path $text ([bool]$Force)
  $outputs+= [pscustomobject]@{Kind=$request.Kind;Path=$request.Path;Status='Written';Error=$null}
 } catch {
  Write-Warning ("Report not written ("+$request.Kind+"): "+$_.Exception.Message)
  $outputs+= [pscustomobject]@{Kind=$request.Kind;Path=$request.Path;Status='Failed';Error=$_.Exception.Message}
 }
}
$result.ReportOutputs=$outputs
$result
}
