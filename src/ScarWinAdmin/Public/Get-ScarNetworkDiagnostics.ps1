function Get-ScarNetworkDiagnostics {
<#
.SYNOPSIS
Collects local Windows network inventory and optional, explicit DNS/TCP probes.
#>
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
if($env:OS -ne 'Windows_NT'){throw 'This command requires Windows.'}
if($TcpTarget.Count -ne $TcpPort.Count){throw 'TcpTarget and TcpPort must contain the same number of entries.'}
if($DnsTarget.Count -gt 20 -or $TcpTarget.Count -gt 20){throw 'At most 20 DNS targets and 20 TCP targets are supported.'}
foreach($target in @($DnsTarget)+@($TcpTarget)){
 if([string]::IsNullOrWhiteSpace($target) -or $target -match '[\s/*?]' -or $target -match '://' -or $target -match '^\[' -or $target -match '/\d+$'){throw "Invalid single-host target: $target"}
}
$timer=[Diagnostics.Stopwatch]::StartNew()
$errors=New-Object 'System.Collections.Generic.List[object]'
$checks=New-Object 'System.Collections.Generic.List[object]'
$adapters=@();$routes=@();$dns=@();$tcp=@();$proxy=[pscustomobject]@{Source='WinHTTP';Settings=$null;Status='Skipped'}
$timedOut=$false
function Add-ScarNetworkCheck {
 param([string]$Name,[string]$Status,[string]$ErrorText,[object]$Evidence)
 $checks.Add([pscustomobject]@{Source=$Name;Status=$Status;EndedAtUtc=[datetime]::UtcNow.ToString('o');Evidence=$Evidence;Error=$ErrorText})
 if($Status -in @('Unavailable','TimedOut')){$errors.Add([pscustomobject]@{Stage=$Name;Error=$ErrorText})}
}
try {
 $adapters=@(Get-NetAdapter -ErrorAction Stop | ForEach-Object {
  [pscustomobject]@{Name=$_.Name;Description=$_.InterfaceDescription;InterfaceIndex=$_.ifIndex;Status=[string]$_.Status;MacAddress=$_.MacAddress}
 })
 Add-ScarNetworkCheck 'Adapters' 'Passed' $null $adapters.Count
} catch {Add-ScarNetworkCheck 'Adapters' 'Unavailable' $_.Exception.Message $null}
try {
 $ipconfig=@(Get-NetIPConfiguration -ErrorAction Stop)
 foreach($adapter in $adapters){
  $config=@($ipconfig | Where-Object InterfaceIndex -eq $adapter.InterfaceIndex | Select-Object -First 1)
  $adapter | Add-Member -NotePropertyName IPv4Addresses -NotePropertyValue @($config | ForEach-Object {$_.IPv4Address | ForEach-Object IPAddress}) -Force
  $adapter | Add-Member -NotePropertyName IPv6Addresses -NotePropertyValue @($config | ForEach-Object {$_.IPv6Address | ForEach-Object IPAddress}) -Force
  $adapter | Add-Member -NotePropertyName DnsServers -NotePropertyValue @($config | ForEach-Object {$_.DNSServer.ServerAddresses}) -Force
  $adapter | Add-Member -NotePropertyName IPv4Gateway -NotePropertyValue @($config | ForEach-Object {$_.IPv4DefaultGateway.NextHop}) -Force
 }
 Add-ScarNetworkCheck 'IPConfiguration' 'Passed' $null $ipconfig.Count
} catch {Add-ScarNetworkCheck 'IPConfiguration' 'Unavailable' $_.Exception.Message $null}
if(-not $SkipRoutes) {
 try {
  $routes=@(Get-NetRoute -ErrorAction Stop | Where-Object {$_.DestinationPrefix -eq '0.0.0.0/0' -or ($IncludeIPv6 -and $_.DestinationPrefix -eq '::/0')} | ForEach-Object {
   [pscustomobject]@{DestinationPrefix=$_.DestinationPrefix;NextHop=$_.NextHop;InterfaceIndex=$_.InterfaceIndex;RouteMetric=$_.RouteMetric;AddressFamily=[string]$_.AddressFamily}
  })
  Add-ScarNetworkCheck 'Routes' 'Passed' $null $routes.Count
 } catch {Add-ScarNetworkCheck 'Routes' 'Unavailable' $_.Exception.Message $null}
} else {Add-ScarNetworkCheck 'Routes' 'Skipped' $null $null}
if(-not $SkipProxy){
 try {
  $output=@(& netsh winhttp show proxy 2>&1)
  if($LASTEXITCODE -ne 0){throw "netsh returned exit code $LASTEXITCODE"}
  $proxy=[pscustomobject]@{Source='WinHTTP';Settings=($output -join [Environment]::NewLine);Status='Collected'}
  Add-ScarNetworkCheck 'Proxy' 'Passed' $null $null
 } catch {
  $proxy=[pscustomobject]@{Source='WinHTTP';Settings=$null;Status='Unavailable'}
  Add-ScarNetworkCheck 'Proxy' 'Unavailable' $_.Exception.Message $null
 }
}
foreach($target in $DnsTarget){
 if($timer.Elapsed.TotalSeconds -ge $TimeoutSeconds){$timedOut=$true;break}
 $started=[Diagnostics.Stopwatch]::StartNew()
 try {
  $addresses=@([Net.Dns]::GetHostAddresses($target) | ForEach-Object IPAddressToString)
  $dns+= [pscustomobject]@{Target=$target;Status='Passed';Answers=$addresses;ElapsedMs=$started.ElapsedMilliseconds;Error=$null}
  Add-ScarNetworkCheck 'DNS' 'Passed' $null $target
 } catch {
  $dns+= [pscustomobject]@{Target=$target;Status='Failed';Answers=@();ElapsedMs=$started.ElapsedMilliseconds;Error=$_.Exception.Message}
  Add-ScarNetworkCheck 'DNS' 'Failed' $_.Exception.Message $target
 }
}
for($i=0;$i -lt $TcpTarget.Count;$i++){
 if($timer.Elapsed.TotalSeconds -ge $TimeoutSeconds){$timedOut=$true;break}
 $client=New-Object Net.Sockets.TcpClient
 $started=[Diagnostics.Stopwatch]::StartNew()
 $status='Failed';$errorText=$null
 try{
  $remaining=[math]::Max(1,[math]::Min($PerTestTimeoutSeconds*1000,[int](($TimeoutSeconds-$timer.Elapsed.TotalSeconds)*1000)))
  $task=$client.ConnectAsync($TcpTarget[$i],$TcpPort[$i])
  if(-not $task.Wait($remaining)){$status='TimedOut';$errorText='Connection deadline exceeded.'}
  elseif($client.Connected){$status='Passed'}
  else{$errorText='Connection not established.'}
 }catch{$errorText=$_.Exception.Message}
 finally{$client.Dispose()}
 $tcp+= [pscustomobject]@{Target=$TcpTarget[$i];Port=$TcpPort[$i];Status=$status;ElapsedMs=$started.ElapsedMilliseconds;Error=$errorText}
 Add-ScarNetworkCheck 'TCP' $status $errorText ($TcpTarget[$i]+':'+$TcpPort[$i])
}
if($timedOut){Add-ScarNetworkCheck 'Budget' 'TimedOut' 'Overall time budget exhausted; some tests were not attempted.' $null}
$partial=$timedOut -or @($checks | Where-Object {$_.Status -in @('Unavailable','TimedOut')}).Count -gt 0
[pscustomobject]@{
 PSTypeName='ScarWinAdmin.NetworkDiagnosticsResult';SchemaVersion='1.0';Tool='ScarWinAdmin.NetworkDiagnostics'
 ComputerName=$env:COMPUTERNAME;CollectedAtUtc=[datetime]::UtcNow.ToString('o')
 CollectionStatus=$(if($partial){'Partial'}else{'Complete'});TimedOut=$timedOut
 Adapters=@($adapters);DefaultRoutes=@($routes);DnsTests=@($dns);TcpTests=@($tcp)
 Proxy=$proxy;Checks=$checks.ToArray();Findings=@();CollectionErrors=$errors.ToArray()
}
}
