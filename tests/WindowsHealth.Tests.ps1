BeforeAll { Import-Module (Join-Path $PSScriptRoot '../src/ScarWinAdmin/ScarWinAdmin.psd1') -Force }

Describe 'Windows Health Snapshot validation' {
 It 'exports the health command' {
  (Get-Command Get-ScarWindowsHealth).Name | Should -Be 'Get-ScarWindowsHealth'
 }
 It 'rejects inverted thresholds before collection' {
  {Get-ScarWindowsHealth -CriticalDiskFreePercent 50 -WarningDiskFreePercent 20} | Should -Throw
  {Get-ScarWindowsHealth -CriticalMemoryUsedPercent 80 -WarningMemoryUsedPercent 95} | Should -Throw
 }
 It 'rejects wildcard, blank and excessive service names before collection' {
  {Get-ScarWindowsHealth -ServiceName 'Spool*'} | Should -Throw
  {Get-ScarWindowsHealth -ServiceName ' '} | Should -Throw
  {Get-ScarWindowsHealth -ServiceName (1..31 | ForEach-Object {"svc$_"})} | Should -Throw
 }
 It 'rejects a missing output directory and identical report paths before collection on Windows' -Skip:($env:OS -ne 'Windows_NT') {
  {Get-ScarWindowsHealth -OutputJsonPath (Join-Path $TestDrive 'nope/health.json')} | Should -Throw '*directory does not exist*'
  $same=Join-Path $TestDrive 'same.out'
  {Get-ScarWindowsHealth -OutputJsonPath $same -OutputHtmlPath $same} | Should -Throw '*must differ*'
 }
 It 'rejects existing report paths without Force on Windows' -Skip:($env:OS -ne 'Windows_NT') {
  $path=Join-Path $TestDrive 'existing.json'
  Set-Content -LiteralPath $path -Value 'existing'
  {Get-ScarWindowsHealth -OutputJsonPath $path} | Should -Throw
  Get-Content -LiteralPath $path -Raw | Should -Match 'existing'
 }
}

Describe 'Windows Health Snapshot collection' -Skip:($env:OS -ne 'Windows_NT') {
 BeforeEach {
  Mock -ModuleName ScarWinAdmin Get-CimInstance {
   if($ClassName -eq 'Win32_OperatingSystem') {
    return [pscustomobject]@{Caption='Windows';Version='10';BuildNumber='1';LastBootUpTime=[datetime]::Now.AddHours(-8);FreePhysicalMemory=500000}
   }
   if($ClassName -eq 'Win32_ComputerSystem') {
    return [pscustomobject]@{TotalPhysicalMemory=1000000000;Manufacturer='Test';Model='Machine'}
   }
   return [pscustomobject]@{LoadPercentage=5}
  }
  Mock -ModuleName ScarWinAdmin Get-ScarDiskUsage {
   [pscustomobject]@{CollectionStatus='Complete';CollectionErrors=@();Volumes=@([pscustomobject]@{Drive='C:';SizeBytes=100;FreeBytes=60;FreePercent=60;Severity='Informational'})}
  }
  Mock -ModuleName ScarWinAdmin Test-ScarPendingReboot {[pscustomobject]@{Status='NotDetected';Indicators=@([pscustomobject]@{Name='CBS.RebootPending';Status='NotDetected';Error=$null})}}
  Mock -ModuleName ScarWinAdmin Get-ScarEventSummary {[pscustomobject]@{CollectionStatus='Complete';CollectionErrors=@();GroupedEvents=@()}}
  Mock -ModuleName ScarWinAdmin Get-ScarNetworkDiagnostics {throw 'Network should not run'}
 }
 It 'reports NoFindings with Complete coverage and does not run network or write files by default' {
  $result=Get-ScarWindowsHealth
  $result.CollectionStatus | Should -Be 'Complete'
  $result.HealthStatus | Should -Be 'NoFindings'
  $result.Findings.Count | Should -Be 0
  $result.ReportOutputs.Count | Should -Be 0
  ($result.SourceStatus | Where-Object Source -eq 'Network').Status | Should -Be 'Skipped'
  Should -Invoke Get-ScarNetworkDiagnostics -ModuleName ScarWinAdmin -Exactly -Times 0
 }
 It 'propagates partial child coverage and keeps critical findings visible' {
  Mock -ModuleName ScarWinAdmin Get-ScarDiskUsage {
   [pscustomobject]@{CollectionStatus='Partial';CollectionErrors=@('Volume inventory: denied');Volumes=@([pscustomobject]@{Drive='C:';FreePercent=4;Severity='Critical'})}
  }
  Mock -ModuleName ScarWinAdmin Test-ScarPendingReboot {[pscustomobject]@{Status='Indeterminate';Indicators=@()}}
  $result=Get-ScarWindowsHealth
  $result.CollectionStatus | Should -Be 'Partial'
  $result.HealthStatus | Should -Be 'Critical'
  ($result.SourceStatus | Where-Object Source -eq 'Disk').Error | Should -Match 'denied'
  $result.CollectionErrors.Count | Should -BeGreaterThan 1
 }
 It 'orders multiple findings deterministically by severity, source and id' {
  Mock -ModuleName ScarWinAdmin Get-ScarDiskUsage {
   [pscustomobject]@{CollectionStatus='Complete';CollectionErrors=@();Volumes=@(
    [pscustomobject]@{Drive='E:';FreePercent=15;Severity='Warning'}
    [pscustomobject]@{Drive='D:';FreePercent=3;Severity='Critical'}
    [pscustomobject]@{Drive='C:';FreePercent=60;Severity='Informational'}
    [pscustomobject]@{Drive='F:';FreePercent=2;Severity='Critical'})}
  }
  $result=Get-ScarWindowsHealth
  @($result.Findings).Count | Should -Be 3
  ($result.Findings | ForEach-Object FindingId) -join ',' | Should -Be 'disk.D:,disk.F:,disk.E:'
  $result.HealthStatus | Should -Be 'Critical'
 }
 It 'does not turn missing CPU or memory measurements into zero' {
  Mock -ModuleName ScarWinAdmin Get-CimInstance {
   if($ClassName -eq 'Win32_OperatingSystem') {return [pscustomobject]@{Caption='Windows';Version='10';BuildNumber='1';LastBootUpTime=[datetime]::Now.AddHours(-1);FreePhysicalMemory=$null}}
   if($ClassName -eq 'Win32_ComputerSystem') {return [pscustomobject]@{TotalPhysicalMemory=1000000000;Manufacturer='T';Model='M'}}
   return [pscustomobject]@{LoadPercentage=$null}
  }
  $result=Get-ScarWindowsHealth
  ($result.SourceStatus | Where-Object Source -eq 'Memory').Status | Should -Be 'Unavailable'
  ($result.SourceStatus | Where-Object Source -eq 'Cpu').Status | Should -Be 'Unavailable'
  $result.Memory | Should -BeNullOrEmpty
  $result.Cpu | Should -BeNullOrEmpty
  $result.Findings.Count | Should -Be 0
  $result.HealthStatus | Should -Be 'Unknown'
 }
 It 'keeps a pending reboot finding but marks coverage partial when another indicator is indeterminate' {
  Mock -ModuleName ScarWinAdmin Test-ScarPendingReboot {
   [pscustomobject]@{Status='Pending';Indicators=@(
    [pscustomobject]@{Name='CBS.RebootPending';Status='Detected';Error=$null}
    [pscustomobject]@{Name='ComputerRename.Pending';Status='Indeterminate';Error='Access denied'})}
  }
  $result=Get-ScarWindowsHealth
  ($result.SourceStatus | Where-Object Source -eq 'Reboot').Status | Should -Be 'Partial'
  ($result.CollectionErrors | Where-Object Source -eq 'Reboot').Message | Should -Match 'Access denied'
  ($result.Findings | ForEach-Object FindingId) | Should -Contain 'reboot.pending'
  ($result.Findings | ForEach-Object FindingId) | Should -Contain 'reboot.indeterminate'
  $result.HealthStatus | Should -Be 'Warning'
 }
 It 'distinguishes running, missing and failing services and runs the network inventory only when asked' {
  Mock -ModuleName ScarWinAdmin Get-Service {
   if($Name -eq 'Present'){return [pscustomobject]@{Status='Running';DisplayName='Present service'}}
   if($Name -eq 'Missing'){
    $record=[Management.Automation.ErrorRecord]::new([Exception]::new('not found'),'NoServiceFoundForGivenName,Microsoft.PowerShell.Commands.GetServiceCommand',[Management.Automation.ErrorCategory]::ObjectNotFound,$Name)
    throw $record
   }
   throw 'Access is denied'
  }
  Mock -ModuleName ScarWinAdmin Get-ScarNetworkDiagnostics {[pscustomobject]@{CollectionStatus='Complete';CollectionErrors=@();Adapters=@()}}
  $result=Get-ScarWindowsHealth -ServiceName 'Present','Missing','Denied' -IncludeNetwork
  ($result.Services | Where-Object Name -eq 'Present').Status | Should -Be 'Running'
  ($result.Services | Where-Object Name -eq 'Denied').Status | Should -Be 'Unavailable'
  ($result.SourceStatus | Where-Object Source -eq 'Services').Status | Should -Be 'Partial'
  ($result.SourceStatus | Where-Object Source -eq 'Network').Status | Should -Be 'Complete'
  Should -Invoke Get-ScarNetworkDiagnostics -ModuleName ScarWinAdmin -Exactly -Times 1
 }
 It 'stops service lookups once the time budget is exhausted and reports the rest as skipped' {
  Mock -ModuleName ScarWinAdmin Get-Service { Start-Sleep -Seconds 6; [pscustomobject]@{Status='Running';DisplayName='Slow'} }
  $result=Get-ScarWindowsHealth -ServiceName 'A','B','C' -TimeoutSeconds 10
  Should -Invoke Get-Service -ModuleName ScarWinAdmin -Exactly -Times 2
  ($result.Services | Where-Object Name -eq 'C').Status | Should -Be 'Skipped'
  $result.TimedOut | Should -BeTrue
  $result.CollectionStatus | Should -Be 'Partial'
  $result.HealthStatus | Should -Not -Be 'NoFindings'
 }
 It 'round-trips JSON with single-element arrays and keeps write outcomes off the evidence status' {
  $json=Join-Path $TestDrive 'health.json'
  Mock -ModuleName ScarWinAdmin Get-Service { [pscustomobject]@{Status='Running';DisplayName='One'} }
  $result=Get-ScarWindowsHealth -ServiceName 'One' -OutputJsonPath $json
  $result.ReportOutputs[0].Status | Should -Be 'Written'
  $parsed=Get-Content -LiteralPath $json -Raw | ConvertFrom-Json
  $parsed.SchemaVersion | Should -Be '1.0'
  $parsed.Tool | Should -Be 'ScarWinAdmin.WindowsHealth'
  @($parsed.Services).Count | Should -Be 1
  @($parsed.SourceStatus).Count | Should -Be $result.SourceStatus.Count
  # Check the raw text: PowerShell 7 converts ISO strings to DateTime when parsing.
  Get-Content -LiteralPath $json -Raw | Should -Match '"LastBootUpTimeUtc":\s*"\d{4}-\d{2}-\d{2}T'
 }
 It 'encodes every dynamic value in the HTML report and renders coverage and evidence' {
  $html=Join-Path $TestDrive 'health.html'
  $payload='<script>alert(1)</script>'
  Mock -ModuleName ScarWinAdmin Get-Service { throw '<img src=x onerror=alert(1)>' }
  Mock -ModuleName ScarWinAdmin Get-ScarEventSummary {[pscustomobject]@{CollectionStatus='Partial';CollectionErrors=@([pscustomobject]@{LogName='System';Error='<b>denied</b>'});GroupedEvents=@()}}
  $result=Get-ScarWindowsHealth -ServiceName $payload -OutputHtmlPath $html
  $text=Get-Content -LiteralPath $html -Raw
  $text | Should -Not -Match '<script>alert'
  $text | Should -Not -Match '<img src=x'
  $text | Should -Not -Match '<b>denied'
  $text | Should -Match '&lt;script&gt;alert\(1\)&lt;/script&gt;'
  $text | Should -Match 'Source coverage'
  $text | Should -Match '&lt;b&gt;denied&lt;/b&gt;'
  $text | Should -Match 'Evidence'
  $text | Should -Not -Match '(?i)<script|https?://'
 }
 It 'replaces existing reports only with Force' {
  $path=Join-Path $TestDrive 'replace.json'
  Set-Content -LiteralPath $path -Value 'old'
  { Get-ScarWindowsHealth -OutputJsonPath $path } | Should -Throw
  $result=Get-ScarWindowsHealth -OutputJsonPath $path -Force
  $result.ReportOutputs[0].Status | Should -Be 'Written'
  Get-Content -LiteralPath $path -Raw | Should -Match 'SchemaVersion'
 }
 It 'reports a failed report write separately without changing collection status' {
  $directory=Join-Path $TestDrive 'a-directory'
  New-Item -ItemType Directory -Path $directory | Out-Null
  $json=Join-Path $TestDrive 'ok.json'
  $result=Get-ScarWindowsHealth -OutputJsonPath $json -OutputHtmlPath $directory -Force -WarningAction SilentlyContinue
  $result.CollectionStatus | Should -Be 'Complete'
  $result.CollectionErrors.Count | Should -Be 0
  ($result.ReportOutputs | Where-Object Kind -eq 'Json').Status | Should -Be 'Written'
  ($result.ReportOutputs | Where-Object Kind -eq 'Html').Status | Should -Be 'Failed'
  ($result.ReportOutputs | Where-Object Kind -eq 'Html').Error | Should -Not -BeNullOrEmpty
  ((Get-Content -LiteralPath $json -Raw | ConvertFrom-Json).CollectionStatus) | Should -Be 'Complete'
 }
}

Describe 'Windows Health standalone script parity' -Skip:($env:OS -ne 'Windows_NT') {
 BeforeAll {
  $script:outDir=Join-Path $TestDrive 'out'
  & (Join-Path $PSScriptRoot '../tooling/Build.ps1') -OutputDirectory $script:outDir | Out-Null
  $script:standalone=Join-Path $script:outDir 'scripts/health/Get-WindowsHealth.ps1'
 }
 It 'builds a standalone script with the same parameters as the module command' {
  Test-Path -LiteralPath $script:standalone | Should -BeTrue
  $common=[Management.Automation.PSCmdlet]::CommonParameters + [Management.Automation.PSCmdlet]::OptionalCommonParameters
  $moduleParams=(Get-Command Get-ScarWindowsHealth).Parameters
  $scriptParams=(Get-Command $script:standalone).Parameters
  $names={param($p) @($p.Keys | Where-Object {$_ -notin $common} | Sort-Object)}
  (& $names $scriptParams) -join ',' | Should -Be ((& $names $moduleParams) -join ',')
  foreach($name in (& $names $moduleParams)){
   $scriptParams[$name].ParameterType | Should -Be $moduleParams[$name].ParameterType
   $moduleRange=$moduleParams[$name].Attributes | Where-Object {$_ -is [System.Management.Automation.ValidateRangeAttribute]}
   $scriptRange=$scriptParams[$name].Attributes | Where-Object {$_ -is [System.Management.Automation.ValidateRangeAttribute]}
   "$($scriptRange.MinRange)-$($scriptRange.MaxRange)" | Should -Be "$($moduleRange.MinRange)-$($moduleRange.MaxRange)"
  }
 }
 It 'produces the same result shape as the module command without module installation' {
  $splat=@{EventLookbackHours=1;MaxEventsPerLog=5;TimeoutSeconds=60}
  $fromModule=Get-ScarWindowsHealth @splat
  $fromScript=& $script:standalone @splat
  (($fromScript.PSObject.Properties.Name | Sort-Object) -join ',') | Should -Be (($fromModule.PSObject.Properties.Name | Sort-Object) -join ',')
  (($fromScript.SourceStatus | ForEach-Object Source) -join ',') | Should -Be (($fromModule.SourceStatus | ForEach-Object Source) -join ',')
  $fromScript.SchemaVersion | Should -Be $fromModule.SchemaVersion
 }
}
